#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

function join() { local IFS="$1"; shift; echo "$*"; }
if [[ -n "${SDH_NAMESPACE:-}" ]]; then
    export HOME="$(mktemp -d)"    # so that oc can create $HOME/.kube/ directory
    oc project "$SDH_NAMESPACE"
else
    SDH_NAMESPACE="$(oc project -q 2>/dev/null|| :)"
fi
# support both 3.x and 4.x output formats
version="$(oc version --short 2>/dev/null || oc version)"
serverVersion="$(sed -n 's/^\(\([sS]erver\|[kK]ubernetes\).*:\|[oO]pen[sS]hift\) v\?\([0-9]\+\.[0-9]\+\).*/\3/p' \
                    <<<"$version" | head -n 1)"
clientVersion="$(sed -n 's/^\([cC]lient.*:\|oc\) \(openshift-clients-\|v\)\([0-9]\+\.[0-9]\+\).*/\3/p' \
                    <<<"$version" | head -n 1)"
# translate k8s 1.13 to ocp 4.1
if [[ "${serverVersion:-}" =~ ^1\.([0-9]+)$ && "${BASH_REMATCH[1]}" -gt 12 ]]; then
    serverVersion="4.$((${BASH_REMATCH[1]} - 12))"
fi
if [[ -z "${clientVersion:-}" ]]; then
    printf 'WARNING: Failed to determine oc client version!\n' >&2
elif [[ -z "${serverVersion}" ]]; then 
    printf 'WARNING: Failed to determine k8s server version!\n' >&2
elif [[ "${serverVersion}" != "${clientVersion}" ]]; then
    printf 'WARNING: Client version != Server version (%s != %s).\n' "$clientVersion" "$serverVersion" >&2
    printf '                 Please reinstantiate this template with the correct BASE_IMAGE_TAG parameter (e.g. v%s)."\n' >&2 \
        "$serverVersion"
else
    printf "Server and client version: $serverVersion"
fi

if [[ ! "${NODE_LOG_FORMAT:-}" =~ ^(text|json|)$ ]]; then
    printf 'WARNING: unrecognized NODE_LOG_FORMAT; "%s" is not one of "json" or "text"!' \
        "$NODE_LOG_FORMAT"
    exit 1
fi
if [[ -z "${NODE_LOG_FORMAT:-}" ]]; then
    if [[ "${serverVersion}" =~ ^3 ]]; then
        NODE_LOG_FORMAT=json
    else
        NODE_LOG_FORMAT=text
    fi
fi

function log() {
    local reenableDebug="$([[ "$-" =~ x ]] && printf '1' || printf '0')"
    { set +x; } >/dev/null 2>&1
    date -R | tr '\n' ' ' >&2
    # no new line
    if [[ "$1" == -n ]]; then
        shift
    elif [[ "${1: -1}" != $'\n' ]]; then
        local fmt="${1:-}\n"
        shift
        printf "$fmt" "$@" >&2
        return 0
    fi
    printf "$@" >&2
    [[ "${reenableDebug}" == 1 ]] && set -x
}

registry="${REGISTRY:-}"
function get_registry() {
    if [[ -z "${registry:-}" ]]; then
        registry="$(oc get secret -o go-template='{{index .data "installer-config.yaml"}}' installer-config | \
             base64 -d | sed -n 's/^\s*\(DOCKER\|VFLOW\)_REGISTRY:\s*\(...\+\)/\2/p' | \
                tr -d '"'"'" | grep -v '^[[:space:]]*$' | tail -n 1)"
    fi
    if [[ -z "${registry:-}" ]]; then
        log "Failed to determine the registry!"
        return 1
    fi
    printf '%s\n' "$registry"
}

function terminate() {
    # terminate all the process in the container once one observer dies
    kill -9 -- `ps -ahx | awk '{print $1}' | grep -v -F "$BASHPID" | tac`
}

function observe() {
    oc observe --listen-addr=:11256 pod        &
    oc observe --listen-addr=:11254 configmap  &
    oc observe --listen-addr=:11253 daemonset  &
    oc observe --listen-addr=:11252 statefulset&
    oc observe --listen-addr=:11251 deploy     &
    while true; do
        sleep 0.1
        if [[ "$(jobs -r | wc -l)" -lt 3 ]]; then
            terminate
        fi
    done
}

function evalBool() {
    local varName="$1"
    local default="${2:-}"
    eval 'local value="${'"$varName"':-}"'
    if [[ -z "${value:-}" ]]; then
        value="${default:-}"
    fi
    grep -q -i '^\s*\(y\(es\)\?\|true\|1\)\s*$' <<<"${value:-}"
}

function runOrLog() {
    if evalBool DRY_RUN; then
        echo "$@"
    else
        "$@"
    fi
}

function mkPasswdSecretKey() {
    local imgID="$1"
    local wd="${2:-}"
    local envVarHOME="${3:-}"
    printf '%s\n' "${imgID}:${wd:-}:${envVarHOME:-}"
}

function mkPasswdSecretName() {
    local key="$1"
    printf 'di-installer-job-passwd-%s\n' "$(dd if=<(sha256sum <<<"$key") of=/dev/fd/1 bs=1 count=9)"
}

function mkPasswdSecret() {
    local imgID="$1"
    local jobname="$2"
    local containerName="$3"
    local key="$4"
    local imgName wd envVarHOME
    IFS=: read -r imgName wd envVarHOME
    local data="$5"
    local secretName="$(mkPasswdSecretName "${imgID}" "${wd:-}" "${envVarHOME:-}" | tr -d '\n')"
    oc create secret generic "${secretName}" --from-literal=passwd="$data" --dry-run -o yaml | \
        oc label --local -f - -o yaml \
            job-name="$jobname" \
            container-image-id="${imgID}" \
            container-image-name="$imgName" \
            container-working-directory="${wd:-}" \
            container-home-directory="${envVarHOME:-}" | oc create -f -;
    printf '%s\n' "${secretName}"
}

# maps secretname to timestamp of the last check
declare -A secretCache=()

function doesPasswdSecretExist() {
    local key="$1"
    local secretName="$(mkPasswdSecretName "${key}")"
    if oc get secret -o name >/dev/null 2>&1 "$secretName"; then
        printf '%s\n' "$secretName"
    fi
}

function getPasswdSecretData() {
    local key="$1"
    oc get secret -o jsonpath='{.data.passwd}' "$(mkPasswdSecretName "${key}")" | base64 -d
}

gotmplarr=(
    '{{range $di, $d := .items}}'
        '{{if eq .kind "Deployment"}}'
            '{{with $appcomp := index .metadata.labels "datahub.sap.com/app-component"}}'
                '{{if eq $appcomp "vsystem-app"}}'
                    # vsystem-app deployment
                    '{{range $i, $c := $d.spec.template.spec.containers}}'
                        '{{if eq .name "vsystem-iptables"}}'
                            # print (string kind)/(string sdh-app-component):(string "ready" or "unready"):(int containerIndex):(bool unprivileged)
                            '{{$d.kind}}/{{$appcomp}}:'
                            '{{with $s := $d.status}}'
                                '{{with $s.replicas}}'
                                    '{{with $s.availableReplicas}}'
                                        '{{if and (eq $s.replicas .) (and (gt . 0.1) (eq . $s.readyReplicas))}}'
                                            'ready'
                                        '{{else}}'
                                            'unready'
                                        '{{end}}'
                                    # when .status.availableReplicas is undefined
                                    '{{else}}'
                                        'unready'
                                    '{{end}}'
                                # when .status.replicas is undefined
                                '{{else}}'
                                    'unready'
                                '{{end}}'
                            '{{end}}'
                         $':{{$i}}:{{not $c.securityContext.privileged}}\n'
                        '{{end}}'
                    '{{end}}'
                '{{else if eq $appcomp "vflow"}}'
                    # print (string kind)/(string name):(string version):(bool unprivileged):[(string docker-socket-volume-mount-name):(string seLinuxtype)]
                    '{{$d.kind}}/{{$appcomp}}:'
                    '{{index $d.metadata.labels "datahub.sap.com/package-version"}}:'
                    '{{with $spec := $d.spec.template.spec}}'
                        '{{not (index $spec.containers 0).securityContext.privileged}}:'
                        '{{range $i, $vol := $spec.volumes}}'
                            '{{with $path := $vol.hostPath.path}}'
                                '{{if eq $path "/var/run/docker.sock"}}'
                                    '{{$vol.name}}:'
                                    '{{with $t := $spec.securityContext.seLinuxOptions.type}}{{$t}}{{end}}'
                                '{{end}}'
                            '{{end}}'
                        '{{end}}'
                    '{{end}}'
                 $'\n'
                '{{end}}'
            '{{end}}'

        '{{else if eq .kind "DaemonSet"}}'
            '{{if eq .metadata.name "diagnostics-fluentd"}}'
                # print (string kind):(int containerIndex):(string containerName):(bool unprivileged)
                #            :(int volumeindex):(string varlibdockercontainers volumehostpath)
                #            :(int volumeMount index):(string varlibdockercontainers volumeMount path)
                '{{.kind}}'
                '{{range $i, $c := $d.spec.template.spec.containers}}'
                    '{{if eq $c.name "diagnostics-fluentd"}}'
                        ':{{$i}}:{{$c.name}}:{{not $c.securityContext.privileged}}'
                        '{{range $j, $v := $d.spec.template.spec.volumes}}'
                            '{{if eq $v.name "varlibdockercontainers"}}'
                                ':{{$j}}:{{$v.hostPath.path}}'
                            '{{end}}'
                        '{{end}}'
                        '{{range $j, $vm := $c.volumeMounts}}'
                            '{{if eq $vm.name "varlibdockercontainers"}}'
                                ':{{$j}}:{{$vm.mountPath}}'
                            '{{end}}'
                        '{{end}}'
                    '{{end}}'
                '{{end}}'
             $'\n'
            '{{end}}'

        '{{else if eq .kind "Pod"}}'
            # print (string kind)/(string name)#(string ownerKind)/(string ownerName)#
            #             ((int containerIndex),(string containerName),(string image),(string imageID):(string workingDir):(string envVarHOME),
            #                ((string volumeMountName),)+#)+
            '{{if eq .status.phase "Running"}}'
                '{{with $or := (index .metadata.ownerReferences 0)}}'
                    '{{if $or.kind == "Job"}}'
                        '{{.kind}}/{{.metadata.name}}#{{$or.kind}}/${$or.name}}#'
                        '{{range $i, $c := $d.spec.containers}}'
                            '{{$i}},{{$c.name}},{{$c.image}},'
                            '{{with $status := (index $d.status.containerStatuses $i)}}'
                                '{{$status.imageID}}'
                            '{{end}}:'
                            '{{$c.workingDir}}:'
                            '{{range $_, $e := $c.env}}'
                                '{{if eq $e.name "HOME"}}'
                                    '{{with $v := $e.value}}$v{{end}}'
                                '{{end}}'
                            '{{end}}'
                            ','
                            '{{range $j, $vm := $c.volumeMounts}}'
                                '{{if eq $vm.mountPath "/etc/passwd"}}'
                                    '{{$vm.name}},'
                                '{{end}}'
                            '{{end}}'
                            '#'
                        '{{end}}'
                        $'\n'
                    '{{end}}'
                '{{end}}'
            '{{end}}'

        '{{else if eq .kind "ConfigMap"}}'
            '{{if eq .metadata.name "diagnostics-fluentd-settings"}}'
                # print (string kind)/(string name)
                $'{{.kind}}/{{.metadata.name}}\n'
            '{{end}}'

        '{{else}}'
            # vsystem-vrep statefulset
            '{{if eq .metadata.name "vsystem-vrep"}}'
                # print (string kind):(int containerIndex):(string volumeMountName)
                '{{.kind}}'
                '{{range $i, $c := $d.spec.template.spec.containers}}'
                    '{{if eq $c.name "vsystem-vrep"}}'
                        ':{{$i}}'
                        '{{range $vmi, $vm := $c.volumeMounts}}'
                            '{{if eq $vm.mountPath "/exports"}}'
                                ':{{$vm.name}}'
                            '{{end}}'
                        '{{end}}'
                    '{{end}}'
                '{{end}}'
             $'\n'
            '{{end}}'
        '{{end}}'
    '{{end}}'
)

lackingPermissions=0
for perm in get/nodes get/projects get/secrets get/configmaps \
                    watch/pods \
                    watch/deployments get/deployments watch/statefulsets get/statefulsets watch/configmaps \
                    patch/deployments patch/statefulsets patch/daemonsets patch/configmaps \
                    update/daemonsets delete/pods;
do
    if ! oc auth can-i "${perm%%/*}" "${perm##*/}" >/dev/null; then
        log -n 'Cannot "%s" "%s", please grant the needed permissions' "${perm%%/*}" "${perm##*/}"
        log ' to sdh-observer service account!'
        lackingPermissions=1
    fi
done
[[ "${lackingPermissions:-0}" == 1 ]] && terminate
if [[ -n "${SDH_NAMESPACE:-}" ]]; then
    log 'Watching namespace "%s" for vsystem-apps deployments...' "$SDH_NAMESPACE"
fi

# delete obsolete deploymentconfigs
( oc get -o name {deploymentconfig,serviceaccount,role}/{vflow,vsystem,sdh}-observer 2>/dev/null;
    oc get -o name rolebinding -l deploymentconfig=vflow-observer 2>/dev/null;
    oc get -o name rolebinding -l deploymentconfig=vsystem-observer 2>/dev/null;
    oc get -o name rolebinding -l deploymentconfig=sdh-observer 2>/dev/null; ) | \
        xargs -r oc delete || :

gotmpl="$(printf '%s' "${gotmplarr[@]}")"
gotmplvflow=$'{{range $index, $arg := (index (index .spec.template.spec.containers 0) "args")}}{{$arg}}\n{{end}}'
mkiptabsprivileged=0
if evalBool "MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED"; then
    mkiptabsprivileged=1
fi

while IFS=' ' read -u 4 -r _ _ _ _ _ name; do
    [[ -z "${name:-}" ]] && continue
    while IFS=: read -u 3 -r resource rest; do
        if [[ "${serverVersion}" =~ ^3\. && "$mkiptabsprivileged/${resource,,}" =~ ^0/(deployment/vsystem-app|statefulset) ]]; then
            resource="${resource%%/*}"
            log 'No need to patch vsystem pods on OpenShift %s, skipping %s/%s...' "${serverVersion}" "${resource,,}" "$name"
            continue
        fi
        case "${resource,,}" in
        deployment/vsystem-app)
            if [[ "${mkiptabsprivileged}" == 0 ]]; then
                continue
            fi
            IFS=: read -r ready index unprivileged <<<"${rest:-}"
            if [[ "$unprivileged" == "true" ]]; then
                log 'Patching container #%d in deployment/%s to make its pods privileged ...' \
                        "$index" "$name" >&2
                runOrLog oc patch "deploy/$name" --type json -p '[{
                    "op": "add",
                    "path": "/spec/template/spec/containers/'"$index"'/securityContext/privileged",
                    "value": true
                }]'
            else
                log 'Container #%d in deployment/%s already patched, skipping ...' "$index" "$name"
            fi
            ;;

        deployment/vflow)
            patches=()
            IFS=: read -r pkgversion unprivileged volName seType <<<"${rest:-}"
            pkgversion="${pkgversion#v}"
            pkgmajor="${pkgversion%%.*}"
            pkgminor="${pkgversion#*.}"
            pkgminor="${pkgminor%%.*}"

            # -insecure-registry flag is supported starting from 2.5; earlier releases need no patching
            if evalBool MARK_REGISTRY_INSECURE && [[ -n "$(get_registry)" ]] && [[ "${pkgmajor:-0}" == 2 && "${pkgminor:-0}" -ge 5 ]]; then
                registry="$(get_registry)"
                readarray -t vflowargs <<<"$(oc get deploy -o go-template="${gotmplvflow}" "$name")"
                if ! grep -q -F -- "-insecure-registry=${registry}" <<<"${vflowargs[@]}"; then
                    vflowargs+=( "-insecure-registry=${registry}" )
                    newargs=( )
                    for ((i=0; i<"${#vflowargs[@]}"; i++)) do
                        # escape double qoutes of each argument and surround it with double quotes
                        newargs+=( '"'"$(sed 's/"/\\"/g' <<<"${vflowargs[$i]}")"'"' )
                    done
                    # turn the argument array into a json list of strings
                    newarglist="[$(join , "${newargs[@]}")]"
                    log 'Patching deployment/%s to treat %s registry as insecure ...' "$name" "$registry"
                    patches+=( '{"op":"add","path":"/spec/template/spec/containers/0/args","value":'"$newarglist"'}' )
                else
                    log 'deployment/%s already patched to treat %s registry as insecure, not patching ...' "$name" "$registry"
                fi
            fi

            if [[ -n "${volName:-}" ]]; then
                if [[ "${pkgmajor:-0}" == 2 && "${pkgminor:-0}" -ge 5 ]]; then
                    if [[ "${seType:-}" != "spc_t" ]]; then
                        log 'Patching deployment/%s to run as spc_t SELinux type ...' "$name"
                        patches+=( "$(join , \
                                                '{"op":"add"' \
                                                 '"path":"/spec/template/spec/securityContext"' \
                                                 '"value":{"seLinuxOptions":{"type":"spc_t"}}}' )" )
                    else
                        log 'deployment/%s already patched to run as spc_t type, not patching ...' "$name"
                    fi
                else
                    # SDH 2.4 fails to run as spc_t on top of NFS - therefor privileged
                    if [[ "${unprivileged:-true}" != "false" ]]; then
                        log 'Patching deployment/%s to run as privileged ...' "$name"
                        patches+=( '{"op": "add"' \
                                                '"path": "/spec/template/spec/containers/0/securityContext"' \
                                                '"value": {"privileged": true}}' )
                    else
                        log 'deployment/%s already patched to run as privileged type, not patching ...' "$name"
                    fi
                fi
            fi

            [[ "${#patches[@]}" == 0 ]] && continue
            runOrLog oc patch --type json -p "[$(join , "${patches[@]}")]" deploy "$name"
            ;;

        configmap/diagnostics-fluentd-settings)
            contents="$(oc get "${resource,,}" -o go-template='{{index .data "fluent.conf"}}')"
            if [[ -z "${contents:-}" ]]; then
                log "Failed to get contents of fluent.conf configuration file!"
                continue
            fi
            currentLogParseType="$(sed -n '/<parse>/,/<\/parse>/s,^\s\+@type\s*\([^[:space:]]\+\).*,\1,p' <<<"${contents}")"
            if [[ -z "${currentLogParseType:-}" ]]; then
                log "Failed to determine the current log type parsing of fluentd pods!"
                continue
            fi
            case "${currentLogParseType}" in
            "multi_format") continue; ;; # shall support both json and text 
            "json")
                if [[ "$NODE_LOG_FORMAT" == json ]]; then
                    log "Fluentd pods are already configured to parse json, not patching..."
                    continue
                fi
                ;;
            "regexp")
                if [[ "$NODE_LOG_FORMAT" == text ]]; then
                    log "Fluentd pods are already configured to parse text, not patching..."
                    continue
                fi
                ;;
            esac
            exprs=(
                -e '/^\s\+expression\s\+\/\^.*logtag/d'
            )
            if [[ "$NODE_LOG_FORMAT" == text ]]; then
                exprs+=(
                            -e '/<parse>/,/<\/parse>/s,@type.*,@type regexp,'
                            -e '/<parse>/,/<\/parse>/s,\(\s*\)@type.*,\0\n\1expression /^(?<time>.+) (?<stream>stdout|stderr)( (?<logtag>.))? (?<log>.*)$/,'
                            -e "/<parse>/,/<\/parse>/s,time_format.*,time_format '%Y-%m-%dT%H:%M:%S.%N%:z',"
                )
            else
                exprs+=(
                    -e '/<parse>/,/<\/parse>/s,@type.*,@type json,'
                    -e "/<parse>/,/<\/parse>/s,time_format.*,time_format '%Y-%m-%dT%H:%M:%S.%NZ',"
                )
            fi
            newContents="$(printf '%s\n' "${contents}" | sed "${exprs[@]}")"
            log 'Patching configmap %s to support %s logging format on OCP 4...' "$name" "$NODE_LOG_FORMAT"
            yamlPatch="$(printf '%s\n' "data:" "    fluent.conf: |" "$(sed 's/^/        /' <<<"${newContents}")")"
            runOrLog oc patch "${resource,,}" -p "$yamlPatch"
            readarray -t pods <<<"$(oc get pods -l datahub.sap.com/app-component=fluentd -o name)"
            [[ "${#pods[@]}" == 0 ]] && continue
            log 'Restarting fluentd pods ...'
            runOrLog oc delete --force --grace-period=0 "${pods[@]}"
            ;;

        daemonset)
            IFS=: read -r index cname unprivileged volumeIndex hostPath volumeMountIndex mountPath <<<"${rest:-}"
            name="diagnostics-fluentd"
            patches=()
            patchTypes=()
            if [[ "$unprivileged" == "true" ]]; then
                log 'Patching container #%d in daemonset/%s to make its pods privileged ...' \
                        "$index" "$name"
                        patches+=( "$(join ' ' '{"spec":{"template":{"spec":{"containers":' \
                                                    '[{"name":"diagnostics-fluentd", "securityContext":{"privileged": true}}]}}}}')"
                        )
                        patchTypes+=( strategic )
            else
                log 'Container #%d in daemonset/%s already patched, skipping ...' "$index" "$name"
            fi
            if [[ -n "${hostPath:-}" && "${hostPath}" != "/var/lib/docker" ]]; then
                log 'Patching container #%d in daemonset/%s to mount /var/lib/docker instead of %s' \
                        "$index" "$name" "$hostPath"
                patches+=( "$(join ' ' '[{"op": "replace", "path":' \
                                    '"/spec/template/spec/containers/'"$index/volumeMounts/$volumeMountIndex"'",' \
                                    '"value": {"name":"varlibdockercontainers","mountPath":"/var/lib/docker","readOnly": true}}]' )"
                )
                patchTypes+=( json )
                patches+=( "$(join ' ' '{"spec":{"template":{"spec":' \
                                '{"volumes":[{"name": "varlibdockercontainers", "hostPath":' \
                                    '{"path": "/var/lib/docker", "type":""}}]}}}}' )"
                )
                patchTypes+=( strategic )
            elif [[ -z "${hostPath:-}" ]]; then
                log 'Failed to determine hostPath for varlibcontainers volume!'
            else
                log 'Daemonset/%s already patched to mount /var/lib/docker, skipping ...' "$name"
            fi

            [[ "${#patches[@]}" == 0 ]] && continue
            dsSpec="$(oc get -o json daemonset/"$name")"
            for ((i=0; i < "${#patches[@]}"; i++)); do
                patch="${patches[$i]}"
                patchType="${patchTypes[$i]}"
                dsSpec="$(oc patch -o json --local -f - --type "$patchType" -p "${patch}" <<<"${dsSpec}")"
            done
            oc replace -f - <<<"${dsSpec}"
            ;;

        statefulset)
            IFS=: read -r index ready <<<"${rest:-}"
            if [[ -n "${index:-}" && -n "${ready:-}" ]]; then
                log 'statefulset/vsystem-vrep already patched, skipping ...'
            else
                log 'Adding emptyDir volume to statefulset/vsystem-vrep ...'
                runOrLog oc patch "statefulset/vsystem-vrep" --type json -p '[{
                    "op": "add",
                    "path": "/spec/template/spec/containers/'"$index"'/volumeMounts/0",
                    "value": {"mountPath": "/exports", "name": "exports-volume"}
                }, {
                    "op": "add",
                    "path": "/spec/template/spec/volumes/0",
                    "value": {"emptyDir": {}, "name": "exports-volume"}
                }]'
            fi
            ;;

        pod/*)
            log 'Debugging pod %s' "$name"
            set -x
            declare -A toPatch=()
            declare -A secretsToAdd=()
            readrray -t -d '#' ownerReference containerInfos <<<"${rest:-}"
            jobName="${ownerReference##*/}"
            for ci in "${containerInfos[@]}"; do
                IFS=',' read -r cindex cname cimage csecretKey volumeMounts <<<"${ci:-}"
                if [[ -z "${cimage:-}" || -z "${cname:-}" || -z "${secretkey:-}" ]]; then
                    continue
                fi
                [[ "${cimage}" =~ /di-releasepack-installer[@:] ]] || continue

                readarray -t -d , vms <<<"${volumeMounts:-}"
                if [[ "${#volumes[@]}" == 0 ]]; then
                    continue
                fi
                for vm in "${vms[@]}"; do
                        [[ -z "${vm:-}" ]] && continue
                        # if /etc/passwd secret is mounted already, no need to patch the pod again
                        continue 2
                done

                secretName="$(doesPasswdSecretExist "${csecretKey}")"
                if [[ -z "${secretName:-}" ]]; then
                    rawData="$(oc rsh -c "${cname}" "${name}" /bin/sh -c 'whoami; echo $HOME; cat /etc/passwd')"
                    if [[ -z "${rawData:-}" ]]; then
                        log 'Could not read /etc/passwd file in container %s in pod %s' "${cname}" "${name}"
                        continue
                    fi
                    username="$(head -n 1      <<<"$rawData")"
                    homeDir="$(sed   -n '2p'   <<<"$rawData")"
                    data="$(sed      -n '3,$p' <<<"$rawData")"
                    secretName="$(mkPasswdSecret "$imageID" "$jobName" "$cname" "${csecretKey}" "${data:-}")"
                    if [[ -z "${secretName:-}" ]]; then
                        log 'Could not create secret for container %s of job %s with key %s!' "${cname}" "${jobName}"
                        continue
                    fi
                fi
            done

            if [[ "${#toPatch[@]}" -lt 1 ]]; then
                log 'no container to patch';
                set +x
                break
            fi

            patches=( "$(join ' ' '{"spec":{"template":{"spec":' \
                                    '{"volumes":[{"name": "etc-passwd-secret", "secret":' \
                                    '{"secretName": "/var/lib/docker", "type":""}}]}}}}' )")
            for item in "${toPatch[@]}"; do
                IFS=# read -r jobname cindex cname <<<"$item"
                patches+=( "$(join ',' '{"op": "add"' \
                                        '"path": "/spec/template/spec/containers/'"$cindex"'/volumeMounts/0"' \
                                        '"value": {"name": "etc-passwd-secret"'
                                                  '"mountPath": "/etc/passwd"'
                                                  '"subPath":"passwd"'
                                                  '"readOnly": true}}' )" )
            done
            runOrLog oc patch --type json -p "[$(join , "${patches[@]}")]" job "$jobName"
            log 'ended processing of pod'
            set +x
            ;;

        esac
    done 3< <(oc get deploy/"$name" statefulset/"$name" daemonset/"$name" \
                configmap/"$name" -o go-template="${gotmpl}" 2>/dev/null ||: )
done 4< <(observe)

#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

for d in "$(dirname "${BASH_SOURCE[0]}")" . /usr/local/share/sdi; do
    if [[ -e "$d/lib/common.sh" ]]; then
        eval "source '$d/lib/common.sh'"
    fi
done
if [[ "${_SDI_LIB_SOURCED:-0}" == 0 ]]; then
    printf 'FATAL: failed to source lib/common.sh!\n' >&2
    exit 1
fi
common_init

registry="${REGISTRY:-}"
function getRegistry() {
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

# observe() produces a stream of lines where each line stands for a monitor resource changed on
# OCP's server side. Each line looks like this:
#   <namespace> <name> <kind>/<name>
# Where <kind> is capitalized.
# Monitored resources must be passed as arguments.
function observe() {
    if [[ $# == 0 ]]; then
        printf 'Nothing to observe!\n' >&2
        return 1
    fi
    # we cannot call oc observe directly with the desired template because its object cache is not
    # updated fast enough and it returns outdated information; instead, each object needs to be
    # fully refetched each time
    tr '[:upper:]' '[:lower:]' <<<"$(printf '%s\n' "$@")" | \
        parallel --halt now,done=1 --line-buffer -J "$#" \
            oc observe -n "$SDI_NAMESPACE" --no-headers --listen-addr=":1125{#}" '{}' \
                --output=gotemplate --argument '{{.kind}}/{{.metadata.name}}' -- echo
}

function mkVsystemIptablesPatchFor() {
    local name="$1"
    local specField="$2"
    local containerIndex="${3:-}"
    local unprivileged="${4:-}"
    if [[ -z "${containerIndex:-}" || -z "${unprivileged:-}" ]]; then
        return 0
    fi
    if [[ "$unprivileged" == "true" ]]; then
        log 'Patching container #%d in deployment/%s to make its pods privileged ...' \
                "$containerIndex" "$name" >&2
        printf '{
            "op": "add", "value": true,
            "path": "/spec/template/spec/%s/%d/securityContext/privileged"
        }' "$specField" "$containerIndex"
    else
        log 'Container #%d in deployment/%s already patched, skipping ...' \
            "$containerIndex" "$name"
    fi
}

# shellcheck disable=SC2016
gotmplDeployment=(
    '{{with $d := .}}'
        '{{with $appcomp := index $d.metadata.labels "datahub.sap.com/app-component"}}'
            '{{if eq $appcomp "vflow"}}'
                # print (string kind)#(string componentName):(string version)
                '{{$d.kind}}#{{$appcomp}}:'
               $'{{index $d.metadata.labels "datahub.sap.com/package-version"}}:\n'
            '{{else if eq $appcomp "vsystem-app"}}'
                # print (string kind)#((int containerIndex):(bool unprivileged))?#
                #       ((int initContainerIndex):(bool unprivileged))?
                '{{$d.kind}}#'
                '{{range $i, $c := $d.spec.template.spec.containers}}'
                    '{{if eq .name "vsystem-iptables"}}'
                        '{{$i}}:{{not $c.securityContext.privileged}}'
                    '{{end}}'
                '{{end}}#'
                '{{range $i, $c := $d.spec.template.spec.initContainers}}'
                    '{{if eq .name "vsystem-iptables"}}'
                        '{{$i}}:{{not $c.securityContext.privileged}}'
                    '{{end}}'
                '{{end}}'
                $'\n'
            '{{end}}'
        '{{end}}'
    '{{end}}'
)

# shellcheck disable=SC2016
gotmplDaemonSet=( 
    '{{with $ds := .}}'
        '{{if eq .metadata.name "diagnostics-fluentd"}}'
            # print (string kind)#((int containerIndex):(string containerName):(bool unprivileged)
            #            :(int volumeindex):(string varlibdockercontainers volumehostpath)
            #            :(int volumeMount index):(string varlibdockercontainers volumeMount path)#)+
            '{{$ds.kind}}#'
            '{{range $i, $c := $ds.spec.template.spec.containers}}'
                '{{if eq $c.name "diagnostics-fluentd"}}'
                    '{{$i}}:{{$c.name}}:{{not $c.securityContext.privileged}}'
                    '{{range $j, $v := $ds.spec.template.spec.volumes}}'
                        '{{if eq $v.name "varlibdockercontainers"}}'
                            ':{{$j}}:{{$v.hostPath.path}}'
                        '{{end}}'
                    '{{end}}'
                    '{{range $j, $vm := $c.volumeMounts}}'
                        '{{if eq $vm.name "varlibdockercontainers"}}'
                            ':{{$j}}:{{$vm.mountPath}}'
                        '{{end}}'
                    '{{end}}#'
                '{{end}}'
            '{{end}}'
            $'\n'
        '{{end}}'
    '{{end}}'
)

# shellcheck disable=SC2016
gotmplStatefulSet=(
    '{{with $ss := .}}'
        '{{if eq $ss.metadata.name "vsystem-vrep"}}'
            # print (string kind)#((int containerIndex)(:(string volumeMountName))*#)+
            '{{$ss.kind}}#'
            '{{range $i, $c := $ss.spec.template.spec.containers}}'
                '{{if eq $c.name "vsystem-vrep"}}'
                    '{{$i}}'
                    '{{range $vmi, $vm := $c.volumeMounts}}'
                        '{{if eq $vm.mountPath "/exports"}}'
                            ':{{$vm.name}}'
                        '{{end}}'
                    '{{end}}'
                '{{end}}'
            '{{end}}#'
           $'\n'
        '{{end}}'
    '{{end}}'
)

gotmplConfigMap=(
    '{{if eq .metadata.name "diagnostics-fluentd-settings"}}'
        # print (string kind)
        $'{{.kind}}\n'
    '{{end}}'
)

declare -A gotmpls=(
    [Deployment]="$(join '' "${gotmplDeployment[@]}")"
    [DaemonSet]="$(join '' "${gotmplDaemonSet[@]}")"
    [StatefulSet]="$(join '' "${gotmplStatefulSet[@]}")"
    [ConfigMap]="$(join '' "${gotmplConfigMap[@]}")"
)

function checkPerm() {
    local perm="$1"
    local namespace=""
    local args=()
    if [[ "$perm" =~ (.+):(.+) ]]; then
        namespace="${BASH_REMATCH[1]}"
        perm="${BASH_REMATCH[2]}"
    else
        namespace="$SDI_NAMESPACE"
    fi
    args+=( -n "$namespace" "${perm%%/*}" "${perm##*/}" )
    if ! oc auth can-i "${args[@]}" >/dev/null; then
        printf '%s\n' "$perm"
    fi
}
export -f checkPerm

function checkPermissions() {
    declare -a lackingPermissions
    local perm
    local rc=0
    local toCheck=(
        get/configmaps
        get/deployments
        get/nodes
        get/projects
        get/secrets
        get/statefulsets
        patch/configmaps
        patch/daemonsets
        patch/deployments
        patch/statefulsets
        update/daemonsets
        watch/configmaps
        watch/daemonsets
        watch/deployments
        watch/statefulsets
    )
    local nmprefix=""
    [[ -n "${NAMESPACE:-}" ]] && nmprefix="${NAMESPACE:-}:"
    if evalBool DEPLOY_SDI_REGISTRY; then
        declare -a registryKinds=()
        readarray -t registryKinds <<<"$(oc process REDHAT_REGISTRY_SECRET_NAME=foo \
            -f "$(getRegistryTemplatePath)" -o jsonpath=$'{range .items[*]}{.kind}\n{end}')"
        for kind in "${registryKinds[@],,}"; do
            toCheck+=( "${nmprefix}create/${kind}" )
        done
    fi
    if evalBool DEPLOY_LETSENCRYPT; then
        declare -a letsencryptKinds=()
        local prefix="${LETSENCRYPT_REPOSITORY:-$DEFAULT_LETSENCRYPT_REPOSITORY}"
        for fn in "${LETSENCRYPT_DEPLOY_FILES[@]//@environment@/live}"; do
            readarray -t letsencryptKinds <<<"$(oc create --dry-run \
                -f "${prefix#file://}/$fn" -o jsonpath=$'{.kind}\n')"
            for kind in "${letsencryptKinds[@],,}"; do
                toCheck+=( "${nmprefix}create/${kind}" )
            done
        done
    fi

    readarray -t lackingPermissions <<<"$(parallel checkPerm ::: "${toCheck[@]}")"

    if [[ "${#lackingPermissions[@]}" -gt 0 ]]; then
        for perm in "${lackingPermissions[@]}"; do
            [[ -z "$perm" ]] && continue
            log -n 'Cannot "%s" "%s", please grant the needed permissions' "${perm%%/*}" "${perm##*/}"
            log -d ' to sdi-observer service account!'
            rc=1
        done
        return "$rc"
    fi
}

function getJobImage() {
    if [[ -n "${JOB_IMAGE:-}" ]]; then
        printf '%s' "${JOB_IMAGE}"
        return 0
    fi
    # shellcheck disable=SC2016
    JOB_IMAGE="$(oc get -n "$NAMESPACE" dc/sdi-observer -o  \
        go-template='{{with $c := index .spec.template.spec.containers 0}}{{$c.image}}{{end}}')"
    export JOB_IMAGE
    printf '%s' "${JOB_IMAGE}"
}

function deployComponent() {
    local component="$1"
    local dirs=(
        .
        ""
        "$(dirname "${BASH_SOURCE[@]}")"
        /usr/local/share/sdi
    )
    local d
    local fn="$component/deploy-job-template.json"
    # shellcheck disable=SC2191
    local args=(
        DRY_RUN="${DRY_RUN:-}"
        NAMESPACE="${NAMESPACE:-}"
        FORCE_REDEPLOY="${FORCE_REDEPLOY:-}"
        REPLACE_SECRETS="${REPLACE_SECRETS:-}"
        JOB_IMAGE="$(getJobImage)"
        # passed as an argument instead
        #WAIT_UNTIL_ROLLEDOUT=true
    )
    case "${component}" in
        registry)
            # shellcheck disable=SC2191
            args+=(
                SDI_REGISTRY_STORAGE_CLASS_NAME="${SDI_REGISTRY_STORAGE_CLASS_NAME:-}"
                SDI_REGISTRY_USERNAME="${SDI_REGISTRY_USERNAME:-}"
                SDI_REGISTRY_PASSWORD="${SDI_REGISTRY_PASSWORD:-}"
                SDI_REGISTRY_HTPASSWD_SECRET_NAME="${SDI_REGISTRY_HTPASSWD_SECRET_NAME:-}"
                SDI_REGISTRY_ROUTE_HOSTNAME="${SDI_REGISTRY_ROUTE_HOSTNAME:-}"
                SDI_REGISTRY_HTTP_SECRET="${SDI_REGISTRY_HTTP_SECRET:-}"
                SDI_REGISTRY_VOLUME_CAPACITY="${SDI_REGISTRY_VOLUME_CAPACITY:-}"
                EXPOSE_WITH_LETSENCRYPT="${EXPOSE_WITH_LETSENCRYPT:-}"
                REDHAT_REGISTRY_SECRET_NAME="${REDHAT_REGISTRY_SECRET_NAME:-}"
            )
            ;;
        letsencrypt)
            local projects=( "$SDI_NAMESPACE" )
            if evalBool DEPLOY_SDI_REGISTRY && [[ -n "${NAMESPACE:-}" ]]; then
                projects+=( "$NAMESPACE" )
            fi
            args+=( "PROJECTS_TO_MONITOR=$(join , "${projects[@]}")" )
            ;;
    esac

    # prune empty parameters
    local toDelete=()
    for ((i=${#args[@]} - 1; i >= 0 ; i--)); do
        if [[ "${args[$i]}" =~ ^[^=]+=$ ]]; then
            toDelete+=( "$i" )
        fi
    done
    if [[ "${#toDelete[@]}" -gt 0 ]]; then
        for i in "${toDelete[@]}"; do
            unset args["$i"]
        done
    fi

    for d in "${dirs[@]}"; do
        local pth="$d/$fn"
        if [[ -f "$pth" ]]; then
            oc process "${args[@]}" -f "$pth" | createOrReplace
            return 0
        fi
    done
    log 'WARNING: Cannot find %s, skipping deployment!' "$fn"
    return 1
}

checkPermissions

if evalBool DEPLOY_SDI_REGISTRY; then
    if evalBool DEPLOY_LETSENCRYPT && [[ -z "${EXPOSE_WITH_LETSENCRYPT:-}" ]]; then
        export EXPOSE_WITH_LETSENCRYPT=true
    fi
    if [[ -z "${SDI_REGISTRY_ROUTE_HOSTNAME:-}" && -n "${REGISTRY:-}" ]]; then
        SDI_REGISTRY_ROUTE_HOSTNAME="${REGISTRY}"
    fi
    deployComponent registry
fi
if evalBool DEPLOY_LETSENCRYPT; then
    if [[ -z "${LETSENCRYPT_NAMESPACE:-}" ]] && evalBool DEPLOY_SDI_REGISTRY; then
        LETSENCRYPT_NAMESPACE="${SDI_REGISTRY_NAMESPACE:-}"
    fi
    LETSENCRYPT_NAMESPACE="${LETSENCRYPT_NAMESPACE:-$SDI_NAMESPACE}" \
        deployComponent letsencrypt
fi

if [[ -n "${SDI_NAMESPACE:-}" ]]; then
    log 'Monitoring namespace "%s" for SAP Data Intelligence objects...' "$SDI_NAMESPACE"
fi

# delete obsolete deploymentconfigs
function deleteResource() {
    oc get -o name "$@" 2>/dev/null | xargs -r oc delete || :
}
export -f deleteResource
parallel deleteResource ::: {deploymentconfig,serviceaccount,role}/{vflow,vsystem,sdh}-observer \
    "rolebinding -l deploymentconfig="{vflow-observer,vsystem-observer,sdh-observer}

gotmplvflow=$'{{range $index, $arg := (index (index .spec.template.spec.containers 0) "args")}}{{$arg}}\n{{end}}'

if [[ -n "${NAMESPACE:-}" && -n "${SDI_NAMESPACE:-}" && "$NAMESPACE" != "$SDI_NAMESPACE" ]]; then
    oc project "$SDI_NAMESPACE"
fi

while IFS=' ' read -u 3 -r _ name resource; do
    if [[ "${resource:-""}" == '""' ]]; then
        continue
    fi
    kind="${resource%%/*}"
    if [[ "$name" != "${resource##*/}" ]]; then
        printf 'Names do not match (%s != %s). Something is terribly wrong!\n' "$name" \
            "${resource##/*}"
        continue
    fi
    if [[ -z "${kind:-}" || -z "${name:-}" ]]; then
        continue
    fi
    data="$(oc get "$resource" -o go-template="${gotmpls[$kind]}")" ||:
    if [[ -z "${data:-}" ]]; then
        continue
    fi
    IFS='#' read -r _kind rest <<<"${data}"
    if [[ "$_kind" != "$kind" ]]; then
        printf 'Kinds do not match (%s != %s)! Something is terribly wrong!\n' "$kind" "$_kind"
        continue
    fi
    resource="${resource,,}"

    case "${resource}" in
    deployment/vflow* | deployment/pipeline-modeler*)
        patches=()
        IFS=: read -r pkgversion <<<"${rest:-}"
        pkgversion="${pkgversion#v}"
        pkgmajor="${pkgversion%%.*}"
        pkgminor="${pkgversion#*.}"
        pkgminor="${pkgminor%%.*}"

        # -insecure-registry flag is supported starting from 2.5; earlier releases need no patching
        if evalBool MARK_REGISTRY_INSECURE && \
                    [[ -n "$(getRegistry)" ]] && \
                    [[ "${pkgmajor:-0}" == 2 && "${pkgminor:-0}" -ge 5 ]];
        then
            registry="$(getRegistry)"
            readarray -t vflowargs <<<"$(oc get deploy -o go-template="${gotmplvflow}" "$name")"
            if ! grep -q -F -- "-insecure-registry=${registry}" <<<"${vflowargs[@]}"; then
                vflowargs+=( "-insecure-registry=${registry}" )
                newargs=( )
                for ((i=0; i<"${#vflowargs[@]}"; i++)) do
                    # escape double qoutes of each argument and surround it with double quotes
                    newargs+=( '"'"${vflowargs[$i]//\"/\\\"}"'"' )
                done
                # turn the argument array into a json list of strings
                newarglist="[$(join , "${newargs[@]}")]"
                log 'Patching deployment/%s to treat %s registry as insecure ...' "$name" "$registry"
                patches+=( '{"op":"add","path":"/spec/template/spec/containers/0/args","value":'"$newarglist"'}' )
            else
                log 'deployment/%s already patched to treat %s registry as insecure, not patching ...' "$name" "$registry"
            fi
        fi

        [[ "${#patches[@]}" == 0 ]] && continue
        runOrLog oc patch --type json -p "[$(join , "${patches[@]}")]" deploy "$name"
        ;;

    deployment/*)
        IFS='#' read -r cs ics <<<"${rest:-}"
        IFS=: read -r cindex cunprivileged <<<"${cs:-}"
        IFS=: read -r icindex icunprivileged <<<"${ics:-}"
        patches=()
        patch="$(mkVsystemIptablesPatchFor "$name" "containers" \
            "${cindex:-}" "${cunprivileged:-}")"
        [[ "${patch:-}" ]] && patches+=( "${patch}" )
        patch="$(mkVsystemIptablesPatchFor "$name" "initContainers" \
            "${icindex:-}" "${icunprivileged:-}")"
        [[ "${patch:-}" ]] && patches+=( "${patch}" )
        [[ "${#patches[@]}" == 0 ]] && continue

        runOrLog oc patch "deploy/$name" --type json -p '['"$(join , "${patches[@]}")"']'
        ;;

    daemonset/*)
        IFS=: read -r index _ unprivileged _ hostPath volumeMountIndex mountPath <<<"${rest:-}"
        name="diagnostics-fluentd"
        patches=()
        patchTypes=()
        mountPath="${mountPath%%#*}"
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
            patches+=(
                "$(join ' ' '[{"op": "replace", "path":' \
                                '"/spec/template/spec/containers/'"$index/volumeMounts/$volumeMountIndex"'",' \
                                '"value": {"name":"varlibdockercontainers","mountPath":"/var/lib/docker","readOnly": true}}]' )"
            )
            patchTypes+=( json )
            patches+=(
                "$(join ' ' '{"spec":{"template":{"spec":' \
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
        createOrReplace <<<"${dsSpec}"
        ;;

    statefulset/*)
        IFS=: read -r cindex vmName <<<"${rest:-}"
        if [[ -n "${cindex:-}" && -n "${vmName:-}" ]]; then
            log 'statefulset/vsystem-vrep already patched, skipping ...'
        else
            log 'Adding emptyDir volume to statefulset/vsystem-vrep ...'
            runOrLog oc set volume "$resource" --add --type emptyDir \
                --mount-path=/exports --name exports-volume
        fi
        ;;

    configmap/diagnostics-fluentd-settings)
        contents="$(oc get "$resource" -o go-template='{{index .data "fluent.conf"}}')"
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
        # shellcheck disable=SC2001
        yamlPatch="$(printf '%s\n' "data:" "    fluent.conf: |" \
            "$(sed 's/^/        /' <<<"${newContents}")")"
        runOrLog oc patch "$resource" -p "$yamlPatch"
        readarray -t pods <<<"$(oc get pods -l datahub.sap.com/app-component=fluentd -o name)"
        [[ "${#pods[@]}" == 0 ]] && continue
        log 'Restarting fluentd pods ...'
        runOrLog oc delete --force --grace-period=0 "${pods[@]}"
        ;;

    *)
        log 'Got unexpected resource: name="%s", kind="%s", rest:"%s"' "${name:-}" "${kind:-}" \
            "${rest:-}"
        ;;

    esac
done 3< <(observe "${!gotmpls[@]}")

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

readonly CLUSTERIP_SERVICE_NAME="slcbridge-clusterip"
readonly CABUNDLE_VOLUME_NAME="sdi-observer-cabundle"
readonly CABUNDLE_VOLUME_MOUNT_PATH="/mnt/sdi-observer/cabundle"
readonly CHECKPOINT_CHECK_JOBNAME="datahub.checks.checkpoint"
readonly INSTALLER_JOB_TYPE_LABEL="com.sap.datahub.installers.scripts"
readonly UPDATE_CA_TRUST_CONTAINER_NAME="sdi-observer-update-ca-certificates"
readonly VORA_CABUNDLE_SECRET_NAME="ca-bundle.pem"
readonly VREP_EXPORTS_VOLUME_OBSOLETE_NAMES=( "exports-volume" )
readonly VREP_EXPORTS_VOLUME_NAME="exports"
readonly VREP_EXPORTS_VOLUME_SIZE="500Mi"

function getRegistries() {
    local registries=()
    readarray -t registries <<<"$(oc get secret \
        -o go-template='{{index .data "secret"}}' vflow-secret | \
        base64 -d | sed -n 's/^\s*address:\s*\(...\+\)/\1/p' | \
            tr -d '"'"'" | grep -v '^[[:space:]]*$' | sort -u)"
    if [[ "${#registries[@]}" == 0 ]]; then
        log "Failed to determine the registry for the pipeline modeler!"
        return 1
    fi
    printf '%s\n' "${registries[@]}"
}

function _observe() {
    local kind="${1##*:}"
    local namespace="$SDI_NAMESPACE"
    if [[ "$1" =~ ^(.+):(.+)$ ]]; then
        namespace="${BASH_REMATCH[1]}"
    fi
    local jobnumber="$2"
    local portnumber="$((11251 + jobnumber))"
    oc observe -n "$namespace" --no-headers --listen-addr=":$portnumber" "$kind" \
        --output=gotemplate --argument '{{.kind}}/{{.metadata.name}}' -- echo
}
export -f _observe

function _cleanup() {
    jobs -r -p | xargs -r kill -KILL ||:
    common_cleanup
}
trap _cleanup EXIT

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
    local cpus
    cpus="$(grep -c processor /proc/cpuinfo)" ||:
    local N="$#"
    if [[ "${cpus:-1}" -lt "$N" ]]; then
        N="+$((N - 1))"
    fi
    # we cannot call oc observe directly with the desired template because its object cache is not
    # updated fast enough and it returns outdated information; instead, each object needs to be
    # fully refetched each time
    tr '[:upper:]' '[:lower:]' <<<"$(printf '%s\n' "$@")" | \
        parallel --halt now,done=1 --termseq KILL,25 --line-buffer \
            --jobs "$N" -i '{}' -- _observe '{}' '{#}'
    log 'WARNING: Monitoring terminated.'
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

if [[ -z "${SLCB_NAMESPACE:-}" ]]; then
    export SLCB_NAMESPACE=sap-slcbridge
fi

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
            $'{{end}}\n'
        '{{end}}'
    '{{end}}'
)

# shellcheck disable=SC2016
gotmplStatefulSet=(
    '{{with $ss := .}}'
        '{{if eq $ss.metadata.name "vsystem-vrep"}}'
            # print (string kind)#((int containerIndex)
            #       (:(string volumeMountName),(string claimVolumeSize))*#)+
            '{{$ss.kind}}#'
            '{{range $i, $c := $ss.spec.template.spec.containers}}'
                '{{if eq $c.name "vsystem-vrep"}}'
                    '{{$i}}'
                    '{{range $vmi, $vm := $c.volumeMounts}}'
                        '{{if eq $vm.mountPath "/exports"}}'
                            ':{{$vm.name}}'
                            '{{range $vcti, $vct := $ss.spec.volumeClaimTemplates}}'
                                '{{if eq $vct.metadata.name $vm.name}}'
                                    ',{{$vct.spec.resources.requests.storage}}'
                                '{{end}}'
                            '{{end}}'
                        '{{end}}'
                    '{{end}}'
                '{{end}}'
            '{{end}}#'
           $'\n'
        '{{end}}'
    '{{end}}'
)

gotmplConfigMap=(
    $'{{.kind}}\n'
)

# shellcheck disable=SC2016
gotmplService=(
    '{{with $s := .}}'
        '{{with $run := index $s.metadata.labels "run"}}'
            '{{with $ss := $s.spec}}'
                '{{if eq $run "slcbridge"}}'
                    # print (string kind)#(string clusterIP)#(string type)#
                    #       (string sessionAffinity)#((string targetPort):)+
                    '{{$s.kind}}#{{$ss.clusterIP}}#{{$ss.type}}#{{$ss.sessionAffinity}}#'
                    '{{range $i, $p := $ss.ports}}'
                        '{{$p.targetPort}}:'
                    '{{end}}'
                '{{end}}'
            '{{end}}'
           $'\n'
        '{{end}}'
    '{{end}}'
)

gotmplSecret=()
if evalBool INJECT_CABUNDLE || [[ -n "${REDHAT_REGISTRY_SECRET_NAME:-}" ]]; then
    if [[ -z "${CABUNDLE_SECRET_NAME:-}" ]]; then
        CABUNDLE_SECRET_NAME="openshift-ingress-operator/router-ca"
    fi
    CABUNDLE_SECRET_NAMESPACE="${CABUNDLE_SECRET_NAME%%/*}"
    CABUNDLE_SECRET_NAME="${CABUNDLE_SECRET_NAME##*/}"
    CABUNDLE_SECRET_NAMESPACE="${CABUNDLE_SECRET_NAMESPACE:-$NAMESPACE}"
    gotmplSecret=(
        '{{if or (and (eq .metadata.name "'"$CABUNDLE_SECRET_NAME"'")'
                    ' (eq .metadata.namespace "'"$CABUNDLE_SECRET_NAMESPACE"'"))'
               ' (eq .metadata.name "'"${REDHAT_REGISTRY_SECRET_NAME:-redhat-registry-secret-name}"'")}}'
            $'{{.kind}}#{{.metadata.uid}}\n'
        '{{end}}'
    )
    export CABUNDLE_SECRET_NAMESPACE CABUNDLE_SECRET_NAME INJECT_CABUNDLE
fi

# shellcheck disable=SC2016
gotmplJob=(
    '{{with $j := .}}'
        '{{with $t := index $j.metadata.labels "job-type"}}'
            '{{if eq $t "'"$INSTALLER_JOB_TYPE_LABEL"'"}}'
                # print (string kind)#(string injected-cabundle)#((int volumeIndex):)*
                '{{$j.kind}}#'
                '{{if $j.metadata.annotations}}'
                    '{{with $cab := index $j.metadata.annotations "'"$CABUNDLE_INJECTED_ANNOTATION"'"}}'
                        '{{$cab}}'
                    '{{end}}'
                '{{end}}#'
                '{{range $i, $v := $j.spec.template.spec.volumes}}'
                    '{{if eq $v.name "'"$CABUNDLE_VOLUME_NAME"'"}}'
                        '{{$i}}:'
                    '{{end}}'
                $'{{end}}\n'
            '{{end}}'
        '{{end}}'
    '{{end}}'
)

# Defines all the resource types that shall be monitored accross different namespaces.
# The associated value is a go-template producing an output the will be passed to the observer
# loop.
declare -A gotmpls=(
    ["${SDI_NAMESPACE}:Deployment"]="$(join '' "${gotmplDeployment[@]}")"
    ["${SDI_NAMESPACE}:DaemonSet"]="$(join '' "${gotmplDaemonSet[@]}")"
    ["${SDI_NAMESPACE}:StatefulSet"]="$(join '' "${gotmplStatefulSet[@]}")"
    ["${SDI_NAMESPACE}:ConfigMap"]="$(join '' "${gotmplConfigMap[@]}")"
    ["${SDI_NAMESPACE}:Job"]="$(join '' "${gotmplJob[@]}")"
    ["${SLCB_NAMESPACE}:ConfigMap"]="$(join '' "${gotmplConfigMap[@]}")"
    ["${SLCB_NAMESPACE}:Service"]="$(join '' "${gotmplService[@]}")"
)

if evalBool INJECT_CABUNDLE; then
    gotmpls["${CABUNDLE_SECRET_NAMESPACE}:Secret"]="$(join '' "${gotmplSecret[@]}")"
fi
if [[ -n "${REDHAT_REGISTRY_SECRET_NAME:-}" ]]; then
    for nm in ${REDHAT_REGISTRY_SECRET_NAMESPACE} "${SDI_NAMESPACE}" "${SLCB_NAMESPACE}"; do
        gotmpls["${nm}:Secret"]="$(join '' "${gotmplSecret[@]}")"
    done
fi

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
        printf '%s\n' "$namespace:$perm"
    fi
}
export -f checkPerm

function checkPermissions() {
    declare -a lackingPermissions
    local perm
    local rc=0
    local toCheck=()
    for verb in get patch watch; do
        for resource in configmaps daemonsets deployments statefulsets jobs; do
            toCheck+=( "$verb/$resource" )
        done
    done
    toCheck+=(
        get/nodes
        get/projects
        get/secrets
        update/daemonsets

        "$SLCB_NAMESPACE:get/configmaps"
        "$SLCB_NAMESPACE:patch/configmaps"
        "$SLCB_NAMESPACE:watch/configmaps"
        "$SLCB_NAMESPACE:get/service"
        "$SLCB_NAMESPACE:create/service"
        "$SLCB_NAMESPACE:delete/service"
        "$SLCB_NAMESPACE:create/route"
        "$SLCB_NAMESPACE:delete/route"
        "$SLCB_NAMESPACE:get/route"
        "$SLCB_NAMESPACE:watch/configmaps"
    )
    if [[ -n "${CABUNDLE_SECRET_NAMESPACE:-}" ]]; then
        toCheck+=( "${CABUNDLE_SECRET_NAMESPACE:-}:get/secrets" )
    fi

    local nmprefix=""
    [[ -n "${NAMESPACE:-}" ]] && nmprefix="${NAMESPACE:-}:"
    if evalBool DEPLOY_SDI_REGISTRY; then
        declare -a registryKinds=()
        readarray -t registryKinds <<<"$(oc process \
            NAMESPACE="${NAMESPACE:-foo}" \
            REDHAT_REGISTRY_SECRET_NAME=foo \
            -f "$(SOURCE_IMAGE_PULL_SPEC="" getRegistryTemplatePath)" \
                -o jsonpath=$'{range .items[*]}{.kind}\n{end}')"
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
                toCheck+=( "${nmprefix}create/${kind,,}" )
            done
        done
    fi
    if evalBool DEPLOY_LETSENCRYPT || evalBool DEPLOY_SDI_REGISTRY; then
        toCheck+=( "${nmprefix}delete/job" )
    fi

    readarray -t lackingPermissions <<<"$(parallel checkPerm ::: "${toCheck[@]}")"

    if [[ "${#lackingPermissions[@]}" -gt 0 ]]; then
        for nsperm in "${lackingPermissions[@]}"; do
            [[ -z "$nsperm" ]] && continue
            local namespace="${nsperm%%:*}"
            local perm="${nsperm##*:}"
            log -n 'Cannot "%s" "%s" in namespace "%s", please grant the needed permissions' \
                "${perm%%/*}" "${perm##*/}" "$namespace"
            log -d ' to sdi-observer service account!'
            rc=1
        done
        return "$rc"
    fi
}

# delete obsolete deploymentconfigs
function deleteResource() {
    local namespace="$1"
    shift
    local resources=()
    readarray -t resources <<<"$(oc get -o name -n "$namespace" "$@" 2>/dev/null)"
    if [[ "${#resources[@]}" == 0 || ( "${#resources[@]}" == 1 && "${resources[0]}" == '' ) ]];
    then
        return 0
    fi
    runOrLog oc delete -n "$namespace" "${resources[@]}"
}
export -f deleteResource
function purgeDeprecatedResources() {
    local purgeNamespaces=( "$NAMESPACE" )
    if [[ "$NAMESPACE" != "$SDI_NAMESPACE" ]]; then
        purgeNamespaces+=( "$SDI_NAMESPACE" )
    fi
    export DRY_RUN
    parallel deleteResource ::: "${purgeNamespaces[@]}" ::: \
        {deploymentconfig,serviceaccount,role}/{vflow,vsystem,sdh}-observer || :
    parallel deleteResource '{1}' rolebinding '{2}' ::: "${purgeNamespaces[@]}" :::  \
        "--selector=deploymentconfig="{vflow-observer,vsystem-observer,sdh-observer} ||:
}

function processSLCBService() {
    local namespace="$1"
    local name="$2"
    local _type="$3"
    local sessionAffinity="$4"
    if [[ "$name" == "$CLUSTERIP_SERVICE_NAME" && \
          "${_type:-}" == "ClusterIP" &&
          "${sessionAffinity:-}" == "ClientIP" ]];
    then
        log 'Service %s in namespace %s already exists, skipping ...' \
            "$name" "$namespace"
        return 0
    fi

    if [[ "$name" == "$CLUSTERIP_SERVICE_NAME" ]]; then
        log 'Patching service %s in namespace %s to become clusterIP, ...' \
            "$name" "$namespace"
        oc get -n "$namespace" -o json "service/$name" | \
            jq '.spec.type |= "ClusterIP" |
                .spec.sessionAffinity |= "ClientIP" |
                walk(if type == "object" then
                            delpaths([["nodePort"],["externalTrafficPolicy"]])
                     else . end)' | createOrReplace -n "$namespace"
        return 0
    fi
    if oc get -n "$namespace" "service/$CLUSTERIP_SERVICE_NAME" -o name >/dev/null 2>&1; then
        log 'Service %s in namespace %s already exists, ignoring event for service %s ...' \
            "$CLUSTERIP_SERVICE_NAME" "$namespace" "$name"
        return 0
    fi

    log 'Creating service %s in namespace %s, ...' "$CLUSTERIP_SERVICE_NAME" "$namespace"
    oc get -n "$namespace" -o json "service/$name" | \
        jq '.spec.type |= "ClusterIP" | .metadata.name |= "'"$CLUSTERIP_SERVICE_NAME"'" |
            .spec.sessionAffinity |= "ClientIP" | del(.spec.clusterIP) |
            walk(if type == "object" then
                        delpaths([["nodePort"],["externalTrafficPolicy"]])
                 else . end)' | createOrReplace -n "$namespace"
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

function addUpdateCaTrustInitContainer() {
    local arr=() object scriptLines=() script
    mapfile -d $'\0' arr
    object="${arr[0]:-}"
    # shellcheck disable=SC2016
    # 
    scriptLines=(
        'mkdir -pv /etc/pki/ca-trust/source/anchors/ ||:'
        'k8scacert=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
        # copy a standard k8s cabundle generated and mounted by OCP platform
        # TODO: make this optional - may not be desirable
        'if [[ -e "$k8scacert" ]]; then'
        '  cp -aLv "$k8scacert" /etc/pki/ca-trust/source/anchors/k8s-ca.crt'
        'fi'
        # copy also the desired CA certificate bundle
        "$(join ' ' 'cp -aLv' \
            '"'"$CABUNDLE_VOLUME_MOUNT_PATH/$SDI_CABUNDLE_SECRET_FILE_NAME"'"' \
            '/etc/pki/ca-trust/source/anchors/')"
        # the command is named differently on RHEL and SLES, support both
        'cmd=update-ca-trust'
        'if command -v update-ca-certificates >/dev/null; then'
        '  cmd=update-ca-certificates'
        'fi'
        '"$cmd"'
        # copy the generated updated CA certificates to an empty dir volume which will be mounted
        # to the injected container at /etc/pki
        'cd /etc/pki'
        'cp -av * /mnt/etc-pki/'
#        "$(join ' ' 'find -L -type f |' \
#            ' grep -v -F -f <(find -L -type l) |' \
#            ' xargs -n 1 -r -i install --preserve-context -p -D -v "{}" "/mnt/etc-pki/{}"')"
    )

    local namespace saName
    IFS=: read -r namespace saName <<<"$(jq -r \
        '"\(.metadata.namespace // "'"$SDI_NAMESPACE"'"):\(.spec.template.spec.serviceAccountName)"' \
            <<<"$object")"
    local pullSecretName
    pullSecretName="$(oc get -n "$namespace" "sa/$saName" -o json | \
        jq -r '.secrets[] | select(.name | test("-dockercfg-")) | .name')"

    script="$(printf '%s\\n' "${scriptLines[@]//\"/\\\"}")"
    # TODO: report that equivalent `oc set volume --local -f - ...` command results in a traceback
    # shellcheck disable=SC2016
    local patches=(
        '.spec.template.spec.initContainers |= (. // [] | [.[] |
                select(.name != "'"$UPDATE_CA_TRUST_CONTAINER_NAME"'")]) + [
            {
              "command": [
                "/bin/bash",
                "-c",
                "'"$script"'"
              ],
              "image": "'"$(getJobImage)"'",
              "name": "'"$UPDATE_CA_TRUST_CONTAINER_NAME"'"
            }]'

        '.spec.template.spec |= (. | walk(if type == "object" and has("image") and has("name") then
                . as $c | .volumeMounts |= (. // [] |
                    [.[] | select(.name != "'"$CABUNDLE_VOLUME_NAME"'" and .name != "etc-pki")] + [
                        {
                            "mountPath": "'"$CABUNDLE_VOLUME_MOUNT_PATH"'",
                            "name": "'"$CABUNDLE_VOLUME_NAME"'",
                            "readOnly": true
                        }, {
                            "mountPath": (if $c.name == "'"$UPDATE_CA_TRUST_CONTAINER_NAME"'" then
                                "/mnt/etc-pki"
                            else
                                "/etc/pki"
                            end),
                            "name": "etc-pki",
                        }
                    ])
                else . end))'

        '.spec.template.spec.volumes |= (. // [] | [.[] | 
            select(.name != "'"$CABUNDLE_VOLUME_NAME"'" and .name != "etc-pki")] + [
                {
                    "name": "etc-pki",
                    "emptyDir": {}
                }, {
                    "name": "'"$CABUNDLE_VOLUME_NAME"'",
                    "secret": {
                        "secretName": "'"$SDI_CABUNDLE_SECRET_NAME"'"
                    }
                }])'

        '.spec.template.spec.imagePullSecrets |= ((. // []) | [.[] | select(.name !=
            "sdi-observer-registry")] + [{"name":"'"$pullSecretName"'"}])'
    )
    jq "$(join '|' "${patches[@]}")" <<<"$object"
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
        OCP_MINOR_RELEASE="${OCP_MINOR_RELEASE:-}"
        # passed as an argument instead
        #WAIT_UNTIL_ROLLEDOUT=true
    )

    if [[ -n "${SOURCE_IMAGESTREAM_NAME:-}" && "${SOURCE_IMAGESTREAM_TAG:-}" && \
            -n "${SOURCE_IMAGE_PULL_SPEC:-}" ]]; then
        fn="$component/deploy-job-custom-source-image-template.json"
        args+=(
            SOURCE_IMAGE_PULL_SPEC="${SOURCE_IMAGE_PULL_SPEC:-}"
            SOURCE_IMAGESTREAM_NAME="${SOURCE_IMAGESTREAM_NAME:-}"
            SOURCE_IMAGESTREAM_TAG="${SOURCE_IMAGESTREAM_TAG:-}"
            SOURCE_IMAGE_REGISTRY_SECRET_NAME="${SOURCE_IMAGE_REGISTRY_SECRET_NAME:-}"
        )
    else
        args+=(
            REDHAT_REGISTRY_SECRET_NAME="${REDHAT_REGISTRY_SECRET_NAMESPACE:-}/${REDHAT_REGISTRY_SECRET_NAME:-}"
        )
    fi

    case "${component}" in
        registry)
            # shellcheck disable=SC2191
            args+=(
                SDI_REGISTRY_STORAGE_CLASS_NAME="${SDI_REGISTRY_STORAGE_CLASS_NAME:-}"
                SDI_REGISTRY_VOLUME_ACCESS_MODE="${SDI_REGISTRY_VOLUME_ACCESS_MODE:-}"
                SDI_REGISTRY_USERNAME="${SDI_REGISTRY_USERNAME:-}"
                SDI_REGISTRY_PASSWORD="${SDI_REGISTRY_PASSWORD:-}"
                SDI_REGISTRY_HTPASSWD_SECRET_NAME="${SDI_REGISTRY_HTPASSWD_SECRET_NAME:-}"
                SDI_REGISTRY_ROUTE_HOSTNAME="${SDI_REGISTRY_ROUTE_HOSTNAME:-}"
                SDI_REGISTRY_HTTP_SECRET="${SDI_REGISTRY_HTTP_SECRET:-}"
                SDI_REGISTRY_VOLUME_CAPACITY="${SDI_REGISTRY_VOLUME_CAPACITY:-}"
                EXPOSE_WITH_LETSENCRYPT="${EXPOSE_WITH_LETSENCRYPT:-}"
                REPLACE_PERSISTENT_VOLUME_CLAIMS="${REPLACE_PERSISTENT_VOLUME_CLAIMS:-}"
            )
            ;;
        letsencrypt)
            local projects=( "$SDI_NAMESPACE" )
            if evalBool DEPLOY_SDI_REGISTRY && [[ -n "${NAMESPACE:-}" ]]; then
                projects+=( "$NAMESPACE" )
            fi
            args+=(
                "PROJECTS_TO_MONITOR=$(join , "${projects[@]}")"
                "LETSENCRYPT_ENVIRONMENT=${LETSENCRYPT_ENVIRONMENT:-}"
            )
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
            # TODO: filter out clusterrolebindings
            oc process "${args[@]}" -f "$pth" | createOrReplace
            return 0
        fi
    done
    log 'WARNING: Cannot find %s, skipping deployment!' "$fn"
    return 1
}

function injectCABundle() {
    local namespace="$1"
    local kind="$2"
    local name="$3"
    local resource="${kind,,}/$name"
    local podLabelSelector="$4"
    # value '""' stands for unset, empty stands for unknown
    local injectedKey="${5:-}"
    local contents injectKey cabundleKey namespace objuid

    contents="$(oc get -o json "$resource")" ||:
    [[ -z "${contents:-}" ]] && return 1
    injectKey="$(jq -r '.metadata.annotations["'"$CABUNDLE_INJECT_ANNOTATION"'"] | if .
        then . else "" end' <<<"$contents")" ||:
    if [[ -z "${injectedKey:-}" ]]; then
        injectedKey="$(jq -r '.metadata.annotations["'"$CABUNDLE_INJECTED_ANNOTATION"'"] | if .
            then . else "" end' <<<"$contents")" ||:
    elif [[ "${injectedKey}" == '""' ]]; then
        injectedKey=''
    fi
    if [[ -n "${injectedKey:-}" && "${injectedKey}" == "${injectKey:-}" ]]; then
        log '%s %s is using the latest cabundle secret, skipping ...' "$kind" "$name"
        return 0
    fi

    cabundleKey="$(oc get secret -o go-template="$(join '' \
        '{{if .metadata.annotations}}' \
                '{{index .metadata.annotations "'"$SOURCE_KEY_ANNOTATION"'"}}{{end}}')" \
        "$SDI_CABUNDLE_SECRET_NAME" 2>/dev/null)" ||:
    if ! [[ "${cabundleKey:-}" =~ ^.+:.+:.+$ ]]; then
        log 'Not patching %s %s because the %s secret does not exist yet.' \
            "${kind,,}" "$name" "$SDI_CABUNDLE_SECRET_NAME"
        return 0
    fi
    log 'Mounting %s secret into %s %s ...' "$SDI_CABUNDLE_SECRET_NAME" "${kind,,}" "$name"
    local jqPatch='.'
    if [[ "${kind,,}" == job ]]; then
        jqPatch='. | del(.spec.selector) | del(.status) |
                     del(.spec.template.metadata.labels."controller-uid")'
    fi
    oc get -o json "$resource" |
        oc annotate --overwrite -f - --local -o json \
            "$CABUNDLE_INJECT_ANNOTATION=$cabundleKey"  \
            "$CABUNDLE_INJECTED_ANNOTATION=$cabundleKey" | \
            jq "${jqPatch}" | \
        addUpdateCaTrustInitContainer | \
            createOrReplace
    ensurePullsFromNamespace "$NAMESPACE" \
        "$(jq -r '.spec.template.spec.serviceAccountName' <<<"$contents")" \
        "$namespace"
    objuid="$(jq -r '.metadata.uid' <<<"${contents}")" ||:
    if [[ -z "${objuid:-}" ]]; then
        log 'WARNING: Could not get uid out of %s %s, not terminating its pods ...' \
            "$kind" "$name"
        return 1
    fi
    if evalBool DRY_RUN; then
        log 'Deleting pods belonging to %s(name=%s, uid=%s)' "$kind" "$name" "$objuid"
    else
        oc get pods -o json -l "$podLabelSelector" | \
            jq -r '.items[] | select((.metadata.ownerReferences // []) | any(
                .name == "'"$name"'" and .uid == "'"$objuid"'")) | "pod/\(.metadata.name)"' | \
            xargs -r oc delete ||:
    fi
}

function addPvToStatefulSet() {
    local name="$1"
    local volumeName="$2"
    local mountPath="$3"
    local volumeSize="$4"
    shift 4
    declare -A removeVolumeNames=( ["$volumeName"]=1 )
    while [[ $# -gt 0 ]]; do
        removeVolumeNames["$1"]=1
        shift
    done
    # shellcheck disable=SC2046
    removeSet='{'"$(join "," $(printf '"%s":null\n' "${!removeVolumeNames[@]}"))"'}'

    # shellcheck disable=SC2016
    local patches=( "$(join ' ' '.spec.volumeClaimTemplates |=' \
        '(. // [] | [.[] | select(.metadata.name | in('"${removeSet}"') | not)] |' \
        '. as $filtered | . +' \
        '[if isempty($filtered) then {' \
                '"metadata": {' \
                    '"creationTimestamp": null,' \
                    '"labels": {' \
                        '"app": "vora",' \
                        '"datahub.sap.com/app": "vsystem",' \
                        '"datahub.sap.com/app-component": "vrep",' \
                        '"datahub.sap.com/bdh-uninstall": "delete",' \
                        '"vora-component": "vsystem-vrep"' \
                    '},' \
                    '"name": "'"$volumeName"'"' \
                '},' \
                '"spec": {' \
                    '"resources": {' \
                        '"requests": {"storage": "'"$volumeSize"'"}' \
                    '},' \
                    '"volumeMode": "Filesystem"' \
                '},' \
                '"status": {"phase": "Pending"}' \
            '} else $filtered[0] | .metadata.name |= "'"$volumeName"'" |' \
                '.spec.resources.requests.storage |= "'"$volumeSize"'" |' \
                '.spec.volumeMode |= "Filesystem" |' \
                '.metadata.labels["datahub.sap.com/bdh-uninstall"] |= "delete"' \
        'end])')"
    )
    
    patches+=( "$(join ' ' '.spec.template.spec |= walk(' \
        'if (. | type) == "object" and has("name") and has("image") then' \
            '.volumeMounts |= (. // [] | [.[] |' \
                'select((.name | in('"${removeSet}"') | not) and' \
                            '.mountPath != "'"$mountPath"'")] + ' \
                '[{"mountPath":"'"$mountPath"'", "name":"'"$volumeName"'"}])' \
        'else . end)')"
    )
    
    patches+=( "$(join ' ' '.spec.template.spec.volumes |=' \
        '(. // [] | [.[] | select(.name | in('"${removeSet}"') | not)])')"
    )

    log 'Mounting a new PV volume named %s of size %s at %s in %s ...' "$volumeName" \
        "$volumeSize" "$mountPath" "$resource"
    # changes to the .spec.volumeClaimTemplates need to be forced
    oc get -o json "$resource" | jq "$(join "|" "${patches[@]}")" | createOrReplace -f
}

checkPermissions
purgeDeprecatedResources

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
if [[ -n "${SLCB_NAMESPACE:-}" && "${SLCB_NAMESPACE}" != "${SDI_NAMESPACE:-}" ]]; then
    log 'Monitoring SLC Bridge namespace "%s" for objects...' "$SLCB_NAMESPACE"
fi


gotmplvflow=$'{{range $index, $arg := (index (index .spec.template.spec.containers 0) "args")}}{{$arg}}\n{{end}}'

if [[ -n "${NAMESPACE:-}" && -n "${SDI_NAMESPACE:-}" && "$NAMESPACE" != "$SDI_NAMESPACE" ]]; then
    oc project "$SDI_NAMESPACE"
fi

while IFS=' ' read -u 3 -r namespace name resource; do
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
    tmpl="${gotmpls["$namespace:$kind"]:-}"
    if [[ -z "${tmpl:-}" ]]; then
        log 'WARNING: Could not find go-template for kind "%s" in namespace "%s"!' "$kind" "$namespace"
        continue
    fi
    data="$(oc get -n "$namespace" "$resource" -o go-template="$tmpl")" ||:
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
        registries=()
        if evalBool MARK_REGISTRY_INSECURE; then
            if [[ "${REGISTRY:-}" ]]; then
                registries=( "$REGISTRY" )
            else
                readarray -t registries <<<"$(getRegistries)"
            fi
        fi

        # -insecure-registry flag is supported starting from 2.5; earlier releases need no patching
        if evalBool MARK_REGISTRY_INSECURE && \
                    [[ "${#registries[@]}" -gt 0 && "${#registries[0]}" -gt 0 ]];
        then
            readarray -t vflowargs <<<"$(oc get deploy -o go-template="${gotmplvflow}" "$name")"
            newargs=( )
            doPatch=0
            for reg in "${registries[@]}"; do
                if [[ -z "${reg:-}" ]]; then
                    continue
                fi
                if ! grep -q -F -- "-insecure-registry=${reg}" <<<"${vflowargs[@]}"; then
                    log 'Patching deployment/%s to treat %s registry as insecure ...' \
                            "$name" "$reg"
                    vflowargs+=( "-insecure-registry=${reg}" )
                    doPatch=1
                else
                    log '%s already patched to treat %s registry as insecure, skipping ...' \
                        "$resource" "$reg"
                fi
            done
            if [[ "${doPatch}" == 1 ]]; then
                # turn the argument array into a json list of strings
                for ((i=0; i<"${#vflowargs[@]}"; i++)) do
                    # escape double qoutes of each argument and surround it with double quotes
                    newargs+=( '"'"${vflowargs[$i]//\"/\\\"}"'"' )
                done
                newarglist="[$(join , "${newargs[@]}")]"
                patches+=( "$(join "," '{"op":"add"' \
                    '"path":"/spec/template/spec/containers/0/args"' \
                    '"value":'"$newarglist"'}')" )
            else
                log 'No need to update insecure registries in %s ...' "$resource"
            fi
        fi

        [[ "${#patches[@]}" == 0 ]] && continue
        runOrLog oc patch --type json -p "[$(join , "${patches[@]}")]" deploy "$name"
        ;;

    deployment/*)
        if ! evalBool MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED; then
            log 'Not patching %s because MAKE_VSYSTEM_IPTABLES_PODS_PRIVILEGED is not true, ...' \
                "$resource"
            continue
        fi
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
        vmSize="${vmName##*,}"
        vmName="${vmName%%,*}"
        if [[ -n "${cindex:-}" && -n "${vmName:-}" && \
                "${vmSize:-}" ==  "$VREP_EXPORTS_VOLUME_SIZE" ]]; then
            log '%s already patched, skipping ...' "$resource"
        else
            addPvToStatefulSet "$resource" "$VREP_EXPORTS_VOLUME_NAME" "/exports" \
                "$VREP_EXPORTS_VOLUME_SIZE" "${VREP_EXPORTS_VOLUME_OBSOLETE_NAMES[@]}"
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
        runOrLog oc delete --force --grace-period=0 "${pods[@]}" ||:
        ;;

    configmap/*nginx*)
        contents="$(oc get -n "$namespace" "$resource" \
            -o go-template='{{index .data "nginx.conf"}}')"
        if [[ -z "${contents:-}" ]]; then
            log "Failed to get contents of nginx.conf configuration file!"
            continue
        fi
        if      ! grep -q 'https\?://localhost' <<<"$contents" && \
                ! grep -q '^\s\+listen\s\+\[::' <<<"$contents";
        then
            log 'No need to patch %s in %s namespace, skipping...' "$resource" "$SLCB_NAMESPACE"
            continue
        fi
        newContents="$(sed -e 's/^\([[:space:]]\+\)\(listen[[:space:]]\+\[::\)/\1#\2/' \
            -e 's,\(https\?://\)localhost,\1127.0.0.1,g' <<<"$contents")"
        # shellcheck disable=SC2001
        log 'Patching configmap %s in namespace "%s" to disable IPv4 for nginx frontend ...' \
            "$name" "$namespace"
        # shellcheck disable=SC2001
        yamlPatch="$(printf '%s\n' "data:" "    nginx.conf: |" \
            "$(sed 's/^/        /' <<<"$newContents")")"
        runOrLog oc patch -n "$SLCB_NAMESPACE" "$resource" -p "$yamlPatch"

        ensureCABundleSecret

        # do not restart slcbridge if modifyin secrets of other pods
        [[ "$name" =~ master-nginx ]] || continue
        # do not restart any pods managed by slcbridge as it will make slcbridge unresponsive;
        # replacing cm of any managed pod is done on best effort - we cannot guarantee that the
        # pod is started and runs with a patched config file
        readarray -t pods <<<"$(oc get pods -n "$SLCB_NAMESPACE" -o json -l run=slcbridge | \
            jq -r '.items[] | select(.spec.volumes |
                any(.name == "master-nginx-conf")) | "pod/\(.metadata.name)"')"
        for ((i = $((${#pods[@]} - 1)); i >= 0; i--)); do
            [[ -z "$(tr -d '[:space:]' <<<"${pods[$i]}")" ]] && unset pods["$i"]
        done
        [[ "${#pods[@]}" == 0 ]] && continue
        log 'Restarting slcbridge pods ...'
        runOrLog oc delete -n "$namespace" --force --grace-period=0 "${pods[@]}" ||:
        ;;

    configmap/*)
        continue
        ;;

    service/*)
        IFS='#' read -r _ _type sessionAffinity _ <<<"${rest:-}"
        processSLCBService "$namespace" "$name" "$_type" "$sessionAffinity"

        # TODO: find out why SLC Bridge is not usable behind router
        # right now can be used only via the default NodePort (on-premise solution) or the
        # default LoadBalancer services
        continue

        desiredTermination="passthrough"
        evalBool EXPOSE_WITH_LETSENCRYPT && desiredTermination=reencrypt

        routes="$(oc get route -n "$namespace" -l "run=slcbridge" -o json)"
        for routeName in $(jq -r '.items[] | .metadata.name' <<<"$routes"); do
            IFS=: read -r termination toKind toName host <<<"$(jq -r '.items[] |
                select(.metadata.name == "'"$routeName"'") |
                    "\(.spec.tls.termination):\(.spec.to.kind):\(.spec.to.name):\(.spec.host)"' \
                                <<<"$routes")"
            if [[   "${termination:-}" == "$desiredTermination" && \
                    "${toKind:-}" == "Service" && \
                    "${toName:-}" == "$CLUSTERIP_SERVICE_NAME" && \
                    ( -z "${SLCB_ROUTE_HOSTNAME:-}" || \
                    "${host:-}" == "${SLCB_ROUTE_HOSTNAME}" ) ]];
            then
                log -n 'Service %s in namespace %s is already exposed at %s via route %s' \
                    "$CLUSTERIP_SERVICE_NAME" "$namespace" "${host:-}" "$routeName"
                log -d ' not exposing again ...'
                continue 2
            fi
        done

        args=( "$desiredTermination" --namespace="$namespace"
            --service="$CLUSTERIP_SERVICE_NAME"
            --dry-run -o json
            --insecure-policy=Redirect 
        )

        if [[ -z "${SLCB_ROUTE_HOSTNAME:-}" ]]; then
            domain="$(oc get -o jsonpath='{.spec.domain}' \
                ingresses.config.openshift.io/cluster)" ||:
            if [[ -z "${domain:-}" ]]; then
                log 'Failed to determine ingress'"'"' wildcard address!'
            else
                SLCB_ROUTE_HOSTNAME="slcb.$domain"
            fi
        fi
        if [[ -n "${SLCB_ROUTE_HOSTNAME:-}" ]]; then
            args+=( --hostname="${SLCB_ROUTE_HOSTNAME:-}" )
            log 'Exposing service %s in namespace %s at %s via route, ...' \
                "$CLUSTERIP_SERVICE_NAME" "$namespace" "$SLCB_ROUTE_HOSTNAME"
        else
            log 'Exposing service %s in namespace %s via route, ...' \
                "$CLUSTERIP_SERVICE_NAME" "$namespace"
        fi
        if [[ -n "${SLCB_ROUTE_HOSTNAME:-}" ]]; then
            readarray -t toDelete <<<"$(jq -r '.items[] | select(
                .metadata.name != "'"$CLUSTERIP_SERVICE_NAME"'" and
                .spec.host == "'"$SLCB_ROUTE_HOSTNAME"'") | .metadata.name' \
                    <<<"$routes")"
            for r in "${toDelete[@]}"; do
                [[ -z "$(tr -d '[:space:]' <<<"${r:-}")" ]] && continue
                log 'Deleting conflicting route "%s" having the same hostname "%s"!' \
                    "$r" "$SLCB_ROUTE_HOSTNAME"
                printf 'route/%s\n' "$r"
            done | parallel -- runOrLog oc delete -n "$namespace"
        fi

        if evalBool DRY_RUN; then
            runOrLog oc create route "${args[@]}"
        else
            object="$(oc create route "${args[@]}")"
            if evalBool EXPOSE_WITH_LETSENCRYPT; then
                object="$(jq '.metadata.annotations["kubernetes.io/tls-acme"] |= "true"' \
                    <<<"$object")"
            fi
            createOrReplace -n "$namespace" <<<"$object"
        fi
        ;;

    "secret/${CABUNDLE_SECRET_NAME:-}" | "secret/$VORA_CABUNDLE_SECRET_NAME")
        ensureCABundleSecret ||:
        ;&  # fallthrough to the next secret/$VORA_CABUNDLE_SECRET_NAME

    "secret/${REDHAT_REGISTRY_SECRET_NAME:-}")
        ensureRedHatRegistrySecret "$namespace"
        ensurePullsFromNamespace "$NAMESPACE" default "$SLCB_NAMESPACE"
        ensurePullsFromNamespace "$NAMESPACE" default "$SDI_NAMESPACE"
        ;;

    secret/*)
        log 'Ignoring secret "%s" in namespace %s.' "$name" "$namespace"
        ;;

    job/*checkpoint*)
        if ! evalBool INJECT_CABUNDLE; then
            continue
        fi
        IFS='#' read -r injectedKey _ <<<"${rest}"
        if ! injectCABundle "$namespace" "$kind" "$name" job-name="$name" \
                "${injectedKey:-""}"; then
            log 'WARNING: Failed to inject CA bundle into %s in namespace %s!' \
                "$resource" "$namespace"
        fi
        ;;

    job/*)
        #log 'Ignoring job "%s"' "$name"
        continue
        ;;

    *)
        log 'Got unexpected resource: name="%s", kind="%s", rest:"%s"' "${name:-}" "${kind:-}" \
            "${rest:-}"
        ;;

    esac
done 3< <(observe "${!gotmpls[@]}")

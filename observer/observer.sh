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

readonly CABUNDLE_VOLUME_NAME="sdi-observer-cabundle"
readonly CABUNDLE_VOLUME_MOUNT_PATH="/mnt/sdi-observer/cabundle"
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

# VoraCluster cannot be observed by the regular mechanisms - need to pull the state manually
function _observeVoraCluster() {
    local spec
    local newSpec
    sleep 15
    while true; do
        newSpec="$(oc get vc/vora -o json)"
        local kind namespace rev
        IFS=: read -r kind rev namespace <<<"$(jq -r '[
            .kind, .metadata.resourceVersion, .metadata.namespace
        ] | join(":")' <<<"${newSpec}")"
        if [[ -z "${spec:-}" || \
                "$(jq -r '.metadata.resourceVersion' <<<"${spec}")" -lt "$rev" ]];
        then
            # generate an event only if updated or never checked before
            echo "${namespace} vora $kind/vora"
        fi
        spec="${newSpec}"
        sleep 35
    done
    return 0
}
export -f _observeVoraCluster

function _observe() {
    local kind="${1##*:}"
    if [[ "$kind" == "voracluster" ]]; then
        _observeVoraCluster
        return 0
    fi
    local args=( )
    if [[ "$1" =~ ^(.+):(.+)$ ]]; then
        args+=( -n "${BASH_REMATCH[1]}" --names="echo" --delete="echo" )
    fi
    local jobnumber="$2"
    local portnumber="$((11251 + jobnumber))"
    args+=( --listen-addr=":$portnumber" "$kind"  )
    if [[ "$(cut -d . -f 2 <<<"${OCP_CLIENT_VERSION:-}")" -lt 6 ]]; then
        args+=( --no-headers --output=gotemplate --argument )
    else
        args+=( --quiet --output=go-template --template )
    fi
    args+=( '{{.kind}}/{{.metadata.name}}' -- echo )
    exec oc observe "${args[@]}"
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
                "$containerIndex" "$name"
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
        # print (string kind)#((string nodeSelectorLabel)=(string nodeSelectorLabelValue),)*#
        '{{$ds.kind}}#'
        '{{if $ds.spec.template.spec.nodeSelector}}'
            '{{range $k, $v := $ds.spec.template.spec.nodeSelector}}'
                '{{$k}}={{$v}},'
            '{{end}}'
        '{{end}}'
        '#'
        '{{if eq .metadata.name "diagnostics-fluentd"}}'
            # ((int containerIndex):(string containerName):(bool unprivileged)
            #            :(int volumeindex):(string varlibdockercontainers volumehostpath)
            #            :(int volumeMount index):(string varlibdockercontainers volumeMount path)#)+
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
       $'{{end}}\n'
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

gotmplRoute=(
    $'{{.kind}}\n'
)

gotmplVoraCluster=(
    $'{{.kind}}\n'
)

# shellcheck disable=SC2016
gotmplNamespace=(
    '{{with $nm := .}}{{with $n := $nm.metadata.name}}'
        '{{if or (eq $n "'"$SLCB_NAMESPACE"'")'
            ' (or (eq $n "'"$SDI_NAMESPACE"'") (eq $n "datahub-system"))}}'
            # print (string kind)#(string value of node-selector annotation)?
            $'{{$nm.kind}}#'
            '{{range $k, $v := $nm.metadata.annotations}}'
                '{{if eq $k "openshift.io/node-selector"}}'
                    '{{$v}}'
                '{{end}}'
            $'{{end}}\n'
        '{{end}}'
    '{{end}}{{end}}'
)

# shellcheck disable=SC2016
gotmplService=(
    '{{with $s := .}}'
        '{{if eq $s.metadata.name "vsystem"}}'
            '{{with $comp := index $s.metadata.labels "datahub.sap.com/app-component"}}'
                '{{if (eq $comp "vsystem")}}'
                    # print (string kind)
                    $'{{$s.kind}}\n'
                '{{end}}'
            '{{end}}'
        '{{end}}'
    '{{end}}'
)

# shellcheck disable=SC2016
gotmplRole=(
    # print (string kind)#("workloads/finalizers:")?("update:")?
    $'{{.kind}}#'
    '{{range $i, $r := .rules}}'
        '{{range $j, $rs := $r.resources}}'
            '{{if eq $rs "workloads/finalizers"}}'
                '{{$rs}}:'
                '{{range $k, $v := $r.verbs}}'
                    '{{if eq $v "update"}}'
                        '{{$v}}:'
                    '{{end}}'
                '{{end}}'
            '{{end}}'
        '{{end}}'
    $'{{end}}\n'
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

# Defines all the resource types that shall be monitored accross different namespaces.
# The associated value is a go-template producing an output the will be passed to the observer
# loop.
declare -A gotmpls=(
    [":Namespace"]="$(join '' "${gotmplNamespace[@]}")"
    ["${SDI_NAMESPACE}:Deployment"]="$(join '' "${gotmplDeployment[@]}")"
    ["${SDI_NAMESPACE}:DaemonSet"]="$(join '' "${gotmplDaemonSet[@]}")"
    ["${SDI_NAMESPACE}:StatefulSet"]="$(join '' "${gotmplStatefulSet[@]}")"
    ["${SDI_NAMESPACE}:ConfigMap"]="$(join '' "${gotmplConfigMap[@]}")"
    ["${SDI_NAMESPACE}:Route"]="$(join '' "${gotmplRoute[@]}")"
    ["${SDI_NAMESPACE}:Service"]="$(join '' "${gotmplService[@]}")"
    ["${SDI_NAMESPACE}:Role"]="$(join '' "${gotmplRole[@]}")"
    ["${SDI_NAMESPACE}:VoraCluster"]="$(join '' "${gotmplVoraCluster[@]}")"
    ["${SLCB_NAMESPACE}:DaemonSet"]="$(join '' "${gotmplDaemonSet[@]}")"
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
    if [[ "${namespace}" == "*" ]]; then
        args+=( --all-namespaces )
    else
        args+=( -n "$namespace" )
    fi
    args+=( "${perm%%/*}" "${perm##*/}" )
    if ! oc auth can-i "${args[@]}" >/dev/null; then
        if [[ "${namespace}" != "*" ]]; then
            printf '%s:%s\n' "$namespace" "$perm"
        else
            printf '%s\n' "$perm"
        fi
    fi
}
export -f checkPerm

function checkPermissions() {
    declare -a lackingPermissions
    local perm
    local rc=0
    local toCheck=()
    for verb in get patch watch; do
        for resource in configmaps daemonsets deployments statefulsets jobs role route; do
            toCheck+=( "$verb/$resource" )
        done
    done
    toCheck+=(
        "*:get/nodes"
        "*:get/projects"
        get/secrets
        update/daemonsets
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
            readarray -t letsencryptKinds <<<"$(oc create "$DRUNARG" \
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
                SDI_REGISTRY_AUTHENTICATION="${SDI_REGISTRY_AUTHENTICATION:-}"
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

function normNodeSelector() {
    local ns="${1:-}"
    tr ',' '\n' <<<"$ns" | sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/\s*$//' | sort -u | \
        tr '\n' ',' | sed 's/,$//'
}

function applyNodeSelectorToDS() {
    local nm="$1"
    local name="$2"
    local newNodeSelector curNodeSelector
    newNodeSelector="$(normNodeSelector "${SDI_NODE_SELECTOR:-}")"
    if [[ -z "${newNodeSelector:-}" ]]; then
        return 0
    fi
    curNodeSelector="$(normNodeSelector "${3:-}")"
    if [[ "${newNodeSelector,,}" =~ ^removed?$ ]]; then
        if [[ -z "${curNodeSelector:-}" ]]; then
            return 0
        fi
        log 'Removing node selectors from daemonset/%s ...' "$name"
        runOrLog oc patch -n "$nm" "daemonset/$name" \
            -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
        return 0
    fi
    if [[ "${curNodeSelector}" == "${newNodeSelector}" ]]; then
        log 'The node selector of daemonset/%s is up to date ...' "$name"
        return 0
    fi
    if [[ -z "${curNodeSelector:-}" && \
            "$(cut -d . -f 2 <<<"${OCP_SERVER_VERSION:-}")" -ge 6 ]];
    then
        log 'Not setting node selector on daemonset/%s on OCP release ≥ 4.6 ...' "$name"
        return 0
    fi
    log 'Patching daemonset/%s to run its pods on nodes matching the node selector "%s" ...' \
        "$name" "$newNodeSelector"
    local labels=()
    readarray -t -d , labelitems <<<"${newNodeSelector}"
    for item in "${labelitems[@]}"; do
        if [[ -z "${item:-}" ]]; then
            continue
        fi
        IFS='=' read -r key value <<<"${item}"
        labels+=( '"'"$key"'":"'"${value:-}"'"' )
    done
    createOrReplace <<<"$(oc get -o json -n "$nm" "ds/$name" | \
        jq '.spec.template.spec.nodeSelector |= {'"$(join , "${labels[@]}")"'}')"
}

function getResourceSAPLabels() {
    jq -r '.metadata.labels as $labs |
        [$labs | keys[] | select(test("sap\\.com\\/")) | "\(.)=\($labs[.] | gsub("\\s+"; ""))"] |
        sort | join(",")'
}

function ensureVsystemRoute() {
    local remove
    remove="$(grep -E -i -q '^\s*(remove|delete)d?\s*$' <<<"${MANAGE_VSYSTEM_ROUTE:-}" && \
        printf 1 || printf 0)"
    if [[ "$remove" == 0 ]] && ! evalBool MANAGE_VSYSTEM_ROUTE; then
        return 0
    fi
    local routeSpec svcSpec secretSpec
    routeSpec="$(oc get -n "${SDI_NAMESPACE}" route/vsystem -o json)" ||:
    svcSpec="$(oc get -n "${SDI_NAMESPACE}" svc/vsystem -o json)" ||:
    secretSpec="$(oc get -n "${SDI_NAMESPACE}" "secret/$VORA_CABUNDLE_SECRET_NAME" -o json)" ||:

    # delete route
    if [[ -n "${routeSpec:-}" ]]; then
        local delete=0
        if [[ -z "${svcSpec:-}${secretSpec:-}" ]]; then
            log -n 'Removing vsystem route because either the vsystem service or ca-bundle secret'
            log -d ' does not exist'
            delete=1
        elif [[ "$remove" == 1 ]]; then
            log 'Removing vsystem route because as instructed...'
            delete=1
        fi
        if [[ "${delete:-0}" == 1 ]]; then
            runOrLog oc delete -n "${SDI_NAMESPACE}" route/vsystem
            return 0
        fi
    elif [[ "$remove" == 1 ]]; then
        return 0
    elif [[ -z "${svcSpec:-}" ]]; then
        log 'Not creating vsystem route for the missing vsystem service...'
        return 0
    fi

    # create or replace route
    local reason=""
    if [[ -z "${routeSpec:-}" ]]; then
        reason=removed
    else
        if [[ "$(jq -r '.spec.tls.destinationCACertificate' <<<"$routeSpec" | \
                tr -d '[:space:]\n')" != \
            "$(jq -r '.data["ca-bundle.pem"] | @base64d' <<<"${secretSpec}" | \
                tr -d '[:space:]\n')" ]]
        then
            reason=cert
        elif [[ "$(getResourceSAPLabels <<<"${routeSpec}")" != \
            "$(getResourceSAPLabels <<<"$svcSpec")" ]]
        then
            reason=label
        elif [[ -n  "${VSYSTEM_ROUTE_HOSTNAME:-}" && "${VSYSTEM_ROUTE_HOSTNAME:-}" != \
            "$(jq -r '.spec.host' <<<"${routeSpec:-}")" ]]
        then
            reason=hostname
        elif ! jq -r '(.metadata.annotations // {}) | keys[]' <<<"$routeSpec" | \
            grep -F -x -q haproxy.router.openshift.io/timeout || \
            (  evalBool EXPOSE_WITH_LETSENCRYPT \
            && ! jq -r '(.metadata.annotations // {}) | keys[]' <<<"$routeSpec" | \
                    grep -F -x -q "kubernetes.io/tls-acme=true" )
        then
            reason=annotation
        else 
            log "Route vsystem is up to date."
            return 0
        fi
    fi
    local suffix="" msg="" desc=""
    case "$reason" in
        removed)    msg='Creating vsystem route for vsystem service%s...';              ;;
        label)      desc="outdated labels";                                             ;;&
        annotation) desc="missing annotation";                                          ;;&
        cert)       desc="outdated or missing destination CA certificate";              ;;&
        hostname)   desc='hostname mismatch';                                           ;;&
        *)          msg="$(printf 'Replacing vsystem route%%s due to %s...' "$desc")";  ;;
    esac
    if [[ -n "${VSYSTEM_ROUTE_HOSTNAME:-}" ]]; then
        suffix="$(printf ' to be exposed at https://%s' "${VSYSTEM_ROUTE_HOSTNAME:-}")"
    fi
    log "$msg" "${suffix:-}"

    local args=() annotations=()
    args=( -n "${SDI_NAMESPACE}" "$DRUNARG" -o json
            "--service=vsystem" "--insecure-policy=Redirect" )
    if [[ -n "${VSYSTEM_ROUTE_HOSTNAME:-}" ]]; then
        args+=( "--hostname=${VSYSTEM_ROUTE_HOSTNAME:-}" )
    fi
    annotations=( "haproxy.router.openshift.io/timeout=2m")
    if evalBool EXPOSE_WITH_LETSENCRYPT; then
        annotations+=( "kubernetes.io/tls-acme=true" )
    fi
    jq -r '.data["ca-bundle.pem"] | @base64d' <<<"$secretSpec" >"$TMP/vsystem-ca-bundle.pem"
    createOrReplace -n "${SDI_NAMESPACE}" -f <<<"$(oc create route reencrypt "${args[@]}" \
          --dest-ca-cert="$TMP/vsystem-ca-bundle.pem" | \
      oc annotate --local -f - "${annotations[@]}" -o json)"
}


function ensureRoutes() {
    ensureVsystemRoute
}

function managePullSecret() {
    # Arguments:
    #  1. saSpec
    #  2. secretName
    #  3. link  - one of "link" or "unlink"
    local saSpec="$1"
    local secretName="$2"
    local link="$3"
    local present
    present="$(jq -r --arg secretName "$secretName" '(.imagePullSecrets // [])[] |
        .name // "" | select(. == $secretName) | "present"' <<<"$saSpec")"
    case "$present:$link" in
        present:link)
            log -n 'Secret %s already linked with the default service acount' "$secretName"
            log -d ' for image pulls, skipping ...'
            return 0
            ;;
        present:unlink)
            log 'Unlinking secret %s from the default service account ...' "$secretName"
            runOrLog oc secret unlink default "$secretName"
            ;;
        *:unlink)
            log -n 'Secret %s not linked with the default service acount' "$secretName"
            log -d ' for image pulls, skipping ...'
            ;;
        *:link)
            log 'Linking secret %s to the default service account ...' "$secretName"
            runOrLog oc secret link default "$secretName" --for=pull
            ;;
    esac
    return 0
}
export -f managePullSecret

function ensureRegistryPullSecret() {
    local slpSecretExists="${1:-}" #uid current currentSource bundleData key nm _name _uid
    local vcSecret
    vcSecret="$(oc get vc/vora -o jsonpath='{.spec.docker.imagePullSecret}')"
    declare -A secrets
    if [[ -n "${vcSecret:-}" ]]; then
        secrets["${vcSecret:-}"]="link"
    fi

    case "${slpSecretExists:-}" in
        0 | removed | no | 1 | exists | yes)
            ;;
        *)
            if doesResourceExist secret/slp-docker-registry-pull-secret; then
                slpSecretExists=exists
            else
                slpSecretExists=removed
            fi
            ;;
    esac

    case "${slpSecretExists:-}:${secrets[slp-docker-registry-pull-secret]:-}" in
        *:link)
            ;;
        0:* | removed:* | no:*)
            secrets[slp-docker-registry-pull-secret]="unlink"
            ;;
        1:* | exists:* | yes:*)
            secrets[slp-docker-registry-pull-secret]="link"
            ;;
    esac

    local secretName
    local saSpec
    saSpec="$(oc get sa default -o json)"
    for secretName in "${!secrets[@]}"; do
        if [[ -z "${secretName:-}" ]]; then
            continue
        fi
        managePullSecret "$saSpec" "$secretName" "${secrets[${secretName}]}" ||:
    done
}
export -f ensureRegistryPullSecret

_version='unknown'
function getObserverVersion() {
    local version
    if [[ "${_version:-unknown}" != "unknown" ]]; then
        printf '%s' "${_version}"
        return 0
    fi
    for d in "$(dirname "${BASH_SOURCE[0]}")" . /usr/local/share/sdi; do
        if [[ -e "$d/lib/metadata.json" ]]; then
            version="$(jq -r '.version' "$d/lib/metadata.json")" ||:
            break
        fi
    done
    if [[ "${version:-unknown}" != unknown ]]; then
        _version="$version"
        printf '%s' "$version"
        return 0
    fi

    version="${SDI_OBSERVER_VERSION:-unknown}"
    if [[ "${version}" != "unknown" ]]; then
        _version="$version"
        printf '%s' "$version"
        return 0
    fi

    # assume we are running in a pod
    version="$(oc label --list "pods/${HOSTNAME}" | sed -n 's,^sdi-observer/version=,,p')"
    if [[ -n "${version:-}" ]]; then
        _version="$version"
        printf '%s' "$version"
        return 0
    fi

    log 'Failed to determine SDI Observer'"'"'s version\n'
    printf 'unknown'
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

log 'Running SDI Observer version %s' "$(getObserverVersion)"
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
    if [[ "${name:-}" =~ .+/.+ ]]; then
        # unscoped (not-namespaced) resource produces just two columns:
        #   <name> <kind>/<name>
        resource="$name"
        name="${namespace:-}"
        kind="${resource%%/*}"
        namespace=""
    fi
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
    tmpl="${gotmpls["${namespace:-}:$kind"]:-}"
    if [[ -z "${tmpl:-}" ]]; then
        log 'WARNING: Could not find go-template for kind "%s" in namespace "%s"!' \
            "$kind" "${namespace:-}"
        continue
    fi
    deleted=0
    args=( "$resource" -o go-template="$tmpl" )
    if [[ -n "${namespace:-}" ]]; then
        args+=( -n "$namespace" )
    fi
    rc=0
    data="$(oc get "${args[@]}")" || rc=$?
    if [[ -z "${data:-}" ]]; then
        # no data produced by template means the object is not interesting
        [[ "$rc" == 0 ]] && continue
        case "${kind,,}" in
        "route" | "secret")
            if ! doesResourceExist -n "$namespace" "$resource"; then
                deleted=1
            else
                log 'Could not get any data for resource %s!' "$resource"
                continue
            fi
            ;;
        *)
            continue
            ;;
        esac
    else
        IFS='#' read -r _kind rest <<<"${data}"
        if [[ "$_kind" != "$kind" ]]; then
            printf 'Kinds do not match (%s != %s)! Something is terribly wrong!\n' "$kind" "$_kind"
            continue
        fi
    fi
    resource="${resource,,}"

    case "${resource}" in
    deployment/vflow* | deployment/pipeline-modeler*)
        patches=()
        registries=()
        vflowargs=()
        if evalBool MARK_REGISTRY_INSECURE; then
            if [[ "${REGISTRY:-}" ]]; then
                registries=( "$REGISTRY" )
            else
                readarray -t vflowargs <<<"$(oc get deploy -o go-template="${gotmplvflow}" "$name")"
                for arg in "${vflowargs[@]}"; do
                    if [[ "${arg:-}" =~ ^-registry=([^[:space:]]+) ]]; then
                        registries+=( "${BASH_REMATCH[1]}" )
                    fi
                done
            fi

            if [[ "${#registries[@]}" == 0 || "${#registries[0]}" == 0 ]]; then
                readarray -t registries <<<"$(getRegistries)"
            fi
        fi

        if evalBool MARK_REGISTRY_INSECURE && \
                    [[ "${#registries[@]}" -gt 0 && "${#registries[0]}" -gt 0 ]];
        then
            if  [[ "${#vflowargs[@]}" -lt 1 ]]; then
                readarray -t vflowargs <<<"$(oc get deploy -o go-template="${gotmplvflow}" "$name")"
            fi
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

        if [[ "${#patches[@]}" -gt 0 ]]; then
            runOrLog oc patch --type json -p "[$(join , "${patches[@]}")]" deploy "$name"
        fi
        ;&

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

    daemonset/diagnostics-fluentd)
        IFS='#' read -r nodeSelector _rest <<<"${rest:-}"
        applyNodeSelectorToDS "$namespace" "$name" "${nodeSelector:-}"
        IFS=: read -r index _ unprivileged _ hostPath volumeMountIndex mountPath <<<"${_rest:-}"
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

    daemonset/*)
        IFS='#' read -r nodeSelector _ <<<"${rest:-}"
        applyNodeSelectorToDS "$namespace" "$name" "${nodeSelector}"
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

    configmap/*)
        continue
        ;;

    service/vsystem | route/*)
        ensureRoutes ||:
        ;;

    "secret/${CABUNDLE_SECRET_NAME:-}" | "secret/$VORA_CABUNDLE_SECRET_NAME")
        ensureCABundleSecret ||:
        if [[ "$name" == "$VORA_CABUNDLE_SECRET_NAME" ]]; then
            ensureRoutes ||:
        fi
        ;&  # fallthrough to the next secret/$VORA_CABUNDLE_SECRET_NAME

    "secret/${REDHAT_REGISTRY_SECRET_NAME:-}")
        ensureRedHatRegistrySecret "$namespace"
        ensurePullsFromNamespace "$NAMESPACE" default "$SLCB_NAMESPACE"
        ensurePullsFromNamespace "$NAMESPACE" default "$SDI_NAMESPACE"
        ensureRoutes
        ;;

    secret/slp-docker-registry-pull-secret | voracluster/*)
        exists="unknown"
        if [[ "${kind,,}" == "secret" && "$deleted" == 1 ]]; then
            exists=removed
        fi
        ensureRegistryPullSecret "$exists"
        ;;

    "role/vora-vsystem-${SDI_NAMESPACE}")
        if [[ "${rest:-}" =~ (^|:)workloads/finalizers:update: ]]; then
            log 'vsystem can already update workloads/finalizers resource, skipping %s...' \
                "$resource"
            continue
        fi
        log 'Patching %s to permit vsystem to update workloads/finalizers resource...' \
            "$resource"
        oc get -o json "$resource" | jq '.rules |= [
            .[]|select(.resources[0] != "workloads/finalizers")
        ] + [{
          "apiGroups": ["vsystem.datahub.sap.com"],
          "resources": ["workloads/finalizers"],
          "verbs": ["update"]
        }]' | createOrReplace
        ;;

    role/*)
        ;;

    secret/*)
        log 'Ignoring secret "%s" in namespace %s.' "$name" "$namespace"
        ;;

    namespace/*)
        if [[ "$name" != "$SDI_NAMESPACE" && "$name" != "$SLCB_NAMESPACE" && \
                "$name" != "datahub-system" ]];
        then
            continue
        fi
        newNodeSelector="$(normNodeSelector "${SDI_NODE_SELECTOR:-}")"
        if [[ -z "${newNodeSelector:-}" ]]; then
            continue
        fi
        curNodeSelector="$(normNodeSelector "${rest:-}")"
        if [[ "${newNodeSelector,,}" =~ ^removed?$ ]]; then
            if [[ -z "${curNodeSelector:-}" ]]; then
                continue
            fi
            log 'Removing node selectors from %s ...' "$resource"
            runOrLog oc annotate "$resource" openshift.io/node-selector-
            continue
        fi
        if [[ "${curNodeSelector}" == "${newNodeSelector}" ]]; then
            log 'The node selector of %s is up to date ...' "$resource"
            continue
        fi
        log 'Patching %s to run on nodes matching the node selector "%s" ...' \
            "$resource" "$newNodeSelector"
        if [[ "${rest:-}" != "${SDI_NODE_SELECTOR:-}"  ]]; then
            runOrLog oc annotate --overwrite "$resource" "openshift.io/node-selector=$newNodeSelector"
        fi
        ;;

    *)
        log 'Got unexpected resource: name="%s", kind="%s", rest:"%s"' "${name:-}" "${kind:-}" \
            "${rest:-}"
        ;;

    esac
done 3< <(observe "${!gotmpls[@]}")

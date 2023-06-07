#!/usr/bin/env bash

set -xeuo pipefail
IFS=$'\n\t'

for d in "$(dirname "${BASH_SOURCE[0]}")/.." . .. /usr/local/share/sdi; do
    if [[ -e "$d/lib/common.sh" ]]; then
        eval "source '$d/lib/common.sh'"
    fi
done
if [[ "${_SDI_LIB_SOURCED:-0}" == 0 ]]; then
    printf 'FATAL: failed to source lib/common.sh!\n' >&2
    exit 1
fi
common_init

readonly VORA_CABUNDLE_SECRET_NAME="ca-bundle.pem"
readonly VREP_EXPORTS_VOLUME_OBSOLETE_NAMES='["exports", "exports-volume"]'
readonly VREP_EXPORTS_VOLUME_NAME="exports-mask"
readonly VREP_EXPORTS_VOLUME_SIZE="500Mi"
readonly FLUENTD_DOCKER_VOLUME_NAME="varlibdockercontainers"
# number of seconds to sleep between the checks for a SDI custom resource definition
readonly SDI_CRD_CHECK_PERIOD="35"
export SDI_CRD_CHECK_PERIOD

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
function _observeSdiCrd() {
    local nm="${1:-}"
    local crdname="$2"
    # key is in format namespace/name
    declare -A revisions=()
    local def
    local ocArgs=( -o json )
    if [[ -n "${nm:-}" && "$nm" == "*" ]]; then
        ocArgs+=( --all-namespaces )
    elif [[ -n "${nm:-}" ]]; then
        ocArgs+=( --namespace="$nm" )
    fi
    sleep "$((5 + RANDOM % 10))"
    while true; do
        def="$(oc get "${ocArgs[@]}" "$crdname" ||:)"
        local kind namespace rev name crs=()
        readarray -t crs <<<"$(jq -r '.items[] | [
            .kind, .metadata.resourceVersion, (.metadata.namespace // ""), .metadata.name
        ] | join(":")' <<<"${def:-}" ||:)"
        unset def
        if [[ "${#crs[@]}" == 0 || ( "${#crs[@]}" == 1 && "${crs[0]}" == '' ) ]]; then
            sleep "$SDI_CRD_CHECK_PERIOD"
            continue
        fi

        for ((i=0; i < "${#crs[@]}"; i++)); do
            IFS=: read -r kind rev namespace name <<<"${crs[$i]}"
            if [[ -z "${kind:-}" || -z "${name:-}" ]]; then
                continue
            fi
            if [[ ( -z "${revisions["${namespace:-}/${name:-}"]:-}" || \
                    "${revisions["${namespace:-}/$name"]}" -lt "$rev" ) ]];
            then
                # generate an event only if updated or never checked before
                echo "${namespace} $name $kind/$name"
            fi
            revisions["${namespace:-}/$name"]="$rev"
        done
        sleep "$SDI_CRD_CHECK_PERIOD"
    done
    return 0
}
export -f _observeSdiCrd

function _observe() {
    local kind="${1##*:}"
    if [[ "$kind" =~ ^(([^:]*):)?((voracluster|datahub).*) ]]; then
        _observeSdiCrd "${BASH_REMATCH[2]:-}" "${BASH_REMATCH[3]}"
        return 0
    fi
    local args=( )
    if [[ "$1" =~ ^(.+):(.+)$ ]]; then
        args+=( --namespace="${BASH_REMATCH[1]}" --names="echo" --delete="echo" )
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

if [[ -z "${SLCB_NAMESPACE:-}" ]]; then
    export SLCB_NAMESPACE=sap-slcbridge
fi

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
        '{{if eq $ds.metadata.name "diagnostics-fluentd"}}'
            # (string appVersion):(int containerIndex):(string containerName)
            #       :(bool unprivileged)
            '{{range $k, $v := $ds.metadata.labels}}'
                '{{if eq $k "datahub.sap.com/app-version"}}'
                    '{{$v}}:'
                '{{end}}'
            '{{end}}'
            '{{range $i, $c := $ds.spec.template.spec.containers}}'
                '{{if eq $c.name "diagnostics-fluentd"}}'
                    '{{$i}}:{{$c.name}}:{{not $c.securityContext.privileged}}'
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
            #       (:(string volumeMountName)[%(string claimVolumeSize)][@(string volumeJson)])*)+#
            '{{$ss.kind}}#'
            '{{range $i, $c := $ss.spec.template.spec.containers}}'
                '{{if eq $c.name "vsystem-vrep"}}'
                    '{{$i}}'
                    '{{range $vmi, $vm := $c.volumeMounts}}'
                        '{{if eq $vm.mountPath "/exports"}}'
                            ':{{$vm.name}}'
                            '{{range $vcti, $vct := $ss.spec.volumeClaimTemplates}}'
                                '{{if eq $vct.metadata.name $vm.name}}'
                                    '%{{$vct.spec.resources.requests.storage}}'
                                '{{end}}'
                            '{{end}}'
                            '{{range $svi, $sv := $ss.spec.template.spec.volumes}}'
                                '{{if eq $sv.name $vm.name}}'
                                    '@{{js $sv}}'
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

# SDI CRDs
gotmplDatahub=(     $'{{.kind}}\n' )
gotmplVoraCluster=( $'{{.kind}}\n' )

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
        '{{if eq $s.metadata.name "slcbridgebase-service"}}'
            '{{with $app := index $s.metadata.labels "app"}}'
                '{{if (eq $app "slcbridge")}}'
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
    if [[ -z "${CABUNDLE_SECRET_NAMESPACE:-}" && "${CABUNDLE_SECRET_NAME:-}" =~ ^(.+)/ ]]; then
        CABUNDLE_SECRET_NAMESPACE="${BASH_REMATCH[1]}"
    fi
    CABUNDLE_SECRET_NAME="${CABUNDLE_SECRET_NAME##*/}"
    CABUNDLE_SECRET_NAMESPACE="${CABUNDLE_SECRET_NAMESPACE:-$NAMESPACE}"
    gotmplSecret=(
        '{{if or (and (eq .metadata.name "'"$CABUNDLE_SECRET_NAME"'")'
                    ' (eq .metadata.namespace "'"$CABUNDLE_SECRET_NAMESPACE"'"))'
               ' (or (eq .metadata.name "'"${REDHAT_REGISTRY_SECRET_NAME:-redhat-registry-secret-name}"'")'
                   ' (and (eq .metadata.name "'"${SDI_CABUNDLE_SECRET_NAME}"'")'
                        ' (eq .metadata.namespace "'"$SDI_NAMESPACE"'")))}}'
            $'{{.kind}}#{{.metadata.uid}}#{{.metadata.resourceVersion}}\n'
        '{{end}}'
    )
    export CABUNDLE_SECRET_NAMESPACE CABUNDLE_SECRET_NAME INJECT_CABUNDLE
fi

# Defines all the resource types that shall be monitored across different namespaces.
# The associated value is a go-template producing an output the will be passed to the observer
# loop.
declare -A gotmpls=(
    [":Namespace"]="$(join '' "${gotmplNamespace[@]}")"
    ["${SDI_NAMESPACE}:DaemonSet"]="$(join '' "${gotmplDaemonSet[@]}")"
    ["${SDI_NAMESPACE}:StatefulSet"]="$(join '' "${gotmplStatefulSet[@]}")"
    ["${SDI_NAMESPACE}:ConfigMap"]="$(join '' "${gotmplConfigMap[@]}")"
    ["${SDI_NAMESPACE}:Route"]="$(join '' "${gotmplRoute[@]}")"
    ["${SDI_NAMESPACE}:Service"]="$(join '' "${gotmplService[@]}")"
    ["${SDI_NAMESPACE}:Role"]="$(join '' "${gotmplRole[@]}")"
    ["${SDI_NAMESPACE}:VoraCluster"]="$(join '' "${gotmplVoraCluster[@]}")"
    ["${SDI_NAMESPACE}:DataHub"]="$(join '' "${gotmplDatahub[@]}")"
    ["${SLCB_NAMESPACE}:Route"]="$(join '' "${gotmplRoute[@]}")"
    ["${SLCB_NAMESPACE}:Service"]="$(join '' "${gotmplService[@]}")"
    ["${SLCB_NAMESPACE}:DaemonSet"]="$(join '' "${gotmplDaemonSet[@]}")"
)

if evalBool INJECT_CABUNDLE; then
    gotmpls["${CABUNDLE_SECRET_NAMESPACE}:Secret"]="$(join '' "${gotmplSecret[@]}")"
    gotmpls["${SDI_NAMESPACE}:Secret"]="$(join '' "${gotmplSecret[@]}")"
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
    local object="${perm##*/}"
    if [[ "${object,,}" == "voraclusters" ]] && \
                ! oc get crd -o jsonpath='{.metadata.name}' \
                    "voraclusters.sap.com" > /dev/null 2>&1;
    then
        log '%s custom resource definition does not exist yet, skipping the check...' \
            "voraclusters.sap.com"
        return 0
    fi
    args+=( "${perm%%/*}" "$object" )
    if ! oc auth can-i "${args[@]}" >/dev/null; then
        if [[ "${namespace}" != "*" ]]; then
            printf '%s:%s\n' "$namespace" "$perm"
        else
            printf '%s\n' "$perm"
        fi
    fi
}
export -f checkPerm

function waitForSDINamespace() {
    if oc get project/"${SDI_NAMESPACE:-}" >/dev/null 2>&1; then
        return 0
    fi

    log 'Waiting for namespace "%s" to be created...' "$SDI_NAMESPACE"
    local args+=( --names="echo" --delete="echo" )
    args+=( "namespace"  )
    if [[ "$(cut -d . -f 2 <<<"${OCP_CLIENT_VERSION:-}")" -lt 6 ]]; then
        args+=( --no-headers --output=gotemplate --argument )
    else
        args+=( --quiet --output=go-template --template )
    fi
    args+=( '{{.kind}}/{{.metadata.name}}' -- echo )
    oc observe "${args[@]}" | while IFS=' ' read -r _ name _; do
        if [[ "${name#*/}" == "${SDI_NAMESPACE}" ]]; then
            return 0
        fi
    done ||:
}

function checkPermissions() {
    declare -a lackingPermissions
    local perm
    local rc=0
    local toCheck=()
    for verb in get patch watch; do
        for resource in configmaps daemonsets statefulsets jobs role route; do
            toCheck+=( "$verb/$resource" )
        done
    done
    toCheck+=(
        "*:get/nodes"
        "*:get/projects"
        get/secrets
        update/daemonsets
        get/voraclusters
    )
    if [[ -n "${CABUNDLE_SECRET_NAMESPACE:-}" ]]; then
        toCheck+=( "${CABUNDLE_SECRET_NAMESPACE:-}:get/secrets" )
    fi

    local nmprefix=""
    [[ -n "${NAMESPACE:-}" ]] && nmprefix="${NAMESPACE:-}:"
    local tmplParams=( NAMESPACE="${NAMESPACE:-foo}" )
    if [[ "${FLAVOUR:-ubi-build}" == ubi-build ]]; then
        tmplParams+=( REDHAT_REGISTRY_SECRET_NAME=foo )
    fi
    if evalBool DEPLOY_SDI_REGISTRY; then
        declare -a registryKinds=()
        readarray -t registryKinds <<<"$(oc process "${tmplParams[@]}" \
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
        SDI_OBSERVER_GIT_REVISION="${SDI_OBSERVER_GIT_REVISION:-master}"
        SDI_OBSERVER_REPOSITORY="${SDI_OBSERVER_REPOSITORY:-https://github.com/redhat-sap/sap-data-intelligence}"
    )

    if [[ "${FLAVOUR:-ubi-build}" == custom-build ]]; then
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

# Expects k8s object json on its stdin.
# Returns a comma separated sorted list of key=value label pairs.
function getResourceSAPLabels() {
    local metadataPrefixPath="${1:-}"
    jq -r '('"${metadataPrefixPath:-}"'.metadata.labels // {}) as $labs |
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
    local routeDef svcDef secretDef
    routeDef="$(oc get -n "${SDI_NAMESPACE}" route/vsystem -o json)" ||:
    svcDef="$(oc get -n "${SDI_NAMESPACE}" svc/vsystem -o json)" ||:
    secretDef="$(oc get -n "${SDI_NAMESPACE}" "secret/$VORA_CABUNDLE_SECRET_NAME" -o json)" ||:

    # delete route
    if [[ -n "${routeDef:-}" ]]; then
        local delete=0
        if [[ -z "${svcDef:-}${secretDef:-}" ]]; then
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
    elif [[ -z "${svcDef:-}" ]]; then
        log 'Not creating vsystem route for the missing vsystem service...'
        return 0
    fi

    # create or replace route
    local reason=""
    if [[ -z "${routeDef:-}" ]]; then
        reason=removed
    else
        if [[ "$(jq -r '.spec.tls.destinationCACertificate' <<<"$routeDef" | \
                tr -d '[:space:]\n')" != \
            "$(jq -r '.data["ca-bundle.pem"] | @base64d' <<<"${secretDef}" | \
                tr -d '[:space:]\n')" ]]
        then
            reason=cert
        elif [[ "$(getResourceSAPLabels <<<"${routeDef}")" != \
            "$(getResourceSAPLabels <<<"$svcDef")" ]]
        then
            reason=label
        elif [[ -n  "${VSYSTEM_ROUTE_HOSTNAME:-}" && "${VSYSTEM_ROUTE_HOSTNAME:-}" != \
            "$(jq -r '.spec.host' <<<"${routeDef:-}")" ]]
        then
            reason=hostname
        elif ! jq -r '(.metadata.annotations // {}) | keys[]' <<<"$routeDef" | \
            grep -F -x -q haproxy.router.openshift.io/timeout || \
            (  evalBool EXPOSE_WITH_LETSENCRYPT \
            && ! jq -r '(.metadata.annotations // {}) | keys[]' <<<"$routeDef" | \
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
    jq -r '.data["ca-bundle.pem"] | @base64d' <<<"$secretDef" >"$TMP/vsystem-ca-bundle.pem"
    createOrReplace -n "${SDI_NAMESPACE}" -f <<<"$(oc create route reencrypt "${args[@]}" \
          --dest-ca-cert="$TMP/vsystem-ca-bundle.pem" | \
      oc annotate --local -f - "${annotations[@]}" -o json)"
}


function ensureSlcbRoute() {
    local remove
    remove="$(grep -E -i -q '^\s*(remove|delete)d?\s*$' <<<"${MANAGE_SLCB_ROUTE:-}" && \
        printf 1 || printf 0)"
    if [[ "$remove" == 0 ]] && ! evalBool MANAGE_SLCB_ROUTE; then
        return 0
    fi
    local routeDef svcDef
    routeDef="$(oc get -n "${SLCB_NAMESPACE}" route/sap-slcbridge -o json)" ||:
    svcDef="$(oc get -n "${SLCB_NAMESPACE}" svc/slcbridgebase-service -o json)" ||:

    # delete route
    if [[ -n "${routeDef:-}" ]]; then
        local delete=0
        if [[ -z "${svcDef:-}" ]]; then
            log 'Removing slcb route because the slcb service does not exist'
            delete=1
        elif [[ "$remove" == 1 ]]; then
            log 'Removing slcb route because as instructed...'
            delete=1
        fi
        if [[ "${delete:-0}" == 1 ]]; then
            runOrLog oc delete -n "${SLCB_NAMESPACE}" route/sap-slcbridge
            return 0
        fi
    elif [[ "$remove" == 1 ]]; then
        return 0
    elif [[ -z "${svcDef:-}" ]]; then
        log 'Not creating slcb route for the missing slcbridgebase-service ...'
        return 0
    fi

    if [[ -z "${SLCB_ROUTE_HOSTNAME:-}" ]]; then
        local domain
        domain="$(oc get ingresses.config.openshift.io/cluster -o jsonpath='{.spec.domain}' ||:)"
        if [[ -z "${domain:-}" ]]; then
            log -n 'WARNING: Failed to determine cluster apps domain,'
            log -d ' defaulting to the default route name.'
        else
            SLCB_ROUTE_HOSTNAME="${SLCB_NAMESPACE}.$domain"
            log 'Defaulting slcb route hostname to: %s' "${SLCB_ROUTE_HOSTNAME}"
        fi
    fi

    # create or replace route
    local reason=""
    if [[ -z "${routeDef:-}" ]]; then
        reason=removed
    else
        if [[ "$(getResourceSAPLabels <<<"${routeDef}")" != \
            "$(getResourceSAPLabels <<<"$svcDef")" ]]
        then
            reason=label
        elif [[ -n "${SLCB_ROUTE_HOSTNAME:-}" && "${SLCB_ROUTE_HOSTNAME:-}" != \
            "$(jq -r '.spec.host' <<<"${routeDef:-}")" ]]
        then
            reason=hostname
        elif ! jq -r '(.metadata.annotations // {}) | keys[]' <<<"$routeDef" | \
            grep -F -x -q haproxy.router.openshift.io/timeout;
        then
            reason=annotation
        else
            log "Route sap-slcbridge is up to date."
            return 0
        fi
    fi

    local suffix="" msg="" desc=""
    case "$reason" in
        removed)    msg='Creating sap-slcbridge route for slcbridgebase-service service%s...';              ;;
        label)      desc="outdated labels";                                             ;;&
        annotation) desc="missing annotation";                                          ;;&
        hostname)   desc='hostname mismatch';                                           ;;&
        *)          msg="$(printf 'Replacing sap-slcbridge route%%s due to %s...' "$desc")";  ;;
    esac
    if [[ -n "${SLCB_ROUTE_HOSTNAME:-}" ]]; then
        suffix="$(printf ' to be exposed at https://%s' "${SLCB_ROUTE_HOSTNAME:-}")"
    fi
    log "$msg" "${suffix:-}"

    local args=() annotations=()
    args=( -n "${SLCB_NAMESPACE}" "$DRUNARG" -o json
            "--service=slcbridgebase-service" "--insecure-policy=Redirect" )
    if [[ -n "${SLCB_ROUTE_HOSTNAME:-}" ]]; then
        args+=( "--hostname=${SLCB_ROUTE_HOSTNAME:-}" )
    fi
    annotations=( "haproxy.router.openshift.io/timeout=10m")
    createOrReplace -n "${SLCB_NAMESPACE}" -f <<<"$(oc create route passthrough sap-slcbridge \
        "${args[@]}" | oc annotate --local -f - "${annotations[@]}" -o json)"
}


# 3.1.49 chart yaml default values
#    fluentd:
#
#      enabled: true
#
#      # The Docker log directory to mount into Fluentd Pod
#      # If omitted or empty string, no extra log directory is mounted.
#      # varlibdockercontainers: "/var/lib/docker/containers"
#      varlibdockercontainers: "/var/lib/docker/containers"
#
#      # The time format expected by the log driver
#      # logDriverTimeFormat: '%Y-%m-%dT%H:%M:%S.%NZ'
#
#      # The log driver regex that is used to parse the log
#      # logDriverExpression: /^(?<time>.+) (?<stream>stdout|stderr)( (?<logtag>.))? (?<log>.*)$/
#
#      # collectLogs: false
function patchDiagnosticsFluentd() {
    local nm="$1"
    local name="$2"
    local appVersion="$3"
    local unprivileged="$4"
    local jqpatches=()
    local jqargs=( -r )

    if [[ "$unprivileged" == "true" ]]; then
        log 'Patching daemonset/%s to make its pods privileged ...' "$name"
        jqpatches+=( ' .spec.template.spec.containers |= [.[] |
            if .name == "diagnostics-fluentd" then
                .securityContext.privileged |= true
            else . end] ' )
    else
        log 'Containers in the daemonset/%s are already privileged.' "$name"
    fi

    local def
    def="$(oc get -o json -n "$nm" ds/"$name")"

    # fluentd already mounts /var/log/containers and /var/log/pods host paths, thus remove any
    # /var/lib/docker volumes
    if [[ "$(jq --arg vName "$FLUENTD_DOCKER_VOLUME_NAME" '.spec.template.spec as $s |
            def inspectVMs($cs): [(($cs // [])[] | (.volumeMounts // []))[] |
                select(.name == $vName) | true];
            [$s.volumes[] | select((.name == $vName)
                or ((.hostPath.path // "") | test("^/var/lib/docker"))) | true] +
            inspectVMs($s.containers) + inspectVMs($s.initContainers // []) |
                any' <<<"$def")" == "true" ]];
    then
        log 'Removing %s volumes and /var/lib/docker hostPath volumes from the daemonset/%s ...' \
            "$FLUENTD_DOCKER_VOLUME_NAME" "$name"
        # shellcheck disable=SC2016
        jqpatches+=( ' . as $ds | $ds.spec.template.spec.volumes as $vs |
            [$vs[] | select((.name == $vName)
                    or ((.hostPath.path // "") | test("^/var/lib/docker"))) | .name] as $toDelete |
            $ds.spec.template.spec.volumes |= [.[] | select(
                    . as $v | $toDelete | all($v.name != .))] |
            def prune($c): c.volumeMounts |= [(. // [])[] | select(. as $vm | $toDelete |
                all($vm.name != .))];
            $ds | .spec.template.spec.containers |= [.[] | prune(.)] |
            .spec.template.spec.initContainers |= [(. // [])[] | prune(.)] |
            .spec.template.spec.volumes |= [.[] | select(.name as $vn |
                $toDelete | all($vn != .))] ' )
        jqargs+=( --arg vName "$FLUENTD_DOCKER_VOLUME_NAME" )
    else
        log -n 'DaemonSet %s does not have any references to /var/lib/docker' "$name"
        log -d ' host path, no need to patch.'
    fi

    [[ "${#jqpatches[@]}" == 0 ]] && return 0
    createOrReplace < <(jq "${jqargs[@]}" "$(join \| "${jqpatches[@]}")" <<<"$def")
}

function patchDiagnosticsFluentdConfig() {
    local nm="$1"
    local name="$2"
    local resource="cm/$name"
    local contents
    local currentLogParseType
    local newContents
    local yamlPatch

    contents="$(oc get "$resource" -o go-template='{{index .data "fluent.conf"}}')"
    if [[ -z "${contents:-}" ]]; then
        log "Failed to get contents of fluent.conf configuration file!"
        return 1
    fi
    currentLogParseType="$(sed -n '/<parse>/,/<\/parse>/s,^\s\+@type\s*\([^[:space:]]\+\).*,\1,p' <<<"${contents}")"
    if [[ -z "${currentLogParseType:-}" ]]; then
        log "Failed to determine the current log type parsing of fluentd pods!"
        return 1
    fi
    case "${currentLogParseType}" in
    "multi_format")
        return 0;   # shall support both json and text
        ;;
    "json")
        if [[ "$NODE_LOG_FORMAT" == json ]]; then
            log "Fluentd pods are already configured to parse json, not patching..."
            return 0
        fi
        ;;
    "regexp")
        if [[ "$NODE_LOG_FORMAT" == text ]]; then
            log "Fluentd pods are already configured to parse text, not patching..."
            return 0
        fi
        ;;
    esac

    local exprs=(
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

    log 'Patching configmap %s to support %s logging format on OCP 4...' \
        "$name" "$NODE_LOG_FORMAT"

    # shellcheck disable=SC2001
    yamlPatch="$(printf '%s\n' "data:" "    fluent.conf: |" \
        "$(sed 's/^/        /' <<<"${newContents}")")"
    runOrLog oc patch "$resource" -p "$yamlPatch"
    readarray -t pods <<<"$(oc get pods -l datahub.sap.com/app-component=fluentd -o name)"
    [[ "${#pods[@]}" == 0 ]] && return 0

    log 'Restarting fluentd pods ...'
    runOrLog oc delete --force --grace-period=0 "${pods[@]}" ||:
}


function ensureRoutes() {
    ensureVsystemRoute
    ensureSlcbRoute
}

function managePullSecret() {
    local saDef="$1"   # json of the service account that shall be (un)linked with the secret
    local secretName="$2"
    local link="$3"     # one of "link" or "unlink"
    local present
    present="$(jq -r --arg secretName "$secretName" '(.imagePullSecrets // [])[] |
        .name // "" | select(. == $secretName) | "present"' <<<"$saDef")"
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

function patchDataHub() {
    local nm="$1"
    # if empty, operate on all datahub instances
    local name="${2:-}"
    local datahubs
    local jqpatches=()
    local jqargs=( -r )
    datahubs="$(oc get -o json -n "$nm" datahubs.installers.datahub.sap.com)"
    dhNames="$(jq -r '[(.items // [])[] | .metadata.name] | if (. | length) > 1 then
        "datahubs/[\(. | join(", "))]"
    else if (. | length) == 1 then
        "datahub/\(.[0])"
    else
        empty
    end end' <<<"$datahubs")"
    if [[ -z "${dhNames:-}" ]]; then
        return 0
    fi
    if [[ -n "${name:-}" ]]; then
        local tmp
        tmp="$(jq --arg dhName "$name" '.items |= [.[] | select(.metadata.name == $dhName)]' \
            <<<"$datahubs")"
        datahubs="$tmp"
    fi

    if [[ "$(jq -r '[.items[] | .spec.vsystem.vRep.exportsMask // false] | all' \
            <<<"$datahubs")" != "true" ]];
    then
        log 'Patching %s to configure vsystem-vrep with %s volume ...' \
            "$dhNames" "$VREP_EXPORTS_VOLUME_NAME"
        jqpatches+=( '.items |= [.[] | .spec.vsystem.vRep.exportsMask |= true]' )
    else
        log 'No need to patch %s for vsystem-vrep volume, skipping ...' "$dhNames"
    fi

    if [[ "$(jq -r --arg vName "$FLUENTD_DOCKER_VOLUME_NAME" '[.items[] |
            .spec.diagnostic.fluentd."\($vName)" // ""] |
            all(. == "disabled")' <<<"$datahubs")" != "true" ]];
    then
        log 'Patching %s to remove /var/lib/docker volumes from ds/fluentd ...' "$dhNames"
        # shellcheck disable=SC2016
        jqpatches+=( '.items |= [.[] | .spec.diagnostic.fluentd."\($vName)" |= "disabled"]' )
        jqargs+=( --arg "vName" "$FLUENTD_DOCKER_VOLUME_NAME" )
    else
        log 'No need to patch datahubs for fluentd volume mounting, skipping ...'
    fi

    [[ "${#jqpatches[@]}" == 0 ]] && return 0
    createOrReplace < <(jq "${jqargs[@]}" "$(join \| "${jqpatches[@]}")" <<<"$datahubs")
}
export -f patchDataHub

function patchVsystemVrep() {
    local nm="$1"
    local stsDef newDef
    stsDef="$(oc get -o json -n "$nm" sts/vsystem-vrep)"
    newDef="$(jq --arg newVolumeName "$VREP_EXPORTS_VOLUME_NAME" \
            --argjson obsoleteNames "$VREP_EXPORTS_VOLUME_OBSOLETE_NAMES" \
            --arg claimVolumeSize "$VREP_EXPORTS_VOLUME_SIZE" \
        '.spec.volumeClaimTemplates |= [(. // [])[] |
            select(. as $vct | ($obsoleteNames | all(. != $vct.metadata.name)) or
            .spec.resources.requests.storage != $claimVolumeSize)] |
        .spec.template.spec.volumes |= ([(. // [])[] |
            select(.name != $newVolumeName)] + [{"name": $newVolumeName, "emptyDir": {}}]) |
        def mount($c): $c.volumeMounts |= ([(. // [])[] |
            select(.mountPath != "/exports")] +
            if ((. // []) | any(.mountPath == "/exports")) or
                ($c.name == "vsystem-vrep")
            then
                [{"mountPath": "/exports", "name": $newVolumeName}]
            else [] end);
        .spec.template.spec.containers |= [.[] | mount(.)] |
        .spec.template.spec.initContainers |= [(. // [])[] | mount(.)]' <<<"$stsDef")"

    log 'Patching sts/vsystem-vrep for %s volume...' "$VREP_EXPORTS_VOLUME_NAME"
    createOrReplace -f <<<"$newDef" ||:
}
export -f patchVsystemVrep

# maps namespace/stsName to podName:labels["controller-revision-hash"]
declare -A _graceDeletionAtteptedFor=()
# On OCP 4.8, statefulset continues to deploy a broken revision as a pod even though there is a
# newer and correct revision available. The old revisions need to be pruned so the new revision
# can be deployed.
function ensureLatestStatefulSetRevision() {
    local nm="$1"
    local stsName="$2"
    local updateRevision currentRevision def

    def="$(oc get -o json -n "$nm" sts/"$stsName")"
    IFS=: read -r updateRevision currentRevision < <(jq -r \
        '"\(.status.updateRevision):\(.status.currentRevision)"' <<<"$def")
    if [[ "${updateRevision:-}" == "${currentRevision:-}" || -z "${updateRevision:-}" ]]; then
        log 'Stateful %s has the updated revision running already.' "$stsName"
        return 0
    fi
    if [[ -n "$(oc get -o name -n "$nm" pod \
            -l "controller-revision-hash=${updateRevision}")" ]]; then
        # the new pod is being started
        log 'The pod of the updated revision of statefulset %s exists already.' "$stsName"
        return 0
    fi
    local podSelector="$(getResourceSAPLabels ".spec.template" <<<"$def")"
    if [[ -z "${podSelector:-}" ]]; then
        log 'Failed to determine pod label selector for statefulset %s, cannot delete its pods!' \
            "$stsName"
        return 1
    fi

    local toDelete=()
    readarray -t toDelete <<<"$(oc get pod -o json -n "$nm" \
        -l "$podSelector,controller-revision-hash!=$updateRevision" | jq -r \
        '.items[] | .metadata as $md | "\($md.name):\($md.labels["controller-revision-hash"] //
            $md.resourceVersion)"')"
    if [[ "${#toDelete[@]}" == 0 || ( "${#toDelete[@]}" == 1 && "${toDelete[0]}" == '' ) ]]; then
        log 'No outdated children pods of statefulset %s found.' "$stsName"
        return 0
    fi

    local pod name revision
    for pod in "${toDelete[@]}"; do
        if [[ -z "${pod:-}" ]]; then
            continue
        fi
        IFS=: read -r name revision <<<"$pod"
        if [[ "${_graceDeletionAtteptedFor["$nm/$stsName"]:-}" == "$pod" ]]; then
            log 'Force deleting outdated pod %s[revision=%s] of the statefulset %s ...' \
                "$name" "$revision" "$stsName"
            runOrLog oc delete -n "$nm" "pod/$name" --force --timeout=5s ||:
        else
            runOrLog oc delete -n "$nm" "pod/$name" --grace-period=10 --timeout=11s ||:
            _graceDeletionAtteptedFor["$nm/$stsName"]="$pod"
        fi
    done
}
export -f ensureLatestStatefulSetRevision

function ensureRegistryPullSecret() {
    # Motivation:
    #   Some DI backup jobs [1] running under the default service account do not have image pull
    #   secret set and as a result, OCP cannot pull their images from a registry requiring
    #   authentication.
    #   The secret for pulling images is created in the sdi namespace by SLC Bridge and is usually
    #   called "slp-docker-registry-pull-secret". The secret can be overridden by VoraCluster
    #   resource configuration.
    #   By linking the secret with the default service account, jobs will no longer fail on
    #   ImagePullBackoff.
    #   [1] e.g. default-*-backup-hana
    # Requires:
    #   get on VoraCluster and ServiceAccount resources in the sdi namespace
    # Triggered by:
    #   update of VoraCluster or presence of Secret/slp-docker-registry-pull-secret in the sdi
    #   namespace
    local slpSecretExists="${1:-}"  # one of "exists", "removed" or "unknown"
    local vcSecret
    vcSecret="$(oc get voracluster/vora -o jsonpath='{.spec.docker.imagePullSecret}' ||:)"
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
    local saDef
    saDef="$(oc get sa default -o json)"
    for secretName in "${!secrets[@]}"; do
        if [[ -z "${secretName:-}" ]]; then
            continue
        fi
        managePullSecret "$saDef" "$secretName" "${secrets[${secretName}]}" ||:
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

waitForSDINamespace
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
    daemonset/diagnostics-fluentd)
        IFS='#' read -r nodeSelector _rest <<<"${rest:-}"
        applyNodeSelectorToDS "$namespace" "$name" "${nodeSelector:-}"
        IFS=: read -r appVersion _ _ unprivileged <<<"${_rest:-}"
        patchDiagnosticsFluentd "$namespace" "$name" "$appVersion" "$unprivileged" ||:
        patchDataHub "$namespace" ||:
        ;;

    daemonset/*)
        IFS='#' read -r nodeSelector _ <<<"${rest:-}"
        applyNodeSelectorToDS "$namespace" "$name" "${nodeSelector}" ||:
        ;;

    statefulset/*)
        IFS=: read -r cindex vmName <<<"${rest:-}"
        if [[ "$vmName" =~ ([[:alnum:]_-]+)(%([^#:,/%@]~))?(@([^#@%]+))? && \
                -z "${BASH_REMATCH[3]:-}" && -n "${BASH_REMATCH[5]:-}" ]] &&
                grep -q emptyDir <<<"${BASH_REMATCH[5]:-}";
        then
            log 'StatefulSet vsystem-vrep already masks /exports, skipping ...'
        else
            patchVsystemVrep "$namespace" ||:
        fi
        patchDataHub "$namespace" ||:
        ensureLatestStatefulSetRevision "$namespace" "$name" ||:
        ;;

    configmap/diagnostics-fluentd-settings)
        patchDiagnosticsFluentdConfig "$namespace" "$name" ||:
        ;;

    configmap/*)
        continue
        ;;

    service/vsystem | service/slcbridgebase-service | route/*)
        ensureRoutes ||:
        ;;
 
    "secret/${CABUNDLE_SECRET_NAME:-}" | "secret/$VORA_CABUNDLE_SECRET_NAME")
        if [[ "$name" == "$VORA_CABUNDLE_SECRET_NAME" ]]; then
            ensureRoutes ||:
        fi
        ;&  # fallthrough to the next secret/$VORA_CABUNDLE_SECRET_NAME

    "secret/${SDI_CABUNDLE_SECRET_NAME}")
        ensureCABundleSecret ||:
        ;;

    "secret/${REDHAT_REGISTRY_SECRET_NAME:-}")
        ensureRedHatRegistrySecret "" "$NAMESPACE"
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

    datahub/*)
        patchDataHub "$namespace" "$name"
        ensureCABundleSecret ||:
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

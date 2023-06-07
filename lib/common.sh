#!/usr/bin/env bash

if [[ "${_SDI_LIB_SOURCED:-0}" == 1 ]]; then
    return 0
fi

# shellcheck disable=SC2034
readonly DEFAULT_LETSENCRYPT_REPOSITORY=file:///usr/local/share/openshift-acme
# shellcheck disable=SC2034
readonly LETSENCRYPT_DEPLOY_FILES=(
    deploy/specific-namespaces/{role,serviceaccount,deployment}.yaml
    # @environment@ shall be replaced by desired environment (either "live" or "staging")
    deploy/specific-namespaces/issuer-letsencrypt-@environment@.yaml
)
# shellcheck disable=SC2034
readonly DEFAULT_SDI_REGISTRY_HTPASSWD_SECRET_NAME="container-image-registry-htpasswd"

readonly DEFAULT_SOURCE_IMAGESTREAM_NAME=customsourceimage
readonly DEFAULT_SOURCE_IMAGESTREAM_TAG=latest
readonly DEFAULT_SOURCE_IMAGE="registry.centos.org/centos:8"

readonly SDI_REGISTRY_TEMPLATE_FILE_NAME=ocp-template.json
readonly SOURCE_KEY_ANNOTATION=source-secret-key

# shellcheck disable=SC2034
# the annotation represents a cabundle that has been successfully injected into the resource
#   the value is a triple joined by colons:
#     <secret-namespace>:<secret-name>:<secret-uid>
readonly CABUNDLE_INJECTED_ANNOTATION="sdi-observer-injected-cabundle"
# the annotation represents a desired cabundle to be injected into the resource; value is the same
# as for the injected annotation
readonly CABUNDLE_INJECT_ANNOTATION="sdi-observer-inject-cabundle"
readonly SDI_CABUNDLE_SECRET_NAME="cmcertificates"
readonly SDI_CABUNDLE_SECRET_FILE_NAME="cert"

function join() { local IFS="${1:-}"; shift; echo "$*"; }
export -f join

function matchDictEntries() {
    # Arguments:
    #  Attribute      - an path in object to a dictionary that shall be matched
    #                   e.g.: metadata.annotations
    #  key=value ...  - entries that must be included in the JSON object read from stdin
    # Result:
    #  The JSON object itself and exit code 0 if all the entries are included in the Attribute;
    #  empty string otherwise.
    local attribute="$1"
    shift
    local out
    out="$(jq '. as $o |
            if ['"$(join , "$(printf '"%s"' "$@")")"'] | [
                .[] | match("(.+)=(.+)") |
                        {"key": .captures[0].string, "value": .captures[1].string}
                ] | reduce .[] as $item ({}; . + {"\($item.key)": $item.value}) |
                    to_entries |
                    all((($o.'"$attribute"' // {})[.key] // "") == .value)
            then
                $o
            else
                ""
            end')"
    if [[ "$out" == '""' ]]; then
        return 1
    fi
    printf '%s' "$out"
}
export -f matchDictEntries

function doesResourceExist() {
    local cmd=oc args=( get )
    local matchLabels=() matchAnnotations=()
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
        -n)
            args+=( "-n" "$2" )
            shift 2
            ;;
        -l)
            matchLabels+=( "$2" )
            shift 2
            ;;
        -a)
            matchAnnotations+=( "$2" )
            shift 2
            ;;
        *)
            break
            ;;
        esac
    done

    if [[ "${#matchLabels[@]}${#matchAnnotations[@]}" == 00 ]]; then
        $cmd "${args[@]}" "$@" >/dev/null 2>&1
        return $?
    fi

    args+=( -o json )
    local contents
    contents="$($cmd "${args[@]}" "$@" 2>/dev/null)"
    if [[ -z "${contents:-}" ]]; then
        return 1
    fi

    if [[ "${#matchAnnotations[@]}" -gt 0 ]]; then
        matchDictEntries metadata.annotations "${matchAnnotations[@]}" >/dev/null \
            <<<"$contents" || return $?
    fi
                
    if [[ "${#matchLabels[@]}" -gt 0 ]]; then
        matchDictEntries metadata.labels "${matchLabels[@]}" >/dev/null \
            <<<"$contents" || return $?
    fi
    return 0
}
export -f doesResourceExist

function log() {
    local reenableDebug
    reenableDebug="$([[ "$-" =~ x ]] && printf '1' || printf '0')"
    { set +x; } >/dev/null 2>&1
    if [[ "$1" == -d ]]; then
        shift   # do not print date
    else
        date -R | tr '\n' ' ' >&2
    fi
    # no new line
    if [[ "$1" == -n ]]; then
        shift
    elif [[ "${1: -1}" != $'\n' ]]; then
        local fmt="${1:-}\n"
        shift
        # shellcheck disable=SC2059
        printf "$fmt" "$@" >&2
        if [[ "${reenableDebug}" == 1 ]]; then
            set -x
        fi
        return 0
    fi
    # shellcheck disable=SC2059
    printf "$@" >&2
    if [[ "${reenableDebug}" == 1 ]]; then
        set -x
    fi
}
export -f log

function evalBool() {
    local varName="$1"
    local default="${2:-}"
    eval 'local value="${'"$varName"':-}"'
    if [[ -z "${value:-}" ]]; then
        value="${default:-}"
    fi
    grep -q -i '^\s*\(y\(es\)\?\|true\|1\)\s*$' <<<"${value:-}"
}
export -f evalBool

DRY_RUN="${DRY_RUN:-false}"
export DRY_RUN
function runOrLog() {
    if evalBool DRY_RUN; then
        log -n '[DRY_RUN] Executing: '
        echo "$@"
    else
        "$@"
    fi
}
export -f runOrLog

TMP=""
_common_init_performed=0
function common_init() {
    if [[ "${_common_init_performed:-0}" == 1 ]]; then
        return 0
    fi
    trap common_cleanup EXIT
    TMP="$(mktemp -d)"
    for pth in "${KUBECONFIG:-}" "$HOME/.kube/config"; do
        if [[ -n "${pth:-}" && -f "$pth" && -r "$pth" ]]; then
            cp "${pth}" "$TMP/"
            KUBECONFIG="$TMP/$(basename "$pth")"
            export KUBECONFIG
            break
        fi
    done
    HOME="$TMP"    # so that oc can create $HOME/.kube/ directory
    export TMP HOME

    local version
    version="$(oc version --short 2>/dev/null || oc version)"
    OCP_SERVER_VERSION="$(sed -n 's/^\(\([sS]erver\|[kK]ubernetes\).*:\|[oO]pen[sS]hift\) v\?\([0-9]\+\.[0-9]\+\).*/\3/p' \
                        <<<"$version" | head -n 1)"
    OCP_CLIENT_VERSION="$(sed -n 's/^\([cC]lient.*:\|oc\) \(openshift-clients-\|v\|\)\([0-9]\+\.[0-9]\+\).*/\3/p' \
                        <<<"$version" | head -n 1)"
    # translate k8s 1.13 to ocp 4.1
    #               1.14 to ocp 4.2
    #               1.16 to ocp 4.3
    #               1.17 to ocp 4.4
    if [[ "${OCP_SERVER_VERSION:-}" =~ ^1\.([0-9]+)$ && "${BASH_REMATCH[1]}" -gt 14 ]]; then
        OCP_SERVER_VERSION="4.$((BASH_REMATCH[1] - 13))"
    elif [[ "${OCP_SERVER_VERSION:-}" =~ ^1\.([0-9]+)$ && "${BASH_REMATCH[1]}" -gt 12 ]]; then
        OCP_SERVER_VERSION="4.$((BASH_REMATCH[1] - 12))"
    fi
    if [[ -z "${OCP_CLIENT_VERSION:-}" ]]; then
        printf 'WARNING: Failed to determine oc client version!\n' >&2
    elif [[ -z "${OCP_SERVER_VERSION}" ]]; then 
        printf 'WARNING: Failed to determine k8s server version!\n' >&2
    elif [[ "${OCP_SERVER_VERSION}" != "${OCP_CLIENT_VERSION}" ]]; then
        printf 'WARNING: Client version != Server version (%s != %s).\n' "$OCP_CLIENT_VERSION" "$OCP_SERVER_VERSION" >&2
        printf '                 Please reinstantiate this template with the correct BASE_IMAGE_TAG parameter (e.g. v%s)."\n' >&2 \
            "$OCP_SERVER_VERSION"

        local serverMinor clientMinor
        serverMinor="$(cut -d . -f 2 <<<"$OCP_SERVER_VERSION")"
        clientMinor="$(cut -d . -f 2 <<<"$OCP_CLIENT_VERSION")"
        if [[ "$(bc <<<"define abs(i) { if (i < 0) return (-i); return (i); };
                    abs($serverMinor - $clientMinor)")" -gt 1 ]];
        then
            printf 'FATAL: The difference between minor versions of client and server is too big.\n' >&2
            printf 'Refusing to continue. Please reinstantiate the template with the correct' >&2
            printf ' OCP_MINOR_RELEASE!\n' >&2
            exit 1
        fi
    else
        printf "Server and client version: %s\n" "$OCP_SERVER_VERSION"
    fi
    if [[ ! "${OCP_SERVER_VERSION:-}" =~ ^4\. ]]; then
        printf 'FATAL: OpenShift server version other then 4.* is not supported!\n' >&2
        exit 1
    fi
    DRUNARG="--dry-run"
    if [[ "$(cut -d . -f 2 <<<"${OCP_CLIENT_VERSION}")" -ge 5 ]]; then
        DRUNARG="--dry-run=client"
    fi
    export OCP_SERVER_VERSION OCP_CLIENT_VERSION DRUNARG

    if [[ ! "${NODE_LOG_FORMAT:-}" =~ ^(text|json|)$ ]]; then
        printf 'FATAL: unrecognized NODE_LOG_FORMAT; "%s" is not one of "json" or "text"!' \
            "$NODE_LOG_FORMAT"
        exit 1
    fi
    if [[ -z "${NODE_LOG_FORMAT:-}" ]]; then
        if [[ "${OCP_SERVER_VERSION}" =~ ^3 ]]; then
            NODE_LOG_FORMAT=json
        else
            NODE_LOG_FORMAT=text
        fi

    fi
    export NODE_LOG_FORMAT

    # shellcheck disable=SC2015
    # Disable quotation remark according to `parallel --bibtex`:
    #    Academic tradition requires you to cite works you base your article on.
    #    If you use programs that use GNU Parallel to process data for an article in a
    #    scientific publication, please cite:
    # This is not going to be a part of scientific publication.
    PARALLEL_HOME="$TMP/.parallel"
    mkdir -p "$PARALLEL_HOME"
    touch "$PARALLEL_HOME/will-cite" || :
    export PARALLEL_HOME

    [[ -z "${NAMESPACE:-}" ]] && NAMESPACE="$(oc project -q)"
    export NAMESPACE

    if [[ -z "${SDI_NAMESPACE:-}" ]]; then
        SDI_NAMESPACE="$NAMESPACE"
    fi
    export SDI_NAMESPACE
    local var
    # shellcheck disable=SC2034
    for var in in REPLACE_SECRETS REPLACE_PERSISTENT_VOLUME_CLAIMS; do
        eval val='"${'"$var"':-}"'
        [[ -z "${val:-}" ]] && continue
        eval 'export '"$var"'="$val"'
    done

    if [[ -n "${REDHAT_REGISTRY_SECRET_NAMESPACE:-}" ]]; then
        REDHAT_REGISTRY_SECRET_NAME="${REDHAT_REGISTRY_SECRET_NAME##*/}"
    elif [[ "${REDHAT_REGISTRY_SECRET_NAME:-}" =~ ^([^/]+)/(.*) ]]; then
        REDHAT_REGISTRY_SECRET_NAME="${BASH_REMATCH[2]}"
        REDHAT_REGISTRY_SECRET_NAMESPACE="${BASH_REMATCH[1]}"
    else
        REDHAT_REGISTRY_SECRET_NAMESPACE="$NAMESPACE"
    fi
    export REDHAT_REGISTRY_SECRET_NAME REDHAT_REGISTRY_SECRET_NAMESPACE

    if [[ -z "${SOURCE_IMAGESTREAM_NAME:-}" ]]; then
        if [[ "${SOURCE_IMAGE_PULL_SPEC:-}" == "${DEFAULT_SOURCE_IMAGE}" ]]; then
            SOURCE_IMAGESTREAM_NAME=centos8
        fi
        SOURCE_IMAGESTREAM_NAME="${DEFAULT_SOURCE_IMAGESTREAM_NAME}"
    fi
    if [[ -z "${SOURCE_IMAGESTREAM_TAG:-}" ]]; then
        SOURCE_IMAGESTREAM_TAG="${DEFAULT_SOURCE_IMAGESTREAM_TAG}"
    fi
    export SOURCE_IMAGE_PULL_SPEC SOURCE_IMAGESTREAM_NAME SOURCE_IMAGESTREAM_TAG \
           SOURCE_IMAGE_REGISTRY_SECRET_NAME

    getFlavour >/dev/null
    if [[ "$FLAVOUR" == "ubi-prebuilt" && -z "${IMAGE_PULL_SPEC:-}" ]]; then
        IMAGE_PULL_SPEC="${DEFAULT_IMAGE_PULL_SPEC:-}"
    fi

    _common_init_performed=1
    export _common_init_performed
}

function convertObjectToJSON() {
    local input=/dev/fd/0
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
        -i)
            input="$2"
            shift 2
            ;;
        *)
            break
            ;;
        esac
    done
    local object arr=()
    mapfile -d $'\0' arr <"$input"
    object="${arr[0]:-}"
    if ! jq empty <<<"${object}" 2>/dev/null; then
        oc create "$DRUNARG" -f - -o json <<<"$object"
        return 0
    fi
    printf '%s' "$object"
}
export -f convertObjectToJSON

function _forceReplace() {
    local kind="$1"
    # shellcheck disable=SC2034
    local forceFlag="$2"
    local err="${3:-}"
    if ! grep -q 'AlreadyExists\|Conflict\|Forbidden\|field is immutable' <<<"${err:-}"; then
        return 1
    fi
    if [[ "${kind,,}" == job ]]; then
        return 0
    fi
    if ! evalBool forceFlag; then
        return 1
    fi
    case "${kind,,}" in
        secret)
            evalBool REPLACE_SECRETS
            ;;
        persistentvolumeclaim)
            evalBool REPLACE_PERSISTENT_VOLUME_CLAIMS
            ;;
    esac
}
export -f _forceReplace

function createOrReplace() {
    local object
    local rc=0
    local err force namespace action args=()
    local input=/dev/fd/0
    local overrideNamespace=0
    force="$(evalBool FORCE_REDEPLOY && printf true || printf false)"
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
        -f)
            # shellcheck disable=SC2034
            force=true
            shift
            ;;
        -n)
            namespace="$2"
            overrideNamespace=1
            shift 2
            ;;
        -i)
            input="$2"
            shift 2
            ;;
        *)
            break
            ;;
        esac
    done

    object="$(convertObjectToJSON -i "$input")"
    if [[ "$(jq 'has("items")' <<<"$object")" == "true" ]]; then
        local resources=() res kind name
        readarray -t resources <<<"$(jq -r '.items[] | "\(.kind)/\(.metadata.name)\n"' \
                <<<"$object")"
        local rc=0
        local childArgs=()
        "$force" && childArgs+=( "-f" )
        [[ "$overrideNamespace" == 1 ]] && childArgs+=( -n "$namespace" )
        for res in "${resources[@]}"; do
            [[ -z "${res:-}" ]] && continue
            IFS=/ read -r kind name <<<"$res"
            jq '.items[] | select(.kind == "'"$kind"'" and .metadata.name == "'"$name"'")' \
                <<<"$object" | createOrReplace "${childArgs[@]}" || rc=$?
        done
        return $rc
    fi

    if [[ -n "${namespace:-}" ]]; then
        object="$(jq '.metadata.namespace |= "'"$namespace"'"' <<<"$object")"
    fi

    local creator=""
    creator="$(jq -r '.metadata.labels["created-by"]' <<<"$object")" ||:

    IFS=: read -r namespace kind name < <(oc create "$DRUNARG" -f - -o \
        jsonpath=$'{.metadata.namespace}:{.kind}:{.metadata.name}\n' <<<"$object")
    namespace="${namespace:-$NAMESPACE}"
    [[ -z "${namespace:-}" ]] && namespace="$(oc project -q)"
    if evalBool DRY_RUN; then
        [[ -n "${namespace:-}" ]] && args=( -n "$namespace" )
        args+=( "${kind,,}" "$name" )
        action=Creating
        doesResourceExist "${args[@]}" && action=Replacing
        log '[DRY_RUN] %s %s/%s in namespace %s' "$action" "${kind,,}" \
            "$name" "${namespace:-UNKNOWN}"
        return 0
    fi
                
    err="$(oc create -f - <<<"$object" 2>&1 >/dev/null)" || rc=$?
    if [[ $rc == 0 ]]; then
        if [[ -n "${kind:-}" && -n "${name:-}" ]]; then
            log 'Created %s/%s in namespace %s' "${kind,,}" "$name" "${namespace:-UNKNOWN}"
        fi
        return 0
    fi
    originalCreator="$(oc label -n "$namespace" --list "$kind" "$name" | \
        sed -n 's/^created-by=\(.\+\)/\1/p')" 

    if [[ -n "${originalCreator:-}" && "${originalCreator}" != "${creator:-}" ]]; then
        log 'Not replacing %s/%s created by "%s" with a new object created by "%s".' \
            "$kind" "$name" "$originalCreator" "$creator"
        return 0
    fi
    args=( -f - )
    err="$(oc replace "${args[@]}" <<<"$object" 2>&1)" && rc=0 || rc=$?
    if [[ $rc == 0 ]] || ! _forceReplace "$kind" "$force" "${err:-}"; then
        printf '%s\n' "$err" >&2
        if [[ $rc != 0 ]] && ! grep -q 'Conflict\|Forbidden\|field is immutable' <<<"${err:-}";
        then
            return "$rc"
        fi
        return 0
    fi

    args+=( --force )
    err="$(oc replace "${args[@]}" <<<"$object" 2>&1)" && rc=0 || rc=$?
    printf '%s\n' "$err" >&2
    if [[ $rc != 0 ]] && ! grep -q 'Conflict\|Forbidden\|field is immutable' <<<"${err:-}"; then
        return "$rc"
    fi
    return 0
}
export -f createOrReplace

function ocApply() {
    local object
    local rc=0
    local namespace applyArgs=()
    local input=/dev/fd/0
    local overrideNamespace=0
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
        -n)
            namespace="$2"
            overrideNamespace=1
            shift 2
            ;;
        -i)
            input="$2"
            shift 2
            ;;
        *)
            break
            ;;
        esac
    done

    object="$(convertObjectToJSON -i "$input")"
    if [[ "$(jq 'has("items")' <<<"$object")" == "true" ]]; then
        local resources=() res kind name
        readarray -t resources <<<"$(jq -r '.items[] | "\(.kind)/\(.metadata.name)\n"' \
                <<<"$object")"
        local rc=0
        local childArgs=()
        [[ "$overrideNamespace" == 1 ]] && childArgs+=( -n "$namespace" )
        for res in "${resources[@]}"; do
            [[ -z "${res:-}" ]] && continue
            IFS=/ read -r kind name <<<"$res"
            jq '.items[] | select(.kind == "'"$kind"'" and .metadata.name == "'"$name"'")' \
                <<<"$object" | createOrReplace "${childArgs[@]}" || rc=$?
        done
        return $rc
    fi

    if [[ -n "${namespace:-}" ]]; then
        object="$(jq '.metadata.namespace |= "'"$namespace"'"' <<<"$object")"
    fi
    
    applyArgs=( -f - )
    if evalBool DRY_RUN; then
        applyArgs+=( "$DRUNARG" )
    fi
    oc apply "${applyArgs[@]}" <<<"$object" |& \
        grep -vF 'The missing annotation will be patched automatically.'
}
export -f ocApply

function trustfullyExposeService() {
    local serviceName="${1##*/}"; shift
    local routeType
    if [[ $# -gt 0 ]]; then
        routeType="${1:-reencrypt}"
        shift
    fi
    if ! [[ "$routeType" =~ ^(reencrypt|edge)$ ]]; then
        log 'ERROR: unsupported route type "%s". Cannot create.' "$routeType"
        return 1
    fi
    runOrLog oc create route "$routeType" --service "$serviceName" "$DRUNARG" "$@"
}

function isPathLocal() {
    [[ "${1:-}" =~ ^(file://|\./|/|~) ]]
}
export -f isPathLocal
    

function common_cleanup() {
    rm -rf "$TMP"
}

function isFlavourSatisfied() {
    case "$1" in
        ubi-build)
            [[ -n "${REDHAT_REGISTRY_SECRET_NAME:-}" ]]
            ;;
        ubi-prebuilt)
            [[ -n "${IMAGE_PULL_SPEC:-}" || -n "${DEFAULT_IMAGE_PULL_SPEC:-}" ]]
            ;;
        custom-build)
            [[ -n "${SOURCE_IMAGESTREAM_NAME:-}" && \
                "${SOURCE_IMAGESTREAM_TAG:-}" && -n "${SOURCE_IMAGE_PULL_SPEC:-}" ]]
            ;;
        *)
            log 'WARN: Unknown flavour "%s"!' "$1"
    esac
}

function getFlavour() {
    if [[ -z "${DEFAULT_FLAVOUR:-}" ]]; then
        DEFAULT_FLAVOUR="ubi-build"
        export DEFAULT_FLAVOUR
        readonly DEFAULT_FLAVOUR
    fi

    if [[ -z "${FLAVOUR:-}" ]]; then
        FLAVOUR="${DEFAULT_FLAVOUR}"
        if ! isFlavourSatisfied "${DEFAULT_FLAVOUR}"; then
            for f in custom-build ubi-build ubi-prebuilt; do
                if isFlavourSatisfied "$f"; then
                    FLAVOUR="${f}"
                    break
                fi
            done
        fi
        export FLAVOUR
    fi
    printf '%s' "$FLAVOUR"
}

function getRegistryTemplatePath() {
    local dirs=(
        "$(dirname "${BASH_SOURCE[0]}")/../registry"
        ./registry
        ../registry
        /usr/local/share/sdi/registry
        /usr/local/share/sap-data-intelligence/registry
    )
    local tmplfn="$SDI_REGISTRY_TEMPLATE_FILE_NAME"
    case "$(getFlavour)" in
        ubi-build)
            ;;
        ubi-prebuilt)
            tmplfn="ocp-prebuilt-image-template.json"
            ;;
        custom-build)
            tmplfn="ocp-custom-source-image-template.json"
            ;;
    esac

    for d in "${dirs[@]}"; do
        local pth="${d}/$tmplfn"
        if [[ -e "$pth" ]]; then
            printf '%s' "$pth"
            return 0
        fi
    done
    log 'WARNING: Could not determine path to %s' "$tmplfn"
    return 1
}
export -f getRegistryTemplatePath

export LETSENCRYPT_ENVIRONMENT="${LETSENCRYPT_ENVIRONMENT:-live}"

function mkSourceKeyAnnotation() {
    local namespace="$1"
    local name="$2"
    local uid="$3"
    local resourceVersion="$4"
    printf '%s=%s:%s:%s:%s' "$SOURCE_KEY_ANNOTATION" "$namespace" "$name" "$uid" "$resourceVersion"
}
export -f mkSourceKeyAnnotation

# shellcheck disable=SC2120
function ensurePullsFromNamespace() {
    local sourceNamespace="${1:-$NAMESPACE}"
    local saName="${2:-default}"
    local saNamespace="${3:-$SDI_NAMESPACE}"
    local secretName token
    if [[ "$sourceNamespace" == "$saNamespace" ]]; then
        return 0
    fi
    secretName="$(oc get -o json -n "$saNamespace" "sa/$saName" | \
        jq -r '.secrets[] | select(.name | test("token")).name')"

    if [ -z "$secretName" ]; then

        # Get all secrets in the namespace
        secrets=$(oc get secrets -n $saNamespace -o jsonpath='{.items[*].metadata.name}')

        # Iterate over the secrets
        for secret in $secrets; do
            # Get the annotation of the secret
            annotation=$(oc get secret $secret -n $saNamespace -o jsonpath='{.metadata.annotations.kubernetes\.io/service-account\.name}')

            # Check if the annotation matches the desired value
            if [[ "$annotation" == "default" ]]; then
                echo "Found secret with annotation 'kubernetes.io/service-account.name: default': $secret"

                # Perform any additional actions you need with the matching secret
                # For example, you can retrieve and display the token
                token=$(kubectl get secret $secret -n $saNamespace -o jsonpath='{.data.token}' | base64 --decode)
                echo "Token: $token"
                if [[ -z "${token:-}" ]]; then
                    log 'ERROR: failed to get a token of service account %s in namespace %s' \
                        "$saName" "$saNamespace"
                    return 1
                fi
                if oc --token="$token" auth can-i -n "$sourceNamespace" get \
                        imagestreams/layers >/dev/null
                then
                    log 'Service account %s in %s namespace can already pull images from %s namespace.' \
                        "$saName" "$saNamespace" "$sourceNamespace"
                    return 0
                fi
                # Exit the loop if you only want to find the first matching secret
                # break
            fi
        done
        log -n 'Granting privileges to the %s service account in %s namespace to pull' \
            "$saName" "$saNamespace"
        log -d ' images from %s namespace' "$sourceNamespace"
        runOrLog oc policy add-role-to-user \
            system:image-puller "system:serviceaccount:$saNamespace:$saName" \
            --namespace="$sourceNamespace"
    else
        token="$(oc get -n "$saNamespace" -o jsonpath='{.data.token}' "secret/$secretName" | \
                base64 -d)"
        if [[ -z "${token:-}" ]]; then
            log 'ERROR: failed to get a token of service account %s in namespace %s' \
                "$saName" "$saNamespace"
            return 1
        fi
        if oc --token="$token" auth can-i -n "$sourceNamespace" get \
                imagestreams/layers >/dev/null
        then
            log 'Service account %s in %s namespace can already pull images from %s namespace.' \
                "$saName" "$saNamespace" "$sourceNamespace"
            return 0
        fi
        log -n 'Granting privileges to the %s service account in %s namespace to pull' \
            "$saName" "$saNamespace"
        log -d ' images from %s namespace' "$sourceNamespace"
        runOrLog oc policy add-role-to-user \
            system:image-puller "system:serviceaccount:$saNamespace:$saName" \
            --namespace="$sourceNamespace"
    fi
}

function ensureRedHatRegistrySecret() {
    local srcnm="${1:-}"
    local dstnm="${2:-$NAMESPACE}"
    if [[ -z "${REDHAT_REGISTRY_SECRET_NAME:-}" ]]; then
        if [[ -n "${FLAVOUR:-}" && "${FLAVOUR}" != ubi-build ]]; then
            return 0
        fi
        log 'FATAL: REDHAT_REGISTRY_SECRET_NAME must be provided!'
        exit 1
    fi

    local existArgs=()
    if [[ -z "${srcnm:-}" && -n "${REDHAT_REGISTRY_SECRET_NAMESPACE:-}" ]]; then
        srcnm="${REDHAT_REGISTRY_SECRET_NAMESPACE:-}"
    elif [[ -z "${srcnm:-}" ]]; then
        srcnm="$NAMESPACE"
    fi
    if [[ -n "${srcnm:-}" ]]; then
        existArgs+=( -n "${srcnm}" )
    fi
    existArgs+=( "secret/$REDHAT_REGISTRY_SECRET_NAME" )
    # (because existArgs may be empty which would result in an empty string being passed to the
    # function)
    if ! doesResourceExist "${existArgs[@]}"; then
        log 'FATAL: REDHAT_REGISTRY_SECRET_NAME (secret/%s) does not exist in namespace "%s"!' \
            "$REDHAT_REGISTRY_SECRET_NAME" "$srcnm"
        exit 1
    fi
    local contents
    contents="$(oc get -o json "${existArgs[@]}")"
    local uid resourceVersion
    IFS='#' read -r uid resourceVersion < <(jq -r '[.metadata.uid, .metadata.resourceVersion] |
        join("#")' <<<"$contents")
    if [[ "${srcnm:-}" != "${dstnm:-}" ]]; then
        local ann
        ann="$(mkSourceKeyAnnotation "$srcnm" "$REDHAT_REGISTRY_SECRET_NAME" "$uid" \
            "$resourceVersion")"
        if doesResourceExist -a "$ann" -n "$dstnm" "secret/$REDHAT_REGISTRY_SECRET_NAME"; then
            log -n 'Secret "%s" to pull images from Red Hat registry already' \
                "$REDHAT_REGISTRY_SECRET_NAME"
            log -d ' exists in the target namespace "%s"' "$dstnm"
        else
            log 'Copying secret "%s" from namespace "%s" to namespace "%s".' \
                "$REDHAT_REGISTRY_SECRET_NAME" "$srcnm" "$dstnm"
            printf 'contents:\n'
            printf '%s' "$contents"
            createOrReplace -f -n "$dstnm" < <(jq '.metadata.annotations |= ((. // {}) +
                {"'"${ann%%=*}"'": "'"${ann##*=}"'"}) | del(.metadata.uid) |
                    del(.metadata.resourceVersion)' <<<"$contents")
        fi
    fi
    runOrLog oc secrets link default -n "$dstnm" "$REDHAT_REGISTRY_SECRET_NAME" --for=pull
}
export -f ensureRedHatRegistrySecret

function ensureCABundleSecret() {
    if ! evalBool INJECT_CABUNDLE; then
        return 0
    fi
    local uid current currentSource bundleData key nm _name _uid
    current="$(oc get secret -o json "$SDI_CABUNDLE_SECRET_NAME")" ||:
    IFS='#' read -r newUID newResVersion < <(oc get secret -o \
        jsonpath='{.metadata.uid}#{.metadata.resourceVersion}' \
              -n "$CABUNDLE_SECRET_NAMESPACE" "$CABUNDLE_SECRET_NAME")
    if [[ -n "${current:-}" ]]; then
        currentSource="$(jq -r '.metadata.annotations["'"$SOURCE_KEY_ANNOTATION"'"]' \
            <<<"${current}")"
        IFS=: read -r nm _name _uid _rv <<<"${currentSource:-}"
        if [[ "$nm" == "$CABUNDLE_SECRET_NAMESPACE" && \
              "${_name:-}" == "$CABUNDLE_SECRET_NAME" && "${_uid:-}" == "$newUID" && \
              "${_rv:-}" == "$newResVersion" ]];
        then
            log 'CA bundle in %s secret is up to date, no need to update.' \
                "$SDI_CABUNDLE_SECRET_NAME"
            return 0
        fi
    fi
    
    bundleData="$(oc get -o json -n "$CABUNDLE_SECRET_NAMESPACE" secret \
        "$CABUNDLE_SECRET_NAME" | \
        jq -r '.data as $d | $d | keys[] | select(test(
            "^(?:cert(?:ificate)?|ca(?:-?bundle)?|.*\\.(?:crt|pem))$")) | $d[.] | @base64d')" ||:
    if [[ -z "$(tr -d '[:space:]' <<<"${bundleData:-}")" ]]; then
        log 'Failed to get any ca certificates out of secret %s in namespace %s!' \
            "$CABUNDLE_SECRET_NAME" "$CABUNDLE_SECRET_NAMESPACE"
        return 1
    fi

    local action="Creating"
    if [[ -n "${current:-}" ]]; then
        action="Updating"
    fi
    log -n '%s %s secret in %s namespace containing' "$action" "$SDI_CABUNDLE_SECRET_NAME" \
        "$SDI_NAMESPACE"
    log -d ' cabundle that shall be imported into SDI.' 
    oc create secret generic "$SDI_CABUNDLE_SECRET_NAME" "$DRUNARG" -o json \
        --from-literal="${SDI_CABUNDLE_SECRET_FILE_NAME}=$bundleData" | \
        oc annotate --overwrite -f - --local -o json \
            "$(mkSourceKeyAnnotation "$CABUNDLE_SECRET_NAMESPACE" \
                "$CABUNDLE_SECRET_NAME" "$newUID" "$newResVersion")" | \
        createOrReplace
    if evalBool DRY_RUN; then
        return 0
    fi
    key="$CABUNDLE_SECRET_NAMESPACE:$CABUNDLE_SECRET_NAME:$newUID:$newResVersion"
    log 'Annotating resources where cabundle needs to be injected.'
    runOrLog oc annotate --overwrite job/datahub.checks.checkpoint \
        "$CABUNDLE_INJECT_ANNOTATION=$key" ||:
    # shellcheck disable=SC2119
    ensurePullsFromNamespace
}
export -f ensureCABundleSecret

export _SDI_LIB_SOURCED=1

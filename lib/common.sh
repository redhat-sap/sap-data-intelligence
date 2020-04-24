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
readonly SDI_REGISTRY_TEMPLATE_FILE_NAME=ocp-template.json


function join() { local IFS="${1:-}"; shift; echo "$*"; }

# support both 3.x and 4.x output formats
version="$(oc version --short 2>/dev/null || oc version)"
OCP_SERVER_VERSION="$(sed -n 's/^\(\([sS]erver\|[kK]ubernetes\).*:\|[oO]pen[sS]hift\) v\?\([0-9]\+\.[0-9]\+\).*/\3/p' \
                    <<<"$version" | head -n 1)"
OCP_CLIENT_VERSION="$(sed -n 's/^\([cC]lient.*:\|oc\) \(openshift-clients-\|v\)\([0-9]\+\.[0-9]\+\).*/\3/p' \
                    <<<"$version" | head -n 1)"
unset version
# translate k8s 1.13 to ocp 4.1
if [[ "${OCP_SERVER_VERSION:-}" =~ ^1\.([0-9]+)$ && "${BASH_REMATCH[1]}" -gt 12 ]]; then
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
export OCP_SERVER_VERSION OCP_CLIENT_VERSION

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

function doesResourceExist() {
    local cmd=oc args=( get )
    if [[ "${1:-}" == "-n" ]]; then
        args+=( "-n" "$2" )
        shift 2
    fi
    $cmd "${args[@]}" "$@" >/dev/null 2>&1
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
        printf "$fmt" "$@" >&2
        return 0
    fi
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
        log -n 'Executing: '
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

    _common_init_performed=1
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
        oc create --dry-run -f - -o json <<<"$object"
        return 0
    fi
    printf '%s' "$object"
}
export -f convertObjectToJSON

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

    IFS=: read -r namespace kind name <<<"$(oc create --dry-run -f - -o \
        jsonpath=$'{.metadata.namespace}:{.kind}:{.metadata.name}\n' <<<"$object")"
    namespace="${namespace:-$NAMESPACE}"
    [[ -z "${namespace:-}" ]] && namespace="$(oc project -q)"
    if evalBool DRY_RUN; then
        [[ -n "${namespace:-}" ]] && args=( -n "$namespace" )
        args+=( "${kind,,}" "$name" )
        action=Creating
        doesResourceExist "${args[@]}" && action=Replacing
        log '%s %s/%s in namespace %s' "$action" "${kind,,}" "$name" "${namespace:-UNKNOWN}"
        return 0
    fi
                
    err="$(oc create -f - <<<"$object" 2>&1 >/dev/null)" || rc=$?
    if [[ $rc == 0 ]]; then
        if [[ -n "${kind:-}" && -n "${name:-}" ]]; then
            log 'Created %s/%s in namespace %s' "${kind,,}" "$name" "${namespace:-UNKNOWN}"
        fi
        return 0
    fi
    args=( -f - )
    if grep -q 'AlreadyExists\|Conflict\|Forbidden\|field is immutable' <<<"${err:-}" && \
            evalBool force || [[ "${kind,,}" == job ]];
    then
        args+=( --force )
    fi
    err="$(oc replace "${args[@]}" <<<"$object" 2>&1)" && rc=0 || rc=$?
    printf '%s\n' "$err" >&2
    if [[ $rc == 0 ]] || ! grep -q 'Conflict\|Forbidden\|field is immutable' <<<"${err:-}"; then
        return $rc
    fi
    return 0
}
export -f createOrReplace

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
    runOrLog oc create route "$routeType" --service "$serviceName" --dry-run "$@"
}

function isPathLocal() {
    [[ "${1:-}" =~ ^(file://|\./|/|~) ]]
}
export -f isPathLocal
    

function common_cleanup() {
    rm -rf "$TMP"
}

function getRegistryTemplatePath() {
    local dirs=(
        .
        /usr/local/share/sdi/registry
        /usr/local/share/sap-data-intelligence/registry
    )
    for d in "${dirs[@]}"; do
        local pth="${d}/$SDI_REGISTRY_TEMPLATE_FILE_NAME"
        if [[ -e "$pth" ]]; then
            printf '%s' "$pth"
            return 0
        fi
    done
    log 'WARNING: Could not determine path to %s' "$SDI_REGISTRY_TEMPLATE_FILE_NAME"
    return 1
}
export -f getRegistryTemplatePath

export LETSENCRYPT_ENVIRONMENT="${LETSENCRYPT_ENVIRONMENT:-live}"

export _SDI_LIB_SOURCED=1

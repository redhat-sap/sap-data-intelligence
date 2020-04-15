#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly SDI_REGISTRY_TEMPLATE_FILE_NAME=registry-template.yaml

for d in "$(dirname "${BASH_SOURCE[0]}")" . /usr/local/share/sdi-observer; do
    if [[ -e "$d/lib/common.sh" ]]; then
        eval "source '$d/lib/common.sh'"
    fi
done
if [[ "${_SDI_LIB_SOURCED:-0}" != 1 ]]; then
    printf 'FATAL: failed to source lib/common.sh!\n' >&2
    exit 1
fi
common_init

readonly USAGE="$(basename "${BASH_SOURCE[0]}") [options]

Deploy container image registry for SAP Data Intelligence.

Options:
  -h | --help    Show this message and exit.
  (-o | --output-dir) OUTDIR 
                 Output directory where to put htpasswd and .htpasswd.raw files. Defaults to
                 the working directory.
  -n | --noout   Cleanup temporary htpasswd files.
  --secret-name SECRET_NAME
                 Name of the SDI Registry htpasswd secret. Overrides
                 SDI_REGISTRY_HTPASSWD_SECRET_NAME environment variable. Defaults to
                 $DEFAULT_SDI_REGISTRY_HTPASSWD_SECRET_NAME.
  -w | --wait    Block until all resources are available.
  --hostname REGISTRY_HOSTNAME
                 Expose registry's service on the given HOSTNAME. The default is:
                    container-image-registry-\$NAMESPACE.\$clustername.\$basedomain
  --namespace NAMESPACE
                 Desired k8s NAMESPACE where to deploy the registry.
 (-r | --rht-registry-secret-name) RHT_REGISTRY_SECRET_NAME
                 A secret for registry.redhat.io - required for the build of registry image.
 (-r | --rht-registry-secret-namespace) RHT_REGISTRY_SECRET_NAMESPACE
                 K8s namespace, where the RHT_REGISTRY_SECRET_NAME secret resides.
                 Defaults to the target NAMESPACE.
"

long_options=(
    help output-dir: noout secret-name: hostname: wait namespace: rht-registry-secret-name:
    rht-registry-secret-namespace:
)

NAMESPACE="${SDI_REGISTRY_NAMESPACE:-}"
if [[ -z "${NAMESPACE:-}" ]]; then
    NAMESPACE="$(oc project -q ||:)"
    if [[ -z "${NAMESPACE:-}" ]]; then
        NAMESPACE="${SDI_NAMESPACE:-}"
    fi
fi

function cleanup() {
    common_cleanup
    if evalBool NOOUT && [[ -n "${OUTPUT_DIR:-}" ]]; then
        rm -rf "$OUTPUT_DIR"
    fi
}

function getRegistryTemplatePath() {
    local dirs=(
        .
        /usr/local/share/sdi-observer
        /usr/local/share/sap-data-intelligence/observer
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

function genSecret() {
    local length="${1:-32}"
    local characterClass="${2:-a-zA-Z0-9}"
    tr -dc "${characterClass}" < /dev/urandom | fold -w "$length" | head -n 1 ||:
}

function mkHtpasswd() {
    local user="$1"
    local pw="$2"
    local output="${3:-htpasswd}"
    local args=(
        "-B"        # use bcrypt - the only supported encryption by docker/registry
        "-b"        # read password from the command line
        "-c"        # create the file if it does not exist already
        "${output}"    # output file name
        "$user" "$pw"
    )
    htpasswd "${args[@]}"
}

function createHtpasswdSecret() {
    local force=0
    while [[ $# -gt 0 ]]; do
        if [[ "${1:-}" == "-f" ]]; then
            # shellcheck disable=SC2034
            force=1
        fi
        shift
    done
    if [[ -z "${SDI_REGISTRY_USERNAME:-}" ]]; then
        SDI_REGISTRY_USERNAME="user-$(genSecret 9 'a-z0-9')"
    fi
    if [[ -z "${SDI_REGISTRY_PASSWORD:-}" ]]; then
        SDI_REGISTRY_PASSWORD="$(genSecret)"
    fi
    cmd=create
    if doesResourceExist "secret/$SECRET_NAME"; then
        if evalBool force; then
            cmd="replace --force"
        else
            cmd="replace"
        fi
    fi
    mkHtpasswd "$SDI_REGISTRY_USERNAME" "$SDI_REGISTRY_PASSWORD" "$OUTPUT_DIR/htpasswd"
    printf "%s:%s\n" "$SDI_REGISTRY_USERNAME" "$SDI_REGISTRY_PASSWORD" >"$OUTPUT_DIR/.htpasswd.raw"
    oc create secret generic --dry-run -o yaml "$SECRET_NAME" \
        --from-file=htpasswd="$OUTPUT_DIR/htpasswd" \
        --from-file=.htpasswd.raw="$OUTPUT_DIR/.htpasswd.raw"  | \
            oc "$cmd" -f - >/dev/null
    cat "$OUTPUT_DIR/.htpasswd.raw"
}

function getOrCreateHtpasswdSecret() {
    # returns $username:$password
    if evalBool RECREATE_SECRETS; then
        createHtpasswdSecret -f
    elif doesResourceExist "secret/$SECRET_NAME"; then
        oc get -o json "secret/$SECRET_NAME" | jq -r '.data[".htpasswd.raw"]' | base64 -d
    else
        createHtpasswdSecret
    fi
}

function mkRegistryTemplateParams() {
    while IFS="=" read -r key value; do
        # do not override template's defaults
        [[ -z "$value" ]] && continue
        printf '%s=%s\n' "$key" "$value"
    done < <(printf '%s\n' \
        "HOSTNAME=${REGISTRY_HOSTNAME:-}" \
        "HTPASSWD_SECRET_NAME=$SECRET_NAME" \
        "NAMESPACE=$NAMESPACE" \
        "VOLUME_CAPACITY=${SDI_REGISTRY_VOLUME_CAPACITY:-}" \
        "REDHAT_REGISTRY_SECRET_NAME=$REDHAT_REGISTRY_SECRET_NAME")
}
export -f mkRegistryTemplateParams

function getRegistryTemplateAs() {
    local output="$1"
    local params=()
    readarray -t params <<<"$(mkRegistryTemplateParams)"
    oc process --local "${params[@]}" -f "$(getRegistryTemplatePath)" -o "$output" 
}
export -f getRegistryTemplateAs

function createOrReplaceObjectFromTemplate() {
    local resource="$1" kind name
    IFS='/' read -r kind name <<<"${resource}"
    local spec
    spec="$(getRegistryTemplateAs json | \
        jq '.items[] | select(.kind == "'"$kind"'" and .metadata.name == "'"$name"'")')"
    case "${kind,,}" in
    persistentvolumeclaim)
        if [[ -n "${SDI_REGISTRY_STORAGE_CLASS_NAME:-}" ]]; then
            spec="$(jq '.spec.storageClassName |= "'"$SDI_REGISTRY_STORAGE_CLASS_NAME"'"' \
                <<<"$spec")"
        fi
        ;;
    esac
    createOrReplace <<<"$spec"
}
export -f createOrReplaceObjectFromTemplate

function ensureRedHatRegistrySecret() {
    if [[ -z "${REDHAT_REGISTRY_SECRET_NAME:-}" ]]; then
        log 'FATAL: REDHAT_REGISTRY_SECRET_NAME must be provided!'
        exit 1
    fi

    if [[ -n "${REDHAT_REGISTRY_SECRET_NAMESPACE:-}" ]]; then
        REDHAT_REGISTRY_SECRET_NAME="${REDHAT_REGISTRY_SECRET_NAME##*/}"
    elif [[ "$REDHAT_REGISTRY_SECRET_NAME" =~ ^([^/]+)/(.*) ]]; then
        REDHAT_REGISTRY_SECRET_NAME="${BASH_REMATCH[2]}"
        REDHAT_REGISTRY_SECRET_NAMESPACE="${BASH_REMATCH[1]}"
    fi
    existArgs=()
    if [[ -n "${REDHAT_REGISTRY_SECRET_NAMESPACE:-}" ]]; then
        existArgs+=( -n "${REDHAT_REGISTRY_SECRET_NAMESPACE}" )
    fi
    # shellcheck disable=SC2068
    # (because existArgs may be empty which would result in an empty string being passed to the
    # function)
    if ! doesResourceExist ${existArgs[@]} "secret/$REDHAT_REGISTRY_SECRET_NAME"; then
        log 'FATAL: REDHAT_REGISTRY_SECRET_NAME (secret/%s) does not exist!' \
            "$REDHAT_REGISTRY_SECRET_NAME"
        exit 1
    fi
    if [[ "${REDHAT_REGISTRY_SECRET_NAMESPACE:-$NAMESPACE}" != "${NAMESPACE}" ]]; then
        args=()
        if evalBool RECREATE_SECRETS; then
            args+=( -f )
        fi
        # shellcheck disable=SC2086
        oc -n "${REDHAT_REGISTRY_SECRET_NAMESPACE:-$NAMESPACE}" get -o json \
            "secret/$REDHAT_REGISTRY_SECRET_NAME" | \
            createOrReplace -n "$NAMESPACE" ${args:-}
    fi
    oc secrets add default "$REDHAT_REGISTRY_SECRET_NAME" --for=pull
}

function deployRegistry() {
    ensureRedHatRegistrySecret
    getOrCreateHtpasswdSecret
    # needed for parallel
    export NAMESPACE SECRET_NAME REGISTRY_HOSTNAME REDHAT_REGISTRY_SECRET_NAME  \
        SDI_REGISTRY_TEMPLATE_FILE_NAME
    # decide for each resource independently whether it needs to be replaced or not
    getRegistryTemplateAs jsonpath=$'{range .items[*]}{.kind}/{.metadata.name}\n{end}' | \
        parallel createOrReplaceObjectFromTemplate
}

function waitForRegistryBuild() {
    local buildName buildVersion
    local phase="Unknown"
    while true; do
        buildVersion="$(oc get -o jsonpath='{.status.lastVersion}' \
            "bc/container-image-registry")"
        buildName="container-image-registry-$buildVersion"
        phase="$(oc get builds "$buildName" -o jsonpath=$'{.status.phase}\n')" ||:
        case "$phase" in
            Running)
                oc logs -f "build/$buildName"
                ;;
            Complete)
                break
                ;;
            *)
                sleep 1
                ;;
        esac
    done
    printf '%s\n' "$phase"
}

function waitForRegistryPod() {
    local name="container-image-registry"
    local resource="dc/$name"
    oc rollout status --timeout 180s -w "$resource" >&2
    local latestVersion
    latestVersion="$(oc get -o jsonpath='{.status.latestVersion}' "$resource")"
    oc get pods -l "$(join , \
        "deployment=${name}-$latestVersion" \
        "deploymentconfig=container-image-registry")" -o \
            jsonpath=$'{range .items[*]}{.status.phase}\n{end}' | tail -n 1
}

function waitForRegistry() {
    local resource=bc/container-image-registry
    read -r -t 600 phase <<<"$(waitForRegistryBuild)"
    if [[ "$phase" != Complete ]]; then
        log 'WARNING: failed to wait for the latest build of %s' "$resource"
        return 1
    fi
    read -r -t 300 phase <<<"$(waitForRegistryPod)"
    if [[ "$phase" != Running ]]; then
        log 'WARNING: failed to wait for the latest deployment of %s' "dc/${resource#bc/}"
        return 1
    fi
}

function deployLetsencrypt() {
    printf 'TODO\n'
}

NOOUT=0

TMPARGS="$(getopt -o ho:nw -l "$(join , "${long_options[@]}")" -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

while true; do
    case "$1" in
        -h | --help)
            printf '%s' "$USAGE"
            exit 0
            ;;
        -o | --output-dir)
            OUTPUT_DIR="$1"
            shift 2
            ;;
        -n | --noout)
            NOOUT=1
            shift
            ;;
        --secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --hostname)
            # shellcheck disable=SC2034
            REGISTRY_HOSTNAME="$2"
            shift 2
            ;;
        -w | --wait)
            # shellcheck disable=SC2034
            WAIT_UNTIL_ROLLEDOUT=1
            shift
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --rht-registry-secret-name)
            REDHAT_REGISTRY_SECRET_NAME="$2"
            shift 2
            ;;
        --rht-registry-secret-namespace)
            REDHAT_REGISTRY_SECRET_NAMESPACE="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            log 'FATAL: unknown option "%s"! See help.' "$1"
            exit 1
            ;;
    esac
done

if [[ -n "${NOOUT:-}" && -n "${OUTPUT_DIR:-}" ]]; then
    log 'FATAL: --noout and --output-dir are mutually exclusive options!'
    exit 1
fi

trap cleanup EXIT

if [[ -z "${NOOUT:-}" && -z "${OUTPUT_DIR:-}" ]]; then
    OUTPUT_DIR="$(pwd)"
else
    OUTPUT_DIR="$(mktemp -d)"
fi

if evalBool DEPLOY_SDI_REGISTRY true && [[ -z "${DEPLOY_SDI_REGISTRY:-}" ]]; then
    DEPLOY_SDI_REGISTRY=true
fi

if [[ -n "${NAMESPACE:-}" ]]; then
    if evalBool DEPLOY_SDI_REGISTRY; then
        log 'Deploying SDI registry to namespace "%s"...' "$NAMESPACE"
        if ! doesResourceExist "project/$NAMESPACE"; then
            oc new-project --skip-config-write "$NAMESPACE"
        fi
    fi
    if [[ "$(oc project -q)" != "${NAMESPACE}" ]]; then
        oc project "${NAMESPACE}"
    fi
fi

if [[ -z "${SECRET_NAME:-}" ]]; then
    SECRET_NAME="${SDI_REGISTRY_HTPASSWD_SECRET_NAME:-$DEFAULT_SDI_REGISTRY_HTPASSWD_SECRET_NAME}"
fi
if evalBool DEPLOY_SDI_REGISTRY; then
    deployRegistry
fi

if evalBool WAIT_UNTIL_ROLLEDOUT; then
    waitForRegistry
fi

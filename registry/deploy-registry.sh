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

readonly USAGE="$(basename "${BASH_SOURCE[0]}") [options]

Deploy container image registry for SAP Data Intelligence.

Options:
  -h | --help    Show this message and exit.
  --dry-run      Only log the actions that would have been executed. Do not perform any changes to
                 the cluster. Overrides DRY_RUN environment variable.
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
                 Expose registry's service on the given hostname. Overrides
                 SDI_REGISTRY_ROUTE_HOSTNAME environment variable. The default is:
                    container-image-registry-\$NAMESPACE.\$clustername.\$basedomain
  --namespace NAMESPACE
                 Desired k8s NAMESPACE where to deploy the registry.
 (-r | --rht-registry-secret-name) RHT_REGISTRY_SECRET_NAME
                 A secret for registry.redhat.io - required for the build of registry image.
 (-r | --rht-registry-secret-namespace) RHT_REGISTRY_SECRET_NAMESPACE
                 K8s namespace, where the RHT_REGISTRY_SECRET_NAME secret resides.
                 Defaults to the target NAMESPACE.
 --custom-source-image SOURCE_IMAGE_PULL_SPEC
                 Custom source image for container-image-registry build instead of the default
                 ubi8. Overrides SOURCE_IMAGE_PULL_SPEC environment variable.
                 For example: registry.centos.org/centos:8
 --custom-source-imagestream-name SOURCE_IMAGESTREAM_NAME
                 Name of the image stream for the custom source image if SOURCE_IMAGE_PULL_SPEC
                 is specified. Overrides SOURCE_IMAGESTREAM_NAME environment variable.
                 Defaults to \"$DEFAULT_SOURCE_IMAGESTREAM_NAME\".
 --custom-source-imagestream-tag SOURCE_IMAGESTREAM_TAG
                 Tag in the source imagestream referencing the SOURCE_IMAGE_PULL_SPEC. Overrides
                 SOURCE_IMAGESTREAM_TAG environment variable. Defaults to \"latest\".
 --custom-source-image-registry-secret-name SOURCE_IMAGE_REGISTRY_SECRET_NAME
                 If the registry of the custom source image requires authentication, a pull secret
                 must be created in the target NAMESPACE and its name specified here. Overrides
                 SOURCE_IMAGE_REGISTRY_SECRET_NAME environment variable.
"

readonly longOptions=(
    help output-dir: noout secret-name: hostname: wait namespace: rht-registry-secret-name:
    rht-registry-secret-namespace: dry-run
    custom-source-image custom-source-imagestream-name custom-source-imagestream-tag
    custom-source-image-registry-secret-name
)

if [[ -z "${NAMESPACE:-}" && -n "${SDI_REGISTRY_NAMESPACE:-}" ]]; then
    NAMESPACE="${SDI_REGISTRY_NAMESPACE:-}"
elif [[ -z "${NAMESPACE:-}" ]]; then
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
trap cleanup EXIT

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
    if [[ -z "${SDI_REGISTRY_USERNAME:-}" ]]; then
        SDI_REGISTRY_USERNAME="user-$(genSecret 9 'a-z0-9')"
    fi
    if [[ -z "${SDI_REGISTRY_PASSWORD:-}" ]]; then
        SDI_REGISTRY_PASSWORD="$(genSecret)"
    fi
    mkHtpasswd "$SDI_REGISTRY_USERNAME" "$SDI_REGISTRY_PASSWORD" "$OUTPUT_DIR/htpasswd"
    printf "%s:%s\n" "$SDI_REGISTRY_USERNAME" "$SDI_REGISTRY_PASSWORD" >"$OUTPUT_DIR/.htpasswd.raw"

    # shellcheck disable=SC2068
    oc create secret generic --dry-run -o yaml "$SECRET_NAME" \
        --from-file=htpasswd="$OUTPUT_DIR/htpasswd" \
        --from-file=.htpasswd.raw="$OUTPUT_DIR/.htpasswd.raw"  | \
            createOrReplace
    cat "$OUTPUT_DIR/.htpasswd.raw"
}

function getOrCreateHtpasswdSecret() {
    # returns $username:$password
    if doesResourceExist "secret/$SECRET_NAME" && ! evalBool REPLACE_SECRETS; then
        oc get -o json "secret/$SECRET_NAME" | jq -r '.data[".htpasswd.raw"]' | base64 -d
    else
        createHtpasswdSecret
    fi
}

function mkRegistryTemplateParams() {
    local params=(
        "SDI_REGISTRY_ROUTE_HOSTNAME=${REGISTRY_HOSTNAME:-}" 
        "SDI_REGISTRY_HTPASSWD_SECRET_NAME=$SECRET_NAME" 
        "NAMESPACE=$NAMESPACE" 
        "SDI_REGISTRY_VOLUME_CAPACITY=${SDI_REGISTRY_VOLUME_CAPACITY:-}" 
        "SDI_REGISTRY_VOLUME_ACCESS_MODE=${SDI_REGISTRY_VOLUME_ACCESS_MODE:-}" 
        "SDI_REGISTRY_HTTP_SECRET=${SDI_REGISTRY_HTTP_SECRET:-}")
    )
    if [[ -n "${SOURCE_IMAGESTREAM_NAME:-}" && "${SOURCE_IMAGESTREAM_TAG:-}" && \
            -n "${SOURCE_IMAGE_PULL_SPEC:-}" ]]
    then
        params+=(
            SOURCE_IMAGE_PULL_SPEC="${SOURCE_IMAGE_PULL_SPEC:-}"
            SOURCE_IMAGESTREAM_NAME="${SOURCE_IMAGESTREAM_NAME:-}"
            SOURCE_IMAGESTREAM_TAG="${SOURCE_IMAGESTREAM_TAG:-}"
            SOURCE_IMAGE_REGISTRY_SECRET_NAME="${SOURCE_IMAGE_REGISTRY_SECRET_NAME:-}"
        )
    else
        params+=(
            "REDHAT_REGISTRY_SECRET_NAME=$REDHAT_REGISTRY_SECRET_NAME" 
        )
    fi

    while IFS="=" read -r key value; do
        # do not override template's defaults
        [[ -z "$value" ]] && continue
        printf '%s=%s\n' "$key" "$value"
    done < <(printf '%s\n' "${params[@]}")
}
export -f mkRegistryTemplateParams

function getRegistryTemplateAs() {
    local output="$1"
    local params=()
    readarray -t params <<<"$(mkRegistryTemplateParams)"
    local tmplPath
    tmplPath="$(getRegistryTemplatePath)"
    oc process --local "${params[@]}" -f "$tmplPath" -o "$output" 
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
    route)
        if evalBool EXPOSE_WITH_LETSENCRYPT; then
            spec="$(jq '.metadata.annotations["kubernetes.io/tls-acme"] |= "true"' <<<"$spec")"
        fi
        ;;
    esac
    createOrReplace <<<"$spec"
}
export -f createOrReplaceObjectFromTemplate

function deployRegistry() {
    ensureRedHatRegistrySecret
    getOrCreateHtpasswdSecret
    # needed for parallel
    export NAMESPACE SECRET_NAME REGISTRY_HOSTNAME REDHAT_REGISTRY_SECRET_NAME  \
        SDI_REGISTRY_TEMPLATE_FILE_NAME SOURCE_IMAGE_PULL_SPEC \
        SOURCE_IMAGESTREAM_NAME SOURCE_IMAGESTREAM_TAG SOURCE_IMAGE_REGISTRY_SECRET_NAME
    # decide for each resource independently whether it needs to be replaced or not
    getRegistryTemplateAs jsonpath=$'{range .items[*]}{.kind}/{.metadata.name}\n{end}' | \
        parallel createOrReplaceObjectFromTemplate
}

function waitForRegistryBuild() {
    local buildName buildVersion
    local phase="Unknown"
    for ((i=0; 1; i++)); do
        buildVersion="$(oc get -o jsonpath='{.status.lastVersion}' \
            "bc/container-image-registry")"
        buildName="container-image-registry-$buildVersion"
        local rc=0
        phase="$(oc get builds "$buildName" -o jsonpath=$'{.status.phase}\n')" || rc=$?
        case "$phase" in
            Running)
                if ! oc logs -f "build/$buildName" >&2; then
                    sleep 1
                fi
                ;;
            Complete)
                break
                ;;
            *)
                if [[ "$rc" != 0 && "$i" == 5 ]]; then
                    log 'Starting a new build of container-image-registry manually ...'
                    oc start-build --follow container-image-registry >&2
                else
                    sleep 1
                fi
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

function getLatestRunningPodResourceVersion() {
    oc get pod -o json \
        -l deploymentconfig=container-image-registry | \
        jq -r $'.items[] | select(.kind == "Pod" and .status.phase == "Running") |
            "\(.metadata.resourceVersion):\(.metadata.name)\n"' | sort -n -t : | tail -n 1 | \
            sed 's/:.*//'
}

function waitForRegistry() {
    local resource=bc/container-image-registry
    local initialPodResourceVersion
    initialPodResourceVersion="$(getLatestRunningPodResourceVersion)" ||:
    local buildRC=0
    read -r -t 600 phase <<<"$(waitForRegistryBuild)"
    if [[ "$phase" != Complete ]]; then
        log 'WARNING: failed to wait for the latest build of %s' "$resource"
        buildRC=1
    fi
    read -r -t 300 phase <<<"$(waitForRegistryPod)"
    if [[ "$phase" != Running ]]; then
        log 'WARNING: failed to wait for the latest deployment of %s' "dc/${resource#bc/}"
        return 1
    fi
    podResourceVersion="$(getLatestRunningPodResourceVersion)"
    if [[ $buildRC != 0 && -n "${podResourceVersion:-}" && \
            "${initialPodResourceVersion:-}" != "${podResourceVersion:-}" ]]; then
        return 0
    fi
    return "$buildRC"
}

NOOUT=0
if [[ -z "${REGISTRY_HOSTNAME:-}" && -n "${SDI_REGISTRY_ROUTE_HOSTNAME:-}" ]]; then
    REGISTRY_HOSTNAME="${SDI_REGISTRY_ROUTE_HOSTNAME:-}"
fi

TMPARGS="$(getopt -o ho:nw -l "$(join , "${longOptions[@]}")" -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

while true; do
    case "$1" in
        -h | --help)
            printf '%s' "$USAGE"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            export DRY_RUN
            shift
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
        --custom-source-image)
            SOURCE_IMAGE_PULL_SPEC="$2"
            shift 2;
            ;;
        --custom-source-imagestream-name)
            SOURCE_IMAGESTREAM_NAME="$2"
            shift 2
            ;;
        --custom-source-imagestream-tag)
            SOURCE_IMAGESTREAM_TAG="$2"
            shift 2
            ;;
        --custom-source-image-registry-secret-name)
            SOURCE_IMAGE_REGISTRY_SECRET_NAME="$2"
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
            runOrLog oc new-project --skip-config-write "$NAMESPACE"
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

if evalBool WAIT_UNTIL_ROLLEDOUT && ! evalBool DRY_RUN; then
    waitForRegistry
fi

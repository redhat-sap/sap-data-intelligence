#!/usr/bin/env bash

set -euo pipefail
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

readonly DEFAULT_SC_ANNOTATION="storageclass.kubernetes.io/is-default-class"
readonly DEFAULT_VOLUME_CAPACITY="120Gi"
readonly DEFAULT_IMAGE_PULL_SPEC=quay.io/redhat-sap-cop/container-image-registry:latest
# shellcheck disable=SC2034
readonly DEFAULT_FLAVOUR=ubi-prebuilt

USAGE="$(basename "${BASH_SOURCE[0]}") [options]

Deploy SDI Registry (a container image registry for SAP Data Intelligence) on OpenShift.

Options:
  -h | --help   Show this message and exit.
  --dry-run     Only log the actions that would have been executed. Do not perform any changes to
                the cluster. Overrides DRY_RUN environment variable.
 (-f | --flavour) FLAVOUR
                Choose one of the flavours:
                  ubi-prebuilt - (default) Specify a remote or local image location of the
                                 prebuilt SDI Registry image. The only option for disconnected
                                 clusters.
                  ubi-build    - (connected) Build registry image on OpenShift cluster using the
                                 Red Hat UBI8, store it internally in the integrated image registry
                                 and deploy it from there.
                  custom-build - (connected) Specify a custom base image to be used instead of
                                 UBI8.
 (-o | --output-dir) OUTDIR
                Output directory where to put htpasswd and .htpasswd.raw files. Defaults to
                the working directory.
  --noout       Cleanup temporary htpasswd files.
  --no-cleanup  Nelete neither old k8s builds nor deployments.
  --authentication AUTHENTICATION
                Can be one of: none, basic
                Defaults to \"basic\" where the credentials are verified against the provided or
                generated htpasswd file. For basic auth, SDI_REGISTRY_USERNAME and
                SDI_REGISTRY_PASSWORD environment variables can be set with the desired login
                credentials.
  --no-auth     Is a shortcut for --authentication=none
  --secret-name SECRET_NAME
                Name of the SDI Registry htpasswd secret. Overrides
                SDI_REGISTRY_HTPASSWD_SECRET_NAME environment variable. Defaults to
                $DEFAULT_SDI_REGISTRY_HTPASSWD_SECRET_NAME.
  -w | --wait   Block until all resources are available.
  --hostname REGISTRY_HOSTNAME
                Expose registry's service on the given hostname. Overrides
                SDI_REGISTRY_ROUTE_HOSTNAME environment variable. The default is:
                    container-image-registry-\$NAMESPACE.\$clustername.\$basedomain
 (-n | --namespace) NAMESPACE
                Desired k8s NAMESPACE where to deploy the registry. Defaults to the current
                namespace.
 (--sc | --storage-class) STORAGE_CLASS
                Storage Class to use for registry's volume claim. Unless specified, the default
                storage class will be used. Overrides SDI_REGISTRY_STORAGE_CLASS_NAME environment
                variable.
 (--rwx | --read-write-many)
                Causes ReadWriteMany (RWX) access mode to be requested for the persistent volume.
                The default access mode to request is ReadWriteOnce. If the target storage class
                supports RWX, this flag should be specified. Overrides
                SDI_REGISTRY_VOLUME_ACCESS_MODE environment variable.
 (-c | --volume-capacity) VOLUME_CAPACITY
                Capacity of the requested persistent volume. Overrides
                SDI_REGISTRY_VOLUME_CAPACITY environment variable. Defaults to $DEFAULT_VOLUME_CAPACITY
  --replace-secrets
                Whether to replace existing htpasswd secret. Allows to reset credentials. If
                SDI_REGISTRY_USERNAME and/or SDI_REGISTRY_PASSWORD are not provided, they will be
                generated.

Flavour specific options:
- ubi-prebuilt flavour
    --image-pull-spec IMAGE_PULL_SPEC
                Location of the locally mirrored registry's container image. Overrides the
                eponymous environment variable. Defaults to $DEFAULT_IMAGE_PULL_SPEC

- ubi-build flavour
   (-r | --rht-registry-secret-name) REDHAT_REGISTRY_SECRET_NAME
                A secret for registry.redhat.io - required for the build of registry image.
   (--rp | --rht-registry-secret-path) REDHAT_REGISTRY_SECRET_PATH
                Path to the local k8s secret file with credentials to registry.redhat.io
    --rht-registry-secret-namespace REDHAT_REGISTRY_SECRET_NAMESPACE
                K8s namespace, where the REDHAT_REGISTRY_SECRET_NAME secret resides. Defaults to the
                target NAMESPACE.

- custom-build flavour
    --custom-source-image SOURCE_IMAGE_PULL_SPEC
                Custom source image for container-image-registry build instead of the default
                ubi8. Overrides SOURCE_IMAGE_PULL_SPEC environment variable.
                Defaults to $DEFAULT_SOURCE_IMAGE
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
readonly USAGE

declare -r -A flavourParams=(
    [ubi-build]=REDHAT_REGISTRY_SECRET_NAME
    [ubi-prebuilt]=IMAGE_PULL_SPEC
    [custom-build]="$(join , \
        SOURCE_IMAGE_PULL_SPEC \
        SOURCE_IMAGESTREAM_NAME \
        SOURCE_IMAGESTREAM_TAG \
        SOURCE_IMAGE_REGISTRY_SECRET_NAME)"
)

readonly longOptions=(
    help output-dir: noout secret-name: hostname: wait namespace: no-cleanup
    authentication: replace-secrets
    no-auth
    rht-registry-secret-name: rht-registry-secret-namespace: rp: rht-registry-secret-path:
    dry-run
    custom-source-image custom-source-imagestream-name custom-source-imagestream-tag
    custom-source-image-registry-secret-name
    image-pull-spec:
    sc: storage-class: rwx read-write-many
    volume-capacity:
    flavour:
)

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
    oc create secret generic "$DRUNARG" -o yaml "$SECRET_NAME" \
        --from-file=htpasswd="$OUTPUT_DIR/htpasswd" \
        --from-file=.htpasswd.raw="$OUTPUT_DIR/.htpasswd.raw"  | \
            createOrReplace
    printf 'Credentials: '
    cat "$OUTPUT_DIR/.htpasswd.raw"
}

function getOrCreateHtpasswdSecret() {
    # returns $username:$password
    if doesResourceExist "secret/$SECRET_NAME" && ! evalBool REPLACE_SECRETS; then
        printf 'Credentials: '
        # in the past, the raw secret used to be erroneously generated with "Credentials: " prefix
        oc get -o json "secret/$SECRET_NAME" | jq -r '.data[".htpasswd.raw"]' | base64 -d | \
            sed 's/^Credentials: //'
    else
        createHtpasswdSecret
    fi
}

readonly rwxStorageClasses=(
    ocs-storagecluster-cephfs
)
export rwxStorageClasses

function parseFlavour() {
    local flavour="${1:-}"
    if [[ -n "${flavour:-}" ]]; then
        if [[ ! "${flavour,,}" =~ ^(ubi-build|ubi-prebuilt|custom-build)$ ]]; then
            printf 'Unknown flavour "%s"!\n' >&2 "$FLAVOUR"
            exit 1
        fi
        flavour="${flavour,,}"
    else
        flavour=ubi-build
    fi
    FLAVOUR="$flavour"
    export FLAVOUR

    readarray -t -d , params <<<"${flavourParams[$flavour]}"
    local param value
    local failed=0
    for param in "${params[@]}"; do
        eval 'value="\${'"$param:-}"'"'
        if [[ -z "${value:-}" ]]; then
            failed=1
            printf 'Missing a mandatory parameter "%s" for flavour=%s!\n' >&2 \
                "$param" "$flavour"
        fi
    done
    if [[ "$failed" == 1 ]]; then
        exit 1
    fi
}

function getStorageClass() {
    if [[ -n "${SDI_REGISTRY_STORAGE_CLASS_NAME:-}" ]]; then
        printf '%s' "${SDI_REGISTRY_STORAGE_CLASS_NAME}"
        return 0
    fi
    local defaultSCs
    defaultSCs="$(oc get sc --no-headers | awk '$2 == "(default)" {print $1}')"
    if [[ "$(wc -l <<<"${defaultSCs:-}")" == 1 ]]; then
        SDI_REGISTRY_STORAGE_CLASS_NAME="$(tr -d '\n' <<<"${defaultSCs:-}")"
        printf '%s' "$SDI_REGISTRY_STORAGE_CLASS_NAME"
        export SDI_REGISTRY_STORAGE_CLASS_NAME
        return 0
    fi
    if [[ "$(wc -l <<<"${defaultSCs:-}")" -gt 1 ]]; then
        local rwxDefaults
        rwxDefaults="$(grep -F -x -f <(printf '%s\n' "${rwxStorageClasses[@]}") \
            <<<"${defaultSCs}")"
        if [[ "$(wc -l <<<"${rwxDefaults:-}")" == 1 ]]; then
            SDI_REGISTRY_STORAGE_CLASS_NAME="$(tr -d '\n' <<<"$rwxDefaults")"
            printf '%s' "$SDI_REGISTRY_STORAGE_CLASS_NAME"
            export SDI_REGISTRY_STORAGE_CLASS_NAME
            return 0
        fi
        # more than one default storage class - let the cluster decide which one to use
        return 0
    fi

    local rwxSCs
    rwxSCs="$(grep -F -x -f <(printf '%s\n' "${rwxStorageClasses[@]}") \
        <<<"$(oc get -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' sc)")"
    if [[ "$(wc -l <<<"${rwxSCs:-}")" == 1 ]]; then
        SDI_REGISTRY_STORAGE_CLASS_NAME="$(tr -d '\n' <<<"${rwxSCs:-}")"
        export SDI_REGISTRY_STORAGE_CLASS_NAME
        return 0
    fi
    if [[ "$(wc -l <<<"${rwxSCs:-}")" == 0 ]]; then
        printf 'No storage class found!\n' >&2
        exit 1
    fi
    printf 'No default storage class defined and no storage class selected!' >&2
    printf 'Either annotate a storage class with "%s" or pass one with --sc parameter.\n' >&2 \
        "$DEFAULT_SC_ANNOTATION"
    exit 1
}
export -f getStorageClass

function getCurrentVolumeAccessMode() {
    local pvc
    pvc="$(oc get -o json -n "$NAMESPACE" dc/container-image-registry 2>/dev/null | jq -r \
        '. as $dc | $dc.spec.template.spec.containers[] | .volumeMounts | (. // [])[] |
            select(.mountPath == "/var/lib/registry") | .name | . as $vname |
                $dc.spec.template.spec.volumes[] | select(.name == $vname) |
                .persistentVolumeClaim.claimName // ""')"
    if [[ -z "${pvc:-}" ]]; then
        return 0
    fi
    local accessModes phase 
    IFS=: read -r phase accessModes < <(oc get -o json -n "$NAMESPACE" "pvc/$pvc" 2>/dev/null | \
        jq -r '([.status.phase] + .status.accessModes) | join(":")')
    if [[ "${phase:-}" == Bound ]]; then
        # print the first accessmode matching the prefix
        for am in ReadWriteMany ReadWrite Read; do
            if grep "\<$am" < <(tr ':' '\n' <<<"${accessModes:-}") | head -n 1; then
                return 0
            fi
        done
    fi
}
export -f getCurrentVolumeAccessMode

function getVolumeAccessMode() {
    if [[ -n "${SDI_REGISTRY_VOLUME_ACCESS_MODE:-}" ]]; then
        printf '%s' "$SDI_REGISTRY_VOLUME_ACCESS_MODE"
        return 0
    fi

    if ! evalBool REPLACE_PERSISTENT_VOLUME_CLAIMS; then
        local current
        current="$(getCurrentVolumeAccessMode)"
        # we need to respect the current accessmode if defined already
        if [[ -n "${current:-}" ]]; then
            printf '%s\n' "$current"
            return 0
        fi
    fi

    local sc
    sc="$(getStorageClass)"
    if grep -F -x -q -f <(printf '%s\n' "${rwxStorageClasses[@]}") <<<"${sc:-}";
    then
        SDI_REGISTRY_VOLUME_ACCESS_MODE=ReadWriteMany
    elif grep -F -x -q -f <(printf '%s\n' "${rwxStorageClasses[@]}") \
        < <(oc get sc --no-headers | awk '$2 == "(default)" {print $1}');
    then
        SDI_REGISTRY_VOLUME_ACCESS_MODE=ReadWriteMany
    else
        SDI_REGISTRY_VOLUME_ACCESS_MODE=ReadWriteOnce
    fi

    printf '%s' "$SDI_REGISTRY_VOLUME_ACCESS_MODE"
    export SDI_REGISTRY_VOLUME_ACCESS_MODE
    return 0
}
export -f getVolumeAccessMode

function mkRegistryTemplateParams() {
    if [[ -z "${SDI_REGISTRY_VOLUME_CAPACITY:-}" ]]; then
        SDI_REGISTRY_VOLUME_CAPACITY="$DEFAULT_VOLUME_CAPACITY"
    fi
    local params=(
        "SDI_REGISTRY_ROUTE_HOSTNAME=${REGISTRY_HOSTNAME:-}"
        "SDI_REGISTRY_HTPASSWD_SECRET_NAME=$SECRET_NAME"
        "NAMESPACE=$NAMESPACE"
        "SDI_REGISTRY_VOLUME_CAPACITY=${SDI_REGISTRY_VOLUME_CAPACITY:-}"
        "SDI_REGISTRY_VOLUME_ACCESS_MODE=$(getVolumeAccessMode)"
        "SDI_REGISTRY_HTTP_SECRET=${SDI_REGISTRY_HTTP_SECRET:-}"

        # removed from template's parameters because the default value "" causes no PV to get
        # bound
        #"SDI_REGISTRY_STORAGE_CLASS_NAME=${SDI_REGISTRY_STORAGE_CLASS_NAME:-}"
    )
    case "$FLAVOUR" in
        ubi-build)
            params+=(
                "REDHAT_REGISTRY_SECRET_NAME=$REDHAT_REGISTRY_SECRET_NAME"
            )
            ;;
        ubi-prebuilt)
            if [[ -z "${IMAGE_PULL_SPEC:-}" ]]; then
                IMAGE_PULL_SPEC="$DEFAULT_IMAGE_PULL_SPEC"
            fi
            params+=(
                IMAGE_PULL_SPEC="$IMAGE_PULL_SPEC"
            )
            ;;

        custom-build)
            if [[ -z "${SOURCE_IMAGE_PULL_SPEC:-}" ]]; then
                SOURCE_IMAGE_PULL_SPEC="$DEFAULT_SOURCE_IMAGE"
            fi
            params+=(
                SOURCE_IMAGE_PULL_SPEC="${SOURCE_IMAGE_PULL_SPEC:-}"
                SOURCE_IMAGESTREAM_NAME="${SOURCE_IMAGESTREAM_NAME:-}"
                SOURCE_IMAGESTREAM_TAG="${SOURCE_IMAGESTREAM_TAG:-}"
                SOURCE_IMAGE_REGISTRY_SECRET_NAME="${SOURCE_IMAGE_REGISTRY_SECRET_NAME:-}"
            )
            ;;
    esac

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
    local resource="$1" kind name sc
    IFS='/' read -r kind name <<<"${resource}"
    local def
    def="$(getRegistryTemplateAs json | \
        jq '.items[] | select(.kind == "'"$kind"'" and .metadata.name == "'"$name"'")')"
    case "${kind,,}" in
    persistentvolumeclaim)
        sc="$(getStorageClass)"
        if [[ -n "${sc:-}" ]]; then
            def="$(jq '.spec.storageClassName |= "'"$sc"'"' <<<"$def")"
        fi
        ;;
    route)
        if evalBool EXPOSE_WITH_LETSENCRYPT; then
            def="$(jq '.metadata.annotations["kubernetes.io/tls-acme"] |= "true"' <<<"$def")"
        fi
        ;;
    deploymentconfig)
        if [[ "${AUTHENTICATION:-basic}" == none ]]; then
            def="$(oc set env --local -o json -f - \
                REGISTRY_AUTH_HTPASSWD_REALM- \
                REGISTRY_AUTH_HTPASSWD_PATH- <<<"$def")"
        fi
        if [[ "$(getVolumeAccessMode)" =~ ^Read.*WriteOnce ]]; then
            def="$(jq '.spec.strategy.type |= "Recreate"' <<<"$def")"
        fi
    esac
    ocApply -n "$NAMESPACE" <<<"$def"
}
export -f createOrReplaceObjectFromTemplate

function deployRegistry() {
    ensureRedHatRegistrySecret
    if [[ "${AUTHENTICATION:-basic}" == basic ]]; then
        getOrCreateHtpasswdSecret
    fi

    # decide for each resource independently whether it needs to be replaced or not
    readarray -t resources < <(getRegistryTemplateAs \
        jsonpath='{range .items[*]}{.kind}/{.metadata.name}{"\n"}{end}')
    for resource in "${resources[@]}"; do
        createOrReplaceObjectFromTemplate "$resource" ||:
    done
}

function waitForRegistryBuild() {
    local buildName buildVersion
    local phase="Unknown"
    if [[ ! "$FLAVOUR" =~ build ]]; then
        phase="None"
        return 0
    fi
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
    if [[ ! "$phase" =~ ^(Complete|None)$ ]]; then
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

TMPARGS="$(getopt -o ho:n:wr:f:c: -l "$(join , "${longOptions[@]}")" -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

NOOUT=0
NOCLEANUP=0

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
        -f | --flavour)
            FLAVOUR="$2"
            shift 2
            ;;
        -o | --output-dir)
            OUTPUT_DIR="$1"
            shift 2
            ;;
        --noout)
            NOOUT=1
            shift
            ;;
        --no-cleanup)
            NOCLEANUP=1
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
        -n | --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --authentication)
            AUTHENTICATION="$2"
            shift 2
            ;;
        --no-auth)
            AUTHENTICATION=none
            shift
            ;;
        --sc | --storage-class)
            SDI_REGISTRY_STORAGE_CLASS_NAME="$2"
            shift 2
            ;;
        --rwx | --read-write-many)
            SDI_REGISTRY_VOLUME_ACCESS_MODE=ReadWriteMany
            shift
            ;;
        -c | --volume-capacity)
            SDI_REGISTRY_VOLUME_CAPACITY="$2"
            shift 2
            ;;
        --replace-secrets)
            # shellcheck disable=SC2034
            REPLACE_SECRETS=true
            shift
            ;;
        -r | --rht-registry-secret-name)
            REDHAT_REGISTRY_SECRET_NAME="$2"
            shift 2
            ;;
        --rht-registry-secret-namespace)
            # shellcheck disable=SC2034
            REDHAT_REGISTRY_SECRET_NAMESPACE="$2"
            shift 2
            ;;
        --rp | --rht-registry-secret-path)
            REDHAT_REGISTRY_SECRET_PATH="$2"
            shift 2
            ;;
        --image-pull-spec)
            IMAGE_PULL_SPEC="$2"
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

if [[ "$#" -gt 0 ]]; then
    printf 'Unrecognized arguments:' >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    exit 1
fi

common_init
if [[ -z "${NAMESPACE:-}" && -n "${SDI_REGISTRY_NAMESPACE:-}" ]]; then
    NAMESPACE="${SDI_REGISTRY_NAMESPACE:-}"
elif [[ -z "${NAMESPACE:-}" ]]; then
    NAMESPACE="$(oc project -q ||:)"
    if [[ -z "${NAMESPACE:-}" ]]; then
        NAMESPACE="${SDI_NAMESPACE:-}"
    fi
fi

if [[ -z "${REGISTRY_HOSTNAME:-}" && -n "${SDI_REGISTRY_ROUTE_HOSTNAME:-}" ]]; then
    REGISTRY_HOSTNAME="${SDI_REGISTRY_ROUTE_HOSTNAME:-}"
fi

if [[ -z "${AUTHENTICATION:-}" ]]; then
    AUTHENTICATION="${SDI_REGISTRY_AUTHENTICATION:-basic}"
fi
# shellcheck disable=SC2001
AUTHENTICATION="$(sed 's/^[[:space:]]\+\|[[:space:]]\+$//g' <<<"${AUTHENTICATION,,}")"
if ! [[ "${AUTHENTICATION:-}" =~ ^(basic|none)$ ]]; then
    printf 'Authentication can be one of "basic" and "none", not %s!\n' >&2 "${AUTHENTICATION:-}"
    exit 1
fi

if [[ "$AUTHENTICATION" == none && -n "${SECRET_NAME:-}" ]]; then
    printf 'SECRET_NAME cannot be set while AUTHENTICATION is none!\n'
    exit 1
fi

if evalBool NOOUT && [[ -n "${OUTPUT_DIR:-}" ]]; then
    log 'FATAL: --noout and --output-dir are mutually exclusive options!'
    exit 1
fi

if [[ -z "${NOOUT:-}" && -z "${OUTPUT_DIR:-}" ]]; then
    OUTPUT_DIR="$(pwd)"
else
    OUTPUT_DIR="$(mktemp -d)"
fi

if [[ -n "${REDHAT_REGISTRY_SECRET_NAME:-}" && -n "${REDHAT_REGISTRY_SECRET_PATH:-}" ]]; then
    printf 'REDHAT_REGISTRY_SECRET_NAME and REDHAT_REGISTRY_SECRET_PATH are mutually' >&2
    printf ' exclusive!\nPlease set just one of them!\n' >&2
    exit 1
fi


if evalBool DEPLOY_SDI_REGISTRY true && [[ -z "${DEPLOY_SDI_REGISTRY:-}" ]]; then
    DEPLOY_SDI_REGISTRY=true
fi

parseFlavour "${FLAVOUR:-}"

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

if [[ "$FLAVOUR" == ubi-build ]]; then
    if [[ -n "${REDHAT_REGISTRY_SECRET_PATH:-}" ]]; then
        oc patch --local --dry-run=client -f "${REDHAT_REGISTRY_SECRET_PATH:-}" \
            -p '{"metadata":{"namespace": "'"$NAMESPACE"'"}}' -o json | \
            ocApply -n "$NAMESPACE" -f -
        REDHAT_REGISTRY_SECRET_NAME="$(oc patch -n "$NAMESPACE" --local --dry-run=client \
            -f "$REDHAT_REGISTRY_SECRET_PATH" -p '{"foo": "bar"}}' \
            -o jsonpath='{.metadata.name}')"
    elif [[ -n "${REDHAT_REGISTRY_SECRET_NAME:-}" ]]; then
        if ! oc get -n "${NAMESPACE:-}" secret/"${REDHAT_REGISTRY_SECRET_NAME:-}"; then
            printf 'Please create the secret REDHAT_REGISTRY_SECRET_NAME (%s)' \
                "${REDHAT_REGISTRY_SECRET_NAME:-}" >&2
            printf ' in namespace %s first!\n' "${NAMESPACE:-}" >&2
            exit 1
        fi
    else
        printf 'Please set either the REDHAT_REGISTRY_SECRET_NAME '
        printf ' or REDHAT_REGISTRY_SECRET_PATH for ubi-build flavour!\n' >&2
        exit 1
    fi
fi

if [[ -z "${SECRET_NAME:-}" ]]; then
    SECRET_NAME="${SDI_REGISTRY_HTPASSWD_SECRET_NAME:-$DEFAULT_SDI_REGISTRY_HTPASSWD_SECRET_NAME}"
fi

# maps bcName to .status.lastVersion
declare -A lastVersions
if evalBool DEPLOY_SDI_REGISTRY true; then
    if [[ "${FLAVOUR:-}" =~ build ]]; then
        builds=( container-image-registry )
        for b in "${builds[@]}"; do
            lastVersions["$b"]="$(oc get -n "$NAMESPACE" "bc/${b}" -o \
                jsonpath='{.status.lastVersion}' --ignore-not-found 2>/dev/null)"
        done
    fi

    deployRegistry

    # start new image builds if not started automatically
    if [[ "$FLAVOUR" =~ build ]]; then
        for b in "${builds[@]}"; do
            lv="$(oc get "bc/$b" -n "$NAMESPACE" -o jsonpath='{.status.lastVersion}')"
            if [[ "${lv:-0}" -gt "${lastVersions["$b"]:-0}" ]]; then
                printf 'Build "%s" has been started automatically.\n' "$b"
                printf '  You can follow its progress with: oc logs -n %s -f bc/%s\n' \
                    "$NAMESPACE" "$b"
                continue
            fi
            buildArgs=( -n "$NAMESPACE" )
            if evalBool WAIT_UNTIL_ROLLEDOUT; then
                buildArgs+=( -F )
            fi
            runOrLog oc start-build "${buildArgs[@]}" "bc/$b"
        done
    fi
fi

if evalBool WAIT_UNTIL_ROLLEDOUT && ! evalBool DRY_RUN; then
    waitForRegistry
fi

if [[ "${NOCLEANUP:-0}" == 1 ]]; then
    exit 0
fi

pruneArgs=( -n "$NAMESPACE" )
if ! evalBool DRY_RUN; then
    pruneArgs+=( --confirm )
fi

if [[ ! "$FLAVOUR" =~ build ]]; then
    readarray -t toDelete < <(oc get bc,build -n "$NAMESPACE" \
        -l created-by=registry-template -o name)
    if [[ "${#toDelete[@]}" -gt 1 || ( "${#toDelete[@]}" == 1 && -z "${toDelete[0]:-}" ) ]]; then
        printf 'Deleting build related objects...\n'
        printf '%s\n' "${toDelete[@]}" | grep -v '^\s*$' | xargs -P 4 -n 1 -r \
            oc delete -n "$NAMESPACE"
    fi
else
    printf 'Pruning old builds...\n'
    oc adm prune builds "${pruneArgs[@]}"
fi

printf 'Pruning old deployments...\n'
oc adm prune deployments "${pruneArgs[@]}"

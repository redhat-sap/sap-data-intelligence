#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly RGW_SERVICE_NAME="rook-ceph-rgw-ocs-storagecluster-cephobjectstore"
readonly DEFAULT_ENDPOINT="http://${RGW_SERVICE_NAME}.openshift-storage.svc.cluster.local"
readonly jqMinVersion=1.6
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

readonly USAGE="$SCRIPT_NAME [options]

Update Object Bucket access information in SAP Data Intelligence instance. The primary use case is
to migrate from an S3 endpoint for SDI's checkpoint-store to RGW endpoint running on the OCP
cluster as part of ODF (either internal or external mode).

So far, the bucket name (aka root path) must be the same for both old and new S3 endpoints.

Prerequisites:
- SAP DI stopped
- Object Bucket created and containing all the data from the old location

Example:
    $SCRIPT_NAME -c sdi-infra/checkpoint-store-rgw -n sdi
        Read the bucket access details from the bucket in the sdi-infra namespace and update SDI
        resources in sdi namespace accordingly.

Options:
  -h | --help       Display this help message and quit.
  --no-check        Skip all the checks.
  --dry-run         Just print what would be executed. Change nothing.
 (-n | --namespace) NAMESPACE
                    K8s namespace where the SAP DI is deployed to. Defaults to the namespace of
                    the current context.

 (-c | --obc) [CLAIM_NAMESPACE/]OBJECT_BUCKET_CLAIM_NAME
                    Read all the S3 bucket access details from an existing object bucket claim
                    object identified by name and optionally prefixed by the namespace. This
                    options is mutually exclusive with the rest of the options.

 (-e | --endpoint) ENDPOINT
                    New S3 endpoint for the new bucket. If not given and obc is specified, it will
                    be determined from the bucket object. Otherwise, defaults to $DEFAULT_ENDPOINT
 (--rp | --root-path) ROOT_PATH
                    Root path that must match the old one.
 (-a | --access-key-id) ACCESS_KEY_ID
                    New AWS access key id.
 (-s | --secret-access-key) SECRET_ACCESS_KEY
                    New AWS secret access key.
  --env-auth        Read bucket authentication information from the environment variables.
                    Supported variables are: AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY"

storageClassName=ocs-storagecluster-ceph-rgw

namespace="$(oc project -q)"

readonly checkPods=(
    hana-0
    vora-disk-0
    vora-dlog-0
    vsystem-vrep-0
)

readonly checkSecrets=(
    vora.conf.checkpoint-connection   
    com.sap.datahub.installers.br.rclone-configuration
)

readonly longOptions=(
    help no-check dry-run namespace:
    obc:
    endpoint:
    rp: root-path:
    access-key-id: secret-access-key:
    env-auth:
)

function join() { local IFS="$1"; shift; echo "$*"; }

function run() {
    if [[ "${dryRun:-0}" == 1 ]]; then
        local input
        input="$(cat /dev/fd/0)"
        oc apply --dry-run=client -o json -f - <<<"$input"
        oc apply --dry-run=client -f - <<<"$input"
    else
        oc apply -f -
    fi
}

function check() {
	local runLevel
	local failed=0
	runLevel="$(oc get -o jsonpath='{.spec.runLevel}' datahubs/default)"
	if [[ "${runLevel:-}" != Stopped ]]; then
        printf 'Run level must be set to Stopped! Current datahub run level is "%s".\n' "$runLevel"
        failed=1
    fi

    if ! oc get -n openshift-storage service/"$RGW_SERVICE_NAME" >/dev/null 2>&1; then
        printf 'Service %s does not exist in openshift-storage namespace!\n' "$RGW_SERVICE_NAME"
        failed=1
    fi

    local resources=()
    for pod in "${checkPods[@]}"; do
        resources+=( "pod/$pod" )
    done
    pods="$(oc get -o name -n "$namespace" --ignore-not-found "${resources[@]}")"
    if [[ -n "${pods:-}" ]]; then
        printf 'Found pods in DI namespace "%s"! Please stop the DI instance' >&2 "$namespace"
        printf ' and wait until it is stopped.\n'
        failed=1
    fi

    if [[ -z "${bucketClaimName:-}" ]]; then
        if ! oc get sc "$storageClassName" >/dev/null 2>&1; then
            printf 'Storage class "%s" does not exist!\n' "$storageClassName"
            failed=1
        fi

        local obs
        obs="$(oc get -o json objectbucket | jq --arg bucket "$bucketName" \
            --arg sc "$storageClassName" '.items[] | select(
                .spec.endpoint.bucketName == $bucket and
                .spec.storageClassName == $sc)')"
        if [[ -z "${obs:-}" ]]; then
            printf 'Failed to find an object bucket matching the bucket name "%s" ' "$bucketName"
            printf ' and storage class "%s"!\n' "$storageClassName"
            failed=1
        fi
        if ! jq -r '.status.phase' <<<"$obs" | grep -qi '^Bound$'; then
            while IFS=: read -r nm name phase; do
                printf 'Object Bucket "%s/%s" is not bound (phase=="%s")!\n' \
                    "$nm" "$name" "$phase"
                failed=1
            done < <(jq -r '"\(.metadata.namespace):\(.metadata.name):\(.status.phase)"' <<<"$obs")
        fi
    fi

    jqVersion="$(jq --version)"
    jqVersion="${jqVersion##*-}"
    if [[ "$(printf '%s\n%s\n' "$jqMinVersion" "$jqVersion" | sort -V | \
            head -n 1)" != "$jqMinVersion" ]];
    then
        printf 'jq is either not installed or too old. Please make sure to make' >&2
        printf ' jq %s or newer available in the PATH!\n' "$jqMinVersion" >&2
        failed=1
    fi

    if [[ "$failed" == 1 ]]; then
        exit 1
    fi
}

function determineSecrets() {
    local toCheck=( "${checkSecrets[@]}" )
    local secret
    secret="$(oc get -n "$namespace" datahubs/default -o json | jq -r '.spec.voraCluster |
        .template.components.globalParameters.checkpoint.afsiConnectionSecret')"
    if [[ -n "${secret:-}" ]]; then
        readarray -t secrets < <(sort -u < <(printf '%s\n' "$secret" "${toCheck[@]}")) 
        toCheck=()
        for secret in "${secrets[@]}"; do
            toCheck+=( "$secret" )
        done
    fi

    for secret in "${toCheck[@]}"; do
        if oc get -n "$namespace" "secret/$secret" >/dev/null 2>&1; then
            secretsToUpdate+=( "$secret" )
        fi
    done
    if [[ "${#secretsToUpdate[@]}" -lt 1 ]]; then
        printf 'Found no candidate secrets in namespace "%s" for an update.\n' "$namespace"
        exit 0
    fi

    if [[ "${noCheck:-0}" == 1 ]]; then
        return 0
    fi

    local origRemotePath
    if grep -q -F com.sap.datahub.installers.br.rclone-configuration < <(printf '%s\n' \
        "${secretsToUpdate[@]}");
    then
        origRemotePath="$(oc get -o json -n "$namespace" secret \
            com.sap.datahub.installers.br.rclone-configuration | jq -r \
            .data.restore_remote_path | base64 -d)"
    else
        origRemotePath="$(oc get -o json -n "$namespace" secret/"${secretsToUpdate[0]}" | jq -r \
            -r '. as $s | .data["AFSI_CONNECTION_STRING"] | @base64d | split("&") |
                map(capture("^(?<key>[^=]+)=(?<value>.*)")) | from_entries | .Path')"
    fi
    if [[ "$origRemotePath" != "$bucketName" ]]; then
        printf 'Root path does not match the original ("%s" != "%s")!\n' \
            "$origRemotePath" "$bucketName"
        return 1
    fi
}

function getClaimAccessDetails() {
    if [[ -z "${bucketClaimName:-}" ]]; then
        return 0
    fi
    local args=( get )
    local nm="$namespace"
    if [[ -n "${bucketClaimNamespace:-}" ]]; then
        nm="${bucketClaimNamespace:-}"
    fi
    args+=( -n "$nm" )
    if ! oc "${args[@]}" "obc/${bucketClaimName}" >/dev/null; then
        printf 'Failed to get object bucket claim "%s" in namespace "%s"!\n' \
            "${bucketClaimName}" "${nm:-}"
        return 1
    fi

    local name phase sc ob
    IFS=: read -r name phase sc ob <<<"$(oc "${args[@]}" -o json "obc/${bucketClaimName}" | jq -r \
        '[.spec.bucketName, .status.phase, .spec.storageClassName, .spec.objectBucketName] |
        join(":")')"
    if [[ "${phase:-}" != "Bound" ]]; then
        printf 'Given bucket claim is not Bound!\n'
        return 1
    fi
    bucketName="$name"
    storageClassName="$sc"

    local keyId secretKey
    IFS=: read -r keyId secretKey <<<"$(oc "${args[@]}" \
        -o json "secret/${bucketClaimName}" | jq -r '[.data.AWS_ACCESS_KEY_ID,
            .data.AWS_SECRET_ACCESS_KEY] | map(@base64d) | join(":")')"
    ACCESS_KEY_ID="$keyId"
    SECRET_ACCESS_KEY="$secretKey"

    if [[ -z "${destEndpoint:-}" ]]; then
        local ep port proto
        IFS=: read -r ep port < <(oc get "ob/$ob" -o \
            jsonpath='{.spec.endpoint.bucketHost}:{.spec.endpoint.bucketPort}' ||:) ||:
        if [[ -z "${ep:-}" ]]; then
            destEndpoint="$DEFAULT_ENDPOINT"
            return 0
        fi

        if [[ "$ep" =~ ^([^:/]+)://(.+) ]]; then
            proto="${BASH_REMATCH[1]}"
            ep="${BASH_REMATCH[2]}"
        fi
        case "${proto:-}:$port" in
            ":80")
                destEndpoint="http://$ep"
                ;;
            ":443")
                if [[ "$ep" =~ ^(s3|$RGW_SERVICE_NAME)\.openshift-storage\.svc ]]; then
                    # prefer http port for known services that support it
                    # http is easier to debug
                    destEndpoint="http://$ep"
                else
                    destEndpoint="https://$ep"
                fi
                ;;
            *:80 | *:443)
                destEndpoint="$ep"
                ;;
            *:*)
                destEndpoint="$ep:$port"
                ;;
        esac
        # shellcheck disable=SC2001
        destEndpoint="$(sed 's/\.svc\(:[[:digit:]]\+\)\?$/.svc.cluster.local\1/' \
                <<<"$destEndpoint")"
    fi
}

function updateSecret() {
    local secretName="$1"
    local jqCode=""
    case "$secretName" in
        com.sap.datahub.installers.br.rclone-configuration)
            # shellcheck disable=SC2016
            jqCode='. as $s | .data["rclone.conf"] | @base64d |
                    gsub("(?<p>access_key_id\\s*=).*"; "\(.p) \($accessKey)") |
                    gsub("(?<p>secret_access_key\\s*=).*"; "\(.p) \($secretAccessKey)") |
                    gsub("(?<p>endpoint\\s*=).*"; "\(.p) \($host)") | @base64 as $rcloneConf |
                    $s | .data["rclone.conf"] |= $rcloneConf |
                    .restore_remote_path |= ($path | @base64)'
        ;;
        *)
            # shellcheck disable=SC2016
            jqCode='. as $s | .data["AFSI_CONNECTION_STRING"] |
                    @base64d | split("&") | map(capture("^(?<key>[^=]+)=(?<value>.*)")) | from_entries |
                    .AccessKey |= $accessKey | .SecretAccessKey |= $secretAccessKey |
                    .Host |= $host | .Path |= $path |
                    to_entries | map("\(.key)=\(.value)") | join("&") | @base64 as $conn64 |
                    $s | .data["AFSI_CONNECTION_STRING"] |= $conn64'
        ;;
    esac

    oc get -o json -n "$namespace" "secret/$secretName" | jq -r \
        --arg accessKey "$ACCESS_KEY_ID" \
        --arg secretAccessKey "$SECRET_ACCESS_KEY" \
        --arg host "$destEndpoint" \
        --arg path "$bucketName" \
        -r "$jqCode" | run
}

function backupSecrets() {
    if [[ "${dryRun:-0}" == 1 ]]; then
        return 0
    fi
    local fn
    fn="${namespace}-obmigrate-secrets-backup-$(date -Iseconds -u).json"
    printf 'secret/%s\n' "$@" | xargs -r oc get -n "$namespace" -o json >"$fn"
    printf 'Backup of the DI secrets saved as "%s".\n' "$fn"
}

TMPARGS="$(getopt -o "hn:c:e:a:s:e" -l "$(join , "${longOptions[@]}")" \
    -n "${SCRIPT_NAME}" -- "$@")"
eval set -- "$TMPARGS"

noCheck=0
dryRun=0
bucketClaimName=""
bucketClaimNamespace=""
destEndpoint=""
bucketName=""
envAuth=0
ACCESS_KEY_ID=""
SECRET_ACCESS_KEY=""
secretsToUpdate=()

while true; do
    case "${1:-}" in
        -h | --help)
            printf "%s" "$USAGE"
            exit 0
            ;;
        -n | --namespace)
            namespace="$2"
            shift 2
            ;;
        --no-check)
            noCheck=1
            shift
            ;;
        --dry-run)
            dryRun=1
            shift
            ;;
        (-c | --obc)
            bucketClaimName="$2"
            shift 2
            if [[ "$bucketClaimName" =~ ^([^/]+)/(.+) ]]; then
                bucketClaimNamespace="${BASH_REMATCH[1]}"
                bucketClaimName="${BASH_REMATCH[2]}"
            fi
            ;;
        (-e | --endpoint)
            destEndpoint="$2"
            shift 2
            ;;
        (--rp | --root-path)
            bucketName="$2"
            shift 2
            ;;
        (-a | --access-key-id)
            ACCESS_KEY_ID="$2"
            shift 2
            ;;
        (-s | --secret-access-key)
            SECRET_ACCESS_KEY="$2"
            shift 2
            ;;
        (--env-auth)
            envAuth=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'Unrecognized option "%s"!\nSee help...\n' >&2 "${1:-}"
            exit 1
            ;;
    esac
done

if [[ -n "${bucketClaimName:-}" && "${envAuth:-}" == 1 ]]; then
    printf 'Mutually exclusive parameters given: env-auth and obc!\n' >&2
    exit 1
fi
if [[ -n "${bucketClaimName:-}" && ( 
        -n "${destEndpoint:-}" ||
        -n "${bucketName:-}" ||
        -n "${ACCESS_KEY_ID:-}" ||
        -n "${SECRET_ACCESS_KEY:-}" ) ]];
then
    printf 'Mutually exclusive parameters given: obc and one of endpoint, root-path,' >&2
    printf ' access-key-id or secret-access-key!\n' >&2
    exit 1
fi
if [[ "${envAuth:-}" == 1 && ( -n "${ACCESS_KEY_ID:-}" || -n "${SECRET_ACCESS_KEY:-}" ) ]]; then
    printf 'Mutually exclusive parameters given: env-auth and access-key-id or' >&2
    printf ' secret-access-key!\n' >&2
    exit 1
fi

if [[ "${envAuth:-}" == 1 && ( -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ) ]];
then
    printf 'Missing either AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY environemnt variable,' >&2
    printf ' please export them.\n' >&2
    exit 1
fi
if  [[ "${envAuth:-}" == 1 ]]; then
    ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
fi
if [[ -z "${bucketName-}" && -z "${bucketClaimName:-}" ]]; then
    printf 'Either root-path or obc must be given on the command line!\n' >&2
    exit 1
fi

if [[ "${noCheck:-0}" == 0 ]]; then
    check
fi
getClaimAccessDetails
determineSecrets

if [[ -z "${ACCESS_KEY_ID}" || -z "${SECRET_ACCESS_KEY}" ]]; then
    printf 'Missing access-key-id or secret-access-key, please provide them!\n' >&2
    exit 1
fi

backupSecrets "${secretsToUpdate[@]}"
for secret in "${secretsToUpdate[@]}"; do
    updateSecret "$secret"
done

# ex: sw=4 et ts=4 :

#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_REGISTRY_SECRET_NAME=1979710-miminar-pull-secret
readonly DEFAULT_NFS_PATH=/observer.sh
NAMESPACE="$(oc project -q)"

USAGE="$(basename "${BASH_SOURCE[0]}") [options] [SECRET_NAME]

A script for deploying SDI observer from the current directory.

Parameters:
  SECRET_NAME       Pull secret for the redhat.registry.io. Can be specified in environment
                    variable of the same name.

Options:
  -h | --help       Show this help message and quit.
  -s | --shell      Start a shell instead of executing the observer script.
  -r | --rebuild    Rebuild the observer image.
  -n | --namespace NAMESPACE
                    Kubernetes namespace where the SAP Data Intelligence is installed.
                    Unless given, the current namespace will be used to deploy.
  -c | --clean      TODO: Delete existing objects and redeploy from scratch.
  -f | --file PATH  TODO: Copy the given file path to /tmp/observer.sh or mount it at
                    /observer.sh. PATH defaults to \"./observer.sh\"
                    If NFS_SHARE is specified, the PATH is relative to its root.
  --copy-script     Copy the script instead of mounting it at /observer.sh.
  -m | --mount-config-map
                    Mount the at \"/observer.sh\" in the container overriding the original script.
                    Thid is the default.
  --nfs-share NFS_SHARE
                    Fastest method to get the script into the container. It will be mounted at
                    /tmp/observer.sh.
  --nfs-path NFS_PATH
                    Path to the observer script under the NFS_SHARE exported volume.
                    Defaults to $DEFAULT_NFS_PATH
  --no-script-update
                    Do not override the script in any way.
"

REBUILD=0
ENTER_THE_SHELL=0
SECRET_NAME="${SECRET_NAME:-$DEFAULT_REGISTRY_SECRET_NAME}"
MOUNT_CONFIG_MAP=0
COPY_SCRIPT=0
CLEAN=0
NO_SCRIPT_UPDATE=0
NFS_SHARE=""
NFS_PATH=""

readonly long_options=(
    help shell rebuild namespace: mount-config-map clean copy-script no-script-update
    nfs-share: nfs-path:
)

function createOrReplaceFromStdin() {
    local resource="$1"
    local cmd=create
    local args=( -f - )
    if oc get "$resource" >/dev/null; then
        cmd=replace
        args+=( --force )
    fi
    oc "$cmd" "${args[@]}"
}

function join() { local IFS="$1"; shift; echo "$*"; }

TMPARGS="$(getopt -l "$(join ',' "${long_options[@]}")" -o chsrn:m -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

while true; do
    case "$1" in
        -h | --help)
            printf '%s' "$USAGE"
            exit 0
            ;;
        -s | --shell)
            ENTER_THE_SHELL=1
            shift
            ;;
        -r | --rebuild)
            REBUILD=1
            shift
            ;;
        -n | --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -m | --mount-config-map)
            MOUNT_CONFIG_MAP=1
            COPY_SCRIPT=0
            shift
            ;;
        --copy-script)
            MOUNT_CONFIG_MAP=0
            COPY_SCRIPT=1
            shift
            ;;
        -c | --clean)
            CLEAN=1
            shift
            ;;
        --no-script-update)
            NO_SCRIPT_UPDATE=1
            shift
            ;;
        --nfs-share)
            NFS_SHARE="$2"
            shift 2
            ;;
        --nfs-path)
            NFS_PATH="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'Unknown parameter "%s"!\n' "$1"
            exit 1
            ;;
    esac
done

if [[ "$#" -gt 0 ]]; then
    SECRET_NAME="$1"
    shift
fi


case "$NO_SCRIPT_UPDATE$MOUNT_CONFIG_MAP$COPY_SCRIPT:${NFS_SHARE:+share}" in
    11?* | 1?1*)
        printf 'Option --no-script-update is mutually exclusive with the following:\n' >&2
        printf '    --mount-config-map\n' >&2
        printf '    --copy-script\n' >&2
        printf '    --nfs-share\n' >&2
        exit 1
        ;;
    000:share)
        # faster
        MOUNT_CONFIG_MAP=1
        ;;
    ?1?:share)
        printf 'Option --mount-config-map is mutually exclusive with the following:\n' >&2
        printf '    --mount-config-map\n' >&2
        printf '    --nfs-share\n' >&2
        exit 1
        ;;
esac

if [[ -n "${NFS_SHARE:-}" && -z "${NFS_PATH:-}" ]]; then
    NFS_PATH="${DEFAULT_NFS_PATH}"
fi

if [[ "$CLEAN" == 1 ]]; then
    printf 'Cleaning sdi-observer resources...\n' >&2
    (
        oc get all -o name -l deployment=sdi-observer;
        oc get is -o name -l deployment=sdi-observer;
        oc get roles -o name -l deployment=sdi-observer;
        oc get sa -o name -l deployment=sdi-observer;
        oc get bc -o name -l deployment=sdi-observer;
        oc get builds -o name -l deployment=sdi-observer;
        oc get cm -o name sdi-observer;
    ) | xargs -r oc delete --wait --grace-period=0  ||:
fi

set -x
newDeployment=0
if ! oc get deploy/sdi-observer >/dev/null; then
    # TODO patch the container command to spawn sleep
    oc process REGISTRY_SECRET_NAME="${SECRET_NAME}" NAMESPACE="${NAMESPACE}" \
        -f ocp-template.yaml -o json | jq '.items[] | if (.kind != "Deployment") then
    .
else
    .spec.template.spec.containers[].command |= ["/usr/bin/sleep", "infinity"]
end' | oc create -f - || :
    newDeployment=1
else
    oc patch deploy/sdi-observer -p 'spec:
  template:
    spec:
      containers:
      - name: sdi-observer
        command: ["/usr/bin/sleep", "infinity"]'
fi

case "$newDeployment$REBUILD" in
    01)
        oc get -o name builds -l deployment=sdi-observer | xargs -r oc delete --wait ||:
        printf 'Rebuilding sdi-observer from template...\n'
        oc process REGISTRY_SECRET_NAME="$SECRET_NAME" \
                NAMESPACE="$NAMESPACE" -f ocp-template.yaml -o json | \
            jq '.items[] | select(.kind == "BuildConfig")' | \
                createOrReplaceFromStdin bc/sdi-observer
        sleep 1
        #oc start-build -F bc/sdi-observer
        oc logs -f bc/sdi-observer
esac
set -x

script_path=/observer.sh

if [[ "$NO_SCRIPT_UPDATE" == 0 ]]; then
    oc create configmap sdi-observer.sh --from-file=observer.sh=./observer.sh  -o yaml --dry-run | \
        createOrReplaceFromStdin configmap/sdi-observer.sh
    if [[ -n "${NFS_SHARE:-}" ]]; then
        oc set volume deploy/sdi-observer --dry-run -o json \
            --add --overwrite --type emptyDir --sub-path=observer.sh \
            --name observer-sh --configmap-name=sdi-observer.sh \
            --read-only=true --mount-path=/observer.sh | oc patch --local -f - -o json \
                -p '{"spec":{"template":{"spec":{"volumes":[{
                        "name":"observer-sh",
                        "nfs":{
                            "server":"'"$NFS_SHARE"',
                            "path":"'"$NFS_PATH"'}}]}}}}' | \
            oc replace -f -

    elif [[ "$MOUNT_CONFIG_MAP" == 1 ]]; then
        oc set volume deploy/sdi-observer \
            --add --overwrite --type configmap --sub-path=observer.sh \
            --name observer-sh --configmap-name=sdi-observer.sh \
            --read-only=true --mount-path=/observer.sh
        printf 'Script mounted to deploy/sdi-observer at %s, re-deploying...\n' "$script_path"
        sleep 1
        # TODO: determine if a new deployment shall be rolled out or not
        oc rollout latest deploy/sdi-observer
        sleep 1
        oc rollout status -w deploy/sdi-observer
        printf 'deploy/sdi-observer rolled out.\n'

    else
        printf 'Copying observer script to deployment/sdi-observer at %s\n' "$script_path"
        cm="$(oc get pods -l deployment=sdi-observer -o name | \
                    sort -n | tail -n 1 | sed 's,^pod/,,')"
        oc cp ./observer.sh "$cm:/tmp/observer.sh"
        script_path="/tmp$script_path"
        printf 'Script copied to container %s at %s\n' "$cm" "$script_path"
    fi
fi

args=( rsh deploy/sdi-observer )
if [[ "${ENTER_THE_SHELL:-0}" == 0 ]]; then
    args+=( /bin/bash "$script_path" )
fi

exec oc "${args[@]}"

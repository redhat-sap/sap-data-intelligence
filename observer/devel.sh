#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_REGISTRY_SECRET_NAME=1979710-miminar-pull-secret
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
"

REBUILD=0
ENTER_THE_SHELL=0
SECRET_NAME="${SECRET_NAME:-$DEFAULT_REGISTRY_SECRET_NAME}"

long_options=(
    help shell rebuild namespace:
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

TMPARGS="$(getopt -l "$(join ',' "${long_options[@]}")" -o hsrn: -n "${BASH_SOURCE[0]}" -- "$@")"
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
        --)
            break
            shift
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

newDeployment=0
if ! oc get dc/sdi-observer >/dev/null; then
    oc process REGISTRY_SECRET_NAME="${REGISTRY_SECRET_NAME}" NAMESPACE="${NAMESPACE}" \
            -f ocp-template.yaml -o json | \
        oc create -f -
    newDeployment=1
fi

case "$newDeployment$REBUILD" in
    01)
        oc process REGISTRY_SECRET_NAME="$SECRET_NAME" \
                NAMESPACE="$NAMESPACE" -f ocp-template.yaml -o json | \
            jq '.items[] | select(.kind == "BuildConfig")' | \
                createOrReplaceFromStdin bc/sdi-observer
        sleep 1
        oc start-build -F bc/sdi-observer
esac

oc create configmap observer.sh --from-file=observer.sh=./observer.sh  -o yaml --dry-run | \
    createOrReplaceFromStdin configmap/observer.sh

oc set volume dc/sdi-observer \
    --add --overwrite --type configmap --sub-path=observer.sh \
    --name observer-sh --configmap-name=observer.sh \
    --read-only=true --mount-path=/observer.sh
sleep 1
# TODO: determine if a new deployment shall be rolled out or not
oc rollout latest dc/sdi-observer
sleep 1
oc rollout status -w dc/sdi-observer

args=( rsh dc/sdi-observer )
if [[ "${ENTER_THE_SHELL:-0}" == 0 ]]; then
    args+=( /bin/bash /observer.sh )
fi

exec oc rsh dc/sdi-observer "${args[@]}"

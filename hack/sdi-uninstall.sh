#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly DEFAULT_TIMEOUT=35
TIMEOUT=$DEFAULT_TIMEOUT

# TODO: specify volume capacity
readonly USAGE="$(basename "${BASH_SOURCE[0]}") [options]

Deploy container image registry for SAP Data Intelligence.

Options:
  -h | --help       Show this message and exit.
  -n | --namespace SDI_NAMESPACE
                    SDI namespace.
  -s | --slcb-namespace SLCB_NAMESPACE
                    Namespace where SLC Bridge is installed.
  -t | --timeout TIMEOUT
                    Defaults to ${DEFAULT_TIMEOUT}s
"

function forceDeleteResource() {
    set -x
    local crd="$1"
    local nm="$2"
    local name="$3"
    oc patch -n "$nm" "$crd/$name" --type merge -p '{"metadata":{"finalizers":null}}'
    oc delete --timeout "${TIMEOUT}s" --wait -n "$nm" "$crd/$name" ||:
    if ! oc get -n "$nm" "$crd/$name" >/dev/null 2>&1; then
        return 0
    fi
    oc delete --timeout "${TIMEOUT}s" --wait --force --grace-period=0 -n "$nm" "$crd/$name"
}
export -f forceDeleteResource

function deleteCRD() {
    set -x
    local crd="$1"
    local resources=()
    local rsnm nm name
    export TIMEOUT

    # we expect all the resources to be namespaces
    readarray -t resources <<<"$(oc get --all-namespaces "$crd" \
            -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' ||:)"
    if [[ "${#resources[@]}" -gt 1 || ( "${#resources[@]}" == 1 && -n "${resources[0]:-}" ) ]]; then
        for rsnm in "${resources[@]}"; do
            if [[ -z "${rsnm:-}" ]]; then
                printf 'empty rsnm!\n' >&2
                continue
            fi
            IFS=/ read -r nm name <<<"${rsnm}"
            parallel --lb --semaphore --id "del-$crd" \
                oc delete --timeout "${TIMEOUT}s" --wait -n "$nm" "$crd/$name"
        done
        parallel --lb --semaphore --id "del-$crd" --wait ||:

        readarray -t resources <<<"$(oc get --all-namespaces "$crd" \
            -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' ||:)"
        if [[ "$crd" =~ ^datahub ]]; then
            oc delete validatingwebhookconfiguration validating-webhook-configuration --ignore-not-found
        fi
        if [[ "${#resources[@]}" -gt 1 || ( "${#resources[@]}" == 1 && -n "${resources[0]:-}" ) ]]; then
            for rsnm in "${resources[@]}"; do
                if [[ -z "${rsnm:-}" ]]; then
                    printf 'empty rsnm!\n' >&2
                    continue
                fi
                IFS=/ read -r nm name <<<"${rsnm}"
                parallel --lb --semaphore --id "del-$crd" forceDeleteResource "$crd" "$nm" "$name"
            done
            parallel --lb --semaphore --id "del-$crd" --wait ||:
        fi
    fi

    if ! oc delete --timeout "${TIMEOUT}s" --wait "crd/$crd" && oc get "crd/$crd" >/dev/null 2>&1; then
        oc patch -n "$nm" "crd/$crd" --type merge -p '{"metadata":{"finalizers":null}}'
        oc delete --timeout "${TIMEOUT}s" --wait "crd/$crd"
    fi
}
export -f deleteCRD

readarray -t crds <<<"$(oc get crd | awk '/\.sap\./ {print $1}')"

# TODO: make sure to delete datahub-system project as well

if [[ "${#crds[@]}" -gt 0 ]]; then
    export TIMEOUT
    parallel --lb deleteCRD ::: "${crds[@]}"
fi

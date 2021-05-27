#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'


# TODO: specify volume capacity
readonly USAGE="$(basename "${BASH_SOURCE[0]}") [options]

Deploy container image registry for SAP Data Intelligence.

Options:
  -h | --help       Show this message and exit.
  -n | --namespace SDI_NAMESPACE
                    SDI namespace.
  -s | --slcb-namespace SLCB_NAMESPACE
                    Namespace where SLC Bridge is installed.
"

function forceDeleteResource() {
    set -x
    local crd="$1"
    local nm="$2"
    local name="$3"
    oc patch -n "$nm" "$crd/$name" --type merge -p '{"metadata":{"finalizers":null}}'
    oc delete --timeout 21s --wait -n "$nm" "$crd/$name" ||:
    if ! oc get -n "$nm" "$crd/$name" >/dev/null 2>&1; then
        return 0
    fi
    oc delete --timeout 21s --wait --force --grace-period=0 -n "$nm" "$crd/$name"
}
export -f forceDeleteResource

function deleteCRD() {
    set -x
    local crd="$1"
    local resources=()
    local rsnm nm name

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
            parallel --semaphore --id "del-$crd" \
                oc delete --timeout 21s --wait -n "$nm" "$crd/$name"
        done
        parallel --semaphore --id "del-$crd" --wait ||:

        readarray -t resources <<<"$(oc get --all-namespaces "$crd" \
            -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' ||:)"
        if [[ "${#resources[@]}" -gt 1 || ( "${#resources[@]}" == 1 && -n "${resources[0]:-}" ) ]]; then
            for rsnm in "${resources[@]}"; do
                if [[ -z "${rsnm:-}" ]]; then
                    printf 'empty rsnm!\n' >&2
                    continue
                fi
                IFS=/ read -r nm name <<<"${rsnm}"
                parallel --semaphore --id "del-$crd" forceDeleteResource "$crd" "$nm" "$name"
            done
            parallel --semaphore --id "del-$crd" --wait ||:
        fi
    fi

    oc delete --timeout 21s --wait "crd/$crd"
}
export -f deleteCRD

readarray -t crds <<<"$(oc get crd | awk '/\.sap\./ {print $1}')"

if [[ "${#crds[@]}" -gt 0 ]]; then
    parallel deleteCRD ::: "${crds[@]}"
fi

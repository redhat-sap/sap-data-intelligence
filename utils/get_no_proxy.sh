#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

usage="$(basename "${BASH_SOURCE[0]}") [Options] [domain.ltd,...]

Generates NO_PROXY settings for SAP Data Intelligence installation requiring HTTP proxy to access
external resources. Alternatively, it can also generate NO_PROXY value for SLC Bridge, which is
used during the SLC Bridge init. Additional hostnames can be given as arguments.

Requirements:
- OpenShift client binaries (oc) must be installed and located in PATH.
- The user must authenticated to the OpenShift cluster and be at least the cluster-reader. 
- awk in PATH

Options:
  -h | --help       Show this help message and exit.
  -s | --slcbridge
                    Compute NO_PROXY for SLC Bridge init instead of SAP DI.
  -d | --sdi        Compute NO_PROXY for SAP DI."
readonly usage

readonly mustHave=(
    127.0.0.1

    localhost

    *.svc
    *.cluster.local
)

readonly mustHaveSDI=(
    169.254.169.254

    auditlog
    datalake
    diagnostics-prometheus-pushgateway
    hana-service
    storagegateway
    uaa
    vora-consul
    vora-dlog
    vora-prometheus-pushgateway
    vsystem
    vsystem-internal

    *.internal
)

readonly longOptions=(
    help slcb sdi
)

function normalize() {
    local entry
    for entry in "$@"; do
        # shellcheck disable=SC2001
        if [[ "${entry}" =~ , ]]; then
            local entries=()
            readarray -t entries < <(tr ',' '\n' <<<"${entry}")
            normalize "${entries[@]}"
            continue
        fi
        entry="$(sed \
            -e 's/\([[:space:]]\|,\)\+//g' \
            -e 's/\.\+/./g' \
            -e 's/\*\+/*/g' <<<"${entry:-}")"
        if [[ -z "${entry:-}" ]]; then
            continue
        fi
        case "${mode:-sdi}" in
            slcb)
                entry="${entry##\*}"
                ;;
            *)
                if [[ "$entry" =~ ^\. ]]; then
                    printf '*%s\n' "$entry"
                    continue
                fi
                ;;
        esac
        printf '%s\n' "$entry"
    done
}

function joinFromStdin() {
    awk '{
        if ($0 ~ /^[*.]/) {
            if (wildcards[$0]++ == 0) {
                wildcardList[length(wildcardList)] = $0
            }
        } else {
            if (nonWildcards[$0]++ == 0) {
                nonWildcardList[length(nonWildcardList)] = $0
            }
        }
    }
    BEGIN {
        split("", nonWildcardList)
        split("", wildcardList)
    }
    END {
        for (i in nonWildcardList) {
            print nonWildcardList[i]
        }
        // wildcard domains must be at the end of NO_PROXY as of SLCB 1.1.72
        for (i in wildcardList) {
            print wildcardList[i]
        }
    }'
}

function join() { local IFS="$1"; shift; echo "$*"; }

function getOpenShiftNoProxyOrDie() {
    local osNoProxy
    osNoProxy="$(oc get proxy/cluster -o jsonpath='{.status.noProxy}')"
    if [[ -z "${osNoProxy:-}" ]]; then
        printf 'Failed to determine noProxy from OpenShift cluster!\n' >&2
        printf 'Please configure noProxy first on the OpenShift cluster\n' >&2
        printf 'and make sure the current user can read it.\n' >&2
        exit 1
    fi
    printf '%s' "$osNoProxy"
}

function computeNoProxy() {
    local osNoProxy=() entries=()
    readarray -t osNoProxy < <(getOpenShiftNoProxyOrDie | tr ',' '\n')
    readarray -t entries < <({ \
        normalize "${osNoProxy[@]}" "$@" "${mustHave[@]}"; \
        if [[ "${mode:-sdi}" == sdi ]]; then \
            printf '%s\n' "${mustHaveSDI[@]}"; \
        fi \
    } | joinFromStdin)
    join , "${entries[@]}"
}

TMPARGS="$(getopt -o hsd -l "$(join , "${longOptions[@]}")" -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

mode=sdi

while true; do 
    case "$1" in
        -h | --help)
            printf '%s\n' "$usage"
            exit 0
            ;;
        -s | --slcb)
            mode=slcb
            shift
            ;;
        -d | --sdi)
            mode=sdi
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'Unknown argument "%s"!\n' "$1" >&2
            exit 1
            ;;
    esac
done

computeNoProxy "$@"

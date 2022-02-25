#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

usage="$(basename "${BASH_SOURCE[0]}") [Options] [domain.ltd,...] [!excluded.domain]

Generates NO_PROXY settings for SAP Data Intelligence installation requiring HTTP proxy to access
external resources. Alternatively, it can also generate NO_PROXY value for SLC Bridge, which is
used during the SLC Bridge init.

Additional hostnames can be given as arguments. If a domain is prefixed with '!', it will be
excluded from the list. IOW, it will be proxied.

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
    local selectExcluded=0
    if [[ "${1:-}" == -e ]]; then
        selectExcluded=1
        shift
    fi

    for entry in "$@"; do
        # shellcheck disable=SC2001
        if [[ "${entry}" =~ , ]]; then
            local entries=()
            readarray -t entries < <(tr ',' '\n' <<<"${entry}")
            local args=()
            if [[ "$selectExcluded" == 1 ]]; then
                args+=( -e )
            fi
            # shellcheck disable=SC2068
            normalize ${args[@]} "${entries[@]}"
            continue
        fi

        entry="$(sed \
            -e 's/\([[:space:]]\|,\)\+//g' \
            -e 's/\.\+/./g' \
            -e 's/\!\+/!/g' \
            -e 's/\*\+/*/g' <<<"${entry:-}")"
        if [[ -z "${entry:-}" ]]; then
            continue
        fi

        case "$selectExcluded$entry" in
            "0!"*)
                continue
                ;;
            "1!"*)
                entry="${entry##\!}"
                ;;
            "1"*)
                continue
                ;;
        esac

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

function setExcludes() {
    readarray -t excludes < <(normalize -e "$@")
    if [[ "${#excludes[@]}" == 1 && -z "${excludes[0]:-}" ]]; then
        excludes=()
    fi
}

function filterOutExcludes() {
    if [[ "${#excludes[@]}" == 0 ]]; then
        cat /dev/stdin
        return 0
    fi
    grep -v -F -f <(printf '%s\n' "${excludes[@]}") /dev/stdin
}

function assertDependencies() {
    if [[ -z "$(command -v oc)" ]]; then
        printf 'Please ensure oc binary is in PATH and its minor release matches the server!\n' >&2
        exit 1
    fi
    if ! oc auth can-i list proxies.config.openshift.io --all-namespaces >/dev/null; then
        printf 'Please ensure the current OpenShift user is logged-in and has at least the' >&2
        printf ' cluster-reader role.\n' >&2
        exit 1
    fi
}

function computeNoProxy() {
    local osNoProxy=() entries=()
    readarray -t osNoProxy < <(getOpenShiftNoProxyOrDie | tr ',' '\n')
    readarray -t entries < <({ \
        normalize "${osNoProxy[@]}" "$@" "${mustHave[@]}"; \
        if [[ "${mode:-sdi}" == sdi ]]; then \
            printf '%s\n' "${mustHaveSDI[@]}"; \
        fi \
    } | joinFromStdin | filterOutExcludes)
    join , "${entries[@]}"
}

TMPARGS="$(getopt -o hsd -l "$(join , "${longOptions[@]}")" -n "${BASH_SOURCE[0]}" -- "$@")"
eval set -- "$TMPARGS"

mode=sdi
excludes=()

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

assertDependencies
setExcludes "$@"
computeNoProxy "$@"

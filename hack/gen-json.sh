#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly USAGE="$(basename "${BASH_SOURCE[0]}") [OPTIONS]

Generate json files containing OpenShift teplates.

Options:
  -h | --help       Show this help message and exit.
  -v | --version VERSION
                    Version of SDI Observer that will be recorded in the generated files."

readonly longOptions=(
    help version:
)

function join() { local IFS="$1"; shift; echo "$*"; }

TMPARGS="$(getopt -o hv: --long "$(join , "${longOptions[@]}")" \
    --name "$(basename "${BASH_SOURCE[0]}")" -- "$@")"

eval set -- "$TMPARGS"

root="$(dirname "$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")")"

version=""

while true; do
    case "${1:-}" in
        -h | --help)
            printf '%s\n' "${USAGE}"
            exit 0
            ;;
        -v | --version)
            version="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            printf 'Unsupported option "%s"!\nSee help!\n' "${1:-}" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${version:-}" ]]; then
    printf 'Please specify the desired version!\n' >&2
    exit 1
fi

pushd "$root"
    jsonnet --tla-str "version=$version" -J src -m . main.jsonnet
popd

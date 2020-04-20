#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

root="$(dirname "$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")")"

pushd "$root"
    jsonnet -J src -m . main.jsonnet
popd

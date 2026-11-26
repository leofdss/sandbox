#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ ! -x "${ROOT_DIR}/blackbox/sandbox" ]]; then
    printf 'sandbox.sh: roteador não encontrado ou sem permissão de execução: %s\n' \
        "${ROOT_DIR}/blackbox/sandbox" >&2
    exit 1
fi

exec "${ROOT_DIR}/blackbox/sandbox" "$@"

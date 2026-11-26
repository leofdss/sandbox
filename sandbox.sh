#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ ! -x "${ROOT_DIR}/blackbox/sandbox" ]]; then
    printf 'sandbox.sh: roteador não encontrado ou sem permissão de execução: %s\n' \
        "${ROOT_DIR}/blackbox/sandbox" >&2
    exit 1
fi

# Repositório público: lembrar de ativar o hook que bloqueia chaves em commits.
if [[ -d "${ROOT_DIR}/.git" ]] && \
   [[ "$(git -C "${ROOT_DIR}" config --get core.hooksPath 2>/dev/null || true)" != ".githooks" ]]; then
    printf 'sandbox.sh: aviso: o hook anti-segredos não está ativo. Ative com:\n' >&2
    printf '    git -C %q config core.hooksPath .githooks\n' "${ROOT_DIR}" >&2
fi

exec "${ROOT_DIR}/blackbox/sandbox" "$@"

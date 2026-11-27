#!/usr/bin/env bash
set -euo pipefail

umask 077

if [[ "$(id -u)" != "1000" ]]; then
    echo "sandbox: expected UID 1000, got $(id -u)." >&2
    echo "Use the supplied Compose files; do not run this image as root." >&2
    exit 1
fi

export HOME="${HOME:-/home/podman}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

mkdir -p \
    "${XDG_CONFIG_HOME}/opencode" \
    "${XDG_DATA_HOME}/opencode" \
    "${XDG_DATA_HOME}/containers" \
    "${XDG_CACHE_HOME}/opencode" \
    "${XDG_RUNTIME_DIR}/containers" \
    "${XDG_RUNTIME_DIR}/pulse"
chmod 0700 "${XDG_RUNTIME_DIR}" "${XDG_RUNTIME_DIR}/pulse"

if [[ "$#" -eq 0 ]]; then
    set -- fish --login
fi

exec "$@"

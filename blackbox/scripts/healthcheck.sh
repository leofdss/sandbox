#!/usr/bin/env bash
set -euo pipefail

command -v opencode >/dev/null
command -v git >/dev/null
command -v podman >/dev/null
command -v podman-compose >/dev/null
test -w /workspace
timeout 10 podman info --format '{{.Store.GraphDriverName}}' >/dev/null

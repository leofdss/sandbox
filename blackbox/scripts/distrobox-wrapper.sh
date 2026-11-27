#!/usr/bin/env bash
# Runs the real /usr/bin/distrobox* command with the sandbox podman shim
# first in PATH (see distrobox-podman.sh). Installed as symlinks in
# /usr/local/bin, which precedes /usr/bin in PATH.
set -euo pipefail
export PATH="/usr/local/libexec/sandbox/distrobox-bin:${PATH}"
exec "/usr/bin/$(basename -- "$0")" "$@"

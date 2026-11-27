#!/usr/bin/env bash
# Podman shim used only by distrobox. The distrobox wrappers in
# /usr/local/bin put this file first in PATH as "podman"; every other caller
# uses /usr/bin/podman directly.
#
# distrobox hardcodes two create flags that cannot work in this sandbox:
#   --hostname  nested containers cannot call sethostname(2): the outer
#               seccomp profile allows it only with CAP_SYS_ADMIN, which the
#               sandbox deliberately lacks (scripts/validate.sh I-04/I-05).
#               The distrobox keeps the sandbox hostname.
#   --pid host  the nested containers.conf sets cgroups="disabled", which
#               Podman only accepts with a private PID namespace.
# It also pins --log-driver k8s-file: distrobox-enter follows the container
# logs, which journald cannot do with the nested file events backend.
# Only "create" is rewritten; all other subcommands pass through unchanged.
set -euo pipefail

if [[ "${1:-}" != "create" ]]; then
    exec /usr/bin/podman "$@"
fi

args=(create --log-driver k8s-file)
shift
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --hostname) shift; [[ "$#" -gt 0 ]] && shift; continue ;;
        --hostname=*) shift; continue ;;
        --pid) args+=(--pid private); shift; [[ "$#" -gt 0 ]] && shift; continue ;;
        --pid=*) args+=(--pid=private); shift; continue ;;
    esac
    args+=("$1")
    shift
done
exec /usr/bin/podman "${args[@]}"

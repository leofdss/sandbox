#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '== Identity and tools =='
id
opencode --version
git --version
podman --version
podman-compose --version
python3 --version
node --version

printf '%s\n' '== Workspace =='
test -w /workspace
probe="/workspace/.sandbox-write-test.$$"
trap 'rm -f "${probe}"' EXIT
printf 'ok\n' >"${probe}"
test "$(cat "${probe}")" = "ok"
printf 'workspace writable: ok\n'

printf '%s\n' '== Egress containment =='
# The agent network is internal: no default route and no external DNS.
if awk 'NR > 1 && $2 == "00000000" { found = 1 } END { exit !found }' /proc/net/route; then
    echo 'FAIL: default route present; the sandbox is not on the internal network' >&2
    exit 1
fi
printf 'default route: none\n'
if timeout 5 getent hosts example.com >/dev/null 2>&1; then
    echo 'FAIL: external DNS resolves without the proxy' >&2
    exit 1
fi
printf 'external DNS: blocked\n'
if timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' 2>/dev/null; then
    echo 'FAIL: direct TCP connection bypassing the proxy succeeded' >&2
    exit 1
fi
printf 'direct TCP egress: blocked\n'
# Through the proxy: allowlisted host works, other hosts and ports do not.
timeout 20 curl -fsS -o /dev/null https://api.github.com/zen
printf 'allowlisted host via proxy: ok\n'
if timeout 20 curl -fsS -o /dev/null https://example.com 2>/dev/null; then
    echo 'FAIL: non-allowlisted host reachable through the proxy' >&2
    exit 1
fi
printf 'non-allowlisted host via proxy: denied\n'
if timeout 20 curl -fsS -o /dev/null https://github.com:22 2>/dev/null; then
    echo 'FAIL: proxy tunnels to a non-TLS port' >&2
    exit 1
fi
printf 'non-443 CONNECT via proxy: denied\n'

printf '%s\n' '== Nested rootless Podman =='
test ! -e /run/user/1000/podman/podman.sock
test -c /dev/fuse
podman info --format 'driver={{.Store.GraphDriverName}} rootless={{.Host.Security.Rootless}} network={{.Host.NetworkBackend}}'

if [[ "${VERIFY_PULL:-1}" == "1" ]]; then
    podman run --rm \
        --network=none \
        --read-only \
        --cap-drop=ALL \
        --security-opt=label=disable \
        --tmpfs=/tmp:rw,nosuid,nodev \
        docker.io/library/busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec \
        echo 'nested container: ok'
else
    printf 'nested image execution: skipped (VERIFY_PULL=0)\n'
fi

if [[ "${VERIFY_GUI:-0}" == "1" ]]; then
    printf '%s\n' '== Wayland =='
    test -n "${WAYLAND_DISPLAY:-}"
    test -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    timeout 15 wayland-info >/dev/null
    printf 'Wayland connection: ok\n'

    if [[ -n "${DISPLAY:-}" && -d /tmp/.X11-unix ]]; then
        printf '%s\n' '== X11 compatibility =='
        timeout 15 xdpyinfo >/dev/null
        printf 'X11 connection: ok\n'
    fi

    if [[ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]]; then
        printf '%s\n' '== PipeWire =='
        timeout 15 pw-cli info 0 >/dev/null
        printf 'PipeWire connection: ok\n'
    elif [[ -n "${PULSE_SERVER:-}" ]]; then
        printf '%s\n' '== PulseAudio compatibility =='
        timeout 15 pactl info >/dev/null
        printf 'PulseAudio connection: ok\n'
    else
        printf '%s\n' 'audio: not configured (optional)'
    fi
fi

printf '%s\n' 'All requested checks passed.'

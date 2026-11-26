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

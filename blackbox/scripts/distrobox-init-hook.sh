#!/bin/sh
# Runs as root inside each new distrobox (container_init_hook in
# /etc/distrobox/distrobox.conf; the sandbox root is visible at /run/host).
# The only way out of the sandbox is the egress proxy, so the proxy variables
# must survive sudo: otherwise "sudo dnf/apt" tries direct DNS and fails.
set -eu
if [ -d /etc/sudoers.d ]; then
    printf '%s\n' 'Defaults env_keep += "HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy"' \
        > /etc/sudoers.d/90-sandbox-proxy
    chmod 0440 /etc/sudoers.d/90-sandbox-proxy
fi

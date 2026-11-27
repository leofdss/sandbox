# Interactive defaults for the sandbox only; fish is the login shell inside
# the container regardless of the host shell. Mirrors config/bashrc.sh.
set -gx EDITOR (set -q EDITOR; and echo $EDITOR; or echo nano)
set -gx GIT_PAGER (set -q GIT_PAGER; and echo $GIT_PAGER; or echo less)
set -gx PAGER (set -q PAGER; and echo $PAGER; or echo less)

# Do not inherit provider keys from the host. Connect providers explicitly
# inside the sandbox; credentials stay in the opencode-data named volume.

# Tools such as distrobox-enter and opencode pick the shell from $SHELL.
set -gx SHELL /usr/bin/fish

if status is-interactive
    set -g fish_greeting
    alias oc 'opencode --standalone'
    alias sandbox-check sandbox-verify

    # Image-managed prompt; a personal ~/.config/starship.toml takes precedence.
    if not set -q STARSHIP_CONFIG; and not test -f ~/.config/starship.toml
        set -gx STARSHIP_CONFIG /etc/starship.toml
    end
    starship init fish | source
end

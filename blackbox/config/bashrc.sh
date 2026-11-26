# Interactive defaults for the sandbox only.
alias oc='opencode --standalone'
alias sandbox-check='sandbox-verify'
export EDITOR="${EDITOR:-nano}"
export GIT_PAGER="${GIT_PAGER:-less}"
export PAGER="${PAGER:-less}"

# Do not inherit provider keys from the host. Connect providers explicitly
# inside the sandbox; credentials stay in the opencode-data named volume.

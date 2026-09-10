#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="gh-cli"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

KEYRING_PATH="/usr/share/keyrings/githubcli-archive-keyring.gpg"
SOURCE_PATH="/etc/apt/sources.list.d/github-cli.list"
KEYRING_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"

usage() {
    cat <<'EOF'
Usage: ./scripts/install-gh-cli.sh

Installs GitHub CLI from the official apt repository.
EOF
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        if is_help_token "$1"; then
            usage
            exit 0
        fi

        case "$1" in
            --*|-*)
                err "Unknown option: $1"
                usage
                return 1
                ;;
            *)
                err "Unexpected argument: $1"
                usage
                return 1
                ;;
        esac
    done
}

ensure_base_tools() {
    apt_prepare_repo_prereqs
}

configure_repository() {
    local arch
    local source_line

    require_commands dpkg

    arch="$(dpkg --print-architecture)"
    source_line="deb [arch=${arch} signed-by=${KEYRING_PATH}] https://cli.github.com/packages stable main"

    log "Configuring GitHub CLI apt repository"
    apt_configure_repo_with_keyring_and_source_line \
        "${KEYRING_URL}" \
        "${KEYRING_PATH}" \
        "${SOURCE_PATH}" \
        "${source_line}" \
        "0644"
}

install_gh() {
    reset_apt_update
    apt_install_missing gh
}

main() {
    parse_args "$@" || exit 1
    require_apt_environment
    ensure_base_tools
    configure_repository
    install_gh
    log "Completed"
}

main "$@"

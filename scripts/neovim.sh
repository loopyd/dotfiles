#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="neovim"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

WORK_DIR="${WORK_DIR:-/tmp/neovim-build}"
NEOVIM_REPO="https://github.com/neovim/neovim.git"

usage() {
    cat <<'EOF'
Usage: ./scripts/neovim.sh <install|update|uninstall|check>

Builds and installs the latest tagged Neovim release from source.
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

install_build_deps() {
    apt_install_missing \
        ninja-build \
        gettext \
        cmake \
        unzip \
        curl \
        build-essential
}

prepare_repo() {
    require_commands git

    if [[ -e "${WORK_DIR}" && ! -d "${WORK_DIR}/.git" ]]; then
        log "Removing non-git work directory at ${WORK_DIR}"
        rm -rf "${WORK_DIR}"
    fi

    if [[ ! -d "${WORK_DIR}/.git" ]]; then
        log "Cloning Neovim repository"
        git clone "${NEOVIM_REPO}" "${WORK_DIR}"
    fi

    log "Fetching latest tags"
    git -C "${WORK_DIR}" fetch --tags --force

    local latest_tag
    latest_tag="$(git -C "${WORK_DIR}" tag --sort=-v:refname | head -n1)"
    if [[ -z "${latest_tag}" ]]; then
        err "Unable to determine latest Neovim tag"
        exit 1
    fi

    log "Checking out ${latest_tag}"
    git -C "${WORK_DIR}" checkout --force "${latest_tag}"
}

build_and_install() {
    log "Building Neovim"
    make -C "${WORK_DIR}" distclean >/dev/null 2>&1 || true
    make -C "${WORK_DIR}" CMAKE_BUILD_TYPE=RelWithDebInfo

    log "Installing Neovim"
    safe_sudo make -C "${WORK_DIR}" install
}

validate() {
    if ! command -v nvim >/dev/null 2>&1; then
        err "nvim command not found after install"
        exit 1
    fi

    log "Installed: $(nvim --version | head -n1)"
}

main() {
    parse_args "$@" || exit 1
    require_apt_environment
    install_build_deps
    prepare_repo
    build_and_install
    validate
    log "Completed"
}

lifecycle_dispatch neovim "$@"

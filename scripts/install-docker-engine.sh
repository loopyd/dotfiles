#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="docker"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

DOCKER_GPG_PATH="/etc/apt/keyrings/docker.asc"
DOCKER_SOURCE_PATH="/etc/apt/sources.list.d/docker.list"
ADD_GROUP_USER="${ADD_GROUP_USER:-true}"
DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"

usage() {
    cat <<'EOF'
Usage: ./scripts/install-docker-engine.sh [--skip-group]

Options:
  --skip-group   Do not add current user to docker group
  -h, --help     Show help
EOF
}

ensure_base_tools() {
    apt_prepare_repo_prereqs_extra lsb-release
}

configure_repository() {
    local arch codename source_line

    require_commands dpkg

    arch="$(dpkg --print-architecture)"
    codename="$(resolve_ubuntu_codename)"
    source_line="deb [arch=${arch} signed-by=${DOCKER_GPG_PATH}] https://download.docker.com/linux/ubuntu ${codename} stable"

    log "Configuring Docker apt repository"
    apt_configure_repo_with_keyring_and_source_line \
        "${DOCKER_GPG_URL}" \
        "${DOCKER_GPG_PATH}" \
        "${DOCKER_SOURCE_PATH}" \
        "${source_line}" \
        "0644"
}

install_packages() {
    reset_apt_update
    apt_install_missing \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
}

configure_group() {
    local user_name

    if [[ "${ADD_GROUP_USER}" != "true" ]]; then
        log "Skipping docker group assignment by configuration"
        return 0
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        user_name="${SUDO_USER:-}"
    else
        user_name="${USER:-}"
    fi

    if [[ -z "${user_name}" ]]; then
        log "No target user detected for docker group assignment"
        return 0
    fi

    if ! getent group docker >/dev/null 2>&1; then
        log "Creating docker group"
        safe_sudo groupadd docker
    fi

    if id -nG "${user_name}" | tr ' ' '\n' | grep -Fxq docker; then
        log "User ${user_name} is already in docker group"
        return 0
    fi

    log "Adding ${user_name} to docker group"
    safe_sudo usermod -aG docker "${user_name}"
    log "Group membership updated. Re-login is required for non-root docker usage"
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        if is_help_token "$1"; then
            usage
            exit 0
        fi

        case "$1" in
            --skip-group)
                ADD_GROUP_USER="false"
                shift
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    require_apt_environment
    ensure_base_tools
    configure_repository
    install_packages
    configure_group
    log "Completed"
}

main "$@"

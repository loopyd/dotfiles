#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="nvidia-toolkit"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

KEYRING_PATH="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
SOURCE_PATH="/etc/apt/sources.list.d/nvidia-container-toolkit.list"
SKIP_DRIVER_CHECK="${SKIP_DRIVER_CHECK:-false}"
KEYRING_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
LIST_URL="https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list"

usage() {
    cat <<'EOF'
Usage: ./scripts/nvidia.sh <install|update|uninstall|check> [--skip-driver-check]

Options:
  --skip-driver-check   Skip nvidia-smi driver preflight
  -h, --help            Show help
EOF
}

preflight_driver() {
    if [[ "${SKIP_DRIVER_CHECK}" == "true" ]]; then
        log "Skipping NVIDIA driver preflight by configuration"
        return 0
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        err "nvidia-smi not found. Install NVIDIA driver first, or pass --skip-driver-check"
        exit 1
    fi

    if ! nvidia-smi >/dev/null 2>&1; then
        err "nvidia-smi check failed. NVIDIA driver appears unavailable"
        exit 1
    fi

    log "NVIDIA driver preflight passed"
}

ensure_base_tools() {
    apt_prepare_repo_prereqs
}

configure_repository() {
    require_commands gpg sed

    log "Configuring NVIDIA Container Toolkit apt repository"
    apt_install_keyring_from_stream "${KEYRING_URL}" "${KEYRING_PATH}" "0644" gpg --dearmor
    apt_write_source_from_stream "${LIST_URL}" "${SOURCE_PATH}" sed "s#deb https://#deb [signed-by=${KEYRING_PATH}] https://#"
    apt_mark_index_stale
}

install_toolkit() {
    reset_apt_update
    apt_install_missing nvidia-container-toolkit
}

configure_docker_runtime() {
    if ! command -v nvidia-ctk >/dev/null 2>&1; then
        err "nvidia-ctk not found after install"
        exit 1
    fi

    log "Configuring Docker runtime with nvidia-ctk"
    safe_sudo nvidia-ctk runtime configure --runtime=docker

    with_systemctl_or_log "Docker restart" systemctl restart docker
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        if is_help_token "$1"; then
            usage
            exit 0
        fi

        case "$1" in
            --skip-driver-check)
                SKIP_DRIVER_CHECK="true"
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
    preflight_driver
    ensure_base_tools
    configure_repository
    install_toolkit
    configure_docker_runtime
    log "Completed"
}

lifecycle_dispatch nvidia "$@"

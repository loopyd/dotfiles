#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG=easyllama
source "${SCRIPT_DIR}/delib.sh"
START_SERVICES=true
IMAGES_DIR=""

usage() {
    printf '%s\n' 'Usage: easyllama.sh <install|update|uninstall|check> [--dry-run] [--no-start] [--images-dir PATH]' \
        'Uses captured EasyLlama 0.6.0 local images; never rebuilds floating sources or deletes models.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --no-start) START_SERVICES=false ;;
            --images-dir) require_option_value "$1" "${2-}"; IMAGES_DIR="$2"; shift ;;
            *) err "Unknown option: $1"; return 2 ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user'; return 1; }
    require_commands docker python3 systemctl
    docker info >/dev/null
    local -a options=()
    [[ -z "${IMAGES_DIR}" ]] || options+=(--directory "${IMAGES_DIR}")
    python3 "${SCRIPT_DIR}/easyllama.py" images "${options[@]}"
    python3 "${SCRIPT_DIR}/easyllama.py" prepare
    systemctl --user daemon-reload
    systemctl --user enable easyllama.service
    if [[ "${START_SERVICES}" == true ]]; then
        if [[ "${LIFECYCLE_ACTION}" == update ]]; then
            systemctl --user restart easyllama.service
        else
            systemctl --user start easyllama.service
        fi
        python3 "${SCRIPT_DIR}/easyllama.py" check
    fi
}

lifecycle_dispatch easyllama "$@"

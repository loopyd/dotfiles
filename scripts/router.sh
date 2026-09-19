#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG=router
source "${SCRIPT_DIR}/delib.sh"
START_SERVICES=true
BUILD_IMAGE=true
BUILD_TAG=""
BUILD_FORCE=false
COMPOSE=(docker compose --project-name 9router --file "${HOME}/.config/9router/compose.yaml")

usage() {
    printf '%s\n' 'Usage: router.sh <install|update|uninstall|check> [--no-start] [--no-build] [--tag TAG] [--force]' \
        'Builds the 9router image from the newest upstream release tag (or --tag) before starting.' \
        'Data and credentials survive uninstall.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --no-start) START_SERVICES=false ;;
            --no-build) BUILD_IMAGE=false ;;
            --tag) require_option_value "$1" "${2-}"; BUILD_TAG="$2"; shift ;;
            --force) BUILD_FORCE=true ;;
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
    if [[ "${START_SERVICES}" == true ]]; then python3 "${SCRIPT_DIR}/router.py" ready; fi
    python3 "${SCRIPT_DIR}/router.py" prepare
    if [[ "${BUILD_IMAGE}" == true ]]; then
        local -a build_options=()
        [[ -z "${BUILD_TAG}" ]] || build_options+=(--tag "${BUILD_TAG}")
        [[ "${BUILD_FORCE}" != true ]] || build_options+=(--force)
        python3 "${SCRIPT_DIR}/router.py" build "${build_options[@]}"
    fi
    python3 "${SCRIPT_DIR}/router.py" initialize
    systemctl --user daemon-reload
    systemctl --user enable 9router.service
    if [[ "${START_SERVICES}" == true ]]; then
        if [[ "${LIFECYCLE_ACTION}" == update ]]; then
            systemctl --user restart 9router.service
        else
            systemctl --user start 9router.service
        fi
        python3 "${SCRIPT_DIR}/router.py" wait
    fi
}

lifecycle_dispatch router "$@"

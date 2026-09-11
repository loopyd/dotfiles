#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG=router
source "${SCRIPT_DIR}/delib.sh"
START_SERVICES=true
COMPOSE=(docker compose --project-name 9router --file "${HOME}/.config/9router/compose.yaml")

usage() {
    printf '%s\n' 'Usage: router.sh <install|update|uninstall|check> [--dry-run] [--no-start]' \
        'Uses the rendered Compose image pin; data and credentials survive uninstall.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --no-start) START_SERVICES=false ;;
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
    "${COMPOSE[@]}" pull --policy missing
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

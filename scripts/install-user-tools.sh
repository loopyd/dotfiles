#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="user-tools"
source "${SCRIPT_DIR}/delib.sh"

DRY_RUN=false
INCLUDE_RETIRED_PI=false

usage() {
    printf '%s\n' 'Usage: ./scripts/install-user-tools.sh [--dry-run] [--include-retired-pi]' \
        'Restore configured mise runtimes and versionless user packages after rendering dotfiles.' \
        'No sudo, system package writes, project virtualenv changes or automatic local Go rebuilds.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --include-retired-pi) INCLUDE_RETIRED_PI=true ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    require_commands python3
    local -a options=()
    if [[ "${DRY_RUN}" == true ]]; then
        bash "${SCRIPT_DIR}/install-mise.sh" --dry-run
        options+=(--dry-run)
    else
        [[ "${EUID}" -ne 0 ]] || { err 'Run as the destination user, not root'; return 1; }
        python3 "${SCRIPT_DIR}/packages.py" validate
        bash "${SCRIPT_DIR}/install-mise.sh"
    fi
    if [[ "${INCLUDE_RETIRED_PI}" == true ]]; then
        options+=(--include-retired-pi)
    fi
    python3 "${SCRIPT_DIR}/packages.py" restore "${options[@]}"
}

main "$@"

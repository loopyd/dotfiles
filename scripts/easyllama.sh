#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG=easyllama
source "${SCRIPT_DIR}/delib.sh"
START_SERVICES=true

usage() {
    printf '%s\n' 'Usage: easyllama.sh <install|update|uninstall|check> [--no-start]' \
        'Installs the systemd latch for the native EasyLlama stack. The checkout run.sh keeps owning' \
        'start/stop/restart; the unit adopts an already-running stack and holds it in the foreground.'
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
    python3 - "${SCRIPT_DIR}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from network import installed_helpers
installed_helpers(['easyllama.py', 'readiness.py'])
PY
    LIFECYCLE_PATHS=("${HOME}/.local/lib/dotfiles/easyllama.py")
    systemctl --user daemon-reload
    systemctl --user enable easyllama.service
    lifecycle_receipt record
    if [[ "${START_SERVICES}" == true ]]; then
        if [[ "${LIFECYCLE_ACTION}" == update ]]; then
            systemctl --user restart easyllama.service
        else
            systemctl --user start easyllama.service
        fi
    fi
}

lifecycle_dispatch easyllama "$@"

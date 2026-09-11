#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG=tailscale
source "${SCRIPT_DIR}/delib.sh"
START_SERVICES=true

usage() {
    printf '%s\n' 'Usage: tailscale.sh <install|update|uninstall|check> [--dry-run] [--no-start|--nostart]' \
        'Preserves the captured native host and its approved private HTTPS services.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --no-start|--nostart) START_SERVICES=false ;;
            -h|--help) usage; return ;;
            *) err "Unknown option: $1"; usage; return 2 ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user'; return 1; }
    require_commands python3 systemctl
    if ! command_exists tailscale; then
        local codename keyring=/usr/share/keyrings/tailscale-archive-keyring.gpg
        codename="$(resolve_ubuntu_codename)"
        [[ "${codename}" =~ ^[a-z]+$ ]] || { err 'Invalid Ubuntu base codename'; return 1; }
        apt_prepare_repo_prereqs
        apt_configure_repo_with_keyring_and_source_line \
            "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" "${keyring}" \
            /etc/apt/sources.list.d/tailscale.list \
            "deb [signed-by=${keyring}] https://pkgs.tailscale.com/stable/ubuntu ${codename} main"
        apt_install_missing tailscale
    elif [[ "${LIFECYCLE_ACTION}" == update ]]; then
        apt_install_missing tailscale
    fi
    python3 - "${SCRIPT_DIR}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from network import installed_helpers
installed_helpers(['tailscale.py', 'network.py'])
PY
    LIFECYCLE_PATHS=("${HOME}/.local/lib/dotfiles/tailscale.py")
    systemctl --user daemon-reload
    systemctl --user enable tailscale.service
    lifecycle_receipt record
    if [[ "${START_SERVICES}" == true ]]; then
        systemctl is-active --quiet tailscaled.service
        python3 "${HOME}/.local/lib/dotfiles/tailscale.py" preflight
        if [[ "${LIFECYCLE_ACTION}" == update ]]; then
            systemctl --user restart tailscale.service
        else
            systemctl --user start tailscale.service
        fi
        python3 "${HOME}/.local/lib/dotfiles/tailscale.py" check
    fi
}

lifecycle_dispatch tailscale "$@"

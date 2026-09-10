#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="herdr"
source "${SCRIPT_DIR}/delib.sh"
DRY_RUN=false
START=true
PLUGINS=true
CHECK=false
TEMP_BINARY=""
VERSION=0.8.2

usage() {
    printf '%s\n' 'Usage: ./scripts/install-herdr.sh [--dry-run] [--no-start] [--no-plugins] [--check]' \
        'Install herdr for the logged-in user, restore non-Pi plugins and enable its user unit.' \
        'Render private dotfiles first; existing binaries, sessions and active services are preserved.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --no-start) START=false ;;
            --no-plugins) PLUGINS=false ;;
            --check) CHECK=true ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

cleanup() {
    cleanup_paths_if_present "${TEMP_BINARY}"
}

main() {
    parse_args "$@"
    set_dry_run_mode "${DRY_RUN}"
    local architecture checksum
    case "$(uname -m)" in
        x86_64) architecture=x86_64; checksum=976150a14d490c94b243ea2e1a7eb2dfb67f12e36b182db90936f6728e6aecf4 ;;
        aarch64|arm64) architecture=aarch64; checksum=f55610658e1c2e0d2aaef730b4b2ab885f7f8ba00285ab372bfb14f2e3d5b40d ;;
        *) err 'Unsupported architecture'; return 1 ;;
    esac
    [[ "$(uname -s)" == Linux ]] || { err 'Linux is required'; return 1; }
    if [[ "${DRY_RUN}" != true ]]; then
        [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user'; return 1; }
        require_commands python3 systemctl
    fi
    run_maybe_dry python3 "${SCRIPT_DIR}/terminal.py" check-herdr
    if [[ "${CHECK}" == true ]]; then
        run_maybe_dry "${HOME}/.local/bin/herdr" --version
        return
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY-RUN: install verified herdr ${VERSION} (${architecture}) into ~/.local/bin when absent"
    elif [[ -x "${HOME}/.local/bin/herdr" ]]; then
        log 'Existing herdr binary preserved'
    else
        [[ ! -e "${HOME}/.local/bin/herdr" && ! -L "${HOME}/.local/bin/herdr" ]] || { err 'Existing herdr path needs manual review'; return 1; }
        require_commands curl sha256sum awk install mktemp
        trap cleanup EXIT
        mktemp_file_var TEMP_BINARY '/tmp/herdr-install.XXXXXX'
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            "https://github.com/herdrdev/herdr/releases/download/v${VERSION}/herdr-linux-${architecture}" -o "${TEMP_BINARY}"
        verify_file_sha256 "${TEMP_BINARY}" "${checksum}" herdr
        install -Dm0755 "${TEMP_BINARY}" "${HOME}/.local/bin/herdr"
    fi
    if [[ "${PLUGINS}" == true ]]; then
        if [[ "${DRY_RUN}" == true ]]; then
            python3 "${SCRIPT_DIR}/terminal.py" plugins --dry-run
        else
            python3 "${SCRIPT_DIR}/terminal.py" plugins
        fi
    fi
    run_maybe_dry systemctl --user daemon-reload
    run_maybe_dry systemctl --user enable herdr.service
    if [[ "${START}" == true ]]; then
        run_maybe_dry systemctl --user start herdr.service
        run_maybe_dry systemctl --user is-active --quiet herdr.service
    fi
    log 'No active service restart, workspace restoration or Pi plugin changes requested'
}

main "$@"

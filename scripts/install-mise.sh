#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="mise"
source "${SCRIPT_DIR}/delib.sh"

DRY_RUN=false
VERSION=2026.5.0
TEMP_ARCHIVE=""
TEMP_BINARY=""

usage() {
    printf '%s\n' 'Usage: ./scripts/install-mise.sh [--dry-run]' \
        'Install the checksum-pinned official mise binary into ~/.local/bin.' \
        'Existing mise installations are preserved; tool installation is separate.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

cleanup() {
    cleanup_paths_if_present "${TEMP_ARCHIVE}" "${TEMP_BINARY}"
}

main() {
    parse_args "$@"
    [[ "$(uname -s)" == Linux ]] || { err 'Linux is required'; return 1; }
    local architecture checksum
    case "$(uname -m)" in
        x86_64) architecture=x64; checksum=df2fd343a0c2117922bc705000ae163ff8fa623504132e3b27465a0d5f2eab23 ;;
        aarch64|arm64) architecture=arm64; checksum=ed6770970dc28b847b57f2ef01d0b25822ee1e4399c6b59d199a5993529820ff ;;
        *) err 'Only Linux amd64 and arm64 are supported'; return 1 ;;
    esac
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY-RUN: install checksum-verified mise ${VERSION} (${architecture}) into ~/.local/bin if missing"
        return
    fi
    [[ "${EUID}" -ne 0 ]] || { err 'Run as the destination user, not root'; return 1; }
    if [[ -x "${HOME}/.local/bin/mise" ]]; then
        "${HOME}/.local/bin/mise" --version
        log 'Existing mise preserved'
        return
    fi
    require_commands curl tar xz sha256sum awk install mktemp
    trap cleanup EXIT
    mktemp_file_var TEMP_ARCHIVE '/tmp/mise-archive.XXXXXX'
    mktemp_file_var TEMP_BINARY '/tmp/mise-binary.XXXXXX'
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        "https://github.com/jdx/mise/releases/download/v${VERSION}/mise-v${VERSION}-linux-${architecture}.tar.xz" -o "${TEMP_ARCHIVE}"
    verify_file_sha256 "${TEMP_ARCHIVE}" "${checksum}" 'mise archive'
    tar -xJOf "${TEMP_ARCHIVE}" mise/bin/mise > "${TEMP_BINARY}"
    install -Dm0755 "${TEMP_BINARY}" "${HOME}/.local/bin/mise"
    "${HOME}/.local/bin/mise" --version
}

main "$@"

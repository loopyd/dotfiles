#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="hindsight"
source "${SCRIPT_DIR}/delib.sh"

DRY_RUN=false
START_SERVICES=true
CHECK_ONLY=false
CLI_VERSION=0.9.2
RUNTIME_VERSION=0.5.3
TEMP_BINARY=""
COMPOSE=(docker compose --project-name hindsight --file "${HOME}/.config/hindsight/compose.yaml")

usage() {
    cat <<'EOF'
Usage: ./scripts/install-hindsight.sh [--dry-run] [--no-start] [--check]

Install the pinned CLI, stage the official coding-agent runtime, pull the
rendered digest-pinned containers and enable the database/app user units.
Run as the logged-in destination user after rendering private dotfiles.
Docker/Compose, Node >=22.15, npm and Python >=3.11 must already be installed.
9router/EasyLlama must be running before the Hindsight app can become healthy.

  --dry-run   Preview only: no downloads, sudo, writes or service changes
  --no-start  Install and enable user units without starting Hindsight
  --check     Validate rendered config and live authenticated services only
EOF
}

cleanup() {
    cleanup_paths_if_present "${TEMP_BINARY}"
}

install_clients() {
    local platform checksum
    case "$(uname -m)" in
        x86_64)
            platform=amd64
            checksum=463ecf45d2582b0ba966429b0c755969b6e57493ba8b7a8b60c56e95d020aa58
            ;;
        aarch64|arm64)
            platform=arm64
            checksum=5f11e3370ae78ae4f6419ad800e90d9f06737f5e8ebbf6c5a574d6d9ed139faa
            ;;
        *) err 'Only Linux amd64 and arm64 are supported'; return 1 ;;
    esac
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY-RUN: install verified Hindsight CLI ${CLI_VERSION} (${platform}) into ~/.local/bin"
        run_maybe_dry npm exec --yes "--package=@vectorize-io/hindsight-coding-agents@${RUNTIME_VERSION}" -- hindsight-coding-agents update
        return
    fi
    if [[ -f "${HOME}/.local/bin/hindsight" ]] && [[ "$(compute_sha256 "${HOME}/.local/bin/hindsight")" == "${checksum}" ]]; then
        log 'Pinned CLI is already installed'
    else
        mktemp_file_var TEMP_BINARY '/tmp/hindsight-cli.XXXXXX'
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            "https://github.com/vectorize-io/hindsight/releases/download/v${CLI_VERSION}/hindsight-linux-${platform}" -o "${TEMP_BINARY}"
        verify_file_sha256 "${TEMP_BINARY}" "${checksum}" 'Hindsight CLI'
        install -Dm0755 "${TEMP_BINARY}" "${HOME}/.local/bin/hindsight"
    fi
    if ! python3 "${SCRIPT_DIR}/hindsight.py" runtime --minimum "${RUNTIME_VERSION}"; then
        npm exec --yes "--package=@vectorize-io/hindsight-coding-agents@${RUNTIME_VERSION}" -- hindsight-coding-agents update
        python3 "${SCRIPT_DIR}/hindsight.py" runtime --minimum "${RUNTIME_VERSION}"
    fi
}

activate_services() {
    run_maybe_dry safe_sudo systemctl enable --now docker.service
    if [[ "${DRY_RUN}" != true ]] && ! docker info >/dev/null 2>&1; then
        err 'Docker is inaccessible to this user; log in again after Docker group setup. Do not run this installer as root.'
        return 1
    fi
    run_maybe_dry "${COMPOSE[@]}" pull --policy missing database app
    run_maybe_dry systemctl --user daemon-reload
    run_maybe_dry systemctl --user enable hindsight-db.service hindsight.service
    if [[ "${START_SERVICES}" == true ]]; then
        run_maybe_dry systemctl --user start hindsight-db.service
        run_maybe_dry systemctl --user start hindsight.service
        run_maybe_dry python3 "${SCRIPT_DIR}/hindsight.py" health
    fi
}

main() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --no-start) START_SERVICES=false ;;
            --check) CHECK_ONLY=true ;;
            -h|--help) usage; return ;;
            *) err "Unknown option: $1"; usage; return 1 ;;
        esac
        shift
    done
    set_dry_run_mode "${DRY_RUN}"
    [[ "$(uname -s)" == Linux ]] || { err 'Linux is required'; return 1; }
    if [[ "${DRY_RUN}" != true ]]; then
        [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user, not root'; return 1; }
        require_commands python3 docker systemctl
        systemctl --user show-environment >/dev/null
    fi
    run_maybe_dry python3 "${SCRIPT_DIR}/hindsight.py" preflight
    if [[ "${CHECK_ONLY}" == true ]]; then
        run_maybe_dry python3 "${SCRIPT_DIR}/hindsight.py" health
        return
    fi
    if [[ "${DRY_RUN}" != true ]]; then
        require_commands curl sha256sum awk install mktemp node npm
        node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 22 || (major === 22 && minor < 15)) process.exit(1)'
    fi
    trap cleanup EXIT
    install_clients
    activate_services
    log 'Completed; no bank creation, key rotation, database reset or lingering changes'
}

main "$@"

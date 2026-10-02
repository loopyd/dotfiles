#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="openspec"
source "${SCRIPT_DIR}/delib.sh"

DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: ./scripts/openspec.sh <install|update|uninstall|check> [--dry-run]

Maintain the global OpenSpec integration for the Pi and Codex coding agents.
The CLI comes from scripts/tools.sh (templates/packages.json); this component
regenerates agent files from the rendered global config. Codex skills go into
~/.agents/skills; Pi skills and prompts go into ~/.pi/agent/skills and prompts.
Run as the logged-in destination user after rendering private dotfiles.

  --dry-run   Preview only: no writes
  check       Validate the rendered config, receipt and installed artifacts
  uninstall   Remove only this component's recorded skills, prompts and staging

Project scaffolding uses the installed wrapper: openspec-init [PATH].
EOF
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            -h|--help) usage; return ;;
            *) err "Unknown option: $1"; usage; return 1 ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    set_dry_run_mode "${DRY_RUN}"
    if [[ "${DRY_RUN}" != true ]]; then
        [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user, not root'; return 1; }
        require_commands python3 node
    fi
    run_maybe_dry install -Dm0644 "${SCRIPT_DIR}/openspec.py" "${HOME}/.local/lib/dotfiles/openspec.py"
    run_maybe_dry install -Dm0644 "${SCRIPT_DIR}/../templates/openspec/config.yaml" "${HOME}/.local/lib/dotfiles/openspec-config.yaml"
    run_maybe_dry python3 "${SCRIPT_DIR}/openspec.py" sync
    log 'Completed; OpenSpec integration owned by scripts/openspec.py'
}

lifecycle_dispatch openspec "$@"

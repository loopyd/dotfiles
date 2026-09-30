#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="skills"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

usage() {
    cat <<'EOF'
Usage: ./scripts/skills.sh <sync|check|backup> [--dry-run] [--prune]

Maintain the shared skills captured under root/home/user/.agents/skills.
  sync    Capture ~/.agents/skills and ~/.pi/agent/agents into templates
  check   Fail when either capture is stale (with --prune: also upstream deletions)
  backup  Zip every live skill into ~/.agents/skills/archive/<skill>.zip

Options are forwarded to scripts/skills.py; --prune applies to sync and check only.
EOF
}

main() {
    local action="${1:-}"
    case "${action}" in
        -h|--help|help) usage; return 0 ;;
        sync|check|backup) ;;
        '') usage; return 2 ;;
        *) err "Unknown action: ${action}"; usage; return 2 ;;
    esac
    require_commands python3
    if [[ "${action}" == backup ]]; then
        [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user, not root'; return 1; }
    fi
    python3 "${SCRIPT_DIR}/skills.py" "$@"
}

main "$@"

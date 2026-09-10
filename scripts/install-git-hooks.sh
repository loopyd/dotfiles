#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export INSTALL_LIB_TAG="git-hooks"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

usage() {
	cat <<'EOF'
Usage: ./scripts/install-git-hooks.sh

Installs repository-local git hooks from .githooks.
EOF
}

parse_args() {
	while [[ "$#" -gt 0 ]]; do
		if is_help_token "$1"; then
			usage
			exit 0
		fi

		case "$1" in
			--*|-*)
				err "Unknown option: $1"
				usage
				return 1
				;;
			*)
				err "Unexpected argument: $1"
				usage
				return 1
				;;
		esac
	done
}

install_hooks() {
	require_commands git chmod

	cd "${REPO_ROOT}"

	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit

	log "Installed repository hooks path: .githooks"
	log "Enabled: .githooks/pre-commit"
}

main() {
	parse_args "$@" || exit 1
	install_hooks
}

main "$@"

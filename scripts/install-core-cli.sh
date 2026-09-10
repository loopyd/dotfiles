#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="core-cli"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

usage() {
    cat <<'EOF'
Usage: ./scripts/install-core-cli.sh

Installs baseline CLI/toolchain packages required by bootstrap.
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

main() {
    parse_args "$@" || exit 1
    require_apt_environment
    apt_install_missing \
        ca-certificates \
        curl \
        git \
        wget \
        unzip \
        xz-utils \
        build-essential \
        pkg-config \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        fish

    log "Completed"
}

main "$@"

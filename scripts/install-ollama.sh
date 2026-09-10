#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="ollama"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

MODE="${MODE:-script}"
SYSTEMD_MODE="${SYSTEMD_MODE:-true}"
OLLAMA_USER="${OLLAMA_USER:-ollama}"
INSTALL_SCRIPT_URL="${INSTALL_SCRIPT_URL:-https://ollama.com/install.sh}"
INSTALL_SCRIPT_SHA256="${INSTALL_SCRIPT_SHA256-25f64b810b947145095956533e1bdf56eacea2673c55a7e586be4515fc882c9f}"
TARBALL_URL="${TARBALL_URL:-}"
TARBALL_SHA256="${TARBALL_SHA256:-}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local}"
TEMP_SCRIPT=""
TEMP_TAR=""

# shellcheck disable=SC2034 # consumed indirectly via validate_install_dir_against_prefixes nameref.
declare -a OLLAMA_ALLOWED_INSTALL_PREFIXES=(
    "/"
)

usage() {
    cat <<'EOF'
Usage: ./scripts/install-ollama.sh [options]

Options:
  --mode <script|manual>   Install mode (default: script)
    --script-url <url>       Script URL for script mode (default: https://ollama.com/install.sh)
    --script-sha256 <hex>    Expected SHA256 for script mode
  --no-systemd             Do not enable/start ollama service
  --tarball-url <url>      Tarball URL for manual mode
    --tarball-sha256 <hex>   Expected SHA256 for manual mode tarball (required)
  --install-dir <path>     Install prefix for manual mode (default: /usr/local)
  -h, --help               Show help
EOF
}

cleanup_ollama_temp() {
    cleanup_paths_if_present "${TEMP_SCRIPT}" "${TEMP_TAR}"
}

validate_ollama_install_dir() {
    validate_install_dir_against_prefixes "${INSTALL_DIR}" OLLAMA_ALLOWED_INSTALL_PREFIXES "Ollama install directory"
}

install_with_script() {
    local expected_script_sha256=""

    require_commands curl mktemp bash sha256sum awk

    expected_script_sha256="$(validate_sha256_hex "${INSTALL_SCRIPT_SHA256}" "Ollama install script checksum" || true)"
    if [[ -z "${expected_script_sha256}" ]]; then
        err "Missing or invalid script checksum"
        err "Provide --script-sha256 <hex> (or INSTALL_SCRIPT_SHA256) to continue"
        exit 1
    fi

    mktemp_file_var TEMP_SCRIPT "/tmp/ollama-install.XXXXXX.sh"
    log "Downloading official Ollama install script"
    curl -fsSL "${INSTALL_SCRIPT_URL}" -o "${TEMP_SCRIPT}"
    verify_file_sha256 "${TEMP_SCRIPT}" "${expected_script_sha256}" "ollama install script"
    safe_sudo bash "${TEMP_SCRIPT}"
    cleanup_paths_if_present "${TEMP_SCRIPT}"
    TEMP_SCRIPT=""
}

install_manual() {
    local expected_tarball_sha256=""

    require_commands curl mktemp tar

    if [[ -z "${TARBALL_URL}" ]]; then
        err "--tarball-url is required in manual mode"
        exit 1
    fi
    if [[ -z "${TARBALL_SHA256}" ]]; then
        err "--tarball-sha256 is required in manual mode"
        exit 1
    fi

    expected_tarball_sha256="$(validate_sha256_hex "${TARBALL_SHA256}" "Ollama tarball checksum" || true)"
    if [[ -z "${expected_tarball_sha256}" ]]; then
        err "Invalid manual-mode tarball checksum"
        exit 1
    fi

    validate_ollama_install_dir
    mktemp_file_var TEMP_TAR "/tmp/ollama.XXXXXX.tgz"
    log "Downloading Ollama tarball"
    curl -fL "${TARBALL_URL}" -o "${TEMP_TAR}"
    verify_file_sha256 "${TEMP_TAR}" "${expected_tarball_sha256}" "ollama tarball"

    log "Extracting Ollama into ${INSTALL_DIR}"
    safe_sudo mkdir -p "${INSTALL_DIR}"
    safe_sudo tar -xzf "${TEMP_TAR}" -C "${INSTALL_DIR}"
    cleanup_paths_if_present "${TEMP_TAR}"
    TEMP_TAR=""
}

configure_systemd() {
    if [[ "${SYSTEMD_MODE}" != "true" ]]; then
        log "Systemd mode disabled"
        return 0
    fi

    if ! require_systemctl_or_fail "ollama systemd mode"; then
        err "systemctl not available, cannot enforce systemd mode"
        exit 1
    fi

    if id -u "${OLLAMA_USER}" >/dev/null 2>&1; then
        log "User ${OLLAMA_USER} already exists"
    else
        log "Creating system user ${OLLAMA_USER}"
        safe_sudo useradd -r -s /usr/sbin/nologin -m "${OLLAMA_USER}"
    fi

    log "Enabling and starting ollama service"
    safe_sudo systemctl daemon-reload
    safe_sudo systemctl enable --now ollama
}

validate_install() {
    if ! command -v ollama >/dev/null 2>&1; then
        err "ollama command not found after install"
        exit 1
    fi

    log "Installed: $(ollama --version 2>/dev/null || echo 'version check unavailable')"
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        if is_help_token "$1"; then
            usage
            exit 0
        fi

        case "$1" in
            --mode)
                require_option_value "$1" "${2-}" || exit 1
                MODE="${2:-}"
                shift 2
                ;;
            --script-url)
                require_option_value "$1" "${2-}" || exit 1
                INSTALL_SCRIPT_URL="${2:-}"
                shift 2
                ;;
            --script-sha256)
                require_option_value "$1" "${2-}" || exit 1
                INSTALL_SCRIPT_SHA256="${2:-}"
                shift 2
                ;;
            --no-systemd)
                SYSTEMD_MODE="false"
                shift
                ;;
            --tarball-url)
                require_option_value "$1" "${2-}" || exit 1
                TARBALL_URL="${2:-}"
                shift 2
                ;;
            --tarball-sha256)
                require_option_value "$1" "${2-}" || exit 1
                TARBALL_SHA256="${2:-}"
                shift 2
                ;;
            --install-dir)
                require_option_value "$1" "${2-}" || exit 1
                INSTALL_DIR="${2:-}"
                shift 2
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ "${MODE}" != "script" && "${MODE}" != "manual" ]]; then
        err "Invalid mode: ${MODE}"
        usage
        exit 1
    fi
}

main() {
    trap_cleanup_handler cleanup_ollama_temp
    parse_args "$@"

    case "${MODE}" in
        script)
            install_with_script
            ;;
        manual)
            install_manual
            ;;
    esac

    configure_systemd
    validate_install
    log "Completed"
}

main "$@"

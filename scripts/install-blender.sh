#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="blender"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

BLENDER_DEFAULT_VERSION="5.0.1"
BLENDER_DEFAULT_SHA256="8019580ee1b7262e505f4196a00237ccf743c88d205b38d34201510676e60b09"
BLENDER_VERSION="${BLENDER_VERSION:-${BLENDER_DEFAULT_VERSION}}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/blender}"
SYMLINK_PATH="${SYMLINK_PATH:-/usr/local/bin/blender}"
DESKTOP_ENTRY_PATH="${DESKTOP_ENTRY_PATH:-/usr/share/applications/blender.desktop}"
BLENDER_SHA256="${BLENDER_SHA256:-}"

# shellcheck disable=SC2034 # consumed indirectly via validate_install_dir_against_prefixes nameref.
declare -a BLENDER_ALLOWED_INSTALL_PREFIXES=(
    "/usr/local/blender"
    "/opt/blender"
    "${HOME}/.local/blender"
    "${HOME}/.local/opt/blender"
)

BLENDER_TAR=""
BLENDER_URL=""
BLENDER_TMP_TAR=""
BLENDER_TMP_DIR=""

usage() {
    cat <<'EOF'
Usage: ./scripts/install-blender.sh [options]

Options:
  --version <ver>         Blender version (default: 5.0.1)
  --install-dir <path>    Install directory (default: /usr/local/blender)
  --symlink-path <path>   Blender symlink target path (default: /usr/local/bin/blender)
  --desktop-entry <path>  Desktop entry path (default: /usr/share/applications/blender.desktop)
  -h, --help              Show help
EOF
}

refresh_blender_metadata() {
    BLENDER_TAR="blender-${BLENDER_VERSION}-linux-x64.tar.xz"
    BLENDER_URL="https://download.blender.org/release/Blender${BLENDER_VERSION%.*}/${BLENDER_TAR}"
}

validate_blender_install_dir() {
    validate_install_dir_against_prefixes "${INSTALL_DIR}" BLENDER_ALLOWED_INSTALL_PREFIXES "Install directory"
}

resolve_blender_sha256() {
    local fallback_sha256=""

    if [[ "${BLENDER_VERSION}" == "${BLENDER_DEFAULT_VERSION}" ]]; then
        fallback_sha256="${BLENDER_DEFAULT_SHA256}"
    fi

    resolve_sha256_with_fallback \
        "${BLENDER_SHA256}" \
        "BLENDER_SHA256" \
        "${fallback_sha256}" \
        "" \
        "" \
        "${BLENDER_TAR}" \
        "Set BLENDER_SHA256 to a trusted SHA256 value for non-default Blender versions"
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        if is_help_token "$1"; then
            usage
            exit 0
        fi

        case "$1" in
            --version)
                require_option_value "$1" "${2-}" || exit 1
                BLENDER_VERSION="${2}"
                shift 2
                ;;
            --install-dir)
                require_option_value "$1" "${2-}" || exit 1
                INSTALL_DIR="${2}"
                shift 2
                ;;
            --symlink-path)
                require_option_value "$1" "${2-}" || exit 1
                SYMLINK_PATH="${2}"
                shift 2
                ;;
            --desktop-entry)
                require_option_value "$1" "${2-}" || exit 1
                DESKTOP_ENTRY_PATH="${2}"
                shift 2
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

install_deps() {
    require_apt_environment
    apt_install_missing \
        ca-certificates \
        curl \
        xz-utils \
        libxi6 \
        libxrender1 \
        libxrandr2 \
        libxcursor1 \
        libxinerama1 \
        libfreetype6
}

install_blender() {
    if safe_sudo test -x "${INSTALL_DIR}/blender"; then
        local installed_version
        installed_version="$(safe_sudo "${INSTALL_DIR}/blender" --version 2>/dev/null | head -n1 || true)"
        if grep -Fq "${BLENDER_VERSION}" <<<"${installed_version}"; then
            log "Blender ${BLENDER_VERSION} already installed in ${INSTALL_DIR}"
            return 0
        fi
        log "Existing Blender install detected; refreshing to ${BLENDER_VERSION}"
    fi

    require_commands curl mktemp tar sha256sum awk
    validate_blender_install_dir

    trap_cleanup_handler 'cleanup_temp_vars BLENDER_TMP_DIR BLENDER_TMP_TAR'
    mktemp_file_var BLENDER_TMP_TAR "/tmp/blender.XXXXXX.tar.xz"
    mktemp_dir_var BLENDER_TMP_DIR "/tmp/blender.XXXXXX"

    log "Downloading Blender ${BLENDER_VERSION}"
    curl -fL "${BLENDER_URL}" -o "${BLENDER_TMP_TAR}"
    verify_archive_sha256_with_resolver "${BLENDER_TMP_TAR}" resolve_blender_sha256 "${BLENDER_TAR}"

    log "Installing Blender into ${INSTALL_DIR}"
    safe_sudo mkdir -p "${INSTALL_DIR}"
    safe_sudo rm -rf "${INSTALL_DIR:?}/"*
    safe_sudo tar -xf "${BLENDER_TMP_TAR}" -C "${BLENDER_TMP_DIR}"
    safe_sudo tar -xf "${BLENDER_TMP_TAR}" -C "${INSTALL_DIR}" --strip-components=1

    cleanup_temp_vars BLENDER_TMP_DIR BLENDER_TMP_TAR
    trap - EXIT INT TERM
}

configure_symlink() {
    local link_dir
    link_dir="$(dirname "${SYMLINK_PATH}")"

    safe_sudo mkdir -p "${link_dir}"
    safe_sudo ln -sfn "${INSTALL_DIR}/blender" "${SYMLINK_PATH}"
    log "Symlink set: ${SYMLINK_PATH} -> ${INSTALL_DIR}/blender"
}

configure_desktop_entry() {
    write_desktop_entry_from_stdin "${DESKTOP_ENTRY_PATH}" <<EOF
[Desktop Entry]
Name=Blender
Comment=3D modeling, animation, rendering and post-production
Exec=${SYMLINK_PATH} %f
Icon=${INSTALL_DIR}/blender.svg
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;
MimeType=application/x-blender;
EOF

    update_desktop_database_if_available "/usr/share/applications/"
}

main() {
    parse_args "$@"
    refresh_blender_metadata
    validate_blender_install_dir
    install_deps
    install_blender
    configure_symlink
    configure_desktop_entry
    log "Completed (${BLENDER_VERSION})"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
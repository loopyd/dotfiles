#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="reaper"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

REAPER_DEFAULT_VERSION="761"
REAPER_DEFAULT_SHA256_X86_64="362a1716250d3b64f3267d3186840a1166fc383ec70fc3beb0701fe1e9e8a718"
REAPER_DEFAULT_SHA256_AARCH64="a6540a648f62ca180749dc8229bcc94c5cab2ee68843e2c05dd12adc5eef87a3"
REAPER_VERSION="${REAPER_VERSION:-${REAPER_DEFAULT_VERSION}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt}"
ENABLE_LIB_SWELL="${ENABLE_LIB_SWELL:-true}"
REAPER_SHA256="${REAPER_SHA256:-}"
REAPER_DESKTOP_ENTRY="${REAPER_DESKTOP_ENTRY:-/usr/share/applications/reaper.desktop}"
WDL_SOURCE_URL="${WDL_SOURCE_URL:-https://www-dev.cockos.com/wdl/WDL.git}"
WDL_REF="${WDL_REF-6cde6934c3946f02f3ac845b7b8544dcf7178358}"

# shellcheck disable=SC2034 # consumed indirectly via validate_install_dir_against_prefixes nameref.
declare -a REAPER_ALLOWED_INSTALL_PREFIXES=(
    "/"
)

ARCH=""
REAPER_TAR=""
REAPER_URL=""
REAPER_EXTRACT_DIR=""
REAPER_INSTALL_DIR=""

TEMP_TAR=""
TEMP_DIR=""
TEMP_WDL=""

usage() {
    cat <<'EOF'
Usage: ./scripts/reaper.sh <install|update|uninstall|check> [options]

Options:
  --version <ver>             REAPER version build number (default: 761)
  --install-prefix <path>     Install prefix (default: /opt)
    --sha256 <hex>              Expected SHA256 for REAPER archive
    --wdl-ref <commit>          Immutable WDL commit for libSwell build
  --no-lib-swell              Skip custom libSwell.so build/install
  -h, --help                  Show help
EOF
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
                REAPER_VERSION="${2}"
                shift 2
                ;;
            --install-prefix)
                require_option_value "$1" "${2-}" || exit 1
                INSTALL_PREFIX="${2}"
                shift 2
                ;;
            --sha256)
                require_option_value "$1" "${2-}" || exit 1
                REAPER_SHA256="${2}"
                shift 2
                ;;
            --wdl-ref)
                require_option_value "$1" "${2-}" || exit 1
                WDL_REF="${2}"
                shift 2
                ;;
            --no-lib-swell)
                ENABLE_LIB_SWELL="false"
                shift
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

refresh_reaper_metadata() {
    ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64)
            REAPER_TAR="reaper${REAPER_VERSION}_linux_x86_64.tar.xz"
            REAPER_EXTRACT_DIR="reaper_linux_x86_64"
            ;;
        aarch64|arm64)
            REAPER_TAR="reaper${REAPER_VERSION}_linux_aarch64.tar.xz"
            REAPER_EXTRACT_DIR="reaper_linux_aarch64"
            ;;
        *)
            err "Unsupported architecture for REAPER installer: ${ARCH}"
            exit 1
            ;;
    esac

    REAPER_URL="https://www.reaper.fm/files/7.x/${REAPER_TAR}"
    REAPER_INSTALL_DIR="${INSTALL_PREFIX}/REAPER"
}

cleanup() {
    cleanup_temp_vars TEMP_DIR TEMP_TAR TEMP_WDL
}

validate_reaper_install_dir() {
    validate_install_dir_against_prefixes "${REAPER_INSTALL_DIR}" REAPER_ALLOWED_INSTALL_PREFIXES "REAPER install directory"
}

validate_wdl_ref() {
    if [[ ! "${WDL_REF}" =~ ^[A-Fa-f0-9]{40}$ ]]; then
        err "WDL ref must be a 40-character commit hash"
        err "Provide --wdl-ref <commit> (or WDL_REF) to continue"
        return 1
    fi

    WDL_REF="${WDL_REF,,}"
}

resolve_reaper_sha256() {
    local fallback_sha256=""

    if [[ "${REAPER_VERSION}" == "${REAPER_DEFAULT_VERSION}" ]]; then
        case "${ARCH}" in
            x86_64)
                fallback_sha256="${REAPER_DEFAULT_SHA256_X86_64}"
                ;;
            aarch64|arm64)
                fallback_sha256="${REAPER_DEFAULT_SHA256_AARCH64}"
                ;;
        esac
    fi

    resolve_sha256_with_fallback \
        "${REAPER_SHA256}" \
        "REAPER_SHA256" \
        "${fallback_sha256}" \
        "" \
        "" \
        "${REAPER_TAR}" \
        "Provide --sha256 <hex> (or REAPER_SHA256) for non-default REAPER versions"
}

configure_reaper_desktop_entry() {
    write_desktop_entry_from_stdin "${REAPER_DESKTOP_ENTRY}" <<EOF
[Desktop Entry]
Name=REAPER
Comment=Digital audio workstation
Exec=/usr/local/bin/reaper %F
TryExec=/usr/local/bin/reaper
Icon=${REAPER_INSTALL_DIR}/Data/toolbar_icons/record_arm.png
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Recorder;
EOF
}

install_deps() {
    require_apt_environment
    apt_install_missing \
        ca-certificates \
        curl \
        tar \
        xz-utils \
        build-essential \
        git \
        libgtk-3-dev
}

install_reaper() {
    local extracted_reaper_dir=""

    require_commands curl mktemp tar sha256sum awk cp ln

    if [[ "${LIFECYCLE_ACTION:-install}" == install ]] && safe_sudo test -x "${REAPER_INSTALL_DIR}/reaper"; then
        log "REAPER already installed at ${REAPER_INSTALL_DIR}"
        return 0
    fi

    mktemp_file_var TEMP_TAR "/tmp/reaper.XXXXXX.tar.xz"
    mktemp_dir_var TEMP_DIR "/tmp/reaper.XXXXXX"

    log "Downloading REAPER ${REAPER_VERSION} (${ARCH})"
    curl -fL "${REAPER_URL}" -o "${TEMP_TAR}"
    verify_archive_sha256_with_resolver "${TEMP_TAR}" resolve_reaper_sha256 "${REAPER_TAR}"

    log "Extracting REAPER archive"
    tar -xf "${TEMP_TAR}" -C "${TEMP_DIR}"

    extracted_reaper_dir="${TEMP_DIR}/${REAPER_EXTRACT_DIR}/REAPER"
    if [[ ! -d "${extracted_reaper_dir}" ]]; then
        err "REAPER payload directory not found in extracted archive"
        exit 1
    fi

    validate_reaper_install_dir

    log "Installing REAPER payload into ${REAPER_INSTALL_DIR}"
    safe_sudo mkdir -p "${INSTALL_PREFIX}"
    safe_sudo rm -rf "${REAPER_INSTALL_DIR}"
    safe_sudo mkdir -p "${REAPER_INSTALL_DIR}"
    safe_sudo cp -a "${extracted_reaper_dir}/." "${REAPER_INSTALL_DIR}/"

    safe_sudo mkdir -p /usr/local/bin
    safe_sudo ln -sfn "${REAPER_INSTALL_DIR}/reaper" /usr/local/bin/reaper
    configure_reaper_desktop_entry

    if ! safe_sudo test -x "${REAPER_INSTALL_DIR}/reaper"; then
        err "REAPER install did not produce ${REAPER_INSTALL_DIR}/reaper"
        exit 1
    fi
    if ! safe_sudo test -L /usr/local/bin/reaper; then
        err "REAPER install did not produce /usr/local/bin/reaper symlink"
        exit 1
    fi
}

install_lib_swell() {
    local proc_count
    local resolved_wdl_ref=""

    if [[ "${ENABLE_LIB_SWELL}" != "true" ]]; then
        log "Skipping libSwell build by configuration"
        return 0
    fi
    if ! safe_sudo test -x "${REAPER_INSTALL_DIR}/reaper"; then
        err "REAPER must be installed before libSwell build"
        exit 1
    fi
    if safe_sudo test -f "${REAPER_INSTALL_DIR}/libSwell.so"; then
        log "libSwell.so already present at ${REAPER_INSTALL_DIR}/libSwell.so"
        return 0
    fi

    require_commands git make nproc
    proc_count="$(nproc --ignore=1 2>/dev/null || echo 1)"
    [[ "${proc_count}" -gt 0 ]] || proc_count=1

    mktemp_dir_var TEMP_WDL "/tmp/reaper-wdl.XXXXXX"

    validate_wdl_ref || exit 1

    log "Building libSwell.so from WDL commit ${WDL_REF}"
    git -C "${TEMP_WDL}" init
    git -C "${TEMP_WDL}" remote add origin "${WDL_SOURCE_URL}"
    git -C "${TEMP_WDL}" fetch --depth 1 origin "${WDL_REF}"
    git -C "${TEMP_WDL}" checkout --detach FETCH_HEAD
    resolved_wdl_ref="$(git -C "${TEMP_WDL}" rev-parse HEAD)"
    if [[ "${resolved_wdl_ref}" != "${WDL_REF}" ]]; then
        err "Resolved WDL commit does not match requested ref"
        return 1
    fi

    make -C "${TEMP_WDL}/WDL/swell" -j"${proc_count}"

    safe_sudo install -m 0644 "${TEMP_WDL}/WDL/swell/libSwell.so" "${REAPER_INSTALL_DIR}/libSwell.so"
}

main() {
    trap_cleanup_handler cleanup EXIT
    parse_args "$@"
    refresh_reaper_metadata
    validate_reaper_install_dir
    install_deps
    install_reaper
    install_lib_swell
    log "Completed (${REAPER_VERSION})"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    lifecycle_dispatch reaper "$@"
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="ghidra"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

CSCRIPT_ACTION=""
# shellcheck disable=SC2034 # retained for compatibility with prior script interface.
CSCRIPT_SUBACTION=""
# shellcheck disable=SC2034 # retained for compatibility with prior script interface.
declare -a CSCRIPT_ARGS=("$@")
declare -a CSCRIPT_BARGS=()
CSCRIPT_DEBUG=0
CSCRIPT_QUIET=0

GHIDRA_DEFAULT_VERSION="12.0.3"
GHIDRA_DEFAULT_DATE="20260210"
GHIDRA_DEFAULT_SHA256="90d3fffb20b00030dcef8d2a24dd0f422d3a61e432b3ad43f77233ac6d667981"
GHIDRA_VERSION=${GHIDRA_VERSION:-"${GHIDRA_DEFAULT_VERSION}"}
GHIDRA_DATE=${GHIDRA_DATE:-"${GHIDRA_DEFAULT_DATE}"}
GHIDRA_ZIP="ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/${GHIDRA_ZIP}"
GHIDRA_SHA256=${GHIDRA_SHA256:-""}
INSTALL_DIR=${INSTALL_DIR:-"/opt/ghidra"}
SDKMAN_JAVA_VERSION=${SDKMAN_JAVA_VERSION:-"21.0.10-tem"}
APACHE_MAVEN_VERSION=${APACHE_MAVEN_VERSION:-"3.9.11"}
PYTHON_VERSION=${PYTHON_VERSION:-"3.12.10"}
INSTALL_GHIDRA_MCP=${INSTALL_GHIDRA_MCP:-"false"}
GHIDRA_MCP_REPO_URL="https://github.com/bethington/ghidra-mcp.git"
GHIDRA_MCP_REPO_DIR=${GHIDRA_MCP_REPO_DIR:-"${HOME}/.local/share/ghidra-mcp"}
GHIDRA_MCP_REF=${GHIDRA_MCP_REF:-""}
INSTALL_GHIDRA_PSX_LDR=${INSTALL_GHIDRA_PSX_LDR:-"false"}
GHIDRA_PSX_LDR_RELEASE_TAG=${GHIDRA_PSX_LDR_RELEASE_TAG:-""}
GHIDRA_PSX_LDR_SHA256=${GHIDRA_PSX_LDR_SHA256:-""}
SYSTEM_LAUNCHER=${SYSTEM_LAUNCHER:-"/usr/local/bin/ghidra"}
GHIDRA_DESKTOP_ENTRY=${GHIDRA_DESKTOP_ENTRY:-"/usr/share/applications/ghidra.desktop"}
GHIDRA_CONF_FILE=${GHIDRA_CONF_FILE:-"/etc/ghidra/ghidra.conf"}
SDKMAN_BOOTSTRAP_URL=${SDKMAN_BOOTSTRAP_URL:-"https://get.sdkman.io"}
SDKMAN_BOOTSTRAP_SHA256=${SDKMAN_BOOTSTRAP_SHA256:-""}
PYENV_REPO_URL=${PYENV_REPO_URL:-"https://github.com/pyenv/pyenv.git"}
PYENV_DEFAULT_GIT_REF="94071a937429c1923e12f8e57bc109aeebe7a0ff"
PYENV_GIT_REF=${PYENV_GIT_REF:-"${PYENV_DEFAULT_GIT_REF}"}
GHIDRA_TMP_FOLDER=""
GHIDRA_TMP_FILE=""

# shellcheck disable=SC2034 # consumed indirectly via validate_install_dir_against_prefixes nameref.
declare -a GHIDRA_ALLOWED_INSTALL_PREFIXES=(
    "/opt/ghidra"
    "/usr/local/ghidra"
    "${HOME}/.local/ghidra"
    "${HOME}/.local/opt/ghidra"
)

# shellcheck disable=SC2034 # consumed indirectly via validate_resolved_path_against_prefixes nameref.
declare -a GHIDRA_ALLOWED_MCP_REPO_PREFIXES=(
    "${HOME}/.local/share/ghidra-mcp"
)

debug() {
    [[ "${CSCRIPT_QUIET}" -eq 1 ]] && return 0
    [[ "${CSCRIPT_DEBUG}" -eq 1 ]] || return 0
    log "DEBUG: $*"
}

error() {
    err "$*"
}

warn() {
    [[ "${CSCRIPT_QUIET}" -eq 1 ]] && return 0
    log_warn "$*"
}

info() {
    [[ "${CSCRIPT_QUIET}" -eq 1 ]] && return 0
    log "INFO: $*"
}

success() {
    [[ "${CSCRIPT_QUIET}" -eq 1 ]] && return 0
    log_success "$*"
}

usage() {
    local action="${1:-}"
    local shared_version_opts
    shared_version_opts=$(
        echo "    -V, --ghidra-version <ver>         Override GHIDRA_VERSION         (default: ${GHIDRA_VERSION})"
        echo "    -A, --ghidra-date <date>           Override GHIDRA_DATE             (default: ${GHIDRA_DATE})"
        echo "    -J, --sdkman-java-version <ver>    Override SDKMAN_JAVA_VERSION    (default: ${SDKMAN_JAVA_VERSION})"
        echo "    -M, --apache-maven-version <ver>   Override APACHE_MAVEN_VERSION   (default: ${APACHE_MAVEN_VERSION})"
        echo "    -P, --python-version <ver>         Override PYTHON_VERSION          (default: ${PYTHON_VERSION})"
        echo "    --install-ghidra-mcp               Enable Ghidra MCP install        (default: ${INSTALL_GHIDRA_MCP})"
        echo "    --ghidra-mcp-repo-dir <path>       Override GHIDRA_MCP_REPO_DIR     (default: ${GHIDRA_MCP_REPO_DIR})"
        echo "    --ghidra-mcp-ref <sha>             Override GHIDRA_MCP_REF (40-char commit SHA) (default: ${GHIDRA_MCP_REF:-unset})"
        echo "    --install-ghidra-psx-ldr           Enable PSX loader install        (default: ${INSTALL_GHIDRA_PSX_LDR})"
        echo "    --no-install-ghidra-psx-ldr        Disable PSX loader install"
        echo "    --ghidra-psx-ldr-release-tag <tag> Override PSX loader release tag  (default: ${GHIDRA_PSX_LDR_RELEASE_TAG:-unset})"
        echo "    --ghidra-psx-ldr-sha256 <hex>      Override PSX loader SHA256       (default: ${GHIDRA_PSX_LDR_SHA256:-unset})"
        echo "    -I, --install-dir <path>           Override INSTALL_DIR             (default: ${INSTALL_DIR})"
        echo "    -L, --system-launcher <path>       Override SYSTEM_LAUNCHER         (default: ${SYSTEM_LAUNCHER})"
        echo "    -D, --desktop-entry <path>         Override GHIDRA_DESKTOP_ENTRY    (default: ${GHIDRA_DESKTOP_ENTRY})"
    )
    case "${action}" in
        install)
            echo "Usage: $0 install [options]"
            echo ""
            echo "Options:"
            echo ""
            echo "${shared_version_opts}"
            ;;
        uninstall)
            echo "Usage: $0 uninstall [options]"
            echo ""
            echo "Options:"
            echo ""
            echo "    -I, --install-dir <path>       Override INSTALL_DIR           (default: ${INSTALL_DIR})"
            echo "    -L, --system-launcher <path>   Override SYSTEM_LAUNCHER       (default: ${SYSTEM_LAUNCHER})"
            echo "    -D, --desktop-entry <path>     Override GHIDRA_DESKTOP_ENTRY  (default: ${GHIDRA_DESKTOP_ENTRY})"
            echo "    --ghidra-mcp-repo-dir <path>   Override GHIDRA_MCP_REPO_DIR   (default: ${GHIDRA_MCP_REPO_DIR})"
            ;;
        run)
            echo "Usage: $0 run [options]"
            echo ""
            echo "Options:"
            echo ""
            echo "${shared_version_opts}"
            echo "    --                             Pass remaining args to ghidraRun"
            ;;
        --help|-h|help|*)
            echo "Usage: $0 <action> [options]"
            echo ""
            echo "Actions:"
            echo "    install     Install Ghidra"
            echo "    uninstall   Uninstall Ghidra"
            echo "    run         Run Ghidra"
            ;;
    esac
    echo ""
    echo "Global Options:"
    echo "    -h, --help      Show this help message"
    echo "    -d, --debug     Enable debug output"
    echo "    -q, --quiet     Suppress all output except errors"
    return 0
}

refresh_ghidra_metadata() {
    GHIDRA_ZIP="ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip"
    GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/${GHIDRA_ZIP}"
}

validate_ghidra_install_dir() {
    validate_install_dir_against_prefixes "${INSTALL_DIR}" GHIDRA_ALLOWED_INSTALL_PREFIXES "INSTALL_DIR"
}

validate_ghidra_mcp_repo_dir_for_uninstall() {
    validate_resolved_path_against_prefixes "${GHIDRA_MCP_REPO_DIR}" GHIDRA_ALLOWED_MCP_REPO_PREFIXES "GHIDRA_MCP_REPO_DIR"
}

ghidra_mcp_ref_is_pinned() {
    local ref="${1:-}"
    [[ "${ref}" =~ ^[a-fA-F0-9]{40}$ ]]
}

validate_ghidra_mcp_policy() {
    if [[ "${INSTALL_GHIDRA_MCP}" != "true" ]]; then
        return 0
    fi

    if ! ghidra_mcp_ref_is_pinned "${GHIDRA_MCP_REF}"; then
        error "INSTALL_GHIDRA_MCP=true requires --ghidra-mcp-ref pinned to a full 40-character git commit SHA"
        return 1
    fi

    return 0
}

validate_ghidra_psx_ldr_policy() {
    if [[ "${INSTALL_GHIDRA_PSX_LDR}" != "true" ]]; then
        return 0
    fi

    if [[ -z "${GHIDRA_PSX_LDR_RELEASE_TAG}" || "${GHIDRA_PSX_LDR_RELEASE_TAG}" == "latest" ]]; then
        error "INSTALL_GHIDRA_PSX_LDR=true requires --ghidra-psx-ldr-release-tag pinned to an immutable release tag (not 'latest')"
        return 1
    fi

    GHIDRA_PSX_LDR_SHA256="$(validate_sha256_hex "${GHIDRA_PSX_LDR_SHA256}" "GHIDRA_PSX_LDR_SHA256" || true)"
    if [[ -z "${GHIDRA_PSX_LDR_SHA256}" ]]; then
        error "INSTALL_GHIDRA_PSX_LDR=true requires --ghidra-psx-ldr-sha256 with a trusted SHA256 digest"
        return 1
    fi

    return 0
}

resolve_ghidra_sha256() {
    local fallback_sha256=""

    if [[ "${GHIDRA_VERSION}" == "${GHIDRA_DEFAULT_VERSION}" && "${GHIDRA_DATE}" == "${GHIDRA_DEFAULT_DATE}" ]]; then
        fallback_sha256="${GHIDRA_DEFAULT_SHA256}"
    fi

    resolve_sha256_with_fallback \
        "${GHIDRA_SHA256}" \
        "GHIDRA_SHA256" \
        "${fallback_sha256}" \
        "" \
        "" \
        "${GHIDRA_ZIP}" \
        "Set GHIDRA_SHA256 to a pinned SHA256 value for non-default Ghidra versions"
}

verify_ghidra_archive_sha256() {
    local archive_path="${1:-}"

    verify_archive_sha256_with_resolver "${archive_path}" resolve_ghidra_sha256 "${GHIDRA_ZIP}" info
}

cleanup_install_gidra_temp() {
    cleanup_temp_vars GHIDRA_TMP_FOLDER GHIDRA_TMP_FILE
}

parse_args() {
    [[ "$#" -gt 0 ]] || {
        usage
        return 1
    }
    if is_help_token "${1:-}"; then
        usage
        CSCRIPT_ACTION="help"
        return 0
    fi
    CSCRIPT_ACTION="${1:-}"
    shift
    if [[ ! "${CSCRIPT_ACTION}" =~ ^(install|uninstall|run)$ ]]; then
        usage
        return 1
    fi

    local _version_actions="install run"
    local _path_actions="install run uninstall"
    local _mcp_actions="install run uninstall"
    local _mcp_install_actions="install run"
    local _psx_ldr_install_actions="install"

    while [[ $# -gt 0 ]]; do
        if is_help_token "${1:-}"; then
            usage "${CSCRIPT_ACTION}"
            exit 0
        fi

        case "${1:-}" in
            -d|--debug)
                CSCRIPT_DEBUG=1
                shift 1
                ;;
            -q|--quiet)
                CSCRIPT_QUIET=1
                shift 1
                ;;
            -V|--ghidra-version)
                [[ " ${_version_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_version_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_VERSION="$2"
                shift 2
                ;;
            -A|--ghidra-date)
                [[ " ${_version_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_version_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_DATE="$2"
                shift 2
                ;;
            -J|--sdkman-java-version)
                [[ " ${_version_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_version_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                SDKMAN_JAVA_VERSION="$2"
                shift 2
                ;;
            -M|--apache-maven-version)
                [[ " ${_version_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_version_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                APACHE_MAVEN_VERSION="$2"
                shift 2
                ;;
            -P|--python-version)
                [[ " ${_version_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_version_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                PYTHON_VERSION="$2"
                shift 2
                ;;
            --install-ghidra-mcp)
                [[ " ${_mcp_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_mcp_install_actions}"
                    return 1
                }
                INSTALL_GHIDRA_MCP="true"
                shift 1
                ;;
            --no-install-ghidra-mcp)
                [[ " ${_mcp_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_mcp_install_actions}"
                    return 1
                }
                INSTALL_GHIDRA_MCP="false"
                shift 1
                ;;
            --ghidra-mcp-repo-dir)
                [[ " ${_mcp_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_mcp_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_MCP_REPO_DIR="$2"
                shift 2
                ;;
            --ghidra-mcp-ref)
                [[ " ${_mcp_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_mcp_install_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_MCP_REF="$2"
                shift 2
                ;;
            --install-ghidra-psx-ldr)
                [[ " ${_psx_ldr_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_psx_ldr_install_actions}"
                    return 1
                }
                INSTALL_GHIDRA_PSX_LDR="true"
                shift 1
                ;;
            --no-install-ghidra-psx-ldr)
                [[ " ${_psx_ldr_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_psx_ldr_install_actions}"
                    return 1
                }
                INSTALL_GHIDRA_PSX_LDR="false"
                shift 1
                ;;
            --ghidra-psx-ldr-release-tag)
                [[ " ${_psx_ldr_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_psx_ldr_install_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_PSX_LDR_RELEASE_TAG="$2"
                shift 2
                ;;
            --ghidra-psx-ldr-sha256)
                [[ " ${_psx_ldr_install_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_psx_ldr_install_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_PSX_LDR_SHA256="$2"
                shift 2
                ;;
            -I|--install-dir)
                [[ " ${_path_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_path_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                INSTALL_DIR="$2"
                shift 2
                ;;
            -L|--system-launcher)
                [[ " ${_path_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_path_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                SYSTEM_LAUNCHER="$2"
                shift 2
                ;;
            -D|--desktop-entry)
                [[ " ${_path_actions} " == *" ${CSCRIPT_ACTION} "* ]] || {
                    error "$1 is only supported for: ${_path_actions}"
                    return 1
                }
                require_option_value "$1" "${2-}" || return 1
                GHIDRA_DESKTOP_ENTRY="$2"
                shift 2
                ;;
            --)
                shift
                CSCRIPT_BARGS+=("$@")
                break
                ;;
            --*|-*)
                error "Unknown option for ${CSCRIPT_ACTION}: ${1}"
                return 1
                ;;
            *)
                CSCRIPT_BARGS+=("$1")
                shift 1
                ;;
        esac
    done

    refresh_ghidra_metadata
}

safe_env() {
  local name="${1:-}"
  local value="${2-}"
  if [[ -z "${name}" ]]; then
    error "safe_env requires a variable name"
    return 1
  fi
  if [[ ! "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    error "safe_env received invalid variable name: ${name}"
    return 1
  fi

    if [[ -z "${!name+x}" ]]; then
        printf -v "${name}" '%s' "${value}"
    fi

    export "${name}=${!name}"
}

mod_path() {
  local path_entry="${1:-}"
  local position="${2:-prepend}"
  local current_path="${PATH:-}"
  if [[ -z "${path_entry}" ]]; then
    return 0
  fi
  case ":${current_path}:" in
    *":${path_entry}:"*)
      return 0
      ;;
  esac
  if [[ "${position}" == "append" ]]; then
    export PATH="${current_path:+${current_path}:}${path_entry}"
  else
    export PATH="${path_entry}${current_path:+:${current_path}}"
  fi
}

write_config() {
    local conf_dir
    conf_dir="$(dirname "${GHIDRA_CONF_FILE}")"

    info "Writing config to ${GHIDRA_CONF_FILE}..."
    safe_sudo mkdir -p "${conf_dir}" || {
        error "Failed to create config directory ${conf_dir}"
        return 1
    }
    safe_sudo tee "${GHIDRA_CONF_FILE}" >/dev/null <<EOF
# Ghidra config — written by $(basename "${BASH_SOURCE[0]}") on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
GHIDRA_VERSION="${GHIDRA_VERSION}"
GHIDRA_DATE="${GHIDRA_DATE}"
SDKMAN_JAVA_VERSION="${SDKMAN_JAVA_VERSION}"
APACHE_MAVEN_VERSION="${APACHE_MAVEN_VERSION}"
PYTHON_VERSION="${PYTHON_VERSION}"
INSTALL_GHIDRA_MCP="${INSTALL_GHIDRA_MCP}"
GHIDRA_MCP_REPO_DIR="${GHIDRA_MCP_REPO_DIR}"
GHIDRA_MCP_REF="${GHIDRA_MCP_REF}"
INSTALL_GHIDRA_PSX_LDR="${INSTALL_GHIDRA_PSX_LDR}"
GHIDRA_PSX_LDR_RELEASE_TAG="${GHIDRA_PSX_LDR_RELEASE_TAG}"
GHIDRA_PSX_LDR_SHA256="${GHIDRA_PSX_LDR_SHA256}"
INSTALL_DIR="${INSTALL_DIR}"
SYSTEM_LAUNCHER="${SYSTEM_LAUNCHER}"
GHIDRA_DESKTOP_ENTRY="${GHIDRA_DESKTOP_ENTRY}"
EOF
    safe_sudo chmod 0644 "${GHIDRA_CONF_FILE}" || {
        error "Failed to set permissions on ${GHIDRA_CONF_FILE}"
        return 1
    }
    debug "Config written: ${GHIDRA_CONF_FILE}"
}

load_config() {
    [[ -f "${GHIDRA_CONF_FILE}" ]] || {
        debug "Config file not found: ${GHIDRA_CONF_FILE} — using defaults"
        return 0
    }

    info "Loading config from ${GHIDRA_CONF_FILE}..."
    local key value line

    while IFS= read -r line; do
        # skip blank lines and comment lines
        [[ "${line}" =~ ^[[:space:]]*(#.*)?$ ]] && continue

        # match KEY="value" or KEY=value
        if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=\"?([^\"]*)\"?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            case "${key}" in
                GHIDRA_VERSION|GHIDRA_DATE|SDKMAN_JAVA_VERSION|APACHE_MAVEN_VERSION|\
PYTHON_VERSION|INSTALL_GHIDRA_MCP|GHIDRA_MCP_REPO_DIR|GHIDRA_MCP_REF|\
INSTALL_GHIDRA_PSX_LDR|GHIDRA_PSX_LDR_RELEASE_TAG|\
GHIDRA_PSX_LDR_SHA256|\
INSTALL_DIR|SYSTEM_LAUNCHER|GHIDRA_DESKTOP_ENTRY)
                    export "${key}=${value}"
                    debug "  Config loaded: ${key}=${value}"
                    ;;
                *)
                    warn "Ignoring unknown config key '${key}' in ${GHIDRA_CONF_FILE}"
                    ;;
            esac
        fi
    done < "${GHIDRA_CONF_FILE}"

    refresh_ghidra_metadata
}

has_sdkman() {
    [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]
}

prepare_sdkman_env() {
    safe_env "SDKMAN_DIR" "${HOME}/.sdkman" || return 1

    if ! has_sdkman; then
        error "SDKMAN! not found at ${SDKMAN_DIR}"
        return 1
    fi

    # sdkman-init.sh references ZSH_VERSION etc. which are unbound under set -u
    set +u
    # shellcheck disable=SC1090,SC1091
    source "${SDKMAN_DIR}/bin/sdkman-init.sh" || {
        set -u
        error "Failed to source SDKMAN initialization script"
        return 1
    }
    set -u

    return 0
}

sdk_cmd() {
    set +u
    sdk "$@"
    local _sdk_rc=$?
    set -u
    return ${_sdk_rc}
}

install_sdkman() {
    local installer_tmp=""

    if ! has_sdkman; then
        if [[ -z "${SDKMAN_BOOTSTRAP_SHA256}" ]]; then
            error "Refusing to bootstrap SDKMAN without SDKMAN_BOOTSTRAP_SHA256"
            error "Set SDKMAN_BOOTSTRAP_SHA256 to a pinned trusted digest, or preinstall SDKMAN"
            return 1
        fi

        validate_sha256_hex "${SDKMAN_BOOTSTRAP_SHA256}" "SDKMAN_BOOTSTRAP_SHA256" >/dev/null || return 1

        info "Installing SDKMAN with checksum verification..."
        require_commands curl mktemp bash || return 1
        mktemp_file_var installer_tmp "/tmp/sdkman-bootstrap.XXXXXX.sh"
        curl -fsSL "${SDKMAN_BOOTSTRAP_URL}" -o "${installer_tmp}" || {
            rm -f "${installer_tmp}" || true
            error "Failed to download SDKMAN bootstrap script"
            return 1
        }

        if ! verify_file_sha256 "${installer_tmp}" "${SDKMAN_BOOTSTRAP_SHA256}" "SDKMAN bootstrap"; then
            rm -f "${installer_tmp}" || true
            return 1
        fi

        bash "${installer_tmp}" || {
            rm -f "${installer_tmp}" || true
            error "Failed to install SDKMAN"
            return 1
        }
        rm -f "${installer_tmp}" || true
    fi

    prepare_sdkman_env
}

has_java_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_sdkman; then
        return 1
    fi

    sdk_cmd list java | grep -q "${version}"
}

is_java_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_sdkman; then
        return 1
    fi

    sdk_cmd current java 2>/dev/null | grep -Fq "${version}"
}

install_java_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_sdkman; then
        return 1
    fi

    if ! has_java_version "${version}"; then
        error "Java version ${version} not found in SDKMAN! catalog."
        error "Check available versions with: sdk list java"
        return 1
    fi
    if ! is_java_version "${version}"; then
        info "Installing Java ${version} with SDKMAN!..."
        sdk_cmd install java "${version}" || {
            error "Failed to install Java ${version} with SDKMAN!"
            return 1
        }
    fi
}

has_maven_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_sdkman; then
        return 1
    fi

    sdk_cmd list maven | grep -q "${version}"
}

is_maven_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_sdkman; then
        return 1
    fi

    sdk_cmd current maven 2>/dev/null | grep -Fq "${version}"
}

install_maven_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_sdkman; then
        return 1
    fi

    if ! has_maven_version "${version}"; then
        error "Maven version ${version} not found in SDKMAN! catalog."
        error "Check available versions with: sdk list maven"
        return 1
    fi
    if ! is_maven_version "${version}"; then
        info "Installing Maven ${version} with SDKMAN!..."
        sdk_cmd install maven "${version}" || {
            error "Failed to install Maven ${version} with SDKMAN!"
            return 1
        }
    fi
}

has_pyenv() {
    command -v pyenv >/dev/null 2>&1
}

prepare_pyenv_env() {
    safe_env "PYENV_ROOT" "${HOME}/.pyenv" || return 1
    mod_path "${PYENV_ROOT}/bin" || return 1

    if ! has_pyenv; then
        error "pyenv not found at ${PYENV_ROOT}"
        return 1
    fi
    set +u
    eval "$(pyenv init - bash)" || {
        set -u
        error "Failed to initialize pyenv"
        return 1
    }
    set -u

    return 0
}

validate_pyenv_git_ref() {
    if [[ ! "${PYENV_GIT_REF}" =~ ^[A-Fa-f0-9]{40}$ ]]; then
        error "PYENV_GIT_REF must be a full 40-character git commit SHA"
        error "Set PYENV_GIT_REF to a pinned commit to continue"
        return 1
    fi

    PYENV_GIT_REF="${PYENV_GIT_REF,,}"
}

verify_pyenv_checkout_matches_ref() {
    local resolved_ref=""

    resolved_ref="$(git -C "${PYENV_ROOT}" rev-parse HEAD 2>/dev/null || true)"
    if [[ "${resolved_ref}" != "${PYENV_GIT_REF}" ]]; then
        error "Resolved pyenv checkout commit does not match requested ref"
        error "Expected ${PYENV_GIT_REF}, got ${resolved_ref:-<unknown>}"
        return 1
    fi

    return 0
}

install_pyenv() {
    local pyenv_parent=""

    safe_env "PYENV_ROOT" "${HOME}/.pyenv" || return 1

    if ! has_pyenv; then
        require_commands git || return 1
        validate_pyenv_git_ref || return 1
        info "Installing pyenv from pinned ref ${PYENV_GIT_REF}..."

        pyenv_parent="$(dirname "${PYENV_ROOT}")"
        mkdir -p "${pyenv_parent}" || {
            error "Failed to create pyenv parent directory: ${pyenv_parent}"
            return 1
        }

        if [[ -e "${PYENV_ROOT}" && ! -d "${PYENV_ROOT}/.git" ]]; then
            error "PYENV_ROOT exists but is not a git repository: ${PYENV_ROOT}"
            return 1
        fi

        if [[ -d "${PYENV_ROOT}/.git" ]]; then
            git -C "${PYENV_ROOT}" fetch --depth 1 origin "${PYENV_GIT_REF}" || {
                error "Failed to fetch ${PYENV_GIT_REF} for pyenv"
                return 1
            }
            git -C "${PYENV_ROOT}" checkout --detach FETCH_HEAD || {
                error "Failed to checkout ${PYENV_GIT_REF} in ${PYENV_ROOT}"
                return 1
            }
            verify_pyenv_checkout_matches_ref || return 1
        else
            mkdir -p "${PYENV_ROOT}" || {
                error "Failed to create ${PYENV_ROOT}"
                return 1
            }
            git -C "${PYENV_ROOT}" init || {
                error "Failed to initialize git repository at ${PYENV_ROOT}"
                return 1
            }
            git -C "${PYENV_ROOT}" remote add origin "${PYENV_REPO_URL}" || {
                error "Failed to configure origin for ${PYENV_ROOT}"
                return 1
            }
            git -C "${PYENV_ROOT}" fetch --depth 1 origin "${PYENV_GIT_REF}" || {
                error "Failed to fetch ${PYENV_GIT_REF} for pyenv"
                return 1
            }
            git -C "${PYENV_ROOT}" checkout --detach FETCH_HEAD || {
                error "Failed to checkout ${PYENV_GIT_REF} in ${PYENV_ROOT}"
                return 1
            }
            verify_pyenv_checkout_matches_ref || return 1
        fi
    fi

    validate_pyenv_git_ref || return 1
    if [[ -d "${PYENV_ROOT}/.git" ]]; then
        verify_pyenv_checkout_matches_ref || {
            error "pyenv checkout in ${PYENV_ROOT} is not pinned to ${PYENV_GIT_REF}"
            return 1
        }
    fi

    if ! has_pyenv; then
        error "pyenv was not found after installation attempt"
        return 1
    fi

    prepare_pyenv_env
}

has_python_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    safe_env "PYENV_ROOT" "${HOME}/.pyenv" || return 1

    if ! has_pyenv; then
        return 1
    fi

    [[ -d "${PYENV_ROOT}/versions/${version}" ]]
}

is_python_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_pyenv; then
        return 1
    fi

    [[ "$(pyenv version-name 2>/dev/null || true)" == "${version}" ]]
}

install_python_version() {
    local version="${1:-}"
    [[ -n "${version}" ]] || return 1

    if ! has_pyenv; then
        return 1
    fi

    if ! has_python_version "${version}"; then
        info "Installing Python ${version} with pyenv..."
        pyenv install -s "${version}" || {
            error "Failed to install Python ${version} with pyenv!"
            return 1
        }
    fi
}

install_self() {
    local source_script=""

    source_script="$(readlink -f "${BASH_SOURCE[0]}")"
    info "Installing launcher script to ${SYSTEM_LAUNCHER}..."
    safe_sudo install -m 0755 "${source_script}" "${SYSTEM_LAUNCHER}" || {
        error "Failed to install launcher script to ${SYSTEM_LAUNCHER}"
        return 1
    }
}

create_desktop_entry() {
    local user_desktop_dir="${HOME}/.local/share/applications"
    local user_desktop_entry="${user_desktop_dir}/ghidra.desktop"
    local desktop_entry_content=""

    desktop_entry_content="$(cat <<EOF
[Desktop Entry]
Name=Ghidra
Comment=Software reverse engineering suite
Exec=${SYSTEM_LAUNCHER} run
TryExec=${SYSTEM_LAUNCHER}
Path=${INSTALL_DIR}
Icon=${INSTALL_DIR}/docs/images/GHIDRA_1.png
Type=Application
Categories=Development;Security;
Terminal=false
StartupNotify=true
EOF
)"

    info "Creating desktop entry..."
    printf '%s\n' "${desktop_entry_content}" | write_desktop_entry_from_stdin "${GHIDRA_DESKTOP_ENTRY}"

    # Keep a user-scoped launcher in sync so desktop environments do not prefer stale entries.
    if [[ "${GHIDRA_DESKTOP_ENTRY}" != "${user_desktop_entry}" ]]; then
        mkdir -p "${user_desktop_dir}"
        printf '%s\n' "${desktop_entry_content}" | tee "${user_desktop_entry}" >/dev/null
        chmod 0644 "${user_desktop_entry}"
    fi
}

prepare_runtime() {
    prepare_sdkman_env || return 1
    sdk_cmd use java "${SDKMAN_JAVA_VERSION}" >/dev/null || {
        error "Failed to select Java ${SDKMAN_JAVA_VERSION}"
        return 1
    }
    sdk_cmd use maven "${APACHE_MAVEN_VERSION}" >/dev/null || {
        error "Failed to select Maven ${APACHE_MAVEN_VERSION}"
        return 1
    }

    prepare_pyenv_env || return 1
    pyenv shell "${PYTHON_VERSION}" || {
        error "Failed to select Python ${PYTHON_VERSION}"
        return 1
    }
    pyenv rehash >/dev/null 2>&1 || true
}

install_deps() {
    info "Installing system dependencies..."
    require_apt_environment || return 1
    apt_install_missing \
        curl unzip zip ca-certificates git build-essential \
        libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libncurses-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
        libffi-dev liblzma-dev llvm make || {
        error "Failed to install system dependencies"
        return 1
    }

    safe_env "SDKMAN_DIR" "${HOME}/.sdkman"
    safe_env "PYENV_ROOT" "${HOME}/.pyenv"

    if ! has_sdkman; then
        install_sdkman || {
            error "SDKMAN! not found after install."
            return 1
        }
    fi

    prepare_sdkman_env || return 1

    if ! has_java_version "${SDKMAN_JAVA_VERSION}"; then
        error "Java version ${SDKMAN_JAVA_VERSION} not found in SDKMAN! catalog."
        error "Check available versions with: sdk list java"
        return 1
    fi

    if ! is_java_version "${SDKMAN_JAVA_VERSION}"; then
        install_java_version "${SDKMAN_JAVA_VERSION}" || {
            error "Java ${SDKMAN_JAVA_VERSION} not found after install."
            return 1
        }
    fi

    sdk_cmd use java "${SDKMAN_JAVA_VERSION}" >/dev/null || {
        error "Failed to select Java ${SDKMAN_JAVA_VERSION}"
        return 1
    }

    if ! has_maven_version "${APACHE_MAVEN_VERSION}"; then
        error "Maven version ${APACHE_MAVEN_VERSION} not found in SDKMAN! catalog."
        error "Check available versions with: sdk list maven"
        return 1
    fi

    if ! is_maven_version "${APACHE_MAVEN_VERSION}"; then
        install_maven_version "${APACHE_MAVEN_VERSION}" || {
            error "Maven ${APACHE_MAVEN_VERSION} not found after install."
            return 1
        }
    fi

    sdk_cmd use maven "${APACHE_MAVEN_VERSION}" >/dev/null || {
        error "Failed to select Maven ${APACHE_MAVEN_VERSION}"
        return 1
    }

    if ! has_pyenv; then
        install_pyenv || {
            error "pyenv not found after install."
            return 1
        }
    fi

    prepare_pyenv_env || return 1

    if ! has_python_version "${PYTHON_VERSION}"; then
        install_python_version "${PYTHON_VERSION}" || {
            error "Python ${PYTHON_VERSION} not found after install."
            return 1
        }
    fi

    pyenv shell "${PYTHON_VERSION}" || {
        error "Failed to select Python ${PYTHON_VERSION}"
        return 1
    }
}

install_gidra() {
    local extracted_dir=""

    info "Downloading Ghidra ${GHIDRA_VERSION}..."
    require_commands curl mktemp unzip grep tr sed || return 1
    validate_ghidra_install_dir || return 1
    trap_cleanup_handler cleanup_install_gidra_temp

    mktemp_dir_var GHIDRA_TMP_FOLDER "/tmp/${GHIDRA_ZIP}.XXXX"
    GHIDRA_TMP_FILE="${GHIDRA_TMP_FOLDER}/${GHIDRA_ZIP}"
    curl -fsSL "${GHIDRA_URL}" -o "${GHIDRA_TMP_FILE}" || {
        error "Failed to download Ghidra from ${GHIDRA_URL}"
        return 1
    }
    verify_ghidra_archive_sha256 "${GHIDRA_TMP_FILE}" || return 1

    info "Installing Ghidra to ${INSTALL_DIR}..."
    safe_sudo mkdir -p "${INSTALL_DIR}" || {
        error "Failed to create installation directory ${INSTALL_DIR}"
        return 1
    }
    safe_sudo unzip -q "${GHIDRA_TMP_FILE}" -d "${GHIDRA_TMP_FOLDER}" || {
        error "Failed to unzip ${GHIDRA_TMP_FILE} to ${GHIDRA_TMP_FOLDER}"
        return 1
    }
    extracted_dir="${GHIDRA_TMP_FOLDER}/ghidra_${GHIDRA_VERSION}_PUBLIC"
    if [[ ! -d "${extracted_dir}" ]]; then
        error "Expected extracted directory not found: ${extracted_dir}"
        return 1
    fi

    safe_sudo rm -rf "${INSTALL_DIR:?}/"* || {
        error "Failed to clean installation directory ${INSTALL_DIR}"
        return 1
    }
    safe_sudo mv "${extracted_dir}/"* "${INSTALL_DIR}" || {
        error "Failed to move Ghidra files to ${INSTALL_DIR}"
        return 1
    }

    cleanup_install_gidra_temp
    trap - EXIT INT TERM
}

install_ghidra_mcp() {
    local setup_script=""
    local bridge_source=""
    local requirements_source=""

    if [[ "${INSTALL_GHIDRA_MCP}" != "true" ]]; then
        debug "Skipping Ghidra MCP install (INSTALL_GHIDRA_MCP=${INSTALL_GHIDRA_MCP})"
        return 0
    fi

    validate_ghidra_mcp_policy || return 1

    info "Installing Ghidra MCP Server from ${GHIDRA_MCP_REPO_URL}"
    info "Using repository path: ${GHIDRA_MCP_REPO_DIR}"

    if [[ -d "${GHIDRA_MCP_REPO_DIR}/.git" ]]; then
        info "Updating existing Ghidra MCP repository..."
        git -C "${GHIDRA_MCP_REPO_DIR}" fetch --tags --prune || {
            error "Failed to fetch updates for ${GHIDRA_MCP_REPO_DIR}"
            return 1
        }
    elif [[ -e "${GHIDRA_MCP_REPO_DIR}" ]]; then
        error "MCP repo path exists but is not a git repo: ${GHIDRA_MCP_REPO_DIR}"
        return 1
    else
        info "Cloning Ghidra MCP repository..."
        mkdir -p "$(dirname "${GHIDRA_MCP_REPO_DIR}")" || {
            error "Failed to create parent directory for ${GHIDRA_MCP_REPO_DIR}"
            return 1
        }
        git clone "${GHIDRA_MCP_REPO_URL}" "${GHIDRA_MCP_REPO_DIR}" || {
            error "Failed to clone ${GHIDRA_MCP_REPO_URL}"
            return 1
        }
    fi

    if [[ -n "${GHIDRA_MCP_REF}" ]]; then
        info "Checking out Ghidra MCP ref: ${GHIDRA_MCP_REF}"
        git -C "${GHIDRA_MCP_REPO_DIR}" checkout "${GHIDRA_MCP_REF}" || {
            error "Failed to checkout ref ${GHIDRA_MCP_REF}"
            return 1
        }
    fi

    setup_script="${GHIDRA_MCP_REPO_DIR}/ghidra-mcp-setup.sh"
    if [[ ! -f "${setup_script}" ]]; then
        error "Ghidra MCP setup script not found: ${setup_script}"
        return 1
    fi

    chmod +x "${setup_script}" || true

    info "Running Ghidra MCP preflight..."
    (
        cd "${GHIDRA_MCP_REPO_DIR}"
        "${setup_script}" --preflight --ghidra-path "${INSTALL_DIR}"
    ) || {
        error "Ghidra MCP preflight failed"
        return 1
    }

    info "Running Ghidra MCP deploy..."
    (
        cd "${GHIDRA_MCP_REPO_DIR}"
        "${setup_script}" --deploy --skip-restart --ghidra-path "${INSTALL_DIR}"
    ) || {
        error "Ghidra MCP deploy failed"
        return 1
    }

    bridge_source="${GHIDRA_MCP_REPO_DIR}/bridge_mcp_ghidra.py"
    requirements_source="${GHIDRA_MCP_REPO_DIR}/requirements.txt"

    if [[ ! -f "${bridge_source}" ]]; then
        error "Expected MCP bridge not found after deploy: ${bridge_source}"
        return 1
    fi

    info "Installing MCP bridge into ${INSTALL_DIR}..."
    safe_sudo install -m 0644 "${bridge_source}" "${INSTALL_DIR}/bridge_mcp_ghidra.py" || {
        error "Failed to install MCP bridge into ${INSTALL_DIR}"
        return 1
    }

    if [[ -f "${requirements_source}" ]]; then
        info "Installing MCP bridge requirements into ${INSTALL_DIR}..."
        safe_sudo install -m 0644 "${requirements_source}" "${INSTALL_DIR}/requirements.txt" || {
            warn "Could not install requirements.txt into ${INSTALL_DIR}"
        }
    fi
}

resolve_ghidra_mcp_bridge() {
    local -a candidates=(
        "${INSTALL_DIR}/bridge_mcp_ghidra.py"
        "${GHIDRA_MCP_REPO_DIR}/bridge_mcp_ghidra.py"
    )
    local candidate=""

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

install_ghidra_psx_ldr() {
    if [[ "${INSTALL_GHIDRA_PSX_LDR}" != "true" ]]; then
        info "Ghidra PSX loader install disabled; skipping."
        return 0
    fi

    validate_ghidra_psx_ldr_policy || return 1

    local extensions_dir="${INSTALL_DIR}/Ghidra/Extensions"
    local ext_dir="${extensions_dir}/ghidra_psx_ldr"

    if safe_sudo test -d "${ext_dir}"; then
        info "Ghidra PSX loader already installed at ${ext_dir}; skipping."
        return 0
    fi

    info "Resolving ghidra_psx_ldr release (tag: ${GHIDRA_PSX_LDR_RELEASE_TAG})..."

    local api_url
    api_url="https://api.github.com/repos/lab313ru/ghidra_psx_ldr/releases/tags/${GHIDRA_PSX_LDR_RELEASE_TAG}"

    local release_json
    release_json="$(curl -fsSL "${api_url}")" || {
        error "Failed to fetch ghidra_psx_ldr release metadata from ${api_url}"
        return 1
    }

    local asset_name asset_url
    local version_pattern="ghidra_${GHIDRA_VERSION}_PUBLIC_"
    local assets_block
    assets_block="$(printf '%s\n' "${release_json}" | tr -d '\r')"
    asset_name="$(printf '%s\n' "${assets_block}" \
        | grep -o "\"name\": *\"${version_pattern}[^\"]*_ghidra_psx_ldr\\.zip\"" \
        | head -n1 \
        | sed 's/.*"\(ghidra_[^"]*\.zip\)"/\1/')"

    if [[ -z "${asset_name}" ]]; then
        error "No ghidra_psx_ldr release asset found matching Ghidra ${GHIDRA_VERSION} in release ${GHIDRA_PSX_LDR_RELEASE_TAG}"
        error "Available assets for that release may not include this Ghidra version."
        return 1
    fi

    asset_url="$(printf '%s\n' "${assets_block}" \
        | grep -o "\"browser_download_url\": *\"[^\"]*/${asset_name}\"" \
        | head -n1 \
        | sed 's/.*"\(https:\/\/[^"]*\)"/\1/')"

    info "Downloading ${asset_name}..."
    local tmp_dir=""
    mktemp_dir_var tmp_dir "/tmp/ghidra-psx-ldr.XXXXXX"
    local zip_path="${tmp_dir}/${asset_name}"

    curl -fsSL -o "${zip_path}" "${asset_url}" || {
        error "Failed to download ${asset_url}"
        rm -rf "${tmp_dir}"
        return 1
    }

    info "Verifying checksum..."
    if ! verify_file_sha256 "${zip_path}" "${GHIDRA_PSX_LDR_SHA256}" "${asset_name}"; then
        rm -rf "${tmp_dir}"
        return 1
    fi
    debug "Checksum OK for ${asset_name}"

    info "Installing PSX loader extension into ${extensions_dir}..."
    safe_sudo mkdir -p "${extensions_dir}" || {
        error "Failed to create extensions directory ${extensions_dir}"
        rm -rf "${tmp_dir}"
        return 1
    }

    safe_sudo unzip -q -o "${zip_path}" -d "${extensions_dir}" || {
        error "Failed to extract ${asset_name} into ${extensions_dir}"
        rm -rf "${tmp_dir}"
        return 1
    }

    rm -rf "${tmp_dir}"
    success "Ghidra PSX loader installed: ${ext_dir}"
}

install_action() {
    validate_ghidra_install_dir || return 1
    validate_ghidra_mcp_policy || return 1
    validate_ghidra_psx_ldr_policy || return 1

    if safe_sudo test -x "${INSTALL_DIR}/ghidraRun" \
        || safe_sudo test -f "${SYSTEM_LAUNCHER}" \
        || safe_sudo test -f "${GHIDRA_DESKTOP_ENTRY}"; then
        warn "Existing Ghidra system installation detected; install will overwrite current system install artifacts."
    fi

    install_deps || return 1
    install_gidra || return 1
    install_ghidra_mcp || return 1
    install_ghidra_psx_ldr || return 1
    install_self || return 1
    create_desktop_entry || return 1
    write_config || return 1

    success "Installation complete."
    info "Launcher:      ${SYSTEM_LAUNCHER}"
    info "Desktop entry: ${GHIDRA_DESKTOP_ENTRY}"
    info "Config:        ${GHIDRA_CONF_FILE}"
    info "Java:          ${SDKMAN_JAVA_VERSION}"
    info "Maven:         ${APACHE_MAVEN_VERSION}"
    info "Python:        ${PYTHON_VERSION}"
    info "Ghidra MCP:    ${INSTALL_GHIDRA_MCP}"
    if [[ "${INSTALL_GHIDRA_MCP}" == "true" ]]; then
        info "MCP Repo:      ${GHIDRA_MCP_REPO_DIR} (${GHIDRA_MCP_REF})"
    fi
    info "PSX Loader:    ${INSTALL_GHIDRA_PSX_LDR}"
    if [[ "${INSTALL_GHIDRA_PSX_LDR}" == "true" ]]; then
        info "PSX Ldr Tag:   ${GHIDRA_PSX_LDR_RELEASE_TAG}"
        info "PSX Ldr SHA:   ${GHIDRA_PSX_LDR_SHA256}"
    fi
    info "Run with:      ghidra run"
}

run_action() {
    local current_script=""
    local launcher_script=""
    local -a launcher_args=()
    local bridge_script=""
    local bridge_pid=""
    local bridge_log=""
    local ghidra_rc=0
    local ghidra_pids_before=""
    local ghidra_pids_after=""
    local tracked_ghidra_pid=""

    current_script="$(readlink -f "${BASH_SOURCE[0]}")"
    launcher_script="$(readlink -f "${SYSTEM_LAUNCHER}" 2>/dev/null || printf '%s' "${SYSTEM_LAUNCHER}")"

    if [[ "${current_script}" != "${launcher_script}" ]]; then
        install_self || return 1

        launcher_args=(
            run
            --ghidra-version "${GHIDRA_VERSION}"
            --ghidra-date "${GHIDRA_DATE}"
            --sdkman-java-version "${SDKMAN_JAVA_VERSION}"
            --apache-maven-version "${APACHE_MAVEN_VERSION}"
            --python-version "${PYTHON_VERSION}"
            --ghidra-mcp-repo-dir "${GHIDRA_MCP_REPO_DIR}"
            --install-dir "${INSTALL_DIR}"
            --system-launcher "${SYSTEM_LAUNCHER}"
        )

        if [[ -n "${GHIDRA_MCP_REF}" ]]; then
            launcher_args+=(--ghidra-mcp-ref "${GHIDRA_MCP_REF}")
        fi

        if [[ "${INSTALL_GHIDRA_MCP}" == "true" ]]; then
            launcher_args+=(--install-ghidra-mcp)
        else
            launcher_args+=(--no-install-ghidra-mcp)
        fi

        if [[ "${CSCRIPT_DEBUG}" -eq 1 ]]; then
            launcher_args+=(--debug)
        fi

        if [[ "${CSCRIPT_QUIET}" -eq 1 ]]; then
            launcher_args+=(--quiet)
        fi

        if [[ "${#CSCRIPT_BARGS[@]}" -gt 0 ]]; then
            launcher_args+=(--)
            launcher_args+=("${CSCRIPT_BARGS[@]}")
        fi

        exec "${SYSTEM_LAUNCHER}" "${launcher_args[@]}"
    fi

    prepare_runtime || return 1

    if [[ ! -x "${INSTALL_DIR}/ghidraRun" ]]; then
        error "Ghidra launcher not found at ${INSTALL_DIR}/ghidraRun"
        return 1
    fi

    stop_ghidra_mcp_bridge() {
        local _bridge_pid="${bridge_pid-}"
        if [[ -n "${_bridge_pid}" ]] && kill -0 "${_bridge_pid}" 2>/dev/null; then
            info "Stopping Ghidra MCP bridge (pid ${_bridge_pid})..."
            kill "${_bridge_pid}" 2>/dev/null || true
            wait "${_bridge_pid}" 2>/dev/null || true
        fi
    }

    get_ghidra_gui_pids() {
        pgrep -f 'ghidra\.(GhidraRun|GhidraLauncher)' 2>/dev/null || true
    }

    pid_in_list() {
        local needle="${1:-}"
        local list="${2-}"
        local pid=""

        [[ -n "${needle}" ]] || return 1
        while IFS= read -r pid; do
            [[ -n "${pid}" ]] || continue
            [[ "${pid}" == "${needle}" ]] && return 0
        done <<< "${list}"
        return 1
    }

    if [[ "${INSTALL_GHIDRA_MCP}" == "true" ]]; then
        bridge_script="$(resolve_ghidra_mcp_bridge || true)"
        if [[ -n "${bridge_script}" ]]; then
            bridge_log="${HOME}/.cache/ghidra-mcp/bridge.log"
            mkdir -p "$(dirname "${bridge_log}")" || {
                error "Failed to create MCP bridge log directory"
                return 1
            }

            info "Starting Ghidra MCP bridge: ${bridge_script}"
            python "${bridge_script}" >"${bridge_log}" 2>&1 &
            bridge_pid=$!

            sleep 1
            if ! kill -0 "${bridge_pid}" 2>/dev/null; then
                warn "Ghidra MCP bridge failed to start (see ${bridge_log}); continuing with Ghidra launch."
                bridge_pid=""
            fi
            if [[ -n "${bridge_pid}" ]]; then
                info "Ghidra MCP bridge started (pid ${bridge_pid})"
                trap stop_ghidra_mcp_bridge EXIT INT TERM
            fi
        else
            warn "INSTALL_GHIDRA_MCP=true but bridge_mcp_ghidra.py was not found; starting Ghidra without MCP bridge."
        fi
    fi

    ghidra_pids_before="$(get_ghidra_gui_pids)"

    "${INSTALL_DIR}/ghidraRun" "${CSCRIPT_BARGS[@]}"
    ghidra_rc=$?

    ghidra_pids_after="$(get_ghidra_gui_pids)"
    tracked_ghidra_pid=""

    if [[ -n "${ghidra_pids_after}" ]]; then
        while IFS= read -r _pid; do
            [[ -n "${_pid}" ]] || continue
            if ! pid_in_list "${_pid}" "${ghidra_pids_before}"; then
                tracked_ghidra_pid="${_pid}"
                break
            fi
        done <<< "${ghidra_pids_after}"
    fi
    if [[ -n "${tracked_ghidra_pid}" ]]; then
        debug "Waiting for Ghidra GUI process ${tracked_ghidra_pid} to exit..."
        while kill -0 "${tracked_ghidra_pid}" 2>/dev/null; do
            sleep 2
        done
    elif [[ -z "${ghidra_pids_before}" && -n "${ghidra_pids_after}" ]]; then
        debug "Waiting for Ghidra GUI processes to exit..."
        while [[ -n "$(get_ghidra_gui_pids)" ]]; do
            sleep 2
        done
    fi

    trap - EXIT INT TERM
    stop_ghidra_mcp_bridge

    return ${ghidra_rc}
}

uninstall_action() {
    local conf_dir
    conf_dir="$(dirname "${GHIDRA_CONF_FILE}")"
    local user_desktop_entry="${HOME}/.local/share/applications/ghidra.desktop"
    local errors=0
    local normalized_mcp_repo_dir=""

    if ! validate_ghidra_install_dir; then
        error "Refusing to remove INSTALL_DIR due to failed safety validation: ${INSTALL_DIR}"
        (( errors++ )) || true
    elif [[ -d "${INSTALL_DIR}" ]]; then
        info "Removing Ghidra installation directory: ${INSTALL_DIR}"
        safe_sudo rm -rf "${INSTALL_DIR}" || {
            error "Failed to remove ${INSTALL_DIR}"
            (( errors++ )) || true
        }
    else
        warn "Ghidra installation directory not found (already removed?): ${INSTALL_DIR}"
    fi

    if [[ -f "${SYSTEM_LAUNCHER}" ]]; then
        info "Removing system launcher: ${SYSTEM_LAUNCHER}"
        safe_sudo rm -f "${SYSTEM_LAUNCHER}" || {
            error "Failed to remove ${SYSTEM_LAUNCHER}"
            (( errors++ )) || true
        }
    else
        warn "System launcher not found (already removed?): ${SYSTEM_LAUNCHER}"
    fi

    if [[ -f "${GHIDRA_DESKTOP_ENTRY}" ]]; then
        info "Removing desktop entry: ${GHIDRA_DESKTOP_ENTRY}"
        safe_sudo rm -f "${GHIDRA_DESKTOP_ENTRY}" || {
            error "Failed to remove ${GHIDRA_DESKTOP_ENTRY}"
            (( errors++ )) || true
        }
    else
        warn "Desktop entry not found (already removed?): ${GHIDRA_DESKTOP_ENTRY}"
    fi

    if [[ "${GHIDRA_DESKTOP_ENTRY}" != "${user_desktop_entry}" && -f "${user_desktop_entry}" ]]; then
        info "Removing user desktop entry: ${user_desktop_entry}"
        rm -f "${user_desktop_entry}" || {
            error "Failed to remove ${user_desktop_entry}"
            (( errors++ )) || true
        }
    fi

    if [[ -f "${GHIDRA_CONF_FILE}" ]]; then
        info "Removing config file: ${GHIDRA_CONF_FILE}"
        safe_sudo rm -f "${GHIDRA_CONF_FILE}" || {
            error "Failed to remove ${GHIDRA_CONF_FILE}"
            (( errors++ )) || true
        }
    else
        warn "Config file not found (already removed?): ${GHIDRA_CONF_FILE}"
    fi

    if [[ -d "${conf_dir}" ]]; then
        if safe_sudo find "${conf_dir}" -maxdepth 0 -empty 2>/dev/null | grep -q .; then
            info "Removing empty config directory: ${conf_dir}"
            safe_sudo rmdir "${conf_dir}" || {
                warn "Could not remove config directory (may not be empty): ${conf_dir}"
            }
        else
            warn "Config directory not empty, leaving in place: ${conf_dir}"
        fi
    fi

    if [[ -d "${GHIDRA_MCP_REPO_DIR}" ]] || [[ -f "${INSTALL_DIR}/bridge_mcp_ghidra.py" ]]; then
        if [[ -d "${GHIDRA_MCP_REPO_DIR}" ]]; then
            normalized_mcp_repo_dir="$(validate_ghidra_mcp_repo_dir_for_uninstall || true)"
            if [[ -z "${normalized_mcp_repo_dir}" ]]; then
                error "Refusing to remove GHIDRA_MCP_REPO_DIR due to failed safety validation: ${GHIDRA_MCP_REPO_DIR}"
                (( errors++ )) || true
            else
                info "Removing cloned Ghidra MCP repository: ${normalized_mcp_repo_dir}"
                rm -rf "${normalized_mcp_repo_dir}" || {
                    error "Failed to remove ${normalized_mcp_repo_dir}"
                    (( errors++ )) || true
                }
            fi
        else
            info "No cloned Ghidra MCP repository found at ${GHIDRA_MCP_REPO_DIR}; skipping repo cleanup."
        fi
    fi

    local psx_ext_dir="${INSTALL_DIR}/Ghidra/Extensions/ghidra_psx_ldr"
    if safe_sudo test -d "${psx_ext_dir}"; then
        info "Removing Ghidra PSX loader extension: ${psx_ext_dir}"
        safe_sudo rm -rf "${psx_ext_dir}" || {
            error "Failed to remove ${psx_ext_dir}"
            (( errors++ )) || true
        }
    fi

    if [[ ${errors} -gt 0 ]]; then
        error "Uninstall completed with ${errors} error(s)."
        return 1
    fi

    success "Ghidra uninstalled successfully."
}

main() {
    safe_env "SDKMAN_DIR" "${HOME}/.sdkman"
    safe_env "PYENV_ROOT" "${HOME}/.pyenv"
    refresh_ghidra_metadata

    # For run: load persisted config before CLI args so CLI can still override.
    # We peek at the first non-flag token to detect the action without consuming args.
    local _peek_action=""
    local _i
    for _i in "$@"; do
        case "${_i}" in
            -*) continue ;;
            *)  _peek_action="${_i}"; break ;;
        esac
    done

    if [[ "${_peek_action}" =~ ^(run|uninstall)$ ]]; then
        load_config
    fi

    parse_args "$@" || return 1

    case "${CSCRIPT_ACTION}" in
        install)
            install_action
            ;;
        run)
            run_action
            ;;
        uninstall)
            uninstall_action
            ;;
        help)
            return 0
            ;;
        *)
            error "Unknown action: ${CSCRIPT_ACTION}"
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
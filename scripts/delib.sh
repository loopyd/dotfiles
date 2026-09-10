#!/usr/bin/env bash

# Shared lifecycle helpers for noun-based component commands.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "scripts/delib.sh is a library and must be sourced, not executed." >&2
    exit 1
fi

if [[ -n "${_DELIB_SH_LOADED:-}" ]]; then
    return 0
fi
readonly _DELIB_SH_LOADED=1

: "${INSTALL_LIB_TAG:=install}"
: "${APT_UPDATED:=0}"
: "${SUDO_AUTHENTICATED:=0}"
: "${DELIB_DRY_RUN:=false}"
: "${DELIB_DESKTOP_CONTEXT_READY:=0}"
: "${DELIB_DESKTOP_TARGET_USER:=}"
: "${DELIB_DESKTOP_TARGET_UID:=}"
: "${DELIB_DESKTOP_RUNTIME_DIR:=}"
: "${DELIB_DESKTOP_DBUS_SESSION_BUS_ADDRESS:=}"
: "${DELIB_DESKTOP_TARGET_HOME:=}"

declare -a DELIB_SAFE_TEMP_PREFIXES=(
    "/tmp"
    "/var/tmp"
    "/dev/shm"
)
if [[ -n "${TMPDIR:-}" && "${TMPDIR}" == /* ]]; then
    DELIB_SAFE_TEMP_PREFIXES+=("${TMPDIR}")
fi
declare -a DELIB_MKTEMP_PARENT_PREFIXES=()

declare -a DELIB_DESKTOP_PREFERENCE_TARGET_PAIRS=(
    "org.gnome.desktop.interface:scaling-factor"
    "org.gnome.desktop.interface:text-scaling-factor"
    "org.gnome.desktop.interface:gtk-theme"
    "org.gnome.desktop.interface:icon-theme"
    "org.gnome.desktop.interface:cursor-theme"
    "org.gnome.desktop.interface:font-name"
    "org.cinnamon.desktop.interface:scaling-factor"
    "org.cinnamon.desktop.interface:gtk-theme"
    "org.cinnamon.desktop.interface:icon-theme"
    "org.cinnamon.desktop.interface:cursor-theme"
    "org.cinnamon.desktop.interface:font-name"
    "org.gnome.desktop.background:picture-uri"
    "org.gnome.desktop.background:picture-uri-dark"
    "org.cinnamon.desktop.background:picture-uri"
)

log() {
    printf '[%s] %s\n' "${INSTALL_LIB_TAG}" "$*"
}

err() {
    printf '[%s] ERROR: %s\n' "${INSTALL_LIB_TAG}" "$*" >&2
}

log_warn() {
    printf '[%s] WARN: %s\n' "${INSTALL_LIB_TAG}" "$*" >&2
}

log_success() {
    printf '[%s] SUCCESS: %s\n' "${INSTALL_LIB_TAG}" "$*"
}

command_exists() {
    local cmd="${1:-}"
    [[ -n "${cmd}" ]] || return 1
    command -v "${cmd}" >/dev/null 2>&1
}

require_command() {
    local cmd="${1:-}"
    if [[ -z "${cmd}" ]]; then
        err "require_command called without an argument"
        return 1
    fi
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Required command not found: ${cmd}"
        return 1
    fi
}

has_systemctl() {
    command_exists systemctl
}

require_commands() {
    local cmd=""
    for cmd in "$@"; do
        require_command "${cmd}" || return 1
    done
}

require_apt_environment() {
    require_commands apt-get dpkg-query
}

require_option_value() {
    local option_name="${1:-option}"
    local option_value="${2-}"
    if [[ -z "${option_value}" ]]; then
        err "Missing value for ${option_name}"
        return 1
    fi
    return 0
}

is_help_token() {
    local token="${1:-}"
    [[ "${token}" =~ ^(-h|--help|help)$ ]]
}

safe_sudo() {
    local -a cmd=("$@")
    if [[ "${#cmd[@]}" -eq 0 ]]; then
        err "safe_sudo requires a command"
        return 1
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        "${cmd[@]}"
        return 0
    fi

    require_command sudo || return 1

    if ! sudo -n true 2>/dev/null; then
        if [[ "${SUDO_AUTHENTICATED}" -eq 0 ]]; then
            log "Requesting sudo authentication"
        fi
        sudo -v
    fi

    SUDO_AUTHENTICATED=1
    sudo "${cmd[@]}"
}

apt_update_once() {
    require_apt_environment || return 1
    if [[ "${APT_UPDATED}" -eq 0 ]]; then
        log "Updating apt package index"
        safe_sudo env DEBIAN_FRONTEND=noninteractive apt-get update
        APT_UPDATED=1
    fi
}

reset_apt_update() {
    APT_UPDATED=0
}

apt_install_missing() {
    local pkg=""
    local status=""
    local -a missing=()

    require_apt_environment || return 1
    if [[ "$#" -eq 0 ]]; then
        return 0
    fi

    for pkg in "$@"; do
        status="$(dpkg-query -W -f='${db:Status-Status}\n' "${pkg}" 2>/dev/null || true)"
        if [[ "${status}" != "installed" || "${LIFECYCLE_ACTION:-install}" == update ]]; then
            missing+=("${pkg}")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        log "All requested packages are already installed"
        return 0
    fi

    apt_update_once
    log "Installing packages: ${missing[*]}"
    safe_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

lifecycle_usage() {
    printf 'Usage: %s <install|update|uninstall|check> [--dry-run] [component options]\n' "$0"
    printf '%s\n' 'Update converges to configured pins. Uninstall requires an installation receipt and preserves user data.'
}

lifecycle_payload() {
    LIFECYCLE_PATHS=()
    LIFECYCLE_PACKAGES=()
    case "${LIFECYCLE_COMPONENT}" in
        core) LIFECYCLE_PACKAGES=(ca-certificates curl git wget unzip xz-utils build-essential pkg-config gnupg lsb-release software-properties-common apt-transport-https fish) ;;
        gh) LIFECYCLE_PACKAGES=(gh) ;;
        docker) LIFECYCLE_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin) ;;
        nvidia) LIFECYCLE_PACKAGES=(nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1) ;;
        8bitdo)
            LIFECYCLE_PACKAGES=(xboxdrv)
            [[ "${INSTALL_JSTEST}" != true ]] || LIFECYCLE_PACKAGES+=(jstest-gtk)
            LIFECYCLE_PATHS=("${BLACKLIST_PATH}" "${UDEV_RULES_PATH}" "${SERVICE_PATH}") ;;
        blender) LIFECYCLE_PATHS=("${INSTALL_DIR}" "${SYMLINK_PATH}" "${DESKTOP_ENTRY_PATH}") ;;
        reaper) LIFECYCLE_PATHS=("${INSTALL_PREFIX}/REAPER" /usr/local/bin/reaper "${REAPER_DESKTOP_ENTRY}") ;;
        ghidra) LIFECYCLE_PATHS=("${INSTALL_DIR}" "${SYSTEM_LAUNCHER}" "${SYSTEM_LAUNCHER}.d" "${GHIDRA_DESKTOP_ENTRY}" "${HOME}/.local/share/applications/ghidra.desktop") ;;
        neovim) LIFECYCLE_PATHS=(/usr/local/bin/nvim /usr/local/share/nvim /usr/local/share/man/man1/nvim.1) ;;
        ollama) LIFECYCLE_PATHS=("${INSTALL_DIR}/bin/ollama" "${INSTALL_DIR}/lib/ollama") ;;
        mise|herdr) LIFECYCLE_PATHS=("${HOME}/.local/bin/${LIFECYCLE_COMPONENT}") ;;
        hindsight) LIFECYCLE_PATHS=("${HOME}/.local/bin/hindsight") ;;
        alacritty)
            LIFECYCLE_PATHS=("${HOME}/.local/bin/alacritty" "${HOME}/.local/share/icons/hicolor/scalable/apps/Alacritty.svg"
                "${HOME}/.local/share/bash-completion/completions/alacritty" "${HOME}/.config/fish/completions/alacritty.fish"
                "${HOME}/.zsh_functions/_alacritty" "${HOME}/.local/share/fonts/DepartureMono"
                "${HOME}/.terminfo/a/alacritty" "${HOME}/.terminfo/a/alacritty-direct"
                "${HOME}/.local/share/man/man1/alacritty.1.gz" "${HOME}/.local/share/man/man5/alacritty.5.gz"
                "${HOME}/.local/share/man/man5/alacritty-bindings.5.gz" "${HOME}/.local/share/man/man1/alacritty-msg.1.gz"
                "${HOME}/.local/share/man/man7/alacritty-escapes.7.gz") ;;
        router) LIFECYCLE_PATHS=("${HOME}/.local/lib/dotfiles/router.py") ;;
        tailscale) LIFECYCLE_PATHS=("${HOME}/.local/lib/dotfiles/tailscale.py") ;;
        hooks|tools) ;;
        *) err "Unknown component: ${LIFECYCLE_COMPONENT}"; return 1 ;;
    esac
}

lifecycle_receipt() {
    local operation="$1" path package
    local -a options=()
    for path in "${LIFECYCLE_PATHS[@]}"; do options+=(--path "${path}"); done
    for package in "${LIFECYCLE_PACKAGES[@]}"; do options+=(--package "${package}"); done
    python3 "${SCRIPT_DIR}/lifecycle.py" "${operation}" "${LIFECYCLE_COMPONENT}" "${options[@]}"
}

lifecycle_check() {
    local package
    for package in "${LIFECYCLE_PACKAGES[@]}"; do
        [[ "$(dpkg-query -W -f='${db:Status-Status}' "${package}" 2>/dev/null)" == installed ]] || { err "Missing package: ${package}"; return 1; }
    done
    case "${LIFECYCLE_COMPONENT}" in
        alacritty)
            python3 "${SCRIPT_DIR}/terminal.py" check-alacritty
            [[ "$("${HOME}/.local/bin/alacritty" --version)" == "alacritty 0.18.0-dev (${REVISION:0:8})" ]] || { err 'Pinned user Alacritty development build is missing'; return 1; } ;;
        herdr) python3 "${SCRIPT_DIR}/terminal.py" check-herdr; "${HOME}/.local/bin/herdr" --version ;;
        hindsight) python3 "${SCRIPT_DIR}/hindsight.py" preflight; python3 "${SCRIPT_DIR}/hindsight.py" health ;;
        tools) python3 "${SCRIPT_DIR}/packages.py" check ;;
        router) python3 "${SCRIPT_DIR}/router.py" check ;;
        tailscale) python3 "${SCRIPT_DIR}/tailscale.py" check ;;
        mise) MISE_OFFLINE=true MISE_SELF_UPDATE_AVAILABLE=false "${HOME}/.local/bin/mise" --version ;;
        hooks) [[ "$(git -C "${SCRIPT_DIR}/.." config --local core.hooksPath)" == .githooks ]] && [[ -x "${SCRIPT_DIR}/../.githooks/pre-commit" ]] ;;
        blender) "${INSTALL_DIR}/blender" --version ;;
        reaper) test -x "${INSTALL_PREFIX}/REAPER/reaper" ;;
        ghidra) test -x "${INSTALL_DIR}/ghidraRun" ;;
        neovim) /usr/local/bin/nvim --version ;;
        ollama) test -x "${INSTALL_DIR}/bin/ollama" ;;
        8bitdo) test -f "${UDEV_RULES_PATH}" ;;
    esac
    log "${LIFECYCLE_COMPONENT}: check passed"
}

lifecycle_uninstall() {
    lifecycle_receipt verify
    case "${LIFECYCLE_COMPONENT}" in
        herdr) systemctl --user disable --now herdr.service ;;
        router)
            systemctl --user disable --now 9router.service
            "${COMPOSE[@]}" down ;;
        tailscale) systemctl --user disable --now tailscale.service ;;
        hindsight)
            systemctl --user disable --now hindsight.service
            systemctl --user disable --now hindsight-db.service
            "${COMPOSE[@]}" down ;;
        ollama) safe_sudo systemctl disable --now ollama.service ;;
        8bitdo) safe_sudo systemctl stop '8bitdo-ultimate-xinput@*.service' ;;
        hooks)
            if [[ "$(git -C "${SCRIPT_DIR}/.." config --local --get core.hooksPath || true)" == .githooks ]]; then
                git -C "${SCRIPT_DIR}/.." config --local --unset core.hooksPath
            fi ;;
        tools) python3 "${SCRIPT_DIR}/packages.py" uninstall ;;
    esac
    lifecycle_receipt remove
    if [[ "${LIFECYCLE_COMPONENT}" == 8bitdo ]]; then
        safe_sudo systemctl daemon-reload
        reload_udev_rules_if_available
    fi
    log 'Removed recorded software only; configuration, credentials, models, databases and shared dependencies retained'
}

lifecycle_dispatch() {
    LIFECYCLE_COMPONENT="$1"
    shift
    LIFECYCLE_ACTION="${1:-}"
    if [[ "${LIFECYCLE_COMPONENT}" == ghidra && "${LIFECYCLE_ACTION}" == run ]]; then
        main "$@"
        return
    fi
    case "${LIFECYCLE_ACTION}" in
        install|update|uninstall|check) shift ;;
        -h|--help|help) lifecycle_usage; usage; return ;;
        *) lifecycle_usage; return 2 ;;
    esac
    export LIFECYCLE_ACTION
    local argument dry_run=false verify=false
    local -a arguments=()
    for argument in "$@"; do
        case "${argument}" in
            --dry-run) dry_run=true ;;
            --verify) verify=true ;;
            -h|--help) lifecycle_usage; usage; return ;;
            *) arguments+=("${argument}") ;;
        esac
    done
    [[ "${verify}" != true || "${LIFECYCLE_ACTION}" == uninstall ]] || { err '--verify is only valid with uninstall'; return 2; }
    if [[ "${LIFECYCLE_COMPONENT}" == ghidra ]]; then
        if [[ "${LIFECYCLE_ACTION}" == uninstall || "${LIFECYCLE_ACTION}" == check ]]; then load_config; fi
        parse_args install "${arguments[@]}"
    else
        parse_args "${arguments[@]}"
    fi
    lifecycle_payload
    if [[ "${dry_run}" == true ]]; then
        log "DRY-RUN: ${LIFECYCLE_ACTION} ${LIFECYCLE_COMPONENT}; no downloads, writes or service changes"
        case "${LIFECYCLE_ACTION}" in
            uninstall) log 'Verify ownership receipt and unchanged files; stop component services; remove recorded payload without configuration/data' ;;
            check) log 'Read-only component validation' ;;
            *)
                if [[ "${LIFECYCLE_COMPONENT}" == alacritty ]]; then
                    log "Compile ${REVISION}: cargo build --release --locked; verify 0.18.0-dev (${REVISION:0:8})"
                fi ;;
        esac
        return
    fi
    require_commands python3
    if [[ "${verify}" == true ]]; then lifecycle_receipt verify; return; fi
    case "${LIFECYCLE_ACTION}" in
        check) lifecycle_check ;;
        uninstall) lifecycle_uninstall ;;
        install|update)
            if [[ "${LIFECYCLE_COMPONENT}" == ghidra ]]; then main install "${arguments[@]}"; else main "${arguments[@]}"; fi
            lifecycle_receipt record ;;
    esac
}

resolve_ubuntu_codename() {
    local codename=""

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    fi

    if [[ -z "${codename}" ]] && command -v lsb_release >/dev/null 2>&1; then
        codename="$(lsb_release -cs 2>/dev/null || true)"
    fi

    if [[ -z "${codename}" ]]; then
        err "Unable to determine Ubuntu codename from /etc/os-release or lsb_release"
        return 1
    fi

    printf '%s\n' "${codename}"
}

normalize_path_strict() {
    local path="${1:-}"

    [[ -n "${path}" ]] || return 1
    while [[ "${path}" != "/" && "${path}" == */ ]]; do
        path="${path%/}"
    done

    printf '%s\n' "${path}"
}

path_is_within_prefix() {
    local path="${1:-}"
    local prefix="${2:-}"
    [[ -n "${path}" && -n "${prefix}" ]] || return 1
    [[ "${path}" == "${prefix}" || "${path}" == "${prefix}/"* ]]
}

resolve_abs_path_safe() {
    local path="${1:-}"
    [[ -n "${path}" ]] || return 1

    if command_exists readlink; then
        readlink -m -- "${path}" 2>/dev/null || return 1
        return 0
    fi

    err "resolve_abs_path_safe requires readlink"
    return 1
}

delib_load_desktop_preference_target_pairs() {
    local pairs_name="${1:-}"

    [[ -n "${pairs_name}" ]] || {
        err "delib_load_desktop_preference_target_pairs requires an array variable name"
        return 1
    }

    local -n pairs_ref="${pairs_name}"
    # shellcheck disable=SC2034
    pairs_ref=("${DELIB_DESKTOP_PREFERENCE_TARGET_PAIRS[@]}")
}

register_mktemp_cleanup_parent_prefix() {
    local created_path="${1:-}"
    local parent=""
    local normalized_parent=""
    local resolved_parent=""
    local existing=""

    [[ -n "${created_path}" ]] || return 1
    parent="${created_path%/*}"
    [[ -n "${parent}" ]] || parent="/"

    normalized_parent="$(normalize_path_strict "${parent}" || true)"
    [[ -n "${normalized_parent}" && "${normalized_parent}" == /* && "${normalized_parent}" != "/" ]] || return 1

    resolved_parent="$(resolve_abs_path_safe "${normalized_parent}" || true)"
    resolved_parent="$(normalize_path_strict "${resolved_parent}" || true)"
    [[ -n "${resolved_parent}" && "${resolved_parent}" == /* && "${resolved_parent}" != "/" ]] || return 1

    for existing in "${DELIB_MKTEMP_PARENT_PREFIXES[@]}"; do
        if [[ "${existing}" == "${resolved_parent}" ]]; then
            return 0
        fi
    done

    DELIB_MKTEMP_PARENT_PREFIXES+=("${resolved_parent}")
}

validate_temp_cleanup_target_path() {
    local candidate_raw="${1:-}"
    local normalized_candidate=""
    local resolved_candidate=""
    local normalized_prefix=""
    local resolved_prefix=""
    local prefix=""
    local -a allowed_prefixes=()

    normalized_candidate="$(normalize_path_strict "${candidate_raw}" || true)"
    if [[ -z "${normalized_candidate}" || "${normalized_candidate}" == "/" || "${normalized_candidate}" == "." || "${normalized_candidate}" == ".." ]]; then
        err "Unsafe cleanup target rejected: '${candidate_raw}'"
        return 1
    fi

    if [[ "${normalized_candidate}" != /* ]]; then
        err "Cleanup target must be absolute: ${candidate_raw}"
        return 1
    fi

    resolved_candidate="$(resolve_abs_path_safe "${normalized_candidate}" || true)"
    resolved_candidate="$(normalize_path_strict "${resolved_candidate}" || true)"
    if [[ -z "${resolved_candidate}" || "${resolved_candidate}" == "/" || "${resolved_candidate}" == "." || "${resolved_candidate}" == ".." ]]; then
        err "Unsafe normalized cleanup target rejected: '${candidate_raw}'"
        return 1
    fi

    if [[ "${resolved_candidate}" != /* ]]; then
        err "Normalized cleanup target must be absolute: ${resolved_candidate}"
        return 1
    fi

    allowed_prefixes=("${DELIB_SAFE_TEMP_PREFIXES[@]}" "${DELIB_MKTEMP_PARENT_PREFIXES[@]}")
    for prefix in "${allowed_prefixes[@]}"; do
        normalized_prefix="$(normalize_path_strict "${prefix}" || true)"
        [[ -n "${normalized_prefix}" && "${normalized_prefix}" == /* ]] || continue

        resolved_prefix="$(resolve_abs_path_safe "${normalized_prefix}" || true)"
        resolved_prefix="$(normalize_path_strict "${resolved_prefix}" || true)"
        [[ -n "${resolved_prefix}" && "${resolved_prefix}" == /* && "${resolved_prefix}" != "/" ]] || continue

        if [[ "${resolved_candidate}" == "${resolved_prefix}" ]]; then
            err "Refusing to delete temp boundary root: ${candidate_raw}"
            return 1
        fi

        if path_is_within_prefix "${resolved_candidate}" "${resolved_prefix}"; then
            printf '%s\n' "${resolved_candidate}"
            return 0
        fi
    done

    err "Cleanup target '${candidate_raw}' is outside allowed temporary prefixes"
    return 1
}

validate_install_dir_against_prefixes() {
    local candidate_raw="${1:-}"
    local prefixes_name="${2:-}"
    local label="${3:-path}"
    local candidate=""
    local normalized_prefix=""
    local prefix=""
    local -n prefixes_ref="${prefixes_name}"

    candidate="$(normalize_path_strict "${candidate_raw}" || true)"
    if [[ -z "${candidate}" || "${candidate}" == "/" || "${candidate}" == "." || "${candidate}" == ".." ]]; then
        err "Unsafe ${label} rejected: '${candidate_raw}'"
        return 1
    fi

    if [[ "${candidate}" != /* ]]; then
        err "${label} must be absolute: ${candidate_raw}"
        return 1
    fi

    for prefix in "${prefixes_ref[@]}"; do
        normalized_prefix="$(normalize_path_strict "${prefix}" || true)"
        if path_is_within_prefix "${candidate}" "${normalized_prefix}"; then
            return 0
        fi
    done

    err "${label} '${candidate_raw}' is outside allowed prefixes: ${prefixes_ref[*]}"
    return 1
}

validate_resolved_path_against_prefixes() {
    local candidate_raw="${1:-}"
    local prefixes_name="${2:-}"
    local label="${3:-path}"
    local resolved_candidate=""
    local normalized_candidate=""
    local normalized_prefix=""
    local resolved_prefix=""
    local prefix=""
    local -n prefixes_ref="${prefixes_name}"

    normalized_candidate="$(normalize_path_strict "${candidate_raw}" || true)"
    if [[ -z "${normalized_candidate}" || "${normalized_candidate}" == "/" || "${normalized_candidate}" == "." || "${normalized_candidate}" == ".." ]]; then
        err "Unsafe ${label} rejected: '${candidate_raw}'"
        return 1
    fi

    if [[ "${normalized_candidate}" != /* ]]; then
        err "${label} must be absolute: ${candidate_raw}"
        return 1
    fi

    resolved_candidate="$(resolve_abs_path_safe "${normalized_candidate}" || true)"
    resolved_candidate="$(normalize_path_strict "${resolved_candidate}" || true)"
    if [[ -z "${resolved_candidate}" || "${resolved_candidate}" == "/" || "${resolved_candidate}" == "." || "${resolved_candidate}" == ".." ]]; then
        err "Unsafe normalized ${label} rejected: '${resolved_candidate}'"
        return 1
    fi

    if [[ "${resolved_candidate}" != /* ]]; then
        err "Normalized ${label} must be absolute: ${resolved_candidate}"
        return 1
    fi

    for prefix in "${prefixes_ref[@]}"; do
        normalized_prefix="$(normalize_path_strict "${prefix}" || true)"
        [[ -n "${normalized_prefix}" && "${normalized_prefix}" == /* ]] || continue

        resolved_prefix="$(resolve_abs_path_safe "${normalized_prefix}" || true)"
        resolved_prefix="$(normalize_path_strict "${resolved_prefix}" || true)"
        [[ -n "${resolved_prefix}" && "${resolved_prefix}" == /* ]] || continue

        if path_is_within_prefix "${resolved_candidate}" "${resolved_prefix}"; then
            printf '%s\n' "${resolved_candidate}"
            return 0
        fi
    done

    err "${label} '${candidate_raw}' is outside allowed prefixes: ${prefixes_ref[*]}"
    return 1
}

assert_no_symlink_components() {
    local target_raw="${1:-}"
    local label="${2:-path}"
    local normalized_target=""
    local current="/"
    local component=""
    local -a components=()

    normalized_target="$(normalize_path_strict "${target_raw}" || true)"
    if [[ -z "${normalized_target}" || "${normalized_target}" != /* || "${normalized_target}" == "/" ]]; then
        err "${label} must be an absolute non-root path"
        return 1
    fi

    IFS='/' read -r -a components <<< "${normalized_target#/}"
    for component in "${components[@]}"; do
        [[ -n "${component}" ]] || continue

        if [[ "${current}" == "/" ]]; then
            current="/${component}"
        else
            current+="/${component}"
        fi

        if [[ -L "${current}" ]]; then
            err "${label} contains symlink component: ${current}"
            return 1
        fi

        if [[ ! -e "${current}" ]]; then
            break
        fi
    done
}

write_text_file_atomic() {
    local destination_raw="${1:-}"
    local content="${2-}"
    local label="${3:-file}"
    local destination=""
    local destination_parent=""
    local temp_file=""

    destination="$(normalize_path_strict "${destination_raw}" || true)"
    if [[ -z "${destination}" || "${destination}" != /* || "${destination}" == "/" ]]; then
        err "${label} destination must be an absolute non-root path"
        return 1
    fi

    destination="$(resolve_abs_path_safe "${destination}" || true)"
    destination="$(normalize_path_strict "${destination}" || true)"
    if [[ -z "${destination}" || "${destination}" != /* || "${destination}" == "/" ]]; then
        err "Unable to resolve ${label} destination path safely"
        return 1
    fi

    destination_parent="${destination%/*}"
    [[ -n "${destination_parent}" ]] || destination_parent="/"

    assert_no_symlink_components "${destination_parent}" "${label} parent path" || return 1
    mkdir -p "${destination_parent}"
    assert_no_symlink_components "${destination_parent}" "${label} parent path" || return 1
    assert_no_symlink_components "${destination}" "${label} destination path" || return 1

    if [[ -L "${destination}" ]]; then
        err "Refusing to overwrite symlinked ${label}: ${destination}"
        return 1
    fi

    if [[ -e "${destination}" && ! -f "${destination}" ]]; then
        err "Refusing to overwrite non-regular ${label}: ${destination}"
        return 1
    fi

    mktemp_file_var temp_file "${destination_parent}/.delib.atomic.XXXXXX" || return 1

    if ! printf '%s\n' "${content}" > "${temp_file}"; then
        rm -f -- "${temp_file}" || true
        err "Failed writing temporary ${label}: ${temp_file}"
        return 1
    fi

    if ! mv -f -- "${temp_file}" "${destination}"; then
        rm -f -- "${temp_file}" || true
        err "Failed atomic move for ${label}: ${destination}"
        return 1
    fi
}

validate_sha256_hex() {
    local value="${1:-}"
    local label="${2:-sha256}"

    if [[ ! "${value}" =~ ^[A-Fa-f0-9]{64}$ ]]; then
        err "${label} must be a 64-character SHA256 hex string"
        return 1
    fi

    printf '%s\n' "${value,,}"
}

fetch_sidecar_sha256() {
    local checksum_url="${1:-}"
    local target_name="${2:-}"
    local payload=""
    local digest=""

    require_commands curl awk || return 1
    [[ -n "${checksum_url}" ]] || {
        err "fetch_sidecar_sha256 requires checksum URL"
        return 1
    }

    payload="$(curl -fsSL "${checksum_url}" || true)"
    if [[ -z "${payload}" ]]; then
        err "Unable to fetch checksum metadata from ${checksum_url}"
        return 1
    fi

    if [[ -n "${target_name}" ]]; then
        digest="$(printf '%s\n' "${payload}" | awk -v target="${target_name}" 'index($0,target){print $1; exit}')"
    fi
    if [[ -z "${digest}" ]]; then
        digest="$(printf '%s\n' "${payload}" | awk 'NF>0 {print $1; exit}')"
    fi

    validate_sha256_hex "${digest}" "checksum"
}

resolve_sha256_with_fallback() {
    local explicit_sha256="${1:-}"
    local explicit_label="${2:-SHA256}"
    local fallback_sha256="${3:-}"
    local checksum_url="${4:-}"
    local target_name="${5:-}"
    local artifact_label="${6:-artifact}"
    local guidance_message="${7:-}"
    local digest=""

    if [[ -n "${explicit_sha256}" ]]; then
        validate_sha256_hex "${explicit_sha256}" "${explicit_label}"
        return
    fi

    if [[ -n "${fallback_sha256}" ]]; then
        digest="$(validate_sha256_hex "${fallback_sha256}" "checksum" || true)"
    fi

    if [[ -z "${digest}" && -n "${checksum_url}" ]]; then
        digest="$(fetch_sidecar_sha256 "${checksum_url}" "${target_name}" || true)"
    fi

    if [[ ! "${digest}" =~ ^[A-Fa-f0-9]{64}$ ]]; then
        err "Unable to determine trusted checksum for ${artifact_label}"
        if [[ -n "${guidance_message}" ]]; then
            err "${guidance_message}"
        fi
        return 1
    fi

    printf '%s\n' "${digest,,}"
}

verify_archive_sha256_with_resolver() {
    local archive_path="${1:-}"
    local resolver_fn="${2:-}"
    local artifact_label="${3:-archive}"
    local success_logger_fn="${4:-log}"
    local expected_sha256=""

    [[ -n "${archive_path}" && -f "${archive_path}" ]] || {
        err "Cannot verify checksum; archive not found: ${archive_path}"
        return 1
    }

    if [[ -z "${resolver_fn}" ]] || ! declare -F "${resolver_fn}" >/dev/null 2>&1; then
        err "verify_archive_sha256_with_resolver requires a valid resolver function"
        return 1
    fi

    expected_sha256="$("${resolver_fn}")" || return 1
    verify_file_sha256 "${archive_path}" "${expected_sha256}" "${artifact_label}" || return 1

    if [[ -n "${success_logger_fn}" ]]; then
        if declare -F "${success_logger_fn}" >/dev/null 2>&1; then
            "${success_logger_fn}" "Checksum verified for ${artifact_label}"
        else
            err "Unknown success logger function: ${success_logger_fn}"
            return 1
        fi
    fi
}

compute_sha256() {
    local file_path="${1:-}"
    [[ -n "${file_path}" && -f "${file_path}" ]] || {
        err "Cannot compute checksum; file not found: ${file_path}"
        return 1
    }

    require_commands sha256sum awk || return 1
    sha256sum "${file_path}" | awk '{print $1}'
}

verify_file_sha256() {
    local file_path="${1:-}"
    local expected_raw="${2:-}"
    local label="${3:-file}"
    local expected=""
    local actual=""

    [[ -n "${file_path}" && -f "${file_path}" ]] || {
        err "Cannot verify checksum; file not found: ${file_path}"
        return 1
    }

    expected="$(validate_sha256_hex "${expected_raw}" "expected checksum" || true)"
    [[ -n "${expected}" ]] || return 1
    actual="$(compute_sha256 "${file_path}" || true)"
    [[ -n "${actual}" ]] || return 1

    if [[ "${actual}" != "${expected}" ]]; then
        err "Checksum mismatch for ${label}: expected ${expected}, got ${actual}"
        return 1
    fi

    return 0
}

mktemp_file_var() {
    local var_name="${1:-}"
    local template="${2:-/tmp/delib.XXXXXX}"
    local created=""

    [[ -n "${var_name}" ]] || {
        err "mktemp_file_var requires a variable name"
        return 1
    }

    created="$(mktemp "${template}")" || return 1
    register_mktemp_cleanup_parent_prefix "${created}" || true
    printf -v "${var_name}" '%s' "${created}"
}

mktemp_dir_var() {
    local var_name="${1:-}"
    local template="${2:-/tmp/delib.XXXXXX}"
    local created=""

    [[ -n "${var_name}" ]] || {
        err "mktemp_dir_var requires a variable name"
        return 1
    }

    created="$(mktemp -d "${template}")" || return 1
    register_mktemp_cleanup_parent_prefix "${created}" || true
    printf -v "${var_name}" '%s' "${created}"
}

cleanup_paths_if_present() {
    local path=""
    local safe_path=""

    for path in "$@"; do
        [[ -n "${path}" ]] || continue
        if [[ -d "${path}" || -f "${path}" || -L "${path}" ]]; then
            safe_path="$(validate_temp_cleanup_target_path "${path}" || true)"
            if [[ -z "${safe_path}" ]]; then
                log_warn "Skipping unsafe cleanup target: ${path}"
                continue
            fi
            rm -rf -- "${safe_path}" || true
        fi
    done
}

cleanup_temp_vars() {
    local var_name=""
    local path_value=""

    for var_name in "$@"; do
        if [[ ! "${var_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            err "cleanup_temp_vars received invalid variable name: ${var_name}"
            return 1
        fi

        path_value="${!var_name-}"
        if [[ -n "${path_value}" ]]; then
            cleanup_paths_if_present "${path_value}"
        fi
        printf -v "${var_name}" '%s' ""
    done
}

trap_cleanup_handler() {
    local handler="${1:-}"
    shift || true

    [[ -n "${handler}" ]] || {
        err "trap_cleanup_handler requires a handler function name"
        return 1
    }

    if [[ "$#" -eq 0 ]]; then
        set -- EXIT INT TERM
    fi

    # shellcheck disable=SC2064
    trap "${handler}" "$@"
}

apt_prepare_repo_prereqs() {
    apt_install_missing ca-certificates curl gnupg
}

apt_prepare_repo_prereqs_extra() {
    apt_install_missing ca-certificates curl gnupg "$@"
}

apt_install_keyring_from_url() {
    local url="${1:-}"
    local keyring_path="${2:-}"
    local chmod_mode="${3:-0644}"

    [[ -n "${url}" && -n "${keyring_path}" ]] || {
        err "apt_install_keyring_from_url requires url and keyring path"
        return 1
    }

    require_commands curl tee chmod dirname || return 1
    safe_sudo mkdir -p "$(dirname "${keyring_path}")"
    curl -fsSL "${url}" | safe_sudo tee "${keyring_path}" >/dev/null
    safe_sudo chmod "${chmod_mode}" "${keyring_path}"
}

apt_install_keyring_from_stream() {
    local url="${1:-}"
    local keyring_path="${2:-}"
    local chmod_mode="${3:-0644}"
    shift 3 || true

    [[ -n "${url}" && -n "${keyring_path}" ]] || {
        err "apt_install_keyring_from_stream requires url and keyring path"
        return 1
    }

    require_commands curl tee chmod dirname || return 1
    safe_sudo mkdir -p "$(dirname "${keyring_path}")"

    if [[ "$#" -gt 0 ]]; then
        curl -fsSL "${url}" | "$@" | safe_sudo tee "${keyring_path}" >/dev/null
    else
        curl -fsSL "${url}" | safe_sudo tee "${keyring_path}" >/dev/null
    fi

    safe_sudo chmod "${chmod_mode}" "${keyring_path}"
}

apt_write_source_line() {
    local source_path="${1:-}"
    local source_line="${2:-}"

    [[ -n "${source_path}" && -n "${source_line}" ]] || {
        err "apt_write_source_line requires source path and source line"
        return 1
    }

    require_commands tee dirname || return 1
    safe_sudo mkdir -p "$(dirname "${source_path}")"
    printf '%s\n' "${source_line}" | safe_sudo tee "${source_path}" >/dev/null
}

apt_configure_repo_with_keyring_and_source_line() {
    local keyring_url="${1:-}"
    local keyring_path="${2:-}"
    local source_path="${3:-}"
    local source_line="${4:-}"
    local chmod_mode="${5:-0644}"

    [[ -n "${keyring_url}" && -n "${keyring_path}" && -n "${source_path}" && -n "${source_line}" ]] || {
        err "apt_configure_repo_with_keyring_and_source_line requires keyring URL/path and source path/line"
        return 1
    }

    apt_install_keyring_from_url "${keyring_url}" "${keyring_path}" "${chmod_mode}"
    apt_write_source_line "${source_path}" "${source_line}"
    apt_mark_index_stale
}

apt_write_source_from_stream() {
    local url="${1:-}"
    local source_path="${2:-}"
    shift 2 || true

    [[ -n "${url}" && -n "${source_path}" ]] || {
        err "apt_write_source_from_stream requires url and source path"
        return 1
    }

    require_commands curl tee dirname || return 1
    safe_sudo mkdir -p "$(dirname "${source_path}")"

    if [[ "$#" -gt 0 ]]; then
        curl -fsSL "${url}" | "$@" | safe_sudo tee "${source_path}" >/dev/null
    else
        curl -fsSL "${url}" | safe_sudo tee "${source_path}" >/dev/null
    fi
}

apt_mark_index_stale() {
    reset_apt_update
}

require_systemctl_or_fail() {
    local context="${1:-operation}"
    if ! has_systemctl; then
        err "systemctl not available for ${context}"
        return 1
    fi
}

with_systemctl_or_log() {
    local context="${1:-systemd action}"
    shift || true

    if has_systemctl; then
        safe_sudo "$@"
    else
        log "systemctl not available; skipping ${context}"
    fi
}

systemd_daemon_reload_if_available() {
    with_systemctl_or_log "daemon-reload" systemctl daemon-reload
}

reload_udev_rules_if_available() {
    if command_exists udevadm; then
        safe_sudo udevadm control --reload-rules
        safe_sudo udevadm trigger
    else
        log "udevadm not available; udev rule reload skipped"
    fi
}

set_dry_run_mode() {
    local mode="${1:-false}"
    case "${mode}" in
        true|false) DELIB_DRY_RUN="${mode}" ;;
        *)
            err "set_dry_run_mode expects true or false"
            return 1
            ;;
    esac
}

run_maybe_dry() {
    local -a cmd=("$@")

    if [[ "${#cmd[@]}" -eq 0 ]]; then
        err "run_maybe_dry requires a command"
        return 1
    fi

    if [[ "${DELIB_DRY_RUN}" == "true" ]]; then
        printf '[%s] DRY-RUN:' "${INSTALL_LIB_TAG}"
        printf ' %q' "${cmd[@]}"
        printf '\n'
        return 0
    fi

    "${cmd[@]}"
}

resolve_user_home_dir() {
    local target_user="${1:-}"
    local passwd_entry=""
    local home_dir=""

    [[ -n "${target_user}" ]] || {
        err "resolve_user_home_dir requires a user name"
        return 1
    }

    if command_exists getent; then
        passwd_entry="$(getent passwd "${target_user}" || true)"
    fi

    if [[ -z "${passwd_entry}" && -r /etc/passwd ]]; then
        passwd_entry="$(awk -F: -v user="${target_user}" '$1 == user { print; exit }' /etc/passwd || true)"
    fi

    home_dir="$(awk -F: '{print $6}' <<< "${passwd_entry}")"
    if [[ -z "${home_dir}" ]]; then
        err "Unable to resolve home directory for user: ${target_user}"
        return 1
    fi

    printf '%s\n' "${home_dir}"
}

resolve_desktop_target_user() {
    local target_user="${DESKTOP_TARGET_USER:-}"

    if [[ -n "${target_user}" ]]; then
        :
    elif [[ "${EUID}" -ne 0 ]]; then
        target_user="$(id -un)"
    elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        target_user="${SUDO_USER}"
    else
        err "Desktop user context is unavailable when running as root. Re-run via sudo from the desktop user session or set DESKTOP_TARGET_USER=<user>."
        return 1
    fi

    if ! id "${target_user}" >/dev/null 2>&1; then
        err "Configured desktop target user does not exist: ${target_user}"
        return 1
    fi

    printf '%s\n' "${target_user}"
}

prepare_desktop_gsettings_context() {
    local target_user=""
    local target_uid=""
    local runtime_dir=""
    local bus_address=""
    local target_home=""

    if [[ "${DELIB_DESKTOP_CONTEXT_READY}" -eq 1 ]]; then
        return 0
    fi

    require_command gsettings || return 1

    target_user="$(resolve_desktop_target_user)" || return 1
    target_uid="$(id -u "${target_user}" 2>/dev/null || true)"
    if [[ -z "${target_uid}" ]]; then
        err "Unable to resolve UID for desktop target user: ${target_user}"
        return 1
    fi

    target_home="$(resolve_user_home_dir "${target_user}" || true)"
    [[ -n "${target_home}" ]] || target_home="/home/${target_user}"

    if [[ -n "${XDG_RUNTIME_DIR:-}" && "${XDG_RUNTIME_DIR}" == "/run/user/${target_uid}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
        runtime_dir="${XDG_RUNTIME_DIR}"
    elif [[ -S "/run/user/${target_uid}/bus" ]]; then
        runtime_dir="/run/user/${target_uid}"
    fi

    if [[ -n "${runtime_dir}" ]]; then
        bus_address="unix:path=${runtime_dir}/bus"
    elif [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        bus_address="${DBUS_SESSION_BUS_ADDRESS}"
    else
        err "Unable to locate a desktop D-Bus session for '${target_user}'. Log in to a desktop session or provide DBUS_SESSION_BUS_ADDRESS for that user."
        return 1
    fi

    DELIB_DESKTOP_TARGET_USER="${target_user}"
    DELIB_DESKTOP_TARGET_UID="${target_uid}"
    DELIB_DESKTOP_RUNTIME_DIR="${runtime_dir}"
    DELIB_DESKTOP_DBUS_SESSION_BUS_ADDRESS="${bus_address}"
    DELIB_DESKTOP_TARGET_HOME="${target_home}"
    DELIB_DESKTOP_CONTEXT_READY=1
}

run_gsettings_in_desktop_context() {
    local -a gsettings_cmd=(gsettings "$@")
    local current_user=""
    local -a env_cmd=(env)

    [[ "${#gsettings_cmd[@]}" -gt 1 ]] || {
        err "run_gsettings_in_desktop_context requires gsettings arguments"
        return 1
    }

    prepare_desktop_gsettings_context || return 1

    if [[ -n "${DELIB_DESKTOP_RUNTIME_DIR}" ]]; then
        env_cmd+=("XDG_RUNTIME_DIR=${DELIB_DESKTOP_RUNTIME_DIR}")
    fi
    env_cmd+=("DBUS_SESSION_BUS_ADDRESS=${DELIB_DESKTOP_DBUS_SESSION_BUS_ADDRESS}")
    env_cmd+=("HOME=${DELIB_DESKTOP_TARGET_HOME}")

    current_user="$(id -un)"
    if [[ "${current_user}" == "${DELIB_DESKTOP_TARGET_USER}" ]]; then
        "${env_cmd[@]}" "${gsettings_cmd[@]}"
        return 0
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        if command_exists runuser; then
            runuser -u "${DELIB_DESKTOP_TARGET_USER}" -- "${env_cmd[@]}" "${gsettings_cmd[@]}"
            return 0
        fi
        if command_exists sudo; then
            sudo -u "${DELIB_DESKTOP_TARGET_USER}" -- "${env_cmd[@]}" "${gsettings_cmd[@]}"
            return 0
        fi

        err "Need runuser or sudo to execute gsettings as ${DELIB_DESKTOP_TARGET_USER}"
        return 1
    fi

    require_command sudo || {
        err "Current user '${current_user}' cannot switch to desktop target '${DELIB_DESKTOP_TARGET_USER}' without sudo"
        return 1
    }
    sudo -u "${DELIB_DESKTOP_TARGET_USER}" -- "${env_cmd[@]}" "${gsettings_cmd[@]}"
}

delib_load_available_gsettings_schemas() {
    local schema_set_name="${1:-}"
    local schema=""

    [[ -n "${schema_set_name}" ]] || {
        err "delib_load_available_gsettings_schemas requires an associative array variable name"
        return 1
    }

    local -n schema_set_ref="${schema_set_name}"
    schema_set_ref=()
    while IFS= read -r schema; do
        [[ -n "${schema}" ]] || continue
        schema_set_ref["${schema}"]=1
    done < <(run_gsettings_in_desktop_context list-schemas)
}

delib_gsettings_schema_exists() {
    local schema_set_name="${1:-}"
    local schema="${2:-}"

    [[ -n "${schema_set_name}" ]] || {
        err "delib_gsettings_schema_exists requires a schema set variable name"
        return 1
    }

    # shellcheck disable=SC2178
    local -n schema_set_ref="${schema_set_name}"

    [[ -n "${schema}" && -n "${schema_set_ref[${schema}]+x}" ]]
}

delib_gsettings_schema_has_key() {
    local schema_cache_name="${1:-}"
    local schema="${2:-}"
    local key="${3:-}"

    [[ -n "${schema_cache_name}" && -n "${schema}" && -n "${key}" ]] || {
        err "delib_gsettings_schema_has_key requires cache variable name, schema, and key"
        return 1
    }

    # shellcheck disable=SC2178
    local -n schema_cache_ref="${schema_cache_name}"

    if [[ -z "${schema_cache_ref[${schema}]+x}" ]]; then
        schema_cache_ref["${schema}"]="$(run_gsettings_in_desktop_context list-keys "${schema}" 2>/dev/null || true)"
    fi

    grep -Fxq -- "${key}" <<< "${schema_cache_ref[${schema}]}"
}

delib_gsettings_get() {
    local schema="${1:-}"
    local key="${2:-}"

    [[ -n "${schema}" && -n "${key}" ]] || {
        err "delib_gsettings_get requires schema and key"
        return 1
    }

    run_gsettings_in_desktop_context get "${schema}" "${key}"
}

delib_gsettings_set() {
    local schema="${1:-}"
    local key="${2:-}"
    local value="${3:-}"

    [[ -n "${schema}" && -n "${key}" ]] || {
        err "delib_gsettings_set requires schema and key"
        return 1
    }

    run_gsettings_in_desktop_context set "${schema}" "${key}" "${value}"
}

require_file_exists() {
    local file_path="${1:-}"
    local label="${2:-file}"

    if [[ ! -f "${file_path}" ]]; then
        err "Required ${label} not found: ${file_path}"
        return 1
    fi
}

run_script_maybe_dry() {
    local script_path="${1:-}"
    shift || true

    require_file_exists "${script_path}" "script" || return 1
    run_maybe_dry "${script_path}" "$@"
}

write_desktop_entry_from_stdin() {
    local desktop_entry_path="${1:-}"
    local mode="${2:-0644}"

    [[ -n "${desktop_entry_path}" ]] || {
        err "write_desktop_entry_from_stdin requires a desktop entry path"
        return 1
    }

    require_commands tee chmod dirname || return 1
    safe_sudo mkdir -p "$(dirname "${desktop_entry_path}")"
    safe_sudo tee "${desktop_entry_path}" >/dev/null
    safe_sudo chmod "${mode}" "${desktop_entry_path}"
}

update_desktop_database_if_available() {
    local desktop_dir="${1:-/usr/share/applications/}"

    if command_exists update-desktop-database; then
        safe_sudo update-desktop-database "${desktop_dir}"
    fi
}

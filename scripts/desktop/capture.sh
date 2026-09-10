#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="desktop-export"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/../delib.sh"

DEFAULT_OUTPUT_DIR_REL="root/home/user/.config/repro/desktop-preferences"
REPO_ROOT="$(resolve_abs_path_safe "${SCRIPT_DIR}/../..")"
DEFAULT_OUTPUT_DIR="$(resolve_abs_path_safe "${REPO_ROOT}/${DEFAULT_OUTPUT_DIR_REL}")"

OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
DRY_RUN="false"
STRICT_MODE="false"

declare -a TARGET_PAIRS=()
declare -a TARGET_SCHEMAS=()
declare -a DESKTOP_PREF_ALLOWED_PREFIXES=()

# shellcheck disable=SC2034
declare -A AVAILABLE_SCHEMA_SET=()
# shellcheck disable=SC2034
declare -A SCHEMA_KEYS_CACHE=()
declare -A EXPORTED_VALUES=()

declare -a EXPORTED_KEYS=()
declare -a SKIPPED_KEYS=()
declare -a AVAILABLE_TARGET_SCHEMAS=()
declare -a MISSING_TARGET_SCHEMAS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/desktop.sh export [OPTIONS]

Exports deterministic desktop preference keys via gsettings.

Options:
  --dry-run            Preview actions without writing artifacts.
  --strict             Fail if any targeted schema/key pair is unavailable.
    --output <dir>       Export directory (default: root/home/user/.config/repro/desktop-preferences)
  -h, --help           Show this help text.

Notes:
  - This script only handles explicit desktop preference keys.
  - This script does not read or write ~/.config/dconf/user.
  - Pre-import snapshot convention: <dir>/pre-import-keys.dconf.ini
EOF
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                usage
                exit 0
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --strict)
                STRICT_MODE="true"
                shift
                ;;
            --output)
                require_option_value "--output" "${2-}" || return 1
                OUTPUT_DIR="$2"
                shift 2
                ;;
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

append_unique_item() {
    local array_name="${1:-}"
    local candidate="${2:-}"
    local item=""

    [[ -n "${array_name}" && -n "${candidate}" ]] || return 1
    local -n array_ref="${array_name}"

    for item in "${array_ref[@]}"; do
        if [[ "${item}" == "${candidate}" ]]; then
            return 0
        fi
    done

    array_ref+=("${candidate}")
}

initialize_target_pairs_and_schemas() {
    local pair=""
    local schema=""

    delib_load_desktop_preference_target_pairs TARGET_PAIRS || return 1
    TARGET_SCHEMAS=()

    for pair in "${TARGET_PAIRS[@]}"; do
        schema="${pair%%:*}"
        append_unique_item TARGET_SCHEMAS "${schema}"
    done
}

build_allowed_output_prefixes() {
    local prefix=""
    local resolved_prefix=""

    # shellcheck disable=SC2034
    DESKTOP_PREF_ALLOWED_PREFIXES=()
    append_unique_item DESKTOP_PREF_ALLOWED_PREFIXES "${DEFAULT_OUTPUT_DIR}"
    append_unique_item DESKTOP_PREF_ALLOWED_PREFIXES "${HOME}/.local/state/dotfiles/desktop"

    for prefix in "${DELIB_SAFE_TEMP_PREFIXES[@]}"; do
        resolved_prefix="$(resolve_abs_path_safe "${prefix}" || true)"
        resolved_prefix="$(normalize_path_strict "${resolved_prefix}" || true)"
        [[ -n "${resolved_prefix}" && "${resolved_prefix}" == /* ]] || continue
        append_unique_item DESKTOP_PREF_ALLOWED_PREFIXES "${resolved_prefix}"
    done
}

resolve_and_validate_output_dir() {
    local resolved_output=""

    build_allowed_output_prefixes

    resolved_output="$(resolve_abs_path_safe "${OUTPUT_DIR}" || true)"
    resolved_output="$(normalize_path_strict "${resolved_output}" || true)"
    if [[ -z "${resolved_output}" || "${resolved_output}" != /* || "${resolved_output}" == "/" ]]; then
        err "Unable to resolve output directory safely: ${OUTPUT_DIR}"
        return 1
    fi

    resolved_output="$(validate_resolved_path_against_prefixes "${resolved_output}" DESKTOP_PREF_ALLOWED_PREFIXES "output directory" || true)"
    [[ -n "${resolved_output}" ]] || return 1

    assert_no_symlink_components "${resolved_output}" "output directory" || return 1
    OUTPUT_DIR="${resolved_output}"
}

join_items() {
    local joined=""
    local item=""

    for item in "$@"; do
        if [[ -n "${joined}" ]]; then
            joined+=" "
        fi
        joined+="${item}"
    done

    printf '%s' "${joined}"
}

load_available_schemas() {
    local schema=""

    delib_load_available_gsettings_schemas AVAILABLE_SCHEMA_SET || return 1

    for schema in "${TARGET_SCHEMAS[@]}"; do
        if delib_gsettings_schema_exists AVAILABLE_SCHEMA_SET "${schema}"; then
            AVAILABLE_TARGET_SCHEMAS+=("${schema}")
        else
            MISSING_TARGET_SCHEMAS+=("${schema}")
        fi
    done
}

collect_key_data() {
    local pair=""
    local schema=""
    local key=""
    local value=""
    local map_key=""

    for pair in "${TARGET_PAIRS[@]}"; do
        schema="${pair%%:*}"
        key="${pair#*:}"

        if ! delib_gsettings_schema_exists AVAILABLE_SCHEMA_SET "${schema}"; then
            SKIPPED_KEYS+=("${schema}/${key}:missing-schema")
            continue
        fi

        if ! delib_gsettings_schema_has_key SCHEMA_KEYS_CACHE "${schema}" "${key}"; then
            SKIPPED_KEYS+=("${schema}/${key}:missing-key")
            continue
        fi

        value="$(delib_gsettings_get "${schema}" "${key}")"
        map_key="${schema}|${key}"
        EXPORTED_VALUES["${map_key}"]="${value}"
        EXPORTED_KEYS+=("${schema}/${key}")
    done
}

render_keys_ini() {
    local pair=""
    local schema=""
    local key=""
    local map_key=""
    local current_schema=""

    printf '# Desktop preference export generated by scripts/desktop/capture.sh\n'
    printf '# Only targeted desktop preference keys are included.\n'
    printf '# Pre-import snapshot convention: %s/pre-import-keys.dconf.ini\n' "${OUTPUT_DIR}"
    printf '\n'

    for pair in "${TARGET_PAIRS[@]}"; do
        schema="${pair%%:*}"
        key="${pair#*:}"
        map_key="${schema}|${key}"

        if [[ -z "${EXPORTED_VALUES[${map_key}]+x}" ]]; then
            continue
        fi

        if [[ "${schema}" != "${current_schema}" ]]; then
            if [[ -n "${current_schema}" ]]; then
                printf '\n'
            fi
            printf '[%s]\n' "${schema}"
            current_schema="${schema}"
        fi

        printf '%s=%s\n' "${key}" "${EXPORTED_VALUES[${map_key}]}"
    done
}

render_metadata_env() {
    local available_summary=""
    local missing_summary=""
    local exported_summary=""
    local skipped_summary=""

    available_summary="$(join_items "${AVAILABLE_TARGET_SCHEMAS[@]}")"
    missing_summary="$(join_items "${MISSING_TARGET_SCHEMAS[@]}")"
    exported_summary="$(join_items "${EXPORTED_KEYS[@]}")"
    skipped_summary="$(join_items "${SKIPPED_KEYS[@]}")"

    printf '# Desktop preference metadata generated by scripts/desktop/capture.sh\n'
    printf '# This script does not read or write ~/.config/dconf/user\n'
    printf 'EXPORT_TIMESTAMP_UTC=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'DETECTED_XDG_CURRENT_DESKTOP=%q\n' "${XDG_CURRENT_DESKTOP:-unknown}"
    printf 'DETECTED_DESKTOP_SESSION=%q\n' "${DESKTOP_SESSION:-unknown}"
    printf 'DESKTOP_TARGET_USER=%q\n' "${DELIB_DESKTOP_TARGET_USER:-unknown}"
    printf 'DESKTOP_TARGET_UID=%q\n' "${DELIB_DESKTOP_TARGET_UID:-unknown}"
    printf 'DESKTOP_RUNTIME_DIR=%q\n' "${DELIB_DESKTOP_RUNTIME_DIR:-unknown}"
    printf 'AVAILABLE_TARGET_SCHEMAS=%q\n' "${available_summary}"
    printf 'MISSING_TARGET_SCHEMAS=%q\n' "${missing_summary}"
    printf 'EXPORTED_SCHEMA_KEYS=%q\n' "${exported_summary}"
    printf 'SKIPPED_SCHEMA_KEYS=%q\n' "${skipped_summary}"
    printf 'STRICT_MODE=%q\n' "${STRICT_MODE}"
    printf 'DRY_RUN=%q\n' "${DRY_RUN}"
    printf 'PRE_IMPORT_SNAPSHOT_PATH=%q\n' "${OUTPUT_DIR}/pre-import-keys.dconf.ini"
}

write_artifacts() {
    local keys_file="${OUTPUT_DIR}/keys.dconf.ini"
    local metadata_file="${OUTPUT_DIR}/metadata.env"
    local keys_content=""
    local metadata_content=""

    keys_content="$(render_keys_ini)"
    metadata_content="$(render_metadata_env)"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY-RUN: would create directory ${OUTPUT_DIR}"
        log "DRY-RUN: would write ${keys_file} and ${metadata_file}"
        return 0
    fi

    mkdir -p "${OUTPUT_DIR}"
    assert_no_symlink_components "${OUTPUT_DIR}" "output directory" || return 1

    write_text_file_atomic "${keys_file}" "${keys_content}" "keys manifest" || return 1
    write_text_file_atomic "${metadata_file}" "${metadata_content}" "metadata file" || return 1

    log "Wrote ${keys_file}"
    log "Wrote ${metadata_file}"
}

main() {
    parse_args "$@" || exit 1
    initialize_target_pairs_and_schemas || exit 1
    resolve_and_validate_output_dir || exit 1
    set_dry_run_mode "${DRY_RUN}"

    require_command gsettings || exit 1
    prepare_desktop_gsettings_context || exit 1
    log "Using desktop gsettings context user=${DELIB_DESKTOP_TARGET_USER} uid=${DELIB_DESKTOP_TARGET_UID}"

    load_available_schemas || exit 1
    collect_key_data
    write_artifacts

    log "Exported keys: ${#EXPORTED_KEYS[@]}"
    log "Skipped keys: ${#SKIPPED_KEYS[@]}"

    if [[ "${STRICT_MODE}" == "true" && "${#SKIPPED_KEYS[@]}" -gt 0 ]]; then
        err "Strict mode enabled and some targeted schema/key pairs were skipped"
        exit 1
    fi
}

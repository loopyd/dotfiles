#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="desktop-import"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

DEFAULT_INPUT_DIR_REL="root/home/user/.config/repro/desktop-preferences"
REPO_ROOT="$(resolve_abs_path_safe "${SCRIPT_DIR}/..")"
DEFAULT_INPUT_DIR="$(resolve_abs_path_safe "${REPO_ROOT}/${DEFAULT_INPUT_DIR_REL}")"

INPUT_DIR="${DEFAULT_INPUT_DIR}"
DRY_RUN="false"
STRICT_MODE="false"

declare -a ALLOWED_TARGET_PAIRS=()
declare -a DESKTOP_PREF_ALLOWED_PREFIXES=()
declare -A ALLOWED_PAIR_SET=()

# shellcheck disable=SC2034
declare -A AVAILABLE_SCHEMA_SET=()
# shellcheck disable=SC2034
declare -A SCHEMA_KEYS_CACHE=()

declare -a APPLIED_KEYS=()
declare -a PLANNED_KEYS=()
declare -a SKIPPED_KEYS=()
declare -a FAILED_KEYS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/import-desktop-preferences.sh [OPTIONS]

Imports deterministic desktop preference keys via gsettings from keys.dconf.ini.

Options:
  --dry-run            Preview actions without calling gsettings set.
  --strict             Fail on unsupported schema/key pairs.
  --input <dir>        Import directory (default: root/home/user/.config/repro/desktop-preferences)
  -h, --help           Show this help text.

Notes:
  - Required input file: <dir>/keys.dconf.ini
  - Report output file: <dir>/last-import-report.log
  - This script does not read or write ~/.config/dconf/user.
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
            --input)
                require_option_value "--input" "${2-}" || return 1
                INPUT_DIR="$2"
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

initialize_allowed_manifest_pairs() {
    local pair=""
    local schema=""
    local key=""

    delib_load_desktop_preference_target_pairs ALLOWED_TARGET_PAIRS || return 1
    ALLOWED_PAIR_SET=()

    for pair in "${ALLOWED_TARGET_PAIRS[@]}"; do
        schema="${pair%%:*}"
        key="${pair#*:}"
        ALLOWED_PAIR_SET["${schema}|${key}"]=1
    done
}

build_allowed_input_prefixes() {
    local prefix=""
    local resolved_prefix=""

    # shellcheck disable=SC2034
    DESKTOP_PREF_ALLOWED_PREFIXES=()
    append_unique_item DESKTOP_PREF_ALLOWED_PREFIXES "${DEFAULT_INPUT_DIR}"

    for prefix in "${DELIB_SAFE_TEMP_PREFIXES[@]}"; do
        resolved_prefix="$(resolve_abs_path_safe "${prefix}" || true)"
        resolved_prefix="$(normalize_path_strict "${resolved_prefix}" || true)"
        [[ -n "${resolved_prefix}" && "${resolved_prefix}" == /* ]] || continue
        append_unique_item DESKTOP_PREF_ALLOWED_PREFIXES "${resolved_prefix}"
    done
}

resolve_and_validate_input_dir() {
    local resolved_input=""

    build_allowed_input_prefixes

    resolved_input="$(resolve_abs_path_safe "${INPUT_DIR}" || true)"
    resolved_input="$(normalize_path_strict "${resolved_input}" || true)"
    if [[ -z "${resolved_input}" || "${resolved_input}" != /* || "${resolved_input}" == "/" ]]; then
        err "Unable to resolve input directory safely: ${INPUT_DIR}"
        return 1
    fi

    resolved_input="$(validate_resolved_path_against_prefixes "${resolved_input}" DESKTOP_PREF_ALLOWED_PREFIXES "input directory" || true)"
    [[ -n "${resolved_input}" ]] || return 1

    assert_no_symlink_components "${resolved_input}" "input directory" || return 1
    INPUT_DIR="${resolved_input}"
}

manifest_pair_allowed() {
    local schema="${1:-}"
    local key="${2:-}"
    [[ -n "${schema}" && -n "${key}" && -n "${ALLOWED_PAIR_SET[${schema}|${key}]+x}" ]]
}

trim_whitespace() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "${value}"
}

load_available_schemas() {
    delib_load_available_gsettings_schemas AVAILABLE_SCHEMA_SET
}

append_skipped() {
    local schema="${1:-}"
    local key="${2:-}"
    local reason="${3:-unsupported}"
    SKIPPED_KEYS+=("${schema}/${key}:${reason}")
}

append_failed() {
    local schema="${1:-}"
    local key="${2:-}"
    local reason="${3:-failed}"
    FAILED_KEYS+=("${schema}/${key}:${reason}")
}

apply_preference() {
    local schema="${1:-}"
    local key="${2:-}"
    local value="${3:-}"
    local readback=""

    if ! delib_gsettings_schema_exists AVAILABLE_SCHEMA_SET "${schema}"; then
        append_skipped "${schema}" "${key}" "missing-schema"
        log_warn "Skipping unsupported schema: ${schema}"
        return 2
    fi

    if ! delib_gsettings_schema_has_key SCHEMA_KEYS_CACHE "${schema}" "${key}"; then
        append_skipped "${schema}" "${key}" "missing-key"
        log_warn "Skipping unsupported key: ${schema}/${key}"
        return 2
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        PLANNED_KEYS+=("${schema}/${key}")
        log "DRY-RUN: gsettings set ${schema} ${key} ${value}"
        return 0
    fi

    if ! delib_gsettings_set "${schema}" "${key}" "${value}"; then
        append_failed "${schema}" "${key}" "set-failed"
        err "Failed to set ${schema}/${key}"
        return 1
    fi

    readback="$(delib_gsettings_get "${schema}" "${key}")"
    if [[ "${readback}" != "${value}" ]]; then
        append_failed "${schema}" "${key}" "verify-mismatch"
        err "Verification mismatch for ${schema}/${key}: expected '${value}' got '${readback}'"
        return 1
    fi

    APPLIED_KEYS+=("${schema}/${key}")
    log "Applied ${schema}/${key}"
    return 0
}

process_manifest() {
    local manifest_path="${INPUT_DIR}/keys.dconf.ini"
    local line=""
    local current_schema=""
    local key=""
    local value=""
    local status=0
    local rc=0

    assert_no_symlink_components "${manifest_path}" "keys manifest path" || return 1
    if [[ -L "${manifest_path}" ]]; then
        err "Refusing to read symlinked keys manifest: ${manifest_path}"
        return 1
    fi

    require_file_exists "${manifest_path}" "keys manifest" || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"

        if [[ -z "${line}" || "${line}" == \#* || "${line}" == \;* ]]; then
            continue
        fi

        if [[ "${line}" == \[*\] ]]; then
            current_schema="${line#[}"
            current_schema="${current_schema%]}"
            current_schema="$(trim_whitespace "${current_schema}")"
            continue
        fi

        if [[ "${line}" != *=* ]]; then
            log_warn "Ignoring malformed line: ${line}"
            continue
        fi

        if [[ -z "${current_schema}" ]]; then
            log_warn "Ignoring key outside schema section: ${line}"
            continue
        fi

        key="${line%%=*}"
        value="${line#*=}"
        key="$(trim_whitespace "${key}")"

        if [[ -z "${key}" ]]; then
            log_warn "Ignoring line with empty key in schema ${current_schema}"
            continue
        fi

        if ! manifest_pair_allowed "${current_schema}" "${key}"; then
            append_skipped "${current_schema}" "${key}" "disallowed-entry"
            log_warn "Skipping disallowed manifest entry: ${current_schema}/${key}"
            if [[ "${STRICT_MODE}" == "true" ]]; then
                status=1
            fi
            continue
        fi

        if apply_preference "${current_schema}" "${key}" "${value}"; then
            :
        else
            rc=$?
            if [[ "${rc}" -eq 2 ]]; then
                if [[ "${STRICT_MODE}" == "true" ]]; then
                    status=1
                fi
            else
                status=1
            fi
        fi
    done < "${manifest_path}"

    return "${status}"
}

write_report() {
    local report_path="${INPUT_DIR}/last-import-report.log"
    local report_content=""
    local item=""

    report_content="$({
        printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'input_dir=%s\n' "${INPUT_DIR}"
        printf 'manifest_path=%s\n' "${INPUT_DIR}/keys.dconf.ini"
        printf 'desktop_target_user=%s\n' "${DELIB_DESKTOP_TARGET_USER:-unknown}"
        printf 'desktop_target_uid=%s\n' "${DELIB_DESKTOP_TARGET_UID:-unknown}"
        printf 'desktop_runtime_dir=%s\n' "${DELIB_DESKTOP_RUNTIME_DIR:-unknown}"
        printf 'dry_run=%s\n' "${DRY_RUN}"
        printf 'strict_mode=%s\n' "${STRICT_MODE}"
        printf 'applied_count=%s\n' "${#APPLIED_KEYS[@]}"
        printf 'planned_count=%s\n' "${#PLANNED_KEYS[@]}"
        printf 'skipped_count=%s\n' "${#SKIPPED_KEYS[@]}"
        printf 'failed_count=%s\n' "${#FAILED_KEYS[@]}"
        printf '\n'

        printf '[applied]\n'
        for item in "${APPLIED_KEYS[@]}"; do
            printf '%s\n' "${item}"
        done
        printf '\n'

        printf '[planned]\n'
        for item in "${PLANNED_KEYS[@]}"; do
            printf '%s\n' "${item}"
        done
        printf '\n'

        printf '[skipped]\n'
        for item in "${SKIPPED_KEYS[@]}"; do
            printf '%s\n' "${item}"
        done
        printf '\n'

        printf '[failed]\n'
        for item in "${FAILED_KEYS[@]}"; do
            printf '%s\n' "${item}"
        done
    })"

    mkdir -p "${INPUT_DIR}"
    assert_no_symlink_components "${INPUT_DIR}" "input directory" || return 1
    write_text_file_atomic "${report_path}" "${report_content}" "import report" || return 1

    log "Wrote ${report_path}"
}

main() {
    local status=0

    parse_args "$@" || exit 1
    initialize_allowed_manifest_pairs || exit 1
    resolve_and_validate_input_dir || exit 1
    set_dry_run_mode "${DRY_RUN}"

    require_command gsettings || exit 1
    prepare_desktop_gsettings_context || exit 1
    log "Using desktop gsettings context user=${DELIB_DESKTOP_TARGET_USER} uid=${DELIB_DESKTOP_TARGET_UID}"

    load_available_schemas || exit 1

    if ! process_manifest; then
        status=1
    fi

    write_report

    if [[ "${STRICT_MODE}" == "true" && "${#SKIPPED_KEYS[@]}" -gt 0 ]]; then
        err "Strict mode enabled and unsupported schema/key pairs were found"
        status=1
    fi

    if [[ "${#FAILED_KEYS[@]}" -gt 0 ]]; then
        status=1
    fi

    exit "${status}"
}

main "$@"
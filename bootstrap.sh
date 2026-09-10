#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
export INSTALL_LIB_TAG=bootstrap
source "${SCRIPTS_DIR}/delib.sh"

ACTION=""
PROFILE=default
DRY_RUN=false
ONLY=""
WITH_GPU=""
WITH_APPS=""
WITH_OLLAMA=""
WITH_GIT_HOOKS=true
WITH_8BITDO=false
WITH_DOTFILES=false
WITH_HINDSIGHT=false
WITH_EASYLLAMA=false
WITH_USER_TOOLS=false
WITH_TERMINALS=false
WITH_DESKTOP=false
WITH_NETWORK=false
DESKTOP_BACKUP=""
DOTFILES_VALUES="${HOME}/.config/dotfiles/values.json"
COMPONENTS=()

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh <install|update|uninstall|check> [options]

  --only <names>       Comma-separated component nouns; required for uninstall
  --profile <name>     default or minimal (core, gh, hooks, neovim)
  --dry-run            Preview order without executing component commands
  --no-gpu             Skip Docker/NVIDIA unless the selected local AI stack needs them
  --no-apps            Skip Blender/Ghidra/REAPER
  --no-ollama          Skip Ollama
  --no-git-hooks       Skip repository hooks
  --with-8bitdo        Include controller support
  --with-dotfiles      Render configuration before user software
  --with-user-tools    Include mise-managed runtimes and user packages
  --with-hindsight     Include Hindsight (Docker prerequisite)
  --with-easyllama     Include the pinned local Qwen Docker stack
  --with-terminals     Include Alacritty and herdr
  --with-desktop       Include selected desktop preferences
  --with-network       Include native Tailscale exposure and 9router Compose
  --desktop-backup <path>  Explicit pre-install settings snapshot for removal
  --dotfiles-values <path>  Private renderer values outside the repository

Names: core, gh, docker, nvidia, hooks, neovim, ghidra, blender, reaper,
ollama, 8bitdo, dotfiles, desktop, mise, tools, alacritty, herdr, tailscale, easyllama, router, hindsight.
Install/update follow dependency order; uninstall verifies receipts first
and reverses that order. Check never installs prerequisites.
EOF
}

parse_args() {
    ACTION="${1:-}"
    case "${ACTION}" in
        install|update|uninstall|check) shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --profile|--only|--dotfiles-values|--desktop-backup)
                require_option_value "$1" "${2-}"
                case "$1" in
                    --profile) PROFILE="$2" ;;
                    --only) ONLY="$2" ;;
                    --dotfiles-values) DOTFILES_VALUES="$2" ;;
                    --desktop-backup) DESKTOP_BACKUP="$2" ;;
                esac
                shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --no-gpu) WITH_GPU=false; shift ;;
            --no-apps) WITH_APPS=false; shift ;;
            --no-ollama) WITH_OLLAMA=false; shift ;;
            --no-git-hooks) WITH_GIT_HOOKS=false; shift ;;
            --with-8bitdo) WITH_8BITDO=true; shift ;;
            --with-dotfiles) WITH_DOTFILES=true; shift ;;
            --with-hindsight) WITH_HINDSIGHT=true; shift ;;
            --with-easyllama) WITH_EASYLLAMA=true; shift ;;
            --with-user-tools) WITH_USER_TOOLS=true; shift ;;
            --with-terminals) WITH_TERMINALS=true; shift ;;
            --with-desktop) WITH_DESKTOP=true; shift ;;
            --with-network) WITH_NETWORK=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; return 2 ;;
        esac
    done
    [[ "${PROFILE}" == default || "${PROFILE}" == minimal ]] || { err 'Unknown profile'; return 2; }
    [[ "${ACTION}" != uninstall || -n "${ONLY}" ]] || { err 'Uninstall requires --only; no implicit full-system removal'; return 2; }
}

select_components() {
    local component defaults=false
    local -A selected=()
    local -a requested=()
    if [[ -n "${ONLY}" ]]; then
        [[ "${ONLY}" =~ ^[a-z0-9-]+(,[a-z0-9-]+)*$ ]] || { err 'Invalid component list'; return 2; }
        IFS=, read -r -a requested <<< "${ONLY}"
    else
        [[ "${PROFILE}" != default ]] || defaults=true
        requested=(core gh neovim)
        [[ "${WITH_GIT_HOOKS}" != true ]] || requested+=(hooks)
        [[ "${WITH_GPU:-${defaults}}" != true ]] || requested+=(docker nvidia)
        [[ "${WITH_APPS:-${defaults}}" != true ]] || requested+=(ghidra blender reaper)
        [[ "${WITH_OLLAMA:-${defaults}}" != true ]] || requested+=(ollama)
        [[ "${WITH_8BITDO}" != true ]] || requested+=(8bitdo)
        [[ "${WITH_DOTFILES}" != true ]] || requested+=(dotfiles)
        [[ "${WITH_USER_TOOLS}" != true ]] || requested+=(tools)
        [[ "${WITH_HINDSIGHT}" != true ]] || requested+=(hindsight)
        [[ "${WITH_EASYLLAMA}" != true ]] || requested+=(easyllama)
        [[ "${WITH_TERMINALS}" != true ]] || requested+=(alacritty herdr)
        [[ "${WITH_DESKTOP}" != true ]] || requested+=(desktop)
        [[ "${WITH_NETWORK}" != true ]] || requested+=(tailscale router)
    fi
    for component in "${requested[@]}"; do
        case "${component}" in
            core|gh|docker|nvidia|hooks|neovim|ghidra|blender|reaper|ollama|8bitdo|dotfiles|desktop|mise|tools|alacritty|herdr|tailscale|easyllama|router|hindsight) selected["${component}"]=true ;;
            *) err "Unknown component: ${component}"; return 2 ;;
        esac
    done
    if [[ "${ACTION}" == install || "${ACTION}" == update ]]; then
        if [[ -n "${selected[hindsight]:-}" ]]; then selected[router]=true; fi
        if [[ -n "${selected[router]:-}" ]]; then selected[easyllama]=true; fi
        if [[ -n "${selected[easyllama]:-}" ]]; then selected[docker]=true; selected[nvidia]=true; fi
        if [[ -n "${selected[hindsight]:-}${selected[nvidia]:-}${selected[router]:-}" ]]; then selected[docker]=true; fi
        if [[ -n "${selected[router]:-}" ]]; then selected[tailscale]=true; fi
    fi
    if [[ "${ACTION}" == uninstall && -n "${selected[desktop]:-}" && -z "${DESKTOP_BACKUP}" ]]; then
        err 'Desktop removal requires --desktop-backup'; return 2
    fi
    for component in core gh docker nvidia hooks neovim ghidra blender reaper ollama 8bitdo dotfiles desktop mise tools alacritty herdr tailscale easyllama router hindsight; do
        [[ -z "${selected[${component}]:-}" ]] || COMPONENTS+=("${component}")
    done
}

run_component() {
    local component="$1" action="$2"
    shift 2
    if [[ "${component}" == dotfiles ]]; then
        run_maybe_dry python3 "${SCRIPTS_DIR}/dotfiles.py" "${action}" --values "${DOTFILES_VALUES}"
    elif [[ "${component}" == desktop && "${action}" == uninstall ]]; then
        local -a options=(--input "${DESKTOP_BACKUP}")
        [[ "${1:-}" != --verify ]] || options+=(--dry-run)
        run_maybe_dry bash "${SCRIPTS_DIR}/desktop.sh" uninstall "${options[@]}"
    else
        run_maybe_dry bash "${SCRIPTS_DIR}/${component}.sh" "${action}" "$@"
    fi
}

main() {
    parse_args "$@"
    select_components
    set_dry_run_mode "${DRY_RUN}"
    local component index
    if [[ "${ACTION}" == uninstall ]]; then
        for component in "${COMPONENTS[@]}"; do
            [[ "${component}" == dotfiles ]] || run_component "${component}" uninstall --verify
        done
        for ((index=${#COMPONENTS[@]}-1; index>=0; index--)); do
            run_component "${COMPONENTS[index]}" uninstall
        done
    else
        for component in "${COMPONENTS[@]}"; do
            run_component "${component}" "${ACTION}"
            if [[ "${component}" == tools || "${component}" == mise ]]; then
                export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.local/share/mise/shims:${PATH}"
            fi
        done
    fi
    log "${ACTION} completed for: ${COMPONENTS[*]}"
}

main "$@"

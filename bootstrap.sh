#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
export INSTALL_LIB_TAG="bootstrap"
# shellcheck source=./scripts/delib.sh
source "${SCRIPTS_DIR}/delib.sh"

PROFILE="default"
DRY_RUN="false"

WITH_GPU="true"
WITH_8BITDO="false"
WITH_APPS="true"
WITH_OLLAMA="true"
WITH_GIT_HOOKS="true"
WITH_DOTFILES="false"
DOTFILES_VALUES="${HOME}/.config/dotfiles/values.json"

OVERRIDE_GPU=""
OVERRIDE_8BITDO=""
OVERRIDE_APPS=""
OVERRIDE_OLLAMA=""
OVERRIDE_GIT_HOOKS=""

usage() {
	cat <<'EOF'
Usage: ./bootstrap.sh [options]

Options:
	--profile <default|minimal>  Execution profile (default: default)
  --dry-run          Print actions without running them
  --no-gpu           Skip Docker + NVIDIA toolkit installers
  --with-8bitdo      Run optional 8BitDo setup
  --no-apps          Skip Blender/Ghidra/REAPER installers
  --no-ollama        Skip Ollama installer
  --no-git-hooks     Skip repository hook installation
  --with-dotfiles    Render user configuration after installers
  --dotfiles-values <path>  Private JSON values outside the repository
  -h, --help         Show this help
EOF
}

run_installer() {
	local script_name="${1}"
	shift
	local script_path="${SCRIPTS_DIR}/${script_name}"
	run_script_maybe_dry "${script_path}" "$@"
}

apply_profile_defaults() {
	case "${PROFILE}" in
		default)
			WITH_GPU="true"
			WITH_8BITDO="false"
			WITH_APPS="true"
			WITH_OLLAMA="true"
			WITH_GIT_HOOKS="true"
			;;
		minimal)
			WITH_GPU="false"
			WITH_8BITDO="false"
			WITH_APPS="false"
			WITH_OLLAMA="false"
			WITH_GIT_HOOKS="true"
			;;
		*)
			err "Unknown profile: ${PROFILE}"
			usage
			exit 1
			;;
	esac
}

apply_flag_overrides() {
	if [[ -n "${OVERRIDE_GPU}" ]]; then
		WITH_GPU="${OVERRIDE_GPU}"
	fi
	if [[ -n "${OVERRIDE_8BITDO}" ]]; then
		WITH_8BITDO="${OVERRIDE_8BITDO}"
	fi
	if [[ -n "${OVERRIDE_APPS}" ]]; then
		WITH_APPS="${OVERRIDE_APPS}"
	fi
	if [[ -n "${OVERRIDE_OLLAMA}" ]]; then
		WITH_OLLAMA="${OVERRIDE_OLLAMA}"
	fi
	if [[ -n "${OVERRIDE_GIT_HOOKS}" ]]; then
		WITH_GIT_HOOKS="${OVERRIDE_GIT_HOOKS}"
	fi
}

phase_0_preflight() {
	log 'Phase 0: preflight checks'
	require_command bash || {
		err 'bash is required'
		exit 1
	}
	require_command uname || {
		err 'uname is required'
		exit 1
	}
	require_command apt-get || {
		err 'apt-get is required (Debian/Ubuntu family expected)'
		exit 1
	}
	if [[ ! -r /etc/os-release ]]; then
		err '/etc/os-release is required for distro detection'
		exit 1
	fi
	if [[ "${EUID}" -ne 0 ]] && [[ "${DRY_RUN}" != "true" ]] && ! command -v sudo >/dev/null 2>&1; then
		err 'sudo is required for non-root execution'
		exit 1
	fi

	local arch distro codename
	arch="$(uname -m)"
	distro="$(. /etc/os-release && echo "${ID}:${VERSION_ID}")"
	codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}")"
	log "Host detected: ${distro} codename=${codename} (${arch})"
	if [[ "${PROFILE}" == "minimal" ]]; then
		log 'Using minimal profile'
	else
		log 'Using default profile'
	fi
}

phase_1_base_prereqs() {
	log 'Phase 1: base prerequisites'
	run_installer install-core-cli.sh
}

phase_2_repo_keyring_setup() {
	log 'Phase 2: repository and keyring capable installers'
	run_installer install-gh-cli.sh
	if [[ "${WITH_GPU}" == "true" ]]; then
		run_installer install-docker-engine.sh
		run_installer install-nvidia-container-toolkit.sh
	else
		log 'Skipping Docker + NVIDIA toolkit by configuration'
	fi
}

phase_3_core_tools() {
	log 'Phase 3: core tool installation'
	if [[ "${WITH_GIT_HOOKS}" == "true" ]]; then
		run_installer install-git-hooks.sh
	else
		log 'Skipping git hooks by configuration'
	fi

	run_installer install-neovim-latest.sh
}

phase_4_specialized_installers() {
	log 'Phase 4: specialized installer delegation'

	if [[ "${WITH_APPS}" == "true" ]]; then
		run_installer install-gidra.sh install
		run_installer install-blender.sh
		run_installer install-reaper.sh
	else
		log 'Skipping Blender/Ghidra/REAPER by configuration'
	fi

	if [[ "${WITH_OLLAMA}" == "true" ]]; then
		run_installer install-ollama.sh --mode script
	else
		log 'Skipping Ollama by configuration'
	fi

	if [[ "${WITH_8BITDO}" == "true" ]]; then
		run_installer 8bitdo.sh
	else
		log 'Skipping 8BitDo setup by configuration'
	fi
}

phase_5_validation() {
	log 'Phase 5: validation'
	if [[ "${DRY_RUN}" == "true" ]]; then
		log 'Dry-run mode enabled; skipping runtime validation checks'
		return 0
	fi

	local -a checks=(
		gh
		nvim
	)
	if [[ "${WITH_OLLAMA}" == "true" ]]; then
		checks+=(ollama)
	fi
	if [[ "${WITH_GPU}" == "true" ]]; then
		checks+=(docker nvidia-ctk)
	fi
	local tool
	for tool in "${checks[@]}"; do
		if command -v "${tool}" >/dev/null 2>&1; then
			log "Validation passed: ${tool} is installed"
		else
			err "Validation failed: ${tool} is missing"
			exit 1
		fi
	done

	if [[ "${WITH_OLLAMA}" == "true" ]] && command -v systemctl >/dev/null 2>&1; then
		if systemctl is-enabled ollama >/dev/null 2>&1; then
			log 'Validation passed: ollama service is enabled'
		else
			err 'Validation warning: ollama service is not enabled'
		fi
	fi
}

phase_dotfiles() {
	if [[ "${WITH_DOTFILES}" == "true" ]]; then
		run_maybe_dry python3 "${SCRIPTS_DIR}/setup-dotfiles.py" --values "${DOTFILES_VALUES}" --apply
	fi
}

parse_args() {
	while [[ "$#" -gt 0 ]]; do
		if is_help_token "$1"; then
			usage
			exit 0
		fi

		case "$1" in
			--profile)
				require_option_value "$1" "${2-}" || exit 1
				PROFILE="${2}"
				shift 2
				;;
			--dry-run)
				DRY_RUN="true"
				shift
				;;
			--no-gpu)
				OVERRIDE_GPU="false"
				shift
				;;
			--with-8bitdo)
				OVERRIDE_8BITDO="true"
				shift
				;;
			--no-apps)
				OVERRIDE_APPS="false"
				shift
				;;
			--no-ollama)
				OVERRIDE_OLLAMA="false"
				shift
				;;
			--no-git-hooks)
				OVERRIDE_GIT_HOOKS="false"
				shift
				;;
			--with-dotfiles)
				WITH_DOTFILES="true"
				shift
				;;
			--dotfiles-values)
				require_option_value "$1" "${2-}" || exit 1
				DOTFILES_VALUES="$2"
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

main() {
	parse_args "$@"
	apply_profile_defaults
	apply_flag_overrides
	set_dry_run_mode "${DRY_RUN}"
	phase_0_preflight
	phase_1_base_prereqs
	phase_2_repo_keyring_setup
	phase_3_core_tools
	phase_4_specialized_installers
	phase_dotfiles
	phase_5_validation
	log 'Bootstrap completed'
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="alacritty"
source "${SCRIPT_DIR}/delib.sh"
REVISION=f99dc71708d31d5c32d4b3fa611f9a87bf22657e
FONT_SHA256=f099f71bc240fb59ffeaba50d26206b32df7e54051e49d6837a1702e4d3b4f3f
DRY_RUN=false
DEPS=true
BUILD_DIR=""

usage() {
    printf '%s\n' 'Usage: ./scripts/alacritty.sh <install|update|uninstall|check> [--dry-run] [--no-deps] ' \
        'Build the captured Alacritty revision into ~/.local/bin; install font and terminal integration.' \
        'Render configuration first. Rust/Cargo are prerequisites; apt build dependencies are optional.'
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --no-deps) DEPS=false ;;
            -h|--help) usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done
}

cleanup() {
    cleanup_paths_if_present "${BUILD_DIR}"
}

main() {
    parse_args "$@"
    set_dry_run_mode "${DRY_RUN}"
    [[ "$(uname -s)" == Linux ]] || { err 'Linux is required'; return 1; }
    if [[ "${DRY_RUN}" != true ]]; then
        [[ "${EUID}" -ne 0 ]] || { err 'Run as the destination user, not root'; return 1; }
        require_commands python3
    fi
    run_maybe_dry python3 "${SCRIPT_DIR}/terminal.py" check-alacritty
    if [[ "${DEPS}" == true ]]; then
        if [[ "${DRY_RUN}" != true ]]; then
            require_apt_environment
        fi
        run_maybe_dry apt_install_missing cmake g++ pkg-config libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3 libegl1-mesa-dev ncurses-bin fontconfig scdoc gzip desktop-file-utils git curl xz-utils
    fi
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY-RUN: fetch official Alacritty commit ${REVISION}; cargo build --release --locked in a private temporary checkout"
        log 'DRY-RUN: install ~/.local/bin/alacritty, user terminfo/icon/manuals/completions and verified DepartureMono Nerd Font 3.4.0'
        log 'DRY-RUN: preserve rendered desktop launcher, theme, font size, shell and keybindings; do not open a terminal'
        return
    fi
    require_commands cargo git curl tar install tic fc-cache sha256sum awk scdoc gzip mktemp update-desktop-database
    trap cleanup EXIT
    mktemp_dir_var BUILD_DIR '/tmp/alacritty-build.XXXXXX'
    git init --quiet "${BUILD_DIR}/source"
    git -C "${BUILD_DIR}/source" config core.abbrev 8
    git -C "${BUILD_DIR}/source" remote add origin https://github.com/alacritty/alacritty.git
    git -C "${BUILD_DIR}/source" fetch --quiet --depth 1 origin "${REVISION}"
    git -C "${BUILD_DIR}/source" checkout --quiet --detach FETCH_HEAD
    [[ "$(git -C "${BUILD_DIR}/source" rev-parse HEAD)" == "${REVISION}" ]] || { err 'Source revision mismatch'; return 1; }
    local binary="${BUILD_DIR}/target/release/alacritty" target="${HOME}/.local/bin/alacritty"
    [[ ! -L "${target}" ]] || { err 'Existing Alacritty symlink needs manual review'; return 1; }
    CARGO_TARGET_DIR="${BUILD_DIR}/target" cargo build --manifest-path "${BUILD_DIR}/source/Cargo.toml" --package alacritty --release --locked
    [[ "$("${binary}" --version)" == "alacritty 0.18.0-dev (${REVISION:0:8})" ]] || { err 'Built Alacritty version does not match the captured development revision'; return 1; }
    install -Dm0755 "${binary}" "${target}"
    tic -x -e alacritty,alacritty-direct -o "${HOME}/.terminfo" "${BUILD_DIR}/source/extra/alacritty.info"
    install -Dm0644 "${BUILD_DIR}/source/extra/logo/alacritty-term.svg" "${HOME}/.local/share/icons/hicolor/scalable/apps/Alacritty.svg"
    install -Dm0644 "${BUILD_DIR}/source/extra/completions/alacritty.bash" "${HOME}/.local/share/bash-completion/completions/alacritty"
    install -Dm0644 "${BUILD_DIR}/source/extra/completions/alacritty.fish" "${HOME}/.config/fish/completions/alacritty.fish"
    install -Dm0644 "${BUILD_DIR}/source/extra/completions/_alacritty" "${HOME}/.zsh_functions/_alacritty"
    local manual name section
    for manual in "${BUILD_DIR}/source/extra/man/"*.scd; do
        name="$(basename "${manual}" .scd)"
        section="${name##*.}"
        mkdir -p "${HOME}/.local/share/man/man${section}"
        scdoc < "${manual}" | gzip -c > "${HOME}/.local/share/man/man${section}/${name}.gz"
    done
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/DepartureMono.tar.xz -o "${BUILD_DIR}/font.tar.xz"
    verify_file_sha256 "${BUILD_DIR}/font.tar.xz" "${FONT_SHA256}" 'DepartureMono font'
    local font destination="${HOME}/.local/share/fonts/DepartureMono"
    mkdir -p "${destination}"
    for font in DepartureMonoNerdFont-Regular.otf DepartureMonoNerdFontMono-Regular.otf DepartureMonoNerdFontPropo-Regular.otf LICENSE; do
        tar -xJOf "${BUILD_DIR}/font.tar.xz" "${font}" > "${destination}/${font}"
    done
    fc-cache -f "${destination}"
    update-desktop-database "${HOME}/.local/share/applications"
    "${target}" --version
    log 'Installed user terminal integration; no terminal or agent session launched'
}

lifecycle_dispatch alacritty "$@"

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG="8bitdo"
# shellcheck source=scripts/delib.sh
source "${SCRIPT_DIR}/delib.sh"

ENABLE_SYSTEMD_SERVICE="true"
INSTALL_JSTEST="true"

BLACKLIST_PATH="/etc/modprobe.d/notendo.conf"
UDEV_RULES_PATH="/etc/udev/rules.d/99-8bitdo-ultimate.rules"
SERVICE_PATH="/etc/systemd/system/8bitdo-ultimate-xinput@.service"

usage() {
    cat <<'EOF'
Usage: ./scripts/8bitdo.sh <install|update|uninstall|check> [options]

Options:
  --skip-systemd-service   Skip systemd service creation/wiring
  --skip-jstest            Skip installing jstest-gtk
  -h, --help               Show help
EOF
}

parse_args() {
    while [[ "$#" -gt 0 ]]; do
        if is_help_token "$1"; then
            usage
            exit 0
        fi

        case "$1" in
            --skip-systemd-service)
                ENABLE_SYSTEMD_SERVICE="false"
                shift
                ;;
            --skip-jstest)
                INSTALL_JSTEST="false"
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

install_deps() {
    require_apt_environment
    apt_install_missing xboxdrv

    if [[ "${INSTALL_JSTEST}" == "true" ]]; then
        apt_install_missing jstest-gtk
    else
        log "Skipping jstest-gtk install by configuration"
    fi
}

configure_blacklist() {
    safe_sudo tee "${BLACKLIST_PATH}" >/dev/null <<'EOF'
blacklist hid_nintendo
EOF
}

configure_udev_rules() {
    local start_action stop_action

    if [[ "${ENABLE_SYSTEMD_SERVICE}" == "true" ]]; then
        start_action="/bin/systemctl start 8bitdo-ultimate-xinput@2dc8:3106"
        stop_action="/bin/systemctl stop 8bitdo-ultimate-xinput@2dc8:3106"
    else
        start_action="/usr/bin/true"
        stop_action="/usr/bin/true"
    fi

    safe_sudo mkdir -p "$(dirname "${UDEV_RULES_PATH}")"
    safe_sudo tee "${UDEV_RULES_PATH}" >/dev/null <<EOF
SUBSYSTEM=="usb", ACTION=="add", ATTR{idVendor}=="2dc8", ATTR{idProduct}=="3106", ATTR{manufacturer}=="8BitDo", RUN+="${start_action}"
SUBSYSTEM=="usb", ACTION=="add", ATTR{idVendor}=="2dc8", ATTR{idProduct}=="3109", ATTR{manufacturer}=="8BitDo", RUN+="${stop_action}"
EOF

    reload_udev_rules_if_available
}

configure_systemd_service() {
    if [[ "${ENABLE_SYSTEMD_SERVICE}" != "true" ]]; then
        log "Systemd service setup skipped by configuration"
        return 0
    fi
    if ! has_systemctl; then
        log "systemctl not available; skipping service setup"
        return 0
    fi

    safe_sudo tee "${SERVICE_PATH}" >/dev/null <<'EOF'
[Unit]
Description=8BitDo Ultimate Controller XInput mode xboxdrv daemon

[Service]
Type=simple
ExecStart=/usr/bin/xboxdrv --mimic-xpad --silent --type xbox360 --device-by-id %i --force-feedback --detach-kernel-driver
EOF

    systemd_daemon_reload_if_available
}

main() {
    parse_args "$@"

    if [[ "${ENABLE_SYSTEMD_SERVICE}" == "true" ]] && ! has_systemctl; then
        log "systemctl unavailable; forcing --skip-systemd-service behavior"
        ENABLE_SYSTEMD_SERVICE="false"
    fi

    install_deps
    configure_blacklist
    configure_systemd_service
    configure_udev_rules
    log "Completed"
}

lifecycle_dispatch 8bitdo "$@"

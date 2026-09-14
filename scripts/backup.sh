#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_LIB_TAG=backup
source "${SCRIPT_DIR}/delib.sh"
CONFIG="${HOME}/.config/dotfiles/nas-backup.json"
TEMP_DIR=""

usage() {
    printf '%s\n' 'Usage: backup.sh <install|update|uninstall|check> [--dry-run]' \
        'Installs CIFS/rsync support, manages the NAS hosts/fstab entries, and enables the daily user timer.'
}

parse_args() {
    [[ "$#" -eq 0 ]] || { err "Unknown option: $1"; return 2; }
}

config_value() {
    python3 - "$CONFIG" "$1" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))[sys.argv[2]]
if not isinstance(value, str) or "\n" in value or "\0" in value:
    raise SystemExit("Invalid backup configuration value")
print(value)
PY
}

render_system_files() {
    local remove="${1:-false}"
    TEMP_DIR="$(mktemp -d /tmp/dotfiles-nas-backup.XXXXXX)"
    local -a options=(render --config "$CONFIG" --output "$TEMP_DIR")
    [[ "$remove" != true ]] || options+=(--remove)
    python3 "${SCRIPT_DIR}/nas_backup.py" "${options[@]}"
    safe_sudo install -m 0644 "$TEMP_DIR/hosts" /etc/hosts
    safe_sudo install -m 0644 "$TEMP_DIR/fstab" /etc/fstab
    rm -rf -- "$TEMP_DIR"
    TEMP_DIR=""
    safe_sudo systemctl daemon-reload
}

activate_mount() {
    local mount_point expected_source actual_source options
    mount_point="$(config_value mount_point)"
    expected_source="//$(config_value hostname)/$(config_value share)"
    safe_sudo install -d -m 0755 "$mount_point"
    if mountpoint -q "$mount_point"; then
        actual_source="$(findmnt -rn -M "$mount_point" -o SOURCE)"
        [[ "${actual_source,,}" == "${expected_source,,}" ]] || { err "$mount_point is mounted from unexpected source: $actual_source"; return 1; }
        options=",$(findmnt -rn -M "$mount_point" -o OPTIONS),"
        if [[ "$options" != *,rw,* || "$options" != *,nosuid,* || "$options" != *,nodev,* || "$options" != *,noexec,* || "$options" != *,file_mode=0600,* || "$options" != *,dir_mode=0700,* ]]; then
            safe_sudo umount "$mount_point"
            safe_sudo mount "$mount_point"
        fi
    else
        safe_sudo mount "$mount_point"
    fi
    findmnt -rn -M "$mount_point" -t cifs -O rw >/dev/null || { err 'Configured CIFS mount is not writable'; return 1; }
}

check_backup() {
    local mount_point
    mount_point="$(config_value mount_point)"
    python3 "${SCRIPT_DIR}/nas_backup.py" check --config "$CONFIG"
    findmnt -rn -M "$mount_point" -t cifs -O rw >/dev/null || { err 'Configured CIFS mount is not writable'; return 1; }
    systemctl --user is-enabled --quiet nas-backup.timer
}

deactivate_backup() {
    local mount_point
    mount_point="$(config_value mount_point)"
    systemctl --user disable --now nas-backup.timer
    if mountpoint -q "$mount_point"; then
        safe_sudo umount "$mount_point"
    fi
    render_system_files true
}

main() {
    parse_args "$@"
    [[ "${EUID}" -ne 0 ]] || { err 'Run as the logged-in destination user'; return 1; }
    require_commands python3 systemctl mount mountpoint findmnt mktemp install
    [[ -f "$CONFIG" && ! -L "$CONFIG" ]] || { err "Render private dotfiles first: missing $CONFIG"; return 1; }
    apt_install_missing cifs-utils smbclient rsync unzip
    trap '[[ -z "$TEMP_DIR" ]] || rm -rf -- "$TEMP_DIR"' EXIT
    render_system_files false
    activate_mount
    systemctl --user daemon-reload
    systemctl --user enable --now nas-backup.timer
    log 'NAS mount configured; daily backup timer enabled'
}

lifecycle_dispatch backup "$@"

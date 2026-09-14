#!/usr/bin/env python3
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re


BEGIN = "# BEGIN dotfiles nas-backup"
END = "# END dotfiles nas-backup"
HOSTNAME = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_config(path):
    require(path.is_file() and not path.is_symlink(), "Backup configuration must be a regular file")
    data = json.loads(path.read_text())
    names = (
        "hostname", "ip", "share", "mount_point", "credentials_file",
        "backup_directory", "retention_days", "compose_file",
    )
    require(all(isinstance(data.get(name), str) for name in names), "Backup configuration is incomplete")
    require(HOSTNAME.fullmatch(data["hostname"]), "Invalid NAS hostname")
    ipaddress.ip_address(data["ip"])
    require(data["share"] and "/" not in data["share"] and "\\" not in data["share"], "Invalid NAS share")
    mount = Path(data["mount_point"])
    require(mount.is_absolute() and len(mount.parts) >= 3, "Mount point must be a specific absolute path")
    require(mount.parts[1] in {"mnt", "media"}, "Mount point must be beneath /mnt or /media")
    credentials = Path(data["credentials_file"])
    require(credentials.is_absolute() and credentials.name == "nas-01.credentials", "Unexpected credentials path")
    relative = Path(data["backup_directory"])
    require(not relative.is_absolute() and relative.parts and not {".", ".."}.intersection(relative.parts), "Invalid backup directory")
    require(data["retention_days"].isdigit() and 1 <= int(data["retention_days"]) <= 3650, "Retention days must be 1 through 3650")
    require(Path(data["compose_file"]).is_absolute(), "Compose file must be absolute")
    return data


def escape_fstab(value):
    return value.replace("\\", "\\134").replace(" ", "\\040").replace("\t", "\\011")


def without_block(text):
    lines = text.splitlines(keepends=True)
    output = []
    inside = False
    seen_begin = False
    for line in lines:
        marker = line.rstrip("\r\n")
        if marker == BEGIN:
            require(not inside and not seen_begin, "Duplicate or nested nas-backup block")
            inside = True
            seen_begin = True
            continue
        if marker == END:
            require(inside, "Unmatched nas-backup block end")
            inside = False
            continue
        if not inside:
            output.append(line)
    require(not inside, "Unterminated nas-backup block")
    return "".join(output).rstrip("\n")


def with_block(text, lines):
    base = without_block(text)
    block = "\n".join((BEGIN, *lines, END))
    return (base + "\n\n" if base else "") + block + "\n"


def without_hostname(text, hostname):
    output = []
    wanted = hostname.casefold()
    for line in text.splitlines(keepends=True):
        body, separator, comment = line.partition("#")
        fields = body.split()
        if len(fields) >= 2 and any(alias.casefold() == wanted for alias in fields[1:]):
            aliases = [alias for alias in fields[1:] if alias.casefold() != wanted]
            if aliases:
                rebuilt = fields[0] + "\t" + " ".join(aliases)
                if separator:
                    rebuilt += "\t#" + comment.rstrip("\r\n")
                output.append(rebuilt + "\n")
            continue
        output.append(line)
    return "".join(output)


def without_fstab_target(text, source, mount_point):
    output = []
    encoded_source = escape_fstab(source)
    encoded_mount = escape_fstab(mount_point)
    for line in text.splitlines(keepends=True):
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            output.append(line)
            continue
        same_source = fields[0].casefold() == encoded_source.casefold()
        same_mount = len(fields) > 1 and fields[1] == encoded_mount
        if same_source or same_mount:
            require(len(fields) >= 3 and fields[2].casefold() == "cifs", "Configured NAS source or mount point conflicts with a non-CIFS fstab entry")
            require(same_source and same_mount, "Configured NAS source or mount point conflicts with another fstab entry")
            continue
        output.append(line)
    return "".join(output)


def managed_files(config, hosts_text, fstab_text, remove=False):
    hosts = without_block(hosts_text)
    fstab = without_block(fstab_text)
    if remove:
        return (hosts + "\n" if hosts else "", fstab + "\n" if fstab else "")
    host_line = f'{config["ip"]}\t{config["hostname"]}'
    source = f'//{config["hostname"]}/{config["share"]}'
    hosts_text = without_hostname(hosts, config["hostname"])
    fstab_text = without_fstab_target(fstab, source, config["mount_point"])
    options = ",".join((
        "rw", f'credentials={escape_fstab(config["credentials_file"])}',
        f'uid={os.getuid()}', f'gid={os.getgid()}', "vers=3.1.1", "iocharset=utf8",
        "file_mode=0600", "dir_mode=0700", "nosuid", "nodev", "noexec",
        "_netdev", "nofail", "x-systemd.automount", "x-systemd.idle-timeout=10min",
    ))
    fstab_line = "\t".join((escape_fstab(source), escape_fstab(config["mount_point"]), "cifs", options, "0", "0"))
    return with_block(hosts_text, [host_line]), with_block(fstab_text, [fstab_line])


def render(args):
    config = load_config(args.config)
    hosts_text = args.hosts.read_text()
    fstab_text = args.fstab.read_text()
    hosts, fstab = managed_files(config, hosts_text, fstab_text, args.remove)
    args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, text in (("hosts", hosts), ("fstab", fstab)):
        target = args.output / name
        require(not target.exists() and not target.is_symlink(), "Output already exists: " + str(target))
        target.write_text(text)
        target.chmod(0o600)


def check(args):
    config = load_config(args.config)
    expected_hosts, expected_fstab = managed_files(config, args.hosts.read_text(), args.fstab.read_text())
    require(args.hosts.read_text() == expected_hosts, "/etc/hosts nas-backup entry differs from configuration")
    require(args.fstab.read_text() == expected_fstab, "/etc/fstab nas-backup entry differs from configuration")
    print("NAS system configuration check passed")


def main():
    parser = argparse.ArgumentParser(description="Render or validate the managed NAS hosts/fstab blocks without exposing credentials")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("render", "check"):
        child = subparsers.add_parser(name)
        child.add_argument("--config", type=Path, required=True)
        child.add_argument("--hosts", type=Path, default=Path("/etc/hosts"))
        child.add_argument("--fstab", type=Path, default=Path("/etc/fstab"))
        if name == "render":
            child.add_argument("--output", type=Path, required=True)
            child.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    (render if args.command == "render" else check)(args)


if __name__ == "__main__":
    main()

# GitHub CLI on Linux

## Why this exists

- Keep `gh` installs on officially supported package channels.
- Avoid known-bad distribution methods that reduce reliability.

## Recommended path

1. Use official GitHub CLI apt repository (`cli.github.com/packages`).
2. Store key in `/etc/apt/keyrings/githubcli-archive-keyring.gpg`.
3. Use apt source entry with `signed-by` and architecture selector.
4. Install and update with apt.

## Policy notes

- The GitHub CLI team labels distro community packages as unsupported by them.
- Upstream explicitly discourages the Snap package for `gh`.
- Upstream also calls out recent Debian/Ubuntu community package breakage in
  older versions, reinforcing use of official packages.

## Repository fit notes

- `scripts/install-gh-cli.sh` already follows the official apt keyring and
  signed repository pattern.

## Sources

- https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- https://cli.github.com/

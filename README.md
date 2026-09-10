# dotfiles

My system configuration

## Bootstrap

Run full setup with defaults (includes Docker + NVIDIA toolkit, Neovim source build, Ollama systemd mode):

```bash
./bootstrap.sh
```

Preview actions without executing:

```bash
./bootstrap.sh --dry-run
```

Common profile flags:

```bash
./bootstrap.sh --no-gpu
./bootstrap.sh --no-apps
./bootstrap.sh --no-ollama
./bootstrap.sh --with-8bitdo
```

An allowlisted reproducibility sync from host paths into `root/` was completed as a one-time capture. Current `bootstrap.sh` runs do not execute a recurring sync phase.

Intentional refreshes are manual one-time actions only and should follow the source-to-target allowlist mapping in `.github/context/PROJECT/system-context.md`.

Command pattern example:

```bash
install -Dm0644 <source> <repo-target>
```

Checksum automation note: installer integrity checks remain environment-driven using pinned `*_SHA256` values when provided, so expected digests stay explicit and auditable.

## Configuration templates

The public snapshot contains user settings from `.config`, terminal/shell files,
Codex configuration and rules, `.agents` skills, Hindsight integration settings,
authored local launchers, desktop entries and user systemd units. 9router's
configuration tables are exported as JSON, not as its live database.

`templates/manifest.json` owns the captured files, integrity hashes, generated
user-unit links and exclusions. Sources end in `.tmpl`; `@@DOTFILES:NAME@@`
placeholders are rendered from a private JSON file outside this repository.
Template bytes and source whitespace are preserved by `.gitattributes`, so Git
line-ending conversion cannot invalidate their recorded hashes.
`HOME`, `USER`, `UID` and `GID` resolve for the destination user automatically.
The current machine's values remain in `~/.config/dotfiles/values.json`; never
commit or paste that file. On another machine, fill a private copy of
`templates/values.example.json`. Python 3.11 or newer is required.

```bash
python3 scripts/setup-dotfiles.py
python3 scripts/setup-dotfiles.py --values /private/path/values.json --apply
./bootstrap.sh --with-dotfiles --dotfiles-values /private/path/values.json --dry-run
```

Rendering previews by default, validates all inputs before writing, refuses path
traversal and symlink escapes, and backs up replaced files beneath the target
home's `.local/state/dotfiles/`. It creates empty Hindsight data directories and
owned user-unit enablement links, but does not install packages or start services.
Run as the destination user; reload the user systemd manager after review.

To restore 9router routing, initialize the same compatible 9router version once,
stop it, then add `--restore-router --apply`. Only the exported configuration
tables are replaced in one transaction, after a private SQLite backup; request
history and usage tables are untouched. OAuth connections require a fresh login.

Refreshes are explicit, never automatic:

```bash
python3 scripts/snapshot.py --output /tmp/new-dotfiles --values /private/path/values.json
python3 scripts/guard.py --values /private/path/values.json
```

Review the new snapshot before replacing repository templates. Values must stay
outside the snapshot and all Git working trees. Existing values are backed up
privately in a sibling `backups/` directory before refresh. `scripts/guard.py` scans complete
files and reports only finding locations/categories, never secret contents.

Not captured: authentication/session stores, histories, Hindsight's corpus and
database, caches, installed executables/packages, firmware, sample libraries and
browser/account state. Reinstall those applications through their normal tools;
the snapshot is configuration recovery, not a complete home-directory backup.

`templates/requirements.json` records installed integration versions and restore
order. Captured operational notes may refer to runtime receipts that are not
backed up; perform fresh health checks after restoring services.

## Installer scripts

- `scripts/install-core-cli.sh` installs base apt tooling and fish (install-only).
- `scripts/install-gh-cli.sh` configures the official GitHub CLI apt repo and installs `gh`.
- `scripts/install-neovim-latest.sh` builds and installs latest tagged Neovim from source.
- `scripts/install-docker-engine.sh` configures official Docker apt repo and installs Docker Engine packages.
- `scripts/install-nvidia-container-toolkit.sh` installs and configures NVIDIA Container Toolkit for Docker.
- `scripts/install-ollama.sh` installs Ollama and enables systemd service mode by default.
- Existing app installers remain available in `scripts/` for Blender, Ghidra, REAPER, and optional 8BitDo setup.

## Security

See [SECURITY.md](SECURITY.md) for credential protection and pre-commit hook policy.

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

### Hindsight authentication

Set `SECRET_HINDSIGHT_API_KEY` and `SECRET_HINDSIGHT_DASHBOARD_ACCESS_KEY` in
your private renderer values. The API key is reused by the server, built-in MCP,
dashboard dataplane client, Codex Hindsight plugin and CLI; the dashboard login
uses its separate access key. Both keys are generated and populated on this host.
Only placeholders and null-valued examples belong in Git.

Rendering also creates `~/.config/hindsight/credentials.json` with mode `0600`
for local key retrieval. Keep it private. After an intentional restore, restart
only `hindsight.service`; the renderer does not restart it automatically. Existing
imports remain in the separate persistent database. Services stay loopback-only;
upstream health, metrics and API-documentation routes remain unauthenticated.

## Installer scripts

- `scripts/install-hindsight.sh` installs the pinned CLI/runtime and activates the captured Docker-backed user units (details below).
- `scripts/install-core-cli.sh` installs base apt tooling and fish (install-only).
- `scripts/install-gh-cli.sh` configures the official GitHub CLI apt repo and installs `gh`.
- `scripts/install-neovim-latest.sh` builds and installs latest tagged Neovim from source.
- `scripts/install-docker-engine.sh` configures official Docker apt repo and installs Docker Engine packages.
- `scripts/install-nvidia-container-toolkit.sh` installs and configures NVIDIA Container Toolkit for Docker.
- `scripts/install-ollama.sh` installs Ollama and enables systemd service mode by default.
- Existing app installers remain available in `scripts/` for Blender, Ghidra, REAPER, and optional 8BitDo setup.

### Hindsight installation and activation

Run as the destination user in a logged-in Linux session, never with `sudo`.
First install Docker/Compose, Node >=22.15 with npm, and Python >=3.11. Restore
the private templates, then install and activate Hindsight:

```bash
python3 scripts/setup-dotfiles.py --values /private/path/values.json --apply
./scripts/install-hindsight.sh --dry-run
./scripts/install-hindsight.sh
./scripts/install-hindsight.sh --check
```

Alternatively, use `./bootstrap.sh --with-dotfiles --with-hindsight` with your
private `--dotfiles-values` path. Hindsight is opt-in; when requested, bootstrap
installs Docker even with `--no-gpu` or the minimal profile. Node/npm and running
9router/EasyLlama remain prerequisites. A newly granted Docker group membership
requires a fresh login before the Hindsight installer can proceed.

The installer verifies SHA256-pinned official CLI 0.9.2 binaries for Linux amd64
or arm64. It stages the official coding-agent 0.5.3 runtime via npm when missing;
a newer compatible installed runtime is retained, preserving automatic updates.
The captured Codex hooks, MCP configuration and skills are restored by the
renderer, not rewritten by the runtime-only updater. No Codex session is launched.

It enables/starts the system Docker daemon, pulls only missing digest-pinned
images from the rendered Compose configuration, reloads the user service manager,
enables both units for login, then starts `hindsight-db.service` before
`hindsight.service`. The app also requires the database unit; both units check the
system Docker daemon. `--no-start` enables the user units without starting them;
`--check` validates configuration and authenticated endpoints without mutation.
Existing active units are not restarted. No database/volume is deleted, credentials
are not rotated, and lingering is not enabled. Back up database contents separately.

The CLI checksum pins come from the official
[Hindsight v0.9.2 release](https://github.com/vectorize-io/hindsight/releases/tag/v0.9.2).
Changing the CLI version requires reviewing new checksums; container digest changes
remain explicit template changes rather than automatic upgrades.

## Security

See [SECURITY.md](SECURITY.md) for credential protection and pre-commit hook policy.

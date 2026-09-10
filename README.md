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

- `scripts/install-herdr.sh` restores herdr/plugins and enables its user unit; `scripts/install-alacritty.sh` restores the terminal build, font and desktop integration.
- `scripts/install-mise.sh` installs checksum-verified mise; `scripts/install-user-tools.sh` restores user toolchains and versionless packages.
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
9router/EasyLlama remain prerequisites. Add `--with-user-tools` to restore Node/npm
and your other user tools before Hindsight. A newly granted Docker group membership
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

### User toolchains and versionless packages

`templates/packages.json` inventories user npm globals across installed Node
runtimes, mise tool identities, Python user-site and user-owned mise distributions, requested
packages, uv tools, Cargo crates, Rust components/targets, and Go command package paths. Package versions
and duplicate runtime installations are omitted; restoration resolves current
releases. Configured runtime selectors are preserved separately: Node `24`,
Python `3.12.13`, and the remaining selectors in the mise template. The rustup
default version/profile is preserved with the destination host target. Inactive
mise tools install without changing global defaults. uv becomes a global mise
tool instead of restoring its old standalone binary/installation receipt.

```bash
python3 scripts/setup-dotfiles.py --values /private/path/values.json --apply
./scripts/install-user-tools.sh --dry-run
./scripts/install-user-tools.sh
./bootstrap.sh --with-dotfiles --with-user-tools --with-hindsight --dry-run
```

Run as the destination user; no sudo or system Python writes. Python distributions
restore through `uv pip --target` into the corresponding user site or `uv pip`
into an explicitly resolved, user-owned mise interpreter; requested
ruff/sqlfluff/yamllint commands use isolated `uv tool` environments, replacing their
old exposed command wrappers when present. npm globals stay in the resolved,
user-owned Node prefix; uv/Cargo/Rustup/Go destinations are restricted to the user
account rather than inherited system prefixes. Cargo registry
tools use `cargo install --locked`; release-built Go packages use `go install` with
`@latest`. The two local/development Go binaries (`gmux`, `gmuxd`) remain explicit
manual source rebuilds, not guessed remote package installs. Local/direct Python
sources are inventoried separately and require their original source installs;
they are never silently replaced by similarly named PyPI packages. Retired Pi packages
are fully inventoried but skipped unless `--include-retired-pi` is explicitly used.
Review conflicting legacy Pi CLI packages before opting in.

Shell/profile, Cargo environment and rustup settings are templated. Non-secret
npm scope/registry and script settings live in the package manifest; `.npmrc`
tokens are excluded, so authenticate separately for private registries. Go
telemetry, uv installation receipts, caches and compiled toolchains are excluded.
The restored mise config intentionally drops blanket `/` trust; the installer
trusts only the rendered user config, never all project configurations. Existing
live trust settings are not changed by capture. Review templates before rendering.

To refresh package names intentionally, run `python3 scripts/packages.py snapshot`
and review the diff. This does not refresh credentials or copy package payloads.
The mise installer preserves an existing binary; fresh Linux amd64/arm64 installs
use checksums from the official [mise v2026.5.0 release](https://github.com/jdx/mise/releases/tag/v2026.5.0).

### Herdr and Alacritty

```bash
./scripts/install-herdr.sh --dry-run
./scripts/install-alacritty.sh --dry-run
./bootstrap.sh --with-dotfiles --with-user-tools --with-terminals --dry-run
```

Remove `--dry-run` only after reviewing rendered configuration. Herdr fresh installs
use checksum-pinned upstream `0.8.2`; existing binaries are preserved even when
mise's directory name is stale. The installer enables its user unit for login and
starts it without restarting an active server. `--no-start`, `--no-plugins` and
read-only `--check` are available. Existing sessions and workspaces are untouched.

Herdr theme, keybindings, terminal/remote preferences and user unit are captured.
The complete plugin registry is archived as
`~/.config/herdr/restore/plugins.json`, not replayed as stale live registry paths.
The installer preserves present plugins and restores missing GitHub plugins at
their recorded source commit using herdr's native installer. Local DRPer integration
requires its source checkout; missing source is reported rather than downloaded
from a guessed location. Retired `pi-herd` is archived but not installed or changed.
Plugin build dependencies (Rust, Bun/Node, etc.) must be available; use user-tools
restoration first. Logs, session history, locks, release-note caches and installed
plugin payloads are excluded. Plugin code stays in its original repositories.

Alacritty preserves the installed `0.18.0-dev` source revision
`f99dc71708d31d5c32d4b3fa611f9a87bf22657e`, rather than substituting a stable
release. It installs into `~/.local/bin`, with user terminfo, icon, manuals, shell
completions and the verified DepartureMono Nerd Font asset used on this machine.
The rendered desktop launcher targets that user binary. Font size, theme imports,
keyboard/mouse bindings, OSC52 and other terminal preferences remain configured.
The existing source checkout and `/usr/local/bin/alacritty` are not modified.
Rust/Cargo are prerequisites; `--no-deps` skips the apt build dependencies and
`--check` validates configuration without compiling or opening a window. Zsh users
should include `~/.zsh_functions` in their `fpath` to use the installed completion.

Pinned sources: [herdr release](https://github.com/herdrdev/herdr/releases/tag/v0.8.2),
[Alacritty source](https://github.com/alacritty/alacritty/tree/f99dc71708d31d5c32d4b3fa611f9a87bf22657e),
[Nerd Fonts release](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.4.0).

## Security

See [SECURITY.md](SECURITY.md) for credential protection and pre-commit hook policy.

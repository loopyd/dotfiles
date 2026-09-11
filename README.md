# dotfiles

My system configuration

## Bootstrap

Run full setup with defaults (includes Docker + NVIDIA toolkit, Neovim source build, Ollama systemd mode):

```bash
./bootstrap.sh install
```

Preview actions without executing:

```bash
./bootstrap.sh install --dry-run
```

Common profile flags:

```bash
./bootstrap.sh install --no-gpu
./bootstrap.sh install --no-apps
./bootstrap.sh install --no-ollama
./bootstrap.sh install --with-8bitdo
```

An allowlisted reproducibility sync from host paths into `root/` was completed as a one-time capture. Current `bootstrap.sh` runs do not execute a recurring sync phase.

Intentional refreshes are manual one-time actions only and should follow the source-to-target allowlist mapping in `.github/context/PROJECT/system-context.md`.

Command pattern example:

```bash
install -Dm0644 <source> <repo-target>
```

Checksum automation note: installer integrity checks remain environment-driven using pinned `*_SHA256` values when provided, so expected digests stay explicit and auditable.

## Configuration templates

Games are outside this repository's deployment scope. Game/server configs,
launchers, emulator settings and game package entries are excluded from capture
and restoration, including Unity Horizon/DreadZone and Steam. System-package
installs also reject APT's `games` section. Graphics drivers, developer tools,
audio configuration and unrelated Horizon-named themes/effects remain supported.
These exclusions never uninstall games or alter their live configuration.

The public snapshot contains user settings from `.config`, terminal/shell files,
Codex configuration and rules, `.agents` skills, Hindsight integration settings,
authored local launchers, desktop entries and user systemd units. 9router's
configuration tables are private renderer values, not a live database in Git.

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
python3 scripts/dotfiles.py check
python3 scripts/dotfiles.py install --values /private/path/values.json
./bootstrap.sh install --with-dotfiles --dotfiles-values /private/path/values.json --dry-run
```

Use `check` or `install --dry-run` to preview. Rendering validates inputs, refuses path
traversal and symlink escapes, and backs up replaced files beneath the target
home's `.local/state/dotfiles/`. It creates empty Hindsight data directories and
owned user-unit enablement links, but does not install packages or start services.
Run as the destination user; reload the user systemd manager after review.

For a fresh 9router installation, `scripts/router.sh install` initializes the
pinned container offline and restores the captured tables before network exposure.
For an existing database, stop the gateway and run `scripts/router.py restore`
or add `--restore-router` to `dotfiles.py install`. Only six configuration tables
are replaced transactionally after a private SQLite backup; history and usage
remain untouched. Captured OAuth credentials are retained, but expired or revoked
sessions may still require login. See the network identity boundary below.

Refreshes are explicit, never automatic:

```bash
python3 scripts/snapshot.py --output /tmp/new-dotfiles --values /private/path/values.json
python3 scripts/guard.py --values /private/path/values.json
```

Review the new snapshot before replacing repository templates. Values must stay
outside the snapshot and all Git working trees. Existing values are backed up
privately in a sibling `backups/` directory before refresh. `scripts/guard.py` scans complete
files and reports only finding locations/categories, never secret contents.
Snapshot backups exclude `SECRET_TAILSCALE_API_KEY`; refresh preserves it only in
the private `values.json`.

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

## Lifecycle commands

Component entry points use noun filenames and require an explicit action:

```bash
./scripts/alacritty.sh install --no-deps
./scripts/alacritty.sh update --no-deps
./scripts/alacritty.sh check
./bootstrap.sh update --only alacritty,herdr --dry-run
./bootstrap.sh uninstall --only alacritty,herdr --dry-run
./bootstrap.sh check --only herdr,mise
```

`install` creates/converges the selected component; `update` upgrades its apt
packages or reapplies its configured source/version pins, never silently choosing
a new upstream version. User-package updates refresh versionless packages while
keeping configured runtime selectors. `check` is read-only; `--dry-run` works for
every action and never downloads or changes files/services. There are no legacy
action-prefixed aliases. Bootstrap sorts dependencies, validates every selected
uninstall receipt before mutation, then removes dependents first. Uninstall
requires explicit `--only` selection; it never implies removing the whole system.

Successful component installs record their declared payload files and packages
in `~/.local/state/dotfiles/lifecycle/`. This adopts matching existing payloads;
review the install selection first. Uninstall refuses unmanaged installations,
changed payloads, paths outside the selected component and apt dependency
cascades. Use the same custom path options used during installation. It removes
only recorded files, not directory trees, and does not purge configuration,
credentials, database volumes, models or unrelated dependencies. Stop/removal of
Hindsight leaves its shared coding-agent runtime and settings available for reuse.
User-tools removal targets managed npm/uv/Cargo commands; shared language
runtimes, Python libraries, local Go builds and retired Pi packages are retained.

`dotfiles.py install|update` renders settings; `check` validates templates and
private values. Its `uninstall` deliberately retains configuration and backups:
the renderer has no installed runtime. `desktop.sh` consolidates desktop
`install|update|check|export`; `uninstall --input <backup>` restores an explicit
pre-install snapshot rather than resetting unrelated preferences. Capture it
first with `desktop.sh export --output ~/.local/state/dotfiles/desktop/before`.
Bootstrap includes it through `--with-desktop` or `--only desktop`; removal
requires `--desktop-backup <backup>`. Shared libraries and developer
utilities (`delib`, `lifecycle`, `guard`, `snapshot`, `packages`, `terminal`,
`hindsight`) retain their domain-specific helper commands, not fake installers.

- `scripts/herdr.sh` restores herdr/plugins and enables its user unit; `scripts/alacritty.sh` restores the terminal build, font and desktop integration.
- `scripts/mise.sh` installs checksum-verified mise; `scripts/tools.sh` restores user toolchains and versionless packages.
- `scripts/hindsight.sh` installs the pinned CLI/runtime and activates the captured Docker-backed user units (details below).
- `scripts/core.sh` installs base apt tooling and fish.
- `scripts/gh.sh` configures the official GitHub CLI apt repo and installs `gh`.
- `scripts/neovim.sh` builds and installs latest tagged Neovim from source.
- `scripts/docker.sh` configures official Docker apt repo and installs Docker Engine packages.
- `scripts/nvidia.sh` installs and configures NVIDIA Container Toolkit for Docker.
- `scripts/ollama.sh` installs Ollama and enables systemd service mode by default.
- Existing app installers remain available in `scripts/` for Blender, Ghidra, REAPER, and optional 8BitDo setup.

### Hindsight installation and activation

Run as the destination user in a logged-in Linux session, never with `sudo`.
First install Docker/Compose, Node >=22.15 with npm, and Python >=3.11. Restore
the private templates, then install and activate Hindsight:

```bash
python3 scripts/dotfiles.py install --values /private/path/values.json
./scripts/hindsight.sh install --dry-run
./scripts/hindsight.sh install
./scripts/hindsight.sh check
```

Alternatively, use `./bootstrap.sh install --with-dotfiles --with-hindsight` with your
private `--dotfiles-values` path. Hindsight is opt-in; when requested, bootstrap
installs Docker even with `--no-gpu` or the minimal profile. Node/npm and running
The captured local stack now selects EasyLlama, 9router and their Docker/NVIDIA
prerequisites in order. Add `--with-user-tools` to restore Node/npm
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
`check` validates configuration and authenticated endpoints without mutation.
Install leaves active units running. Update stops the app, restarts the database,
then restarts the app to apply configured container pins; `--no-start` suppresses
this activation. No database/volume is deleted, credentials
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
python3 scripts/dotfiles.py install --values /private/path/values.json
./scripts/tools.sh install --dry-run
./scripts/tools.sh install
./bootstrap.sh install --with-dotfiles --with-user-tools --with-hindsight --dry-run
```

Run as the destination user; no sudo or system Python writes. Python distributions
restore through `uv pip --target` into the corresponding user site or `uv pip`
into an explicitly resolved, user-owned mise interpreter; requested
ruff/sqlfluff/yamllint commands use isolated `uv tool` environments, replacing their
old exposed command wrappers when present. npm globals stay in the resolved,
user-owned Node prefix; uv/Cargo/Rustup/Go destinations are restricted to the user
account rather than inherited system prefixes. Cargo registry
tools use `cargo install --locked`; release-built Go packages use `go install` with
`@latest`. Local/development Go builds require their original source and explicit
manual rebuilds, not guessed remote package installs. Local/direct Python
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
./scripts/herdr.sh install --dry-run
./scripts/alacritty.sh install --dry-run
./bootstrap.sh install --with-dotfiles --with-user-tools --with-terminals --dry-run
```

Remove `--dry-run` only after reviewing rendered configuration. Herdr fresh installs
use checksum-pinned upstream `0.8.2`; existing binaries are preserved even when
mise's directory name is stale; `update` replaces the user launcher with the pinned
binary without following an old mise symlink. The installer enables its user unit for login and
starts it without restarting an active server. `--no-start`, `--no-plugins` and
read-only `check` are available. Existing sessions and workspaces are untouched.
An active herdr server picks up an updated binary on its next deliberate restart.

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

Alacritty always compiles the captured `0.18.0-dev` source revision
`f99dc71708d31d5c32d4b3fa611f9a87bf22657e`, rather than substituting a stable
release. Install and update never reuse an existing binary; the build must report
`alacritty 0.18.0-dev (f99dc717)` before installation. It installs into `~/.local/bin`, with user terminfo, icon, manuals, shell
completions and the verified DepartureMono Nerd Font asset used on this machine.
The rendered desktop launcher targets that user binary. Font size, theme imports,
keyboard/mouse bindings, OSC52 and other terminal preferences remain configured.
The existing source checkout and `/usr/local/bin/alacritty` are not modified.
Rust/Cargo are prerequisites; `--no-deps` skips the apt build dependencies and
`check` validates configuration without compiling or opening a window. Zsh users
should include `~/.zsh_functions` in their `fpath` to use the installed completion.

Pinned sources: [herdr release](https://github.com/herdrdev/herdr/releases/tag/v0.8.2),
[Alacritty source](https://github.com/alacritty/alacritty/tree/f99dc71708d31d5c32d4b3fa611f9a87bf22657e),
[Nerd Fonts release](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.4.0).

### Network services

`scripts/easyllama.sh install|update|uninstall|check` restores the captured Qwen
Docker stack with its **0.6.0 source revision and immutable local image IDs**.
Use `--with-easyllama` or `--only easyllama` in bootstrap; Hindsight and 9router
select it automatically for install/update. The user supervisor adopts matching
running containers without model reload, starts them at login and stops them on
unit shutdown. Dependency ordering and restart propagation cover the local stack.

Captured configuration, mode profiles and chat templates live under
`~/.config/easyllama`; `EASYLLAMA_ROOT` preserves the existing model/cache root.
Credentials remain private renderer values. Locally built images require the
explicit archive/load workflow documented in
[network service operations](.github/context/PROJECT/network-services.md#easyllama-snapshot);
they are not silently rebuilt or pulled from an assumed public registry.

`scripts/router.sh` and `scripts/tailscale.sh` expose the same lifecycle actions
as other components; bootstrap selects them with `--with-network` or
`--only tailscale,router`. The Compose definition keeps 9router 0.5.69
pinned by digest, **2 CPUs**, **4 GiB `/dev/shm`** and the existing `~/.9router`
data. Its verified backend is loopback-only `127.0.0.1:20128`; host Tailscale
socket/binary mounts are removed and internal publication is set to `false`.

**Phase 1 complete — Verified 2026-09-10.** After Code/Security GO,
migration and gateway/Hindsight restarts succeeded. Native `ninerouter` serves
private HTTPS; Funnel removal is confirmed from native configuration.
Dashboard and API share HTTPS 443; use
`https://ninerouter.tailc28ab1.ts.net/v1` as the API base. Port 20128 is the local
Docker proxy backend, not a raw remote API endpoint.

The proposed next stage uses native kernel Tailscale Services: native host
`koija` / `tag:ssh` and a separate `ninerouter:443` Service VIP. Services
require host tagging, which removes personal ownership and Taildrop eligibility.
Fresh preferences show **four DriveShares**; an approved tagged-host migration
must preserve owner wildcard read/write access through the Taildrive capability,
host `drive:share` and client `drive:access`. Renaming changes Taildrive mount
and bookmark paths; see the [owner/file-sharing requirements](.github/context/PROJECT/network-services.md#owner-identity-and-file-sharing).
Phase 1 preserved the in-memory DriveShares fingerprint and count of four;
capture does not export share definitions. The original owner stays pinned privately.
Rename, tagging and Service activation await the user's personal-identity
choice; native identity, SSH settings and preferences are preserved, with no
tag, rename or tailnet API writes. Checked owner SSH to
local user `koija` must remain available; external SSH login is untested.

The root native daemon owns networking and SSH. Starting `9router.service`
pulls in and re-executes the user coordinator to restore private configuration,
without another userspace daemon or startup API/model launches. This dependency
path passed verification. Retired app helpers and unit/endpoints templates are
removed from the repository; snapshot capture excludes obsolete live app artifacts.
The owner template and masked/offline home state remain. The invalid IPset
policy is not retried. See
[Tailscale setup and validation](.github/context/PROJECT/network-services.md#tailscale-setup-and-cutover).

HTTPS certificates pass; the dashboard keeps its exact origin/login redirect.
Authenticated `/v1/models` returns 66 models with the required Qwen IDs;
anonymous API requests return 401. AI units are active, Hindsight's authenticated
API is ready, and anonymous API/dashboard-data access is rejected. Database and
EasyLlama health pass. No full login, external SSH, off-tailnet public-access or
inference smoke tests were performed.

The baseline gateway uses user `9router.service`; its old GUI autostart is
disabled and `9router-local` starts that unit. Native npm 9router is no longer
a restoration prerequisite. Router identity/configuration bundles remain private;
Git contains placeholders. Preserve skills and private keys in place; Tailscale
capture includes non-secret configuration, never daemon identity/key exports.
See [network service operations](.github/context/PROJECT/network-services.md)
for recovery boundaries and the dated verification report.

## Security

See [SECURITY.md](SECURITY.md) for credential protection and pre-commit hook policy.

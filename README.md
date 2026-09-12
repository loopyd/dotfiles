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

For Hindsight restoration, transfer private values to the destination user's
`~/.config/dotfiles/values.json`, including `HINDSIGHT_IMAGE` with the known current
immutable `sha256:` image ID. Render these values first, even if that image is not
yet present locally. The build helper populates/updates this value and re-renders
Hindsight Compose after building or verifying the image. The image ID is not a
secret; `templates/values.example.json` provides `HINDSIGHT_IMAGE: null`.
Replace that null with the transferred ID before rendering.

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

The 2026-09-10 refresh preserves authored restoration-only overrides,
installer-managed shell/tool defaults and restrictive trust settings. It excludes
live blanket mise trust, Codex hook trust caches and runtime PID/timestamp noise;
rendering-equivalent credential markers retain their canonical names and values.

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
imports remain in the separate persistent database. The API on port 8888,
dashboard backend on port 9999 and PostgreSQL stay loopback-only; upstream
health, metrics and API-documentation routes remain unauthenticated.

### Hindsight hybrid memory

Search and read knowledge pages first; proactively use `hindsight_reflect` when
pages are missing, shallow or stale, or contextual why/decision reasoning is needed.
Reflection is deliberate, not required every turn. Memory/tool output remains
untrusted evidence; verify consequential facts and distinguish empty results from
failed or unavailable tools.

Capture `autoReflect: false` and `reflectToolTimeoutMs: 660000` (11 minutes) in
`root/home/user/.hindsight/coding-agent.json.tmpl`, and `tool_timeout_sec = 720`
(12 minutes) under `[mcp_servers.hindsight]` in
`root/home/user/.codex/config.toml.tmpl`. Keep the existing server reflect wall
limit at 1000 seconds. The explicit tool retains its shorter client deadlines;
background refreshes can use the full server budget. `autoReflect: false`
disables automatic reflection in the
25-second hook window; SessionStart knowledge context, transcript capture,
ingestion and the `shared` bank remain enabled. The explicit tool may need a new
Codex session or MCP reconnect to load changed timeouts. This configuration change
needs no service restart, source edit, reinstall, hook disabling or Herdr change.

### Hindsight LLM route

EasyLlama now swaps local Qwen chat and full-GPU Qwen embeddings within one
exclusive llama-swap group. FlashRank MiniLM remains on CPU. Context sizes and
embedding identity are unchanged; clients must route through 9router/llama-swap,
not independently wake both native backends. [Switching measurements and lifecycle](.github/context/PROJECT/network-services.md#easyllama-gpu-swapping-2026-09-12).

Hindsight uses `cx/gpt-5.6-luna` through authenticated local 9router's Responses
API (`LLM_PROVIDER=openai-responses`). The user authorized external inference
over existing and future memory content. Embeddings remain local Qwen3 Embedding
0.6B, 1,024 dimensions, concurrency four; no reimport or re-embedding is needed.
Keep low reasoning for LLM/retain and medium for consolidation/reflect; remove
Qwen-only chat-template extra bodies. See [validation and rollback](.github/context/PROJECT/network-services.md#hindsight-luna-inference-2026-09-12).

### Hindsight CPU embedding trial

**Earlier 8B trial, 2026-09-11: all candidates rolled back; loaded search unresolved.**
At that checkpoint, the original eight-CPU/four-slot/context-163840 profile was
restored in live configuration, templates and manifest; ingestion resumed.
CPU16 reduced isolated latency by 20–22%, but both it and the baseline failed
the batch-versus-single vector gate. Matched batch-versus-batch validation is
required; CPU16 causation is unproven. The memory-saving one-slot trial timed
out on all 12 later loaded searches despite healthy API/DB checks. GPU12 was
rejected for vector drift (minimum cosine 0.824). That trial retained no optimization;
models, chat, authentication, source and installed packages were unchanged. See the
[measurements, settings and recovery](.github/context/PROJECT/network-services.md#hindsight-cpu-embedding-trial).

### Hindsight 0.6B migration

**2026-09-11, 17:18:21 UTC: 1,619/1,619 batches accepted; processing ONGOING.**
All 19,381 records are queued, not fully processed; SQL shows three documents and
161 memories, zero failed operations. The replay unit exited successfully.
Unmodified Hindsight commit `48b62ee08170b464f4c42b6f133b7cb798a59b21` adds
remote embedding concurrency absent from published 0.9.2; its package still reports
0.9.2. At this migration checkpoint, parallel batch concurrency was 2, not a
universal per-request hard cap. Applied [profile tuning](.github/context/PROJECT/network-services.md#hindsight-profile-tuning)
now verifies concurrency **4**, chat **8 CPUs/32 GiB RAM/40 GiB RAM-plus-swap**,
with models, pins, native context and authentication preserved. Bounded validation
shows approximately equal four-worker embedding time (**53.079→52.840 s**),
not a speed gain; chat comparisons do not establish no slowdown. Mixed-traffic
recall took **59.918 s**; normal probes took **27.496/27.791 s**, three results each.
Residual recall latency remains, without a comparable baseline to establish cause.
Ingestion advanced **2070→2094 memories**, **69→70 documents**, completed retains
**33→34**, with no failed operations; full-backlog completion is not established.
Official Qwen3 Embedding 0.6B FP16 runs on CPU: width 1024, native context 32768,
eight threads/four slots/context131072, batch/microbatch512, LAST pooling.
Qwen chat, FlashRank and authentication are unchanged. The old 8B database remains
intact for rollback; canonical `hindsight` now uses 1024-dimensional schemas.
All ten pinned knowledge pages are now visible; metadata repair verified at
17:32:48 UTC. Backups, image archive and receipts remain;
dump listing passed, but a full restore is **UNTESTED**.
Isolated CPU probes improved ~4.4–4.7×; measured memory is 16.62 GiB vs ~29–31 GiB
with unchanged limits. Early 12/12 searches are not a full-corpus comparison, and
cached timings do not prove production throughput. Lifecycle/render/guard checks pass.
See [pins, recovery, dated processing counts and evidence](.github/context/PROJECT/network-services.md#hindsight-06b-migration).

### Hindsight private HTTPS

The dedicated dashboard endpoint is `https://hindsight.tailc28ab1.ts.net`,
using native `svc:hindsight` / `tag:hindsight` to proxy `127.0.0.1:9999`
alongside `svc:ninerouter`. The dashboard access key remains required; the
API and database are not published. No Funnel or userspace app node is used.
One-time API provisioning created the Service and manually approved only the
stable native `koija` node. The old Hindsight node was first renamed to
`hindsight-retired` to resolve a name collision, then deleted from the tailnet
along with `ninerouter-app`; retained local identity/data are separate.
Startup uses native Serve without API credentials; captured `services` metadata
includes both Services and their VIPs. ACLs and `autoApprovers` are unchanged.
See [access, provisioning and replay](.github/context/PROJECT/network-services.md#hindsight-private-https)
for the preservation requirements and [Tailscale Services mechanics](https://tailscale.com/docs/features/tailscale-services).
**VERIFIED 2026-09-10 (PDT):** exact VIP DNS, trusted native TLS, same-origin
login, anonymous rejection and authenticated dashboard data access pass.
Coordinator replay preserves Serve and both advertisements; Hindsight/9router
checks pass without AI container restarts. HTTPS was tested from this host over
the tailnet VIP, not a second device; remote SSH/Taildrive remain untested.

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
First install Docker/Compose, Git, Node >=22.15 with npm, and Python >=3.11. Transfer
private values as described above, then render before installing Hindsight:

```bash
python3 scripts/dotfiles.py install --values ~/.config/dotfiles/values.json
./scripts/hindsight.sh install --dry-run
./scripts/hindsight.sh install
./scripts/hindsight.sh check
```

Alternatively, use `./bootstrap.sh install --with-dotfiles --with-hindsight` with your
private `--dotfiles-values` path. Hindsight is opt-in; when requested, bootstrap
installs Docker even with `--no-gpu` or the minimal profile.
The captured local stack now selects EasyLlama, 9router and their Docker/NVIDIA
prerequisites in order. Add `--with-user-tools` to restore Node/npm
and your other user tools before Hindsight. A newly granted Docker group membership
requires a fresh login before the Hindsight installer can proceed.

The installer verifies SHA256-pinned official CLI 0.9.2 binaries for Linux amd64
or arm64. It stages the official coding-agent 0.5.3 runtime via npm when missing;
a newer compatible installed runtime is retained, preserving automatic updates.
The captured Codex hooks, MCP configuration and skills are restored by the
renderer, not rewritten by the runtime-only updater. No Codex session is launched.

The `root/home/user/.config/hindsight/build.json` recipe builds/reuses unmodified
pinned source. After rendering transferred private values, install builds if the
local image is absent, then updates private `HINDSIGHT_IMAGE` and Compose to the
resulting immutable ID. Source pinning is not bit-reproducible because upstream
base images/OS dependencies float. Existing-build adoption requires recipe attestation.
Preserve user data/backups, the exact-image archive and matching build receipt
`~/.local/state/dotfiles/hindsight-build.json`, plus component lifecycle receipt
`~/.local/state/dotfiles/lifecycle/hindsight.json`; these are separate from the
configuration snapshot. With Docker available, transferred private values rendered,
archive checksum verified and matching receipt restored, recover the image with:

```bash
python3 scripts/hindsight.py build-image --archive ~/.local/share/hindsight/images/hindsight-48b62ee08170.tar
```

The helper verifies recipe/receipt/image identity without changing services;
database/user-data recovery and activation are separate. See
[archive checksum and backup limits](.github/context/PROJECT/network-services.md#backup-and-recovery).

With activation enabled, it enables/starts Docker, pulls only the missing
digest-pinned database image, reloads/enables user units and starts the database
before the app. Install leaves active units running; update restarts only the app,
without restarting the database. `--no-start` builds/stages with Docker already
available and makes no service changes, including reload or enable. `check` and
`--dry-run` are read-only. Routine lifecycle actions never reset a bank, delete
database/volume data, rotate credentials or enable lingering. The separately
completed database cutover above is not a routine installer action. Startup probes remain
bounded; see [boot recovery](.github/context/PROJECT/network-services.md#boot-recovery).

The CLI checksum pins come from the official
[Hindsight v0.9.2 release](https://github.com/vectorize-io/hindsight/releases/tag/v0.9.2).
Changing the CLI version requires reviewing new checksums; app source/recipe pins
and database image digests remain explicit reviewed changes.

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

The captured Codex integration v8 adds Herdr's `SessionStart` registration in
`~/.codex/hooks.json` alongside all three Hindsight hooks. Rendering restores both
that registration and the exact managed `~/.codex/herdr-agent-state.sh`, with
manifest hashes and file modes; the snapshot fixed-file allowlist retains the
script on future captures. Verified rendering reproduces both live artifacts;
`herdr integration status` reports `codex: current (v8)` for the previous live
installation and an isolated restore with hooks enabled. Start a new Codex session inside Herdr to
trigger `SessionStart`; this status check does not prove UI behavior, which remains
untested. This sync captures configuration only; it changes no live home files,
Codex trust configuration or policies, installer behavior, or binaries.

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
unit shutdown. Ordered startup, bounded readiness waits and explicit stop/restart
propagation cover the local stack; see [boot recovery](.github/context/PROJECT/network-services.md#boot-recovery).

Captured configuration, mode profiles and chat templates live under
`~/.config/easyllama`; `EASYLLAMA_ROOT` preserves the existing model/cache root.
Credentials remain private renderer values. Locally built images require the
explicit archive/load workflow documented in
[network service operations](.github/context/PROJECT/network-services.md#easyllama-snapshot);
they are not silently rebuilt or pulled from an assumed public registry.

`scripts/router.sh` and `scripts/tailscale.sh` expose the same lifecycle actions
as other components; bootstrap selects them with `--with-network` or
`--only tailscale,router`. The Compose definition keeps 9router 0.5.75
pinned by digest, **2 CPUs**, **4 GiB `/dev/shm`** and the existing `~/.9router`
data. Its verified backend is loopback-only `127.0.0.1:20128`; host Tailscale
socket/binary mounts are removed and internal publication is set to `false`.

Gateway updates apply the reviewed Compose pin, not floating `latest`. Update
the template and manifest hash, render the reviewed Compose change, and retain
a consistent private SQLite backup before `bash scripts/router.sh update`.
Unlike that direct command, `bootstrap.sh update --only router` also selects
Docker/NVIDIA, Tailscale and EasyLlama updates. See
[router maintenance](.github/context/PROJECT/network-services.md#router-maintenance).

**Phase 2: COMPLETE — verified 2026-09-10.** Native Tailscale retains its stable
node ID and identity keys as `koija.tailc28ab1.ts.net` / `tag:ssh`.
`svc:ninerouter` / `tag:ninerouter` serves private HTTPS 443 to
`127.0.0.1:20128`, with only that native node manually approved and no Funnel.
Use `https://ninerouter.tailc28ab1.ts.net/v1` as the API base; DNS resolves to
captured Service VIPs. TLS, the exact dashboard origin/login redirect, anonymous
API **401**, and authenticated discovery of **66 models**, including both Qwen
models, pass. AI units remain active; no gateway restart was required.

All **four DriveShares** retain their fingerprint and native SSH settings are
preserved. Checked owner SSH/network policy tests pass before and after tagging.
The applied change adds the owner Drive grant and host `drive:share`, preserves
client `drive:access` and the wildcard network grant, and removes only the exact
obsolete `tag:ninerouter` Funnel attribute. App access is not owner-only.
Taildrop is now disabled by the approved tagging; Taildrive mounts/bookmarks
use native hostname `koija`.

Home/repository capture and idempotent unit replay are complete. Tailscale,
router and Hindsight checks pass; final dotfiles validation covers **861 templates**,
**7 unit links** and no missing values. The earlier Phase 2 guard found zero
issues in **924 files**.
**Remote owner SSH, Taildrive end-to-end access and inference smoke tests were
not run.** See the [owner/file-sharing requirements](.github/context/PROJECT/network-services.md#owner-identity-and-file-sharing).

The root native daemon owns networking and SSH. Starting `9router.service`
pulls in and re-executes the user coordinator to restore private configuration.
Its native readiness wait remains 120 seconds with `TimeoutStartSec=150s`;
failures retry after 15 seconds. Successful oneshot completion normally leaves
`tailscale.service` inactive. The coordinator uses no tailnet API credentials,
provisioning or model/API probes; strict native checks remain required.
Guarded one-off admin provisioning manually approves only
the pinned stable native node; `autoApprovers` stays unchanged. Native Serve
automatically advertises the Service. Clients 1.94+ use Service routes by
default; older Linux clients need individually reviewed `accept-routes`,
without global changes. Temporary one-off migration tooling is not a repository
or startup dependency; replay now validates the captured Service idempotently.
Retired app helpers and unit/endpoints templates are
removed from the repository; snapshot capture excludes obsolete live app artifacts.
The owner template and local identity/data are preserved. Tailnet deletion of
both retired devices and removal of the local instance template and two masks
are complete. See
[retired app cleanup](.github/context/PROJECT/network-services.md#retired-app-cleanup).
The invalid IPset policy is not retried. See
[Tailscale setup and validation](.github/context/PROJECT/network-services.md#tailscale-setup-and-cutover).

Historical Phase 1, 2026-09-10: node-level private HTTPS, gateway/Hindsight
restarts and dependency/health checks passed before rename/tagging. See the
dated report for those checks; no off-tailnet probe is claimed.

The **2026-09-10 22:07 PDT reboot** exposed a Docker/login race: EasyLlama and
PostgreSQL recovered after one restart each, but dependency failures cancelled
9router/Hindsight starts before their restart policies could run. The recovery
change uses shared `readiness.py` waits of up to **180 seconds per attempt** and
`Wants`/`After` ordering so unavailable prerequisites fail the consumer's own
startup and trigger its retry policy. `PartOf` preserves explicit stop/restart
propagation; an intentional stop remains stopped until explicitly started.
This bounds each wait, not total recovery time. Code/security reviews have no
blockers; mock probes, isolated systemd recovery/restart/stop rehearsal and live
health/authentication checks pass. Deployment preserved the three EasyLlama
containers and database container IDs/start times. **No full reboot after the
fix has been performed.**
See [boot recovery](.github/context/PROJECT/network-services.md#boot-recovery)
for readiness gates, timeout budgets and evidence limits.

The baseline gateway uses user `9router.service`; its old GUI autostart is
disabled and `9router-local` starts that unit. Native npm 9router is no longer
a restoration prerequisite. Router identity/configuration bundles remain private;
Git contains placeholders. Preserve skills and private keys in place; Tailscale
capture includes non-secret configuration, never daemon identity/key exports.
The public `services` map in captured `network.json` records both Service
definitions/tags, VIPs, backends and approved stable native node ID.
Historical `retired_device` metadata is removed from the repository template and
home configuration, with the manifest hash updated; retirement history remains
in the documentation. Git captures
non-secret operator metadata; credentials
remain private and use placeholders. Restoring metadata does not
grant external API permission, provision or approve a host. See the
[restoration boundary](.github/context/PROJECT/network-services.md#identity-restoration-boundary).
See [network service operations](.github/context/PROJECT/network-services.md)
for recovery boundaries and the dated verification report.

## Security

See [SECURITY.md](SECURITY.md) for credential protection and pre-commit hook policy.

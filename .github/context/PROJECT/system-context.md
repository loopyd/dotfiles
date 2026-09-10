# System Context

## Purpose

This file is the planning context for:

- system inventory and portability considerations
- installer coverage planning for programs and tools
- recommended user configuration import scope
- proposed bootstrap.sh additions (plan only)

## Update Policy

- Refine this file in place on reiteration.
- Keep findings evidence-based and credential-safe.
- Treat /etc and /usr as read-only inventory references.
- Store plans and recommendations only.
- If this or any context markdown document exceeds 25K tokens, compact it in place while preserving critical facts, source traceability, and canonical policy references.

## Current Status (Compacted)

- `bootstrap.sh` orchestration and the first wave of installer scripts are implemented.
- Overlay capture baseline exists under `root/home/user` for approved non-sensitive config paths.
- Audio/system reproducibility capture moved to intentional one-time refresh (not recurring sync).
- Historical implementation-phase checklists and completed planning inventories were compacted from this file to keep focus on active work.

## Host Customization Scan Continuation (Display/Theme/Background)

### Evidence Boundary

- Scope remains repository-captured overlay/config content only.

### Repository-Observable Findings

1. Display and rendering preferences captured
- `root/home/user/.config/alacritty/alacritty.toml` sets `WINIT_X11_SCALE_FACTOR="1"` and `decorations_theme_variant="Dark"`.

2. Terminal theme state captured
- `root/home/user/.config/kitty/kitty.conf` includes `current-theme.conf`.
- `root/home/user/.config/kitty/current-theme.conf` defines explicit foreground/background palette values.

3. Background path and asset captured
- `root/home/user/.config/kitty/kitty.conf` references `/home/koija/Pictures/termianldragon.png`.
- `root/home/user/Pictures/termianldragon.png` is now present in overlay.

4. User directory and icon defaults captured
- `root/home/user/.config/user-dirs.dirs` pins XDG home subdirectory mappings, including `XDG_PICTURES_DIR`.
- `root/home/user/.local/share/icons/default/index.theme` sets icon inheritance (`Yaru`).

5. MIME associations captured with ephemeral cleanup
- `root/home/user/.config/mimeapps.list` is now tracked for app/scheme associations.
- Ephemeral Discord scheme handler entries were removed to avoid carrying host-specific transient bindings.

6. Desktop-stack hints are indirect
- `root/home/user/Documents/pipewirepatch.qpwgraph` contains `cinnamon:*` node names.
- `root/home/user/.config/autostart/org.rncbc.qpwgraph.desktop` contains `X-GNOME-*` keys.
- These indicate likely Cinnamon/GNOME compatibility, not a definitive desktop-preference export.

### Active Gaps To Close

- Display layout export remains missing because `~/.config/monitors.xml` is not present on host.
- GTK appearance settings remain missing because `~/.config/gtk-3.0/settings.ini` and `~/.config/gtk-4.0/settings.ini` are not present on host.
- Decision is still pending on scripted display/theme export path (targeted `gsettings`/`dconf` key exports).

### Continuation Guidance

- Prefer deterministic export/import scripts for display/theme/background keys.
- Keep `~/.config/dconf/user` and other opaque session/account binary stores excluded.
- Keep wallpaper assets in a deterministic tracked location when intentionally captured.

## Desktop Preference Export/Import Plan (Actionable, Planning-Only)

### Gap State And Newly Observed Inputs

- Host gap remains: `~/.config/monitors.xml` absent.
- Host gap remains: `~/.config/gtk-3.0/settings.ini` and `~/.config/gtk-4.0/settings.ini` absent.
- Deterministic path remains required: targeted `gsettings`/`dconf` key export/import instead of broad DB capture.
- Focused scan additions confirm terminal/default-app and wallpaper folder context:
	- `root/home/user/.config/X-Cinnamon-xdg-terminals.list`
	- `root/home/user/.config/xdg-terminals.list`
	- `root/home/user/.config/cinnamon/backgrounds/user-folders.lst`

### Proposed Script Surfaces

1. `scripts/export-desktop-preferences.sh`
- Reads targeted keys from available schemas/backends.
- Emits deterministic text artifacts under overlay capture paths.
- Does not export opaque binary/session stores.

2. `scripts/import-desktop-preferences.sh`
- Applies only keys that are present in exported artifacts and supported on host.
- Skips unsupported schemas/keys with clear warnings (non-fatal).
- Supports dry-run mode for preview before mutation.

### Scoped Key Sets (Cinnamon/GNOME-Compatible)

- Display/scaling (best-effort):
	- `org.gnome.desktop.interface scaling-factor`
	- `org.gnome.desktop.interface text-scaling-factor`
	- `org.cinnamon.desktop.interface scaling-factor` (if schema exists)
- Interface/theme/icons/cursor/font:
	- `org.gnome.desktop.interface gtk-theme`
	- `org.gnome.desktop.interface icon-theme`
	- `org.gnome.desktop.interface cursor-theme`
	- `org.gnome.desktop.interface font-name`
	- `org.cinnamon.desktop.interface gtk-theme` (if schema exists)
	- `org.cinnamon.desktop.interface icon-theme` (if schema exists)
	- `org.cinnamon.desktop.interface cursor-theme` (if schema exists)
	- `org.cinnamon.desktop.interface font-name` (if schema exists)
- Wallpaper URI/path (primary + dark variant when available):
	- `org.gnome.desktop.background picture-uri`
	- `org.gnome.desktop.background picture-uri-dark` (if key exists)
	- `org.cinnamon.desktop.background picture-uri` (if schema exists)

### Artifact Format And Repository Locations (Text-Only)

- Primary export manifest (canonical key/value map):
	- `root/home/user/.config/repro/desktop-preferences/keys.dconf.ini`
- Metadata and capability record:
	- `root/home/user/.config/repro/desktop-preferences/metadata.env`
	- Includes export timestamp, detected DE/session, available schemas, and skipped keys.
- Optional import report (non-authoritative runtime evidence; if tracked, keep text-only):
	- `root/home/user/.config/repro/desktop-preferences/last-import-report.log`

### Host Detection And Fallback Behavior

- Detect session and available namespaces via environment plus schema introspection:
	- `XDG_CURRENT_DESKTOP`, `DESKTOP_SESSION`, `gsettings list-schemas`.
- Decision matrix:
	- GNOME keys available: export/import GNOME key set.
	- Cinnamon keys available: export/import Cinnamon key set.
	- Both available: prefer DE-native key first, then compatible fallback key where non-conflicting.
	- No supported schemas: no-op with explicit warning and non-zero optional strict mode.
- Missing tools:
	- If `gsettings` missing: hard fail for export/import.
	- If `dconf` missing but `gsettings` present: continue via `gsettings` only.

### Strict Exclusions

- Never capture/import `~/.config/dconf/user` or any dconf binary DB.
- Never capture secrets/session/account/browser stores (ssh, gpg, keyrings, browser profiles, auth/session caches).
- Never export host-derived symlinks or binary launcher artifacts through this preference flow.

### Validation And Rollback/Repair Guidance

1. Validation checklist
- Verify exported artifacts exist and are text-only (`file` reports text for all tracked outputs).
- Verify key round-trip with readback (`gsettings get`) for each imported key.
- Verify wallpaper URI resolves to tracked asset path when asset is intentionally captured.
- Verify terminal/default-app context files remain unchanged unless explicitly in scope.
- Verify unsupported keys are reported but do not abort non-strict imports.

2. Rollback/repair guidance
- Before import, capture pre-import snapshot to `root/home/user/.config/repro/desktop-preferences/pre-import-keys.dconf.ini`.
- On failure/regression, replay pre-import snapshot in deterministic order.
- If display becomes unusable, instruct TTY recovery path: restore prior key snapshot then restart session manager.
- If schema mismatch persists, remove unsupported keys from manifest and re-run import.

## Executor Handoff: Desktop Preference Export/Import

1. Objective
- Implement deterministic desktop preference export/import scripts for Cinnamon/GNOME-compatible hosts using targeted key lists and text-only artifacts.

2. Approved decisions
- Script surfaces: `scripts/export-desktop-preferences.sh` and `scripts/import-desktop-preferences.sh`.
- Scope: display/scaling, theme/icon/cursor/font, wallpaper URI/path.
- Storage: `root/home/user/.config/repro/desktop-preferences/` text artifacts only.
- Exclusions: dconf binary DB and all secret/session/account stores.
- Behavior: schema-aware best-effort mode with optional strict failure mode.

3. Target files
- `scripts/export-desktop-preferences.sh` (new)
- `scripts/import-desktop-preferences.sh` (new)
- `scripts/delib.sh` (only if shared helper additions are required)
- `README.md` (usage notes only if requested by Project Manager)

4. Constraints
- Preserve credential-safe overlay policy and symlink guardrails.
- Keep implementation deterministic and idempotent.
- Do not broaden capture to unrelated DE settings.
- Keep `/etc` and `/usr` treatment as read-only inventory context.

5. Edge cases to cover
- Host has only GNOME schemas, only Cinnamon schemas, both, or neither.
- Keys absent in older/newer schema versions.
- Wallpaper URI points to non-existent asset.
- Import executed in headless/non-graphical session.
- Permission/context mismatch when run under sudo vs user shell.

6. Validation checklist
- `bash -n` passes for touched scripts.
- ShellCheck passes for touched `.sh` scope.
- Export produces deterministic text artifacts with stable key ordering.
- Import readback confirms applied keys where supported.
- Dry-run output accurately reflects intended mutations.

7. Deliverables
- Two scripts with help text and argument parsing (`--dry-run`, `--strict`, `--output` or equivalent).
- Canonical key manifest artifact under `root/home/user/.config/repro/desktop-preferences/`.
- Short implementation note summarizing detected schemas, applied keys, skipped keys, and rollback path.

## Remaining Reconstruction/Refactor Gaps

1. Standards drift in legacy installers
- `scripts/install-blender.sh`, `scripts/install-reaper.sh`, `scripts/install-gidra.sh`, and `scripts/8bitdo.sh` still duplicate helper logic instead of using `scripts/delib.sh` consistently.
- `scripts/8bitdo.sh` still has shell robustness gaps relative to coding standards.

2. Bootstrap phase drift
- Repository/keyring setup is not fully aligned with documented phase intent.
- Dotfiles sync/relink remains intentionally non-default and currently informational.
- Validation coverage is still partial relative to all delegated installers/services.

3. Reproducibility and hardening gaps
- Checksum/digest verification remains inconsistent across archive installers.
- Install/link target normalization (`/usr/bin`, `/usr/local/bin`, `/opt`) is not yet centralized.
- User-state side effects (desktop entries/cache artifacts) are not fully modeled in reconstruction policy.

4. Profile completeness gap
- Default app path still includes heavy GUI installers without a documented minimal/headless baseline and retry policy for partial failures.

## Comprehensive Shell Refactor Handoff (Active)

### Objective

- Consolidate duplicated installer/bootstrap shell logic into `scripts/delib.sh`.
- Keep wrappers generic, reusable, and behavior-preserving.
- Reduce bootstrap branching with shared execution primitives.

### Active Pending Phases

1. Phase 1: additive `delib` API expansion
- Add reusable path-safety, checksum, temp-lifecycle, apt repo/keyring, systemd-gating, and dry-run execution helpers.

2. Phase 2: installer call-site migrations in small batches
- Repo/keyring installers, then archive installers, then remaining system/config installers.

3. Phase 3: bootstrap simplification
- Replace local bootstrap wrappers with shared `delib` wrappers.
- Move installer execution into data-driven phase arrays while preserving current flags/profile behavior.

4. Phase 4: validation and context sync
- Run syntax/lint/dry-run acceptance checks for changed scope.
- Publish one consolidated lint report for touched `.sh`/`.md` files.

### Current Handoff Targets

- `scripts/delib.sh`
- `bootstrap.sh`
- `scripts/8bitdo.sh`
- `scripts/install-blender.sh`
- `scripts/install-core-cli.sh`
- `scripts/install-docker-engine.sh`
- `scripts/install-gh-cli.sh`
- `scripts/install-gidra.sh`
- `scripts/install-git-hooks.sh`
- `scripts/install-neovim-latest.sh`
- `scripts/install-nvidia-container-toolkit.sh`
- `scripts/install-ollama.sh`
- `scripts/install-reaper.sh`

## Overlay/Security Guardrails And Exclusions

- Treat `/etc` and `/usr` as read-only inventory context unless explicitly requested.
- Keep overlay credential-safe: exclude secret-bearing and account/session stores.
- Do not commit host-derived symlinks into overlay; recreate required symlinks/wrappers in bootstrap/scripts.
- Do not commit `~/.local/bin` artifacts or bin-target symlinks.
- Keep launcher capture strict allowlist-only.
- Preserve apt source trust constraints (`signed-by` keyring usage) for managed repository files.
- Keep recurring sync/relink disabled by default; intentional refresh actions must be explicit/manual.

## Active Risks And Assumptions

- Baseline remains Debian/Ubuntu-family by observed apt signals.
- Docker behavior on derivative distributions may diverge from upstream support.
- Some runtime surfaces remain partially observable under non-root scans and should be treated as rebuildable outputs.
- GPU toolkit flow assumes compatible NVIDIA driver presence when enabled.
- Desktop launchers and audio graph files may contain host-specific labels and can require post-restore normalization.
## Template capture expansion (2026-09-10)

The user authorized configuration capture for 9router, terminals, Codex, agents,
Hindsight and the wider home configuration. `templates/manifest.json` now owns
the current captured-file inventory, integrity hashes and exclusions; earlier
allowlists describe the initial baseline. Refresh capture only on explicit request.
See the root README for private-value rendering, transactional 9router restore
and the distinction between configuration recovery and runtime/database backup.

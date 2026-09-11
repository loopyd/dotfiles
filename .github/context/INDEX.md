# Context Index

This index tracks curated research and historical documentation under .github/context.

## Core Context

- coding-standards: [PROJECT/coding-standards.md](PROJECT/coding-standards.md)
- network-services: [PROJECT/network-services.md](PROJECT/network-services.md) - Local AI lifecycle, private restoration and dated migration checks. Retired app artifacts stay excluded; owner template and local identity/data are preserved.
- boot-recovery: [Boot recovery](PROJECT/network-services.md#boot-recovery) - 2026-09-10 22:07 PDT reboot exposed Docker/login dependency cancellation. Shared 180-second readiness waits and consumer retries are deployed; reviews have no blockers, mock/isolated recovery checks and live health/authentication checks pass. EasyLlama/database container IDs and start times are unchanged; no full reboot after the fix performed.
- tailscale-retirement: [Retired app cleanup](PROJECT/network-services.md#retired-app-cleanup) - Both retired tailnet devices, local template/masks and historical capture metadata removed. Final runtime checks pass; renderer validates 861 templates/7 links with no missing values. Local identity/data, native coordinator/daemon and both Services are preserved.
- hindsight-hybrid-memory: [Hybrid memory](../../README.md#hindsight-hybrid-memory) - Knowledge pages first; explicit reflect when justified. `autoReflect: false` skips automatic reflection in the 25-second hook window while SessionStart context, capture, ingestion and `shared` remain enabled. Plugin/tool/server limits: 660000 ms / 720 s / 600 s; a new Codex session or MCP reconnect may be needed.
- hindsight-06b-migration: [Deployment, pins and recovery](PROJECT/network-services.md#hindsight-06b-migration) - 2026-09-11 17:18:21 UTC: all 1,619 batches/19,381 records accepted; processing ONGOING. Unmodified source pin, package still 0.9.2; 0.6B CPU/1024, parallel batch concurrency 2 (not a universal request cap). All ten knowledge pages visible after metadata repair verified at 17:32:48 UTC; page-node mappings are distinct from backing-model mappings. Old DB retained; full restore untested. Early probes are not full-corpus performance proof.
- hindsight-cpu-embedding-trial: [Trial evidence and recovery](PROJECT/network-services.md#hindsight-cpu-embedding-trial) - Historical 8B trial, 2026-09-11: all candidates rolled back to eight CPUs/four slots; services resumed. Isolated gains did not establish loaded reliability. CPU8 and CPU16 both fail the batch-versus-single gate; matched-batch and retrieval validation remain required. GPU vector drift prevents promotion; no RAM savings retained.
- hindsight-private-https: [Access, provisioning and replay](PROJECT/network-services.md#hindsight-private-https) - VERIFIED 2026-09-10 (PDT): `svc:hindsight` / `tag:hindsight`, only native `koija` manually approved/ready; exact VIP DNS, trusted TLS, access-key authentication and idempotent replay pass. API/database loopback-only; ACLs/autoApprovers unchanged. HTTPS tested from this host over the VIP, not a second device; remote SSH/Taildrive untested.
- tailscale-setup: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover) - Phase 2 COMPLETE, verified 2026-09-10: stable native `koija` / `tag:ssh`; `svc:ninerouter` / `tag:ninerouter`, only native host manually approved. Service VIP DNS, TLS, dashboard/API and 66 models verified; no Funnel or gateway restart. Broad network grant unchanged.
- tailscale-identity: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing) - Stable identity/keys, SSH settings and four DriveShares fingerprints preserved; checked owner SSH/network policy tests pass. Drive grant/attributes applied. Taildrop disabled; paths use `koija`. Remote SSH/Taildrive end-to-end access not run.
- tailscale-private-values: [Restoration boundary](PROJECT/network-services.md#identity-restoration-boundary) - Public `services` map captures both definitions/tags, VIPs and approved stable native node ID; historical `retired_device` metadata is removed. Snapshot preserves authored restoration overrides and canonical credential markers, excluding live trust caches/runtime noise. Admin reprovisioning/approval stay separate from credential-free startup; no broader auto-approval or key export.
- herdr-codex: [Herdr and Alacritty](../../README.md#herdr-and-alacritty) - Codex v8 hook/script restoration and future capture; previous live installation reports current. Fresh session inside Herdr required; UI untested.
- lifecycle: [PROJECT/coding-standards.md#lifecycle-interface](PROJECT/coding-standards.md#lifecycle-interface) - Noun commands, action dispatch, pinned builds and guarded removal; [usage](../../README.md#lifecycle-commands).
- system-context: [PROJECT/system-context.md](PROJECT/system-context.md)
- system-context-audio-repro-pass: [PROJECT/system-context.md](PROJECT/system-context.md) - 2026-04-06 audio/system reproducibility inventory and source-to-overlay mapping.
- system-context-display-theme-background-pass: [PROJECT/system-context.md](PROJECT/system-context.md) - 2026-04-06 overlay-observable display/theme/background reproducibility scan with explicit assumptions.
- security-policies: [PROJECT/security-policies.md](PROJECT/security-policies.md)

## Subject Catalog

- hindsight-preparation-evidence: [Backup and recovery](PROJECT/network-services.md#backup-and-recovery) - Initial 48-file backup later supplemented by frozen dump/manifest and six hashed recovery exports. Exact image recovery requires archive plus matching receipt; [persistent benchmarks and early assessment](PROJECT/network-services.md#model-and-standalone-evidence) qualify measured gains.

- docker-engine: [docker-engine/ubuntu-install.md](docker-engine/ubuntu-install.md) - Ubuntu apt repository setup, install sequence, and security caveats.
- nvidia-toolkit: [nvidia-toolkit/install-config.md](nvidia-toolkit/install-config.md) - NVIDIA toolkit installation and Docker runtime configuration guidance.
- github-cli: [github-cli/linux-install.md](github-cli/linux-install.md) - Official Linux installation path and discouraged package channels.
- ollama: [ollama/linux-install-service.md](ollama/linux-install-service.md) - Install modes, service operation, and version pinning controls.
- neovim: [neovim/source-build.md](neovim/source-build.md) - Latest-from-source build flow and reproducibility controls.
- repro-security: [repro-security/policies.md](repro-security/policies.md) - Policy-level references for apt trust, privilege boundaries, and workflow security posture.

## Maintenance Rules

- Keep entries concise and searchable.
- Keep this index synchronized with GLOSSARY.md and subject folders.

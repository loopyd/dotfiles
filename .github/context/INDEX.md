# Context Index

This index tracks curated research and historical documentation under .github/context.

## Core Context

- coding-standards: [PROJECT/coding-standards.md](PROJECT/coding-standards.md)
- network-services: [PROJECT/network-services.md](PROJECT/network-services.md) - Local AI lifecycle and private restoration; Phase 2 capture, unit replay and Tailscale/router/Hindsight checks pass. Retired app artifacts stay excluded; owner template and local identity/data are preserved.
- tailscale-retirement: [Retired app cleanup](PROJECT/network-services.md#retired-app-cleanup) - Both retired tailnet devices, local template/masks and historical capture metadata removed. Final runtime checks pass; renderer validates 861 templates/7 links with no missing values. Local identity/data, native coordinator/daemon and both Services are preserved.
- hindsight-private-https: [Access, provisioning and replay](PROJECT/network-services.md#hindsight-private-https) - VERIFIED 2026-09-10 (PDT): `svc:hindsight` / `tag:hindsight`, only native `koija` manually approved/ready; exact VIP DNS, trusted TLS, access-key authentication and idempotent replay pass. API/database loopback-only; ACLs/autoApprovers unchanged. HTTPS tested from this host over the VIP, not a second device; remote SSH/Taildrive untested.
- tailscale-setup: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover) - Phase 2 COMPLETE, verified 2026-09-10: stable native `koija` / `tag:ssh`; `svc:ninerouter` / `tag:ninerouter`, only native host manually approved. Service VIP DNS, TLS, dashboard/API and 66 models verified; no Funnel or gateway restart. Broad network grant unchanged.
- tailscale-identity: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing) - Stable identity/keys, SSH settings and four DriveShares fingerprints preserved; checked owner SSH/network policy tests pass. Drive grant/attributes applied. Taildrop disabled; paths use `koija`. Remote SSH/Taildrive end-to-end access not run.
- tailscale-private-values: [Restoration boundary](PROJECT/network-services.md#identity-restoration-boundary) - Public `services` map captures both definitions/tags, VIPs and approved stable native node ID; historical `retired_device` metadata is removed. Snapshot preserves authored restoration overrides and canonical credential markers, excluding live trust caches/runtime noise. Admin reprovisioning/approval stay separate from credential-free startup; no broader auto-approval or key export.
- lifecycle: [PROJECT/coding-standards.md#lifecycle-interface](PROJECT/coding-standards.md#lifecycle-interface) - Noun commands, action dispatch, pinned builds and guarded removal; [usage](../../README.md#lifecycle-commands).
- system-context: [PROJECT/system-context.md](PROJECT/system-context.md)
- system-context-audio-repro-pass: [PROJECT/system-context.md](PROJECT/system-context.md) - 2026-04-06 audio/system reproducibility inventory and source-to-overlay mapping.
- system-context-display-theme-background-pass: [PROJECT/system-context.md](PROJECT/system-context.md) - 2026-04-06 overlay-observable display/theme/background reproducibility scan with explicit assumptions.
- security-policies: [PROJECT/security-policies.md](PROJECT/security-policies.md)

## Subject Catalog

- docker-engine: [docker-engine/ubuntu-install.md](docker-engine/ubuntu-install.md) - Ubuntu apt repository setup, install sequence, and security caveats.
- nvidia-toolkit: [nvidia-toolkit/install-config.md](nvidia-toolkit/install-config.md) - NVIDIA toolkit installation and Docker runtime configuration guidance.
- github-cli: [github-cli/linux-install.md](github-cli/linux-install.md) - Official Linux installation path and discouraged package channels.
- ollama: [ollama/linux-install-service.md](ollama/linux-install-service.md) - Install modes, service operation, and version pinning controls.
- neovim: [neovim/source-build.md](neovim/source-build.md) - Latest-from-source build flow and reproducibility controls.
- repro-security: [repro-security/policies.md](repro-security/policies.md) - Policy-level references for apt trust, privilege boundaries, and workflow security posture.

## Maintenance Rules

- Keep entries concise and searchable.
- Keep this index synchronized with GLOSSARY.md and subject folders.

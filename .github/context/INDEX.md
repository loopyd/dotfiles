# Context Index

This index tracks curated research and historical documentation under .github/context.

## Core Context

- coding-standards: [PROJECT/coding-standards.md](PROJECT/coding-standards.md)
- network-services: [PROJECT/network-services.md](PROJECT/network-services.md) - Local AI lifecycle and private restoration; gateway/Hindsight restarts and health checks pass. Retired app helpers/templates are removed; snapshot excludes obsolete live app artifacts. Owner template, home state and masks stay.
- tailscale-setup: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover) - Phase 1 complete, Verified 2026-09-10: native `ninerouter` dashboard and `/v1` use private HTTPS 443 via loopback 20128; Funnel off in native config. Native `koija` + Services VIP remains pending the tagged-host/Taildrop choice.
- tailscale-identity: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing) - Four DriveShares compared exactly in memory, never exported. Future tagging needs host `drive:share`, client `drive:access` and owner wildcard read/write capability; rename changes mount/bookmark paths. Pending choice; external SSH untested.
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

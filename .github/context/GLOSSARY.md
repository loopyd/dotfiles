# Glossary

Concise repository terms used across .github/context.

## bootstrap

- Meaning: Repository setup orchestration flow and related install stages.
- References: [PROJECT/system-context.md](PROJECT/system-context.md), [PROJECT/coding-standards.md](PROJECT/coding-standards.md)

## overlay

- Meaning: Rebuildable filesystem/config snapshot captured in repository structure.
- References: [PROJECT/system-context.md](PROJECT/system-context.md)

## lifecycle command

- Meaning: Noun-named component entry point with install, update, uninstall and read-only check actions, coordinated by bootstrap.
- References: [PROJECT/coding-standards.md#lifecycle-interface](PROJECT/coding-standards.md#lifecycle-interface)

## payload receipt

- Meaning: Local installation record used to refuse unmanaged, modified or dependency-cascading removal while preserving configuration and persistent data.
- References: [PROJECT/coding-standards.md#lifecycle-interface](PROJECT/coding-standards.md#lifecycle-interface)

## private identity export

- Meaning: Fixed-allowlist router identity/configuration capture into private values; only placeholders enter Git. Tailscale daemon identity/SSH keys stay in place and are never exported or copied.
- References: [Network identity boundary](PROJECT/network-services.md#identity-restoration-boundary)

## Tailscale Services

- Meaning: Phase 2 COMPLETE, verified 2026-09-10: native `koija` / `tag:ssh` hosts `svc:ninerouter` / `tag:ninerouter`, private HTTPS 443 to `127.0.0.1:20128`, with no Funnel. Only the stable native node is manually approved; Service VIP DNS and TLS/dashboard/API checks pass. The broad network grant remains; app access is not owner-only.
- References: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover)

## Private HTTPS conversion

- Meaning: Historical Phase 1, verified 2026-09-10: private node-level HTTPS replaced Funnel on personal native `ninerouter`. Phase 2 retains the origin through a Service VIP after the native rename to `koija`; no off-tailnet probe or inference smoke test is claimed.
- References: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover)

## Native hostname and SSH host

- Meaning: Native `koija` / `tag:ssh` retains its stable ID, identity keys and SSH settings. Original-owner SSH to local user `koija` uses `action: check`; policy tests pass before and after tagging. Remote owner SSH login was not run.
- References: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing)

## Original-owner pin

- Meaning: Privately retained, verified owner metadata needed before host tagging replaces user ownership with tag identity. It is neither a credential nor a transferable daemon identity and does not itself grant access.
- References: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing)

## Taildrop and Taildrive

- Meaning: Taildrop is disabled by the approved tagging; Taildrive mount/bookmark paths use `koija`. All four DriveShares retain their in-memory fingerprint without export. Host `drive:share`, client `drive:access`, and original-owner → `tag:ssh` capability `tailscale.com/cap/drive` with `shares: ["*"]`, `access: "rw"` preserve policy access. Remote Taildrive end-to-end access was not run.
- References: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing)

## Native coordinator

- Meaning: User service restoring reviewed private configuration through root-owned native `tailscaled.service`. Gateway start re-executes it; Phase 2 unit replay idempotently validates the captured Service. Startup has no API credentials, provisioning, extra userspace daemons or API/model probes. Admin reprovisioning and approval are separate; no full login test is claimed.
- References: [Runtime lifecycle](PROJECT/network-services.md#runtime-lifecycle)

## Retired Tailscale app nodes

- Meaning: Old userspace nodes remain masked/offline with home identity state preserved. Retired app helpers and unit/endpoints templates are removed from the repository and obsolete live app artifacts are excluded from snapshot capture; the owner template and home masks stay. The rejected IPset policy is not retried.
- References: [Verification and remaining work](PROJECT/network-services.md#verification-and-remaining-work)

## Private per-service values

- Meaning: Captured `network.service` metadata includes the exact definition/tags, VIP addresses and approved stable node ID alongside listeners/backends. Git captures this non-secret operator metadata and credential placeholders, not credentials. Metadata is not authorization; external API permission, admin reprovisioning and manual approval remain separate from startup, without broader auto-approval.
- References: [Network identity boundary](PROJECT/network-services.md#identity-restoration-boundary)

## symlink policy

- Meaning: Host-derived symlinks are not stored in overlay; recreate via scripts/bootstrap.
- References: [PROJECT/system-context.md](PROJECT/system-context.md), [repro-security/policies.md](repro-security/policies.md)

## severity gate

- Meaning: High/medium/low review blocking policy used by manager/reviewer/security agents.
- References: [PROJECT/coding-standards.md](PROJECT/coding-standards.md), [repro-security/policies.md](repro-security/policies.md)

## shared installer library

- Meaning: Common installer helper functions stored in scripts/delib.sh.
- References: [PROJECT/coding-standards.md](PROJECT/coding-standards.md)

## signed-by keyring

- Meaning: APT source constraint that binds a repository to a specific keyring file for signature verification.
- References: [repro-security/policies.md](repro-security/policies.md), [docker-engine/ubuntu-install.md](docker-engine/ubuntu-install.md), [github-cli/linux-install.md](github-cli/linux-install.md), [nvidia-toolkit/install-config.md](nvidia-toolkit/install-config.md)

## rootless mode

- Meaning: Running container tooling without root privileges, with alternate runtime configuration paths and limits.
- References: [docker-engine/ubuntu-install.md](docker-engine/ubuntu-install.md), [nvidia-toolkit/install-config.md](nvidia-toolkit/install-config.md)

## runtime configure

- Meaning: Post-install engine integration step using `nvidia-ctk` to register NVIDIA runtime support for container engines.
- References: [nvidia-toolkit/install-config.md](nvidia-toolkit/install-config.md)

## service-first mode

- Meaning: Operating a tool as a managed systemd service by default instead of ad-hoc foreground commands.
- References: [ollama/linux-install-service.md](ollama/linux-install-service.md)

## source pinning

- Meaning: Building from a specific upstream tag/version instead of moving branches to keep installs reproducible.
- References: [neovim/source-build.md](neovim/source-build.md), [repro-security/policies.md](repro-security/policies.md)

## carxp project

- Meaning: Carla project/preset file used to persist plugin graph and parameter state for reproducible audio routing.
- References: [PROJECT/system-context.md](PROJECT/system-context.md)

## qpwgraph patch

- Meaning: PipeWire patch graph file format used to persist node/port wiring for session reproducibility.
- References: [PROJECT/system-context.md](PROJECT/system-context.md)

## apt pinning

- Meaning: APT package priority policy defined in preferences files to constrain package origin/selection behavior.
- References: [PROJECT/system-context.md](PROJECT/system-context.md), [repro-security/policies.md](repro-security/policies.md)

## in-place compaction

- Meaning: Context markdown maintenance rule requiring documents over 25K tokens to be compacted in place rather than split into duplicative notes.
- References: [PROJECT/coding-standards.md](PROJECT/coding-standards.md), [PROJECT/system-context.md](PROJECT/system-context.md)

## desktop preference export

- Meaning: Script-managed capture of selected display/theme/background settings for reproducibility, instead of committing opaque desktop preference databases.
- References: [PROJECT/system-context.md](PROJECT/system-context.md)

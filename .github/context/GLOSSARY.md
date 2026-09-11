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

- Meaning: Proposed native kernel service hosting with a separate `ninerouter:443` VIP proxying loopback Docker port 20128. Requires a tagged host; native `koija` rename, tagging and Service activation await the user's personal-identity decision and final tests.
- References: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover)

## Private HTTPS conversion

- Meaning: Completed Phase 1 on personal native `ninerouter`: dashboard and `/v1` share private HTTPS 443 through loopback 20128, with Funnel off in native configuration. Verified 2026-09-10; no off-tailnet probe or inference test claimed.
- References: [Setup and cutover](PROJECT/network-services.md#tailscale-setup-and-cutover)

## Native hostname and SSH host

- Meaning: Current native node is personal `ninerouter`; later `koija` / `tag:ssh` is pending the identity decision. Preserve original-owner SSH to local user `koija`, using `action: check` for the tagged-host rule. External SSH login has not been tested.
- References: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing)

## Original-owner pin

- Meaning: Privately retained, verified owner metadata needed before host tagging replaces user ownership with tag identity. It is neither a credential nor a transferable daemon identity and does not itself grant access.
- References: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing)

## Taildrop and Taildrive

- Meaning: Taildrop is unavailable on tagged hosts. Phase 1 preserved all four DriveShares by in-memory fingerprint comparison without exporting definitions. Future tagging requires host `drive:share`, client `drive:access`, and owner → `tag:ssh` capability `tailscale.com/cap/drive` with wildcard read/write access. Rename changes mount/bookmark paths; tagging remains pending choice and untested.
- References: [Owner identity and file sharing](PROJECT/network-services.md#owner-identity-and-file-sharing)

## Native coordinator

- Meaning: User service restoring private configuration through root-owned native `tailscaled.service`. Phase 1 pulls it in and re-executes it when `9router.service` starts, without extra userspace daemons or startup API/model calls. This dependency check is not a full login test.
- References: [Runtime lifecycle](PROJECT/network-services.md#runtime-lifecycle)

## Retired Tailscale app nodes

- Meaning: Old userspace nodes remain masked/offline with home identity state preserved. Retired app helpers and unit/endpoints templates are removed from the repository and obsolete live app artifacts are excluded from snapshot capture; the owner template and home masks stay. The rejected IPset policy is not retried.
- References: [Verification and remaining work](PROJECT/network-services.md#verification-and-remaining-work)

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

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

- Meaning: Explicit fixed-allowlist capture into private renderer values; only placeholders enter Git.
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

# Reproducibility Security Policies

## Why this exists

- Provide one policy subject for reproducibility-security terms used in the glossary.
- Keep installer and overlay workflows aligned with canonical project guardrails.

## Policy references by glossary term

- signed-by keyring: require per-repository keyrings and `signed-by`/`Signed-By`
  source constraints for third-party apt repositories.
- apt pinning: keep `preferences.d` priority rules explicit and tracked for
  deterministic package-source selection.
- source pinning: prefer pinned release tags and explicit checksum variables for
  archive/source install paths.
- symlink policy: do not commit host-derived symlinks or user bin artifacts;
  recreate required links through bootstrap/install logic.
- severity gate: treat high findings as blocking and medium findings as
  blocking unless explicitly deferred by manager policy.

## Canonical internal references

- Project policy baseline: [PROJECT/security-policies.md](../PROJECT/security-policies.md)
- Operational mapping context: [PROJECT/system-context.md](../PROJECT/system-context.md)
- Standards and severity policy: [PROJECT/coding-standards.md](../PROJECT/coding-standards.md)

## Sources

- https://manpages.ubuntu.com/manpages/noble/en/man8/apt-secure.8.html
- https://docs.docker.com/engine/install/ubuntu/
- https://docs.docker.com/engine/install/linux-postinstall/
- https://github.com/cli/cli/blob/trunk/docs/install_linux.md

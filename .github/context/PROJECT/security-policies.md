# Reproducibility and Security Policy References

## Why this exists

- Centralize policy-level external guidance that affects installer design.
- Keep shell automation aligned with apt trust and least-privilege realities.

## APT repository trust baseline

- Prefer dedicated keyring files and source entries with `Signed-By`.
- Do not rely on unsigned repositories.
- Treat repository auth failures as blocking unless explicitly risk-accepted.

## Privilege model reminders

- Docker group membership grants root-level privileges on the host.
- Service users should be non-login and least privilege.

## Installer method guidance

- Prefer official apt repositories over unofficial community mirrors for core
  tools.
- Prefer package-manager flows over convenience scripts when reproducibility is
  a primary goal.
- If convenience scripts are used, inspect script content and pin explicit
  versions where supported.

## Repository guardrail alignment

- Keep sensitive paths out of overlays and context summaries.
- Avoid host-derived symlink capture in repository overlays.
- Preserve idempotent installer behavior and explicit failure on missing trust
  prerequisites.

## Sources

- https://manpages.ubuntu.com/manpages/noble/en/man8/apt-secure.8.html
- https://docs.docker.com/engine/install/linux-postinstall/
- https://docs.docker.com/engine/install/ubuntu/
- https://github.com/cli/cli/blob/trunk/docs/install_linux.md

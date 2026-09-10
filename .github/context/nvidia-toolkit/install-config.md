# NVIDIA Container Toolkit

## Why this exists

- Track the official install and runtime configuration path for NVIDIA GPUs with
  containers.
- Capture caveats that affect reliability in day-to-day use.

## Install flow (Ubuntu or Debian)

1. Confirm NVIDIA driver is installed and working (`nvidia-smi`).
2. Add NVIDIA keyring and apt repository list from `libnvidia-container`.
3. Install toolkit packages.
4. Configure Docker runtime via `nvidia-ctk runtime configure --runtime=docker`.
5. Restart Docker.

## Runtime configuration notes

- Rootful Docker:
  - `sudo nvidia-ctk runtime configure --runtime=docker`
  - `sudo systemctl restart docker`
- Rootless Docker has a separate config path under user config and may require
  `nvidia-container-cli.no-cgroups` tuning.

## Reliability caveat

- NVIDIA documents a known issue where `systemctl daemon-reload` on systems
  using systemd cgroup drivers may cause containers to lose GPU access.
- Keep this as a troubleshooting checkpoint after daemon or unit reload events.

## Repository fit notes

- `scripts/install-nvidia-container-toolkit.sh` follows the documented apt
  keyring + repo + `nvidia-ctk` runtime configure flow.
- Optional package version pinning is available upstream and can improve
  reproducibility across hosts.

## Sources

- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/troubleshooting.html

# Ollama on Linux

## Why this exists

- Capture supported install modes and service management choices.
- Keep host setup reproducible while still allowing fast local onboarding.

## Supported install modes

- Script mode:
  - `curl -fsSL https://ollama.com/install.sh | sh`
- Manual mode:
  - Download architecture tarball and extract under `/usr`.
  - Optional ROCm package for AMD GPUs.

## Service model guidance

- Recommended durable mode is a systemd service with dedicated `ollama` user.
- Manual docs include a service unit pattern using:
  - `ExecStart=/usr/bin/ollama serve`
  - `User=ollama`
  - `Group=ollama`
- Service overrides should be done with `systemctl edit ollama`.

## Reproducibility notes

- Script mode supports `OLLAMA_VERSION` to pin exact versions.
- Manual install allows explicit artifact URL pinning per architecture.
- Log review path: `journalctl -e -u ollama` when running as service.

## Repository fit notes

- `scripts/install-ollama.sh` exposes both script and manual modes.
- Default behavior aligns with service-first operation and includes user
  creation plus service enable/start.

## Sources

- https://docs.ollama.com/linux
- https://github.com/ollama/ollama/blob/main/README.md

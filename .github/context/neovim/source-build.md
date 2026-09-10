# Neovim Latest From Source

## Why this exists

- Track a reliable latest-from-source flow for Linux hosts.
- Document practical reproducibility controls for moving targets.

## Build flow

1. Install Neovim build prerequisites (see `BUILD.md`).
2. Clone or fetch upstream repository and tags.
3. Checkout explicit tag.
4. Build with `make CMAKE_BUILD_TYPE=Release`.
5. Install with `make install` (default prefix `/usr/local`).

## Reproducibility controls

- Prefer explicit tags over branch heads.
- Record selected tag in logs or installer output.
- Optionally set install prefix (`CMAKE_INSTALL_PREFIX`) to isolate updates.
- Rebuild from clean state (`distclean` or clean build dir) before install.

## Provider note

- Python provider support uses `pynvim`.
- Upstream install docs recommend modern tooling (for example `uv`) to install
  provider packages.

## Repository fit notes

- `scripts/neovim.sh` follows the tag checkout + source build
  pattern and validates installed version.

## Sources

- https://github.com/neovim/neovim/blob/master/INSTALL.md
- https://github.com/neovim/neovim/blob/master/BUILD.md

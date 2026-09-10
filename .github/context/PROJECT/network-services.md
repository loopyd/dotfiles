# 9router and Tailscale

## Service Ownership

- `router.sh install|update|uninstall|check` manages the user `9router.service`
  and official Docker image through `~/.config/9router/compose.yaml`.
- `tailscale.sh install|update|uninstall|check` manages the user exposure-check
  unit while retaining the native system `tailscaled.service`. Fresh Ubuntu/Mint
  installs use Tailscale's signed apt repository; update may restart that daemon.
- `bootstrap.sh <action> --with-network` selects both. With `--only
  tailscale,router`, Docker is added for install/update; Tailscale precedes the
  gateway (also selected automatically for `--only router` install/update), and
  removal reverses that order. Hindsight follows the gateway when
  selected. No harness/model process is launched.

## Preserved Configuration

- The gateway image is version 0.5.69, pinned by manifest digest. CPU quota is
  **2 CPUs** and `/dev/shm` is **4 GiB**. Host networking preserves the existing
  bind on port 20128, including its current LAN accessibility.
- The existing `~/.9router` store is bind-mounted, not copied: SQLite, provider
  credentials, JWT secret, machine identity and certificates remain in place.
  `runtime.env` retains the existing 600-second swap-aware timeouts.
- Routine install/update preserves an existing database and its current identity
  files, including renewed certificates. Captured identity files are used only
  for a missing database; explicit identity restoration refuses differing files.
- Native Tailscale keeps the same node, addresses, SSH, operator and preferences.
  HTTPS/Funnel on `ninerouter.tailc28ab1.ts.net:443` continues to proxy
  `http://127.0.0.1:20128`. This is existing **public Funnel exposure**, not a new
  private-only Serve endpoint. No additional ports or Funnel endpoints are added.
- The container uses the existing Tailscale socket and CLI via read-only mounts.
  It does not run another `tailscaled` or change the tailnet's control-plane ACLs.

## Deployment And Recovery

1. Render configuration and run both commands with `--dry-run` first.
2. `router.sh install --no-start` stages helpers, image and login unit without
   stopping the native process. A missing database is initialized in a disposable
   network-isolated container, then populated transactionally from the private
   table export before exposure. Existing databases are never re-imported by install.
   The user unit refuses startup without a nonempty database, including after an
   interrupted installation.
3. Plan a brief maintenance cutover, record the native process/launcher and
   preserve a private database recovery point before stopping it. The installer
   refuses to activate while an unmanaged process owns port 20128.
4. Start `9router.service`; run `router.sh check` and `tailscale.sh check`. Only
   after success disable the old GUI login autostart to prevent double ownership.
5. On failure stop and disable the user service and restore the previous native
   launcher/autostart. Never run both gateways against the database concurrently.

Live cutover completed on 2026-09-10. Both user units are enabled/active; the
container is healthy, authenticated discovery preserves 66 models and both Qwen
IDs, chat and embeddings pass, and local/Funnel dashboard routes still require
login. The native npm binary
is retained only for rollback; the versionless package restore no longer installs
it. The private SQLite/launcher recovery point is under
`~/.local/state/9router/cutover-20260910T205650Z/`. No upstream source was edited.

Router uninstall stops its Compose project but preserves all data/configuration.
Tailscale uninstall removes only the user exposure-check helper/unit activation;
it deliberately leaves the native daemon, keys and live network online. No command
resets Serve/Funnel, logs out, rotates credentials or removes database volumes.

## Identity Restoration Boundary

Non-secret network settings are captured in `~/.config/tailscale/network.json`.
That file alone cannot recreate the same device identity on another installation.
An optional private `identity.json` contains a `files` field encoding a JSON map
of relative paths to base64 file contents; it belongs outside Git. Router files
are relative to `~/.9router`; Tailscale files are relative to `/var/lib/tailscale`.
Never put actual bundles or credential values in Markdown, Git, logs or Hindsight.

The original broad export was refused; explicit user authorization and a narrower
fixed allowlist replaced it. `python3 scripts/identity.py capture` exports exactly
eight router identity/certificate files, nine Tailscale device/SSH/certificate
files, and six named router configuration tables. Inputs are bounded, regular and
non-symlinked. Root-owned state is read through a network-isolated, read-only
container with logging disabled. Only an atomic 0600 replacement of
`~/.config/dotfiles/values.json` receives credential contents; no Git writes,
uploads or secret output occur. Its directory must be private, outside Git.

`SECRET_ROUTER_IDENTITY`, `SECRET_TAILSCALE_IDENTITY` and `SECRET_ROUTER_TABLES`
are opaque base64 JSON bundles, **not encryption**. Protect and transfer the values
file privately. Normal rendering materializes private identity/restore JSON files
in the destination home. Format-2 table restoration preserves raw SQL field
values, including account tokens; format 1 remains readable. Revoked/expired
provider sessions or Tailscale identities still require provider-side renewal.

General `snapshot.py` refresh preserves these reviewed templates and their private
values without re-reading identity bundles or silently downgrading the table
export. Refresh the fixed allowlist explicitly after credential changes; logs,
request history, caches, Taildrop files and unrelated accounts are never included.

`tailscale.py identity --home <destination-home>` is an explicit root-only restore
operation. Stop the native daemon first; existing differing files are refused.
Do not clone the captured device identity onto a second simultaneously running
node. The native daemon loads preserved identity/preferences on startup; the user
unit verifies the node and preferences before applying any captured exposure.

On a replacement machine, render privately, install native Tailscale, stop its
system daemon, then run `sudo python3 scripts/tailscale.py identity --home "$HOME"`.
Install the rendered `.config/tailscale/default.env` as `/etc/default/tailscaled`
before restarting the daemon; it preserves the captured UDP port and flags.
Only then install/start the user exposure-check and router units. The installer
fails closed on a different node or nonmatching exposure rather than enrolling,
logging out or resetting a device. This root restoration was not run on the live
machine, whose original daemon/state remain in place.

## Sources

- [Official 9router container definitions](https://github.com/decolua/9router/blob/master/docker-compose.yml)
- [Official 9router Dockerfile](https://github.com/decolua/9router/blob/master/Dockerfile)
- [Tailscale Linux packages](https://pkgs.tailscale.com/stable/)
- [Tailscale Serve/Funnel usage](https://tailscale.com/kb/1247/funnel-serve-use-cases)
- Installed `tailscale serve --help`, `tailscale funnel --help` and read-only
  status/preferences established the currently supported commands and exposure.

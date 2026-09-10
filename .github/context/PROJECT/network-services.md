# Local AI Services and Tailscale

## Service Ownership

- `easyllama.sh install|update|uninstall|check` manages the captured Qwen Docker
  stack through a user supervisor; install can adopt matching running containers
  without restarting models. Update restarts the stack and active consumers.
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

Bootstrap selects Docker/NVIDIA → EasyLlama → 9router → Hindsight for the captured
local AI stack; Tailscale precedes 9router and PostgreSQL precedes Hindsight.
User-unit `Requires`, `After` and `PartOf` contracts propagate upstream stop/restart
to active consumers. Database data and its independent unit remain intact.

## EasyLlama Snapshot

- Source release: **0.6.0**, revision
  `94166edbd5e74a9e89741d889483b12bdb82907c` from
  [EasyLlama](https://github.com/loopyd/easyllama/tree/94166edbd5e74a9e89741d889483b12bdb82907c).
  Exact local image IDs, not mutable tags or floating upstream branches, determine
  the deployed binaries. The image inventory is `deployment.json`.
- `~/.config/easyllama` contains the original JSON configuration, all five mode
  profiles, three chat templates, the effective Qwen proxy configuration and
  Compose deployment. Only the captured **Qwen** stack is activated; the JSON's
  old default `llamacpp` mode is archival, not the service selector.
- `EASYLLAMA_ROOT` is a private-renderer path value pointing to the existing
  `/mnt/LIBRARY/llamacpp` data root. Change it for a replacement machine, create
  the directory, then render. Existing caches/models are reused, never copied to
  Git, cleaned, replaced or silently relocated. Referenced weights must be
  restored privately or downloaded by the existing backend as needed.
- Captured resource allocations are retained: proxy 2 CPUs/8 GiB memory and
  backend 24 CPUs/62.5 GiB memory, with 64 MiB shared memory per container.
  These are EasyLlama's existing GPU-workload limits, not Hindsight/9router's
  separate 2-CPU/4-GiB-shared-memory limits. NVIDIA GPU access and host networking
  remain unchanged; the proxy listens on loopback port 8080.
- The supervisor verifies exact image IDs, commands, environment, mounts and
  limits before adopting containers. It replaces Docker restart policy with
  systemd ownership, stops only the verified three containers on shutdown, and
  restarts on container failure. No upstream EasyLlama source is edited and no
  native Python/Torch environment is installed.
- A private adoption journal records immutable IDs and original running/restart
  states before mutation. New containers are created without starting, labeled
  with the invocation and recorded before startup. Failed/interrupted adoption
  restores the previous workload; cleanup/readiness are invocation-bound and
  serialized. Failed recovery retains its journal for the next attempt. Model
  chat templates retain their exact pinned bytes, including terminal newlines.

These custom images are **not publicly pullable release artifacts**. On the
source machine, explicitly save them outside Git:

```bash
python3 scripts/easyllama.py archive --directory "$HOME/.local/share/easyllama/images"
```

Transfer that private directory to the destination, render configuration, then:

```bash
bash scripts/easyllama.sh install --images-dir "$HOME/.local/share/easyllama/images"
```

Install skips imports when both image IDs already exist; otherwise it loads only
the named archives and verifies image IDs afterward. It never pulls a substitute
or rebuilds floating source. Archive export is explicit because images are large;
model weights and the Hindsight database need separate backups. Uninstall stops
the service and removes its receipt-owned helper, preserving containers, images,
configuration and data. Do not concurrently use upstream `run.sh start/stop`.

Profiles are captured evidence; changing them alone does not regenerate the
effective Docker command/proxy snapshot. Stop the stack and regenerate/review
those artifacts before deploying profile changes. Routine snapshot refresh keeps
the data-root placeholder and chat templates portable.

Live verification on 2026-09-10: the EasyLlama user unit adopted all three existing
containers with unchanged IDs/start timestamps. EasyLlama, 9router, PostgreSQL and
Hindsight user units are active and enabled; authenticated Hindsight health passes
and anonymous API/dashboard data access remains rejected. Image archives were not
exported automatically; the explicit archive command remains the transfer step
for a fresh host without these locally built images.

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

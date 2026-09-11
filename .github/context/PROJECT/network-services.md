# Local AI Services and Tailscale

**Phase 2: COMPLETE — verified 2026-09-10.** The native node retains its stable
ID and identity keys as `koija.tailc28ab1.ts.net` with `tag:ssh`.
`svc:ninerouter`, tagged `tag:ninerouter`, serves private HTTPS 443 through
`127.0.0.1:20128`, with only that native node manually approved as its host.
The dashboard/API origin remains `ninerouter.tailc28ab1.ts.net`; DNS resolves
to captured Service VIPs, not the native IP. Funnel is off.

All **four DriveShares** retain their fingerprint and native SSH settings are
preserved. Tagging disables Taildrop; the user accepted that loss and Taildrive
mount/bookmark changes to `koija`. The broad network grant remains unchanged,
so app access is not owner-only. Home/repository capture and unit replay/checks
are complete. Remote owner SSH and Taildrive end-to-end access remain untested.

Old userspace app nodes remain masked/offline with their state preserved.
Repository cleanup is complete: `scripts/tailnet.py`, `scripts/tailserve.py`,
and retired app unit/endpoints templates are removed. The owner template and
home state/masks remain; snapshot capture excludes obsolete live app unit and
endpoints artifacts.
The rejected IPset policy is not a recovery recipe and must not be retried.
The dated historical reports below describe the earlier baseline.

## Service Ownership

- `easyllama.sh install|update|uninstall|check` manages the captured Qwen Docker
  stack through a user supervisor; install can adopt matching running containers
  without restarting models. Update restarts the stack and active consumers.
- `router.sh install|update|uninstall|check` manages user `9router.service`
  and the pinned Docker image through `~/.config/9router/compose.yaml`.
- Root-owned system `tailscaled.service` is the actual native kernel daemon
  and owns host SSH and Serve. The user `tailscale.service` coordinator restores
  reviewed private configuration through that daemon; it must not launch another
  userspace daemon, call the tailnet API or launch a model at startup.
- `bootstrap.sh <action> --with-network` selects Tailscale and 9router.
  For install/update, Docker is selected as needed and Tailscale precedes the
  gateway. Removal reverses dependency order.

Bootstrap selects Docker/NVIDIA → EasyLlama → 9router → Hindsight for the captured
local AI stack; PostgreSQL precedes Hindsight. Existing AI unit dependencies and
database data remain intact. Phase 1 pulls in and re-executes the native user
coordinator as a dependency of starting `9router.service`. This start path was
verified; a full login was not tested.

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

Historical source report, 2026-09-10 (before this Tailscale migration): the EasyLlama user unit adopted all three existing
containers with unchanged IDs/start timestamps. EasyLlama, 9router, PostgreSQL and
Hindsight user units are active and enabled; authenticated Hindsight health passes
and anonymous API/dashboard data access remains rejected. Image archives were not
exported automatically; the explicit archive command remains the transfer step
for a fresh host without these locally built images.

## Preserved Configuration

- 9router remains version **0.5.69**, pinned by manifest digest, with **2 CPUs**
  and **4 GiB `/dev/shm`**. The verified Docker backend binds only
  `127.0.0.1:20128`; raw tailnet/LAN port 20128 is not the public API contract.
  Loopback binding replaces the baseline's LAN-accessible host-network listener.
- The existing `~/.9router` store remains mounted in place: SQLite, provider
  credentials, JWT secret, machine identity and certificates are preserved.
  `runtime.env` retains the existing 600-second swap-aware timeouts.
- Routine install/update preserves an existing database and identity files,
  including renewed certificates. Captured identity files are used only for a
  missing database; explicit identity restoration refuses differing files.
- Native Serve owns HTTPS publication. The container has no host Tailscale
  socket/binary mounts; its internal publication setting is `false`.
- Both dashboard and OpenAI-compatible API use HTTPS 443. The API base is
  `https://ninerouter.tailc28ab1.ts.net/v1`; `http://127.0.0.1:20128` is the
  local proxy backend, not a separate remote endpoint. Gateway authentication
  and the required Qwen chat/embedding models remain configured.
- Hindsight's backend remains on loopback 8888 with its existing API/dashboard
  authentication and separate PostgreSQL data. Its old userspace Tailscale node
  stays offline; no private Hindsight HTTPS readiness is claimed. Earlier ACME
  failures concern that retired deployment, not proof about the new gateway.

## Router Deployment And Recovery

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

Historical router cutover report, 2026-09-10 (before private HTTPS conversion):
both then-existing user units were enabled/active; the
container is healthy, authenticated discovery preserves 66 models and both Qwen
IDs, chat and embeddings pass, and local/Funnel dashboard routes still require
login. The native npm binary
is retained only for rollback; the versionless package restore no longer installs
it. The private SQLite/launcher recovery point is under
`~/.local/state/9router/cutover-20260910T205650Z/`. No upstream source was edited.

Router uninstall stops its Compose project but preserves all data/configuration.
For Tailscale removal and retained state, see [runtime lifecycle](#runtime-lifecycle).

## Tailscale Setup And Cutover

| Stage | Endpoint | Required result | Status |
| --- | --- | --- | --- |
| Native host | `koija.tailc28ab1.ts.net`, `tag:ssh` | Retain stable native identity and checked owner SSH to local user `koija` | Complete; policy tests pass, remote SSH untested |
| Separate Service | `svc:ninerouter`, `tag:ninerouter`; `ninerouter.tailc28ab1.ts.net:443` | Native kernel Services VIP proxies `127.0.0.1:20128`; no Funnel | Complete; exact host manually approved, DNS/TLS/API verified |

The applied policy change added only the original-owner Drive grant and host
`drive:share`, and removed only the exact obsolete `tag:ninerouter` Funnel
attribute. The wildcard network grant, existing checked owner SSH, client
`drive:access` and unrelated policy remain unchanged.

Admin provisioning is a guarded one-off operation, separate from startup:
register the exact Service definition with `tag:ninerouter`, then manually
approve only the pinned stable native node ID as its host. Do not broaden
`autoApprovers`. Definition, advertisement, host approval and client permission
are separate requirements; captured metadata does not establish readiness.

The native coordinator applies the reviewed HTTPS frontend and HTTP backend:

```sh
tailscale serve --service=svc:ninerouter --https=443 http://127.0.0.1:20128
```

This CLI automatically advertises the Service. Avoid versioned `get-config` /
`set-config` round-trips: the researched 1.102.3 conversion conflates frontend
HTTPS with the backend URL scheme and cannot preserve this mapping correctly.
Clients 1.94+ use Service routes by default. Older Linux clients need
`accept-routes`; assess each client's existing routes before an explicit change,
without enabling route acceptance globally.

### Owner Identity And File Sharing

The verified original owner remains pinned privately in `TAILSCALE_OWNER` and
reviewed owner configuration, separately from daemon keys. Tagging replaces
user ownership; never infer the original owner from the tagged node's current
owner field. Owner metadata is non-secret and does not itself grant access.

The existing stable native identity, keys and SSH settings are unchanged.
Taildrop is now disabled by the approved tagging. Taildrive mounts and bookmarks
must use native hostname `koija`; all **four DriveShares** remain in native
state with the same in-memory fingerprint, without exported definitions.

The host has `drive:share`; clients retain `drive:access`. The verified original
owner has `tailscale.com/cap/drive` access to `tag:ssh` with `shares: ["*"]` and
`access: "rw"`. The existing SSH rule remains original owner → `tag:ssh`, local
user `koija`, with `action: check`. Checked SSH and network policy tests passed
before and after tagging. Preserve these rules and unrelated policy.

**Remote owner SSH and Taildrive end-to-end access were not run.** Share
fingerprints and policy tests do not establish remote login or file access.

### Runtime Lifecycle

The lifecycle retains `install`, `update`, `uninstall`, `check`,
`--dry-run` and `--no-start`. Shared helpers and receipts own managed payloads.
`check` is read-only; `--dry-run` previews without mutation. `--no-start`
suppresses activation and does not stop an already running unit.

The user coordinator is limited to restoring reviewed private native
configuration. Explicit admin provisioning and approval precede activation;
temporary migration tooling is not a repository or startup dependency.
Routine startup consumes no tailnet API
credentials, does no provisioning/enrollment or tailnet API mutation, and
launches no model/API probes. It must verify expected native identity and tags
before applying reviewed Service configuration and must not restore Funnel.
Starting `9router.service` pulls it in and re-executes its configuration action.
Phase 2 replay of `tailscale.service` idempotently validated the captured Service.
No full login test was performed.

Receipt-checked removal preserves native SSH, private configuration, daemon
identity state, credentials, skills and backend data. It does not log out,
revoke or delete nodes. Retired repository app artifacts are removed; the owner
template is retained. Old app units remain masked/offline
without enabled links; home identity state and masks are preserved.

### Verification And Remaining Work

**Phase 2: COMPLETE — verified results, 2026-09-10.**

- Native stable node ID and identity keys are unchanged; hostname/DNS is
  `koija` with `tag:ssh`. Only this node is manually approved for
  `svc:ninerouter` / `tag:ninerouter`; the API reports it ready.
- Service DNS resolves to the captured VIP addresses, not the native IP.
  HTTPS 443 proxies `127.0.0.1:20128`; TLS passes and the dashboard retains
  its exact origin and login redirect.
- Anonymous API access returns **401**. Authenticated `/v1/models` returns
  **66 models**, including both required Qwen models. AI units remain active;
  no gateway restart was required.
- All **four DriveShares** retain their fingerprint and native SSH settings
  are preserved. Checked owner SSH/network policy tests pass before and after
  tagging; the Drive grant and attributes are applied. The wildcard network
  grant is unchanged and only the exact obsolete Funnel attribute was removed.
- Home and repository configuration capture include Service VIP metadata and
  the approved native node ID. `systemctl --user start tailscale.service`
  idempotently validates the captured Service. `tailscale.sh check`,
  `router.py check` and `hindsight.py health` pass.
- Dotfiles validation checks **844 templates**, **7 unit links**, and no missing
  values. The guard scans **924 files** with **zero findings**;
  `git diff --check` passes. The host-ID compatibility correction is complete;
  there is no ongoing migration blocker.

**Remote owner SSH, Taildrive end-to-end access and inference smoke tests
were not run.** Model discovery establishes inventory only. No full-login or
off-tailnet public-access probe is claimed.

Historical Phase 1, 2026-09-10: private node-level HTTPS replaced Funnel before
tagging/rename. Gateway and Hindsight restarts, coordinator dependency checks,
authenticated Hindsight health, database and EasyLlama health passed. Those
restart results describe Phase 1; Phase 2 required no gateway restart.

## Identity Restoration Boundary

Capture only reviewed non-secret configuration: expected node metadata,
names/tags, private Serve/Service intent, user units and resource limits.
Share definitions are not exported: compare existing DriveShares exactly in
memory and report only their count of four. Keep them in the native state.
`~/.config/tailscale/network.json` is configuration, not
a transferable identity. Keep the verified original-owner pin private and
runtime verification status separate from intended configuration.

The captured `service` subsection of private `~/.config/tailscale/network.json`
(`network.service`) contains the exact Service definition, `tag:ninerouter`,
assigned VIP addresses and approved stable native node ID. This non-secret
metadata is the operator reference for explicit admin reprovisioning; it is not
identity keys, API permission or host approval. Keep the record separate from
runtime verification and actual control-plane authorization.

Future per-service capture extends the existing configuration/template
workflow with reviewed names, tags, DNS names, VIP addresses, listener ports,
loopback backends and approved stable node IDs. Record each service independently
so later additions preserve other services. Non-secret metadata is captured in
Git; credentials use placeholders and remain outside Git and snapshot output.
Validate renderer/schema support
before relying on new values. Restoring metadata does not enroll or provision
a host or grant approval; those remain explicit admin operations. Startup
does not acquire API credentials or provision Services.

Preserve existing daemon identity/SSH keys in place. Do not read, export or copy
`/var/lib/tailscale` through sudo, containers or other wrappers. Retain old app
state under `~/.local/state/tailscale/` while its units remain offline; exclude
those keys, state files and temporary enrollment files from template capture.
A replacement host requires independent enrollment and an intentional hostname
handoff. Preserve existing skills and private keys without adding key exports.

The tailnet API credential remains only in private `values.json` under
`SECRET_TAILSCALE_API_KEY`, outside Git. It is not a rendered daemon setting,
template payload or memory document. Snapshot refresh preserves it in that
private store but excludes it from snapshot output and snapshot backups.
Never copy private values into snapshot output or read credentials for a
documentation or startup check.

Router recovery is separate: `SECRET_ROUTER_IDENTITY` and
`SECRET_ROUTER_TABLES` are private base64 JSON bundles, **not encryption**.
Only placeholders belong in Git. Identity files are relative to `~/.9router`;
format-2 restoration preserves raw SQL fields and format 1 remains readable.
Provider sessions may require renewal. Refresh only the reviewed router/config
allowlist, excluding logs, request history, caches, Taildrop file contents and
unrelated accounts. Never use a combined capture path that reads native keys.

## Sources

- [Tailscale Services](https://tailscale.com/docs/features/tailscale-services)
- [Tailscale Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [Tailscale SSH and checked access](https://tailscale.com/kb/1193/tailscale-ssh)
- [Official 9router container definitions](https://github.com/decolua/9router/blob/master/docker-compose.yml)
- [Official 9router Dockerfile](https://github.com/decolua/9router/blob/master/Dockerfile)

Installed local/runtime evidence was verified on 2026-09-10.
These URLs are background references; the dated verification report records
the completed live migration and capture/replay checks.

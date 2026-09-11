# Local AI Services and Tailscale

**Phase 1 complete — Verified 2026-09-10.** Migration and verification succeeded
following Code Review and Security Review GO.
The personal native node `ninerouter` serves tailnet-only HTTPS at
`https://ninerouter.tailc28ab1.ts.net` for the dashboard and `/v1` API.
Funnel removal is confirmed from native configuration. Gateway and Hindsight
restarts succeeded; native identity, SSH settings, preferences and all four
DriveShares were preserved without tagging, renaming or tailnet API writes.

The later design uses native kernel Tailscale Services: native host `koija`
serves a separate `ninerouter:443` Service VIP. Services require a tagged host,
so rename, tagging and Service activation await the user's personal-identity
decision. No native tag or identity mutation was performed. Native preferences
show **four DriveShares**; their
configuration and owner access must survive any approved migration.

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
| Phase 1: private HTTPS | Native `ninerouter.tailc28ab1.ts.net:443` | Dashboard and `/v1` through loopback 20128; Funnel off | Complete; Verified 2026-09-10 |
| Native host | `koija.tailc28ab1.ts.net`, `tag:ssh` | Preserve native identity state and checked owner SSH to local user `koija` | Rename/tagging pending personal-identity decision |
| Separate Service | `svc:ninerouter`, `ninerouter.tailc28ab1.ts.net:443` | Native kernel Services VIP proxies loopback 20128 | Pending host decision, provisioning and tests |

### Owner Identity And File Sharing

The original owner must be verified and pinned privately before tagging.
Tagging replaces user ownership with tag identity; the tagged node's current
owner field must not be used to infer the original owner. Preserve verified
owner metadata separately from daemon keys, using the private `TAILSCALE_OWNER`
value and reviewed owner configuration. No credential belongs in that metadata.

Services require host tagging. A tagged host loses Taildrop eligibility; keeping
the current personal identity therefore matters. Tagging requires the user's
configuration choice. Phase 1 private Serve on the
existing native node is complete and does not change personal ownership.

Fresh native preferences contain **four DriveShares**. Preserve all four share
definitions in place and original-owner access. Phase 1 verified their unchanged
fingerprint in memory and reported the count of four; capture does not export
share definitions. The Researcher's confirmed requirements
for a future approved tagging change are:

- Give `tag:ssh` the `drive:share` node attribute and retain the clients'
  existing `drive:access` attribute.
- Grant the verified original owner access to `tag:ssh` through the
  `tailscale.com/cap/drive` application capability, with `shares: ["*"]` and
  `access: "rw"`, preserving the existing wildcard read/write share access.
- Account for the hostname rename in Taildrive mount and bookmark paths;
  retain all four share definitions and verify owner access at the new paths.

These are pending-choice requirements; no tagging or policy mutation has been
performed. A metadata pin alone does not preserve access, and share inventory
is not an end-to-end file-access test.

The intended tagged-host SSH rule is the verified original owner →
`tag:ssh`, local user `koija`, with `action: check`. Preserve unrelated SSH
rules and the existing owner login path during migration. **External SSH login
has not been tested**; policy inspection or local checks cannot establish it.

### Runtime Lifecycle

The lifecycle retains `install`, `update`, `uninstall`, `check`,
`--dry-run` and `--no-start`. Shared helpers and receipts own managed payloads.
`check` is read-only; `--dry-run` previews without mutation. `--no-start`
suppresses activation and does not stop an already running unit.

The user coordinator is limited to restoring reviewed private native
configuration. Provisioning and owner/policy decisions happen explicitly before
activation; routine startup does not enroll nodes, mutate tailnet API policy or
launch model/API probes. It must not silently restore obsolete Funnel settings
or apply the pending tagged-Service configuration to the current personal node.
Phase 1 starts it as a dependency of `9router.service` and re-executes its
configuration action. This dependency path passed verification; no full login
test was performed.

Receipt-checked removal preserves native SSH, private configuration, daemon
identity state, credentials, skills and backend data. It does not log out,
revoke or delete nodes. Retired repository app artifacts are removed; the owner
template is retained. Old app units remain masked/offline
without enabled links; home identity state and masks are preserved.

### Verification And Remaining Work

**Verified 2026-09-10**, after successful gateway and Hindsight
restarts:

- HTTPS certificate valid on `https://ninerouter.tailc28ab1.ts.net`;
  dashboard retains the exact same origin and login redirect.
- Authenticated `/v1/models` returns **66 models**, preserving the required
  Qwen IDs; anonymous API requests return **401**.
- Native configuration confirms Funnel removal. Docker listens only on
  `127.0.0.1:20128`, has no Tailscale socket/binary mounts, and retains its
  pinned image, persistent store, **2 CPUs** and **4 GiB shared memory**.
- Native identity, SSH settings and preferences are preserved; all **four
  DriveShares** retain their in-memory fingerprint. No tag, rename or tailnet
  API write occurred. No share names or definitions were exported.
- The native coordinator re-executes as a gateway-start dependency. AI units
  are active; Hindsight's authenticated API is ready, while anonymous API and
  dashboard-data access are rejected. Database and EasyLlama health pass.
- Final checks validate **844 templates** and **476 placeholders**; the guard
  scans **924 files** with **zero findings**. `tailscale.sh check` and
  `router.sh check` pass, as does `systemd-analyze --user verify` for both
  changed installed units.

No full-login, external SSH, off-tailnet public-access or inference smoke tests
were performed. Model discovery verifies inventory, not inference. Native
Funnel configuration and listener inspection are not external reachability probes.

Native `koija` / `tag:ssh` and the separate `ninerouter` Services VIP remain
pending the user's tagged-host/Taildrop choice. Any approved migration must
preserve checked owner SSH and all four Taildrive shares with the attributes,
capability grant and renamed-path checks described above. Retired repository
app artifacts are removed and excluded from snapshot capture; the owner
template and masked/offline home state remain. The invalid IPset policy is not retried.

## Identity Restoration Boundary

Capture only reviewed non-secret configuration: expected node metadata,
names/tags, private Serve/Service intent, user units and resource limits.
Share definitions are not exported: compare existing DriveShares exactly in
memory and report only their count of four. Keep them in the native state.
`~/.config/tailscale/network.json` is configuration, not
a transferable identity. Keep the verified original-owner pin private and
runtime verification status separate from intended configuration.

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
These URLs are background references; current Services details still require
review before the pending tagged-host migration.

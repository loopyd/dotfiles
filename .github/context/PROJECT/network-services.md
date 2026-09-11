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

Both retired userspace app devices are deleted from the tailnet; their local
template and two masks are removed, with identity/data preserved.
Repository cleanup is complete: `scripts/tailnet.py`, `scripts/tailserve.py`,
and retired app unit/endpoints templates are removed. The owner template and
home identity/data are preserved; snapshot capture excludes obsolete app unit
and endpoints artifacts. See [retired app cleanup](#retired-app-cleanup).
The rejected IPset policy is not a recovery recipe and must not be retried.
The dated historical reports below describe the earlier baseline.

The dedicated [Hindsight HTTPS service](#hindsight-private-https) is verified
2026-09-10 (PDT): native-host approval, exact VIP DNS, trusted TLS, dashboard
authentication and idempotent replay pass. HTTPS testing used this host over
the tailnet VIP, not a second device. Phase 2 below records the earlier 9router cutover.

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
verified; a full host reboot was not tested.

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

- The reviewed Compose pin is 9router **0.5.75**, pinned by image digest, with **2 CPUs**
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
- Hindsight's API on loopback 8888, dashboard backend on loopback 9999 and
  separate PostgreSQL data retain their authentication and loopback bindings.
  Native `svc:hindsight` targets only the dashboard; see
  [Hindsight private HTTPS](#hindsight-private-https) for verified access results.
  Historical ACME failures concern its retired userspace deployment, whose
  tailnet device is now deleted; they do not establish native Service readiness.

## Router Maintenance

Updates converge to the reviewed Compose pin, never automatically to `latest`.
Version **0.5.75** uses image digest
`sha256:7c893bc2c27ecea2ae337abd5eacfec9e5763091b3a3b7862fc0625b770bb156`.

1. Verify the upstream release and image version, update the Compose template
   digest, and recompute its source-file SHA-256 in `templates/manifest.json`.
2. Retain the previous Compose file and a consistent SQLite backup outside Git.
   Use SQLite's backup API, not a plain copy of a live database file.
3. Materialize and install only the reviewed Compose change using the existing
   renderer. Its CLI has no single-file selector; a full render changes other
   captured files too. Preserve authentication, identity, mounts and limits.
4. Preview `bash scripts/router.sh update --dry-run`, then run
   `bash scripts/router.sh update`. This isolates the gateway update;
   `bootstrap.sh update --only router` also selects Docker/NVIDIA, Tailscale and
   EasyLlama updates.
5. Run `bash scripts/router.sh check`; verify image/version, private HTTPS login,
   anonymous API rejection, required Qwen discovery, chat/embedding requests and
   authenticated Hindsight health. Record actual results.

The updater has no automatic rollback. Keep the old image and private backups;
stop the gateway before any database recovery, never overwrite a live database.

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

### Hindsight Private HTTPS

**VERIFIED 2026-09-10 (PDT).** The dedicated dashboard endpoint is
`https://hindsight.tailc28ab1.ts.net` on HTTPS 443, via `svc:hindsight` /
`tag:hindsight` to `http://127.0.0.1:9999`. Access requires a permitted tailnet
client and the existing dashboard access key. Preserve API authentication,
loopback-only API port 8888 and PostgreSQL; neither gets a Serve frontend.
The existing broad network grant remains, so private access is not owner-only.

Verified provisioning history, 2026-09-10 (PDT), before retired-device deletion:

- Service creation initially returned **409**: inactive/masked old Hindsight
  node `n1MGs2nwEA21CNTRL`, last seen hours earlier, held the name. Only its DNS
  label was renamed to `hindsight-retired.tailc28ab1.ts.net`; identity, tags,
  addresses and local-state metadata for **54 paths** were preserved.
- The one-time API operation then created `svc:hindsight`, tagged
  `tag:hindsight`, on `tcp:443`, with VIPs `100.89.123.251` and
  `fd7a:115c:a1e0::c72b:7bfc`. Only native `koija`, stable ID
  `ny5Q2pJD5A21CNTRL`, was manually approved as its host.
- Native processes are one root process and its unprivileged child in the same
  unit. Native preferences, `tag:ssh`, SSH, four shares and 9router are unchanged;
  no ACL or `autoApprovers` change was made.

Reprovisioning remains a separate admin operation; captured metadata grants no
authorization. Retain host `tag:ssh`, and do not add policy grants or
`autoApprovers` without evidence they are needed. Service definition, host
advertisement, host approval and client permission are separate requirements;
see the official [Tailscale Services mechanics](https://tailscale.com/docs/features/tailscale-services).

After provisioning, the native coordinator must replay the reviewed mapping
through the existing root-owned daemon without tailnet API credentials:

```sh
tailscale serve --bg --service=svc:hindsight --https=443 http://127.0.0.1:9999
```

Native Serve advertises the Service. Keep this mapping independent of
`svc:ninerouter`; replay must preserve its HTTPS frontend and backend.
The captured public `services` map includes both Services and their VIPs.
Historical `retired_device` metadata is removed. Preserve each
Service's definition, loopback backend and approved stable node ID on replay.
Restored metadata is not API permission or approval; startup performs neither
provisioning nor credential retrieval. A replacement host needs explicit
enrollment and approval, not a copied daemon identity.

Preserve native hostname `koija`, identity keys, checked owner SSH and all four
DriveShares in place. Retired local app identity/data remain preserved during
[unit cleanup](#retired-app-cleanup). No Funnel, additional daemon or global Serve reset belongs in
this replay path.

Verified runtime results, 2026-09-10 (PDT):

- `svc:hindsight` is configured/ready on `koija`, approved manually. DNS returns
  exactly `100.89.123.251` and `fd7a:115c:a1e0::c72b:7bfc`. Native DNS-01
  issuance produced a trusted TLS certificate without Funnel; initial
  handshakes waiting for the certificate resolved.
- `/` returns **307** to same-origin `/login`, then **200**. Anonymous
  `/api/list` returns **401**. Access-key login POST returns **200** and sets
  `hindsight_cp_access` with `Secure` and `HttpOnly`; authenticated `/api/banks`
  and `/api/list?bank_id=shared` both return **200**.
- Native coordinator replay is idempotent: Serve is unchanged and only the two
  expected Services are advertised. Other native preferences, SSH, the four-share
  fingerprint and ACL remain unchanged; `autoApprovers` remains unchanged.
- API **8888**, dashboard backend **9999** and PostgreSQL **5432** listen only
  on `127.0.0.1`. At this pre-cleanup check, old Hindsight/9router app units
  were masked/inactive.
- Existing Hindsight health and 9router checks pass; no AI container restart
  was required.

HTTPS was tested from this host through the tailnet VIP, **not a second device**.
Remote-client SSH and Taildrive end-to-end tests remain unperformed; no
off-tailnet public-access probe or full host reboot test is claimed.

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
No full host reboot test was performed.

Receipt-checked removal preserves native SSH, private configuration, daemon
identity state, credentials, skills and backend data. It does not log out,
revoke or delete nodes. The separately authorized retired-device deletion and
local cleanup are recorded below. Retired repository app artifacts are removed;
the owner template and home identity/data are preserved.

### Retired App Cleanup

**Tailnet deletion verified, 2026-09-10 (PDT):** `hindsight-retired`
(`n1MGs2nwEA21CNTRL`) and `ninerouter-app` (`ndDeXAoiZ921CNTRL`) are deleted.
Both `svc:hindsight` and `svc:ninerouter` still use approved native host `koija`.
Hindsight trusted HTTPS, login **200** and anonymous API **401**, plus router
discovery of **66 models** including the required Qwen models, are verified.
These checks establish neither new inference results nor remote-client coverage.

**Local removal complete, 2026-09-10 (PDT).** The parent checked the exact
template hash, verified both masks were inactive with no reverse dependencies
or enablement links, and removed only
`~/.config/systemd/user/tailscale@.service` and the two retired instance
`/dev/null` masks. User daemon-reload is complete; no live retired units/masks
remain: `list-unit-files tailscale@*` returns zero entries, both instances report
`LoadState=not-found` / `ActiveState=inactive`, and no `tailscale@` files remain.
Local identity/data, the owner template, native user `tailscale.service`,
root-owned `tailscaled.service`, SSH, all four DriveShares and both active
Services are preserved. State/key deletion or export is not authorized.
Historical `retired_device` metadata is removed from the repository template and
home `network.json`, and the manifest hash is updated. Both active Service
definitions are preserved.

Final checks pass: `tailscale.py check`, `router.py check` (**66 models**,
required Qwen models) and `hindsight.py health` (authenticated API succeeds,
anonymous access rejected). Hindsight HTTPS login returns **200** and anonymous
`/api/list` returns **401**. Renderer validation passes **861 templates** and
**7 unit links**, with no missing values, after syncing **18 skill/lock
templates** and **5 private documentation placeholders**.

The snapshot preserves authored restoration-only overrides absent from live
home, installer-managed shell/tool defaults and restrictive trust settings.
It excludes live mise `trusted_config_paths=['/']`, Codex hook trust caches,
ibus PIDs and Nemo timestamps. Rendering-equivalent credential markers retain
their canonical names/values; the newer installed Tailscale skill and lock are
synced. Local identity/state data remain outside capture.

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
- At the earlier Phase 2 check, dotfiles validated **844 templates**, **7 unit
  links**, and no missing values; the guard scanned **924 files** with **zero
  findings**, and `git diff --check` passed. Final renderer results are recorded
  in [retired app cleanup](#retired-app-cleanup). The host-ID compatibility correction is complete;
  there is no ongoing migration blocker.

**Remote owner SSH, Taildrive end-to-end access and inference smoke tests
were not run.** Model discovery establishes inventory only. No full host reboot test or
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

The captured public `services` map in `~/.config/tailscale/network.json` records
both `svc:ninerouter` and `svc:hindsight`, including their definitions/tags,
VIPs, listeners, loopback backends and approved stable native node ID.
The historical `retired_device` field is removed from capture and home
configuration; retirement history is recorded in [retired app cleanup](#retired-app-cleanup).
The map extends the historical single-Service `network.service` capture. Non-secret metadata
belongs in Git; credentials use placeholders and stay outside Git and snapshot
output. Preserve each Service independently when replaying or adding entries.

Metadata is an operator reference, not identity keys, API permission or host
approval. Keep it separate from runtime evidence and actual control-plane
authorization. Restoring it does not enroll/provision a host or grant approval;
those remain explicit admin operations. Startup neither acquires API credentials
nor provisions Services.

Preserve existing daemon identity/SSH keys in place. Do not read, export or copy
`/var/lib/tailscale` through sudo, containers or other wrappers. Retain old app
identity/data under `~/.local/state/tailscale/` through local unit cleanup; exclude
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

The dated 2026-09-10 reports record the earlier completed migration and
capture/replay checks. These URLs describe upstream mechanics; the Hindsight
section separately records verified control-plane, HTTPS/TLS,
authentication and replay results from 2026-09-10 (PDT), with client-test limits.

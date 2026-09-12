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
local AI stack; PostgreSQL precedes Hindsight. Starting `9router.service` pulls
in and re-executes the native user coordinator. Earlier migration checks verified
that start path; the subsequent reboot failure and recovery change are recorded
below. Database data remain intact.

## Boot Recovery

**Observed reboot failure, 2026-09-10 22:07 PDT.** Docker was not yet active at
user login, so EasyLlama and `hindsight-db.service` failed their immediate
`ExecStartPre` checks. Each recovered after one restart. Their ordered `Requires`
dependencies cancelled the 9router/Hindsight start jobs before the consumers
could execute; the consumers' restart policies therefore never ran. The native
Tailscale coordinator succeeded: inactive is normal after this oneshot completes.

The recovery change replaces those `Requires` edges with `Wants` plus `After`.
Each consumer now waits or fails in its own `ExecStartPre`, allowing its restart
policy to retry after 15 seconds when prerequisites remain unavailable. Shared
`scripts/readiness.py`, installed at `~/.local/lib/dotfiles/readiness.py`, provides
`wait docker|router|hindsight` with a default **180-second bound per attempt**:

| Wait | Required evidence |
| --- | --- |
| `docker` | System `docker.service` active and Docker daemon responsive; used by EasyLlama and PostgreSQL |
| `router` | Docker ready, `easyllama.service` active and strict native `tailscale.py check` successful |
| `hindsight` | Docker ready, database and 9router units active, PostgreSQL `pg_isready` and authenticated router model discovery successful |

Probes use fixed subprocess commands with bounded execution and suppressed
stdout/stderr; status messages contain no credentials or probe output. Router
discovery uses existing private authentication through its helper, without model
inference. This does not add tailnet API credentials or probes to the coordinator.
Router database-presence/preflight checks and existing container readiness checks
remain in place. Installer/helper payloads and the template manifest carry the
shared helper and revised units.

`TimeoutStartSec` budgets are 420 seconds for EasyLlama (180-second Docker wait
plus its existing 180-second readiness check), 330 for PostgreSQL (180-second
Docker wait plus 120-second `pg_isready` check), and 210 each for 9router/Hindsight
(180-second prerequisite wait plus remaining startup work). No router
`ExecStartPost` is added; Hindsight's gate verifies authenticated router discovery.
The coordinator retains its 120-second native wait and 150-second startup
budget, adding `Restart=on-failure` / `RestartSec=15`. Success remains inactive.
These bounds limit individual attempts, not total recovery time or eventual
success while prerequisites remain unavailable.

`PartOf` preserves explicit stop/restart propagation: Tailscale or EasyLlama →
9router, and database or 9router → Hindsight. An intentional stop leaves affected
units stopped until explicitly started; automatic retry is for startup/runtime
failure, not an instruction to undo an operator stop. Readiness probes only
observe prerequisites and do not start or stop dependencies.

**Recovery validation.** Mock probes pass immediate,
delayed, timeout and exception cases. An isolated two-unit systemd rehearsal
using the same `readiness.wait` with a temporary marker probe also passes:
forced initial upstream `ExecStartPre` failure caused one upstream retry and
one consumer retry, then both became active automatically. Restart propagation
and explicit-stop persistence pass; temporary units were cleaned up. Real Docker,
models and the database were untouched.

**Deployment and live verification.** Code and security reviews found zero
blockers. Five unit files and three helpers were deployed with prior-file backups
and a user daemon reload; systemd unit verification passes. Starting Hindsight
pulled in 9router and the native coordinator while already-running EasyLlama and
PostgreSQL stayed untouched. Router/EasyLlama helper receipts were refreshed.

- Hindsight authenticated API health and anonymous API/dashboard denial pass.
  HTTPS login returns **200**; anonymous `/api/list` returns **401**.
- Router discovery returns **66 models**, including the required Qwen models;
  private HTTPS `/dashboard` returns the expected **307** login redirect.
- EasyLlama verifies all **three pinned containers** and authenticated model
  discovery. Strict native Tailscale checks pass.
- All three EasyLlama containers and PostgreSQL retain their container IDs and
  `StartedAt` values. Router/Hindsight are active/running with **zero restarts**;
  EasyLlama/PostgreSQL are active with **one restart each**, from the original
  boot failures, not new failures. The coordinator succeeded and is normally
  inactive after oneshot completion.

**No full reboot after the fix has been performed.** Live health checks, the
isolated rehearsal and mock results do not prove corrected full-host boot
recovery. Images, keys, authentication, policy, native daemons and persistent
data are preserved.

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
- The captured baseline has proxy 2 CPUs/8 GiB memory and
  backend 24 CPUs/62.5 GiB memory, with 64 MiB shared memory per container.
  These are EasyLlama's existing GPU-workload limits, not Hindsight/9router's
  separate 2-CPU/4-GiB-shared-memory limits. NVIDIA GPU access and host networking
  remain unchanged; the proxy listens on loopback port 8080. The later
  [CPU embedding trial](#hindsight-cpu-embedding-trial) changes the live embedding
  allocation; the five affected templates and manifest now capture the accepted settings.
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

## Hindsight CPU Embedding Trial

Historical 8B evidence; these constraints applied to that trial, not every future
embedding model. See the separately [deployed 0.6B migration](#hindsight-06b-migration).

**No optimization candidate promoted, 2026-09-11 UTC; loaded search unresolved.**
CPU16/one-slot failed the late loaded search test. **Both CPU16/four-slot and
the restored eight-CPU/four-slot baseline failed the same batch-versus-single
consistency gate**; this does not establish a CPU16-induced regression. Automatic rollback
restored the earlier **eight-CPU, four-slot, context-163840, f16 CPU-only
embedding profile**, both dotfiles templates and manifest. Routes were verified
and Hindsight resumed. Tested **20–22% isolated latency reductions were not
retained**; no new CPU16 configuration, long-term RAM saving or resolved-search
claim is retained.
Comparable batch-versus-batch validation remains required; the inconsistency's
root cause is unresolved.

The original Qwen 8B Q5_K_M model/build, IDs, per-input token limit and finite,
unit-normalized 4096-dimensional vectors were required for that trial; Qwen 27B Q4 chat kept
its full 262144-token GPU context. The earlier **Hindsight API allocation of
8 CPUs/6G is separate from embedding CPUs**. The two home EasyLlama trial configs
were rolled back; chat, gateway, DB and Hindsight runtime configs are unchanged.
Checked source/modules/images, libraries, extensions, authentication, hooks, `shared` and combo
strategy remain unchanged.

**Earlier retained setup (warm-success interpretation superseded):** CPU coexistence
applied around 07:00, Hindsight tuning at 07:05–07:06 and proxy-cap restoration
at 07:10. Services then had zero automatic restarts; the API's 8-CPU update
around 07:12:58 preserved its PID. The old embedding command used
`--device none --n-gpu-layers 0 --threads 8` (previously 24 CPUs), with
28–29 GiB host RAM observed (29 GiB peak at that stage), over 80 GiB free on
the 125 GiB host and later about 792% embedding CPU. The earlier warm-search
improvement interpretation is superseded by the pre-deployment loaded assessment
below; sustained search/ingestion improvement remains unproven pending new checks.

llama-swap uses `swap: true` for the single-chat GPU group and `swap: false`
for the CPU embedding group; both have `exclusive: false`.
Rejected proxy 4/2 admission caps caused HTTP 429,
an 8-second gateway cooldown and a consolidation retry. Both `concurrencyLimit`
values returned to original zero overrides. At installed v251 revision
`4ec317589b21f58b64802c2b3371a179b9fdaa53`, an unspecified scheduler selects
[FIFO][swap-loader], whose [constructor][swap-fifo] defaults to **10 in-flight
requests per model** and overrides this only for `concurrencyLimit > 0`.
Zero therefore restores ten, not unlimited admission. The [admission check][swap-admission]
returns `ConcurrencyLimitError` at the cap, mapped to [HTTP 429][swap-error].
The recorded binary is marked modified; inspected build patches were outside
the scheduler. Backend chat capacity remains four slots with bounded Hindsight clients/workers.
Use `routing.router.settings.groups` and `routing.router.use: group`, without
legacy groups; see [official llama-swap semantics][swap-config].

### Pre-Deployment Loaded Assessment

At 07:22–07:25 UTC, four queries repeated three times yielded **0/12 successful
knowledge searches: 11 timeouts and one HTTP error**, with a 15-second socket
timeout. Concurrent API health passed 12/12 in 2–4 ms; DB acquisition took
0.4–0.9 ms with zero pool waiters. Three resource snapshots show all four
embedding slots busy, 789.83–792.06% CPU against eight CPUs and about 31.2 GiB
embedding memory, while DB CPU was 0–3.41%. CPU embedding saturation is the
leading bottleneck, not proven to be the sole cause; healthy API/DB checks do
not establish usable knowledge search.

Local embedding HTTP 429s at 07:24:55 and 07:25:03 triggered 9router's sole-account
8/16-second model cooldowns; Hindsight received the propagated error. The
16-second cooldown exceeds the search budget. Raising admission alone would
not prove faster compute or reliable search. Failed requests have censored
latency; differing queries, timeout budgets, cache state and background work
preclude a controlled speedup/slowdown ratio against the earlier warm samples.

From 07:10:15–07:26:02, zero retains completed in 15.80 minutes (one mental-model
refresh completed); documents rose 514→515 and non-observation facts 19082→19099.
This is partial durable progress, not completed ingestion. Evidence:
`/tmp/hindsight-tuning/ASSESSMENT.md`, `429-DIAGNOSIS.md` and their cited JSON/JSONL.

### Historical Measurements (Improvement Interpretation Superseded)

| Probe | Result |
| --- | --- |
| Baseline searches | 16.432 s, 0.462 s, third timed out beyond 20 s; plugin deadline 15 s |
| CPU-stage warm searches | 0.112 s, 0.122 s, 0.108 s |
| CPU embedding cold / warm | 10.528 s / 0.100 s; chat 0.112 s, embedding after chat 0.092 s |
| Initial tuned searches under load | 10.123 s, 3.061 s, 0.105 s; all successful |
| After cap restoration | Searches 4.044/0.102/0.096 s; health 0.010/0.002/0.013 s; all successful |
| Final 8-CPU probes | Searches 0.373/0.259/0.203 s; health 0.003/0.054/0.006 s; all successful |

**07:10:26–07:15:27:** observations 0→9, facts 19082→19091 solely through
observation growth; documents stayed 514, completed operations 260, failures four.
Two retains, one consolidation and one refresh stayed active throughout the
sampled window. Initial MCP hits were placeholders; observations do not prove
generated knowledge pages. Global MCP diagnostics confirm `shared`, authentication
and active hooks; `sync=false` and the backlog remains.
Successful LLM calls since 07:10, reported at 07:11+: retain 2 (mean 68711 ms,
reported output 9975 tokens), consolidation 1 (47890 ms, 2986 tokens), refresh 2
(mean 7706 ms, 508 tokens). These are call results, not a throughput multiplier.
An early 14-second window had no CPU-throttle/memory-max increments; later
four CPUs throttled in 804/1083 periods. Eight CPUs consumed 26.4 CPU-seconds
in 3.3 s: added headroom is used, but quota throttling continues.
The final 1500-line log tail since 07:10:15 had no 429/errors/timeouts/loop-blocked/
slow-pool reports; this is limited-window evidence.

### Isolated Compute and Rejected Profiles

Direct-backend synthetic token probes under `/tmp/embedding-tuning` are not
end-to-end knowledge-search tests. Two rounds used 32/256/768-token inputs with
distinct prefixes. The 256/768-token comparisons exclude the baseline's unusually
fast first 32-token result (0.0901 s); all six vectors per candidate were finite and
4096-dimensional, which alone does not establish compatibility.

| Trial | 256-token seconds (two rounds) | 768-token seconds (two rounds) | Status |
| --- | --- | --- | --- |
| CPU baseline (`baseline-uncached.jsonl`) | 7.1545 / 7.1488 | 21.8192 / 21.5510 | Reference vectors |
| GPU12 (`gpu12-matched.jsonl`) | 0.3688 / 0.3268 | 0.5396 / 0.4224 | Faster isolated compute; rejected for vector drift |
| CPU16 (`cpu16-native.jsonl`) | 5.5419 / 5.6176 | 17.2765 / 17.2444 | Single-input isolation: ~22% / ~20% lower latency |
| CPU16/four slots (`cpu16-four-slots.jsonl`) | 5.6299 / 5.6691 | 17.0644 / 16.9615 | Six single-vector cosines 1.0; consistency gate failed on this and original profile; rolled back |

GPU12 minimum cosine against the six corresponding baseline vectors is
**0.823862 (~0.824)**; `gpu12-uncached` reproduces that drift. CPU16 has six
successful samples and cosine 1.0 against all six baseline vectors, but its
768-token calls still exceed 15 seconds even in isolation. These samples do
not establish loaded search reliability or ingestion throughput. Vector evidence
is in the matching `*-vectors.json` files; `bench.py` records the method.
The initial isolated CPU16 samples run through 08:07 UTC. Neither single-input
series establishes production-batch compatibility. The **rejected one-slot
profile** used 16 threads/CPUs, `np=1`, native context 40960, preserving the
per-input limit. Its production batch passed four inputs of
**256/768/256/768 tokens (2048 total) in 45.968 s**, with all four vectors
unit-normalized and **cosine 1.0** against their references, using the original
model/build. This batch validates those inputs, **not 40K capacity**.

The later CPU16/four-slot gate triggered rollback. Re-running the **same
`/tmp/embedding-tuning/batch.py` on the restored eight-CPU/four-slot baseline**
also raised `RuntimeError('Batch vector changed')` at the **cosine >0.9999** gate.
That gate compares batch outputs with single-input reference vectors: both
profiles failed this consistency check, so the inconsistency is **not proven
to have been introduced by CPU16**. It does not establish equivalence between
the two profiles' batch outputs either. Required next validation is a comparable
**batch-versus-batch** comparison on the intended runtime profile, followed by
sustained uncached loaded search and durable completed-operation progress.
All new candidate configs were rolled back; no runtime optimization was retained.

### Rejected One-Slot Profile: Loaded Results

`/tmp/embedding-tuning/loaded-search.jsonl` records four queries repeated three
times around 08:15 UTC: **12/12 successful within the 15-second budget**,
minimum 0.273 s and maximum 5.964 s. **All 36 hits are placeholders**, not
generated knowledge. Concurrent health checks passed 12/12 with zero DB pool
waiters. The late test in `/tmp/embedding-tuning/late-search.jsonl` then timed
out **12/12 searches at the 15-second budget** (15.014–15.018 s observed), while
health again passed **12/12 with zero pool waiters**. Saturation reproduced;
the initial success does not establish sustained reliability.

**08:14:56–08:19:56 UTC:** documents 518→519, facts 19227→19244, observations
unchanged at 16, completed operations unchanged at 263 and failures unchanged
at seven. This is partial progress (**+1 document/+17 facts**), with **no
completed-operation gain** or demonstrated ingestion-throughput improvement.

At 08:16:40 UTC, the rejected profile used 1569% embedding CPU and 11.88 GiB
actual RAM (earlier rounded to 11.8 GiB), versus 31.2 GiB on the busy old
backend: roughly 62% lower **only for the rejected profile**, not a lasting
saving. The 62.5 GiB memory limit was unchanged. Chat GPU utilization was 83%,
while Hindsight and DB used little CPU. The early two-minute
Hindsight/proxy/9router log window had no error, timeout or 429 markers. An
embedding log's numeric `429` marker is ambiguous and is **not evidence of an
HTTP 429 error**. This limited window does not establish a sustained error-free run.

### Hindsight Reflection Context Budget (2026-09-12)

Reflection now selects `cx/gpt-5.6-terra` using
`HINDSIGHT_API_REFLECT_LLM_MODEL`, inheriting the global Responses provider,
local gateway URL and credential. Consolidation also selects Terra through
`HINDSIGHT_API_CONSOLIDATION_LLM_MODEL`; Luna remains the default for retain.
Consolidation keeps medium reasoning and concurrency one. Embeddings and
FlashRank are unchanged. Both aliases have the same gateway-declared context
window. Live configuration and templates retain
the 250,000-token guard, medium reasoning and existing concurrency/timeouts.

Global `~/.hindsight/coding-agent.json` and its template now set
`autoReflect: true`, restoring first-prompt synthesis in new Codex sessions.
The installed `dist/codex-hook.js` currently sets `HOOK_REFLECT_CAP_MS = 2e4`
(20 seconds), despite stale comments saying 25 seconds. The 660,000 ms explicit
tool timeout and 1,000-second server wall limit do not increase that hard hook
cap; slow automatic reflections can still time out. No plugin source is changed.
Terra passed synthetic Responses strict-JSON extraction and a medium-reasoning
recall tool round trip in 1.60–2.01 seconds per request. These small probes do
not establish full-corpus reflection latency or guarantee the hook deadline.
Rollback removes the reflect and consolidation model overrides and sets
`autoReflect: false` in live/template settings, updates manifest hashes and
restarts Hindsight.

At the user's request, `HINDSIGHT_API_REFLECT_MAX_CONTEXT_TOKENS` is now
**250,000**, leaving 22,000 tokens below the installed 9router
`cx/gpt-5.6-luna` declared context window of 272,000. The user corrected the
full-window proposal to preserve this margin. This supersedes both the original
32,768 cap and the interim upstream-default 100,000 setting. Under the original
cap, warnings forced final synthesis at
37,565–60,670 estimated accumulated tokens on iterations 3–4. This is the
reflection context guard, not the 1,000-second wall timeout or a completion-token
limit. The installed 9router Luna capability table declares a 272,000-token
context and 128,000-token maximum output; this is gateway metadata, not an
independent measurement of the provider's ultimate limit.

Keep the guard enabled rather than suppressing warnings or dropping evidence.
The 10-iteration limit, 1,000-second wall timeout, 300-second LLM timeout, medium
reflection reasoning, concurrency two, recall/source settings and uncapped
reflection synthesis output remain unchanged. Larger loops can consume more
tokens and time, and reflections that exceed 250,000 estimated tokens may still
legitimately force synthesis. The 22,000-token margin is not an enforced output
reservation. Tool results can overshoot the estimate before the guard runs,
and synthesis/output may exceed the provider's remaining context; this is not a
guarantee against overflow or warnings. This change does not establish answer
correctness or fix unrelated extraction queueing.

The runtime env file and `root/home/user/.config/hindsight/server.env.tmpl`
must agree; update its manifest hash and restart only Hindsight to apply.
Rollback restores the interim 100,000 (or original 32,768) through those same
files and lifecycle. Do not reset
the bank, change models or embeddings, or alter plugin/native code for this
adjustment. Earlier 32K-budget observations below remain historical evidence.

Historical validation at 100,000: the shared-bank ConfigResolver confirmed that
cap and unchanged iteration/time/reasoning/concurrency settings. Those traces
include successful 52K–82K-token inputs, above the former cap. A bounded shared-bank
reflection completed HTTP 200 in 497.865 seconds, returning 4,018 characters;
aggregate usage was 340,371 input and 6,592 output tokens across its calls, not
one context window. No provider-context overflow, timeout or error appeared in
the inspected interval. One larger reflection still reached approximately
144,155 estimated accumulated tokens on iteration 5 and invoked protected final
synthesis. This is remaining legitimate budget enforcement, not a claim that all
warnings disappeared; the guard is evaluated after tool results and can overshoot.
The user subsequently selected 250,000 tokens rather than this default.
No speedup or semantic-correctness claim follows from HTTP success.
Local aggregate probe result: `/tmp/hindsight-reflection-budget-check.json`.
Renderer validation, live/template equality, changed-file secret scanning and
`git diff --check` pass.

### EasyLlama GPU Swapping (2026-09-12)

The user selected llama-swap arbitration rather than disabling local Qwen chat
or shrinking either model's context. Both `qwen3-chat` and `qwen3-embeddings`
now belong to the single `gpu` group with `swap: true` and `exclusive: true`.
The separate CPU embedding group is removed. [Upstream group semantics](https://github.com/mostlygeek/llama-swap/blob/main/docs/kb/guides/routing/groups-and-matrix.md)
allow only one member of a swapping group to run at once. EasyLlama's existing
held `/run` and synchronous `/sleep` lifecycle commands start the requested
backend and wait for the previous process to exit before GPU reuse; no native
code changes or model image updates were needed.

The embedding command uses all CUDA0 layers, `--fit off`, four CPU threads,
and `GGML_CUDA_ENABLE_UNIFIED_MEMORY=0` to avoid CPU fallback. Its container now
has four CPUs, 12 GiB host RAM, no additional host swap and 4 GiB `/dev/shm`.
Model FP16 precision, FP16 KV, 1,024 dimensions, last-token pooling, four slots,
131,072 total context and batch/ubatch 512 are unchanged. FlashRank MiniLM stays
on CPU with batch size 8; Hindsight's LLM stays on 9router Luna Responses.

All normal chat/embedding clients must use authenticated 9router, which forwards
to llama-swap at port 8080. Native 9000/9001 endpoints and lifecycle wake controls
are diagnostics, not alternative production routes: bypassing arbitration can
load both models and exhaust VRAM. Do not independently prewarm both backends.
The existing 1,800-second idle TTL remains; cached files help reloads but no
subsecond switching or persistent native-chat KV state is promised.

Ten synthetic requests through 9router passed, including four concurrent mixed
requests. Warm-file switch-and-request times were 1.739 seconds into embeddings
and 3.708–3.785 seconds into chat; initial embedding load took 2.354 seconds.
Contended embedding requests took up to 5.514 seconds, and a resident embedding
request took 12 ms. All responses were HTTP 200. Ninety-three lifecycle samples
found no simultaneous awake pair or unavailable controller; inspected logs and
container state showed no OOM, load/connection failure or restart. Sampling is
not a proof about every instant, and these short synthetic requests do not bound
waiting behind long chat generations. Aggregate evidence:
`/tmp/hindsight-swap-check.json`.

Persist the group in `root/home/user/.config/easyllama/proxy.yaml.tmpl`, the
command/resources in its sibling `compose.yaml.tmpl`, and the source command in
`config/config.qwen.yml.tmpl`; maintain their manifest hashes. Private rendering
must match `~/.config/easyllama` and the bound EasyLlama runtime proxy file.
For changes, stop dependent services and EasyLlama before replacing owned
containers: its supervisor correctly rejects command/resource drift. Preserve
the previous configuration for rollback. A renamed old container with the same
Compose service labels may be replaced automatically; do not rely on its name
as a durable rollback backup. Preserve volumes and model caches. Restart EasyLlama, 9router and
Hindsight in dependency order. The initial dependency stop also stops 9router;
the database need not stop.

Rollback restores the prior CPU command, resource limits and split groups from
the preceding template versions, updates manifest hashes and private rendering,
and recreates the embedding container through the same supervisor. Never restore
split groups while GPU embeddings remain enabled. Neither migration direction
resets the bank, changes vector identity or retries failed imports.

Post-deployment native synthetic batches took 1.130 seconds serially and
1.023 concurrently; minimum cosine to the earlier CPU reference was 0.999454.
The GPU used approximately 16.5 GiB once active. All four user units (EasyLlama,
9router, Hindsight and PostgreSQL) were active, authenticated Hindsight readiness
and anonymous-access rejection passed, and renderer validation passed 864 files
with no missing values. No GPU-trial or migration rollback container remains;
unrelated older containers were not removed. EasyLlama's tracked source stays
unchanged; only its private generated proxy configuration changes outside dotfiles.

### GPU Embedding and CPU FlashRank Trial (2026-09-12)

Historical isolated trial; the GPU deployment gate below was subsequently
resolved by the user's explicit choice of [GPU swapping](#easyllama-gpu-swapping-2026-09-12).

The user chose to keep FlashRank's existing `ms-marco-MiniLM-L-12-v2` on CPU.
The installed ONNX session reports only `CPUExecutionProvider`. Its approximately
34 MB model remains unchanged; [upstream model sizes](https://github.com/PrithivirajDamodaran/FlashRank)
do not describe process RSS. Keep batch size 8: on 32 synthetic candidates,
three-pass median timings were 1.406/1.393/1.601 seconds for batch 8/16/32;
larger batches changed scores, and batch 32 raised cumulative benchmark-process
peak RSS from 380 to 509 MiB. There is no clear tuning win to deploy.

An isolated full-GPU Qwen3 Embedding 0.6B trial preserved model, 1,024 dimensions,
last pooling, four 32K-token slots, FP16 KV, and batch/ubatch 512. Logs confirm
29/29 layers and all KV layers on CUDA0. Four synthetic batches took 1.287 seconds
serially and 1.240 concurrently, versus 43.003/42.973 on the loaded CPU baseline.
These 33–35x ratios are bounded synthetic results, not sustained ingestion gains.
Mixed-length CPU/GPU minimum cosine was 0.999454, similar to CPU self-variation;
a separate labelled semantic probe achieved 0.999992 and identical top-three
rankings on four queries. Corpus-wide parity is not established.

**At trial time, not deployed:** this profile uses approximately 16.5 GiB GPU memory, including
14 GiB KV, and cannot coexist with the current approximately 29 GiB local Qwen
chat profile on the 32 GiB RTX 5090. Local chat was unloaded only for the trial;
CPU embeddings continued serving Hindsight. Resolve the user's local-chat
preference before activation; do not silently reduce context or add swapping.
That deployment decision is now superseded by the swapping configuration. Local evidence:
`/tmp/hindsight-gpu-tune/REPORT.md`.

### Hindsight Luna Inference (2026-09-12)

The user authorized existing corpus content and future memory requests to reach
the external Codex/Luna provider through authenticated local 9router. Its model
listing contains `cx/gpt-5.6-luna`; Hindsight selects that explicit default route
(reflection and consolidation subsequently override it with Terra),
not a fallback combo, with `LLM_PROVIDER=openai-responses` and the unchanged
local `/v1` base URL and gateway credential. This is an HTTP provider, not a
Codex CLI launch or direct Codex credential configuration.

Use Responses rather than Chat Completions: the synthetic chat probe ignored
the requested JSON schema. Responses passed structured extraction and a
medium-reasoning tool round trip in 1.7–2.3 seconds per synthetic request.
Two actual Hindsight prompt/schema replays returned complete, valid outputs:
1,062 source characters in 27.95 seconds (1,490 output tokens), and 11,956
characters in 42.72 seconds (2,309 tokens). These are bounded single trials,
not equal-quality throughput or pricing evidence. The larger sample retained
6/12 literal reference anchors; do not deploy larger chunks based on speed alone.
The short sample preserved redacted verification text instead of reconstructing
those checks as passed, but source-quality and oversized-job recovery gates remain.

Remove the four Qwen-specific `*_LLM_EXTRA_BODY`/`LLM_EXTRA_BODY` settings;
native `*_REASONING_EFFORT` settings remain low for LLM/retain and medium for
consolidation/reflect. Strict schema, existing concurrency, completion budgets,
timeouts, chunk strategies and authentication remain unchanged. Embeddings stay
on local Qwen3 Embedding 0.6B through `qwen3-chat/qwen3-embeddings`, with 1,024
dimensions and concurrency four. No re-embedding, bank reset or failed-job retry
is part of this switch. Hindsight alone is restarted; native model and database
containers are not restarted or removed.

Configuration lives in `root/home/user/.config/hindsight/server.env.tmpl` and
the private rendered `~/.config/hindsight/server.env`; update its manifest hash
when editing the template. Rollback requires restoring `LLM_PROVIDER=openai`,
`LLM_MODEL=qwen-combo` and the prior Qwen chat-template extra bodies (low for
LLM/retain, medium for consolidation/reflect), then restarting only Hindsight.
Neither direction changes embedding identity or undoes already-extracted facts.
Local aggregate replay evidence: `/tmp/hindsight-luna-test/summary.json`.

Activation at 18:21:35 UTC passed authenticated API readiness and anonymous
API/dashboard rejection checks. The running container's complete embedding-env
hash matches the pre-switch snapshot. Initial production traces include successful
retain extraction, consolidation and reflection tool calls; no parse, timeout,
assertion or authentication errors appeared in the inspected startup interval.
Warnings remain: DB acquisition took 68–76 ms, and a reflection hit its existing
32,768-token context budget and forced final synthesis. These are not evidence
that the import backlog or reflection-quality issues are resolved. Renderer
validation passes all 864 files with no missing values; no native library,
gateway/plugin code, model image or embedding settings changed.

### Hindsight Larger-Output Trial (2026-09-12)

Ten non-streaming requests through the authenticated local Qwen combo passed
JSON/schema validation and ended naturally, with the existing 16,384-token
output budget and the real gateway response-header deadline. Production
ingestion stayed active; no chunk sizes, strategies or queued payloads changed.

The same 11,956-character history sample produced:

| Chunk limit | Requests | Total request time | Output tokens | Literal reference coverage |
| --- | ---: | ---: | ---: | ---: |
| 3,000 characters | 5 | 494.97 s | 24,949 | 11/12 |
| 6,000 characters | 3 | 341.95 s | 16,512 | 7/12 |
| 12,000 characters | 1 | 190.21 s | 8,570 | 7/12 |

A second 11,838-character Git-history sample passed at 12,000 characters in
121.65 seconds, producing 6,707 tokens. No tested request hit a token cap,
gateway timeout or exact duplicate-fact loop. Literal reference matching is only
a coverage proxy, not semantic validation; extracted fact counts differed too.
These are single trials under changing live load, not equivalent-quality
throughput benchmarks.

Some bad verification wording originates in already-redacted source fragments
such as `453 [REDACTED]ed`. Do not reconstruct secrets or assume larger chunks
repair damaged input. Two background Hindsight parse warnings occurred despite
all diagnostic responses passing; production parsing is not declared fixed.
Larger chunks are technically viable on these samples, but global rollout and
checkpoint-changing retries remain deferred pending coverage checks and
provenance-preserving subdivision of oversized jobs. Local content-free evidence:
`/tmp/hindsight-large-output-test/REPORT.md`.

### Hindsight Coverage and Recovery Rehearsal (2026-09-12)

Four further non-streaming Qwen requests added generic reference-preservation
and redaction-uncertainty instructions to the same history sample. All returned
valid JSON/schema and stopped naturally within the existing output budget.

| Chunk limit | Requests | Total request time | Output tokens | Literal reference coverage |
| --- | ---: | ---: | ---: | ---: |
| 6,000 characters | 3 | 331.59 s | 18,052 | 8/12 |
| 12,000 characters | 1 | 210.42 s | 8,734 | 7/12 |

Coverage remains below the earlier 3,000-character 11/12 proxy. More importantly,
outputs still misinterpret redacted verification results, including reconstructing
successful checks. **The prompt failed the factual-fidelity gate**; valid JSON
does not justify rollout. These single trials ran under varying background load.
No prompt, strategy or chunk-size change was deployed.

A separate read-only rehearsal matched all 27 committed chunks of a 728-chunk
failed Git-history job with 156 memories. It proposes 88 bounded parts for the
remaining 701 chunks, excluding existing checkpoints. Nothing was submitted.
Before application, require source-fidelity validation, fresh identity pins,
durable provenance/supersession covering parent retries, and a rollback design
that preserves shared derived data. Failed operations cannot be cancelled;
cancelled operations remain retryable, so cancellation alone cannot enforce
supersession. Local diagnostic reports, not durable source payloads:
`/tmp/hindsight-coverage-test/REPORT.md` and
`/tmp/hindsight-recovery-rehearsal/REPORT.md`.

### Hindsight Retain Admission Trial (2026-09-12)

**Provisional:** `HINDSIGHT_API_RETAIN_LLM_MAX_CONCURRENT=2` (previously 1),
with global LLM concurrency 3. Retain-operation concurrency remains 2 and
worker capacity remains 4, including one shared slot. Lowering the application
gate alone would queue already-claimed jobs; removing the shared worker slot
would block unreserved import, export and maintenance task types. Neither change
was adopted. Models, authentication, strict schemas, reflection wall timeout
1000 seconds, embeddings and other concurrency limits are unchanged.

Two 15-minute production windows, baseline 15:50:30–16:05:30 UTC and candidate
16:23:46–16:38:46 UTC after restart/warm-up:

| Measurement | Baseline → candidate |
| --- | --- |
| Successful extraction calls | 11 → 13 |
| Extraction output tokens | 56,772 → 74,302 |
| New memories / document rows | 137 / 2 → 175 / 1 |
| Fully completed retain jobs | 0 → 0 |
| Median extraction trace duration | 1,787.88 → 625.01 s |
| Matched median native duration | 87.83 → 94.18 s |
| JSON-parse warnings | 0 → 2 |

No new failed retain operations, HTTP 502s, header timeouts, assertions, OOMs or
automatic container restarts were observed. Parse warnings triggered provider
retries; their cause is not established. Global and per-operation strict-schema
inheritance was checked. The candidate is not a demonstrated reliability fix:
inputs differ, restarting resets queue age, and neither window completed a retain
job. Consolidation calls fell 13→11 while reflection calls rose 6→9. Preserve
these trade-offs rather than claiming a universal throughput improvement.

An offline run of the unchanged chunker on 11 failed payloads produced
917 / 605 / 457 / 231 chunks at 3000 / 4500 / 6000 / 12000 characters. One
2,151,632-character Git-history payload accounts for 728 baseline chunks. The
single heading-only fragment disappeared at larger sizes, but larger outputs
could exceed model/transport budgets. No chunk-size, strategy or payload change
was deployed. Bound oversized jobs while preserving source and recovery
checkpoints before broadly retrying this backlog. Local content-free evidence:
`/tmp/hindsight-admission-trial/`.

### Hindsight LLM Concurrency Trial (2026-09-11)

**Historical reliability trial, deployed by app-only restart at 21:18:10 UTC.** Then-current
global/retain/reflect/consolidation LLM caps: **3/1/2/1** (original **4/2/2/1**).
Added `HINDSIGHT_API_REFLECT_MAX_CONTEXT_TOKENS=32768` (default **100000**) and
`HINDSIGHT_API_CONSOLIDATION_LLM_BATCH_SIZE=2` (default **8**); bank configuration
confirms batch **2**.

Native prompts reached **53–63K tokens**, with **300-second read deadlines**.
The earlier **65536-token slot** comparison was incorrect: current `/slots`
exposes `n_ctx=262144` for each chat slot with `--kv-unified`.
This is shared unified capacity across four slots, not four independent
262144-token allocations; the prompt sizes alone do not establish proximity
to a fixed slot limit. Worker `.queued` measures local permit waits.
DB idle/no lock waits and unsaturated embeddings point toward LLM workload;
concurrency-only trials still produced two fresh ReadTimeouts.

The reflection threshold triggers earlier synthesis/history summarization,
**not a hard input cap**, and may reduce context depth. Smaller consolidation
batches group fewer new facts but may require more calls; **no hard token limit**.
Models, authentication/credentials, low/medium reasoning, **300/600-second**
timeouts, resources, bank strategies, DB concurrency **2**, chunk batch **4** and
automatic reflection/observations/consolidation remain unchanged.

Foreground reflection: **HTTP 200/nonempty, 459.508 s**; background: **224.267 s**.
Recall: **44.527 s cold / 25.919 s follow-up**, latter **HTTP 200/nonempty**.
Final **447-second** window: memory **1533→1535 (+2)**, completed retains **27
unchanged**, failed **0**, errors/timeouts **0**; broader monitoring found none
for **≥8 minutes**. The original retried operation remains pending: **imports
are incomplete**. Overall memory **1465→1535** spans all trials, not throughput evidence.
Code/configuration, health/authentication and render/secret checks passed.
This bounded reliability trial proves neither a fix nor a speed/quality gain;
context handling changes only through earlier compaction and smaller batches.
Private backups: `~/.local/share/hindsight/backups/timeout-tuning-*`; no raw data
included here. The following table is **historical, not active**.

### Applied Hindsight Settings

These settings describe the earlier 8B trial checkpoint; API CPUs do not describe
the separate embedding backend, then restored to eight CPUs. Names use `HINDSIGHT_API_` except
Compose/native-library env.

| Scope | Configuration |
| --- | --- |
| API container | `cpus: 8`, `mem_limit: 6G` (baseline 2 CPUs/3G), `memswap_limit: 8G` total RAM plus swap; `shm_size: 4G` unchanged |
| Workers | `WORKER_MAX_SLOTS=4`; `WORKER_RETAIN_RESERVED_SLOTS=1`, `WORKER_CONSOLIDATION_RESERVED_SLOTS=1`, `WORKER_REFRESH_MENTAL_MODEL_RESERVED_SLOTS=1` |
| LLM/retain (historical; [current trial](#hindsight-retain-admission-trial-2026-09-12)) | `LLM_MAX_CONCURRENT=4`, composed with `RETAIN_LLM_MAX_CONCURRENT=2`, `CONSOLIDATION_LLM_MAX_CONCURRENT=1`, `REFLECT_LLM_MAX_CONCURRENT=2`; `RETAIN_CHUNK_BATCH_SIZE=4` |
| Embeddings | `EMBEDDINGS_OPENAI_BATCH_SIZE=4`; unused concurrency env removed |
| Application DB/recall | `DB_POOL_MIN_SIZE=4`, `DB_POOL_MAX_SIZE=24`, `RETAIN_MAX_CONCURRENT=2`, `RECALL_MAX_CONCURRENT=4` |
| FlashRank | `RERANKER_FLASHRANK_BATCH_SIZE=8`; `OMP_NUM_THREADS=2`, `OPENBLAS_NUM_THREADS=2`, `MKL_NUM_THREADS=2` |

Reservations are floors, not caps; one shared slot remains and consolidation
is serialized per bank. PostgreSQL is unchanged: 2 CPUs/2 GiB, max connections
100, shared buffers 128MB, work memory 4MB; no observed OOM/throttle/saturation,
about 1 MiB used of 4 GiB shm. Installed FlashRank does not receive
`RERANKER_LOCAL_MAX_CONCURRENT`; no exposed ONNX thread knob was found.
OpenMP env does not establish an ONNX cap. The installed `hindsight_api` inspected
at that checkpoint contained
neither `HINDSIGHT_API_EMBEDDINGS_MAX_CONCURRENT_REQUESTS` nor `max_concurrent_requests`;
that `OpenAIEmbeddings` supported batch size only. Baseline 1/trial 2 were ignored;
removing the persisted env needs no restart. CLI 0.9.2 does not identify the server.
See [Hindsight configuration][hindsight-config] and [ONNX threading][onnx-threading].

Final rollback checks confirm four active units, protected API/dashboard access,
the three pinned EasyLlama containers, and exact starting live/template hashes.
Embedding `/dev/shm` usage is 0 of 64 MiB: increasing that allocation is not
supported as a remedy for these observed CPU/queue bottlenecks. MCP diagnostics
confirm authenticated `shared` routing and enabled hooks; `synced=false`,
20 active operations, and the inspected knowledge page still contains a placeholder.

Historical validation passes health/auth, EasyLlama checks, security, renderer
862 templates/7 links/no missing values, guard 943/zero findings and diff check.
At that historical checkpoint, five configuration templates and the manifest
were synchronized. At the one-slot deployment checkpoint, CPU16 configuration
templates and manifest were also synchronized. Reported validation then passed renderer
862 templates/7 links/no missing values, guard 943/zero findings, live preflight
health and EasyLlama check; these operational checks were not rerun by this
documentation writer. After the failed four-slot batch gate, reports record
baseline templates/manifest restored, routes verified and Hindsight resumed;
the earlier validation counts do not establish candidate acceptance. Private backups
are under `~/.local/state/dotfiles/hindsight-tuning-*`. Rollback quiesces units,
restores configs and recreates only the verified owned embedding container as
needed; preserve chat and DB volumes. Hindsight rollback is separately scoped.

[swap-config]: https://github.com/mostlygeek/llama-swap/blob/v251/config.example.yaml
[swap-loader]: https://github.com/mostlygeek/llama-swap/blob/4ec317589b21f58b64802c2b3371a179b9fdaa53/internal/config/load.go#L258
[swap-fifo]: https://github.com/mostlygeek/llama-swap/blob/4ec317589b21f58b64802c2b3371a179b9fdaa53/internal/router/scheduler/fifo.go#L15
[swap-admission]: https://github.com/mostlygeek/llama-swap/blob/4ec317589b21f58b64802c2b3371a179b9fdaa53/internal/router/scheduler/fifo.go#L307
[swap-error]: https://github.com/mostlygeek/llama-swap/blob/4ec317589b21f58b64802c2b3371a179b9fdaa53/internal/swaputil/httperror.go#L114
[hindsight-config]: https://github.com/vectorize-io/hindsight/blob/main/hindsight-docs/docs/developer/configuration.md
[onnx-threading]: https://onnxruntime.ai/docs/performance/tune-performance/threading.html

## Hindsight Profile Tuning

**Applied 2026-09-11; bounded validation complete.**
Runtime `get_config` verifies `HINDSIGHT_API_EMBEDDINGS_MAX_CONCURRENT_REQUESTS`
**2→4**, embedding batch **4**, global LLM concurrency **3**. Native embedding
remains **four slots, 32768 tokens/slot**, with unchanged CPU/memory; gateway
admission remains **0**, avoiding the earlier 503 regression.
Chat limits: **24→8 CPUs**, RAM **62.5→32 GiB**, total RAM-plus-swap
**94.5→40 GiB**; threads/batch threads **8**, cache RAM **16384→4096 MiB**,
checkpoints **32→8**. Models, weights, image pins, MTP, GPU placement, Q8 KV,
**262144 shared context/four slots**, authentication, reasoning, timeouts and
reflection budget are unchanged. No extension, library or source edits.

| Probe | Baseline → candidate | Interpretation |
| --- | --- | --- |
| 32 embeddings, two workers | 53.849 → 46.359 s | Warm-up/cache-hit bias; no speedup claim |
| 32 embeddings, four workers | 53.079 → 52.840 s | Approximately equal; no demonstrated embedding speed gain |
| Four parallel chat calls | 1.168 → 1.698 s cold / 1.530 s warm | Warm outputs 173 → 186 tokens; not strictly deterministic; slowdown cannot be ruled out |
| Long chat, 17,748 prompt tokens | 4.569 → 6.024 s mostly cold / 4.665 s warm | Warm comparison: 81 output tokens each |

All **64 isolated vectors per profile** passed 1024-dimensional/unit-norm checks.
The initial synthetic chat omitted `stream:false`, producing an invalid response
envelope; explicit false passed. This was a benchmark fix, not a production change.
Baseline chat cgroup current/peak was **19.3/21.5 GiB**, mostly anonymous memory,
without OOM/swap; RTX 5090 VRAM was **30809/32607 MiB (~30.1/31.8 GiB)**. Candidate isolated
peak **4.55 GiB** used fresh caches: reduced limits are verified, but this comparison
does not prove a causal reduction in memory use.

After ingestion resumed, **16/16 mixed-traffic vectors** passed at
**11.676–34.262 s**; long chat **0.992 s** was a cache hit. Recall returned
**three results in 59.918 s** under stress; normal probes returned three each in
**27.496/27.791 s**. Residual normal-recall latency remains; without a comparable
baseline, causality is unestablished. One CPU snapshot showed Hindsight **~800%**,
embedding **~100%**, chat **~120%**, suggesting investigation of application CPU
work, not proving a reranker cause. FlashRank `ms-marco-MiniLM-L-12-v2`,
`RERANK_MAX_CONCURRENT=8` and `OMP=8` remain unchanged.

All services are active with no automatic restarts; replay is active/exited
successfully. Since startup **23:23:54 UTC**, the observed window has no ERROR,
timeout, OOM or assertion events; warnings include slow DB acquisition
**60–103 ms** and the existing reflection-budget guard forcing final synthesis.
Ingestion advanced **2070→2094 memories**,
**69→70 documents**, completed retains **33→34**, with no failed operations.
This bounded progress does not establish full-backlog completion.

Exact-profile checks and supervised adoption of Compose project
`easyllama-profile-20260911` pass; images and embedding/proxy container IDs are
unchanged. The old chat container remains stopped with suffix `-rollback-20260911`;
private recovery snapshots are at `~/.local/share/easyllama/backups/profile-20260911`.
Three configuration templates and manifest hashes changed. Checks: renderer **864 files/
7 links/no missing values**, secrets guard **945 files/zero findings**.

## Hindsight 0.6B Migration

Unmodified source and 0.6B CPU embeddings replace the historical 8B requirements.
Qwen chat, FlashRank reranking, authentication and service URLs are unchanged.

### Source and Image Identity

Source: [upstream commit `48b62ee08170b464f4c42b6f133b7cb798a59b21`](https://github.com/vectorize-io/hindsight/commit/48b62ee08170b464f4c42b6f133b7cb798a59b21).
Published release [0.9.2](https://github.com/vectorize-io/hindsight/releases/tag/v0.9.2)
lacks remote embedding concurrency; this build still reports package **0.9.2**.
Label by commit, `dotfiles/hindsight:48b62ee08170`, not a fabricated release.
Verified image ID:
`sha256:28cc61a710db573b9e7701c9545b89e120a1a48d6c6d2279cb895a555e160f5f`.
At the migration checkpoint, `get_config` confirmed parallel embedding batch
concurrency **2** (now **4**; see [profile tuning](#hindsight-profile-tuning)) through
`HINDSIGHT_API_EMBEDDINGS_MAX_CONCURRENT_REQUESTS`. This is **not a universal
per-request hard cap**: upstream single-batch/concurrency-1 fast paths bypass the
shared semaphore.

`root/home/user/.config/hindsight/build.json` selects upstream
`docker/standalone/Dockerfile`, target `standalone`,
`PRELOAD_ML_MODELS=false`, `INCLUDE_LOCAL_MODELS=true`.
`scripts/hindsight.sh install|update` builds/reuses a verified
`~/.local/state/dotfiles/hindsight-build.json` receipt and renders the immutable ID
through private `HINDSIGHT_IMAGE`. Existing-build adoption requires recipe attestation.
`--no-start` makes no service changes; check/dry-run are read-only. Routine actions
never reset banks; updates restart only the app, leaving the database running.
Base images/OS dependencies float: a pinned commit is not bit-reproducible.
Exact recovery requires the archived image and matching receipt, not just a tag.

### Model and Standalone Evidence

| Item | Deployed value |
| --- | --- |
| Official model | Qwen3 Embedding 0.6B FP16, `Qwen3-Embedding-0.6B-f16.gguf` |
| Hugging Face revision | `370f27d7550e0def9b39c1f16d3fbaa13aa67728` |
| GGUF SHA-256 | `421a27e58d165478cc7acb984a688c2aa41404968b0203e7cd743ece44c54340` |
| Representation | Width 1024; native context 32768; LAST pooling |
| CPU profile | Eight threads, four slots, context 131072 (32768/slot), `-b 512 -ub 512` |

EasyLlama install/update downloads from pinned
`root/home/user/.config/easyllama/model.json`; [official snapshot](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/tree/370f27d7550e0def9b39c1f16d3fbaa13aa67728).
Standalone single/batch/permutation/parallel vectors are finite, normalized and
cosine **>0.9999** (minimum about **0.9999438**). Uncached synthetic 768-token CPU
calls took **4.6541–4.9692 s**, versus old 8B **~21.7 s**: **~4.4–4.7×** for this
isolated probe, not production search/ingestion throughput or retrieval-quality proof.
New GPU candidates passed consistency but left only **~300 MiB** headroom and were
rejected; the earlier 8B GPU drift finding remains valid.
Persistent evidence under `~/.local/share/hindsight/imports/qwen06b-20260911/`:
`benchmark.json` and `early-rebuild-assessment.jsonl`.

### Backup and Recovery

Backup root: `~/.local/share/hindsight/backups/qwen06b-20260911T164040Z`.
The **initial** SHA-manifested backup contained **48 files, 1,824,400,409 bytes**;
later additions include `frozen.dump` and `frozen-manifest.json`, with hashes for
six recovery exports. Those initial counts are not the final backup inventory.
The dump passed **`pg_restore --list` only; full restore remains UNTESTED**.
Canonical `hindsight` was recreated on the **same PostgreSQL instance**, with the
same owner/`vchord` and 1024-dimensional `memory_units`/`mental_models`.
The old DB remains intact as `hindsight_8b_20260911`, not dropped; the empty
diagnostic DB was removed. Retain old DB/dumps, configs, manifests and receipts.

Private exact-image archive (~718 MB):
`~/.local/share/hindsight/images/hindsight-48b62ee08170.tar`, SHA-256
`538b1e256cbdeaf44c08682d9d99733976ea65f65040283e8bf69a04e75589a4`.
Restore its matching build receipt plus component lifecycle receipt; helper
`build-image --archive` validates image identity. User data needs separate recovery.
See [fresh-host rendering and recovery](../../../README.md#hindsight-installation-and-activation).
Restoring the old canonical DB and matching app/model is an explicit recovery
action, not routine install/update behavior.

### Replay Corpus and Definitions

Exact coverage: **19,381 unique records = 19,306 originals + 75 pending extras**,
in **1,619 strategy-homogeneous batches**. The earlier 922 count described
named-strategy items, not unique extras; all 558 exported documents overlap original
IDs. The 20,228 raw entries supply metadata/strategies; 17 pending appends were
folded chronologically into one existing conversation. Original receipts survive.
Ten pinned mental models are restored: five defaults reused by name, five custom models
created with old IDs. **2026-09-11, 17:32:48 UTC:** API `knowledge-base/tree` verifies
**ten visible pages**; each of the five custom page GETs returns **200**. Metadata-only
repair restored one folder and five custom registrations, preserving all five defaults.
`page-map.json` maps old page NODE IDs to new default NODE IDs; `definition-map`
maps backing MODEL IDs. Scoped explicit `[[page:oldnode]]` source-query references
were remapped; no vectors/generated content copied. Bulk processing remains ongoing;
page restoration and its operations do not establish completed replay processing.

### Verified Deployment and Replay Status

**2026-09-11, 17:18:21 UTC: all 1,619 batches/19,381 records accepted;
bulk processing ONGOING, not complete.** `hindsight-reimport.service` is
active/exited, Result=success, zero restarts; app `BindsTo`/`WantedBy` and
idempotent receipts govern replay. Acceptance does not mean completed processing.
SQL snapshot: **three documents, 161 memories**, actual vector width **1024**.
Completed: **two retains, two batches, six page refreshes**. Processing:
**one consolidation, one refresh, two retains**; **zero failed**.

Hindsight/EasyLlama lifecycle checks PASS; renderer **864 files/seven unit links/
no missing values**; guard **945 files/zero findings**. `update --no-start` verified
image reuse, existing CLI and no DB restart. Codex diagnostics confirm `shared`,
matching token and active hooks; configuration health does not establish full sync.
Authenticated API **200**; anonymous API/dashboard **401**. No APIERROR, Traceback,
429, dimension-mismatch or connection-refused signatures in the inspected ten-minute window.
9router cold embedding **6.381 s**, chat **3.612 s**, warm embedding **0.034 s** pass;
cached responses/batch latencies do not measure isolated uncached throughput.

Early rebuild searches and health checks each pass **12/12**; search median
**0.0595 s**, max **5.844 s**, versus old loaded **0/12**. The new bank had few facts:
this proves early responsiveness only, **not an apples-to-apples full-corpus comparison**.

| Container | Observed memory | Unchanged limit |
| --- | --- | --- |
| Embedding | 16.62 GiB vs old ~29–31 GiB | 62.5 GiB |
| API | 471 MiB | 6 GiB |
| Database | 226 MiB | 2 GiB |

Memory figures are measured snapshots, not peak loads or configured-limit reductions.

### Replay Startup Readiness

Replay’s 14:08:00 PDT `AssertionError` preceded container startup (14:08:01)
and API readiness (14:08:06), exhausting three starts/hour.
`Type=simple`/`After=` orders launch, not readiness.

**Code/Security-approved unit-only fix:** `ExecStartPre` uses
`/usr/bin/timeout --kill-after=5s 180s`, `/bin/sh` and `/usr/bin/curl -q`
(first option ignores curlrc), polling credential-free database health at
`http://127.0.0.1:8888/health` for exact HTTP 200: three-second requests,
two-second sleeps. Strict image/database-OID/bank-ID/1024D/model-identity/ledger
guards and replay remain unchanged; no helper/source/library changes.
The private one-time epoch unit is not bootstrapped.

**Verified:** real unit active/exited, `Result=success`, `ExecMainStatus=0`.
Disposable-unit tests passed: delayed 503→200 **2.294s**, persistent 503
**4.246s**, redirect 302 **4.249s** (test deadline four seconds; production 180).
Entire SQLite/source SHA-256 and all five backend container IDs/start timestamps
are unchanged. All **1,619 batches** remain accepted; accepted-batch skipping
and byte-identical ledger establish no resubmissions.
Backups: `~/.local/share/hindsight/backups/replay-readiness-20260911T225733Z`.

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
Remote-client SSH and Taildrive end-to-end tests remain unperformed. These HTTPS
checks included neither an off-tailnet public-access probe nor a host reboot.

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
Coordinator startup consumes no tailnet API credentials, does no
provisioning/enrollment or tailnet API mutation, and launches no model/API probes.
It must verify expected native identity and tags
before applying reviewed Service configuration and must not restore Funnel.
Starting `9router.service` pulls it in and re-executes its configuration action.
Phase 2 replay of `tailscale.service` idempotently validated the captured Service.
The later reboot incident, recovery validation and remaining reboot limitation are recorded in
[boot recovery](#boot-recovery).

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

**Local removal complete, 2026-09-10 (PDT).** The exact checks covered the
template hash and verified both masks were inactive with no reverse dependencies
or enablement links. Removal covered only
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
were not run.** Model discovery establishes inventory only. Phase 2 verification
included neither a full host reboot nor an off-tailnet public-access probe; see
[boot recovery](#boot-recovery) for the later incident, verified recovery checks
and remaining reboot limitation.

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

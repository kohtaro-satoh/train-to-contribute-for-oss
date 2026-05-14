### What feature do you want to see added?

Follow-up to #321 — proposes a concrete, minimal-surface design for the "synchronize locked resources between multiple Jenkins instances" idea.

> **Status of this body:** updated to reflect the finalized Phase 1 shape after the discussion in this thread (transparent DSL with optional `forcedServerId`, plus a `GET /resources` endpoint and the configuration surface in [this comment](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025#issuecomment-4373800000)). Sections "Configuration surface" through "Phase 1 scope" below are the authoritative Phase 1 specification.

## Summary
Add an opt-in mechanism that lets `lock(...)` use a resource managed by another Jenkins. Two operating modes are provided through a single configuration field:

- **Peer mode** (default): a pipeline can opt into a specific remote with `lock(..., serverId: 'X') { body }`. Existing single-Jenkins `lock()` is unchanged.
- **Delegated mode** (when `forcedServerId` is set on the local Jenkins): plain `lock('X') { body }` is transparently routed to the configured remote Jenkins. The pipeline does not need to know about remoteness.

In both modes:
- The `{ body }` passed to `lock()` still executes on the local Jenkins.
- The remote Jenkins is the **single source of truth** for its resources.
- Authentication uses a Jenkins username/password credential (username = remote service account, password = its API token), referenced by `credentialsId` on the local side.
- All Jenkins-to-Jenkins traffic is **local → remote only** (no inbound connections back from remote to local).
- Communication failures are handled fail-closed; locks are **not** auto-released.

Inspired by the "lockable-master / lockable-slave" idea in [#321 (comment)](https://github.com/jenkinsci/lockable-resources-plugin/issues/321#issuecomment-1412529601). Delegated mode achieves that centralized arrangement with a single configuration field rather than a new role for the Jenkins; peer mode is preserved so Jenkins instances can also share resources mutually as independent peers.

> Note: earlier drafts of this idea used the word "federation". The final shape is a much smaller surface — minimal **remote locking** with transparent DSL and an explicit override. Broader federation concerns (multi-server routing, replication, HA, etc.) are intentionally left as future work.

## Goals
- `lock('X') { body }` works transparently against a remote Jenkins when `forcedServerId` is configured (delegated mode).
- `lock(..., serverId: 'X') { body }` is available as an explicit per-call override (peer mode, debugging, operational overrides).
- The `{ body }` passed to `lock()` still executes on the local Jenkins in all modes.
- The remote Jenkins is the **single source of truth** for its resources (availability, queue, timeout, selection strategy).
- Backward compatible: when `forcedServerId` is unset and no `serverId` argument is given, behavior is identical to today's single-Jenkins `lock()`.
- Authentication via a Jenkins username/password credential (service user + API token), referenced by `credentialsId` on the local side.
- All Jenkins-to-Jenkins traffic is **local → remote only** (no inbound connections back from remote to local).
- Safety-first on communication failures (do **not** auto-release locks).
- Assumed scale: **small to medium deployments**; a few-seconds polling delay and modest network overhead are acceptable.
- **Remote resources must be pre-declared.** The remote Jenkins will **never auto-create** a resource or label that is not already registered (no ephemeral / on-the-fly resource creation over the remote API).
- The "local → remote only" rule applies **per relation**, not per Jenkins instance; Jenkins instances may simultaneously hold multiple independent relations (e.g. A→B for B's resources, B→A for A's resources, A→C for C's resources), enabling mutual sharing without any bidirectional channel.

## Non-goals (initial)
- No `serverId: 'any'` / multi-server routing.
- No long-polling or push-based notifications (short-polling only).
- No cross-Jenkins state replication for lock decisions.
- No automatic lease-based release of locks.
- No freestyle project support in the first phase.
- No distributed consensus / HA orchestration.
- No transparent "federation" across multiple Jenkins instances.
- No auto-creation of ad-hoc / ephemeral resources or labels via the remote API (even though local `lock()` may create them for local use).
- No plugin-specific client allow-list in Phase 1; the remote API is protected by Jenkins' standard authentication and authorization.

## High-level design
- The local side is a thin REST client around `lock()` semantics.
- The remote side exposes a versioned REST API under `/lockable-resources/remote/v1/`, separate from the existing `/lockable-resources/api` (different audience: machine-to-machine, not human UI).
- The remote API is **off by default** (`remoteApiEnabled = false`); installations are unaffected by upgrade until an administrator opts in.
- All transport is initiated by the local side (local → remote only).
- The local side uses **short-polling** (a few-seconds interval) to observe acquisition state; no long-polling is used.
- The remote side tracks `lastSeenAt` per lease; leases with no heartbeat become `STALE` in UI but are **not** auto-released.
- **Resource existence is enforced at acquire time.** If the requested resource name or label does not match any pre-declared, exposed resource on the remote, the request is rejected immediately (HTTP error), with no lock state created and nothing to poll.
- HTTP method policy:
  - **POST** acknowledges requests and state transitions only (returns "accepted" / error; never returns acquisition outcome).
  - **GET** is the single source of truth for acquisition state and lease inspection.
  - Rationale: keeps the client loop uniform (`POST /acquire` → poll `GET /acquire/{requestId}` → act on state).

### DSL resolution rules (Phase 1)
```
if forcedServerId is set:
    target = (forcedServerId, name)        # all locks are delegated to that remote Jenkins
                                           # an explicit serverId argument is silently ignored
                                           # (an INFO line is written to the build log)
else:
    if lock(..., serverId: 'X') is given:
        target = (X, name)                 # explicit override (peer mode / debugging)
    else:
        target = (LOCAL, name)             # original single-Jenkins behavior
```

In delegated mode, **local resource definitions on this Jenkins are not used at all**: resolution always goes to the remote Jenkins, the LR page shows the remote's published resources only, and unknown names fail immediately as `UNKNOWN_RESOURCE`. This eliminates name-collision questions and prevents "I thought I locked the remote one but actually locked a local one" accidents.

### Mutual sharing via multiple independent one-way relations
- The `local → remote only` rule is about **a single client/server relation**, not about the roles of the two Jenkins instances overall.
- Any number of Jenkins instances can freely establish **multiple independent one-way relations** at the same time. For example, between A and B (the same pattern extends to A↔C, B↔C, and so on):
  - For resources owned by B: A is local, B is remote. (A opens outbound HTTP to B with A's `credentialsId`.)
  - For resources owned by A: B is local, A is remote. (B opens outbound HTTP to A with B's `credentialsId`.)
- Each relation still obeys the same rules:
  - the single source of truth is the remote side of that relation,
  - traffic is initiated only by the local side of that relation,
  - failures are handled fail-closed on the local side of that relation.
- This yields **mutual sharing without any new concept**: no bidirectional channel, no "peer" role at the protocol level, no replication. Just ordinary one-way remote-lock relations coexisting.

Example (peer mode, explicit `serverId`):
```
A's pipeline:  lock(resource: 'board-a1',  serverId: 'B') { ... }
   # A is local, B is remote. A → B HTTP only.

B's pipeline:  lock(resource: 'license-x', serverId: 'A') { ... }
   # B is local, A is remote. B → A HTTP only.

A's pipeline:  lock(resource: 'staging',   serverId: 'C') { ... }
   # A is local, C is remote. A → C HTTP only.
```
Each Jenkins acts as *local* for its own pipelines and as *remote* for resources it owns. The roles are per-relation, not per-Jenkins.

### REST endpoints (`/lockable-resources/remote/v1/*`)
Where `(base)` = `/lockable-resources/remote/v1` in the listing below. While `remoteApiEnabled = false`, all endpoints respond as if the API did not exist.

Acquire lifecycle (request side):
- `POST (base)/acquire` — enqueue an acquire request. Returns `{requestId}` on acceptance.
  Request body may include `heartbeatIntervalSeconds` (optional in v1; see "Client-declared heartbeat interval" below).
  **Does not return the acquisition outcome**; callers must read `GET (base)/acquire/{requestId}` to observe the result.
  Accepts `skipIfLocked` as a hint; the outcome still materializes via `GET` as state `ACQUIRED` or `SKIPPED`.
  Rejected immediately (HTTP 4xx) if the resource/label is unknown or not exposed (e.g. `UNKNOWN_RESOURCE`, `UNKNOWN_LABEL`); no `requestId` is issued.
- `GET  (base)/acquire/{requestId}` — authoritative acquisition state: `QUEUED` / `ACQUIRED` / `SKIPPED` / `FAILED` / `CANCELLED` / `EXPIRED`.
  Polled by the local side every few seconds.
- `POST (base)/acquire/{requestId}/cancel` — cancel a pending (not yet acquired) request.

Lease lifecycle (after acquisition):
- `GET  (base)/lease/{leaseId}` — inspect a currently held lease (diagnostics / UI). Response includes the negotiated `heartbeatIntervalSeconds` and the resulting `staleThresholdSeconds`.
- `POST (base)/lease/{leaseId}/heartbeat` — liveness signal from the local side while the body runs.
- `POST (base)/lease/{leaseId}/release` — release the lease when the body finishes (or is aborted).

Discovery:
- `GET  (base)/resources` — list resources currently exposed by this remote Jenkins (name, labels, description). State is intentionally **not** included to keep the endpoint cheap and cacheable; lease/state lookups continue to go through the per-lease endpoints. The local side short-caches this list to render its LR page.

### Client loop (reference)
```
requestId = POST /acquire {..., skipIfLocked?, heartbeatIntervalSeconds?}
  # HTTP 4xx if resource/label is unknown or not exposed -> surface error, stop.
loop every few seconds:
    r = GET /acquire/{requestId}
    switch r.state:
      QUEUED    -> continue polling
      ACQUIRED  -> run body; send heartbeat periodically; POST release on exit
      SKIPPED   -> do not run body (skipIfLocked path)
      FAILED    -> surface error
      CANCELLED -> stop
      EXPIRED   -> stop (future: when maxWaitSeconds is set)
```

## Configuration surface (Phase 1)
Roles are **per relation**, not per Jenkins instance — a single Jenkins can act as "server" for one relation and as "client" for another at the same time.

### Server-side settings (the Jenkins that exposes resources)

| Setting | Default | Notes |
|---|---|---|
| `remoteApiEnabled` | `false` | Master switch. While `false`, all `/remote/v1/*` endpoints respond as if the API did not exist. Keeps existing installs unaffected by upgrade. |
| `exposeLabel` | *(unset)* | A single label name. Only resources carrying this label are visible/acquirable through the remote API. **When unset, nothing is exposed** (opt-in). |

Notes:
- No plugin-specific allow-list of clients in Phase 1. The remote API is protected by Jenkins' standard authentication and authorization (API token), exactly like other Jenkins REST endpoints. A plugin-level allow-list / dedicated permission can be revisited in a later phase if there is demand.
- No per-server queue limit, no per-resource QoS in Phase 1.

### Client-side settings (the Jenkins that initiates remote locks)

`remotes` is configured as a map keyed by `serverId`:

| Setting | Notes |
|---|---|
| `remotes[<serverId>]` | Map of remote connections, keyed by the logical name **assigned on the client side**. The key is referenced from `lock(..., serverId: 'X')` and from `forcedServerId`. |
| `remotes[<serverId>].url` | Base URL of the remote Jenkins. |
| `remotes[<serverId>].credentialsId` | Jenkins Credentials ID. Expected to be a **username/password** credential whose username is the service account name on the remote Jenkins and whose password is that account's API token. |
| `forcedServerId` | Optional. When set, must match a key in `remotes`. Setting this turns the local Jenkins into delegated mode. |

Notes:
- `serverId` is purely a **client-side alias** for a remote URL + credentials pair. The remote Jenkins is not aware of this name. The LR page on the client side shows this `serverId`.
- `pollIntervalSeconds`, `heartbeatIntervalSeconds`, `requestTimeoutSeconds` are **not exposed as user settings in Phase 1**. They are implementation-internal constants for now (see "Client-declared heartbeat interval" below for how the value is still future-proof at the API level).

### Validation
- `forcedServerId`, when set, must match a key in `remotes` (otherwise: configuration error at save time).
- The "delegated mode" badge is shown clearly on the LR page when `forcedServerId` is set, so administrators are not surprised by the change in resolution semantics.

### Explicitly out of scope for Phase 1 configuration
- Multiple `forcedServerId` entries / failover.
- A server-side "accept new acquires: ON/OFF" maintenance switch (Phase 2 candidate).
- Plugin-level client allow-list, per-client QoS, per-resource queue limits.

## Client-declared heartbeat interval (forward-compatible default)
`pollIntervalSeconds` and `heartbeatIntervalSeconds` are **not user-configurable in Phase 1**, but they are not symmetric: the client decides how often it sends `heartbeat`, and the server must decide when a lease becomes `STALE`. To keep these two sides consistent — and to leave room for making the interval configurable later **without bumping the API version** — Phase 1 already carries the heartbeat interval on the wire.

`POST /lockable-resources/remote/v1/acquire` request body:
```jsonc
{
  "resource": "X",
  "skipIfLocked": false,
  "heartbeatIntervalSeconds": 10   // optional in v1
}
```

- `heartbeatIntervalSeconds` is **optional** in v1.
- If omitted, the server uses its built-in default (currently 10s).
- If outside the server's accepted range, the server rejects the request with HTTP 400 (`INVALID_HEARTBEAT_INTERVAL`). Silent rounding is intentionally avoided so misconfiguration is visible.

Server-side `STALE` threshold (Phase 1, hard-coded):
```
staleThresholdSeconds = max(heartbeatIntervalSeconds * 6, 60)
```
The factor (`6`) and the lower bound (`60s`) are hard-coded in Phase 1. They can be revisited later without changing the API contract.

`GET /lockable-resources/remote/v1/lease/{leaseId}` response includes both the negotiated `heartbeatIntervalSeconds` and the resulting `staleThresholdSeconds`, so operators can see exactly which values are in effect.

If we omitted `heartbeatIntervalSeconds` from v1 and added it later, every client that wants to use it would force a v2. Adding it now as an optional field means a future "make heartbeat interval configurable" change is just a UI/setting addition — the API contract does not move.

## UI updates on the local (client) side
- **Peer mode** (`forcedServerId` not set): the LR page shows local resources as today, plus any active remote leases this Jenkins currently holds (with their `serverId`).
- **Delegated mode** (`forcedServerId` set): the LR page shows the remote's published resources (from `GET /resources`) and the current remote leases held by this Jenkins. Local resource definitions are hidden or shown as "not used in delegated mode".
- In both modes, the displayed remote state is explicitly labeled as the **client-side cached view**, not the authoritative state on the remote Jenkins.

This way, what the user sees on the LR page and what `lock('X')` will actually try to acquire stay consistent.

On the server (remote) side, the LR page shows the client identifier (e.g. authenticated API user) in the status column for active remote leases, so administrators can tell which client holds what.

## Phase 1 scope (finalized)
Included:
- REST API on the remote side under `/lockable-resources/remote/v1/`:
  - `POST /acquire` (with optional `heartbeatIntervalSeconds`), `GET /acquire/{requestId}`, `POST /acquire/{requestId}/cancel`
  - `GET /lease/{leaseId}` (returns negotiated heartbeat / stale values), `POST /lease/{leaseId}/heartbeat`, `POST /lease/{leaseId}/release`
  - `GET /resources`
- DSL: `lock(..., serverId: 'X')` as explicit override; transparent `lock('X')` resolution under `forcedServerId`.
- Configuration surface: `remoteApiEnabled`, `exposeLabel` on the server side; `remotes` (map) and `forcedServerId` on the client side.
- LR page integration on both sides as described above.
- Safety/versioning: heartbeat → STALE only (no auto-release), fail-closed on errors, versioned path with 404/410 for retired versions, remote API protected by Jenkins' standard authentication/authorization.

Out of scope for Phase 1 (deferred or rejected):
- Multiple remote Jenkins instances with failover / round-robin.
- State mirroring / replication between Jenkins instances.
- Fixed master/slave roles at the Jenkins-instance level.
- `serverId: 'any'` style automatic selection.
- Cross-server label resolution.
- Server-side maintenance "pause new acquires" switch (good idea — Phase 2 candidate).
- User-configurable polling / heartbeat / timeout values (the heartbeat interval is already carried on the wire, so enabling configuration later does not require an API version bump).
- Plugin-specific client allow-list or dedicated remote-API permission.

## Background & motivation
Detailed background notes live in my sandbox repo (work-in-progress, English drafts):
- [Background & motivation](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/blob/main/docs-e/remote-lock-background-e.md)
- [Realworld usecase (small/medium scale)](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/blob/main/docs-e/remote-lock-usecase-e.md)
- [Design rationale](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/blob/main/docs-e/remote-lock-design-notes-e.md) — *initial draft; predates the transparent-DSL / `forcedServerId` direction. The authoritative Phase 1 specification is this issue body (Sections "Configuration surface", "Client-declared heartbeat interval", "UI updates", and "Phase 1 scope").*
- [Existing plugin architecture notes](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/blob/main/docs-e/lockable-resources-architecture-e.md)

(Japanese originals are under [`docs-j/`](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/tree/main/docs-j) in the same repo. The corresponding [`remote-lock-design-notes-j.md`](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/blob/main/docs-j/remote-lock-design-notes-j.md) carries the same caveat — it reflects the original idea and is not the latest specification; this issue is the source of truth.)

## Phases (sub-Epics, to be filed)
- [ ] **Phase 1** — Remote lock via REST + transparent DSL + remote resource list view
  - M1: Core REST API + explicit `lock(..., serverId: 'X')` (peer mode only).
  - M2: `forcedServerId` resolution and the LR page mode-switching behavior.
  - M3: `GET /resources` and the client-side LR page integration with the remote view.
- [ ] **Phase 2** — Operations & observability hardening
  - Server-side maintenance switch ("accept new acquires: ON/OFF").
  - User-configurable polling / heartbeat / timeout values (the wire format already supports this).
  - Optional plugin-level client allow-list / dedicated remote-API permission, if there is demand.
- [ ] **Phase 3** — Future extensions (only if demand emerges)
  - Multi-server routing / failover.
  - Folder-level or job-level overrides.
  - Anything that today sits in "Non-goals".

> Sub-Epic issues will be filed for each phase as they begin. Please discuss the high-level design here; phase-specific implementation details can wait.

## Open questions
Most of the original open questions have been resolved in the discussion above. Remaining items where additional input is welcome:

- Default polling interval (current internal value: 3s).
- Default heartbeat interval / stale threshold (current internal values: 10s / `max(heartbeat × 6, 60s)`).
- Exact error shape (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`) and HTTP status codes — to be finalized during Phase 1 implementation.
- UI integration details for remote entries (merged vs separate tab, badge styling for delegated mode).
- Representation of remote owner/build identity in UI and logs on the server side.

### Upstream changes
No. The proposal can be implemented within this plugin alone.

### Are you interested in contributing this feature?
Yes. I plan to work on it in phases (see Phases section above). The first draft of Phase 1 (M1) will follow this body update.
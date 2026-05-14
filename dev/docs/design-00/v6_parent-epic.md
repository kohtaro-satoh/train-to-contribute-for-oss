> 🧪 **Practice / Draft.** This issue is a personal practice sketch on my sandbox repo.
> 本番設計ではなく、練習用の草案です。本家 `jenkinsci/lockable-resources-plugin` に提案する前の勉強メモとして書いています。

---

Related (upstream, not auto-linked):
`https://github.com/jenkinsci/lockable-resources-plugin/issues/321`

## Summary
Add an opt-in mechanism that lets `lock(...)` target a resource managed by
another Jenkins controller via an explicit `serverId`, without changing
the semantics of existing single-controller `lock()`.

Inspired by the "lockable-master / lockable-slave" idea in
`https://github.com/jenkinsci/lockable-resources-plugin/issues/321#issuecomment-1412529601`
and scoped down to an **explicit, lightweight, safety-first** design.

> Note: in #321 I initially described this as "federation support",
> but after fleshing out the design I decided to start from a much
> smaller surface — a minimal **remote locking** extension with
> explicit routing (`serverId`). Broader federation concerns
> (multi-server routing, replication, HA, etc.) are intentionally
> left as future work.

## Goals
- `lock(..., serverId: 'Remote1') { body }` delegates the lock decision
  (availability, queue, timeout, selection strategy) to the remote controller.
- The body still executes on the local controller.
- The remote controller is the **single source of truth** for its resources.
- Backward compatible: without `serverId`, behavior is unchanged.
- Authentication via Jenkins service user + API token, referenced by
  `credentialsId` on the local side.
- All controller-to-controller traffic is **local → remote only**
  (no inbound connections back from remote to local).
- Safety-first on communication failures (do **not** auto-release locks).
- Assumed scale: **small to medium deployments**; a few-seconds polling
  delay and modest network overhead are acceptable.
- **Remote resources must be pre-declared.** The remote side will
  **never auto-create** a resource or label that is not already
  registered (no ephemeral / on-the-fly resource creation over the
  remote API).

## Non-goals (initial)
- No `serverId: 'any'` / multi-server routing.
- No long-polling or push-based notifications (short-polling only).
- No cross-controller state replication for lock decisions.
- No automatic lease-based release of locks.
- No freestyle project support in the first phase.
- No distributed consensus / HA orchestration.
- No transparent "federation" across multiple controllers.
- No auto-creation of ad-hoc / ephemeral resources or labels via the
  remote API (even though local `lock()` may create them for local use).

## High-level design
- Local side is a thin REST client around `lock()` semantics.
- Remote side exposes a versioned REST API under
  `/lockable-resources/remote/v1/`, separate from the existing
  `/lockable-resources/api` (different audience: machine-to-machine,
  not human UI).
- All transport is initiated by the local side (local → remote only).
- The local side uses **short-polling** (a few-seconds interval) to
  observe acquisition state; no long-polling is used.
- Remote tracks `lastSeenAt` per lease; leases with no heartbeat become
  `STALE` in UI but are **not** auto-released.
- **Resource existence is enforced at acquire time.** If the requested
  resource name or label does not match any pre-declared resource on
  the remote, the request is rejected immediately (HTTP error), with
  no lock state created and nothing to poll.
- HTTP method policy:
  - **POST** acknowledges requests and state transitions only
    (returns "accepted" / error; never returns acquisition outcome).
  - **GET** is the single source of truth for acquisition state and
    lease inspection.
  - Rationale: keeps the client loop uniform
    (`POST /acquire` → poll `GET /acquire/{requestId}` → act on state).

### REST endpoints (v1)
- `POST /lockable-resources/remote/v1/acquire`
  — enqueue an acquire request. Returns `{requestId}` on acceptance.
  **Does not return the acquisition outcome**; callers must read
  `GET /acquire/{requestId}` to observe the result.
  Accepts `skipIfLocked` as a hint; the outcome still materializes
  via `GET` as state `ACQUIRED` or `SKIPPED`.
  Rejected immediately (HTTP 4xx) if the resource/label is unknown
  (e.g. `UNKNOWN_RESOURCE`, `UNKNOWN_LABEL`); no `requestId` is issued.
- `GET  /lockable-resources/remote/v1/acquire/{requestId}`
  — authoritative acquisition state:
  `QUEUED` / `ACQUIRED` / `SKIPPED` / `FAILED` / `CANCELLED` / `EXPIRED`.
  Polled by the local side every few seconds.
- `POST /lockable-resources/remote/v1/acquire/{requestId}/cancel`
  — cancel a pending (not yet acquired) request.
- `GET  /lockable-resources/remote/v1/lease/{leaseId}`
  — inspect a currently held lease (diagnostics / UI).
- `POST /lockable-resources/remote/v1/lease/{leaseId}/heartbeat`
  — liveness signal from the local side while the body runs.
- `POST /lockable-resources/remote/v1/lease/{leaseId}/release`
  — release the lease when the body finishes (or is aborted).

### Client loop (reference)
```
requestId = POST /acquire {..., skipIfLocked?}
  # HTTP 4xx if resource/label is unknown on remote -> surface error, stop.
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

## Background & motivation
- `docs-j/remote-lock-background-j.md` — motivation and scope (JP)
- `docs-j/remote-lock-usecase-j.md` — realworld usecase (JP, small/medium scale)
- `docs-j/remote-lock-design-notes-j.md` — design rationale (JP)
- `docs-j/lockable-resources-architecture-j.md` — existing plugin architecture notes (JP)
- `docs-e/` — English translation (WIP)

## Phases (sub-Epics)
- [ ] Phase 1 — Remote lock via REST (safety-first, short-polling) — see sub-issue
- [ ] Phase 2 — Remote resource view (read-only mirror) — see sub-issue
- [ ] Phase 3 — Ops & hardening — see sub-issue

## Status
- [ ] Background & usecase documented
- [ ] High-level design reviewed
- [ ] Phase 1 scope agreed
- [ ] Phase 1 implementation started

## Open questions
- Default polling interval (proposed: 3s).
- Default heartbeat interval / stale threshold (proposed: 10s / 60s).
- Server-level vs resource-level stale policy.
- UI integration for remote entries (merged vs separate tab).
- Representation of remote owner/build identity in UI and logs.
- `skipIfLocked` surface: confirmed that `POST /acquire` returns only
  `requestId`; outcome is observed exclusively via
  `GET /acquire/{requestId}` (state `SKIPPED` when not acquired).
  Revisit only if a client pattern clearly needs a synchronous skip result.
- Unknown-resource/label rejection: confirmed that the remote API
  will never auto-create ephemeral resources. Error shape
  (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`) and HTTP status code to be
  finalized during Phase 1 implementation.
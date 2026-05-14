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
but intentionally scoped down to an **explicit, lightweight, safety-first** design.

> Note: we deliberately avoid the word *federation* here.
> The intent is **not** a transparent multi-controller federation,
> but a minimal **remote locking** extension with explicit routing.

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

## Non-goals (initial)
- No `serverId: 'any'` / multi-server routing.
- No long-polling or push-based notifications (short-polling only).
- No cross-controller state replication for lock decisions.
- No automatic lease-based release of locks.
- No freestyle project support in the first phase.
- No distributed consensus / HA orchestration.
- No transparent "federation" across multiple controllers.

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
- HTTP method policy:
  - **GET** for reads (status, lease inspection).
  - **POST** for state changes (acquire, cancel, heartbeat, release).

### REST endpoints (v1)
- `POST /lockable-resources/remote/v1/acquire`
  — enqueue an acquire request; returns `{requestId, state}`.
- `GET  /lockable-resources/remote/v1/acquire/{requestId}`
  — read acquisition state (`QUEUED` / `ACQUIRED` / `FAILED` / `CANCELLED`).
  Polled by the local side every few seconds.
- `POST /lockable-resources/remote/v1/acquire/{requestId}/cancel`
  — cancel a pending (not yet acquired) request.
- `GET  /lockable-resources/remote/v1/lease/{leaseId}`
  — inspect a currently held lease (diagnostics / UI).
- `POST /lockable-resources/remote/v1/lease/{leaseId}/heartbeat`
  — liveness signal from the local side while the body runs.
- `POST /lockable-resources/remote/v1/lease/{leaseId}/release`
  — release the lease when the body finishes (or is aborted).

## Background & motivation
(to be added)
- `docs/remote-lock-background.md` — motivation and scope
- `docs/remote-lock-usecase.md` — realworld usecase (small/medium scale)
- `docs/remote-lock-design-notes.md` — design rationale

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
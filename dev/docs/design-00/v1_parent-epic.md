Title: Epic: Remote lockable resources (explicit `serverId` routing)

Related: #321

## Summary
Add an opt-in mechanism that lets `lock(...)` target a resource managed by
another Jenkins controller via an explicit `serverId`, without changing
the semantics of existing single-controller `lock()`.

Inspired by the "lockable-master / lockable-slave" idea in
https://github.com/jenkinsci/lockable-resources-plugin/issues/321#issuecomment-1412529601
but intentionally scoped down to an **explicit, safety-first** design.

## Goals
- `lock(..., serverId: 'Remote1') { body }` delegates the lock decision
  (availability, queue, timeout, selection strategy) to the remote controller.
- The body still executes on the local controller.
- The remote controller is the **single source of truth** for its resources.
- Backward compatible: without `serverId`, behavior is unchanged.
- Authentication via Jenkins service user + API token, referenced by
  `credentialsId` on the local side.
- All controller-to-controller traffic is **slave → master only**
  (no inbound connections back from master to slave).
- Safety-first on communication failures (do **not** auto-release locks).

## Non-goals (initial)
- No `serverId: 'any'` / multi-server routing.
- No push-based master→slave notifications.
- No cross-controller state replication for lock decisions.
- No automatic lease-based release of locks.
- No freestyle project support in the first phase.
- No distributed consensus / HA orchestration.

## High-level design
- Local side is a thin REST wrapper around `lock()` semantics.
- Remote side implements:
  - `POST /federation/lock` (request)
  - `GET  /federation/lock/{requestId}?wait=...` (long-poll)
  - `POST /federation/lease/{leaseId}/heartbeat`
  - `POST /federation/lease/{leaseId}/release`
- All transport is initiated by the local (slave) side.
- Remote tracks `lastSeenAt` per lease; locks with no heartbeat become
  `STALE` in UI but are **not** auto-released.

## Phases (sub-Epics)
- [ ] Phase 1 — Remote lock via REST (safety-first) — see sub-issue
- [ ] Phase 2 — Remote resource view (read-only mirror) — see sub-issue
- [ ] Phase 3 — Ops & hardening — see sub-issue

## Open questions
- Server-level vs resource-level stale policy
- UI integration for remote entries (merged vs separate tab)
- Heartbeat interval defaults and tuning
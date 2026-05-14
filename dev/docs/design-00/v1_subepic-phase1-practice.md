> 🧪 **Practice / Draft.** Personal practice sketch on my sandbox repo.
> 本番設計ではなく、練習用の草案です。

---

Parent Epic: #1
Related (upstream, not auto-linked):
`https://github.com/jenkinsci/lockable-resources-plugin/issues/321`

## Goal
Implement `lock(..., serverId: 'Remote1') { body }` so that the lock
decision is fully delegated to the remote controller, with slave→master
only communication and safety-first failure handling.

## In scope
- New `serverId` parameter on `lock(...)` (local side).
- New `RemoteLockStepExecution` (or equivalent dispatch) that performs:
  - `POST /federation/lock`
  - `GET  /federation/lock/{requestId}?wait=...` (long-poll)
  - `POST /federation/lease/{leaseId}/heartbeat` while body runs
  - `POST /federation/lease/{leaseId}/release` on completion
- Remote side REST handlers implementing the above endpoints.
- Global config: `serverId -> baseUrl + credentialsId`
  (Username+Password credential; username + API token).
- Authentication:
  - Client: `credentialsId`
  - Server: standard Jenkins auth + permission check
- Safety-first on communication failure: do not auto-release; mark STALE.

## Out of scope (tracked in other sub-Epics)
- Read-only remote resource view → Phase 2
- Admin force-unlock UI, stale tuning → Phase 3
- Freestyle projects

## Acceptance
- `lock(..., serverId: 'Remote1') { ... }` behaves equivalently to
  `lock(...) { ... }` on Remote1, except that the body runs locally.
- Backward compatible: no `serverId` → unchanged behavior.
- Tests cover: acquire, queue+wait (long-poll), release, cancel,
  connection loss (verifies **no auto-release**).

## Open questions
- Long-poll wait duration defaults (proposed: 30s).
- Heartbeat interval / staleAfter defaults (proposed: 10s / 60s).
- How to represent remote owner/build identity.
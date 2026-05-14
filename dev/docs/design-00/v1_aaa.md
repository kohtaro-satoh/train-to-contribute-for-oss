Thanks a lot for the feedback!

Below are my current thoughts on Q1?Q4. The overall philosophy for Phase 1 is �gsafety first / fail-closed�h: never silently auto-release a lock on uncertainty.

### Q1 (A dies after A��B lock acquisition)
If A dies while holding a lease on B, B will keep the lease as **still held**, but it will eventually become **STALE** because heartbeats stop (as described in the draft: `lastSeenAt`/stale indicator).

In Phase 1 there is intentionally **no automatic release** on heartbeat loss. So yes: an operator would need to release it manually on B (LR UI / admin action), once they are sure the workload on A is really gone.

(We can later consider opt-in policies like �gauto-release after N minutes stale�h, but I�fd like to keep Phase 1 conservative.)

### Q2 (B dies / restarts)
If B is down, A cannot acquire or poll state; the local side should fail the `lock(...)` step (or keep waiting until timeout, depending on configured max wait).

If B restarts:
- The state on B depends on persistence. Today LR state is mostly in memory; after restart it may be lost. In that case the remote lease would disappear and A�fs polling would eventually see �gnot found�h / �gfailed�h and fail the step (or handle it as �glost lease�h).
- If/when we persist remote leases, B could recover them and A would continue polling and then proceed.

For Phase 1 I assume the �gin-memory�h behavior and treat restart as a failure case that requires operator attention (again: fail-closed).

### Q3 (UI: indicate �glocked from external API�h)
Good point. My idea is to show remote leases clearly in the LR UI, e.g.:
- a badge like `REMOTE` / `EXTERNAL` (and show `serverId`),
- include the �gowner�h details that A sends (controller id, job/build URL, etc.),
- and show last heartbeat time + stale marker.

Also, I agree your GitHub Action idea is interesting: a GitHub Action could call Jenkins (as the lock manager) via this API and use Jenkins as a central lock service.

### Q4 (API versioning / compatibility)
The proposal uses an explicit versioned base path (`/lockable-resources/remote/v1/...`).

Goal is:
- newer A should be able to talk to older B **as long as B still supports v1**,
- newer B should keep v1 for some time even after it implements v2 (deprecation window).

Implementation-wise I think A should first query something like:
- `GET (base)/meta` (or similar) to learn supported versions/capabilities,
or simply rely on the versioned path and handle 404/410 gracefully.

So ideally you do **not** need to update A and B in lock-step, at least within the same major API version.

Happy to clarify any of these and I can update the proposal text to make these behaviors more explicit.

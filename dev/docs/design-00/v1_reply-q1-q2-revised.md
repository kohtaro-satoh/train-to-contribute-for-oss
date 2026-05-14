### Q1 (A dies after A→B lock acquisition)
If A dies while holding a lease on B, B will keep the lease as **still held**, but it will eventually become **STALE** because heartbeats stop (as described in the draft: `lastSeenAt` / stale indicator).

In Phase 1 there is intentionally **no automatic release** on heartbeat loss. So yes: an operator would need to release it manually on B (LR UI / admin action), once they are sure the workload on A is really gone.

Later we can consider adding **configurable, opt-in cleanup policies**, e.g. "auto-release after N minutes stale", but I would like to keep Phase 1 conservative.

### Q2 (B dies / restarts)
If B is down, A cannot acquire or poll state; the local side should fail the `lock(...)` step (or keep waiting until timeout, depending on configured max wait).

If B restarts, my preference is to fail closed as well. Concretely, I would like **remote API exposure to be disabled by default after Jenkins start/restart**. The idea is:
- After every restart, an administrator verifies that the published resources are healthy,
- then manually re-enables the remote API (or the specific remote "serverId" configuration).

This reduces the risk of accidentally serving remote lock requests while the controller is still coming up or in a partially broken state.
Thanks a lot for the feedback!

Below are my current thoughts on Q1–Q4. The overall philosophy for Phase 1 is **safety first / fail-closed**: never silently auto-release a lock on uncertainty.

### Q1 (A dies after A→B lock acquisition)
If A dies while holding a lease on B, B will keep the lease as **still held**, but it will eventually become **STALE** because heartbeats stop (as described in the draft: `lastSeenAt` / stale indicator).

In Phase 1 there is intentionally **no automatic release** on heartbeat loss. So yes: an operator would need to release it manually on B (LR UI / admin action), once they are sure the workload on A is really gone.

Later we can consider adding **configurable, opt-in cleanup policies**, e.g. "auto-release after N minutes stale", but I would like to keep Phase 1 conservative.

### Q2 (B dies / restarts)
If B is down, A cannot acquire or poll state; the local side should fail the `lock(...)` step (or keep waiting until timeout, depending on configured max wait).

If B restarts, my preference is to fail closed as well. Concretely, I would like **remote API exposure to be disabled by default after Jenkins start/restart**:
- After every restart, an administrator verifies that the published resources are healthy,
- then manually enables "Remote API exposure" (or the specific remote configuration).

In other words: **"Remote API exposure" is an explicit on/off mode, and it defaults to OFF after restart.**

### Q3 (UI: indicate "locked from external API")
My current view is that the remote-lock API is just REST, so the remote side should not need to care whether the client is another Jenkins controller, GitHub Actions, or some other CI/CD system. The only thing B can reliably know is "this lease was created via the remote API" and whatever identity/metadata the client provides (access is still controlled by Jenkins authn/authz).

For operators, I think we should extend the existing LR UI (`<JenkinsURL>/lockable-resources/`) to make this visible, while reusing current patterns as much as possible. For example:
- Add a small `REMOTE` / `API` badge in the **Action** column (and show `serverId` / client id when available),
- In **Status**, show the "owner" details provided by the client (e.g. remote controller id, job/build URL, etc.),
- Also show last heartbeat time and a `STALE` indicator when heartbeats stop.

PS: I agree your GitHub Actions idea is interesting — a stable REST API could enable a "lock service" use case beyond Jenkins.

### Q4 (API versioning / compatibility)
The API is versioned in the URL (`/lockable-resources/remote/v1/...`). The intended compatibility model is simple:
- Backward compatibility is the default: if we introduce `/v2` (or `/v3`), we should keep `/v1` working for as long as reasonably possible.
- A newer server may support multiple versions in parallel (e.g. both `/v1` and `/v2`).
- If at some point a major internal redesign or security concern makes an old version unacceptable, we may drop that version. In that case the server will simply respond with `404 Not Found` (or `410 Gone`) for the removed version.

From the client's perspective:
- If A calls an unsupported version on B, it will get 404/410 and fail closed, and operators can then decide to upgrade the older side (plugin/Jenkins) to restore compatibility.
- So A and B do not need strict lock-step upgrades as long as they share at least one supported major API version.

Happy to clarify any of these and I can update the proposal text to make these behaviors more explicit.
Thanks for the questions! Q1 and Q2 inevitably mix system behavior and operational procedures (admin actions), because for a safety-first design they cannot be fully separated. I’ll try to describe both clearly.

### Q1
> What happens when A locks on B, then A dies? What happens with the resource on B — should I reset it manually on B?

Yes — operationally a manual reset/release is required.

When A’s job dies, heartbeats stop. Then Jenkins B can transition that remote lease to `STALE`. After confirming that (a) the workload on A is really gone (not restarted / or already finished) and (b) the physical resource is healthy/free, an administrator on B can manually set it back to `FREE` (e.g. via the LR page / admin action).

### Q2
> What happens when A locks on B, then B dies / restarts? Do we still have the same state?

If B goes down after acquisition, A will keep trying to call lease-related APIs on B (heartbeat/release/etc.) using the `leaseId`, but those requests will just fail / be no-ops while B is unavailable. A should not automatically abort the job just because B is unreachable (fail-closed / do not auto-release).

On the B side, after Jenkins restart, my preference is:
- Remote locking exposure is an explicit on/off feature, and it defaults to **OFF** after Jenkins start/restart.
- An administrator verifies that all resources to be exposed remotely are physically `FREE` and healthy, and then manually turns ON "Remote API exposure".

This switch only controls whether B accepts remote API calls; it does **not** change the behavior of local `lock()` on B. Also, the initial LR state on Jenkins start is `FREE` (same as today), regardless of remote exposure.

One remaining concern is that, with this approach, a local job on B could acquire a resource that is still in use by A right after B restarts. For Phase 1 I’m considering keeping this as an open issue.
A possible solution is to persist remote lease state so that B can restore it after restart and keep the resource locked/`STALE` until an operator explicitly releases it — but this has trade-offs (extra disk I/O and potentially more manual operations), so I don’t have a final decision yet.

### Q3
> How do you want to indicate that the resource is locked from an external API client?

I plan to extend the existing LR UI (`<JenkinsURL>/lockable-resources/`) to make this visible, e.g. using the **Status** and/or **Action** columns.
For example, Status could show not only the job/build name but also the client URL or client ID (the client would need to provide such an identifier, e.g. `Jenkins-tokyo1`, `GitHub`, etc.).

PS: I agree this is an ambitious and interesting direction — if we have a stable REST API, Jenkins could potentially act as a small lock service for other systems.

### Q4
> How do we ensure correct API versioning? Do we need lock-step upgrades?

Even if we introduce v2, we should keep v1 working as long as v1 semantics remain valid and safe (backward compatibility by default).
However, if a future v3 addresses a serious security issue that makes v1 unacceptable, we may drop v1 at that time.

The compatibility model is intentionally simple: when a version is not supported anymore, the server would return HTTP `404 Not Found` (or `410 Gone`) for that versioned path.
Thanks for the questions! For Q1 and Q2, system behavior and operational procedures (admin actions) are tightly coupled in a safety-first design, so the explanation may look a bit long.

### Q1
> What happens when A locks on B, then A is dead? What happens with the resource on B — should I reset it manually on B?

Yes — operationally a manual reset/release is required.

When A’s job dies, heartbeats stop. Then Jenkins B can transition the lease to `STALE`.
After confirming that (a) the workload on A is really gone (not restarted / or already finished) and (b) the physical resource is healthy/free, an administrator on B can manually set it back to `FREE` (e.g. via the LR page / admin action).

### Q2
> What happens when A locks on B, then B is dead / restarted? Do we still have the same state?

If B goes down after acquisition, A will continue to call lease-related endpoints on B (heartbeat/release/etc.) using the `leaseId`, but those requests will fail (connection errors / timeouts) while B is unavailable. In any case, A should not automatically abort the running job just because B is unreachable (fail-closed / do not auto-release).

On the B side, after restarting Jenkins B and *before* exposing resources for remote locking again, an administrator must verify that all resources to be exposed are physically `FREE` and healthy.
This is the same fundamental operational requirement as before introducing remote locking — however, with remote locking, checking “is it really free?” may require coordinating with the remote client side (e.g. Jenkins A) as well, and this extra step is unavoidable operationally.

### Q3
> How do you want to indicate that the resource is locked from an external API client?

I plan to extend the existing LR UI (`<JenkinsURL>/lockable-resources/`) to make this visible, e.g. by enhancing the **Status** and/or **Action** columns.
For example, Status could show not only the job/build name but also the client URL or client ID (the client would need to provide such an identifier, e.g. `Jenkins-tokyo1`, `GitHub`, etc.).

PS: I agree this is an ambitious and interesting direction.

### Q4
> How do we ensure correct API versioning? Do we need lock-step upgrades?

Even if we introduce v2, we should keep v1 working as long as v1 semantics remain valid and safe (backward compatibility by default).
However, if a future v3 addresses a serious security issue that makes v1 unacceptable, we may drop v1 at that time.

The compatibility model is intentionally simple: when a version is not supported anymore, the server would return HTTP `404 Not Found` (or `410 Gone`) for that versioned path.
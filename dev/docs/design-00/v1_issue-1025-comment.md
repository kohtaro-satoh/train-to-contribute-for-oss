@mPokornyETM Thanks again for the additional points and for inviting other maintainers to weigh in. Before more reviewers join, I'd like to consolidate where this design has moved during our discussion, because some parts have changed materially. Concrete answers to your three follow-up points are at the bottom.

## 1. Design pivot: pipelines should not need to know about "remote"

Your earlier "symLink" idea pushed me to reconsider the explicit `serverId` parameter on `lock(...)`. After thinking it through, I agree that **pipeline authors should not have to encode `serverId` in their `Jenkinsfile`** just to use a resource that happens to live on another controller. That's an operational/topology concern, not a pipeline concern.

So I want to update the Phase 1 design accordingly, while keeping the safety properties we already discussed (A1–A4) intact.

### What changes
- The DSL becomes **transparent by default**: pipelines keep writing `lock('X') { ... }`.
- Where that `X` is resolved is decided by **controller-level configuration**, not by the pipeline.

### What does NOT change (intentionally)
- Communication model: still **local → remote only**, per-relation, no inbound channel from remote back to local.
- No master/slave role fixed at the controller level: any controller can be a "local" for some relations and a "remote" for other relations at the same time. (This is different from a centralized lockable-master design.)
- Safety semantics from A1–A4: heartbeat → `STALE` only, no auto-release, fail-closed on communication errors, versioned path with 404/410 for retired versions.
- Remote resources must be **pre-declared** on the remote side; no auto-creation over the remote API.

## 2. New configuration: `forcedServerId` (global)

To make the DSL transparent without re-introducing implicit magic, Phase 1 will add a single global setting in the Lockable Resources section of *Manage Jenkins → System*:

- `forcedServerId` (optional, single value)

### Resolution rules

```
if forcedServerId is set:
    target = (forcedServerId, name)        # all locks are delegated to that remote
                                           # an explicit serverId argument is silently ignored
                                           # (an INFO line is written to the build log)
else:
    if lock(..., serverId: 'X') is given:
        target = (X, name)                 # explicit override (also useful for debugging)
    else:
        target = (LOCAL, name)             # original behavior, fully backward compatible
```

This gives us two coexisting operating modes from a single feature:

- **Peer mode** (`forcedServerId` not set): each controller is independent; pipelines can opt into a specific remote with an explicit `serverId` when they want to. This matches the "mutual sharing via independent one-way relations" model already described in the issue body.
- **Delegated mode** (`forcedServerId` set): the controller behaves like a "lockable-slave" that delegates every `lock()` to a single remote "lockable-master". This is conceptually the configuration you described in [#321 (comment)](https://github.com/jenkinsci/lockable-resources-plugin/issues/321#issuecomment-1412529601), achieved with one config field instead of a new role.

### Why "forced" rather than "default"
In delegated mode, **local resource definitions on this controller are not used at all**:
- Resolution always goes to the remote.
- The LR page on this controller shows the remote's published resources only.
- A `lock('X')` for an unknown name on the remote fails immediately with `UNKNOWN_RESOURCE` (no silent fallback to local).

This eliminates name-collision questions entirely (we don't need to decide which `X` wins) and, more importantly, removes a class of "I thought I locked the remote one but I actually locked a local one" accidents. It is a deliberately strict mode.

### Why `lock(..., serverId: ...)` is preserved
Even after transparency, I want to keep the explicit `serverId` parameter on `lock(...)` in the DSL:
- In peer mode it is the way to address a specific remote.
- It is very useful for debugging and operational overrides ("force this one call to go to server C").
- In delegated mode it is silently ignored (INFO-logged), so pipelines remain portable across controllers.

Documentation will describe it as an **explicit override**, not as a "legacy" parameter.

## 3. Additional API: list published resources on the remote

To make the A-side LR page useful in delegated mode (and informative in peer mode), Phase 1 will add one more read-only endpoint:

- `GET /lockable-resources/remote/v1/resources` — returns the list of resources the remote exposes (name, labels, description). State is intentionally **not** included in this endpoint to keep it cheap and cacheable; lease/state lookups continue to go through the existing per-lease endpoints.

The A side will short-cache this list (a few tens of seconds) and use it to render a remote view on its LR page.

## 4. UI updates on A side

- **Peer mode**: the LR page shows local resources as today, plus any active remote leases this controller currently holds (with their `serverId`).
- **Delegated mode**: the LR page shows the remote's published resources (from the new `GET /resources`) and the current remote leases held by this controller. Local resource definitions are hidden or shown as "not used in delegated mode".
- In both modes, the displayed remote state is explicitly labeled as the **A-side cached view**, not the authoritative state on B.

This way, what the user sees on the LR page and what `lock('X')` will actually try to acquire stay consistent.

## 5. Phase 1 scope (updated and finalized)

Included:
- REST API on remote side under `/lockable-resources/remote/v1/`:
  - `POST /acquire`, `GET /acquire/{requestId}`, `POST /acquire/{requestId}/cancel`
  - `GET /lease/{leaseId}`, `POST /lease/{leaseId}/heartbeat`, `POST /lease/{leaseId}/release`
  - `GET /resources` (new)
- DSL: `lock(..., serverId: 'X')` as explicit override; transparent `lock('X')` resolution under `forcedServerId`.
- Global config: `forcedServerId`, plus the existing remote connection settings (URL, `credentialsId`).
- A-side LR page integration as described above.
- B-side LR page: show client identifier (e.g. `clientId` / URL) in the status column for active remote leases (this is the visualization piece from A3).
- Safety/versioning per A1–A4.

Out of scope for Phase 1 (deferred or rejected):
- Multiple remote servers with failover / round-robin.
- State mirroring / replication between controllers.
- Fixed master/slave roles at the controller level.
- Folder-level or job-level overrides of `forcedServerId`.
- `serverId: 'any'` style automatic selection.
- Cross-server label resolution.
- Global "pause new acquires" maintenance switch (good idea — better as Phase 2).

## 6. Direct answers to your three follow-up points

> I will have visual indication, that the resource on A is "linked" to resource on B.

Agreed and included in Phase 1 (see the UI section above). A side will display remote leases it currently holds and, in delegated mode, the remote's published resources. The display is clearly marked as the A-side cached view.

> Maybe we shall configure resource A as "symLink" from B, so I do not need to care about that in my pipeline.

I think `forcedServerId` (delegated mode) achieves the same end result you're after — pipelines stay as `lock('X')` and don't need to know about remote-ness — without introducing a per-resource symlink construct. A symlink-style mechanism (per-resource alias, mixed local + remote on the same controller) raises non-trivial questions (collision handling, failure semantics when the target is unreachable, configuration consistency) and I'd prefer to keep that out of Phase 1.

> It will be great to have some over all Pause mode, that we can provide maintenance on B without disturbance on A.

Agreed in spirit. A reasonable shape would be a B-side admin switch *"accept new acquires: ON / OFF"*: when OFF, new `acquire` requests are rejected (e.g. HTTP 503) so the A side can back off and retry, while existing leases (`heartbeat` / `release`) keep working so in-flight jobs are not disturbed. I'd like to put this in **Phase 2** rather than Phase 1, to keep Phase 1 focused.

## 7. About implementation pace

There is no fixed deadline on my side. Given the scope above, I'm planning to implement Phase 1 in three internal milestones (core REST + explicit `serverId`, then `forcedServerId` resolution, then the `GET /resources` endpoint and A-side LR page integration), so each step can be reviewed independently rather than as one large PR.

I will update the issue body to reflect this finalized Phase 1 shape after this comment, so newcomers don't have to reconstruct the design from the discussion thread. Feedback on the updated direction — especially on the `forcedServerId` semantics and the new `GET /resources` endpoint — is very welcome.
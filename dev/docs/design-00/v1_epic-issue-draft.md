Title: Epic: Federated lockable resources across Jenkins controllers

Related: #321

## Goal
Enable multiple Jenkins controllers to share a subset of lockable resources,
so that a resource locked on controller A is respected by controller B.

Primary use case: sharing a limited pool of physical debugging devices across
multiple controllers.

## Key requirements
- **Backward compatible**: existing `lock()` usage must behave exactly the same when federation is not configured.
- **Opt-in**: federation is only used when explicitly requested/configured.
- **Operationally safe**: handle timeouts and controller/network failures without leaving resources locked forever.

## Non-goals (for initial implementation)
- No distributed consensus / quorum
- Not targeting large clusters (initial target: a few controllers)
- No attempt to solve general Jenkins controller clustering

## High-level design (initial sketch)
- Each resource can have an optional "home" controller.
- When a controller needs to lock a federated resource, it consults the home controller.
- Initial PoC will add a `serverId` (or similar) plumbing + a dispatch point, with no remote calls yet.

## Phases
### Phase 0: Design agreement
- [ ] Confirm API shape (`serverId` name, semantics, defaults)
- [ ] Confirm configuration mechanism (JCasC / UI / both)
- [ ] Confirm minimal failure/timeout semantics (lease vs. heartbeat)

### Phase 1: Minimal PoC PR (plumbing only)
- [ ] Add `serverId` parameter plumbing to `lock()`
- [ ] Add a stub dispatch point for federation path
- [ ] No remote communication yet
- [ ] Add tests for backward compatibility

### Phase 2: Remote lock protocol (MVP)
- [ ] Implement remote lock/unlock against the home controller
- [ ] Define lease/timeout behavior
- [ ] Add basic authentication strategy (TBD)

### Phase 3: Hardening + UX
- [ ] Improve error messages and diagnostics
- [ ] Add docs + examples

## Open questions
- [ ] How to authenticate controller-to-controller calls?
- [ ] How to represent / configure "home" controller per resource?
- [ ] How to handle controller crash while holding a lock (lease expiry vs. explicit recovery)?
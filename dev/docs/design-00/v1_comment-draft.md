Hi @mPokornyETM and @jimklimov,

I've been studying this issue along with the plugin codebase, and I'd like to 
revive the discussion with a concrete use case and a design sketch. I'm willing 
to contribute the implementation if there's interest.

## My use case

In my $work environment, I maintain Jenkins CI/CD infrastructure where a 
limited number of new-generation debugging devices (physical hardware) need 
to be shared across multiple Jenkins controllers. Statically assigning these 
scarce devices to individual controllers is operationally painful — it's 
essentially capacity-planning by guesswork, and leads to significant 
under-utilization.

Eventually we plan to introduce a dedicated REST+RDB-based resource 
management system, but that's a large project. A lightweight federation 
feature in Lockable Resources would both bridge the gap for us and, I 
believe, help many small-to-medium Jenkins shops in similar situations.

## Relationship to @mPokornyETM's 2023 proposal

I've carefully read the master/slave design in 
https://github.com/jenkinsci/lockable-resources-plugin/issues/321#issuecomment-1412529601
and I think it's a great starting point. What I'd like to propose is a 
small generalization of that model that I think covers both use cases with 
the same implementation:

**Per-resource ownership (P2P) instead of per-instance role:**
- Each resource has exactly one authoritative Jenkins instance (its owner)
- Any instance can request a lock on any resource, routed to the owner
- The "single master holds everything" configuration in the 2023 proposal 
  becomes a natural special case where all resources are owned by one instance
- My use case (each site owns its local hardware but shares some) becomes 
  another configuration of the same mechanism

This keeps things simple:
- No distributed consensus needed
- No split-brain possible (each resource has a single source of truth)
- Same HTTP-based protocol as the 2023 proposal

## Addressing @jimklimov's concerns

From the 2022 comment, the key concerns were in-memory state race conditions, 
timeouts, outages, and crashes. My intended approach:

- **Leases with TTL + heartbeat**: remote locks expire if the requester dies 
  or the network partitions; owner reclaims automatically
- **Owner is single source of truth**: no need to sync in-memory state bidirectionally
- **Graceful degradation**: if a peer is unreachable, local locks still work; 
  remote locks to that peer fail fast with clear Pipeline error messages
- **Explicit opt-in**: fully backward-compatible; `serverId` parameter 
  defaults to null = current behavior unchanged

## Pipeline API sketch (100% backward compatible)

```groovy
// Current behavior — unchanged
lock('my-resource') { ... }

// New: lock a specific remote resource
lock(resource: 'shared-device-1', serverId: 'jenkins-lab-b') { ... }

// New: lock any matching resource across federated peers
lock(label: 'gpu', serverId: 'any') { ... }
```

## Scope limitations (intentional)

- Target: small-to-medium setups (≈ 2–5 federated controllers)
- Larger deployments should use dedicated resource management systems
- Static peer configuration (no dynamic discovery) to keep complexity low
- Per-resource export ACL for security

## Questions before I invest further

1. Is this scope acceptable for the main plugin, or would you prefer it live 
   as a separate plugin extending via SPI?
2. Are there design constraints I should know about — e.g., interaction with 
   recent locking refactors (#586, #607, #703)?
3. Would you prefer to see a full design doc, or a minimal PoC PR first?

Happy to iterate on scope and approach. Thanks for maintaining this plugin!
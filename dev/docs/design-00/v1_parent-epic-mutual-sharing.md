### Mutual sharing via two independent one-way relations
- The `local → remote only` rule is about **a single client/server
  relation**, not about the roles of the two controllers overall.
- Two controllers A and B can freely establish **two independent
  one-way relations** at the same time:
  - For resources owned by B: A is local, B is remote.
    (A opens outbound HTTP to B with A's `credentialsId`.)
  - For resources owned by A: B is local, A is remote.
    (B opens outbound HTTP to A with B's `credentialsId`.)
- Each relation still obeys the same rules:
  - single source of truth is the remote side of that relation,
  - traffic is initiated only by the local side of that relation,
  - failures are handled fail-closed on the local side of that relation.
- This yields **mutual sharing without any new concept**: no bidirectional
  channel, no "peer" role, no replication. Just two ordinary one-way
  remote-lock relations coexisting.

Example:
```
A's pipeline:  lock(resource: 'board-a1', serverId: 'B') { ... }
   # A is local, B is remote. A → B HTTP only.

B's pipeline:  lock(resource: 'license-x',  serverId: 'A') { ... }
   # B is local, A is remote. B → A HTTP only.
```
Each controller acts as *local* for its own pipelines and as *remote*
for resources it owns. The two roles are per-relation, not per-controller.
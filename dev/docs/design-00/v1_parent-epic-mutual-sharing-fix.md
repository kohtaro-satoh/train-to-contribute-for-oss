- Any number of controllers can freely establish **multiple independent
  one-way relations** at the same time. For example, between A and B:
  - For resources owned by B: A is local, B is remote.
    (A opens outbound HTTP to B with A's `credentialsId`.)
  - For resources owned by A: B is local, A is remote.
    (B opens outbound HTTP to A with B's `credentialsId`.)

The same pattern extends naturally to A↔C, B↔C, and so on.
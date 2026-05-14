Title: sub-Epic: Phase 3 - Ops & hardening

Parent Epic: <link to parent Epic>
Related: #321

## Goal
Improve operational usability on top of Phase 1, while keeping
safety-first behavior.

## In scope
- Admin-facing UI on remote side for STALE leases:
  - Display owner and last seen info.
  - Force-unlock with explicit confirmation.
- Configurable stale policy (server-level, later resource-level).
- Better diagnostics and logs (without leaking tokens).

## Out of scope
- Auto-release based on lease expiry.
- Cross-controller HA.

## Acceptance
- Operators can diagnose and safely recover from STALE leases.
- Stale policy is configurable per server (resource-level optional).
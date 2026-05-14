Title: sub-Epic: Phase 2 - Remote resource view (read-only mirror)

Parent Epic: <link to parent Epic>
Related: #321

## Goal
Display resources managed by remote controllers alongside local resources
in the Lockable Resources dashboard, as a **best-effort, read-only** view.

## In scope
- `GET /federation/resources` on remote side (snapshot of resources).
- Periodic pull from local side (e.g., 30–60s).
- UI: show remote entries with a clear `source` column and a "remote /
  best-effort" notice.
- No lock operations on remote rows from local UI.

## Out of scope
- Using mirrored data for lock decisions (explicitly forbidden).
- Persistent storage of mirrored data.
- Admin operations on remote resources from local UI.

## Acceptance
- Local UI shows local + remote resources in a single dashboard.
- Remote rows are clearly labeled and never influence lock logic.
- Stale rows are visibly marked when updates stop.

## Open questions
- Polling interval default.
- Merged table vs separate tab in UI.
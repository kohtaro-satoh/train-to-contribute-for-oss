## Open questions
- Default polling interval (proposed: 3s).
- Default heartbeat interval / stale threshold (proposed: 10s / 60s).
- Server-level vs resource-level stale policy.
- UI integration for remote entries (merged vs separate tab).
- Representation of remote owner/build identity in UI and logs.
- `skipIfLocked` surface: confirmed that `POST /acquire` returns only
  `requestId`; outcome is observed exclusively via
  `GET /acquire/{requestId}` (state `SKIPPED` when not acquired).
  Revisit only if a client pattern clearly needs a synchronous skip result.
- Unknown-resource/label rejection: confirmed that the remote API
  will never auto-create ephemeral resources. Error shape
  (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`) and HTTP status code to be
  finalized during Phase 1 implementation.
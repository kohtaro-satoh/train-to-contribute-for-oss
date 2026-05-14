### REST endpoints (v1)
- `POST /lockable-resources/remote/v1/acquire`
  — enqueue an acquire request. Returns `{requestId}` on acceptance.
  **Does not return the acquisition outcome**; callers must read
  `GET /acquire/{requestId}` to observe the result.
  Accepts `skipIfLocked` as a hint; the outcome still materializes
  via `GET` as state `ACQUIRED` or `SKIPPED`.
- `GET  /lockable-resources/remote/v1/acquire/{requestId}`
  — authoritative acquisition state:
  `QUEUED` / `ACQUIRED` / `SKIPPED` / `FAILED` / `CANCELLED` / `EXPIRED`.
  Polled by the local side every few seconds.
- `POST /lockable-resources/remote/v1/acquire/{requestId}/cancel`
  — cancel a pending (not yet acquired) request.
- `GET  /lockable-resources/remote/v1/lease/{leaseId}`
  — inspect a currently held lease (diagnostics / UI).
- `POST /lockable-resources/remote/v1/lease/{leaseId}/heartbeat`
  — liveness signal from the local side while the body runs.
- `POST /lockable-resources/remote/v1/lease/{leaseId}/release`
  — release the lease when the body finishes (or is aborted).
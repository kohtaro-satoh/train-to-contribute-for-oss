Where `(base)` = `/lockable-resources/remote/v1`.

Acquire lifecycle (request side):
- `POST (base)/acquire` — enqueue an acquire request. ...
- `GET  (base)/acquire/{requestId}` — authoritative acquisition state. ...
- `POST (base)/acquire/{requestId}/cancel` — cancel a pending request.

Lease lifecycle (after acquisition):
- `GET  (base)/lease/{leaseId}` — inspect a currently held lease.
- `POST (base)/lease/{leaseId}/heartbeat` — liveness signal from the local side.
- `POST (base)/lease/{leaseId}/release` — release the lease when done.
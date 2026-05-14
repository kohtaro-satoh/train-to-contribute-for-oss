- HTTP method policy:
  - **POST** acknowledges requests and state transitions only
    (returns "accepted" / error; never returns acquisition outcome).
  - **GET** is the single source of truth for acquisition state and
    lease inspection.
  - Rationale: keeps the client loop uniform
    (`POST /acquire` → poll `GET /acquire/{requestId}` → act on state).
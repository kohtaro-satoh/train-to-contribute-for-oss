- `skipIfLocked` behavior surface: confirmed design returns only
  `requestId` from `POST /acquire`; outcome is observed exclusively
  via `GET /acquire/{requestId}` (state `SKIPPED` when not acquired).
  Revisit if any client pattern needs synchronous skip result.
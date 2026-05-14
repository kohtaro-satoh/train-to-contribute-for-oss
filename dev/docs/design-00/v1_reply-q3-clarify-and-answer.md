### Q3 (UI: indicate "locked from external API")
Just to confirm I understand the question: do you mean how the LR UI on B should indicate that a resource is locked by a *remote API client* (e.g. another Jenkins controller A), rather than by a local job/build on B?

If yes, I agree this is important for operators. My preference is to reuse the existing LR UI patterns as much as possible, but make the "remote" nature explicit, for example:
- show a badge like `REMOTE` / `EXTERNAL` and the `serverId` (or remote controller identity),
- show who/what requested it (e.g. remote controller id + the originating job/build URL from A),
- show last heartbeat time + a `STALE` indicator when heartbeats stop.

For Phase 1 I would keep it minimal (visibility + diagnostics). More advanced integrations (e.g. GitHub Actions as an external client) could be explored later.
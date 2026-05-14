### Q4 (API versioning / compatibility)
The API is versioned in the URL (`/lockable-resources/remote/v1/...`). The intended compatibility model is simple:

- Backward compatibility is the default: if we introduce `/v2` (or `/v3`), we should keep `/v1` working for as long as reasonably possible.
- A newer server may support multiple versions in parallel (e.g. both `/v1` and `/v2`).
- If at some point a major internal redesign or security concern makes an old version unacceptable, we may drop that version. In that case the server will simply respond with `404 Not Found` (or `410 Gone`) for the removed version.

From the client's perspective this means:
- If A calls an unsupported version on B, it will get 404/410 and fail closed, and operators can then decide to upgrade the older side (plugin/Jenkins) to restore compatibility.
- So A and B do not need strict lock-step upgrades as long as they share at least one supported major API version.
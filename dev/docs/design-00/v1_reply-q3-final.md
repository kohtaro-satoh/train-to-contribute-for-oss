### Q3 (UI: indicate "locked from external API")
My current view is that the remote-lock API is just REST, so the remote side should not need to care whether the client is another Jenkins controller, GitHub Actions, or some other CI/CD system. The only thing B can reliably know is "this lease was created via the remote API" and whatever identity/metadata the client provides.

For operators, I think we should extend the existing LR UI (`<JenkinsURL>/lockable-resources/`) to make this visible, while reusing current patterns as much as possible. For example:
- Add a small `REMOTE` / `API` badge in the **Action** column (and show `serverId` / client id when available),
- In **Status**, show the "owner" details provided by the client (e.g. remote controller id, job/build URL, etc.),
- Also show last heartbeat time and a `STALE` indicator when heartbeats stop.

PS: I agree your GitHub Actions idea is interesting — a stable REST API could enable a "lock service" use case beyond Jenkins.
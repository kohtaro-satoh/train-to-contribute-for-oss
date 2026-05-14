Good catch — `Map`/`[:]` keyed by `serverId` makes more sense given that `serverId` is unique and is the lookup key everywhere (resolution, UI, `forcedServerId`). It also makes the JCasC representation cleaner.

I'll update the issue body accordingly when I refresh it with the finalized Phase 1 shape, and use a `Map<String, RemoteConfig>` (or its equivalent in the Jenkins config UI: a repeatable list internally with a uniqueness constraint on the key, exposed as a map at the API/lookup layer).

Thanks for the LGTM — I'll start the first draft.
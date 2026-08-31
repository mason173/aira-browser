# Huawei Space Remote State Is Account-Bound

Accepted: Huawei Space Sync must bind remote `sync_meta` to the owning Huawei account using a stable non-secret identifier or one-way hash. If the current Aira Huawei account does not match that binding, Aira blocks merge, upload, and use-remote flows rather than silently combining one account's local bookmarks with another account's Huawei Space remote state.

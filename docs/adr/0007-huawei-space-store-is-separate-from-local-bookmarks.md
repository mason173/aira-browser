# Huawei Space Store Is Separate From Local Bookmarks

Accepted: Huawei Space Sync will use a cloud-synchronized ArkData RDB store/table set that is physically separate from Aira's local bookmark database. The local bookmark database remains the local working store, while the separate Huawei Space store is the provider adapter's remote-state mapping layer; this prevents platform sync constraints, availability, quota, and migration concerns from leaking into the local bookmark model.

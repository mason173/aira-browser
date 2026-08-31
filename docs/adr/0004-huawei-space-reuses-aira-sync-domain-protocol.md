# Huawei Space Sync Reuses The Aira Sync Domain Protocol

Accepted: Huawei Space Sync will adapt Aira's existing bookmark sync snapshots, operations, tombstones, and conflict semantics onto ArkData RDB cloud-synchronized rows instead of creating a separate bookmark domain model. This keeps primary-source switching and merge behavior consistent across Aira Cloud Sync, WebDAV, and Huawei Space Sync while letting the Huawei Space adapter own only the platform storage representation.

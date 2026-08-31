# Huawei Space Does Not Use App-Layer Encryption

Accepted: Huawei Space Sync will not add Aira application-layer encryption before writing bookmark sync rows to ArkData RDB. The provider should rely on the user's Huawei account and platform cloud storage boundary, while keeping the synchronized data scope limited to bookmark fields and sync metadata; tokens, cookies, page content, auth material, and favicon binaries must not be stored in the Huawei Space tables.

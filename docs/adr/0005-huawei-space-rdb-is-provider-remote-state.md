# Huawei Space RDB Is Provider Remote State

Accepted: when `huawei_space` is selected as the primary sync source, its cloud-synchronized ArkData RDB tables are the provider's remote authoritative state, not a UI-owned cache or alternate local bookmark model. Aira's local bookmark database remains the local working state, and all merge, tombstone, conflict, and switching behavior must pass through the shared Aira sync protocol before data is mapped into Huawei Space rows.

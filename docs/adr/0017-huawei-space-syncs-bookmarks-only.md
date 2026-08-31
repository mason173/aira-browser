# Huawei Space Syncs Bookmarks Only

Superseded by ADR 0026.

Accepted: Huawei Space Sync is limited to bookmark data and the sync metadata needed to preserve bookmark semantics. It must not synchronize reading list, browsing history, open tabs, general settings, personalization settings, or other non-bookmark data; Personalization Sync remains a Pro-only capability and must not become free by being routed through `huawei_space`.

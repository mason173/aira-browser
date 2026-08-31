# Bookmark Sync And Personalization Sync Are Separate Domains

Partially superseded by ADR 0026. Bookmark sync and Personalization Sync remain separate Sync Domains, but Personalization Sync is no longer Pro-only and is no longer restricted to Aira Cloud.

Accepted: Aira's Primary Sync Source applies only to bookmark sync, while Personalization Sync remains a separate Pro-only sync domain. Pro users may sync bookmarks through Huawei Space Sync or WebDAV while still using Aira Cloud for personalization/settings sync; free users must not receive personalization sync by routing it through `huawei_space`.

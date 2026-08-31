# Unavailable Huawei Space Sync Does Not Auto-Failover

Generalized to every Primary Sync Source by ADR 0028.

Accepted: if `huawei_space` is the selected primary sync source but Huawei account login, system Cloud Space sync, or platform cloud synchronization is unavailable, Aira keeps `huawei_space` selected and marks it as unavailable instead of automatically falling back to WebDAV, Aira Cloud Sync, or silent local-only sync. This preserves the user's explicit source choice and keeps merge/switching semantics honest: local bookmarks remain usable, pending changes wait for recovery, and switching to another provider requires the normal primary-source switching flow.

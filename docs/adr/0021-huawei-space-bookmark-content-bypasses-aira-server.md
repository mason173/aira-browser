# Huawei Space Bookmark Content Bypasses Aira Server

Accepted: Huawei Space Sync bookmark content must not pass through Aira's self-hosted server. Aira server systems may provide non-content control-plane support such as membership state, remote config, feature flags, readiness gating, or diagnostics, but they must not receive, proxy, cache, back up, log, or inspect `huawei_space` bookmark URLs, titles, folders, ordering rows, tombstones, or snapshots.

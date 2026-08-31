# Huawei Space Quota Failures Do Not Auto-Repair

Accepted: if Huawei Space Sync cannot write or synchronize because of Cloud Space quota, ArkData limits, or platform capacity errors, Aira marks the selected primary source as failed or unavailable while keeping local bookmarks usable and pending changes queued. Aira must not automatically delete tombstones, compact sync history, switch providers, or report success, because those "repairs" would hide data loss or change the user's selected sync source without consent.

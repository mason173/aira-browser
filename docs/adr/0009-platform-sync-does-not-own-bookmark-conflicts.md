# Platform Sync Does Not Own Bookmark Conflicts

Accepted: HarmonyOS/ArkData cloud synchronization is the transport/storage mechanism for Huawei Space provider rows, not the business conflict-resolution engine for Aira bookmarks. Bookmark outcomes such as move, rename, delete, order, and tombstone handling must remain owned by Aira's shared sync protocol so `huawei_space`, `webdav`, and `aira_cloud` keep consistent merge behavior.

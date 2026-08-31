# Huawei Space Empty Tables Do Not Prove Empty Remote

Accepted: Huawei Space Sync must not treat empty bookmark tables as proof that the remote source is new or empty. First activation must rely on explicit `sync_meta` initialization metadata and confirmed platform store availability; if Aira cannot distinguish a truly uninitialized remote from cloud data that is still preparing or materializing, it should show an unknown/preparing remote state instead of uploading local bookmarks as initial remote data.

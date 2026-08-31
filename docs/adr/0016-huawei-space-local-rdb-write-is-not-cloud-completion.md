# Huawei Space Local RDB Write Is Not Cloud Completion

Accepted: Huawei Space Sync must not treat a successful write into the local cloud-synchronized ArkData RDB store as proof that data reached Huawei Cloud Space or other devices. Aira should distinguish local provider save, waiting for system cloud synchronization, failure/unavailable states, and confirmed cloud completion only when the platform can reliably provide that confirmation.

Amended 2026-07-21: both Bookmark and Personalization manual Cloud Space operations confirm completion only after the
ArkData completion callback and a successful terminal `SYNC_FINISH` progress event have both arrived, regardless of
their ordering. A terminal non-success progress code fails immediately, and a 30-second bound prevents a missing
platform signal from blocking later Sync operations indefinitely. The structured Bookmark transport later extends its
bound to 120 seconds because a complete generation can contain thousands of small records; Personalization remains at
30 seconds. A local row-presence check is not remote confirmation and cannot advance a Bookmark baseline or
Personalization revision after a failed or unconfirmed cloud synchronization.

Amended 2026-07-21: before the first valid Huawei Space remote existed, failed cloud attempts left never-confirmed rows
and ArkData upload metadata in the dedicated Cloud Space RDB. With explicit user authorization, the first deployable
client performs one generation-gated reset of that dedicated RDB before either Domain opens it. This reset is not a
remote commit, migration, or conflict decision: it removes only pre-production staging state that the cloud rejected,
while the separate local Bookmark and Personalization authorities remain untouched. After a valid remote exists, this
exception cannot be reused as a general recovery mechanism.

Amended 2026-07-21: device acceptance then proved the first clean String/TEXT payloads were rejected at the cloud record
boundary. Huawei's official Cloud Space deployment guide maps `Bytes` to local `BLOB`, while ArkData documents a 2 MB
single-row read limit. Before any valid development remote existed, the explicitly authorized follow-up client therefore
performs one new development-schema reset and stores the complete canonical JSON as versioned zlib-compressed UTF-8
bytes in `snapshotJson BLOB`. Cloud completion still requires the callback plus successful terminal `SYNC_FINISH`; a
successful local compression, BLOB insert, or local row read is not cloud confirmation.

Amended 2026-07-21: device evidence proved the same BLOB codec and Cloud Space `Bytes` mapping uploads a roughly 3.9 KB
Personalization value successfully, while the 112,889-byte Bookmark value is rejected per record with `Code:400 Param
is invalid`. The authorized Bookmark-only experiment keeps one logical snapshot and one commit row but stores its
compressed bytes evenly across `snapshotJson BLOB` and `snapshotJsonPart2 BLOB`, each capped at 60,000 bytes for this
experiment. A successful two-column local update is still not cloud completion; only the unchanged callback plus
successful terminal `SYNC_FINISH` boundary may confirm the Bookmark commit.

Amended 2026-07-21: after a Huawei-account cloud-schema refresh removed the earlier schema-version conflict, the same
two-field Bookmark row still failed `1/0/1` with `Code:400 Param is invalid`, ArkData `-1108`, and terminal progress code
1. The experiment is therefore closed and not extended with more BLOB fields. Bookmark now writes one local transaction
containing all rows for an append-only structured generation and inserts its generation metadata last. Local transaction
success and local completeness validation are still not cloud completion; baseline advancement still requires successful
manual cloud confirmation and a complete post-sync generation. Personalization remains on its already-proven one-field
compressed BLOB representation.

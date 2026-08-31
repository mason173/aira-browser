# Huawei Space Sync Uses Structured RDB Data

Accepted: Huawei Space Sync will use HarmonyOS same-application cloud data synchronization over structured ArkData RDB tables, not a single bookmark snapshot blob or a user-visible Cloud Space file. Bookmarks are graph-shaped data with folders, items, ordering, and tombstones, so table-level synchronization gives Aira room for conflict handling, deletion history, and incremental repair without presenting Huawei Cloud Space as a manually browsable drive.

Amended 2026-07-21: the implemented Bookmark representation keeps the shared `AiraSyncRemoteStore` complete-snapshot
interface while projecting every append-only generation into five AGC-compatible RDB tables:
`AiraG3BookmarkGenerations`, `AiraG3BookmarkFolders`, `AiraG3BookmarkItems`, `AiraG3BookmarkOrders`, and
`AiraG3BookmarkTombstones`. Folder, item, order-metadata, and tombstone rows carry the owning `generationId` and either
the shared or App-private partition. The generation row records the parent commit set, schema/source metadata, and exact
row counts for both partitions.

The Huawei Space adapter reconstructs a generation only when every expected row count matches and the resulting complete
snapshot passes the same canonical validation used by Aira Cloud and WebDAV. Partial or orphan rows are never interpreted
as an empty remote. Each folder/item row stores its position within its current parent, while one order-metadata row per
parent preserves the order revision and explicitly empty order groups. Reconstruction rejects missing metadata,
cross-parent children, duplicate child identities, and duplicate or non-contiguous positions. Huawei platform row
conflict behavior moves records between devices but does not replace Aira's provider-baseline and bookmark conflict
algorithm.

Amended 2026-07-25: G6 keeps the same complete-snapshot `AiraSyncRemoteStore` seam but replaces generation-scoped
entity rows with one `AiraG6BookmarkRecords` table containing only `manifest` and `chunk` records. A fixed set of 256
buckets is selected from stable shared/App-private logical keys. Each non-empty bucket stores sorted canonical folder,
item, parent-order, and full tombstone records; its `logicalId` is the SHA-256 hash of the exact chunk JSON. A manifest
directly references every non-empty chunk required for one complete snapshot and records the full parent-head set,
logical/physical versions, counts, App-private presence, device/generated/update metadata, and an aggregate checksum.
The reader accepts a chunk only when each nested record exactly matches the canonical encoding for its logical kind;
extra fields or alternate JSON key order cannot form a viable snapshot. Unchanged chunks are reused across manifests,
so the physical write cost follows changed buckets instead of the whole bookmark tree.

The manifest is viable only when every referenced chunk exists, its content hash/bucket/count matches, the manifest
counts/checksum match, and the reconstructed snapshot passes canonical validation. Incomplete descendants do not hide a
complete parent head, and any G6 rows without a viable manifest are unknown/incomplete rather than an empty remote. G6
does not add manifest pages, dynamic bucket splitting, an operation log, outbox, recovery journal, parent-relative
tombstone replay, or a second merge algorithm.

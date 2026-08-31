# Huawei Space Bookmark History Retention

Superseded 2026-08-03: current-generation Bookmark Sync now has a bounded logical tombstone history. The single
`AiraBookmarkTombstoneLifecycleService` owner advances a history descriptor only when a complete local, remote, or
provider-baseline snapshot actually contains a tombstone older than the 90-day candidate cutoff. The descriptor contains
`version`, `epochId`, and `retainedFrom`; `1970-01-01T00:00:00.000Z` is the origin frontier. A frontier change is part of
the complete Provider commit envelope, and a device that sees a different frontier discards the ordinary three-way
baseline and performs a preservation-first full-snapshot rebootstrap. Old live content may therefore be duplicated or
resurrected, but an expired deletion record cannot silently delete content on a stale client.

The frontier is confirmed locally only after the target Provider accepts the projected complete snapshot, a fresh read
confirms the same commit, snapshot, and history, local apply succeeds or is merge-proven unnecessary, and the
provider-identity baseline is durable. Only then may local deleted rows with `deleted_at < retainedFrom` be physically
purged. Aira Cloud isolates this protocol at `/sync/v3/bookmarks` and `bookmark_sync_states_v3`; WebDAV isolates it at
`aira/g3/bookmarks/snapshot.json` with file envelope version 2. Huawei Space G8 isolates current Heads in
`AiraG8BookmarkHeads` and immutable content-addressed snapshot pages in `AiraG8BookmarkBlocks`. G8 format version 1
materializes only Heads at the newest `retainedFrom` frontier, including every concurrent Head at that same frontier.
Each device owns one replaceable Head slot, while 64 stable shards keep live, order, and tombstone pages in separate
lanes. A row that declares current format 1 and fails canonical parsing blocks the read; it must never be downgraded to
an empty remote head. G7 rows remain physically untouched and outside the active G8 tables. Physical G8 Block cleanup
requires a confirmed storage-epoch checkpoint and quarantine proof; until that proof exists, a maintenance failure may
retain unreachable Blocks but cannot fail Sync or delete a reachable Block.

This supersedes the Huawei-only fingerprint epoch filter described below. New runtimes do not create, read, or write
`AiraHuaweiSpaceBookmarkEpochState`; an existing local table may remain inert. The earlier decisions are retained below
as historical context.

Originally accepted: Huawei Space Sync does not delete current-protocol tombstones, commit/generation records, or device/source
metadata on a fixed time window. Cleanup is safe only after an explicit compaction protocol proves the history is no
longer needed, or after a deliberate protocol epoch/reset; otherwise a long-offline device can resurrect deleted
bookmarks when it returns.

Amended 2026-07-22: the G3 physical representation violated the intent of indefinite retention by copying the complete
tombstone set into every generation under generation-specific row IDs. A device with roughly 413 visible bookmarks and
10,555 historical tombstones produced 87 cloud `BatchInsert` operations and remained in upload for about 147 seconds.
That amplification is not required to preserve deletion history.

Bookmark format version 2 therefore starts an isolated G4 Record-Type epoch. G4 does not read, write, or manually cloud
sync the old G3 tables. The first G4 generation is built from the current visible local tree; a non-distributed local
epoch record captures exact pre-G4 tombstone fingerprints so those inherited tombstones are omitted only from the Huawei
projection without deleting them from the shared local Bookmark authority used by Aira Cloud and WebDAV.

Within G4, folders, items, and order metadata remain complete per generation. Tombstones are append-only deltas relative
to the generation's parent set: a new or changed deletion writes one `upsert` row, an explicit resurrection writes one
`clear` row, and an unchanged later generation writes no row for that tombstone. Reading follows the parent graph and
applies those deltas to reconstruct the complete canonical snapshot before merge and baseline handling.

G4 tombstone deltas still do not time-expire. Without a documented device-ack watermark or a service-owned compaction
proof, an actual deletion delta may be required by an arbitrarily old device. The bounded guarantee is that storage grows
with real deletion/resurrection events, not with every ordinary synchronization generation. The abandoned G3 rows may
remain in Huawei Cloud Space, but they are outside the G4 table-level transport and cannot inflate G4 uploads or
downloads.

Amended 2026-07-23: G5 changes only the Huawei Bookmark physical projection from five active tables to one
`AiraG5BookmarkRecords` table containing many bounded JSON records. It keeps the same parent-relative tombstone delta
semantics and indefinite current-epoch retention rule. G3 and G4 rows remain preserved but are outside the G5 manual
cloud-sync table set; they are not copied into G5, time-expired, compacted, or deleted automatically.

Amended 2026-07-25: G6 starts a clean Huawei-only tombstone epoch and stores full current tombstones in its immutable
content-addressed chunks instead of parent-relative deltas. Each device records the exact fingerprints of tombstones
already present when it first joins G6 and excludes only those fingerprints from its Huawei projection; the local
Bookmark authority and Aira Cloud/WebDAV history remain untouched, and a later changed deletion fingerprint enters G6
normally. G6 retains manifests, chunks, and projected tombstones indefinitely in its first release, reuses unchanged
chunks, and performs no automatic garbage collection, reference counting, acknowledgement tracking, or compaction.
Quota/capacity failure remains explicit rather than triggering destructive repair.

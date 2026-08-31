# Huawei Space Schema Migrations Are Non-Destructive

Accepted: Huawei Space Sync schema upgrades must be explicit, compatible, and verifiable; the client must block unknown, newer, or unsafe schema versions instead of deleting tables, rebuilding the remote store, resetting history, or treating the old remote as empty. This protects tombstones, generations, account binding, and conflict context after data has been synchronized through the user's Huawei Cloud Space.

Amended 2026-07-21: the first attempted Cloud Space schema uses AGC-compatible alphanumeric identifiers because the
live Cloud Space development console rejects underscores in Record Type names and Huawei requires the cloud Record Type
and fields to match the local ArkData table and columns. The attempted tables were `AiraG2BookmarkCommits` and
`AiraG2PersonalizationCommits`; their fields use matching camel-case alphanumeric identifiers such as `rowId`,
`accountUid`, `commitId`, `snapshotJson`, and `updatedAt`. The container remains
`aira_huawei_space_bookmarks_g2`, matching the local database name without `.db`.

The earlier underscore-named device-local tables never had a deployed matching Cloud Space schema and never formed a
valid Huawei Space remote. At the user's explicit direction, the first deployable schema does not read, copy, migrate,
publish, or delete those invalid local staging tables. Local bookmark data remains owned by the separate bookmark
database and is unaffected. Any future change after a valid production Cloud Space schema exists returns to the
non-destructive migration rule above.

Amended 2026-07-21: device verification later proved that the same dedicated RDB also retained one never-confirmed
Bookmark row, seven never-confirmed Personalization rows, and ArkData upload watermarks from failed development attempts.
Those rows were rejected before any valid cloud remote existed and blocked every subsequent readiness check from
evaluating the user's current snapshot. With explicit user authorization, the first deployable client therefore performs
one generation-gated `deleteRdbStore` reset of `aira_huawei_space_bookmarks_g2.db` before either Domain opens it. The
completion generation is stored in separate device-local Preferences so the reset cannot repeat on ordinary process
starts. The reset does not touch the local bookmark database, local personalization authorities, Aira Cloud, WebDAV, or
the AGC development/production records. This narrow pre-production exception does not weaken the non-destructive rule
once a valid Huawei Space remote has formed.

Amended 2026-07-25 after clean-reinstall verification: the pre-production `20260721` reset is retired completely. Its
Preferences marker is removed by uninstall, so retaining the bootstrap path caused every reinstallation to execute
`deleteRdbStore` immediately before the first cloud-first read, after a valid G6 remote already existed. The shared
Bookmark/Personalization RDB must now open non-destructively on every install; neither Domain may call a generation-gated
bootstrap delete, recreate that reset under another key, or delete the shared database to repair synchronization.

Amended 2026-07-25 after tracing ArkData's zero-row cloud materialization: the prior shared-RDB statement remains
historical for G2-G5 only. The accepted G6 Bookmark runtime now uses the new dedicated local RDB/cloud container identity
`aira_huawei_space_bookmarks_g6.db` / `aira_huawei_space_bookmarks_g6`. This is a clean development epoch, not a data
migration: G6 does not read, copy, repair, or delete Bookmark rows or ArkData metadata from
`aira_huawei_space_bookmarks_g2.db`. Personalization alone remains on the old G2 RDB/container with
`AiraG2PersonalizationCommits` unchanged. Application code must not mutate ArkData private relational cloud-log tables;
the G6 identity boundary is the supported clean-state reset.

Superseded later on 2026-07-25 after verifying Huawei's cloud-side deployment rules: an application normally has one
Container, and the development/production controls do not provide a second-Container replacement workflow. The
dedicated G6 Container identity above is therefore not an accepted deployment path. G6 returns to the existing
`aira_huawei_space_bookmarks_g2` Container and local `aira_huawei_space_bookmarks_g2.db`, while keeping
`AiraG6BookmarkRecords` as the active Bookmark table at that point. The attempted repair was deliberately narrower than
a database reset: when that business table was empty after a cloud-first read, the client issued `DROP TABLE` for only
`AiraG6BookmarkRecords`, recreated the schema, and retried cloud-first once. Application code did not issue SQL against
private log tables. This attempt was later disproven by true-device verification and is no longer part of the runtime.

Amended 2026-07-21: Huawei's《端云数据同步云侧环境部署指导》defines the exact Cloud Space mapping used by the BLOB
development experiment: `String` maps to local `TEXT`, `Integer` to `INTEGER`, and `Bytes` to `BLOB`.
`AiraG2PersonalizationCommits.snapshotJson` continues to use cloud `Bytes` and local `BLOB`; `updatedAt` remains cloud
`Integer` and local `INTEGER`. Bookmark used the same mapping during its failed one-field and two-field experiments, but
the current structured Bookmark schema uses only `TEXT`/cloud `String` and `INTEGER`/cloud `Integer` fields.

Amended 2026-07-21: after Personalization successfully reached the development remote, the Bookmark-only
`snapshotJsonPart2 BLOB` addition is non-destructive. The client checks `PRAGMA table_info(AiraG2BookmarkCommits)`, adds
the missing column with `ALTER TABLE ... ADD COLUMN`, and updates any current-account Bookmark row whose second part is
null or empty in place under the same `rowId` and commit identity before explicit cloud synchronization. It does not
advance the delete/reset generation or delete the shared RDB. Personalization remains a one-field BLOB and is not
migrated by this experiment.

Amended 2026-07-21: the current Bookmark schema supersedes the never-confirmed `AiraG2BookmarkCommits` transport with
five new append-only structured Record Types: `AiraG3BookmarkGenerations`, `AiraG3BookmarkFolders`,
`AiraG3BookmarkItems`, `AiraG3BookmarkOrders`, and `AiraG3BookmarkTombstones`. The client creates the matching local tables
without advancing the shared-database delete/reset generation. It deletes only the current Huawei account's rejected
legacy Bookmark staging rows and never resets or deletes `AiraG2PersonalizationCommits`. Because no G2 Bookmark record
was accepted by the cloud, there is no Bookmark remote migration or compatibility reader. Once a valid G3 remote forms,
future schema changes return to the non-destructive rule and must preserve complete generations and their parent graph.

Amended 2026-07-22: an in-place App upgrade from the false-success G2 client uses one bounded re-enable gate rather than
a G2 compatibility reader or automatic record migration. If the device still has Huawei Space selected with Bookmark
enabled and has not confirmed Bookmark format version 3, Sync Experience persists `G3 required`, pauses only the
Bookmark Domain, clears only the stale Huawei Space Bookmark runtime/status presentation, and presents one upgrade
prompt. Huawei identity, Active Provider, durable provider baseline, Personalization, Aira Cloud, WebDAV, Additional
Backup configuration, local bookmarks, and local personalization authorities remain untouched. Re-enabling Bookmark
reuses the normal capability check and current-generation merge/write path; the gate becomes complete only after that
path reports confirmed Huawei G3 Bookmark success. At that stage the G3 client retained the existing
`failed_staging_reset_generation:20260721` marker and prohibited advancing it. The later July 25 amendment above retires
the reset implementation and marker entirely after clean-reinstall evidence proved that uninstall made the old guard
repeat destructively.

Amended 2026-07-22: the user explicitly authorized a G4 Bookmark protocol epoch after true-device logs proved that G3's
per-generation full tombstone copying is operationally unbounded. G4 adds five new Record Types with the same fields:
`AiraG4BookmarkGenerations`, `AiraG4BookmarkFolders`, `AiraG4BookmarkItems`, `AiraG4BookmarkOrders`, and
`AiraG4BookmarkTombstones`. The client does not delete the shared RDB, the valid Personalization table, the local Bookmark
authority, or the G3 cloud records. Existing G3 tables are removed from the Bookmark manual-cloud-sync table set and,
when present locally, have automatic synchronization disabled. G4 uses a fresh provider-baseline identity while keeping
the user-visible Provider and Huawei account identity unchanged.

This is an isolated epoch, not an in-place G3 migration or dual write. Each upgrading device contributes its current
visible local tree when it first joins G4; an offline device's visible content can therefore merge after that device
upgrades, while its old G3 rows never become G4 lineage. A device-local, non-distributed epoch row stores only compressed
fingerprints of the tombstones that existed before that device joined G4. The filter is Huawei-specific and exact, so it
does not purge shared local history or hide later deletions with a different deletion fingerprint. No G4 Record Type
field was added beyond the accepted G3 field set; `entityType` encodes tombstone `upsert` versus `clear` operations.

The existing one-time Bookmark re-enable gate advances to version 4. Devices that still have Huawei Space Bookmark
enabled are paused once, stale G3 Bookmark runtime/status presentation is cleared, and the normal Bookmark activation
path must confirm a G4 generation before the marker completes. Personalization runtime state, Huawei identity, Active
Provider, local data, other Provider configuration, and the shared RDB remain untouched. A pending older re-enable state
is promoted to G4 instead of being discarded.

Amended 2026-07-22: while the G4 re-enable gate is required, Sync Experience's bottom immediate action routes through
the existing confirmed Bookmark-enable path instead of generic manual synchronization. Generic manual synchronization
only runs Domains that are already enabled, so it cannot satisfy a gate that intentionally paused Bookmark and must not
report a Personalization-only completion as completion of the Bookmark upgrade. The gate still clears only after the
normal Bookmark activation path confirms a G4 generation; ordinary `立即同步` behavior is unchanged once the gate is
complete.

Amended 2026-07-23: true-device multi-client failures and the Huawei Browser implementation study showed that the
five-table G4 projection creates unnecessary cross-table materialization risk. The user explicitly authorized a G5
Bookmark physical epoch that preserves the canonical snapshot protocol while replacing the five active Bookmark Record
Types with one `AiraG5BookmarkRecords` Record Type. Each generation metadata record, folder, item, parent order, and
tombstone delta identifies its logical shape through the non-reserved `recordKind` field and is encoded as its own
bounded JSON string in the common `data` field; the client rejects a single JSON record above 24,576 characters instead
of retrying the already-disproven complete-snapshot BLOB transport. Generation
metadata still carries exact per-partition record counts, parent generation ids, format/schema versions, source metadata,
and private-partition presence. A generation is readable only when those counts match, the parent graph is complete and
acyclic, entity positions agree with the stored parent order, tombstone deltas reconstruct deterministically, and the
result passes canonical snapshot validation.

G5 is another isolated epoch, not an in-place G4 migration, compatibility reader, or dual write. The local table is
created in the existing dedicated Huawei Space Bookmark RDB, only `AiraG5BookmarkRecords` participates in Bookmark manual
cloud synchronization, and any locally present G3/G4 Bookmark tables have automatic synchronization disabled. G3/G4
cloud and local rows are preserved and are never interpreted as G5 lineage. The Provider status/baseline identity,
device-local tombstone epoch row, and bounded Bookmark re-enable marker advance to version 5. Existing Huawei identity,
local Bookmark authority, Personalization, Aira Cloud, WebDAV, Additional Backup configuration, and the shared RDB are
not reset or migrated.

Amended 2026-07-25: the user explicitly authorized the isolated G6 Bookmark epoch after G5 device traces proved that a
small edit still republished the complete tree under generation-scoped row IDs. G6 creates one new
`AiraG6BookmarkRecords` Record Type with exact fields `rowId`, `accountUid`, `recordKind`, `logicalId`, `data`, and
`updatedAt`; cloud `String` maps to local `TEXT`, cloud `Integer` maps to local `INTEGER`, and `rowId` remains both local
primary key and endpoint dedup key. `recordKind` is `manifest` or `chunk`; `logicalId` is respectively a commit id or a
SHA-256 content hash. The client caps manifest JSON at 32 KiB and chunk JSON at 64 KiB, uses exactly 256 fixed buckets,
and rejects incompatible versions, oversized records, hash/count/checksum mismatches, and incomplete materialization.

G6 is not an in-place G5 migration, G5 compatibility reader, dual write, fallback, shared-RDB reset, or remote cleanup.
Only `AiraG6BookmarkRecords` participates in Bookmark manual cloud synchronization. Locally present G3/G4/G5 Bookmark
tables have automatic synchronization disabled and their local/cloud rows are never read, written, migrated, or deleted
by the G6 runtime. The durable Bookmark provider/baseline identity advances to `bookmark-g6` / `sync-provider-g6`, the
device-local tombstone epoch row advances to version 6, and the bounded Bookmark re-enable marker advances to version 6.
Huawei identity, local Bookmark authority, Personalization, Aira Cloud, WebDAV, the shared Additional Backup execution
topology, and the dedicated RDB remain unchanged. The gate applies whether Huawei Space was the active Bookmark Provider
or a Bookmark Additional Backup destination. An active Huawei Bookmark Domain is paused; a Huawei Bookmark Additional
Backup selection is removed while other backup selections remain intact. In either role, the marker advances only after
the user explicitly re-enables Huawei and the normal G6 initialization/confirmed-write path succeeds.

Amended later on 2026-07-25 after true-device verification of the empty-table repair: dropping and recreating
`AiraG6BookmarkRecords` through the same open RDB handle did invoke ArkData's formal table-drop callback, but a following
cloud-first sync still reported downloaded rows while the business table remained empty. The client therefore stops
repairing or reusing the G6 table identity. During development, with explicit authorization to discard all Huawei
Bookmark test data, the active physical epoch advances to the fresh Record Type `AiraG7BookmarkRecords` inside the same
`aira_huawei_space_bookmarks_g2` Container and local database. Its fields and manifest/chunk representation are exactly
the accepted G6 shape; only the physical table/row namespace and provider, baseline, local tombstone epoch, and bounded
re-enable identities advance to `bookmark-g7` / `sync-provider-g7` / version 7.

G7 does not read, write, copy, migrate, repair, delete, probe, or re-register G3/G4/G5/G6 rows or table metadata and does
not contain a table-drop retry. Those retired tables remain outside the active Bookmark manual cloud-sync set. Any
automatic-sync shutdown already established by the retired clients remains historical state; the G7 runtime never passes
any retired Bookmark identity to `setDistributedTables`.
Personalization continues to use `AiraG2PersonalizationCommits` in the same G2 database without a schema or behavior
change. Aira Cloud, WebDAV, the shared merge/apply/baseline algorithm, and the fail-closed empty-root guard remain
unchanged.

Amended 2026-08-25: Huawei Bookmark advances non-destructively from G7 to G8 to separate cheap remote discovery from
bulk snapshot storage. The active G8 Record Types are `AiraG8BookmarkHeads` and `AiraG8BookmarkBlocks` in the existing
`aira_huawei_space_bookmarks_g2` Container/database. Both use exact fields `rowId`, `accountUid`, `recordKind`,
`logicalId`, `storageEpoch`, `data`, and `updatedAt`; `rowId` remains the endpoint dedup key. The client must not install
or accept G8 until both cloud Record Types exist with this mapping. Local table creation and distributed registration do
not create those cloud schemas.

This is a new physical protocol identity and version-8 re-enable gate, not an in-place migration. G8 never reads, writes,
registers, copies, repairs, resets, or deletes `AiraG7BookmarkRecords` or any earlier Bookmark table. Existing G7 local
and cloud data remains recoverable outside the G8 runtime, and no G7 row participates in G8 Head discovery, block
materialization, publication, or cleanup.

Amended later on 2026-08-25 after true-device verification of an early G8 local-schema failure: a pre-release G8 table
may already exist without the final `storageEpoch` column, and `CREATE TABLE IF NOT EXISTS` does not complete that table
shape. `HuaweiSpaceRdbStoreOwner` therefore checks both G8 tables with `PRAGMA table_info` and adds only the missing
`storageEpoch INTEGER` column before creating G8 indexes and refreshing distributed registration. This operation is
idempotent and preserves all existing G8 rows. It is a bounded repair of the current G8 local schema, not a compatibility
read or migration from G7 or any earlier generation.

G8 cleanup is restricted to G8 rows and is itself non-destructive to confirmed current state. Each row carries a 90-day
storage epoch. After a seven-day quarantine, cleanup requires complete current-epoch Heads that cover all older logical
Heads; it then deletes and cloud-confirms older Heads before deleting and cloud-confirming older Blocks. Missing proof or
any cleanup error leaves rows in place and cannot fail the already confirmed Bookmark synchronization. These physical
epochs do not replace or shorten the Bookmark Domain's independent tombstone-history frontier.

Amended 2026-08-25: the earlier prohibitions on deleting `AiraG2PersonalizationCommits` apply to schema bootstrap,
Bookmark protocol upgrades, database repair, and generation migration; none may clear or reset that valid Domain table.
They do not require complete-snapshot commit ancestors to remain forever. After a fresh cloud read has identified at
least one natural Head, the active Personalization/Novel adapter may delete only observed non-Head ancestors, upload
those exact row deletions, and confirm a fresh cloud mirror. Every observed Head remains, a concurrent unseen row cannot
enter the deletion plan, and an abnormal no-Head graph skips cleanup. This is bounded physical maintenance inside the
unchanged G2/companion schemas, not a table reset, private ArkData metadata mutation, Bookmark migration, or semantic
user-content deletion. If deletion or its transport confirmation fails after a valid fresh Head was read, the adapter
keeps that semantic read usable, records deferred maintenance, and retries on a later fresh read; it never deletes an
observed Head merely to force the physical bound.

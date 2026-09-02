---
status: accepted
supersedes: ADR-0004, ADR-0008
---

# Bookmark Sync Uses One Snapshot Commit Path

Current-generation Bookmark Sync has one correctness algorithm across the App, Aira-sync, Aira Cloud, WebDAV, and Huawei Space: capture the complete local snapshot, read the complete remote snapshot, merge both against the durable provider baseline, conditionally write with the expected parent, apply the confirmed merged snapshot locally when the merge requires a local change, then durably persist the new baseline before reporting success. A full merge that proves the complete local and remote snapshots already contain the same confirmed content is a successful local no-op: it does not physically re-apply the local snapshot or rewrite an identical baseline. The equality check includes the App-private Bookmark partition rather than relying only on regular Bookmark change counters. When either side differs, the implementation compares that side with the confirmed merged snapshot and only writes or applies the merged snapshot; it never substitutes the raw remote snapshot for a private-only local or concurrent merge. If the provider exposes a different commit identity for equivalent confirmed content, the identity-scoped baseline may advance to that observed commit without a redundant local apply. Stable IDs, folder/item ordering, tombstones, conflict resolution, WebDAV ETag conditions, and Huawei Space append-only multi-head aggregation remain mandatory. Local mutations record one durable pending marker, while bounded periodic full sync discovers remote-only changes.

Amended 2026-08-03: Bookmark tombstones have one cross-Provider lifecycle owner,
`AiraBookmarkTombstoneLifecycleService`. The canonical snapshot schema remains version 2; its commit envelope and
provider baseline additionally carry history descriptor version 1 with `epochId` and `retainedFrom`. The origin frontier
is `1970-01-01T00:00:00.000Z`. A normal run proposes `now - 90 days` only when the local snapshot, remote snapshot, or
provider baseline actually contains a tombstone older than that cutoff, so an idle account does not generate empty
history commits on every run. Concurrent descriptors are ordered first by `retainedFrom` and then by `epochId`.

Only a baseline whose history exactly matches the selected remote and locally confirmed history may participate in the
ordinary three-way merge. Any mismatch is an expired-cursor condition: the baseline is excluded, both complete snapshots
are projected to the newest frontier, and the normal full merge rebuilds preservation-first. That path may resurrect or
duplicate stale live content, but it cannot replay a retired tombstone. Even when visible content is otherwise identical,
a changed history descriptor requires a Provider write. The new frontier becomes local authority only in this order:
target commit, fresh complete read-back of commit/snapshot/history, successful local apply or merge-proven no-op,
provider-identity baseline persistence, local frontier confirmation, then physical deletion of local rows whose
`deleted_at` is strictly earlier than `retainedFrom`. A failure at any earlier point leaves the previous frontier or a
history-mismatched baseline, which forces the same safe rebootstrap on retry.
Fresh snapshot capture no longer has a `generationSeed` branch that deletes or omits local tombstones before this
sequence; current-generation isolation is provided by Provider protocol identity, not by pre-commit local erasure.

The new generation is isolated independently for all three Providers: Aira Cloud uses `/sync/v3/bookmarks` and
`bookmark_sync_states_v3`; WebDAV uses `aira/g3/bookmarks/snapshot.json` with file envelope version 2; Huawei Space keeps
the one `AiraG7BookmarkRecords` table and advances its manifest/index/chunk encoding to format version 3. Huawei
materialization considers only valid format-3 manifests at the greatest `retainedFrom`, while retaining all concurrent
epochs at that same frontier for multi-head merge. Older history rows may remain physically in ArkData but neither their
indexes/chunks nor format-2 development rows participate in the active head. The retired Huawei-only tombstone
fingerprint store and Provider-specific local-snapshot projection are removed; Aira, WebDAV, and Huawei now receive the
same lifecycle projection. This is logical history retirement, not an oplog, acknowledgement matrix, recovery journal,
compatibility read, or application-managed physical Huawei cloud garbage collector. A malformed manifest that declares
format 3 fails closed and cannot be treated as an unsupported old row or an empty remote head.

Amended 2026-07-22: the bounded periodic Bookmark run still performs one complete Provider read so remote-only changes
remain discoverable. After merge/write confirmation, its passive remote-status projection reuses the already-confirmed
snapshot and commit instead of reading the same Provider again. This projection may count the visible regular Bookmark
entities for presentation and persist that cache together with runtime health, but it is not another authority, baseline,
head probe, fast path, or correctness read. Explicit user-requested remote inspection remains a fresh Provider read.

WebDAV stores the current-generation Bookmark state as one complete `aira/g3/bookmarks/snapshot.json` version-2 envelope containing commit metadata, history descriptor, and the canonical snapshot. Its ETag is the replacement revision. First publication prefers `If-None-Match: *`; when a provider demonstrably ignores that header, or returns `409`/`412` for a disposable conditional create whose immediate read confirms the random probe path is absent, the App and Aira-sync may use a transient same-collection upload followed by `MOVE` with `Overwrite: F`. The capability probe may use unconditional writes only for its freshly randomized disposable CAS and MOVE fixture paths. After a rejected conditional create, the CAS probe path must first be confirmed absent before its unconditional fixture write; the probe never performs an unconditional first write to `snapshot.json`. The fallback is accepted only after the probe proves that an existing destination is preserved, an absent destination is created exactly, the result exposes an ETag, a matching revision condition succeeds, and the stale condition fails. Each actual snapshot ETag is classified independently: strong ETags use HTTP `If-Match`; a weak ETag cannot satisfy `If-Match` strong comparison, so it uses the WebDAV `If: ([W/"..."])` condition syntax only when the capability probe has already proved weak-ETag `If` support with a current-match success and stale-match rejection at `409`/`412`; otherwise the provider remains unsupported and fails closed. The App Personalization WebDAV adapter applies the same conditional-create rejection, revision-condition verification, and verified MOVE fallback to `aira/g2/personalization/snapshot.json`; Aira-sync remains Bookmark-only. Transient create files are cleanup-only transport details, never remote history, a lock, a second snapshot authority, or a recovery journal. The App and Aira-sync do not read or migrate the previous head/commit/manifest/pack layout.

Amended 2026-08-02: Aira-sync WebDAV GET requests bypass the browser HTTP cache so a capability check or snapshot read
cannot reuse a stale representation and validator. When a provider ignores the disposable CAS probe's duplicate
`If-None-Match: *` create, Aira-sync does not trust one immediate read: it boundedly re-reads the randomized probe until
both the expected latest body and a valid ETag are visible. An older body, missing validator, or absent probe may be
retried only within that bound; exhaustion fails closed before matched-update verification and before any real
`snapshot.json` commit or baseline advancement. This confirmation is capability-probe behavior only and does not relax
the snapshot CAS, verified `MOVE Overwrite: F`, weak-ETag, merge, local-apply, or baseline contracts.

Amended 2026-07-20: some providers return `409 Conflict` rather than `404 Not Found` when the first snapshot read targets a path whose intermediate collections do not exist. On that first-read conflict, the App and Aira-sync WebDAV adapters each create their fixed root collections in order and retry the same GET once; only a resulting `404` means that the current-generation remote is empty, while a persistent `409` or any other error remains fail-closed.

The one-snapshot WebDAV transport has a fresh baseline identity derived from protocol version, normalized endpoint, username, and root path. Previous WebDAV baselines are ignored without migration or local-bookmark deletion. Both clients fail closed before merge or write unless the envelope contains the exact schema version, all mandatory canonical arrays and entity fields, and unique canonical entity/order/tombstone keys.

Amended 2026-08-03 after true-device Huawei initialization diagnosis: App local snapshot capture canonicalizes repeated
Bookmark tombstones by `type|id` before any Provider projection, validation, merge, or write. A repeated key can arise
when an older cloud-synced row already carries the canonical origin ID and a later local-import row without an origin ID
deterministically resolves to that same entity ID; if both rows are later deleted, they represent one logical deletion,
not two canonical records. The snapshot retains the freshest deletion, then the highest known revision and a stable actor
tie-breaker. It does not purge the local Bookmark database, weaken unique-key validation, create a compatibility read, or
change Provider identity, merge, CAS/ETag, Huawei G7 projection, local apply, pending, or baseline semantics.

Amended 2026-08-03 after the follow-up tombstone architecture audit: App local capture performs one canonical identity resolution
before emitting Bookmark arrays. A collision containing only deleted local rows still becomes one freshest tombstone. If
any colliding row remains live, a live row retains the canonical ID, additional live rows receive deterministic collision
IDs so visible content is duplicated rather than discarded, and local tombstones opposed by that same canonical live
identity are suppressed. Canonical validation enforces live/tombstone disjointness within each partition, entity-ID
disjointness between shared and App-private partitions, and parseable tombstone timestamps before local apply or any
Provider write. Aira Cloud, WebDAV, and Huawei Space App adapters and the Aira server enforce the same write-side rule.
Tombstone merge uses `type|id` and resolves concurrent metadata by deletion time, known revision, then actor. This adds no
oplog, outbox, journal, migration, tombstone GC, compatibility path, Provider-specific merge, or schema/transport change.
Live/tombstone disjointness is evaluated by entity ID even if the malformed opposing records claim different entity
types, because local materialization ultimately resolves deletion targets by canonical ID. Canonical root IDs remain
owned by the four real local root nodes, and apply-time origin aliases cannot overwrite the collision owner's one-to-one
entity mapping.

Amended 2026-08-04 after App and Aira-sync both reported an invalid Aira Cloud snapshot: ordinary three-way merge still
resolves a tombstone against a live entity of the same type with the existing deletion/edit and Provider-transition
rules. After that resolution, if a surviving live folder or item owns an ID that is also carried by an opposite-type
tombstone, the live entity owns the canonical identity and only that opposite-type tombstone is removed. This final
canonicalization applies to the App's shared and App-private data sets, its synchronous and cooperative merge paths, and
Aira-sync's ordinary and missing-baseline merges. It does not suppress an ordinary same-type deletion, revive an entity
deleted on both sides, change conflict resolution, or select one complete snapshot over the other.

The Aira Cloud v3 server now enforces the same complete canonical tree on both snapshot reads and writes as the App and
Aira-sync: every folder/item parent and order parent exists, every live entity appears exactly once in the order matching
its parent, and every live entity is reachable from the root order. A field-valid but structurally invalid stored row
fails closed instead of being returned to clients. This repair changes no snapshot schema, Provider identity, history
frontier, CAS behavior, baseline, migration, compatibility path, or existing production row.

Aira Cloud and Huawei Space use the same canonical validation rule at their current-generation seams. The Aira server stores the g3 canonical snapshot and history descriptor directly under database CAS, returns no legacy `files`, and creates a nonce-bearing commit token so equal device/time inputs cannot repeat a commit. Huawei Space keeps the same complete-snapshot `AiraSyncRemoteStore` interface but projects each append-only generation into many bounded JSON records in one cloud-synchronized RDB table. It does not construct or parse the retired head/commit/manifest/pack file layout. Aira-sync treats `appPrivateBookmarks` as an opaque App-owned partition: it carries the current remote/baseline value through shared-bookmark writes but never applies it to the browser tree.

Huawei Space remains append-only multi-head rather than blind replacement. If the identity already has a valid durable provider baseline, Bookmark Sync uses that baseline as the last known target snapshot and appends a new logically complete manifest whose parent set references every currently materialized head. It does not reinterpret the source as a destructive empty remote, delete local content, or change the Active Provider early. A later materialized older head becomes another merge input, so either case may duplicate or resurrect content but cannot silently discard the last known or local snapshot. The current physical projection uses one `AiraG7BookmarkRecords` table with `manifest`, immutable content-addressed `index`, and immutable content-addressed `chunk` record kinds. Format version 2 maps stable shared/App-private logical keys into 4096 fixed buckets, groups them under 64 fixed index shards, deterministically segments a bucket when needed, and splits every logical parent order into canonical 64-ID `orderPart` records. Each manifest references exactly the 64 indexes; each index references the bounded chunks needed for its 64-bucket range. Every manifest, index, and chunk JSON row is measured as UTF-8 and capped at 12 KiB before ArkData receives it. Unchanged chunks and indexes reuse their existing rows, while an ordinary bookmark move normally changes only the affected bucket chunks, their index shards, and the new manifest. The manifest carries the complete parent-head set, schema/format versions, fixed bucket count, index references, logical per-partition counts, physical record count, aggregate checksum, device/generated/update metadata, and App-private presence. A manifest is viable only when every referenced index and chunk exists, each content hash/shard/bucket/segment/count matches, all order parts are complete and consistent, every nested logical record exactly matches its canonical encoding, aggregate counts/checksum match, and the reconstructed snapshot passes canonical validation. Incomplete descendants do not suppress complete parent heads, and G7 rows without any viable manifest are unknown/incomplete rather than an empty remote. A local transaction appends missing chunks, then missing indexes, then the manifest, but that local save still awaits successful system cloud propagation and post-sync materialization before local apply or baseline advancement.

Amended 2026-07-22: devices upgrading from the cloud-unconfirmed G2 Huawei Bookmark transport retain the same
provider identity and durable baseline, but pause Bookmark once and require explicit re-enable. This is an activation
gate, not a second data algorithm. On re-enable, an empty G3 remote plus a valid baseline uses that baseline only as the
last-known merge input and still proceeds through `writeState()` so the complete current local/merged snapshot is
published as a real structured G3 generation. An absent baseline also follows the same normal empty-remote merge and
full write. The upgrade marker advances only after the existing terminal-success and complete-generation checks pass;
failure leaves Bookmark paused/required and cannot advance the baseline or report success.

Amended 2026-07-22: G4 gave Huawei Space a fresh durable baseline identity and a provider-local input projection while
leaving the shared snapshot/merge/write/apply/baseline algorithm unchanged. Before the first G4 merge on each device, a
non-distributed epoch store captures the exact tombstone fingerprints already present locally and filters only those
entries from Huawei input. The canonical local database is not purged, so Aira Cloud and WebDAV keep their existing
history. G4 then writes the projected merged snapshot and records that same projected snapshot as the G4 baseline.

Amended 2026-07-23: G5 preserves that Huawei-only input projection and the shared logical algorithm, but advances the
durable Provider identity and local epoch row to `bookmark-g5`. It does not read G4 as G5, delete G4 records, change
Aira Cloud/WebDAV representations, or alter Personalization. Devices with Huawei Space Bookmark already enabled pass
the existing bounded re-enable flow once more before a G5 generation can become the confirmed current remote.

G5 uses explicit manual cloud synchronization with table auto-sync disabled. Only `AiraG5BookmarkRecords` is included
in the Bookmark cloud-sync table set; locally present G3/G4 Bookmark tables are retained with automatic synchronization
disabled. One data-layer transport coordinator
serializes Bookmark and Personalization `cloudSync` calls per Huawei account/database; repeated callers for the same
table set share the registered task, while different table sets wait in the same queue. A post-write confirmation is
always a fresh queued task, so it cannot join a task that began before the local generation/commit was inserted. Success
still requires both the completion callback and terminal successful `SYNC_FINISH`. The Bookmark caller has a five-minute
confirmation bound; if it expires, the rejected promise remains registered and the database queue stays blocked until
the original ArkData task later reaches both success signals or a real terminal error. This prevents retries from
overlapping a platform task that may still be running. Huawei official declarations do not promise a device-ack
watermark, safe application tombstone compaction, or reusable concurrent `cloudSync` task-merging semantics, so the App
does not depend on them.

Amended 2026-07-24: ordinary Huawei Space reads no longer decode and reconstruct every append-only G5 generation. The
record repository first builds a lightweight physical catalog from generation metadata plus grouped row counts, derives
the complete multi-head set, and then materializes only those heads' complete entity/order payloads together with the
tombstone ancestry required to reconstruct each logical snapshot. A write reuses the already materialized parent-head
snapshots for tombstone-delta calculation, and post-write confirmation selectively materializes the committed generation.
This is one Provider-local interpretation path, not a remote-head probe or second correctness algorithm: `readState()`
still returns the same complete canonical snapshot, multi-head merge remains above the repository seam, parent-set/CAS
checks are unchanged, and baseline advancement still occurs only after confirmed remote commit and successful local apply.

Amended 2026-07-25: G6 preserves the same Huawei-only input projection and shared logical algorithm while advancing the
durable Provider/baseline identity and local epoch row to `bookmark-g6` / `sync-provider-g6`. It does not read G5 as
G6, migrate or delete G5 rows, dual-write, fall back, change Aira Cloud/WebDAV representations, or alter
Personalization. Devices with Huawei Space Bookmark selected either as the active Provider or as an Additional Backup
destination pass the bounded re-enable flow once more before a G6 manifest can become the confirmed current remote. The
gate pauses only an active Huawei Bookmark Domain or removes only the Huawei Bookmark backup selection; other active
Providers and backup destinations keep their configuration. The first G6 activation captures exact pre-G6 local tombstone
fingerprints and seeds an empty G6 remote from the device's current visible projected snapshot; an existing G6 remote
uses the ordinary read/merge/CAS path.

Only `AiraG6BookmarkRecords` participates in G6 Bookmark manual cloud synchronization. Locally present G3/G4/G5
Bookmark tables are retained with automatic synchronization disabled and are never read, written, or deleted by the G6
runtime. The physical projection contains no manifest pages, dynamic buckets, operation log, outbox, recovery journal,
parent-relative tombstone replay, automatic garbage collection, or compaction. Immutable manifests, chunks, and current
epoch tombstones are retained; quota errors fail explicitly. Cloud completion still requires both ArkData terminal
confirmation and successful complete materialization of the written manifest. The existing serialized account/database
transport queue and five-minute Bookmark confirmation bound remain unchanged.

Amended 2026-07-25 after true-device clean-install verification: Huawei Bookmark G6 uses directional ArkData barriers
rather than the ordinary time-first mode for every operation. Every remote read, capability check, and pre-write head/CAS
read completes `SYNC_MODE_CLOUD_FIRST` before the absence of local distributed rows may mean an empty remote. Only after
the complete merged generation has been appended locally does post-write confirmation use `SYNC_MODE_NATIVE_FIRST`.
This prevents a newly installed empty local store from winning a timestamp comparison, reporting false success, and
publishing an unrelated empty root before historical manifests have materialized. The serialized transport task key
includes the synchronization mode, so a cloud-first read cannot share a native-first upload task for the same table.
Personalization retains its existing time-first behavior; Aira Cloud, WebDAV, merge, tombstone, local-apply, baseline,
and Additional Backup contracts are unchanged.

Amended 2026-07-25 after a later clean-reinstall trace: the obsolete pre-production shared-RDB bootstrap reset is no
longer part of either Huawei Domain's open path. Uninstall removed its device-local completion marker, which made the
next installation delete the dedicated RDB immediately before cloud-first materialization. Bookmark G6 also fails
closed when a parentless write would publish a snapshot with no shared/App-private bookmark items or tombstones after
the pre-write cloud-first read still exposes no remote commit. That state raises an operation-local retry error and must
not proceed to local chunk insertion or `SYNC_MODE_NATIVE_FIRST`. Existing lineages, deletion-only snapshots with real
tombstones, and non-empty first roots retain the normal append path. Personalization data/merge behavior is unchanged;
only its dependency on the retired shared-database delete is removed.

Amended 2026-07-25 after the clean-install hypothesis was disproven: the G6 Bookmark table is registered as an ArkData
`DISTRIBUTED_CLOUD` table with cloud synchronization enabled and automatic synchronization disabled. It does not set
`DistributedConfig.tableType`; Huawei documents `SINGLE_VERSION` and `DEVICE_COLLABORATION` as device-to-device storage
mechanisms, while the official relational-store cloud-sync example leaves `tableType` unspecified. A fresh development
environment, a newly uploaded complete G6 root, clean reinstall, and system Huawei-account re-login still failed to
materialize any remote rows while `SINGLE_VERSION` was set, so it is not part of the accepted cloud contract. The G6
manifest/chunk schema, append-only head semantics, manual cloud-first/native-first barriers, and logical Sync algorithm
are unchanged. Personalization keeps its existing distributed-table configuration.

Amended 2026-07-25 after tracing the clean-install failure through DistributedDB: a cloud-first G6 read may restore
rows into ArkData's private relational cloud-log table without restoring the corresponding application table rows.
DistributedDB then classifies every cloud record as `UPDATE` from the orphan `cloud_gid` / primary-key hash, accepts a
zero-row SQLite update as successful, and reports terminal code `0` while `AiraG6BookmarkRecords` remains empty. Direct
application mutation of that private log table fails and is not an accepted recovery mechanism. Because this is still a
development epoch and the user explicitly rejected data migration, Bookmark G6 moves to the fresh dedicated local
RDB/cloud container identity `aira_huawei_space_bookmarks_g6.db` / `aira_huawei_space_bookmarks_g6`. The old G2 local
Bookmark cache is not read, copied, migrated, repaired, or deleted by G6. Personalization remains on
`aira_huawei_space_bookmarks_g2.db` with its existing table, data shape, and synchronization behavior. Aira Cloud,
WebDAV, merge, apply, baseline semantics, and the G6 Record Type shape are unchanged; the new Bookmark database identity
intentionally creates a fresh provider baseline/cache namespace.

Superseded later on 2026-07-25 after Huawei cloud-side deployment review: the existing application Container
`aira_huawei_space_bookmarks_g2` remains the single Container for both Huawei domains; a second `g6` Container is not
required or supported by the documented deployment flow. The implementation therefore keeps the local database name
`aira_huawei_space_bookmarks_g2.db`. A G6-only business-table drop/recreate and cloud-first retry was attempted without
private DistributedDB SQL, migration, compatibility reads, or Personalization changes.

Superseded again later on 2026-07-25 after true-device verification: ArkData invoked its formal table-drop callback, but
recreating `AiraG6BookmarkRecords` through the same RDB handle still left the next reported cloud download absent from
the business table. The active development epoch therefore advances to `AiraG7BookmarkRecords` inside the same existing
G2 Container/database. G7 keeps the exact accepted manifest/chunk data shape, 256-bucket projection, size limits,
canonical validation, append-only multi-head semantics, directional cloud barriers, and fail-closed empty-root guard.
Only the physical table/row namespace and Bookmark provider, baseline, tombstone-epoch, and re-enable identities advance
to `bookmark-g7` / `sync-provider-g7` / version 7. G7 does not read, write, migrate, repair, delete, re-register, or
dual-write G6 rows/table metadata and contains no empty-table drop/retry path. G3/G4/G5/G6 remain outside the active
manual cloud-sync set; Personalization,
Aira Cloud, WebDAV, shared merge/apply/baseline semantics, and user-visible Sync behavior are unchanged.

Amended later on 2026-07-25 after redacted true-device row diagnostics: a G7 `NATIVE_FIRST` upload accepted 329 of 330
rows and rejected exactly one. The rejected outlier was the only 19,750-byte manifest; a 10,585-byte manifest and every
chunk up to 3,571 bytes succeeded. G7 therefore advances its physical JSON to format version 2 in the same
`AiraG7BookmarkRecords` table and field mapping. The bounded manifest/index/chunk topology and 12 KiB per-row cap are the
accepted contract described above. Current G7 data is development-only and explicitly disposable, so format-v1 rows are
not read, migrated, repaired, or dual-written. Deployment resets those test rows and the local App installation before
format-v2 acceptance. A representative 50,000-bookmark projection produced 4,096 chunks and 64 indexes; its largest
chunk was 11,341 bytes, largest index 6,120 bytes, and manifest 6,095 bytes. This physical correction does not change the
shared snapshot merge, Provider switching, baseline, confirmation, Aira Cloud, WebDAV, or Personalization contracts.

Amended 2026-07-25 after a true-device Aira Cloud -> Huawei Space transition with 34 folders/421 bookmarks: selecting
Huawei as the Active Provider no longer requires the already-enabled Bookmark Domain's first G7 upload to finish inside
the Provider-selection operation. After Huawei readiness and any enabled Personalization work succeed, the client saves
`remoteKind=huawei_space` and a non-zero Bookmark pending marker in one settings mutation, then schedules the ordinary
Automatic Runtime. Process termination pauses execution but preserves that intent; cold start, foreground entry,
reliable-network recovery, periodic execution, and the existing failure backoff resume the same complete-snapshot flow.
The pending marker is cleared only by ordinary successful Bookmark synchronization. ArkData progress code 1 remains a
failed attempt, not a false success. Only classified transient Huawei failures (unknown, network, lock contention, and
confirmation timeout) receive automatic retry; cloud-disabled, record-limit, capacity/network-policy, capability, and
conflict failures remain explicitly blocked until a later user action establishes a new attempt. The Huawei provider
baseline still advances only after complete G7 manifest confirmation and successful local apply. Because a failed
`NATIVE_FIRST` can leave the attempted manifest/indexes/chunks materialized in the local ArkData business table, every pending
Huawei Bookmark retry first performs a fresh `NATIVE_FIRST` confirmation before reading those rows as a remote head.
This prevents an unconfirmed local commit from becoming an apparent remote no-op that clears the pending marker. It adds
no operation log, outbox, recovery journal, dual write, alternate merge path, or new remote representation. Read-only
status refresh does not execute that write-side confirmation; while pending it reports the Huawei remote head as not yet
confirmable instead of reading locally staged rows as remote state. Additional Backup activation, Aira Cloud, WebDAV,
and Personalization retain their existing transition semantics.

Amended 2026-07-25: first activation or re-enablement of Huawei Space Bookmark now uses that same durable pending handoff
instead of waiting in a foreground progress operation. Enabling the Domain persists the enablement intent and pending
marker before returning; the ordinary Automatic Runtime then performs the unchanged complete local capture, cloud-first
remote read, three-way merge, conditional G7 commit, native-first confirmation, local apply, and baseline commit. Before
the first real success, retryable failures back off at 10 seconds, 30 seconds, 1 minute, 2 minutes, and 5 minutes maximum;
cold start, foreground entry, reliable-network recovery, periodic execution, and manual sync can resume the pending
work. A blocked failure remains blocked rather than looping. Incomplete manifest/chunk arrival is explicitly retryable
and never means an empty remote. The G7 re-enable marker completes only after pending clears and the Huawei Bookmark
runtime records an unblocked success. This changes waiting and presentation only; it adds no alternate merge/write path,
new persistent queue, storage representation, migration, compatibility read, or baseline exception.

Amended 2026-07-28 after true-device cross-device deletion diagnostics: the shared Huawei RDB owner exclusively owns
ArkData cloud-table registration. It creates both active business tables, reopens the prepared RDB, and registers
`AiraG7BookmarkRecords` and `AiraG2PersonalizationCommits` together before publishing the one shared handle. Transient Bookmark and
Personalization remote-store instances never call `setDistributedTables`. Registration is also database-lifetime state,
not process-lifetime state: after a successful registration the owner records a local, non-distributed registration
version and later process/cold starts skip `setDistributedTables` until that explicit version changes. When this marker is
introduced to an existing database that already contains Bookmark or Personalization business rows, the owner adopts the
accepted existing registration without upgrading it again; an empty or newly created database still performs and records
the first registration. Re-registering the same tables from transient stores or each new process produced repeated
`UpgradeDistributedTable` / SQLite schema-change events, reset the observed local upload water to zero, and turned a
one-bookmark deletion into hundreds of existing-row `batchUpdate` requests until Huawei's cloud lease renewal failed.
Each table retains its accepted `DISTRIBUTED_CLOUD` configuration and manual-sync policy.
The shared Container/database, G7 physical format, complete-snapshot semantics, directional cloud barriers, pending
marker, confirmation, merge, local apply, and baseline contracts are unchanged.

Superseding amendment 2026-07-28 after true-device local-deletion performance diagnosis: G7 post-write confirmation no
longer uses `SYNC_MODE_NATIVE_FIRST`. The installed Huawei SDK documents that mode as forcing native data to the cloud,
and the corresponding DistributedDB force-push query selects every eligible local row rather than only locally dirty
rows. A projection that appended 12 chunks, 20 indexes, and one manifest therefore also sent 591 unchanged rows as
`batchUpdate`; the repeated 100-row batches exhausted the Huawei cloud lease and produced `403`, DistributedDB `-1108`,
and progress code 1 before a later 102-second retry succeeded. After appending a G7 generation, the write-side barrier
now runs a fresh `SYNC_MODE_TIME_FIRST` task for incremental commit, waits for its completion callback and successful
terminal progress, and then runs a separate fresh `SYNC_MODE_CLOUD_FIRST` task for remote confirmation. Pending retries
use the same two-task barrier before locally materialized rows may be read as a confirmed remote head. Failure or timeout
of either task remains a failed attempt: it preserves the pending marker and cannot advance the Provider baseline,
claim confirmation, or proceed as an apparent remote no-op. Pre-write reads remain cloud-first, and the parentless empty-
root guard still fails before inserting rows or starting the write-side barrier. The shared transport queue, complete-
manifest check, G7 table/schema/format, projection, immutable multi-head semantics, merge, local apply, pending lifecycle,
Personalization, Aira Cloud, WebDAV, Additional Backup, and Sync UI remain unchanged.

Order merge is deterministic and shared by App and Aira-sync: one-sided reorder uses the changed side; concurrent differing orders choose by revision, update time, `updatedBy`, then IDs, while retaining otherwise-unplaced live entities. Deletion versus a concurrent incompatible edit is a conflict for regular and App-private Bookmark entities; single-sided deletion still propagates automatically. A failed local delete, move, or apply is fatal and cannot advance the baseline.

Amended 2026-08-03: the automatic single-sided deletion rule retains one App-only exception for an established Bookmark
Provider transition between any two of Aira Cloud, Huawei Space, and WebDAV. The canonical merge ignores a local
tombstone when the target snapshot still contains that live entity and ignores a target tombstone when the local snapshot
still contains that live entity. The rule applies equally to regular and App-private folders/items, including the deferred
Aira Cloud -> Huawei Space pending handoff, and removes only the opposing tombstone from the merged complete snapshot. It
does not prefer one whole snapshot, suppress a tombstone when both sides lack the entity, bypass conflict handling for
concurrent live edits, or alter ordinary Active Provider synchronization. The confirmed merged snapshot still follows
the one target write, successful local apply, and target-identity baseline commit path. Aira-sync, Additional Backup,
Aira/WebDAV/Huawei transport, Provider identities and baselines, G7 projection/confirmation, and snapshot schema remain
unchanged.

Amended 2026-08-03 after a true-device destructive Aira Cloud -> Huawei Space transition: the deferred transition source
is required durable `AiraSyncSettings` state, not optional metadata. Every settings reconstruction, including Provider
runtime-state and remote-status-cache updates, preserves `pendingBookmarkProviderSwitchFrom` while the matching Bookmark
pending marker remains active. Only successful pending clearance, fresh Huawei initialization, or deliberate
Provider/account removal clears the source together with the pending intent. The previous runtime-state reconstruction
omitted the newly created source before its first save, so the retry merge fell back to ordinary deletion propagation and
allowed Aira tombstones to remove Huawei live entities. This correction restores the existing live-preserving transition
merge; it does not change ordinary same-Provider deletion propagation, tombstone retention, snapshots, baselines,
transports, or Huawei G7 storage.

Amended 2026-08-03 after a same-account Provider-switch apply reported success while dropping the target's live tree:
live-preserving transition merge also preserves the protected entity's canonical order membership. A canonical Bookmark
data set is valid only when every live folder/item has a valid folder-or-root parent, appears exactly once in the order
for that same parent, and is reachable from the root order; orders cannot name unknown entities or non-folder parents.
Local apply fails before writing if its node projection loses any validated live entity. After writing, Sync rebuilds a
fresh canonical snapshot from the local database and compares the Bookmark database's reproducible content with the
merged snapshot before recording the Provider baseline or clearing pending state. This postcondition applies whenever a
merged snapshot is physically applied. It does not change merge-proven local no-ops, ordinary same-Provider deletion
propagation, first activation, Additional Backup, or transport/CAS semantics.

Amended 2026-08-03 after the corrected projection still failed its fresh-database postcondition: canonical entity IDs
can be disjoint while an existing row's planned identity and historical `originId` alias both resolve to one physical
local node ID. Local apply therefore derives the complete canonical live projection before writing and excludes every
physical local node ID occupied by that canonical live projection from the effective delete set. The live projection
wins only for that physical alias collision; an ordinary same-Provider tombstone still deletes its local node when no
live projected node occupies the physical ID. The existing fresh-database postcondition remains mandatory after writes.

Amended 2026-07-24: the shared Bookmark merge implementation is the canonical convergence owner for both regular and
App-private Bookmark content. Its result reports two distinct decisions: whether the canonical remote snapshot requires
a Provider write, and whether the merged content requires a physical local materialization. Remote equality remains a
complete canonical snapshot comparison, including revisions, order metadata, tombstones, and both partitions. Local
materialization equality compares every field the Bookmark database can reproduce, including entity content, hierarchy,
timestamps, authorship, and child order, but does not force a local apply for canonical revisions, independent order
metadata, or tombstone records that the local Bookmark model cannot persist. Those canonical fields remain preserved in
the confirmed remote snapshot and durable baseline. Sync orchestration consumes these decisions rather than
reimplementing equality or inferring a write from regular-only counters. For regular and App-private orders alike, the
merged order preserves the maximum existing revision when its final IDs match either input side; it increments exactly
once only when the merge synthesizes an order that matches neither side. A generated timestamp alone is not a semantic
difference. These ownership rules do not change the complete logical Provider read, conditional commit, baseline, conflict, or
Huawei append-only multi-head contracts.

Amended 2026-08-04 after a clean-install Aira Cloud trace rebuilt 25 shared orders as 24: an explicit parent order with
an empty `ids` array and an absent parent order are equivalent only for local materialization. The local Bookmark store
persists child positions and cannot reproduce a standalone order record for an empty folder. Local verification
therefore removes empty orders from both sides before comparing reproducible order content. Every non-empty order still
requires the same parent key and the exact ordered child IDs. Complete Provider snapshot equality, remote commits,
canonical validation, order metadata, and baseline content remain unchanged.

Amended 2026-08-04 after public-entry failure and stale-readback journeys: every Bookmark Provider write, including a
history-only write and an Additional Backup write, must be followed by a complete Provider read-back that confirms the
exact commit ID, history descriptor, and canonical snapshot. This confirmation is unconditional once a write occurs;
it is not limited to retention-frontier changes. Only a confirmed write may proceed to local apply or its proven no-op,
the fresh local-materialization postcondition, Provider-baseline advancement, pending-state clearance, history-frontier
confirmation, and physical tombstone cleanup. A stale or incomplete read-back fails the run without advancing any of
those states.

Amended 2026-08-04 after the cross-client generation audit: Aira-sync uses the same `/sync/v3/bookmarks` Aira Cloud state,
`aira/g3/bookmarks/snapshot.json` WebDAV envelope version 2, history descriptor, 90-day frontier selection, and complete
post-write read-back rule as the App. Its g3 provider baselines, runtime status, pending-conflict state, and WebDAV root
are isolated from the retired generation without a compatibility read or migration. The existing desktop device ID,
bookmark node-to-entity mapping, selected Provider, authoritative extension-storage ownership, and one cross-context
execution lock are retained. Aira-sync confirms local materialization before saving its provider baseline; because its
local browser tree has no independent tombstone repository, the confirmed projected baseline is also the durable local
retirement of expired desktop tombstones. App-private Bookmark data remains opaque pass-through data and is never applied
to the desktop browser tree. Superseding the earlier App-only scope, an established Aira-sync switch between Aira Cloud and
WebDAV also preserves a live Bookmark against an opposing target or local tombstone during the selection-time merge. The
authoritative selected source determines that intent after the execution lock is acquired; first activation and repeated
selection of the same source remain ordinary merges. The target source is persisted only after confirmed remote commit,
successful local apply or verified no-op, and baseline advancement. Once selected, ordinary synchronization against that
same source resumes normal deletion propagation.

Amended 2026-08-04 after an Aira-sync first-sync preservation duplicate was deleted as a complete folder subtree: the
Aira-sync merge result discards every non-root order whose parent is not a folder in the merged live entity set. Historical
baseline/local/remote order keys cannot retain an empty order for a deleted folder, because that would make an otherwise
valid folder-and-child tombstone merge fail canonical validation before the Provider write. The deletion is committed as
one complete canonical snapshot, confirmed by read-back, and only then advances the Provider baseline. This rule is
shared by Aira-sync Aira Cloud and WebDAV; it does not change first-sync preservation, order conflict selection, tombstone
retention, CAS/ETag, App-private pass-through, or the one execution lock. The App shared-bookmark merger already performs
the equivalent final live-parent order filtering.

Aira-sync Popup sync, Background sync, source selection, WebDAV identity replacement, Aira profile reads and membership refreshes, credential-failure mutation, pairing confirmation, and explicit Aira desktop-account disconnect share one cross-context exclusive execution lock whenever they can affect sync identity. Every mutating Popup operation re-reads authoritative identity, source configuration, and conflict state after acquiring the lock. An asynchronous Aira failure may update account state only when the stored UID and device credential still match the identity that initiated the request; a stale response from an older pairing is ignored. Pending Bookmark conflicts carry the complete provider identity and remain actionable only while the authoritative Aira UID or normalized WebDAV endpoint/username/root still matches. Invalid legacy or stale conflict state is cleared under the same lock and cannot block another account or WebDAV identity. A candidate WebDAV identity is synchronized before it replaces the stored configuration; ordinary failure leaves the previous configuration intact, while a detected conflict persists the candidate disabled so the same identity can resolve it. The selected source is persisted last, after the target is enabled. Local stale-folder deletion is child-first so a parent `removeTree` cannot make a later child delete fail after partial application.

Operation logs, outboxes, incremental replay, delete-only/private-only fast paths, and remote-head probes are not part of the current Sync Generation. They must not be restored as a second correctness path, compatibility bridge, or optimization layer. Additional Backup remains write-only and non-authoritative, and legacy server operation endpoints remain outside the current-generation protocol until their later physical isolation.

Amended 2026-07-31: this Bookmark-specific commit path is not reused for Novel Bookshelf. Huawei Space registers the
independent `AiraG2NovelBookshelfCommits` table beside the accepted Bookmark and Personalization tables; its complete
snapshot, CAS/revision, and confirmation state remain owned by the Novel Bookshelf companion module.

Superseding amendment 2026-08-25 after diagnosing slow no-op synchronization and 4,210 accumulated G7 rows: Huawei
Space Bookmark advances to the isolated G8 physical protocol identity `bookmark-g8-blocks-v1` /
`sync-provider-g8-blocks-v1` and re-enable version 8. G8 uses two independently synchronized Record Types in the existing
Container: `AiraG8BookmarkHeads` and `AiraG8BookmarkBlocks`. Both have exactly `rowId`, `accountUid`, `recordKind`,
`logicalId`, `storageEpoch`, `data`, and `updatedAt`; `rowId` is the endpoint dedup key, `storageEpoch` and `updatedAt`
are Integer fields, and all other fields are Strings. G7 and every earlier Bookmark table remain untouched and are not
read, registered, migrated, repaired, copied, dual-written, or deleted.

Each device owns one replaceable G8 Head slot, so Head count follows participating device count rather than commit count.
A read synchronizes the small Heads table first. It synchronizes Blocks only when the observed confirmed Head set cannot
already be completely materialized from local content-addressed Blocks. A write publishes immutable Blocks before making
its Head visible: local Blocks write, fresh Blocks `TIME_FIRST`, fresh Blocks `CLOUD_FIRST`, complete block
materialization proof, replaceable Head write, fresh Heads `TIME_FIRST`, fresh Heads `CLOUD_FIRST`, and exact Head proof.
An incomplete or malformed Head fails closed and cannot suppress an older complete Head, become an empty remote, advance
the Provider baseline, clear pending state, or claim success.

G8 physical format version 1 replaces the sparse 4,096-bucket projection with 64 stable shards. Every shard has separate
`live`, `order`, and `tombstone` lanes; deterministic chunk pages are capped at 10 KiB UTF-8, while Head and index JSON
remain capped at 12 KiB. Canonical `orderPart` records still carry at most 64 child IDs, each index carries at most 128
ordered page references, all objects are exact-canonical and hash-bound, and complete snapshots retain the established
parent-Head, newest-`retainedFrom`, tombstone-history, multi-head, validation, merge, apply, and baseline semantics.

Physical cleanup is a storage concern, not a second correctness rule. Every G8 Head and Block belongs to an explicit
90-day `storageEpoch`. Only after a complete current-epoch Head covers every older logical Head and the epoch has cleared
a seven-day quarantine may maintenance delete older Head rows. Their cloud deletion must be freshly confirmed before
any older-epoch Block is deleted and freshly confirmed. Cleanup runs after an ordinary commit succeeds; every cleanup
error is logged and swallowed, leaving unreachable rows for a later attempt without failing or rolling back Sync. The
logical tombstone frontier remains owned solely by `AiraBookmarkTombstoneLifecycleService`; storage epochs never retire
a tombstone or reinterpret snapshot history.

Amended 2026-09-02 after a local-backup restore was removed by an existing remote tombstone: an explicit user-initiated
Local Backup bookmark import is a restore intent, not an ordinary same-Provider synchronization. For each import, the
App marks imported live folder/item entities with a unique `local-backup-import-*` actor. During the merge for that
restore, a remote same-type tombstone is ignored when the ID has no remote live entity and the durable baseline does not
already contain the same restore actor; the merged live entity and the tombstone-free snapshot are then committed and
confirmed as usual. Once that exact actor is present in the baseline, later ordinary synchronization propagates a remote
tombstone normally. A later explicit import receives a new actor and can therefore restore the same ID again. The legacy
fixed `local-backup-import` actor remains recognized for compatibility, but cannot distinguish repeated imports. This
exception does not alter Provider switching, Additional Backup, ordinary deletion semantics, snapshot validation, CAS,
local-apply verification, or baseline advancement.

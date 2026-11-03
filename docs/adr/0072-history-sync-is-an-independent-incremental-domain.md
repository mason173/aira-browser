---
status: accepted
date: 2026-08-19
---

# History Sync Is an Independent Incremental Domain

Browsing History Sync is an independent Domain shared by the HarmonyOS App and, when Aira Cloud is selected, Aira-sync.
The App uses the active Primary Provider for History: Aira Cloud and Huawei Cloud Space support the Domain, while
WebDAV disables and ignores it. Huawei Cloud Space synchronizes History only between HarmonyOS Aira clients using the
same Huawei account; Aira-sync remains an Aira Cloud client. History does not become
part of the Bookmark snapshot, the four G2 Personalization sections, Novel Bookshelf, the locally selected Bookmark
payload, or Additional Backup. It requires Huawei-account identity in the App and a Desktop Device Session in Aira-sync.
Aira Cloud transport requires active Pro access; Huawei Cloud Space follows the user-owned Provider entitlement and does
not add a separate Pro gate. The ordinary server-readable JSON trust model is accepted; end-to-end encryption and key
distribution are outside this personal-use scope.

The canonical entity is one immutable visit, not one URL. Its ID is `h1:<clientId>:<nativeOrLocalVisitId>`, so repeated
visits to the same URL remain distinct. All clients always merge the account timeline without conflict UI: live visits
form a set union, exact tombstones and deletion ranges win over matching visits, `clearBefore` wins over every older
visit, and deterministic retention then keeps at most 90 days and 10,000 live visits. A later visit receives a new ID
and is not suppressed by deletion of an older visit. Private/ephemeral activity and non-HTTP(S) URLs never enter the
Domain. App, Aira-sync, and server canonicalize every protocol URL with their standards-compatible URL parser before
identity comparison or upload, so equivalent root URLs cannot create false visit-ID collisions.

The first accepted payload owns the immutable visit content. Any later upload with the same visit ID is an idempotent
no-op, even when Chromium reports a different URL, title, timestamp, transition, referrer, device label, source, or a
legacy native-ID representation. The server acknowledges and drains that stale mutation without changing the canonical
row or rolling back newer mutations in the same batch. This is intentionally first-write-wins: the normal sync path has
no collision error or conflict UI, because a stuck mutation is more harmful than dropping a malformed duplicate event.

The Aira Cloud transport is incremental end to end. `POST /sync/v1/history/exchange` accepts a bounded mutation batch and returns
ordered changes after a durable per-client cursor. Mutations are `upsert_visit`, `delete_visit`, `delete_range`, and
`clear_before`; stable mutation IDs make lost-response retries idempotent. The server serializes accepted mutations onto
one monotonically increasing per-account sequence and keeps materialized entities, deletion frontiers, a bounded change
feed, client cursor leases, and mutation receipts. A missing or expired cursor uses
`POST /sync/v1/history/bootstrap`, which pages a head-stable materialization by `(updatedSeq, visitId)` and then resumes
ordinary exchange. No whole-history snapshot, CAS document, oplog replay chain, cross-Domain transaction, dual write,
or user-resolved conflict is introduced. Client state records initialization independently from the numeric cursor, so
an empty account head at cursor zero is still a completed bootstrap. The server reads the current `clearBefore` directly
from its durable account head when bootstrapping that head; change-feed compaction cannot erase the deletion frontier.
The authenticated request `clientId` owns that caller's cursor, mutation receipts, and Desktop Device Session check; it
does not redefine a visit's source identity. During Provider enrollment, a client may relay canonical visits originally
captured by another client in the same account. The server derives `clientId` and `nativeVisitId` from each canonical
`visitId` and preserves them unchanged, so switching Providers moves the merged set without duplicating or rejecting it.

Huawei Cloud Space reuses the existing Huawei distributed-RDB owner and table-scoped cloud task coordinator, but stores
History in its own `AiraH1HistoryRecords` table rather than Bookmark G7. Format 2 stores each client's complete bounded
logical state through two reusable Head slots, 64 stable-key buckets with two reusable slots each, and size-bounded chunk
rows. Every row stays within 12 KiB, a bucket may reference at most 128 ordered chunks, and ordinary changes rewrite only
changed buckets plus the inactive Head slot. A reader selects the newest complete Head per client; an interrupted
publication leaves the previous complete Head materializable. The selected client states are merged by the ordinary
History set-union and deletion rules.

A read starts with a fresh `CLOUD_FIRST`; changed rows are staged and confirmed with a fresh `TIME_FIRST` followed by a
fresh `CLOUD_FIRST`. Success is claimed only from the confirmed mirror. The former one-logical-record-per-row format is
read only for migration: the App first publishes and confirms the compact state, then deletes only the exact legacy rows
observed by that run and confirms their removal. A concurrent legacy row not present in that deletion set survives for a
later merge. Logical apply remains additive: absence from a mirror is never interpreted as deletion, and only an exact
tombstone, delete range, `clearBefore`, or retention frontier may remove a visit. This keeps visits captured during an
in-flight cloud task intact.
The exact rolling 90-day cutoff filters logical rows on every merge; its day-granularity durable frontier is only the
stale-client resurrection barrier and never extends the visible retention window.
Every row is hash-bound and strictly validated before any physical row cleanup; malformed rows and conflicting immutable
visit or delete-range identities inside one freshly materialized Huawei mirror fail closed instead of selecting
replacement content. After that mirror has passed strict normalization, the remote payload remains the first-accepted
canonical visit when the same ID conflicts only with stale locally reconstructed metadata during remote/local merge.
Applying that confirmed remote state replaces the stale local canonical payload so a later Provider switch cannot
recreate the conflict. This boundary does not relax row hash validation or any deletion rule. Local projection apply,
deletion rules, cursors, canonical rows, and frontiers are all account-scoped. Aira `retention_prune` changes advance the same
durable frontier so retention-expired rows cannot return after a later Huawei switch without becoming user tombstones.
The existing `aira_huawei_space_bookmarks_g2` Container must declare an `AiraH1HistoryRecords` Record Type in Huawei
Cloud Space with `rowId` as the endpoint dedup primary key and nullable `accountUid`, `recordKind`, `logicalId`, `data`,
and `updatedAt` fields matching the local TEXT/TEXT/TEXT/TEXT/INTEGER schema. Client-side RDB creation and
`setDistributedTables` registration do not create this cloud-side Record Type.

Huawei History keeps cloud/RDB operations, transactions, retry, and confirmation sequencing on the existing Sync
owners, but delegates pure physical decode, logical merge/equality planning, compact projection construction, and
confirmation computation to low-priority ArkTS TaskPool work. The executor preflights the complete transfer graph with
a conservative 8 MiB budget. A graph above that budget uses the same pure algorithms through a 16-item cooperative
path, including stable merge sorting and bucket construction, so a valid large state neither fails structured clone nor
runs as one unbounded caller-thread turn. Row validation remains inside the codec execution boundary, and TaskPool
infrastructure errors remain distinct from malformed-row failures. This execution policy does not change the H1 format,
merge result, write/confirmation order, or data-loss boundary. HAP compilation validates the concurrency boundary;
true-device frame-time improvement remains a separate non-visual acceptance gate.

The App materializes synchronized visits into its existing History Manager. Aira-sync declares the browser `history`
permission as required, captures locally originated native visits into an IndexedDB ledger/outbox, and presents the same
account projection in its own full History page. Aira-sync never injects remote visits into browser-native history because
the common History API cannot restore visit time, referrer, and transition losslessly. Browser-native removal events
produce exact tombstones for captured local visits; native delete-all and the Aira History clear action advance the
account `clearBefore` frontier. Retention pruning does not masquerade as a user deletion.

Both client projections enforce the same fixed 90-day/10,000-visit boundary before and after remote apply. Pruning is a
local retention-origin removal, deletes any matching pending upsert, and never creates a deletion mutation. This keeps a
client with a looser device-local History preference from retaining records already retired by the server.

App foreground/network/account/local-change/periodic signals and Aira-sync startup/online/history-event/alarm/page signals
only schedule their single History owner. Remote apply never creates an outgoing mutation, a cursor advances only with
the same local transaction that applies its returned changes, and account identity scopes every local state row. Each
run is bound to one account/client identity. Account changes invalidate and drain the old App run before detached remote
projection cleanup, while a new identity never reuses another identity's in-flight promise. A
successful run converges App and Aira-sync to the same canonical records and ordering; presentation may group the same UTC
timestamps differently when device time zones differ.

This ADR supersedes only earlier statements that Aira-sync is globally Bookmark-only. Aira-sync Bookmark Sync remains
unchanged: it still has one locally selected Bookmark source and its complete-snapshot merge/CAS contract. History is
independent in data model and execution, but it follows the same Primary Provider selection as the other Sync content.
The App exposes only the ordinary History content switch and persists no separate History Provider. History is selected
by default on first use. Selecting WebDAV persistently clears that selection, disables the History card, and performs no
History run; switching away from WebDAV does not silently re-enable it.
Cold startup and account changes use one Sync Experience History lifecycle entry: cancel automatic work, resolve the
current account UID, drain the identity-bound run, normalize the account binding, detach other-account remote
projections, refresh the History projection, then resume scheduling. The drain invalidates an active run only when its
account UID differs from the resolved UID, including account clearing; same-account startup waits for the run without
invalidating it. Sync surface loading reuses the same subordinate binding normalizer without restarting an otherwise
valid run. An enabled legacy/default selection whose account UID is empty binds to the current supported Provider
account; an explicit opt-out stays off, and a non-empty mismatched binding is cleared before work resumes.
There is no dual write and no WebDAV History. A Primary Provider switch between Aira Cloud and Huawei Cloud Space first
attempts to synchronize the current History source, merges and confirms the target, and only then persists the Primary Provider.

Amended 2026-09-19: refreshing the old History source is best effort for supported Provider transitions. If it fails,
the transition continues with the durable local History state, including canonical visits, tombstones, delete ranges,
and deletion/retention frontiers. The target must still merge and confirm that state before the Primary Provider changes;
a target failure keeps the old Provider selected. No old-source reset or deletion is performed to implement this fallback,
and records available only on the old remote are not claimed as migrated. A successful operation includes a short notice
that the old source could not be fully refreshed and local records were merged into the target; the old-source failure
does not produce a failure dialog or require a separate confirmation. Ordinary same-Provider synchronization is unchanged.

A user who later enables History on a supported Provider enrolls the preserved local bounded state into that target. Durable account-scoped
canonical visits, exact tombstones, delete ranges, `clearBefore`,
and retention frontier state prevent target switching or a stale client from resurrecting deleted visits.
Returning to an already initialized Aira Cloud target retains its account/client cursor and pulls from that confirmed
position; only an unavailable or expired cursor enters the existing bootstrap recovery. Provider enrollment selects
canonical visits first observed after the last confirmed Aira state, while exact tombstones, delete ranges, and
`clearBefore` are conservatively re-enrolled because their deletion semantics must remain lossless across Providers.
An unchanged Huawei History target uses its initial fresh `CLOUD_FIRST` mirror as the no-op confirmation and does not run
a redundant `TIME_FIRST` plus second `CLOUD_FIRST`; changed rows keep the full upload and confirmation barrier.
When switching from Aira Cloud to Huawei Space, the prior Aira outbox is retained through target confirmation and
Primary Provider persistence; only a
later ordinary Huawei success may drain it. This removes the process-death window where the App could still be configured
for Aira Cloud after its pending Aira mutations had already been discarded.

Amended 2026-08-25: the Huawei remote-store instance owns the fresh mirror produced by the run's initial
`CLOUD_FIRST`. A changed-state write consumes that same mirror instead of downloading it again, then preserves the
required fresh `TIME_FIRST` plus `CLOUD_FIRST` confirmation. A standalone write without a run-owned mirror still performs
its own fresh `CLOUD_FIRST`. The runner reads local bounded state after the cloud pull, so visits created during that pull
are included; later local mutations retain their scheduler revision for a following run. The no-change path performs one
local full-state read and one pre-merge retention prune rather than three reads and two prunes. A second prune remains
required whenever remote materialization actually changed local state. These optimizations do not treat mirror absence
as deletion, relax row validation, clear another account, or change the 90-day/10,000-visit boundary.

Amended 2026-08-26: Huawei History format 2 replaces the unbounded one-row-per-logical-record physical mirror with the
two-slot Head/Bucket/Chunk topology above while retaining the same logical merge, deletion, retention, Provider-switch,
and fresh-confirmation contracts. Existing legacy rows are removed only after the compact projection is confirmed. The
local canonical-visit repair is also a durable per-account one-time gate: it first checks for any synchronized local visit
missing from the canonical table, batches a required backfill, and persists completion only after success. Ordinary App
startup never performs that full scan, and later syncs in the same or a future process do not repeat it. True-device
verification on 2,462 logical records reduced the Huawei physical mirror from about 2,462 rows to 226 rows; an unchanged
full manual run read local canonical state in 42 ms and completed all enabled Domains in 6.778 seconds.

Amended 2026-09-09 after true-device logs showed a 13-second ordinary Huawei History `CLOUD_FIRST` paging more than
a thousand unchanged `AiraH1HistoryRecords` rows: automatic periodic freshness now enqueues the same enabled-domain set
as manual `立即同步`, instead of a History-only full table pull. An ordinary Huawei History run that enrolled no new
local visits and still matches the process-local confirmed state skips the cloud read and reports a successful no-op.
Provider transitions, a new local enrollment, an account change, or the first ordinary run in a process still perform
the existing fresh `CLOUD_FIRST` plus merge/write path. This is not a second History algorithm and does not treat
mirror absence as deletion.

Amended 2026-09-09 after true-device logs showed ordinary `立即同步` alternating between a 30-second
adopted no-op and a 13-second full `AiraH1HistoryRecords` `CLOUD_FIRST` with zero changes: once an
ordinary Huawei History run has a process-local confirmed remote for the same account, later ordinary
runs reuse that remote instead of paging the whole table. Local enrollments still merge against the
cached remote and upload with `TIME_FIRST`; they do not take a second full `CLOUD_FIRST` confirmation
on that cache-hit path. Provider transitions, account changes, and the first ordinary run in a process
keep the existing fresh `CLOUD_FIRST` plus `TIME_FIRST`/`CLOUD_FIRST` write confirmation. This does
not treat mirror absence as deletion.

Amended 2026-09-09 to follow the G8 Head/Blocks physical split: Huawei History format 2 remains the
logical compact snapshot, but ordinary cloud transport uses two independently synchronized Record Types
in `aira_huawei_space_bookmarks_g2`: `AiraH2HistoryHeads` and `AiraH2HistoryBlocks`. Both have
`rowId`, `accountUid`, `recordKind`, `logicalId`, `data`, and `updatedAt`, with `rowId` as the endpoint
dedup key. A read synchronizes Heads first and fetches Blocks only when the observed Heads cannot already
be materialized from local content-addressed buckets/chunks. A write publishes Blocks before making a new
Head visible. The retired `AiraH1HistoryRecords` table remains locally created and unread by the H2
runtime; it is no longer registered for `DISTRIBUTED_CLOUD`. Client `setDistributedTables` still does not
create cloud-side Record Types: the Container must declare both H2 types before H2 can complete. This is
not a second merge algorithm.

Amended 2026-09-09 after true-device logs showed vsync timeouts of 2.4–3.0s during the first
automatic freshness run, with no `HuaweiSpaceCloud` `cloudSync start` lines: the stall is opening
`aira_huawei_space_bookmarks_g2` and `setDistributedTables` on the UI thread before Head/Block
`cloudSync`. Ordinary Huawei transport now opens that store once, registers distributed tables only
on a version bump, and warms the store after content is ready instead of on the 30-second automatic
timer while the user is scrolling. Automatic drain yields a frame before enqueueing so the timer turn
can complete. Head/Block `cloudSync` remains the ordinary read/write path; this is not a second merge
algorithm.


### Confirmed History read budget

An ordinary Huawei run uses the account-scoped durable confirmed Head to gate unchanged reads; it does not keep and
renormalize a second full logical snapshot after success. Local pruning also counts as pending work. With an unchanged
Head, lite publication loads this device's block rows plus all Heads; a full-merge fallback explicitly reloads all device
blocks before decoding. Lite bucket reuse compares the complete canonical desired chunk bytes and referenced hashes,
so it does not reparse stored visit URLs or trust dirty hints. The H2 bytes, deletion rules, and write/confirmation ordering
remain unchanged. This reduces caller work and CPU work without deferring it until scrolling ends.


Lite publication may retain the inactive slot's previous chunk boundary keys as partition hints, so small deletions do
not shift every following record between chunks. Every output payload still comes from the validated desired state;
reuse requires equality with the full canonical chunk bytes at the original timestamp. An identical inactive chunk is
omitted from upserts, while bucket and Head reference its verified hash. Empty/oversized layouts or invalid hints fall
back to compact construction. Only the inactive slot is staged, preserving the current published snapshot until the
Head barrier. This changes partition choice, not the H2 wire format or deletion/confirmation semantics.

For ordinary local edits with a matching durable/fresh Head, a LOW-priority TaskPool job now opens the already
initialized local database, reads the account's canonical state and the captured outbox, and builds the lite
projection there. Database schema/backfill and distributed registration remain with the existing owners and finish
before dispatch. No RdbStore object crosses threads, and a Context is not serializable across TaskPool either, so the
worker resolves its own `application.getApplicationContext()` and uses the platform's `*Sync` RDB query APIs (the SDK
advises running them on a taskpool thread). The TaskPool entry must also be a synchronous `@Concurrent` function: a
returned Promise is rejected with "Can't return Promise in pending state".

The Huawei replica Head/Block tables are `DISTRIBUTED_CLOUD` tables, and a worker connection cannot query them (a
generic SQLite error with both predicates and raw SQL), so the caller still packs this device's replica rows and hands
over a transferable ArrayBuffer. The worker decodes that buffer and combines it with the state it read itself. This
removes the caller's full local read and its ~5 MB state pack from the UI thread while keeping the replica transfer.
The shared `HistorySyncSnapshotReader` owns row mapping for both database owner and worker, so provider enrollment,
deletion records and retention fields do not acquire a second interpretation.

The worker returns changed rows, captured outbox IDs and an ArrayBuffer reserving the exact planned desired state.
That reserve is not decoded on the normal matching-Head confirmation; a changed/missing Head still invokes the
existing full block/projection/desired-state verification. Outbox acknowledgement removes only IDs captured before
the state read. Later edits remain pending, and provider transitions retain all outbox IDs as before. Compute/read
failure falls back to the existing replica repair/full merge; transport failure does not recompute in the same run.

Platform reference: OpenHarmony's official `batch-database-operations-guide.md` and `@ohos.data.relationalStore` advise
performing `queryWithoutRowCountSync` on a taskpool thread, and `@ohos.app.ability.application`'s `getApplicationContext()`
provides context access independent of the ability base class so a worker can obtain the application context itself. The
installed Huawei SDK documents that simultaneous multithreaded opens are unsupported, so this path awaits owner
initialization, then opens and closes the two read handles sequentially.
The worker does not create tables, perform migrations, register distributed tables, or initiate cloud transport.

Amended 2026-11-03 after the desktop-history retention clarification: Aira-sync's desktop History surface combines
browser-native history with other devices' bounded synchronized visits. The browser remains the authority for all of its
own history, including visits older than the latest 10,000. Native paging and search read the browser API directly;
displaying a native visit never enrolls it in the sync ledger or upload queue. This device's synchronized copy is omitted
from the combined surface to avoid duplicates. Pairing, membership, connectivity, and the History Sync switch do not
gate native history visibility. The synchronization projection and pending live uploads retain the latest 10,000 visits;
this count-only sync boundary never truncates the native view or deletes browser-owned data. Remote tombstones, clears,
and retention remain authoritative within the sync domain and never invoke native deletion. An explicit native-row
removal uses the browser's URL-wide deletion API, with that scope stated in its action label; native removal events keep
the existing captured-visit deletion propagation. The native view is not a second persistent history store, a provider,
or a new synchronization algorithm. Bookmark contracts, phone storage, and wire protocols are unchanged.

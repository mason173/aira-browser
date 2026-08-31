---
status: accepted
date: 2026-08-19
---

# History Sync Is an Independent Incremental Domain

Browsing History Sync is an independent Domain shared by the HarmonyOS App and, when Aira Cloud is selected, Airatab.
The App uses the active Primary Provider for History: Aira Cloud and Huawei Cloud Space support the Domain, while
WebDAV disables and ignores it. Huawei Cloud Space synchronizes History only between HarmonyOS Aira clients using the
same Huawei account; Airatab remains an Aira Cloud client. History does not become
part of the Bookmark snapshot, the four G2 Personalization sections, Novel Bookshelf, the locally selected Bookmark
payload, or Additional Backup. It requires Huawei-account identity in the App and a Desktop Device Session in Airatab.
Aira Cloud transport requires active Pro access; Huawei Cloud Space follows the user-owned Provider entitlement and does
not add a separate Pro gate. The ordinary server-readable JSON trust model is accepted; end-to-end encryption and key
distribution are outside this personal-use scope.

The canonical entity is one immutable visit, not one URL. Its ID is `h1:<clientId>:<nativeOrLocalVisitId>`, so repeated
visits to the same URL remain distinct. All clients always merge the account timeline without conflict UI: live visits
form a set union, exact tombstones and deletion ranges win over matching visits, `clearBefore` wins over every older
visit, and deterministic retention then keeps at most 90 days and 10,000 live visits. A later visit receives a new ID
and is not suppressed by deletion of an older visit. Private/ephemeral activity and non-HTTP(S) URLs never enter the
Domain. App, Airatab, and server canonicalize every protocol URL with their standards-compatible URL parser before
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

The App materializes synchronized visits into its existing History Manager. Airatab declares the browser `history`
permission as required, captures locally originated native visits into an IndexedDB ledger/outbox, and presents the same
account projection in its own full History page. Airatab never injects remote visits into browser-native history because
the common History API cannot restore visit time, referrer, and transition losslessly. Browser-native removal events
produce exact tombstones for captured local visits; native delete-all and the Aira History clear action advance the
account `clearBefore` frontier. Retention pruning does not masquerade as a user deletion.

Both client projections enforce the same fixed 90-day/10,000-visit boundary before and after remote apply. Pruning is a
local retention-origin removal, deletes any matching pending upsert, and never creates a deletion mutation. This keeps a
client with a looser device-local History preference from retaining records already retired by the server.

App foreground/network/account/local-change/periodic signals and Airatab startup/online/history-event/alarm/page signals
only schedule their single History owner. Remote apply never creates an outgoing mutation, a cursor advances only with
the same local transaction that applies its returned changes, and account identity scopes every local state row. Each
run is bound to one account/client identity. Account changes invalidate and drain the old App run before detached remote
projection cleanup, while a new identity never reuses another identity's in-flight promise. A
successful run converges App and Airatab to the same canonical records and ordering; presentation may group the same UTC
timestamps differently when device time zones differ.

This ADR supersedes only earlier statements that Airatab is globally Bookmark-only. Airatab Bookmark Sync remains
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
synchronizes the current History source, merges and confirms the target, and only then persists the Primary Provider.
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

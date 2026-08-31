---
status: accepted
supersedes: none
---

# Novel Bookshelf Uses an Independent Personalization Companion

Accepted 2026-07-31 under explicit Sync-change authorization. The existing Personalization Sync Generation continues
to contain exactly four G2 sections: `home_shortcuts`, `core_preferences`, `activity_heatmap`, and `search`.
Novel Bookshelf is a fifth device-local content selection, but it is stored as a separately versioned companion
snapshot. It is never added to the G2 section map, hidden inside another section, or written to the legacy G2 table.

Version 2 of the companion snapshot contains canonical `detailUrl`, title, optional author, cover URL text, `addedAt`,
`updatedAt`, bounded tombstones, and an independent `readingProgress` collection capped at 200 records to match local
checkpoint retention. A progress record is keyed by
the canonical Book detail URL and carries only the source session/chapter identities, canonical chapter URL, chapter
title, character offset, and its own `updatedAt`. Cover bytes, chapter bodies, catalog data/caches, synopsis, category,
latest-chapter metadata, and palette caches remain device-local. A missing cover is hydrated or rendered through the
existing local fallback; it is not a sync failure.

Novel/comic classification is not portable Bookshelf data. Each App classifies a Book locally from its canonical
`detailUrl` through the current signed/bundled Novel Rule Catalog; a URL without a matching comic rule is a novel. This
keeps category presentation independent from provider snapshots and requires no old-record or cloud migration.

The App remains the semantic merge owner. Each provider adapter exposes one complete companion snapshot with its own
revision and provider-identity-scoped active/backup baseline. The App reads, validates, deterministically merges, and
conditionally writes with bounded CAS retry, then applies remote Bookshelf membership atomically while preserving
device-local metadata and palettes. Local absence is not a deletion; explicit removals produce tombstones, and a later
re-add wins by timestamp. Aira Cloud stores the companion in its own database table and routes, WebDAV uses a separate
document, and Huawei Space uses `AiraG2NovelBookshelfCommits` alongside but independently from the existing active
tables.

Reading progress merges independently from Book display metadata: the newest progress `updatedAt` wins and equal clocks
use a deterministic canonical fingerprint. Missing remote progress is never a deletion, removing a Book from the shelf
does not erase the device-local checkpoint, and only progress associated with a live merged Bookshelf Book is published.
The receiving device stores the anchor but does not trust it blindly: the existing reader rebuilds the local chapter
identity and restores only after the current Book, committed chapter, and canonical URL match. Private sessions never
persist a checkpoint and therefore never enter this companion.

Existing active Sync installations default the new selection off until the user enables it. New first activation
defaults it on. Enabling the only selected companion keeps the existing Personalization Domain enabled; disabling the
last selected content pauses that Domain without deleting remote data. Provider switch and Additional Backup operations
prepare the companion after the existing G2 content and commit local Provider configuration only after all selected
content succeeds. A partial remote write remains retryable and is not rolled back through a second journal or cross-Domain
transaction.

The matching Aira Cloud and Huawei record schemas must be deployed before an App release that can publish this
companion. Old clients continue to read and write exactly the four G2 sections and ignore the companion storage.

Amended 2026-08-03 after the six-direction Aira Cloud / Huawei Space / WebDAV matrix: during an established Provider
switch, a live Book wins over an opposing tombstone in either direction. The merged companion therefore retains the
newest valid reading anchor associated with that live Book, while still validating the anchor against the rebuilt local
chapter identity before restore. This conservative rule is limited to Provider switching: ordinary same-Provider
synchronization continues to propagate an explicit Book deletion and removes its portable anchor from the published
snapshot. First activation and Additional Backup keep their existing semantics.

Amended 2026-08-04 after public-entry first-use, failure, account-change, and two-device journeys: every active or
Additional Backup companion write must receive a complete remote read-back confirming the exact revision, Books,
reading progress, and tombstones. Only then may the active path apply Books and portable reading anchors locally and
save its provider-identity lineage; the backup path advances only its independent backup lineage. A stale or incomplete
read-back advances neither local state nor lineage. Lineage identity includes the Huawei UID and companion table or the
normalized WebDAV identity, so changing accounts cannot treat the previous account's revision as confirmation for the
new account.

Amended 2026-08-25: Huawei companion commits use the same confirmed complete-snapshot ancestor compaction as the four
G2 Personalization sections. A successful write keeps every observed Head and the new commit, deletes only observed
non-Head ancestors, then runs fresh upload and cloud-first confirmation. Complete Head snapshots remain independently
readable by old clients even when their parent rows have been removed; concurrent unseen Heads cannot be selected for
deletion, and malformed no-Head graphs skip cleanup. This changes no companion schema, semantic merge, CAS revision,
Provider lineage, or local tombstone behavior. Fresh reads also run this maintenance so an upgraded user does not need a
new Bookshelf edit before existing ancestor history becomes bounded. Cleanup failure is deferred after a valid complete
Head read rather than making that semantic Bookshelf state unavailable.

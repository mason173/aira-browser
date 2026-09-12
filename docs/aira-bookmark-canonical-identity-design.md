# Aira Bookmark Canonical Identity — Design

Status: implemented (B3) on 2026-09-12, hardened the same day; B2 deferred.
Implementation: Aira-sync `planLeafTabIdentityAdoption` / `persistLeafTabIdentityAdoption` plus the
`adoptLocalIdentity` engine hook; HarmonyOS `AiraBookmarkMergeService.planIdentityAdoption` /
`AiraBookmarkSnapshotService.applyBookmarkIdentityAdoption` invoked from `SyncService` before the
first-sync local snapshot. Extension package 0.2.20.
Scope: the Bookmark Sync identity model shared by the HarmonyOS App and Aira-sync, and the
one-time reconciliation a device performs on its first successful sync.
Related contracts: `docs/adr/0049-bookmark-sync-uses-one-snapshot-commit-path.md`,
`docs/adr/0047-sync-vnext-uses-a-per-device-active-provider.md`.

## 0. Follow-up hardening (2026-09-12)

Two defects remained after the initial B3 cut, both found by driving the real flows and confirmed with
failing tests before the fix. See §6.1a and §6.1b.

- **Adoption only paired by path key.** A reinstall after a move, rename, or URL edit produced a
  different root-anchored path, so nothing paired and the merge unioned the tree again (a second copy).
  Desktop now also pairs on the browser node ID embedded in `bkm_local_<deviceId>_<nodeId>`, which
  Chrome preserves across a reinstall.
- **A missing-baseline merge dropped an opposing tombstone.** When a remote — or cloud — snapshot
  carries a tombstone for an id the joining device still holds live, the old union-filter discarded the
  tombstone and the deleted bookmark resurrected on every first sync. A tombstone may now only be
  suppressed by *that snapshot's own* live entities, on both clients.


## 1. Problem

The same bookmark gets a different entity ID on each client, so a device performing its
**first** sync cannot recognize that its local bookmark and the cloud's bookmark are the
same item. Because a first sync has no baseline, it unions both sides and the bookmark is
duplicated.

Observed on a real account:

| Step | folders | items |
| --- | --- | --- |
| Cloud before the failing device's first sync (written by the desktop extension) | 165 | 1802 |
| The same data re-read by the device that then wrote back | 301 | 3306 |
| Cloud after that write | 301 | 3306 |

A device joined an account that already had 1802 bookmarks and turned the account into
3306 without any user action. Every additional device or reinstall adds another copy.

This is not a crash or a network fault. It is the identity model doing what it currently
specifies.

## 2. Why the current design behaves this way

An entity's `id` *is* its identity. Ordering, tombstones, revisions, and local materialization
all key on it. Today two independent ID schemes exist:

- **Aira-sync (desktop extension)**: `bkm_local_<deviceId>_<chromeNodeId>` for new nodes,
  with content-based legacy IDs (`bkm_<slug>_<hash>`) reserved for pre-0.2.14 migration.
  The `deviceId` is a random UUID in extension storage.
- **HarmonyOS App**: `bkm_<slug>_<hash(parentEntityId|title|url|occurrence)>`, or a
  previously persisted `originId` when one exists.

Both carry the ID in the snapshot and persist it locally (`originId` on the App, the mapping
table on the extension). Neither can prove that two entities on different clients are the
same bookmark, and ADR-0049 deliberately forbids guessing: with no baseline, an unmatched
entity is preserved as a separate entity rather than merged, because an incorrect merge
deletes a real user bookmark. Duplication is the accepted failure mode; silent data loss is
not.

The duplication is therefore a **contract-level gap**, not a defect in one merge function.

## 3. Constraints

What each platform can rely on:

| Fact | Desktop extension | HarmonyOS App |
| --- | --- | --- |
| Browser/DB node IDs survive app reinstall | Yes (bookmarks live in the browser profile) | No (uninstall wipes app data) |
| Extension/app storage survives reinstall | No | No |
| `originId` / mapping survives reinstall | No (extension storage wiped) | No |
| Entity IDs are globally unique across installs | No — scoped to one install | No — content-derived |
| A durable side-channel per bookmark exists | No (only URL/title are stored) | Yes (local DB columns) |

Two consequences drive the design:

1. **No client can mint a reinstall-stable ID from local state alone** unless it is derived
   from something the platform preserves. Chrome preserves the *node ID* but not a GUID;
   the App preserves nothing across a reinstall.
2. **Only content and tree position are available at a first join.** Any first-join matching
   is therefore heuristic, and must not be allowed to reduce the number of bookmarks.

## 4. Two facts that remove the need for a breaking cutover

Verified in both clients:

- **A client writes the cloud only when its merged snapshot differs from the remote**
  (`remoteWriteRequired = !sameSnapshotContent(remote, snapshot)` in the App,
  `remoteNeedsWrite = … || !sameSnapshotContent(remoteSnapshot, finalSnapshot)` in the
  extension).
- **Both clients can rewrite their own local identity records** (the App upserts a node's
  `originId`; the extension rewrites its `nodeIdToEntityId` mapping).

Together these mean the duplication can be fixed by changing **only the joining device's
local identity**, leaving the cloud byte-identical. Old clients therefore never observe a
change, and no generation bump or `client_update_required` gate is required.

## 5. Options considered

### B1 — Content-derived IDs everywhere
Drop the device scope and make every client compute the same deterministic ID from
`canonicalRoot + path + title + url + occurrence`.

- Pro: identical content converges with no reconciliation step.
- Con: the ID would change on move/rename unless a carried ID overrides it, so it cannot be
  the sole identity. Two *intentionally* identical bookmarks are distinguishable only by
  `occurrence`, which is fragile under reordering.
- Verdict: usable as a *derived* matching key, unsafe as the identity.

### B2 — Opaque durable IDs, propagated
Mint an opaque, device-independent ID (ULID-style) once at creation and carry it forever.

- Pro: canonical, stable across moves and renames, matches how mature sync systems work.
- Con: does not solve the first join by itself — a client with no baseline still has its own
  freshly minted IDs and cannot match the cloud's.
- Verdict: correct steady-state identity model; a valuable long-term hardening, but **not
  required** to fix the duplication.

### B3 — Local identity adoption on first join
On a device's first successful sync against a non-empty account, map its local entities onto
the cloud's existing IDs **in local state only**, then merge normally.

- Pro: fixes the duplication; the cloud is unchanged; forward-compatible; no cutover.
- Con: heuristic matching; must preserve cardinality and run only when no baseline exists.
- Verdict: the mechanism that closes the gap with the least disruption.

### A note on the naive version (already tried and reverted)
An earlier attempt remapped local IDs onto remote IDs by content path and ran the existing
migration-dedup helper on — and then rewrote — the *merged snapshot*. It was reverted
because it collapsed two intentionally identical bookmarks into one (a real deletion).
The lesson: adoption must rename only, must never reduce live cardinality, and must act on
local state rather than on the shared cloud snapshot.

## 6. Recommendation

Adopt **B3 now** (fixes the defect, no cutover) and treat **B2 as a later, independent
hardening** that may ship on its own schedule because it is not needed to stop duplication.

### 6.1 Local identity adoption (B3), the immediate fix

When a device syncs and has **no valid provider baseline** while the remote is non-empty:

1. Read the remote snapshot.
2. **Prefer the browser node ID.** A stable local ID embeds the node it was minted for
   (`bkm_local_<deviceId>_<nodeId>`). Chrome preserves that node ID across an extension reinstall,
   so when both sides carry a stable local ID the trailing token identifies the same bookmark even
   after a rename, a URL edit, or a move. Content must still agree on what the token cannot prove
   (title, and URL for items) before an ID is adopted.
3. **Fall back to a canonical, root-anchored path key** (`canonicalRootEntityId → title → [url]`) for
   anything step 2 could not settle — e.g. a remote entity still carrying a pre-0.2.14 content ID.
   The four root IDs are already shared across clients (`browser_root_toolbar`, `browser_root_other`,
   `aira_private_root_toolbar`, `aira_private_root_other`), so paths are device-independent.
   Within a group, order both sides deterministically (parent order index, then title, then ID) and
   pair positionally: `local[i] ↔ remote[i]`. An ID already adopted in step 2 is never paired again.
4. For each pair, **adopt the remote ID into local state** (App: rewrite `originId`;
   extension: rewrite the mapping table). The local bookmark node/URL/title never changes.
5. Unpaired local entities keep their current IDs and upload as genuinely new entities.
   Unpaired remote entities are untouched. **Cardinality is never reduced and nothing is
   deleted on either side.**
6. Merge proceeds; because matched entities now share an ID, the merged snapshot equals the
   remote and **no cloud write occurs**.

This makes the cloud's existing IDs the durable anchor: a device that later reinstalls
repeats adoption and converges to the same IDs rather than adding another copy. It is
idempotent.

### 6.1a Why the node-ID pass is safe

The node token is only trusted when the title — and, for items, the URL — already match. A token that
does not correspond to the same bookmark therefore cannot pair, so this pass can never merge two
different bookmarks or drop one; it can only settle a case the path key would have missed (a moved,
renamed, or re-pointed bookmark). When the token is absent or ambiguous, behavior falls back to the
path key, which is what earlier versions did.

### 6.1b Missing-baseline tombstones

On a first join the merge unions both sides. An entity that one side has *deleted* arrives as a
tombstone, not as a live entity. The union must not discard that tombstone just because the other side
still holds the same id live: the ids are equal, so it is the same entity, and dropping the tombstone
resurrects a bookmark the account already deleted. The rule, applied identically on both clients:

- A tombstone may only be suppressed by **the same snapshot's own live entities**, because no snapshot
  may list one id as both live and deleted.
- A tombstone that survives is a deletion instruction: the opposing live entity with that id is removed
  from the merge on both sides. Local tombstones are still carried for ordinary cases, but they can
  never delete a remote live entity, because those ids are filtered before the tombstone set is used.

### 6.2 Guardrails

- Adoption runs **only** when there is no valid baseline. Ordinary merges (baseline present)
  are unchanged and never guess identity.
- Pairing never deletes; a wrong pairing can only swap two entities' IDs, never drop one.
- If the group keys cannot be built (e.g. malformed/empty tree), skip adoption and fall back
  to today's behavior rather than risk a bad rename.
- Tombstones and revisions are carried with the ID they refer to; a rename must not orphan a
  tombstone or resurrect a deleted entity. The history descriptor is checked after adoption.

### 6.3 Optional later hardening (B2)
Assign opaque durable IDs to newly created entities so their identity no longer depends on
content or installation. This can ship independently, is invisible to older clients (IDs are
opaque strings), and can be introduced without a generation bump. It is a stability
improvement, not a prerequisite.

## 7. Rollout and old users

- **No breaking cutover.** The fix ships as a normal client update. The cloud is not
  rewritten, no generation is bumped, and no `client_update_required` gate is added.
- **Old users keep working.** An old client never sees a change, because the cloud snapshot
  is unchanged. A new client performs adoption locally and then behaves exactly as before.
- **Mixed versions are safe.** If an old client writes first, the cloud keeps old-style IDs,
  and a new client adopts those. If a new client writes first, IDs are new-style and an old
  client carries them opaquely.
- **Existing duplicates are not re-created.** Data already duplicated before the fix stays as
  it is; this design does not grow it further and does not silently delete it. Cleaning up
  pre-existing duplicates is a separate, explicitly user-visible action and is out of scope.

## 8. Risks

- **Ambiguous groups.** Two clients each holding an unrelated but identical-looking bookmark
  (same path, title, url) are indistinguishable. Positional pairing keeps both; the residual
  risk is only a wrong *pairing*, never a deletion. Acceptable.
- **Reordering changes pairing.** Pairing uses order position, which can shift. Because
  pairing only renames, a mispairing shows up as two bookmarks swapping IDs, not as loss.
- **Concurrent first sync from two devices.** Both adopt independently against the same
  remote; the cloud is unchanged either way, and each converges locally. The provider's
  existing commit guard still serializes writes.
- **Tombstone continuity.** Covered by the guardrail in 6.2.

## 9. Non-goals

- No content-based silent merging on ordinary merges.
- No oplog, outbox, recovery journal, dual write, or compatibility bridge.
- No generation bump and no `client_update_required` gate for this fix.
- No user-facing de-duplication UI in this design (a possible follow-up for pre-existing
  duplicates).
- No change to WebDAV/Huawei physical transports beyond reusing the shared identity.

## 10. Decision needed

The recommendation is now **forward-compatible**: fix duplication by local identity adoption
(B3), with no cutover and no old-user impact; optionally harden identity later (B2).

- Confirm: may this be implemented as described — adoption in local state only, no cloud
  rewrite, no generation bump?
- Confirm whether B2 (opaque durable IDs) is wanted now or deferred.

No code will be written until this is confirmed.

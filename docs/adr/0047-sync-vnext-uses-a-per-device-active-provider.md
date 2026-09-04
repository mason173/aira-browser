---
status: accepted
supersedes: ADR-0027, ADR-0032, ADR-0034, ADR-0041
---

# Sync vNext Uses a Per-Device Active Provider

Sync vNext starts in one new product-wide Sync Generation and has no account-level Sync Source Topology. Each Aira App device and browser extension selects one local Active Sync Provider; changing it does not switch other clients. Bookmark Sync and Personalization Sync (`主页收藏` plus Common Settings) are independent Domains whose only remote algorithm is read, non-destructive merge, and conditional write. The four Personalization item selections are also device-local: an unselected item is neither applied nor contributed by that device, and its remote section is carried through unchanged so another device can select and maintain it independently. Provider switching first merges every locally enabled Domain into the target, then changes the local Active Sync Provider; old provider and previous-generation data remain untouched. Additional Backup is a device-local write-only copy and never becomes an authority or promotion path. This deliberately accepts temporary cross-device divergence, duplicates, or resurrected old content in exchange for removing legacy migration, topology adoption/version/conflicts, cross-Domain transactions, promotion, compensation, dual writes, bridges, revision anchors, and recovery journals. Blind overwrite of a non-empty current-generation remote remains forbidden.

Provider and backup lineage is identity-scoped. WebDAV identity includes protocol generation, normalized endpoint, username, and root; Huawei identities include the UID and provider-specific store. Replacing an active or backup WebDAV identity must initialize the new target before committing and restore the previous configuration on failure. Replacing a Huawei UID keeps local content and non-Huawei configuration, but detaches Huawei active/backup roles and Huawei runtime state so the new account follows normal first-selection and backup initialization rather than inheriting the old account's lineage.

App Provider identity changes are serialized with manual and automatic Domain runs by the one Sync Experience execution tail. A queued old-identity run completes before mutation begins; work requested during mutation re-reads the committed identity afterward. This is an execution barrier only, not a second lock, journal, transaction log, or cross-Domain transaction.

Amended 2026-07-31: the authorized Novel Bookshelf companion follows the same provider-switch and Additional Backup
ordering as the existing Personalization Domain. Its revision and provider-identity baseline are independent from the
four-section G2 baseline, and the local Active Provider or backup configuration is committed only after every selected
G2 and companion write succeeds.

Amended 2026-08-03 after confirmed Aira Cloud / Huawei Space and three-Provider WebDAV bookmark-loss reproductions:
established Bookmark Provider switching between any two of Aira Cloud, Huawei Space, and WebDAV preserves a live entity
on either side when the opposite side carries a tombstone. A deletion learned while another Provider was active therefore
cannot erase an item that remains live in the target Provider, and a target Provider tombstone cannot erase an item
restored from the current local snapshot during the same transition. When both sides contain no live entity, the
tombstone remains authoritative. After the target commit, local apply, and baseline advance succeed, later ordinary
synchronization against that Active Provider resumes the existing single-sided deletion rule. The Aira Cloud -> Huawei
Space deferred handoff stores only the source Provider alongside the existing durable Bookmark pending marker so process
restart, foreground recovery, network recovery, periodic retry, and manual retry use the same transition merge policy. A
successful confirmation clears both facts; pausing Bookmark Sync preserves both so re-enablement resumes the same
incomplete transition, while starting a fresh Huawei initialization replaces the source with `none`. This is not an
outbox, journal, second merge path, dual write, or Provider promotion, and it does not change Additional Backup,
Personalization, WebDAV transport/CAS, Provider identities or baselines, Huawei G7 storage/confirmation, or Aira-sync
behavior.

Amended 2026-08-03 after a same-account Aira Cloud -> Huawei Space mass-deletion reproduction: transition preservation
includes canonical parent-order membership, not only the live entity array and opposing-tombstone filter. If the
transition protects a live entity, order merge retains that entity in the order supplied by its live side so it remains
root-reachable. Canonical validation rejects missing or non-folder parents, order membership that disagrees with the
entity parent, duplicate membership, unknown order IDs, and any live entity unreachable from the root order. Local apply
must project every validated live entity and a fresh database read must match the merged local-materialization content
before the target baseline advances or the pending transition clears. Ordinary same-Provider synchronization still uses
single-sided deletion propagation; first activation, Additional Backup, and all Provider transports remain unchanged.

Amended 2026-08-03 after the executable three-Domain Provider matrix: Personalization collection values and Novel
Bookshelf Books use the same live-over-opposing-tombstone rule only during an established switch between Aira Cloud,
Huawei Space, and WebDAV. For Personalization, the rule covers Home Shortcut scenarios/items and custom Search Engines;
an unselected item carries the same switch intent while remaining unapplied on that device. Core Preferences keep their
existing deterministic preference merge, and Activity Heatmap keeps its contribution union because neither uses
collection tombstones. For the independent Novel companion, preserving a live Book also retains the newest valid reading
anchor eligible for that Book. Ordinary same-Provider synchronization still propagates explicit deletions. First
activation and Additional Backup remain ordinary operations, so this preservation rule cannot silently turn every
deletion into permanent resurrection.

Amended 2026-08-04 after public-entry first-use, failure, account-change, and two-device journeys: every
Personalization Provider write must receive a complete read-back confirming the written revision and all four sections
before any local section apply, local section-state save, Novel companion handoff, or Provider runtime state
advancement. Active and Additional Backup writes use the same barrier. Runtime and baseline facts remain scoped to the
complete provider identity: Huawei UID plus provider store, or normalized WebDAV endpoint, username, protocol, and root.
Changing an identity cannot reuse the previous account's confirmed revision, cannot write through the previous
account's transport, and leaves every unselected account remote unchanged until that identity is explicitly selected
and synchronized.

Amended 2026-09-04 for the breaking Aira Cloud Bookmark V4 App upgrade: an entitled upgraded App device that already
has Aira Cloud Bookmark Sync enabled must complete one bounded local bootstrap before ordinary Bookmark synchronization
resumes. The bootstrap state and its verified bookmark-only `.aira-backup` recovery point are local upgrade-safety
artifacts, scoped by UID and protocol. They never replay remote operations, write to a Provider, migrate between
Providers, or participate in ordinary merge correctness. A successful bootstrap or an explicit opt-out resolves the
gate; ordinary current-generation synchronization then continues without consulting the recovery artifact. This is the
only approved recovery-state exception and does not add a general Sync recovery journal, outbox, or compatibility path.

---
status: accepted
supersedes: ADR-0085
---

# The Recommended App Is Not A Default Shortcut

Superseded ADR-0085. Accepted 2026-10-20. Aira no longer seeds the recommended app into the default homepage
shortcuts. The recommendation campaign card of ADR-0084 is the only place Aira announces that app, and the default
seed list is content again: three site shortcuts and nothing else. The store page hand-over of ADR-0086 and the bundled
icon rule stay in force, because they answer "this shortcut's page is an app" for a page a shortcut may still hold.

## Decision

The recommended app leaves the seed list; the ways a shortcut can be about an app stay.

- `BrowserDefaultSeedSites` no longer carries a slot for the recommended app. The id that slot held
  (`shortcut-seed-zhihu`) is dropped from the list, so a fresh install seeds the three site shortcuts and no tile for
  the recommended app. Announcing that app is the campaign card's job alone.
- Existing installs are not touched. A device that already seeded the slot keeps its row as ordinary user data — its
  id, its title, its link, and its deletion tombstone. Nothing removes, renames, or rewrites it, and no migration runs.
  This is ADR-0085's own rule read in the other direction: seed ids decide what a **new** install seeds, never what a
  device already holds, so removing an id from the list changes only what a fresh install gets.
- `ShortcutStoreHandoffCatalog` and `BundledShortcutIconResources` stay. A shortcut that holds an AppGallery detail page
  is still about an app, and two kinds of shortcut hold one: a row an older install kept, and a link the user saved by
  hand. Opening either still hands the app over to the store, and either still draws the app's bundled icon.
- The seed file stays pure content. It must not carry the recommended app's name, its store URL, its store id, or its
  shortcut id again: a slot that names the app would be a second announcement next to the campaign card, and it would
  make the shortcuts list depend on a presentation decision.

## Alternatives Considered

- Keep seeding the slot and let the campaign memory gate it. Rejected: the seed list is content with no device state,
  and gating a seed on a presentation record would make what a fresh install seeds depend on whether the user has been
  told something.
- Restore the site shortcut the recommendation replaced. Rejected: this change removes the recommendation slot, not to
  reinstate one particular site. The seed list is the set of sites Aira ships, and nothing here chooses one of them.
- Delete the shortcut from devices that already seeded it. Rejected: the row is user data. Dropping an id from the seed
  list is not authorization to delete rows on a device, and the user may have made that tile their own.
- Remove `ShortcutStoreHandoffCatalog` and the bundled icon rule along with the seed. Rejected: both are still true for
  a hand-saved store link and for the row an older install keeps. Deleting them would take away behaviour those rows
  still have.
- Move the recommendation into some other default surface so the app is still introduced on a fresh install. Rejected:
  ADR-0084 already owns the announcement, and a second surface would be a second telling with its own rule for when it
  is spent.

## Consequences

- `shortcut-seed-zhihu` is in no seed list, so `appendMissingSeedShortcuts` never creates it and
  `shouldRetainShortcutAfterDeletedSyncPurge` no longer protects it from a deleted-sync purge. A device that still holds
  the row keeps it as an ordinary shortcut: an explicit delete tombstones it as usual, and a cloud purge may drop it
  like any other non-seed shortcut.
- A fresh install seeds three shortcuts, and none of them is the recommended app.
- ADR-0085's slot rule, including its "the id must not be renamed" constraint, no longer applies, because there is no
  slot. Its reasoning about seed ids as retention is unchanged wherever a seed id still exists.
- The campaign of ADR-0084 is unaffected: it is announced once per campaign by the card, and never from the shortcuts
  grid.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-app-recommendation-contract.sh`, which pins that
the recommended app is absent from the default seed list while the store hand-over catalog and its bundled icon rule
remain in place.

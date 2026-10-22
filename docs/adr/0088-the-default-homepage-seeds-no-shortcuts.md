---
status: accepted
supersedes: none
---

# The Default Homepage Seeds No Shortcuts

Accepted 2026-10-21. A fresh install ships no default homepage shortcut. The grid opens with its add tile and nothing
else, and the three site shortcuts ADR-0087 left in the seed list (少数派, 掘金, 哔哩哔哩) are gone with it. This
removes the site list, not the recommendation reasoning of ADR-0087: the store hand-over of ADR-0086 and the bundled
icon rule stay in force, because a shortcut a user saved by hand still holds a store page.

## Decision

The seed list is a declaration of what a new install gets, and Aira no longer declares any site.

- `BrowserDefaultSeedSites` declares no site, so a cold start seeds no shortcut. The default shortcut scenario stays, so
  the grid keeps the destination a user adds into.
- Existing installs are not touched. A seed id decides what a new install seeds, never what a device already holds: a
  device seeded earlier keeps its rows as ordinary user data — its own title, its own link, its own deletion tombstone —
  and no migration runs. The user deletes them the way any shortcut is deleted.
- The seed machinery stays: one seed-id builder, `buildMissingSeedShortcuts`, and
  `shouldRetainShortcutAfterDeletedSyncPurge`. An empty list is still the declaration of what a fresh install gets, so
  shipping a default again is a content change with no new mechanism and no version gate.
- The seed file stays pure content. It must not name a site, a URL, or a shortcut id again without a decision to ship
  that default: what a new user's homepage holds is a product choice, not a compiled-in convenience list.
- The store hand-over catalog and the bundled icon rule are untouched. They answer "this shortcut's page is an app",
  which is still true for a hand-saved AppGallery link and for a row an older install keeps.

## Alternatives Considered

- Delete the three shortcut rows from devices that already seeded them. Rejected: those rows are user data the user may
  have renamed, reordered, or replaced, and dropping an id from the seed list is not authorization to delete rows on a
  device. This is ADR-0085's own rule, read the same way ADR-0087 read it.
- Keep one or two of the three sites. Rejected: the decision is that Aira ships no opinion about which sites a new user
  wants. Keeping a subset would be a different product choice rather than a partial version of this one.
- Seed the list with a single generic entry such as a search page or a start page. Rejected: a tile for a page the user
  did not ask for is the same opinion in a smaller box; the address bar and the add tile already cover that need.
- Remove the seed mechanism along with the list. Rejected: the seed-id rules are what make a default safe to ship
  without touching existing devices, and deleting them would make the next seeded site a new feature instead of a
  content change.
- Carry the removed sites in some other default surface, such as a bookmark folder or a suggestions row. Rejected for
  the same reason as the seed list: a default surface must not carry a site Aira picked for the user.

## Consequences

- A fresh install's homepage shows the add tile only; its first shortcut is whatever the user saves.
- A device seeded before this decision keeps its three shortcuts until the user deletes them. Nothing recreates a
  deleted one, and its tombstone no longer needs seed protection, because the id is in no seed list.
- `buildSeedShortcutIds()` returns an empty array, so the retention path is vacuous for now. It stays in place as the
  mechanism any future seed list uses, and `scripts/check-aira-home-shortcut-seed-contract.sh` keeps pinning it.
- ADR-0087's statement that a fresh install seeds three site shortcuts no longer holds; its decision about the
  recommended app is unaffected.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-home-shortcut-seed-contract.sh`, which pins that
the default seed list declares no site while the seed-id retention rules remain.

---
status: accepted
supersedes: none
---

# The Recommended App Takes Over An Existing Default Shortcut Slot

Accepted 2026-10-19. One of the default homepage shortcuts a fresh install seeds opens the recommended app's
AppGallery page and is titled with that app. The app's own icon is drawn on that tile. Existing installs are not
touched: they keep the shortcut they already have, including its title and its link.

## Decision

The seed list is content, and a slot in it may point at a store page instead of a site.

- The slot keeps the id of the shortcut it replaced (`shortcut-seed-zhihu`). That id is what makes "new installs only"
  true without any version gate or migration: `appendMissingSeedShortcuts` only creates seed ids the device does not
  have, and `shouldRetainShortcutAfterDeletedSyncPurge` only protects ids the seed list still declares. An install that
  already seeded that id keeps its row — its own title, its own link, and its own deletion tombstone — while a fresh
  install seeds the slot as the recommendation. Renaming the id would make every existing device treat the slot as a
  brand-new shortcut and add a second tile next to the one it already has.
- The seed declares only a title and a URL. Nothing in the seed record says which app is recommended, and the persisted
  shortcut keeps no store identity beyond the URL it opens, so this stays the same kind of row as every other seed.
- The tile's icon ships with the app. A homepage shortcut normally draws the favicon of the page it opens, which is
  correct for a site and wrong for a store: an AppGallery detail page's favicon is AppGallery's logo, so the tile would
  show the store rather than the app the shortcut is about. `BundledShortcutIconResources` holds the rule that gives
  that app its bundled icon, looked up by the app `ShortcutStoreHandoffCatalog` resolves the store page to, and the
  shortcut tile draws the bundled artwork in place of the favicon.
- The statement of which page is a store page matches the page prefix, not the exact URL, so the same app keeps its
  icon whether or not the link carries share parameters, and it is scoped to one app id so neither the icon nor the
  hand-over of ADR-0086 can leak onto another AppGallery page.
- The bundled artwork is drawn in the same inset and radius a site icon gets, so a recommended tile and a site tile are
  indistinguishable in the grid.

## Alternatives Considered

- Add a second seeded shortcut for the app and leave the site shortcut in place. Rejected: the home grid is a fixed
  row of four, and a fifth tile changes the layout for every new install to say something the user did not ask for.
- Gate the new seed on the app version or on a first-launch marker. Rejected: the seed ids already answer "has this
  device seeded that slot", and a second, parallel answer would have to be kept in sync with the seed list.
- Put a store identity or an icon name on the seed record. Rejected: the shortcut row is user data that gets edited,
  synced, and deleted, and storing which app it recommends would make the row carry an identity the user never chose.
- Materialize the bundled artwork into the shortcut icon file cache and persist that path. Rejected: it writes app
  files during seeding, duplicates an icon that is already in the package, and would keep drawing the old artwork
  after an update replaced it. Resolving the icon at render time keeps the package as the single source of that image.
- Show an AppGallery glyph or the store's own icon. Rejected: the tile is a recommendation, and the store's icon says
  "AppGallery", not the app.

## Consequences

- Existing installs are unaffected in every respect: no new tile, no changed title, no changed link, and a deleted
  shortcut in that slot stays deleted.
- A fresh install shows the recommended app in the slot where the previous shortcut was, with the app's icon. Opening it
  hands that app over to the store rather than loading the store page in a tab; the hand-over itself is ADR-0086.
- Changing which app the slot recommends is a change to `BrowserDefaultSeedSites` plus the bundled icon rule, and both
  are content. The id must not be renamed, which is the one rule a future edit has to keep.
- `scripts/check-aira-app-recommendation-contract.sh` pins the slot id, the title, the store URL, the bundled icon rule
  and its scope, and the tile branch, so a rename or a drifting URL fails the build.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-app-recommendation-contract.sh`, and
`scripts/check-aira-home-shortcut-seed-contract.sh` keeps the seed-id retention rules this decision relies on.

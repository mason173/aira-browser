---
status: accepted
supersedes: none
---

# A Store-Page Shortcut Hands The App Over To The Store

Accepted 2026-10-19. Tapping a homepage shortcut whose link is an app's AppGallery detail page opens that app's page in
the AppGallery app instead of loading the page in a browser tab. This refines the open behaviour of the shortcut slot in
ADR-0085; the slot itself, its id, and its bundled icon are unchanged.

## Decision

A shortcut that holds a store page is about an app, and the store app is where that ends.

- `ShortcutStoreHandoffCatalog` declares which pages are store pages, mapping a page prefix to the app it belongs to.
  The prefix, not the exact URL, is the key, so a link that carries share or channel parameters still hands over; every
  prefix stays scoped to one app id, so a hand-over cannot leak onto another AppGallery page the user saved.
- The declaration is one list. The tile's icon rule and the tile's open both read it, so the artwork and the behaviour
  cannot disagree about which app a page belongs to; the icon rule names the app rather than repeating the URL.
- The open plan gains a `store` kind beside the `web` and `system` kinds. It carries the app id, not a URL, because the
  store service owns the deep link that actually reaches AppGallery, and it owns the https page used as its fallback.
- Only the tile's own open hands over. A context-menu entry that names a tab — new tab, background tab — still opens the
  page it names: that is what the user asked for there, and a store app cannot open in the background. This is also why
  the hand-over is decided in the open policy rather than by trimming those menu entries.
- The shell implements the hand-over as one method it shares with the recommendation card's store action, so both reach
  AppGallery through a single path that installs nothing and never reads whether the app is already installed.
- Nothing is persisted for this. The rule is resolved from the shortcut's URL at open time, so an install that already
  holds that shortcut — seeded before this decision, or saved by hand — changes behaviour without any migration.

## Alternatives Considered

- Keep opening the store page in a tab. Rejected: the tile draws the app's icon because the tile is about the app, and a
  browser tab of the store page is a read-only facsimile the user then has to leave by hand before installing anything.
- Rewrite every `appgallery.huawei.com/app/detail` link to the store scheme. Rejected: that silently changes the meaning
  of every store link the user saved by hand, and it invents behaviour for pages Aira knows nothing about.
- Hand over for every open intent and remove the tab entries from the shortcut's context menu. Rejected: a store app
  cannot open in the background, so the same menu would have to lose two entries it still answers correctly today.
- Put a store identity on the seed record or on the shortcut row. Rejected for the same reason as in ADR-0085: the row is
  user data that gets edited, synced, and deleted, and the URL it already holds is enough to decide this.
- Open the store page in a new tab when the store app cannot answer. Rejected: the store service's https fallback already
  exists for that case and is shared with the recommendation card, and a second fallback would have to be kept in step.

## Consequences

- On any device, tapping the recommended app's homepage tile opens AppGallery at that app's page once the hand-over is
  accepted, and reports the store through the existing toast channel when it is not.
- Existing installs change behaviour without a migration, and a user who edited the tile's title keeps both the edit and
  the hand-over; renaming or deleting the shortcut ends it, as it already did for the page it opened.
- The tile's context menu is untouched: opening in a new tab or in the background still opens the store page, and copying
  the link still copies the page link.
- An app whose store page gains a hand-over rule must also gain an icon rule to keep drawing its own artwork; a store page
  without one keeps drawing the store's favicon, which is correct but says "AppGallery" rather than naming the app.
- `scripts/check-aira-app-recommendation-contract.sh` pins the catalog, the store open plan, the tile-only hand-over, the
  shared shell path, and the icon rule's dependence on the catalog, so a drifting URL or a second store path fails.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-app-recommendation-contract.sh`, and
`scripts/check-aira-home-shortcut-seed-contract.sh` keeps the seed-id retention rules ADR-0085 relies on.

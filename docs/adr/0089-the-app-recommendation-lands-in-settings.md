---
status: accepted
supersedes: ADR-0084
---

# The App Recommendation Lands In Settings

Accepted 2026-10-21. Aira no longer announces a companion app on the homepage. The card of ADR-0084 — its
per-campaign memory, its homepage trigger, its transient surface, and its system-Back branch — is removed. The
catalog and the card itself move to a page the user opens on purpose: **设置 → 应用推荐**, listed directly above
关于Aira. That page lists the apps Aira offers — 声栖 today — and tapping one opens the same product sheet the
announcement used to show.

Aira makes no offer the user did not ask to see. It also does not hide what it offers: the page is a normal settings
page, and the card is the app's own product page, taken from the same layout as Kitapp's app list and detail sheet.

The store hand-over of ADR-0086 and the bundled icon rule are unaffected: they answer "this shortcut's page is an app"
for a link a user saves by hand, which was already their only remaining subject after ADR-0087 dropped the seeded
recommendation tile.

## Decision

The catalog stays; the announcement around it goes.

- **One page.** `SettingsAppRecommendationPage` renders `AppRecommendationContent`'s catalog as settings rows: the
  app icon, its name, and its phrase. It sits behind a settings destination, `应用推荐`, placed directly above
  关于Aira, and it always opens as its own route (`twoPanePresentation: 'routed'`), so the phone shell and the desktop
  shell both show it as a page rather than embedding it as a settings pane.
- **One card.** Tapping a row opens `AppRecommendationOverlay`/`AppRecommendationSheet` on that page, which draws the
  app's product page — icon, phrase, laurels, sample reviews, centred questions — and one action that hands the app's
  AppGallery detail page to the store. The sheet's `dismiss`/`open_market` actions are declared by the sheet's own host
  now, not by a coordinator.
- **No memory, no trigger.** `AppRecommendationCoordinator` and `AppRecommendationRepository` are deleted. Nothing
  records that the page was opened or the card was seen, because nothing is announced: the page shows what is on offer
  every time the user opens it, and the card is a page the user can visit again. The per-campaign preference file
  (`aira_app_recommendation`) is left on a device that already wrote one and is never read again, so no migration runs.
- **No reserved surface.** `app_recommendation` is no longer a transient surface id, no longer a root bottom-panel
  owner, no longer a system-Back branch, no longer a homepage arrival trigger, and no longer initialized by the
  runtime. `scripts/check-aira-app-recommendation-contract.sh` fails if any of them returns.
- **The catalog is content.** Adding an app is an entry in `AppRecommendationContent` plus its artwork and copy; the
  page and the sheet follow. The page owns no app copy, and the sheet owns none either.
- **The settings string is localized like every other directory entry.** `应用推荐` is a settings destination, so it
  carries a `SettingsCatalogCopy` case, an English search index entry, and the same `app.string.settings_app_recommendation`
  key in all four locales.
- **The store hand-over stays narrow.** The sheet hands one app id to AppGallery through the shared store service, and
  the shortcut hand-over of ADR-0086 keeps its own single-app scope. Neither installs anything or reads whether the
  app is already installed.

## Alternatives Considered

- Keep the announcement and add the page. Rejected: the two tellings would need one shared memory to avoid telling the
  same user twice, and the memory is the part that makes the homepage arrival a gate. Removing the announcement is what
  lets the page be a plain catalog with no state.
- Put the page inside 关于Aira as a group of rows. Rejected: it is not information about Aira. It is a list of apps, and
  a top-level settings row above 关于Aira is where a user looks for it.
- Keep the card as a bottom sheet on the homepage but open it only from a toolbar entry. Rejected: the homepage was the
  problem, not only the timing; the settings directory is the surface a user visits deliberately.
- Reuse the version-update card as a second announcement slot. Rejected: the card is an app's product page, not a
  release note, and the two would have to share the promotional lane the update notice already owns.
- Delete the catalog along with the coordinator and keep only a store link. Rejected: the card is the app's own product
  page and is the whole reason the apps are listed; a bare store link would drop the reviews and questions that make the
  page worth opening.

## Consequences

- A fresh install and every existing device present no app card on the homepage. ADR-0088 already removed the seeded
  tile, so the offered app appears only where the user looked for it.
- A device that already holds the recommendation memory file keeps it, unread and unmigrated.
- `scripts/check-aira-app-recommendation-contract.sh` pins the settings entry, the route, the page, the single catalog,
  the localized directory string, and the absence of a coordinator, memory, reserved surface id, Back branch, homepage
  trigger, and runtime initialization. `scripts/check-aira-shortcut-store-handoff-contract.sh` keeps the store
  hand-over and the bundled icon rule of ADR-0086.
- 应用推荐 is searchable like any other settings destination, in Chinese and in English, because it is a catalog
  target with a copy-table case and an English index entry.

## Verification

Proportional evidence is a Community build plus `scripts/check-aira-app-recommendation-contract.sh`, which fails closed
on every clause above, including the two cases this ADR exists for: the page opens the catalog on demand, and no
arrival opens it.

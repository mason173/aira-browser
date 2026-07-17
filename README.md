# AiraTab

AiraTab is the desktop browser extension paired with the Aira app. It has two responsibilities:

- Synchronize browser bookmarks through one selected source: Aira Cloud or user-provided WebDAV.
- Receive a webpage pushed from the phone and immediately open it in a new active desktop tab.

The extension does not replace the new-tab page and does not synchronize personalization settings.

## Development

```bash
npm install
npm run dev
```

## Build

```bash
npm run typecheck
npm run build
```

The production extension output is written to `build/`. Load that folder from Chrome or Edge developer mode.

## Data And Sync

- One bookmark sync source is active at a time. Inactive sources are not read or written in the background.
- Aira Cloud requires a valid Desktop Device Session and Aira Pro.
- WebDAV is available without an Aira Account Session. WebDAV credentials stay in extension storage.
- Selecting a source enables automatic bookmark sync. There is no separate automatic-sync switch or custom interval.
- First sync and ordinary differences merge automatically. Only a real two-sided conflict asks whether the computer or the current sync source wins.
- Each extension installation chooses its own active provider. The choice is local and does not change the phone app or another extension installation.
- Sync generation `g2` uses `/sync/v2/bookmarks` for Aira Cloud and `aira/g2/bookmarks` for WebDAV. Previous-generation remote data and transport state are not read or migrated.
- Phone Page Push remains independent from bookmark sync. It uses the Desktop Device Session for silent background polling, per-device delivery, open-tab handling, and acknowledgement.
- Do not commit private keys, account credentials, WebDAV passwords, generated builds, release zips, or local test data.

## Structure

- `src/popup`: popup UI and popup-local i18n resources.
- `src/features/sync/bookmarks/BookmarkSyncModule.ts`: the shared bookmark-sync construction seam and deep sync interface used by popup and background flows.
- `src/features/sync/bookmarks/BookmarkSyncPopupRuntime.ts`: popup source selection, manual sync, conflict resolution, eligibility, status persistence, and summary ownership.
- `src/features/sync/bookmarks/BookmarkBackgroundSyncRuntime.ts`: automatic-sync configuration, retry/alarm policy, change probing, and browser-bookmark event ownership.
- `src/sync/leaftab`: lossless Aira bookmark protocol, merge engine, provider adapters, and browser bookmark snapshot logic.
- `src/background.ts`: extension platform/event wiring, WebDAV request proxying, and the independent Phone Page Push runtime.
- `public`: extension manifest, service worker, locales, and icons.
- `scripts`: release build and packaging helpers.

## License

Private and unpublished. Package metadata uses `UNLICENSED`.

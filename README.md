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
- Aira Cloud requires a valid Desktop Device Session, Aira Pro, and permission from the App-owned sync topology.
- WebDAV is available without an Aira Account Session. WebDAV credentials stay in extension storage.
- Selecting a source enables automatic bookmark sync. There is no separate automatic-sync switch or custom interval.
- First sync and ordinary differences merge automatically. Only a real two-sided conflict asks whether the computer or the current sync source wins.
- Aira Cloud follows the Primary source initialized by the Aira app. User-configured WebDAV is standalone and may initialize its own bookmark-sync location.
- Phone Page Push remains independent from bookmark sync. It uses the Desktop Device Session for silent background polling, per-device delivery, open-tab handling, and acknowledgement.
- Do not commit private keys, account credentials, WebDAV passwords, generated builds, release zips, or local test data.

## Structure

- `src/popup`: popup UI and popup-local i18n resources.
- `src/features/sync/bookmarks/BookmarkSyncModule.ts`: the small narrative interface for bookmark view state, source choice, synchronization, and conflict resolution.
- `src/sync/leaftab`: lossless Aira bookmark protocol, merge engine, provider adapters, and browser bookmark snapshot logic.
- `src/background.ts`: single-source automatic bookmark sync and the Phone Page Push background runtime.
- `public`: extension manifest, service worker, locales, and icons.
- `scripts`: release build and packaging helpers.

## License

Private and unpublished. Package metadata uses `UNLICENSED`.

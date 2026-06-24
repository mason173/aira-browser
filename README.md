# Airatab

Airatab is a private Chromium extension for WebDAV bookmark sync.

The extension no longer replaces the browser new tab page. The only user-facing entry is the browser extension action popup, where users can configure WebDAV, enable or disable sync, and trigger bookmark sync manually.

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

- WebDAV connection settings stay in browser extension storage.
- Sync currently targets browser bookmarks only.
- The background service worker only proxies WebDAV requests.
- Do not commit private keys, account credentials, WebDAV passwords, generated builds, release zips, or local test data.

## Structure

- `src/popup`: popup UI and popup-local i18n resources.
- `src/sync`: WebDAV bookmark sync engine and browser bookmark snapshot logic.
- `src/components`: small UI surface used by the popup.
- `public`: extension manifest, service worker, locales, and icons.
- `scripts`: release build and packaging helpers.

## License

Private and unpublished. Package metadata uses `UNLICENSED`.

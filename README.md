# Airatab

Airatab is a private Chromium new-tab extension focused on a clean shortcut grid, keyboard-first search, browser bookmark search, wallpapers, and WebDAV bookmark sync.

This repository is the new private line after the Lite refactor. It no longer carries the old public release docs, Firefox branch, website deployment files, server account sync, role presets, weather, or changelog material.

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

- Local extension data stays in browser storage.
- Bookmark import/export targets standard browser bookmark formats.
- Sync is WebDAV bookmark sync only.
- Do not commit `.env`, private keys, account credentials, WebDAV passwords, generated builds, release zips, or local test data.

## Structure

- `src/`: extension UI and runtime logic.
- `packages/`: in-repo shortcut grid engine packages.
- `public/`: extension static files, manifest templates, icons, and the shortcut icon library.
- `scripts/`: build, verification, icon generation, and local development helpers.

## License

Private and unpublished. Package metadata uses `UNLICENSED`.

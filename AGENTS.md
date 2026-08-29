# Airatab Agent Rules

These rules are mandatory for Codex or any other coding agent working in this repository.

## Frozen Sync Architecture Contract — Explicit User Authorization Required

- Airatab Sync is sealed as of July 18, 2026. It synchronizes Bookmark only. Treat its Popup, Background runtime,
  source switching, WebDAV configuration, Aira pairing/disconnect, browser storage state, Bookmark snapshot/baseline,
  conflict handling, and cross-context execution lock as frozen product infrastructure.
- Do not edit, refactor, optimize, simplify, clean up, migrate, restore, replace, or delete Sync implementation unless
  the user explicitly authorizes changing Airatab Sync in the current task. Authorization from an earlier task or
  conversation does not carry forward. General cleanup, architecture review, release preparation, unrelated bug fixes,
  typecheck/build failures, or requests to improve reliability are not authorization.
- Protected areas include, but are not limited to, `src/sync/**`, `src/features/sync/**`, Sync behavior in `src/popup.tsx`,
  `src/popup/**`, `src/background.ts`, `src/components/sync/**`, `src/utils/webdavConfig.ts`, WebDAV types/providers, and
  any storage key, identity, source, lock, conflict, credential, pairing, or provider-runtime code that affects Sync.
  Do not evade the boundary by moving Sync behavior into another directory or generic utility.
- Read-only diagnosis is allowed without change authorization. If investigation indicates a Sync edit may be required,
  stop after diagnosis, identify the exact protected files and invariant at risk, and ask the user for explicit
  authorization before editing.
- Before any authorized Sync change, completely read this file, `/Users/mason/Desktop/AiraBrowser/AGENTS.md`, and the App
  ADR-0047/0048/0049 contracts. State the exact approved scope and target files before editing. Keep the existing one
  execution lock from `src/sync/leaftab/executionLock.ts`; after acquiring it, re-read authoritative extension storage
  identity, source, WebDAV configuration, and pending conflict state.
- Extension storage remains authoritative; `localStorage` is only a best-effort UI cache. A normal WebDAV candidate
  failure must preserve the previous configuration; a conflict may preserve a disabled candidate; a successful switch
  enables the target before committing the selected source last. The WebDAV save page must keep its existing immediate
  return-to-home/background-sync interaction unless the user explicitly authorizes a UI change.
- Preserve complete Bookmark snapshots, provider-identity baselines, CAS/ETag conditions, the verified WebDAV
  `If-None-Match` or `MOVE Overwrite: F` first-publication behavior, and baseline advancement only after confirmed remote
  commit plus successful local apply. Do not add oplogs, outboxes, recovery journals, dual writes, App Personalization,
  account-level provider topology, cross-Domain transactions, or legacy data bridges.
- After an authorized change, run at least `npm run typecheck` and `npm run build:final`, plus the relevant protocol or
  manual flow checks. Distinguish those results from user-operated real-browser multi-device acceptance.

## Workspace Safety

- Preserve unrelated working-tree changes. Do not create or switch branches/worktrees unless the user explicitly asks.
- Never commit credentials, tokens, production environment files, browser profile data, `node_modules`, signing material,
  or remote data snapshots.

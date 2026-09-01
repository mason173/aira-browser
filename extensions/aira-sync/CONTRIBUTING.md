# Contributing

Aira-sync keeps Community and Official distributions in one source tree. Put distribution-specific behavior behind
`src/config/AiratabDistribution.ts`; the legacy internal filename is retained to avoid storage and Sync migration churn.
Do not create edition branches or copied pages.

## Development

```bash
npm ci
npm run typecheck
npm test
npm run build:community
```

Official builds require private route inputs as documented in [README.md](README.md). The Official local-install package
must be created with `npm run pack:local-official`; that command is the single source of truth for restoring its legacy
fixed Chromium identity. Never commit production routes, tokens, browser profiles, Personal Server data, WebDAV
credentials, or generated build output.

## Pull Requests

- Keep changes focused and explain user-visible behavior, privacy impact, and data-loss/concurrency risk.
- Preserve the single active Bookmark Provider, one cross-context execution lock, complete snapshots, CAS/ETag, and
  provider-identity baselines.
- Keep extension storage authoritative; local storage is only a best-effort UI cache.
- Keep Personal Server single-owner and pairing-based. Do not add accounts, passwords, users, roles, organizations,
  membership, billing, referrals, or Huawei identity.
- Run typecheck, tests, and both applicable distribution builds before requesting review.

Personal Server protocol changes belong in [`services/personal-server`](../../services/personal-server/README.md) in the
same monorepo and must remain explicitly versioned. Update every affected client and protocol document in one pull request.

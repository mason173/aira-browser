# Contributing

Aira Browser, Aira-sync, and Personal Server are maintained in one public monorepo. Keep cross-component protocol
changes in one pull request so compatibility, documentation, and all affected clients can be reviewed together.

This repository is the only client source tree. Community is the committed default. Official packages are built from the
same commit with private AGConnect, signing, and hosted-API inputs; those inputs stay outside Git.

## Component Checks

HarmonyOS Community:

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

Aira-sync:

```bash
cd extensions/aira-sync
npm ci
npm run typecheck
npm test
npm run build:community
```

Personal Server:

```bash
cd services/personal-server
npm ci
npm run check
```

The installable HarmonyOS Community build needs a local signing profile for `org.aira.browser`. Signing files,
AGConnect data, production routes, device credentials, databases, and browser profiles must never be committed.

## Pull Requests

- Keep changes focused and explain user-visible behavior, privacy impact, data-loss risk, and Provider compatibility.
- Prefer existing owners and shared components over distribution-specific copies.
- Update discovery, protocol documentation, and every affected component when wire semantics change.
- Preserve local user data by default and isolate self-host credentials by Personal Server instance identity.
- Do not add registration, passwords, organizations, roles, billing, membership, referral, or Huawei identity to Personal
  Server flows.
- Run the checks for every touched component; root workflows use path filters to enforce the same boundary in CI.

Aira's production backend, Admin, deployment configuration, signing inputs, and operations remain private and are not
part of this monorepo.

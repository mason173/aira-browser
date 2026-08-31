# Contributing

Aira Browser is maintained as one HarmonyOS source tree with Community and Official build distributions. Keep changes
distribution-neutral unless they belong behind the existing capability owner.

## Development Setup

Install DevEco Studio and the HarmonyOS SDK version documented in [AiraBrowser/README.md](AiraBrowser/README.md), then:

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

The Community build needs a local signing profile for `org.aira.browser.community`. Signing files and AGConnect data are
machine-local inputs and must never be committed.

## Pull Requests

- Keep changes focused and explain user-visible behavior, privacy impact, data-loss risk, and Provider compatibility.
- Prefer existing owners and shared components over distribution-specific copies.
- Update the affected contract script or documentation when protocol or build behavior changes.
- Preserve local user data by default and keep self-host credentials isolated by Personal Server instance identity.
- Do not add account registration, passwords, organizations, roles, billing, membership, referral, or Huawei identity to
  Personal Server flows.

Personal Server changes belong in [mason173/aira-server](https://github.com/mason173/aira-server). Aira's production
backend, Admin, deployment configuration, and operations are not part of this repository.

# Open-Source Distribution Boundary

This document describes the release boundary for the public components in the Aira monorepo. The HarmonyOS client and
Aira-sync each build Official and Community distributions from the same component source and commit. They are not
long-lived forks. Personal Server is a distribution-neutral, single-owner self-hosted service.

## Repository Layout

- `AiraBrowser/`, `scripts/`, and `resources/` contain the HarmonyOS client and its build inputs.
- `extensions/aira-sync/` contains the desktop browser extension.
- `services/personal-server/` contains the deployable self-hosted server.
- Aira's production backend, Admin, operations, and private build credentials are not in this monorepo.

## Capability Matrix

| Capability | Community | Official | Notes |
| --- | --- | --- | --- |
| Local browsing, tabs, offline pages, userscripts, ad blocking, themes, and local search | Available | Available | These capabilities do not require an Aira membership or hosted execution service. |
| User-provided WebDAV | Available | Available | Credentials and endpoint remain device-local and are chosen by the user. |
| Aira Cloud bookmark, personalization, and history sync | Unavailable | Available | Official service and membership entitlement are server-authorized. |
| Huawei Account sign-in | Unavailable | Available | Official App/Client identity, approval, and signing are private inputs. |
| Huawei Cloud Space sync | Unavailable | Available | The official Huawei project and cloud container are not bundled in Community. |
| Huawei IAP and purchase verification | Unavailable | Available | IAP receipts are sent only to the Official Aira control plane. |
| Personal Server sync, Page Push, and Cross-device Tabs | Available | Available | Single-owner, paired-device server shared by HarmonyOS Aira and Aira-sync; no Huawei identity, membership, or billing. |
| Automatic crash upload and telemetry | Disabled | Disabled | The client does not upload crash reports to Aira infrastructure. |

Community code may retain shared Huawei integration implementation where licensing permits, but the Community build does
not inherit Aira's Huawei project, approvals, certificates, cloud container, or production identifiers. A builder's own
Huawei project requires separate configuration, signing, and approval work; it is not enabled by the current Community
defaults. Hosted Aira API adapters compile against a non-routable placeholder in Community; the Official API base URL is
injected only while an Official artifact is being built.

## Building

The source tree defaults to Community identity. A Community build requires a HarmonyOS signing profile for
`org.aira.browser`:

```bash
AIRA_DISTRIBUTION=community SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

Public CI can compile and audit an unsigned, non-installable Community HAP without signing material:

```bash
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

Unsigned mode is intentionally restricted to the default Community HAP and requires `SKIP_INSTALL=1`. Installation and
distribution still require a signing profile owned by the builder.

The GitHub workflow always runs public static guards. Native HarmonyOS jobs require a self-hosted runner with the
`self-hosted`, `macOS`, and `harmonyos` labels and repository variable `AIRA_ENABLE_HARMONYOS_CLIENT_CI=true`. The signed
Official job additionally requires `AIRA_ENABLE_SIGNED_CLIENT_CI=true` and the documented private secrets.

The tracked `AiraBrowser/build-profile.json5` is a public template and intentionally has no signing material. Supply a
matching local/external profile through `AIRA_BUILD_PROFILE`, `AiraBrowser/build-profile.local.json5`, or a matching
DevEco profile under `~/.ohos/config`. Do not commit `.p12`, `.cer`, `.p7b`, `material/`, encrypted passwords, or local
profile files.

An Official build additionally requires private AGConnect input and an Official signing profile for `com.aira.browser`:

```bash
AIRA_DISTRIBUTION=official SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

Provide AGConnect through `AIRA_AGCONNECT_CONFIG` or the ignored
`AiraBrowser/agconnect-services.local.json`. The build script injects the private configuration only for the build and
restores the source tree on exit.

`AIRA_DISTRIBUTION` is independent from `AIRA_BUILD_VARIANT=default|release`. The same commit should be used for both
distributions; only the capability owner, package identity, private configuration, and signing inputs differ.

## Privacy And Service Boundaries

- Huawei Account authentication is an Official Aira identity and is not a Personal Server login.
- Personal Server uses one instance owner and paired device credentials. It does not contain registration,
  password login, users, organizations, roles, invitations, membership, billing, or Huawei-token authentication.
- Personal Server is the Community transport for Bookmark, History, Personalization, Novel Bookshelf, Page Push, and
  Cross-device Tabs. Page Push and tab presence are short-lived services, not Bookmark or History payloads.
- A user-selected WebDAV endpoint is separate from Aira Cloud and remains a free client capability.
- Aira's production backend and Admin remain in a separate private repository. They are not the public Personal Server.
- Referral and invite growth flows are retired. Existing grants remain valid until their recorded expiration or permanent
  term, while old compatibility endpoints remain private and rollout-gated.

## Publication Checklist

Before making the monorepo public, all of the following must be true:

1. A clean Community checkout builds with only documented public inputs.
2. Official and Community artifacts are built from the same commit and have separate matching signing profiles.
3. Community packages contain no Aira production identifiers, AGConnect configuration, Huawei-only runtime access, IAP
   credentials, or hosted Aira Cloud requests.
4. Third-party licenses, notices, contribution rules, security reporting, and trademark policy are present.
5. Production backend/Admin history and credentials have been separated from the public repository history.
6. The Personal Server protocol, deployment package, backup/restore, upgrade, pairing, and revocation behavior pass the
   documented acceptance matrix.
7. The project owner's Icons8 license has been confirmed for the intended public source and binary distribution, or the
   commercially licensed assets have been replaced/removed.

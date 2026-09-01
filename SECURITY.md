# Security Policy

## Supported Versions

Until the first stable Community release, security fixes are made only on the latest `main` revision.

## Reporting A Vulnerability

Use the repository's private GitHub Security Advisory form. Do not open a public issue containing an exploit, Personal
Server URL tied to a private person, pairing/setup code, device token, WebDAV credential, browser history, database,
backup, browser profile, or Official service configuration.

Include the affected commit, distribution, Provider, browser version, reproduction steps, and impact. Replace every
credential and user identifier with a non-working placeholder.

## Security Boundaries

- Community contains no default Aira production endpoint or Official desktop-account capability.
- Personal Server uses revocable per-device bearer credentials and never receives Huawei or membership tokens.
- WebDAV credentials are sent only to the endpoint selected by the user.
- Private/incognito tabs and non-HTTP(S) URLs are excluded from Cross-device Tabs.
- Personal Server does not provide end-to-end encryption; its administrator can read synchronized data.

# Security Policy

## Supported Versions

Until the first stable Community release, security fixes are made only on the latest `main` revision.

## Reporting A Vulnerability

Use the repository's private GitHub Security Advisory form. Do not open a public issue containing an exploit, bearer
token, Personal Server URL tied to a private person, setup code, device credential, WebDAV credential, database, backup,
browsing history, signing material, or AGConnect configuration.

Include the affected commit, distribution, Provider, reproduction steps, and impact. Replace every credential and user
identifier with a non-working placeholder.

## Security Boundaries

- Community has no Aira production identity or AGConnect configuration.
- Personal Server uses revocable per-device credentials and never receives Huawei or IAP tokens.
- WebDAV credentials remain device-local and are sent only to the endpoint selected by the user.
- Automatic crash collection and upload are disabled in both distributions.
- Personal Server does not provide end-to-end encryption; its host administrator can read synchronized data.

# Security Policy

## Supported Versions

Until the first stable release, security fixes are made only on the latest `main` revision. Self-hosters should keep a tested backup and upgrade promptly.

## Reporting A Vulnerability

Use the repository's private GitHub Security Advisory form. Do not open a public issue containing an exploit, bearer token, setup code, server URL tied to a private person, database, backup, or browser history.

Include the affected commit, deployment shape, reproduction steps, and impact. Replace every credential with a non-working placeholder.

## Security Model

- one owner, with multiple explicitly paired devices;
- no public registration, user directory, password authentication, roles, or organizations;
- high-entropy one-use pairing codes and revocable per-device bearer credentials;
- server-side token hashes only;
- TLS required outside a trusted local network;
- a private persistent data directory and encrypted off-host backups;
- no Huawei token, Aira account token, membership state, IAP receipt, or billing data.

The server does not provide end-to-end encryption. A host administrator, a process with access to the data directory, or an attacker controlling the TLS endpoint can read synchronized data. Device compromise also exposes that device's bearer credential until it is rotated or revoked.

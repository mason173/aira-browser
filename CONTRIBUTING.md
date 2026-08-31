# Contributing

Keep the server single-owner and paired-device only. Changes that introduce registration, passwords, users, organizations, roles, membership, billing, Huawei identity, or an Aira-operated control plane are out of scope.

Before submitting a change:

```bash
npm ci
npm run check
```

Protocol changes must update discovery or the affected Domain version when semantics are not additive. Database changes use a new ordered migration and must preserve backup/restore and upgrade behavior.

Never commit databases, backups, setup codes, device tokens, production environment files, logs containing credentials, or private user data. Keep pull requests focused and explain data-loss, concurrency, and compatibility risks.

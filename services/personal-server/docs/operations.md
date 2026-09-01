# Operations

## Health

```bash
curl --fail --silent https://sync.example.com/health
curl --fail --silent https://sync.example.com/.well-known/aira
```

The health endpoint intentionally exposes no device or sync content.

## Backup

The backup command uses SQLite's online backup interface and can run while the service is active:

```bash
docker compose exec aira-server npm run backup -- /data/aira-personal-server.backup
docker compose cp aira-server:/data/aira-personal-server.backup ./aira-personal-server.backup
```

Protect backups like browser history. Store at least one encrypted copy outside the server and periodically verify it with SQLite integrity checking or a disposable restore.

## Restore

Stop the server before restoring. The restore script validates SQLite integrity and required tables, retains the previous database beside the restored one, and never deletes that rollback copy automatically.

```bash
docker compose stop aira-server
mkdir -p restore
cp /secure/path/aira-personal-server.backup restore/
docker compose run --rm -v "$PWD/restore:/restore:ro" \
  aira-server npm run restore -- /restore/aira-personal-server.backup
docker compose up -d aira-server
curl --fail --silent https://sync.example.com/health
```

Confirm the returned `instanceId` matches the expected server before clients resume syncing.

## Upgrade

1. Create and export a verified backup.
2. Record the current commit or image digest.
3. Fetch the intended release.
4. Rebuild and restart the service.
5. Check `/health`, `/.well-known/aira`, one authenticated device list, and each changed Domain.

```bash
docker compose exec aira-server npm run backup -- /data/pre-upgrade.backup
git pull --ff-only
docker compose build --pull
docker compose up -d
docker compose logs --tail=100 aira-server
```

Migrations run automatically in a transaction and are recorded in `schema_migrations`. Never edit an already released migration; add the next ordered SQL file.

## Rollback

If the application fails after an upgrade, stop it, restore the prior code or image, and restore the pre-upgrade database with the restore procedure. Do not point an older binary at a database after a new migration unless that release explicitly documents downgrade compatibility.

## Reverse Proxy Checklist

- TLS uses a publicly trusted certificate and redirects HTTP to HTTPS.
- Only the reverse proxy can reach port `8787`.
- The request-body limit is at least 12 MiB.
- The `Authorization` header reaches the upstream unchanged.
- Proxy and application logs do not record request bodies or bearer tokens.
- Backups, `/data/setup-code`, and the SQLite files are never served as static files.

# Aira Contributor Rules

- Do all work directly on the `main` branch. Never create a new branch or a worktree for a task, and never ask whether
  to branch first; commit to `main` when the user asks for a commit.
- This monorepo is the public open-source source of truth. Maintain only this tree.
- This monorepo contains the HarmonyOS client at `AiraBrowser/`, Aira-sync at `extensions/aira-sync/`, and Personal
  Server at `services/personal-server/`.
- Apply the nearest nested `AGENTS.md` in addition to these root rules. Aira-sync's frozen Sync contract remains in
  `extensions/aira-sync/AGENTS.md`.
- Treat Huawei official documentation as the source of truth for platform APIs, lifecycle, permissions, storage,
  networking, and Web components.
- A HarmonyOS node can keep only one `bindSheet`. A second `bindSheet` on the same node replaces the first, and the
  replaced sheet never opens. Do not chain two `bindSheet` calls on one node. A `bindSheet` on a custom component also
  occupies that component and replaces a `bindSheet` on its root. When one screen needs more than one sheet, bind each
  sheet to its own node, or keep a single `bindSheet` and switch its builder.
- Keep Community and Official as build distributions of one source tree. Do not create edition branches, client forks, or
  duplicate pages to carry distribution differences.
- The committed source tree stays Community. Leave `AIRA_DISTRIBUTION = 'community'`, bundle `org.aira.browser`, hosted
  API `https://community.invalid`, and empty Huawei `app_id` / `client_id` metadata in Git.
- Community must remain usable without Aira production credentials. Huawei Account, Huawei Cloud Space, Huawei IAP, and
  Aira Cloud are Official capabilities; WebDAV and Personal Server are user-owned providers.
- Personal Server is single-owner and paired-device only. It has no registration, password accounts, organizations,
  roles, membership, billing, referral, or Huawei-token authentication.
- Every established Bookmark Provider switch between any two of Aira Cloud, Huawei Space, and WebDAV preserves a live entity on either side against an opposing tombstone. Ordinary same-Provider synchronization keeps normal deletion propagation.
- The same Provider-switch-only live-over-opposing-tombstone rule applies to Personalization collection values and Novel
  Bookshelf Books; ordinary same-Provider synchronization continues to propagate explicit deletion.
- Never commit signing material, AGConnect configuration, production environment files, API keys, databases, backups,
  device captures, private user data, `node_modules`, or `oh_modules`.
- Do not capture or inspect a device, emulator, desktop, browser, or app screen unless the user explicitly authorizes
  that specific visual capture in the current task.
- Keep native pages as UI shells and place policy, orchestration, persistence, and transport behavior in their existing
  `core`, `services`, `data`, or `features` owners.
- User-facing release notes stay short: one summary line plus a few plain items about what changed for the user. No
  work-report detail, no implementation, file, test, or verification talk. `release-history.json` notes are the exception
  and keep their provenance record.
- Write every changelog entry twice, once in Chinese and once in English. `changelog.md` and `community-changelog.md` are
  the Chinese documents; `changelog_en.md` and `community-changelog_en.md` are their English counterparts, and
  `release_notice.json` / `release_notice_en.json` follow the same pairing. A new `## <version> (<code>)` section, its
  summary line, and its bullets all land in both languages in the same change, with the same version headings and the
  same bullet count, because an English device reads the English document and falls back to Chinese only for a version
  the English file does not carry. The release-notes script and the changelog localization guard both fail closed when the
  pair disagrees, so a half-translated entry cannot ship.
- Run proportional contract checks and `AIRA_DISTRIBUTION=community SKIP_INSTALL=1 ./scripts/build-aira-browser.sh` for
  Community changes when a matching local signing profile is available.

## Internal Infrastructure (out of tree)

This repository is public. `api.aira.cool`, its production host, and the operator's backup host are private
infrastructure: **never add a host address, login command, SSH key path, or credential to this tree**, including this
file, `docs/`, and `.planning/`. Existing `.planning/` notes that mention a host are historical leftovers, not a pattern
to copy.

When a task in this repo needs to reach the live backend, the login recipe lives outside the repository, on the
operator's machine:

- `~/.config/aira/servers/` — one `<address>.md` per host (what it is, how to log in) plus a `<address>.env` holding the
  credential (mode 600), and `ssh-backup-server.sh` for the backup host.
- `~/Desktop/aira-cloud-private/AGENTS.md` — the authoritative server list and deployment procedure for the backend.

Read those instead of writing new host details here. Anything that must not be published belongs there, not in this
tree.

# Personalization Sync Uses An Explicit Portable Allowlist

Accepted, amended 2026-07-17: Personalization Sync serializes only four explicitly allowlisted sections rather than whole configuration repositories: `home_shortcuts`, a strict `core_preferences` DTO, `activity_heatmap`, and `search`. Search includes custom search engines. Core preferences include portable theme, appearance, toolbar, startup restore, tab auto-close, private-tab restore, and private-mode theme choices.

Custom homepage, translation, reader mode, Cookie policy, scripts, advertising/web filtering, proxy, permissions, downloads, local paths/content, diagnostics, experiments, secrets, cookies, tokens, authentication state, User-Agent/platform policy, and other device-bound state are excluded. Clients and providers ignore retired `custom_homepage`, `web_filters`, and `user_scripts` sections rather than preserving or applying them.

Amended 2026-07-22: every preference exposed by the native Home Settings surface is part of `core_preferences.appearance`. In addition to the existing Favorites/Recently Closed visibility, layout, count, icon-size, and icon-corner choices, the allowlist now carries Favorites title visibility, shortcut-name visibility, Recently Closed title visibility, the Home Settings button, system-home search visibility, system-home search scroll behavior, and the Home wallpaper mode. These fields stay inside the existing section and semantic merge owner; no new Domain, section, transport, or schema version is introduced. New clients always emit the fields, while snapshots from clients that do not contain them preserve the target device's current values.

Amended 2026-07-23: bottom-toolbar Web scroll behavior is represented by the single portable
`core_preferences.appearance.bottomToolbarScrollBehavior` value (`fixed`, `compact`, or `hidden`). It replaces the
misleading `hideChromeOnScroll` boolean, which only produced the compact capsule and could not represent full hiding.
New clients omit the retired boolean. Existing snapshots may still contain that unknown key and are accepted by the
existing unknown-key rule; because they do not contain the new optional value, the receiving device preserves its current
setting. No old-field conversion, dual-field write, repair branch, new section, or schema-version fork is retained.

Wallpaper synchronization is preference-only. `theme`, `bing`, and `custom` mode selection is portable, but custom image bytes, asset metadata, and device-local paths remain excluded. A target device that receives `custom` without a usable local custom asset keeps the portable mode while the existing wallpaper presentation layer renders its safe theme fallback; selecting a custom image remains a device-local content action. Bing asset fetching and cached image data also remain device-local. The Home recovery-entry rule is applied during remote preference application as well as local settings edits: Favorites, Recently Closed, and the Home Settings button must retain at least one visible entry, with the settings button used as the safe recovery entry for an invalid older snapshot. That policy repair is treated as a sync-relevant local correction so a later automatic run writes the valid combination back to the provider.

The Activity heatmap is an App-only Personalization item. It synchronizes counts and durations as bounded per-device daily contributions; it never contains URLs, titles, queries, or page content. Previous-generation activity transports and server state remain isolated and are not read by Sync vNext.

For the same `(sourceId, date)`, monotonic counters merge by component-wise maximum. Different sources are summed only when deriving the visible daily total. Each source retains at most its latest 420 dates. On the first enabled g2 heatmap initialization, the App atomically freezes the complete locally visible totals into the stable `aira-local-visible-history-g2` source and starts a new device contribution ledger. Retries reuse that durable local seed, and multiple upgraded devices merge the shared history source by component-wise maximum. This continues local visible state only; old cloud activity is never read or migrated.

Amended 2026-07-18: every current-generation snapshot always contains all four section envelopes, while the user's four item selections are device-local filters rather than account-global state. A device builds, applies, and contributes only its locally selected sections. For an unselected section it carries the current remote section through the full snapshot unchanged; if no remote content exists it may emit a disabled `{}` envelope. Remote `enabled` therefore describes whether that transported section currently contains active portable content and must never rewrite another device's local selection. An unselected remote section also does not advance that device's local content/deletion baseline; the existing local baseline is retained so first enable, including the heatmap's local-history freeze, remains a device-local initialization. A previously disabled envelope with a payload that passes the full enabled-section schema may be promoted and merged when a device later selects that item. This preserves data and full-snapshot/CAS behavior without adding an operation log or account-level selection topology.

Amended 2026-07-18: current-generation `search.settings` no longer contains or requires `preserveAddressInputOnFocus`. The address bar now always owns its focus behavior, so this obsolete UI-only boolean is removed from the App model, local search settings publication, Personalization snapshot construction/application, and App/server validation. Existing snapshots may still contain the unknown extra key and are accepted without migration; new clients omit it. No cross-version compatibility branch or repair path is retained.

Amended 2026-07-20: when a WebDAV provider returns `409 Conflict` for the first `aira/g2/personalization/snapshot.json` read because its intermediate collections do not exist, the App adapter creates the fixed collections in order and retries that GET once. Only `404 Not Found` after collection preparation means an empty current-generation remote; a persistent conflict remains fail-closed.

The App is the only semantic Personalization merge owner. Aira Cloud, WebDAV, and Huawei Space adapters provide strict snapshot validation, revision/CAS enforcement, and exact snapshot storage; the current-generation Aira server does not run a second semantic merge or silently repair partial sections. Automatic foreground synchronization performs repository-ready recovery, local-change debounce, bounded retry, and a low-frequency full read for remote-only changes and Additional Backup retry. A full read is a confirmed local no-op only when every locally selected merged section is semantically identical to the freshly captured local section. In that case no repository is re-applied; unchanged local section/deletion states are also not rewritten unless a local upload completed and those states must advance. Provider runtime health/revision may still record the confirmed remote observation.

Amended 2026-07-24: Personalization convergence is decided per selected section from its portable payload rather than from envelope timestamps or one whole-snapshot boolean. Only sections whose merged portable payload differs from the freshly captured local payload are applied to local repositories; a difference in one section must not re-apply the other selected sections. Once a remote section exists, a newer envelope timestamp by itself never causes a Provider write when `enabled` and the complete portable payload are identical. Home Shortcut payloads use one canonical record order (`scenarioId`, then `position`, then stable `id`) before checksum, merge comparison, Provider commit, and local application so equal-position records cannot create an array-order apply loop. Activity repository updates are content-revision updates: an apply whose normalized totals and local contributions are unchanged preserves the repository `updatedAt` and performs no persistence, preventing a sync apply from manufacturing the next heatmap contribution revision.

Amended 2026-08-08: Home Shortcut merge preserves record-ID history while enforcing destination identity after the
ordinary ID merge. Multiple active System records for one stable target, or Web records for one normalized destination,
choose the same deterministic winner used by Home projection; additional active IDs become versioned tombstones newer
than every member of that duplicate group. Local snapshot construction and incoming application enforce the same rule,
making convergence idempotent across Aira Cloud, Huawei Space, and WebDAV without a migration, physical cleanup, new
schema field, Provider-side merge, or compatibility transport.

Amended 2026-07-26: the portable toolbar action roster includes `find` for the native `查找网页` quick action. New
layouts place it after `textZoom`; an existing layout that predates the action inserts it once after `textZoom` while
preserving every existing action's relative order. After that normalization, user reordering is ordinary
`core_preferences.toolbarLayout.primaryActionIds` state and synchronizes through the existing complete ordered-array
snapshot path. No new Personalization section, field, merge rule, transport, baseline, Provider behavior, or compatibility
branch is introduced.

Amended 2026-08-03: `core_preferences` still chooses one preferred whole section using the existing section-envelope and
first-sync rules. After that choice, toolbar layout is the single nested last-write-wins value: when the alternate
section has a strictly newer `toolbarLayout.updatedAt`, its complete primary and secondary ordered arrays replace only
the preferred section's toolbar layout. A missing preferred toolbar preserves an available alternate toolbar, while
equal timestamps keep the preferred side. Theme, appearance, and general settings remain entirely from the preferred
section. A mixed section carries the newer section-envelope timestamp and is written back through the existing complete
snapshot/CAS path so an older remote toolbar cannot later overwrite a locally newer drag order.

Amended 2026-07-31: Novel Bookshelf is an explicitly authorized fifth device-local Personalization selection, but it is
not a fifth G2 section. It uses the independent companion snapshot and provider storage defined by ADR-0063, so the
exact four-section allowlist and old-client G2 validation remain unchanged.

Amended 2026-08-25: one canonical section-content comparison in `PersonalizationSyncSnapshotService` now owns upload,
local apply, exact read-back, and Provider-canonical cleanup equality. It sanitizes each allowlisted section before
comparing enabled state and portable payload, ignores envelope timestamps for semantic no-op decisions, and retains
timestamps only for exact write confirmation. The completed merged snapshot is compared with the active remote snapshot
before any upload, so unchanged portable content performs no Provider write.

Huawei G2 commits remain complete snapshots and retain their existing row schema and revision semantics. After a new
commit has been uploaded and freshly read back, the adapter may delete only locally observed commits that are referenced
as ancestors and are not current Heads. It protects every observed Head and the just-published commit, uploads the
deletions, and performs a fresh cloud-first confirmation. Parent references may point to removed ancestors because every
Head materializes independently; old clients therefore continue to read current Heads without a schema or generation
fork. A concurrent unseen commit is absent from the deletion plan and cannot be removed. A graph without a natural Head
fails closed and skips compaction. This bounds ordinary history to current conflict Heads while allowing temporary extra
rows during real concurrent writers or stale-client return. The same maintenance runs after a fresh read, so an upgraded
user with existing ancestor history is compacted even when semantic content is already unchanged; it creates no new
snapshot commit. A temporary cleanup failure does not invalidate the already verified complete Head or turn a readable
account into a semantic Sync failure; maintenance remains deferred and retryable.

# Aira Shared Sync Topology Development Spec

Status: superseded on 2026-07-16 by `docs/adr/0047-sync-vnext-uses-a-per-device-active-provider.md`.

This file is retained only as historical context for the removed account-level Sync Source Topology. It is not a current implementation contract. Current clients must not restore its provider roles, topology propagation, Activity heatmap synchronization, bridge/migration behavior, or cross-Domain transition rules.

This specification replaces the earlier product model in which bookmark sync had one enabled provider, backup paths were removed, Personalization Sync was Aira-Cloud-only/Pro-only, and Huawei Space synchronized bookmarks only. Huawei Space platform transport constraints from `huawei-space-bookmark-sync-development-plan.md` still apply.

## Product Model

- The sync overview contains exactly two navigation rows: `书签同步` and `个性化同步`.
- Each overview row shows only `已开启` or `未开启`.
- Bookmark Sync and Personalization Sync are separate Sync Domains with independent enablement, payloads, merge rules, status, and failures.
- Both domains share one account-level, versioned Sync Source Topology.
- The topology contains exactly one Primary Sync Source and zero, one, or two explicitly enabled Backup Sync Sources.
- Available providers are Huawei Space, WebDAV, and Aira Cloud.
- Automatic synchronization is inherent when a domain is enabled; there is no separate automatic-sync switch.
- `立即同步` remains available inside each enabled domain detail page.

## Entitlements

- Automatic sync, Bookmark Sync, and Personalization Sync are free capabilities.
- Huawei Space and WebDAV are free as primary or backup providers for either domain.
- Aira Cloud requires Pro whenever it is primary or backup.
- Pro expiry makes Aira Cloud unavailable in its retained role; it never triggers automatic source switching or data deletion.
- Aira Cloud data is retained until explicit user deletion/account closure, even when Pro is inactive.

## Cross-System Boundary

- The Aira browser extension provides cross-system bookmark synchronization only.
- Personalization payloads are consumed only by compatible Aira clients.
- Extension read/write is allowed only when Aira Cloud is primary and Pro is active.
- When Aira Cloud is a backup, extension sync is paused and the backend rejects extension writes.

## Source Roles

- Routine automatic sync reads and merges only from the primary.
- After primary sync succeeds, each enabled backup receives the resulting state for each enabled domain.
- Backups are never read during routine sync.
- Backup data is read only for explicit recovery or primary promotion/switching.
- Selecting a primary does not automatically enable the other providers as backups.
- A successful switch changes only the Primary Sync Source; existing explicitly enabled backups remain enabled, while
  the former primary is not automatically added as a backup. Its remote data and provider configuration remain until
  the user explicitly selects or removes them.

## Account-Level Topology

- Compatible Aira devices share one topology identity and monotonically increasing topology version.
- Provider metadata stores topology id/version, primary provider id, enabled backup ids, owner identity, and update/source metadata.
- WebDAV passwords and other provider credentials remain device-local.
- A backup role without credentials on the current device remains in the account topology but does not block a primary
  switch. That provider is marked unavailable locally, may remain on an older topology version, and catches up on the
  next authorized backup write after credentials are restored.
- Local/remote role mismatch is a Topology Conflict and blocks sync instead of last-device-wins overwrite.
- Topology transitions are serialized and committed only after every enabled domain prepares successfully.

## Initialization And Switching

- A domain becomes `已开启` only after primary initialization succeeds.
- First primary activation defaults to non-destructive merge:
  - bookmarks use the existing bookmark conflict/tombstone protocol;
  - portable personalization items merge by item semantics/timestamps;
  - activity heatmap merges per date/source contribution.
- A confirmed-empty remote is seeded from local state.
- Unknown, preparing, foreign-account, incomplete, or incompatible remote state blocks activation.
- Whole-local or whole-remote replacement is recovery-only and is not shown in ordinary activation UI.
- Primary switching is atomic across enabled domains; suspended domains do not participate.
- Promoting a healthy, current backup makes it primary without re-merging; the former primary is not automatically added
  as a backup.
- A stale, failed, or unknown backup enters recovery rather than silent promotion.

## Backup Lifecycle

- The two non-primary providers are optional backup candidates with independent switches.
- Enabling an empty backup target initializes it from the current authoritative state.
- Enabling a non-empty backup never imports it and never overwrites silently; the user confirms replacement or cancels/enters recovery.
- Disabling a backup stops future writes without deleting remote history or local configuration.
- Re-enabling resumes directly only when the same known backup lineage is verified; otherwise initialization confirmation is required again.
- Primary success plus backup failure is a Degraded Backup State, not total sync failure.
- Backup failures keep provider-specific last-success/error/retry state and do not roll back, disable, or switch anything.

## Unavailable Primary

- Aira never automatically promotes a backup.
- Local data remains usable and changes remain pending.
- Manual sync failure alerts immediately.
- Background detection alerts on the next foreground opportunity.
- The same continuous Primary Source Incident produces one popup; status remains visible until recovery.
- The popup provides acknowledgement and source-management entry points but performs no automatic action.

## Domain Enablement And Suspension

- Bookmark and personalization domains can be enabled independently.
- Disabling a domain is a non-destructive suspension: provider configuration and local/remote data remain.
- Re-enable uses normal primary initialization/merge rules.
- Remote deletion/reset is not exposed in sync details or advanced settings in this implementation.
- Aira Cloud deletion remains in account privacy/closure; Huawei Space/WebDAV reset is deferred.

## Personalization Data Boundary

Personalization Sync uses explicit portable representations, not whole repository/config dumps.

Include:

- home shortcuts and ordering;
- a strict core-preferences DTO covering theme, portable appearance, toolbar layout, startup restore, tab auto-close,
  private-tab restore, and private-mode theme preferences;
- search settings, including custom search engines, ordering, suggestions, and fallback configuration;
- activity heatmap contributions and aggregates.

Exclude:

- custom homepage configuration, whether file-backed or URL-backed;
- translation preferences and translation API configuration;
- reader mode and Cookie policy;
- scripts, advertising/web filtering, filter exceptions, and rule sources;
- proxy configuration, site permissions, and WebApp permission state;
- passwords, tokens, cookies, authentication material, and private-mode authentication state;
- local HTML/files and arbitrary local content;
- download paths/device storage configuration;
- system permission state and platform authorization;
- diagnostics and experiments;
- User-Agent and platform-bound external-navigation policy;
- other form-factor/device-only settings.

The client and every server/provider normalization boundary must enforce the same four active section ids:
`home_shortcuts`, `core_preferences`, `activity_heatmap`, and `search`. Retired sections such as
`custom_homepage`, `web_filters`, and `user_scripts` are ignored rather than preserved or reapplied.

On first Personalization Sync enablement, all allowlisted items are preselected and shown for confirmation. Later suspension/re-enable preserves the user's last item choices.

## Activity Heatmap Merge

- Store cumulative contributions by `(date, sourceId)` rather than only a last-write-wins daily total.
- Different sources/devices add to the day's total.
- Repeated updates from the same source replace/advance that source contribution idempotently.
- The visible heat level is derived from the merged daily total.
- Payloads contain counts/durations only, never URLs, titles, queries, or page content.
- Backups retain contribution state needed to avoid duplicate counting after recovery.

## UI Structure

### Sync Overview

- `书签同步` navigation row: summary is only `已开启` / `未开启`.
- `个性化同步` navigation row: summary is only `已开启` / `未开启`.
- No inline switches and no provider/status detail on the overview.

### Bookmark Sync Detail

- Top domain switch.
- Primary Source group with three single-select provider rows.
- Backup Source group containing the two non-primary providers with independent switches.
- Provider-specific state on each row; Aira Cloud carries a Pro badge.
- Immediate-sync action.

### Personalization Sync Detail

- Top domain switch.
- Shared-source summary and `管理同步来源` link to Bookmark Sync Detail.
- Allowlisted item switches.
- Immediate-sync action.

## WebDAV Automatic-Sync Policy

- Keep change batching/debounce and incremental writes.
- Replace fixed rapid failure retry with provider-aware exponential backoff.
- Stop active retries when the app is backgrounded.
- Reduce remote polling pressure relative to hosted/platform providers.
- Preserve manual immediate sync.

## Existing-User Migration

- Preserve the currently selected provider as primary; never auto-migrate to Huawei Space or another provider.
- Do not auto-enable new backups.
- Preserve configured provider identities/credentials locally.
- Preserve an explicit legacy auto-sync-off choice by migrating Bookmark Sync to suspended; otherwise an active configured provider migrates to enabled Bookmark Sync.
- Personalization migrates to enabled only when existing personalization sync history proves prior use; otherwise it remains disabled with all allowlisted items preselected for first enablement.
- Existing Aira Cloud primary remains selected even without current Pro and becomes an unavailable primary per entitlement rules.
- Existing remote data without topology metadata is adopted only when account/provider/baseline lineage is verifiable; otherwise block and require recovery.

## Out Of Scope

- Automatic failover.
- Independent provider topology per Sync Domain or per device.
- Browser-extension personalization sync.
- Normal settings UI for remote reset/deletion.
- Synchronization of secrets, local files, cookies, history, open tabs, or browsing content.
- New repository-internal automated test suites; verification follows the repository build/install/manual policy.

## Acceptance Criteria

- Free users can enable both domains through Huawei Space or WebDAV with automatic sync.
- Aira Cloud is the only Pro-gated provider and is gated as primary and backup.
- Exactly one primary is authoritative and routine reads never come from backups.
- Both backups can be independently enabled and provider failures remain isolated.
- Source switching cannot leave bookmark and personalization domains on different primaries.
- The extension cannot write while Aira Cloud is a backup or Pro is inactive.
- Personalization uses all three providers with the allowlist and activity contribution merge.
- Overview summaries remain strictly `已开启` / `未开启`.
- Build succeeds and phone install is attempted through the repository scripts.

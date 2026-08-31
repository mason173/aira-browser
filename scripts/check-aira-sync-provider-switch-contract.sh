#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERL_BIN="${PERL_BIN:-/usr/bin/perl}"
failures=0

fail() {
  printf 'Sync provider-switch contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

matches_pattern() {
  local rel_path="$1"
  local pattern="$2"
  "${PERL_BIN}" -e '
    use strict;
    use warnings;
    my ($pattern, $path) = @ARGV;
    open my $file, "<", $path or exit 2;
    local $/;
    my $content = <$file>;
    close $file;
    exit($content =~ /$pattern/ ? 0 : 1);
  ' "${pattern}" "${REPO_ROOT}/${rel_path}"
}

require_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if ! matches_pattern "${rel_path}" "${pattern}"; then
    fail "${message}"
  fi
}

MODELS_REL="AiraBrowser/entry/src/main/ets/common/models/AiraSyncModels.ets"
PROVIDER_OPERATIONS_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceProviderOperations.ets"
SYNC_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/sync/SyncService.ets"
CONFIG_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraSyncConfigStore.ets"
MERGE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraBookmarkMergeService.ets"
DECISION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraBookmarkSyncDecisionService.ets"
PERSONALIZATION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncService.ets"
PERSONALIZATION_SNAPSHOT_REL="AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncSnapshotService.ets"
PERSONALIZATION_COLLECTION_REL="AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncCollectionMergeService.ets"
NOVEL_MODULE_REL="AiraBrowser/entry/src/main/ets/services/sync/NovelBookshelfSyncModule.ets"
NOVEL_MERGE_REL="AiraBrowser/entry/src/main/ets/services/sync/NovelBookshelfSyncMergeService.ets"
ADR_PROVIDER_REL="docs/adr/0047-sync-vnext-uses-a-per-device-active-provider.md"
ADR_NOVEL_REL="docs/adr/0063-novel-bookshelf-is-an-independent-personalization-companion.md"
ADR_BOOKMARK_REL="docs/adr/0049-bookmark-sync-uses-one-snapshot-commit-path.md"
AGENTS_REL="AGENTS.md"

for rel_path in "${MODELS_REL}" "${PROVIDER_OPERATIONS_REL}" "${SYNC_SERVICE_REL}" \
  "${CONFIG_STORE_REL}" "${MERGE_SERVICE_REL}" "${DECISION_SERVICE_REL}" "${ADR_PROVIDER_REL}" \
  "${PERSONALIZATION_SERVICE_REL}" "${PERSONALIZATION_SNAPSHOT_REL}" \
  "${PERSONALIZATION_COLLECTION_REL}" "${NOVEL_MODULE_REL}" "${NOVEL_MERGE_REL}" \
  "${ADR_NOVEL_REL}" "${ADR_BOOKMARK_REL}" "${AGENTS_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

if [ ! -x "${PERL_BIN}" ]; then
  fail "Perl is required at ${PERL_BIN}"
fi

if [ "${failures}" -eq 0 ]; then
  require_pattern "${PROVIDER_OPERATIONS_REL}" \
    'resolveBookmarkTargetMergeIntent[\s\S]*isAiraBookmarkProviderTransition\(currentRemoteKind, targetRemoteKind\)' \
    "all established cross-Provider Bookmark switches must declare the provider-switch merge intent"
  require_pattern "${MODELS_REL}" \
    'isAiraBookmarkProviderTransition[\s\S]*sourceRemoteKind !== '\''none'\'' && sourceRemoteKind !== targetRemoteKind' \
    "the shared Bookmark transition predicate must cover every established cross-Provider switch"
  require_pattern "${PROVIDER_OPERATIONS_REL}" \
    'selectActiveProviderWithPendingBookmarkSync\(remoteKind, '\''aira_cloud'\''\)' \
    "the deferred Aira Cloud to Huawei Space handoff must persist its source Provider"
  require_pattern "${MODELS_REL}" \
    'pendingBookmarkProviderSwitchFrom: AiraSyncRemoteKind' \
    "Sync settings must require the durable pending Provider-switch source in every reconstruction"
  require_pattern "${CONFIG_STORE_REL}" \
    'clearBookmarkSyncPending[\s\S]*pendingBookmarkProviderSwitchFrom: '\''none'\''' \
    "clearing the Bookmark pending marker must also clear the Provider-switch source"
  require_pattern "${CONFIG_STORE_REL}" \
    'beginHuaweiBookmarkInitialization[\s\S]*pendingBookmarkProviderSwitchFrom: '\''none'\''' \
    "a fresh Huawei Bookmark initialization must not inherit an earlier Provider-switch source"
  require_pattern "${CONFIG_STORE_REL}" \
    'buildSettingsWithProviderRuntimeState[\s\S]*pendingBookmarkSyncAt: settings\.pendingBookmarkSyncAt,[[:space:]]+pendingBookmarkProviderSwitchFrom: settings\.pendingBookmarkProviderSwitchFrom' \
    "Provider runtime-state reconstruction must retain the pending Provider-switch source"
  require_pattern "${CONFIG_STORE_REL}" \
    'buildSettingsWithRemoteStatusCache[\s\S]*pendingBookmarkSyncAt: settings\.pendingBookmarkSyncAt,[[:space:]]+pendingBookmarkProviderSwitchFrom: settings\.pendingBookmarkProviderSwitchFrom' \
    "remote-status cache reconstruction must retain the pending Provider-switch source"
  require_pattern "${DECISION_SERVICE_REL}" \
    'AiraBookmarkSyncIntent = '\''cloud-over-local'\'' \| '\''local-over-cloud'\'' \| '\''merge'\''' \
    "Bookmark sync must keep the three explicit decision intents in one owner"
  require_pattern "${SYNC_SERVICE_REL}" \
    'mergeAiraRemoteBookmarksForKind[\s\S]*targetIntent: AiraBookmarkTargetMergeIntent = '\''ordinary'\''[\s\S]*const conservativeMerge = targetIntent === '\''provider-switch'\''' \
    "SyncService must map only Provider-switch intent to conservative no-baseline merge"
  require_pattern "${SYNC_SERVICE_REL}" \
    'resolveTargetMergeIntentForActiveMerge[\s\S]*isAiraBookmarkProviderTransition\(settings\.remoteKind, activeProvider\)[\s\S]*return '\''provider-switch'\''' \
    "immediate cross-Provider Bookmark transitions must resolve to Provider-switch intent"
  require_pattern "${SYNC_SERVICE_REL}" \
    'resolveTargetMergeIntentForActiveMerge[\s\S]*pendingBookmarkProviderSwitchFrom[\s\S]*pendingBookmarkSyncAt[\s\S]*isAiraBookmarkProviderTransition\(providerSwitchFrom, activeProvider\)[\s\S]*return '\''provider-switch'\''' \
    "deferred Bookmark retries must recover Provider-switch intent from persisted settings"
  require_pattern "${SYNC_SERVICE_REL}" \
    'bookmarkDecisionService\.decideCooperatively\([\s\S]*baseline: conservativeMerge \? null : historyPlan\.baselineSnapshot' \
    "Provider-switch decisions must discard unrelated Provider baselines before the decision owner merges"
  require_pattern "${MERGE_SERVICE_REL}" \
    'deletionPolicy: AiraBookmarkMergeDeletionPolicy = '\''propagate'\''' \
    "ordinary Bookmark merges must retain single-sided deletion propagation by default"
  require_pattern "${MERGE_SERVICE_REL}" \
    'ignoreTombstonesOpposedByLiveEntities[\s\S]*ignoreTombstonesForLiveEntityId\(value\.id, localTombstones[\s\S]*ignoreTombstonesForLiveEntityId\(value\.id, remoteTombstones' \
    "Provider-switch merge must preserve live entities against opposing tombstones in both directions"
  require_pattern "${MERGE_SERVICE_REL}" \
    'buildIgnoredEntityIdSet[\s\S]*mergeOrderedIds[\s\S]*protectedEntityIds\.has\(id\)[\s\S]*mergeOrderedIdsCooperatively[\s\S]*protectedEntityIds\.has\(id\)' \
    "Provider-switch merge must preserve protected live entities in their canonical order membership"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" \
    'mergeSnapshots[\s\S]*preserveUnselectedSection\(id, localSection, remoteSection, intent\)[\s\S]*preserveUnselectedSection[\s\S]*intent: PersonalizationSyncMergeIntent = '\''ordinary'\''[\s\S]*mergeConcurrentSection\(id, localContent, remoteContent, intent\)' \
    "unselected Personalization collections must retain Provider-switch live-preservation intent"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" \
    'const mergeIntent: PersonalizationSyncMergeIntent = options\.targetRemoteKind !== undefined &&[\s\S]*settings\.remoteKind !== '\''none'\'' && settings\.remoteKind !== activeProvider[\s\S]*\? '\''provider-switch'\''[\s\S]*: '\''ordinary'\''' \
    "Personalization must reserve conservative merge for established cross-Provider switches"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" \
    'mergeRemoteHeads\(localBaseSnapshot, remoteState, config, mergeIntent\)[\s\S]*novelBookshelfSyncModule\.sync\([\s\S]*'\''active'\'',[\s\S]*mergeIntent' \
    "Personalization and its Novel companion must receive the same Provider-switch intent"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" \
    'remoteStore\.writeSnapshot\([\s\S]*confirmRemoteSnapshot\([\s\S]*applyMergedSnapshot\([\s\S]*saveProviderRuntimeState\(' \
    "Personalization must confirm a complete remote write before local apply and runtime advancement"
  require_pattern "${PERSONALIZATION_SNAPSHOT_REL}" \
    'mergeConcurrentSection[\s\S]*intent: PersonalizationSyncMergeIntent = '\''ordinary'\''[\s\S]*return adapter\.merge\(localSection, remoteSection, intent\)' \
    "Personalization collection adapters must receive explicit merge intent"
  require_pattern "${PERSONALIZATION_COLLECTION_REL}" \
    'PersonalizationSyncCollectionMergeIntent = '\''ordinary'\'' \| '\''provider-switch'\''[\s\S]*const preservesLive = intent === '\''provider-switch'\'' && liveUpdatedAt > 0' \
    "Personalization collections must preserve a live value against an opposing switch tombstone"
  require_pattern "${NOVEL_MODULE_REL}" \
    'mergeIntent: NovelBookshelfSyncMergeIntent = '\''ordinary'\''[\s\S]*mergeRemoteHeads\([\s\S]*mergeIntent[\s\S]*mergeService\.merge\(aggregate\.snapshot, headSnapshots\[index\], intent\)' \
    "Novel Bookshelf must retain Provider-switch intent across every remote head"
  require_pattern "${NOVEL_MODULE_REL}" \
    'remoteStore\.writeSnapshot\([\s\S]*confirmRemoteSnapshot\([\s\S]*applySyncedBookshelf\([\s\S]*saveLineage\(' \
    "Novel Bookshelf must confirm a complete remote write before local apply and lineage advancement"
  require_pattern "${NOVEL_MERGE_REL}" \
    'NovelBookshelfSyncMergeIntent = '\''ordinary'\'' \| '\''provider-switch'\''[\s\S]*tombstone\.deletedAt >= live\.updatedAt && intent !== '\''provider-switch'\''' \
    "Novel Bookshelf must preserve a live Book against an opposing switch tombstone"
  require_pattern "${ADR_PROVIDER_REL}" \
    'established Bookmark Provider switching between any two of Aira Cloud, Huawei Space, and WebDAV preserves a live entity[[:space:]]+on either side' \
    "ADR-0047 must record the lossless three-Provider transition rule"
  require_pattern "${ADR_PROVIDER_REL}" \
    'pausing Bookmark Sync preserves both so[[:space:]]+re-enablement resumes the same[[:space:]]+incomplete transition' \
    "ADR-0047 must distinguish resumable pause from successful pending-state clearance"
  require_pattern "${ADR_PROVIDER_REL}" \
    'transition preservation[[:space:]]+includes canonical parent-order membership[\s\S]*root-reachable[\s\S]*Ordinary same-Provider synchronization still uses[[:space:]]+single-sided deletion propagation' \
    "ADR-0047 must bind Provider-switch order preservation without changing ordinary deletion propagation"
  require_pattern "${ADR_BOOKMARK_REL}" \
    'automatic single-sided deletion rule retains one App-only exception for an established Bookmark[[:space:]]+Provider transition between any two of Aira Cloud, Huawei Space, and WebDAV' \
    "ADR-0049 must record the established cross-Provider Bookmark merge exception"
  require_pattern "${ADR_PROVIDER_REL}" \
    'Personalization collection values and Novel[[:space:]]+Bookshelf Books use the same live-over-opposing-tombstone rule[\s\S]*Ordinary same-Provider[[:space:]]+synchronization still propagates explicit deletions' \
    "ADR-0047 must record the three-Domain Provider-switch preservation boundary"
  require_pattern "${ADR_PROVIDER_REL}" \
    'Personalization Provider write[\s\S]*complete read-back[\s\S]*local section apply[\s\S]*runtime state[\s\S]*provider identity' \
    "ADR-0047 must record Personalization confirmation ordering and identity isolation"
  require_pattern "${ADR_NOVEL_REL}" \
    'live Book wins over an opposing tombstone[\s\S]*newest valid reading anchor[\s\S]*ordinary same-Provider[[:space:]]+synchronization' \
    "ADR-0063 must record Novel switch preservation without weakening ordinary deletion"
  require_pattern "${AGENTS_REL}" \
    'Every established Bookmark Provider switch between any two of Aira Cloud, Huawei[[:space:]]+Space, and WebDAV preserves a live entity on either side against an opposing tombstone' \
    "AGENTS.md must record the frozen three-Provider Bookmark switch contract"
  require_pattern "${AGENTS_REL}" \
    'The same Provider-switch-only live-over-opposing-tombstone rule applies to Personalization collection values and Novel[[:space:]]+Bookshelf Books[\s\S]*ordinary[[:space:]]+same-Provider synchronization continues to propagate explicit deletion' \
    "AGENTS.md must bind Personalization and Novel preservation to Provider switching only"
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Sync provider-switch contract passed."

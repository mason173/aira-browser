#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERL_BIN="${PERL_BIN:-/usr/bin/perl}"
failures=0

fail() {
  printf 'Bookmark snapshot contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

matches_file_pattern() {
  local file_path="$1"
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
  ' "${pattern}" "${file_path}"
}

matches_pattern() {
  local rel_path="$1"
  local pattern="$2"
  matches_file_pattern "${REPO_ROOT}/${rel_path}" "${pattern}"
}

require_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if ! matches_pattern "${rel_path}" "${pattern}"; then
    fail "${message}"
  fi
}

forbid_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if matches_pattern "${rel_path}" "${pattern}"; then
    fail "${message}"
  fi
}

require_file_pattern() {
  local file_path="$1"
  local pattern="$2"
  local message="$3"
  if ! matches_file_pattern "${file_path}" "${pattern}"; then
    fail "${message}"
  fi
}

forbid_file_pattern() {
  local file_path="$1"
  local pattern="$2"
  local message="$3"
  if matches_file_pattern "${file_path}" "${pattern}"; then
    fail "${message}"
  fi
}

MODELS_REL="AiraBrowser/entry/src/main/ets/common/models/AiraSyncModels.ets"
SNAPSHOT_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraBookmarkSnapshotService.ets"
VALIDATION_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraBookmarkSnapshotValidationService.ets"
MERGE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraBookmarkMergeService.ets"
LIFECYCLE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraBookmarkTombstoneLifecycleService.ets"
SYNC_REL="AiraBrowser/entry/src/main/ets/services/sync/SyncService.ets"
BASELINE_REL="AiraBrowser/entry/src/main/ets/data/preferences/ArkAiraSyncConfigStorageAdapter.ets"
DATABASE_REL="AiraBrowser/entry/src/main/ets/data/database/BrowserDatabase.ets"
AIRA_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraCloudBookmarkRemoteStore.ets"
WEBDAV_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraWebdavRemoteStore.ets"
HUAWEI_STORE_REL="AiraBrowser/entry/src/main/ets/data/sync/AiraHuaweiSpaceRemoteStore.ets"
HUAWEI_REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceBookmarkChunkRepository.ets"
HUAWEI_RDB_OWNER_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceRdbStoreOwner.ets"
RETIRED_HUAWEI_EPOCH_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceBookmarkEpochStore.ets"
ADR_REL="docs/adr/0049-bookmark-sync-uses-one-snapshot-commit-path.md"
RETENTION_ADR_REL="docs/adr/0010-huawei-space-does-not-time-expire-sync-history.md"
PRIVATE_BACKEND_ROOT="${AIRA_PRIVATE_BACKEND_ROOT:-}"

for rel_path in "${MODELS_REL}" "${SNAPSHOT_REL}" "${VALIDATION_REL}" "${MERGE_REL}" \
  "${LIFECYCLE_REL}" "${SYNC_REL}" "${BASELINE_REL}" "${DATABASE_REL}" \
  "${AIRA_STORE_REL}" "${WEBDAV_STORE_REL}" "${HUAWEI_STORE_REL}" "${HUAWEI_REPOSITORY_REL}" \
  "${HUAWEI_RDB_OWNER_REL}" "${ADR_REL}" "${RETENTION_ADR_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

if [ ! -x "${PERL_BIN}" ]; then
  fail "Perl is required at ${PERL_BIN}"
fi

if [ "${failures}" -eq 0 ]; then
  require_pattern "${SNAPSHOT_REL}" \
    'resolveBookmarkEntityIdCollisionsAsync[\s\S]*suppressedTombstoneNodeIds[\s\S]*createBookmarkEntityCollisionId' \
    "local snapshot capture must resolve live identity collisions and suppress opposing local tombstones"
  require_pattern "${SNAPSHOT_REL}" \
    '!result\.has\(originId\.trim\(\)\)[\s\S]*isBookmarkRootNodeId\(left\.id\)[\s\S]*isCanonicalBookmarkRootEntityId\(existingOriginId\.trim\(\)\)' \
    "canonical roots and the selected local collision owner must keep one-to-one identity ownership"
  require_pattern "${SNAPSHOT_REL}" \
    'buildFreshBookmarkSnapshot[\s\S]*snapshotValidationService\.validate\(snapshot, '\''本机'\''\)' \
    "fresh local Bookmark snapshots must pass canonical validation"
  require_pattern "${SNAPSHOT_REL}" \
    'applyBookmarkSnapshotToLocalDb[\s\S]*snapshotValidationService\.validate\(snapshot, '\''合并结果'\''\)' \
    "local apply must fail closed on a non-canonical merged snapshot"
  require_pattern "${VALIDATION_REL}" \
    'hasPartitionIdentityOverlap[\s\S]*tombstones\.some[\s\S]*folderIds\.has\(value\.id\) \|\| itemIds\.has\(value\.id\)' \
    "canonical validation must reject partition and live/tombstone identity overlap"
  require_pattern "${VALIDATION_REL}" \
    'hasValidBookmarkTree[\s\S]*parentIdByEntityId[\s\S]*orderedEntityIds[\s\S]*reachableEntityIds' \
    "canonical validation must reject invalid parents, order membership, and unreachable live entities"
  require_pattern "${SNAPSHOT_REL}" \
    'buildSyncNodesFromDataSetAsync[\s\S]*assertCompleteDataSetProjection[\s\S]*expectedLiveNodeCount' \
    "local apply must reject a projection that drops validated live entities"
  require_pattern "${SNAPSHOT_REL}" \
    'excludeProjectedLiveNodeIdsFromDeletion[\s\S]*liveNodeIds\.add\(node\.id\)[\s\S]*!liveNodeIds\.has\(localId\)' \
    "local apply must never delete a physical node occupied by the canonical live projection"
  require_pattern "${SNAPSHOT_REL}" \
    'const effectiveDeletedLocalIds = this\.excludeProjectedLiveNodeIdsFromDeletion\(deletedLocalIds, nodes\)[\s\S]*deleteNodes\(effectiveDeletedLocalIds\)' \
    "local apply must execute only the live-safe physical deletion set"
  require_pattern "${MERGE_REL}" \
    'ignoreTombstonesForLiveEntityId[\s\S]*bookmarkTombstoneKey[\s\S]*return `\$\{value\.type\}\|\$\{value\.id\}`[\s\S]*selectFreshestTombstone' \
    "provider-switch preservation must suppress any opposing tombstone while tombstone merge stays deterministic"
  require_pattern "${MERGE_REL}" \
    'sameMaterializedBookmarkOrders[\s\S]*order\.ids\.length > 0[\s\S]*sameBookmarkOrders\(leftNonEmpty, rightNonEmpty, false\)' \
    "local materialization must treat only explicit and implicit empty orders as equivalent"
  require_pattern "${AIRA_STORE_REL}" \
    'writeState[\s\S]*snapshotValidationService\.validate\(params\.snapshot, '\''Aira 云'\''\)' \
    "Aira Cloud writes must validate the outgoing canonical snapshot"
  require_pattern "${WEBDAV_STORE_REL}" \
    'writeState[\s\S]*snapshotValidationService\.validate\(params\.snapshot, '\''WebDAV '\''\)' \
    "WebDAV writes must validate the outgoing canonical snapshot"
  require_pattern "${HUAWEI_STORE_REL}" \
    'writeState[\s\S]*snapshotValidationService\.validate\(params\.snapshot, '\''华为云空间'\''\)' \
    "Huawei Space writes must validate the outgoing canonical snapshot"
  if [ -n "${PRIVATE_BACKEND_ROOT}" ]; then
    server_route_path="${PRIVATE_BACKEND_ROOT%/}/src/routes/bookmark-sync-routes.js"
    server_app_path="${PRIVATE_BACKEND_ROOT%/}/src/app.js"
    server_rate_limit_path="${PRIVATE_BACKEND_ROOT%/}/src/security/rate-limit.js"
    for file_path in "${server_route_path}" "${server_app_path}" "${server_rate_limit_path}"; do
      if [ ! -f "${file_path}" ]; then
        fail "missing private backend file ${file_path}"
      fi
    done
    if [ -f "${server_route_path}" ]; then
      require_file_pattern "${server_route_path}" \
        'sharedIds[\s\S]*privateIds[\s\S]*tombstoneKeys[\s\S]*tombstoneIds[\s\S]*同时包含存活书签和对应删除记录' \
        "the Aira server must enforce partition and live/tombstone disjointness"
      require_file_pattern "${server_route_path}" \
        'assertBookmarkHistoryDoesNotRegress[\s\S]*history_regression[\s\S]*assertBookmarkSnapshotWithinHistory' \
        "the Aira server must reject frontier regression and expired tombstones"
    fi
    if [ -f "${server_app_path}" ]; then
      require_file_pattern "${server_app_path}" \
        '/sync/v4/bookmarks/read[\s\S]*/sync/v4/bookmarks/head[\s\S]*/sync/v4/bookmarks/write' \
        "the server must expose the isolated Bookmark v4 protocol"
    fi
    if [ -f "${server_rate_limit_path}" ]; then
      require_file_pattern "${server_rate_limit_path}" \
        '/sync/v4/bookmarks/write' \
        "the v4 Bookmark write endpoint must retain the explicit sync write rate limit"
    fi
  fi
  require_pattern "${ADR_REL}" \
    'canonical identity resolution[\s\S]*live/tombstone disjointness' \
    "ADR-0049 must record the canonical Bookmark identity invariant"
  require_pattern "${ADR_REL}" \
    'canonical Bookmark[[:space:]]+data set is valid only when[\s\S]*reachable from the root order[\s\S]*fresh canonical snapshot from the local database[\s\S]*before recording the Provider baseline' \
    "ADR-0049 must record reachability validation and the local materialization postcondition"
  require_pattern "${ADR_REL}" \
    'physical local node ID[\s\S]*canonical live projection[\s\S]*ordinary same-Provider tombstone' \
    "ADR-0049 must record physical live/delete apply disjointness"
  require_pattern "${ADR_REL}" \
    'Superseding amendment 2026-08-25[\s\S]*AiraG8BookmarkHeads[\s\S]*AiraG8BookmarkBlocks[\s\S]*Blocks `TIME_FIRST`[\s\S]*Heads `TIME_FIRST`[\s\S]*90-day `storageEpoch`[\s\S]*seven-day quarantine' \
    "ADR-0049 must record the G8 Head/Blocks publication and physical-GC contract"
  require_pattern "${ADR_REL}" \
    'explicit parent order with[[:space:]]+an empty `ids` array[\s\S]*absent parent order[\s\S]*Every non-empty order' \
    "ADR-0049 must record empty-order local materialization equivalence"
  require_pattern "${MODELS_REL}" \
    'AIRA_SYNC_DEFAULT_ROOT: string = '\''aira/g3/bookmarks'\''[\s\S]*AIRA_BOOKMARK_SYNC_PROTOCOL_ID: string = '\''bookmark-snapshot-v3'\''[\s\S]*AIRA_BOOKMARK_TOMBSTONE_RETENTION_MS: number = 90 \* 24 \* 60 \* 60 \* 1000' \
    "Bookmark generation identity and the 90-day retention window must stay isolated and explicit"
  require_pattern "${LIFECYCLE_REL}" \
    'automaticRetainedFromMs[\s\S]*hasTombstoneBefore\([\s\S]*createAdvancedHistory' \
    "the frontier may advance automatically only when an older tombstone actually exists"
  require_pattern "${LIFECYCLE_REL}" \
    'baselineMatches = baseline !== undefined &&[\s\S]*sameHistory\(baseline\.history, targetHistory\)[\s\S]*sameHistory\(remoteState\.history, targetHistory\)[\s\S]*sameHistory\(confirmedHistory, targetHistory\)[\s\S]*baselineSnapshot: baselineMatches' \
    "three-way merge must exclude a baseline unless baseline, remote, and confirmed history agree"
  require_pattern "${SYNC_REL}" \
    'remoteWriteRequired = mergeResult\.remoteWriteRequired \|\| historyPlan\.requiresRemoteHistoryWrite[\s\S]*store\.writeState\([\s\S]*history: historyPlan\.history[\s\S]*confirmRemoteBookmarkCommit\([\s\S]*applyBookmarkSnapshotToLocalDb[\s\S]*recordSuccessfulSync' \
    "every Bookmark write must receive a complete read-back before local apply and success recording"
  require_pattern "${SYNC_REL}" \
    'applyBookmarkSnapshotToLocalDb[\s\S]*assertBookmarkSnapshotMaterializedLocally[\s\S]*recordSuccessfulSync' \
    "baseline success must follow a fresh local materialization postcondition"
  require_pattern "${SYNC_REL}" \
    '!historyPlan\.requiresRemoteHistoryWrite &&[\s\S]*canRecoverMissingBaselineFromMatchingRemote' \
    "matching-content conflict recovery must never confirm an uncommitted history change"
  require_pattern "${SYNC_REL}" \
    'writeBaseline\([\s\S]*bookmarkHistoryService\.confirm\(history\)[\s\S]*purgeBookmarkTombstonesBefore\(history\.retainedFrom\)' \
    "success must persist the provider baseline before frontier confirmation and cutoff purge"
  require_pattern "${DATABASE_REL}" \
    'purgeDeletedBookmarkNodes[\s\S]*isNotNull\('\''deleted_at'\''\)[\s\S]*lessThan\('\''deleted_at'\'', deletedBefore\)' \
    "physical local cleanup must use a strict retainedFrom cutoff"
  forbid_pattern "${SNAPSHOT_REL}" \
    'generationSeed|buildFreshBookmarkSnapshot[\s\S]{0,500}purgeDeletedSyncNodes' \
    "fresh snapshot capture must not own an unconditional generation-seed tombstone purge"
  forbid_pattern "${MODELS_REL}" \
    'projectLocalSnapshotForProvider' \
    "Provider adapters must not expose a second local tombstone projection seam"
  forbid_pattern "${HUAWEI_STORE_REL}" \
    'HuaweiSpaceBookmarkEpochStore|projectLocalSnapshotForProvider' \
    "Huawei Space must not restore its retired Provider-specific tombstone filter"
  forbid_pattern "${HUAWEI_RDB_OWNER_REL}" \
    'AiraHuaweiSpaceBookmarkEpochState|HUAWEI_SPACE_BOOKMARK_EPOCH' \
    "the shared Huawei RDB owner must not recreate the retired epoch table"
  if [ -e "${REPO_ROOT}/${RETIRED_HUAWEI_EPOCH_REL}" ]; then
    fail "retired Huawei tombstone epoch store must remain deleted"
  fi
  require_pattern "${HUAWEI_REPOSITORY_REL}" \
    'HUAWEI_SPACE_BOOKMARK_FORMAT_VERSION: number = 1[\s\S]*HUAWEI_SPACE_BOOKMARK_BUCKET_COUNT: number = 64[\s\S]*HUAWEI_SPACE_BOOKMARK_MAX_PAGE_JSON_BYTES: number = 10 \* 1024[\s\S]*HUAWEI_SPACE_BOOKMARK_LANES[\s\S]*selectCurrentHistoryManifests[\s\S]*newestRetainedFrom[\s\S]*Date\.parse\(manifest\.history\.retainedFrom\) === newestRetainedFrom' \
    "Huawei G8 must materialize 64-shard lane-separated pages only at the newest frontier"
  require_pattern "${HUAWEI_REPOSITORY_REL}" \
    'HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_MS: number = 90 \* 24 \* 60 \* 60 \* 1000[\s\S]*HUAWEI_SPACE_BOOKMARK_STORAGE_EPOCH_QUARANTINE_MS: number = 7 \* 24 \* 60 \* 60 \* 1000[\s\S]*storageEpoch: manifest\.storageEpoch[\s\S]*rowStorageEpoch !== manifest\.storageEpoch' \
    "Huawei G8 Heads and Blocks must carry a canonical 90-day storage epoch with a seven-day quarantine"
  require_pattern "${HUAWEI_REPOSITORY_REL}" \
    'catch \(error\)[\s\S]*declaresCurrentManifestFormat\(encoded\)[\s\S]*throw error as Error[\s\S]*declaresCurrentManifestFormat' \
    "Huawei G8 must fail closed when a current-format Head is malformed"
  require_pattern "${HUAWEI_RDB_OWNER_REL}" \
    'HUAWEI_SPACE_BOOKMARK_HEAD_TABLE: string = '\''AiraG8BookmarkHeads'\''[\s\S]*HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE: string = '\''AiraG8BookmarkBlocks'\''' \
    "Huawei G8 must keep Heads and Blocks in independently synchronized tables"
  require_pattern "${HUAWEI_RDB_OWNER_REL}" \
    'HUAWEI_SPACE_BOOKMARK_HEAD_SCHEMA[\s\S]*storageEpoch INTEGER[\s\S]*HUAWEI_SPACE_BOOKMARK_BLOCK_SCHEMA[\s\S]*storageEpoch INTEGER[\s\S]*setDistributedTables\([\s\S]*HUAWEI_SPACE_BOOKMARK_HEAD_TABLE[\s\S]*HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE' \
    "Huawei G8 cloud tables must both register the explicit storageEpoch field"
  forbid_pattern "${HUAWEI_RDB_OWNER_REL}" \
    'AiraG7BookmarkRecords' \
    "the active G8 RDB owner must not recreate or re-register the retired G7 table"
  require_pattern "${HUAWEI_STORE_REL}" \
    'writeSnapshotBlocks[\s\S]*runIncrementalCommitBarrier\(store, this\.chunkRepository\.getBlockCloudTableNames\(\)\)[\s\S]*confirmPublicationBlocks[\s\S]*publishHead[\s\S]*runIncrementalCommitBarrier\(store, this\.chunkRepository\.getHeadCloudTableNames\(\)\)[\s\S]*hasPublishedHead' \
    "Huawei G8 must confirm Blocks before publishing and confirming Head"
  require_pattern "${HUAWEI_STORE_REL}" \
    'readHead\(\)[\s\S]*getHeadCloudTableNames\(\)[\s\S]*readHeadSummaries[\s\S]*readAggregateAfterCloudFirst[\s\S]*getHeadCloudTableNames\(\)[\s\S]*if \(readResult\.needsBlockSync\)[\s\S]*getBlockCloudTableNames\(\)' \
    "Huawei G8 no-op discovery must synchronize Heads first and fetch Blocks only when materialization needs them"
  require_pattern "${SYNC_REL}" \
    'isEligible\(identityProbe\)[\s\S]*tryHuaweiBookmarkIdentityNoOp[\s\S]*readState' \
    "Huawei ordinary no-op must probe confirmed Head identity before reconstructing a complete snapshot"
  require_pattern "${SYNC_REL}" \
    'matchesConfirmedHead\(probe, head\)[\s\S]*recordSuccessfulSync[\s\S]*本机和云端已经一致' \
    "Huawei identity no-op must reuse the confirmed baseline and skip merge/write when Head identity matches"
  require_pattern "${ADR_REL}" \
    'ordinary same-Provider[\s\S]*confirmed Head identity[\s\S]*pendingBookmarkSyncAt[\s\S]*not a second merge algorithm' \
    "ADR-0049 must record the confirmed-identity no-op gate"
  require_pattern "${HUAWEI_REPOSITORY_REL}" \
    'buildPhysicalGcPlan[\s\S]*hasStorageEpochClearedQuarantine\(storageEpoch\)[\s\S]*findHeadManifestIds[\s\S]*storageEpoch !== storageEpoch[\s\S]*supersededHeadRowIds' \
    "Huawei G8 physical GC must wait for quarantine and complete current-epoch Head coverage"
  require_pattern "${HUAWEI_STORE_REL}" \
    'runPhysicalGcSafely[\s\S]*deleteSupersededHeads[\s\S]*getHeadCloudTableNames\(\)[\s\S]*confirmSupersededHeadsRemoved[\s\S]*buildPhysicalGcPlan[\s\S]*deleteBlocksBeforeStorageEpoch[\s\S]*getBlockCloudTableNames\(\)[\s\S]*confirmNoBlocksBeforeStorageEpoch' \
    "Huawei G8 GC must confirm old Head deletion before deleting and confirming old Blocks"
  require_pattern "${HUAWEI_STORE_REL}" \
    'void this\.runPhysicalGcSafely\(store\);[\s\S]*return \{[\s\S]*commitId,[\s\S]*runPhysicalGcSafely[\s\S]*catch \(error\)[\s\S]*Huawei Space G8 maintenance deferred' \
    "Huawei G8 maintenance must run after commit success and swallow/log cleanup failures"
  require_pattern "${BASELINE_REL}" \
    'history: manifest\.history[\s\S]*manifest\.history\.version !== AIRA_BOOKMARK_HISTORY_VERSION' \
    "provider baselines must persist and validate the history descriptor"
  require_pattern "${AIRA_STORE_REL}" \
    'sync/v4/bookmarks[\s\S]*AIRA_CLOUD_BOOKMARK_SYNC_PROTOCOL_ID[\s\S]*assertSnapshotWithinHistory' \
    "Aira Cloud must use the isolated v4 path and validate the history boundary"
  require_pattern "${WEBDAV_STORE_REL}" \
    'BOOKMARK_WEBDAV_FILE_VERSION: number = 2[\s\S]*history: history[\s\S]*assertSnapshotWithinHistory' \
    "WebDAV must commit history in its isolated file-v2 envelope"
  require_pattern "${RETENTION_ADR_REL}" \
    'single[[:space:]]+`AiraBookmarkTombstoneLifecycleService` owner[\s\S]*90-day candidate cutoff[\s\S]*G8' \
    "ADR-0010 must record the bounded cross-Provider lifecycle"
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Bookmark snapshot contract passed."

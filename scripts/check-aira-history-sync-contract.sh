#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'History Sync contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Eq "${pattern}" "${REPO_ROOT}/${rel_path}"; then
    fail "${message}"
  fi
}

reject_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if grep -Eqi "${pattern}" "${REPO_ROOT}/${rel_path}"; then
    fail "${message}"
  fi
}

MODEL_REL="AiraBrowser/entry/src/main/ets/common/models/HistorySyncModels.ets"
DATABASE_REL="AiraBrowser/entry/src/main/ets/data/database/BrowserDatabase.ets"
OWNER_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceRdbStoreOwner.ets"
REMOTE_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceHistoryRemoteStore.ets"
SNAPSHOT_CODEC_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceHistorySnapshotCodec.ets"
COMPUTE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraSyncComputeExecutor.ets"
TRANSFER_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraHistoryTaskpoolTransferCodec.ets"
THROTTLE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraSyncWorkThrottleService.ets"
MERGE_REL="AiraBrowser/entry/src/main/ets/services/sync/HistorySyncMergeService.ets"
RUNNER_REL="AiraBrowser/entry/src/main/ets/services/sync/HuaweiSpaceHistorySyncRunner.ets"
SERVICE_REL="AiraBrowser/entry/src/main/ets/services/sync/HistorySyncService.ets"
STATE_REL="AiraBrowser/entry/src/main/ets/data/sync/SyncExperienceStateStore.ets"
COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceCoordinator.ets"
AUTOMATIC_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceAutomaticRuntime.ets"
PROVIDER_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceProviderOperations.ets"
VIEW_MODEL_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceViewModel.ets"
SCREEN_REL="AiraBrowser/entry/src/main/ets/app/components/sync/SyncExperienceScreen.ets"
FIRST_ITEMS_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncFirstActivationItemsCoordinator.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
for rel_path in "${MODEL_REL}" "${DATABASE_REL}" "${OWNER_REL}" "${REMOTE_REL}" \
  "${SNAPSHOT_CODEC_REL}" "${COMPUTE_REL}" \
  "${TRANSFER_REL}" \
  "${THROTTLE_REL}" \
  "${MERGE_REL}" "${RUNNER_REL}" "${SERVICE_REL}" "${STATE_REL}" "${COORDINATOR_REL}" \
  "${AUTOMATIC_REL}" "${PROVIDER_REL}" "${VIEW_MODEL_REL}" "${SCREEN_REL}" "${FIRST_ITEMS_REL}" \
  "${RUNTIME_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

if [ "${failures}" -eq 0 ]; then
  require_pattern "${MODEL_REL}" \
    "HistorySyncProviderKind = 'aira_cloud' \| 'huawei_space'" \
    "History transports must remain limited to Aira Cloud and Huawei Space"
  require_pattern "${OWNER_REL}" \
    "HUAWEI_SPACE_HISTORY_HEAD_TABLE: string = 'AiraH2HistoryHeads'" \
    "Huawei History H2 must isolate Heads in AiraH2HistoryHeads"
  require_pattern "${OWNER_REL}" \
    "HUAWEI_SPACE_HISTORY_BLOCK_TABLE: string = 'AiraH2HistoryBlocks'" \
    "Huawei History H2 must isolate Blocks in AiraH2HistoryBlocks"
  if ! sed -n "/private static async prepareDistributedTables/,/private static async hasAnyRows/p" \
    "${REPO_ROOT}/${OWNER_REL}" | grep -Eq "HUAWEI_SPACE_HISTORY_HEAD_TABLE"; then
    fail "the shared Huawei RDB owner must register the History Heads table"
  fi
  if ! sed -n "/private static async prepareDistributedTables/,/private static async hasAnyRows/p" \
    "${REPO_ROOT}/${OWNER_REL}" | grep -Eq "HUAWEI_SPACE_HISTORY_BLOCK_TABLE"; then
    fail "the shared Huawei RDB owner must register the History Blocks table"
  fi
  if sed -n "/private static async prepareDistributedTables/,/private static async hasAnyRows/p" \
    "${REPO_ROOT}/${OWNER_REL}" | grep -Eq "HUAWEI_SPACE_HISTORY_TABLE"; then
    fail "H2 must not re-register the retired H1 History table for cloud sync"
  fi
  require_pattern "${OWNER_REL}" \
    "rdbOpen start db=" \
    "Huawei RDB open must log before native bind so cold-start stalls are visible"
  require_pattern "${OWNER_REL}" \
    "setDistributedTables start db=" \
    "Huawei distributed-table registration must be logged separately from rdbOpen"
  owner_open_count="$(grep -c "relationalStore.getRdbStore" "${REPO_ROOT}/${OWNER_REL}")"
  if [ "${owner_open_count}" -ne 1 ]; then
    fail "Huawei RDB owner must open the cloud store once per prepare, not bootstrap-close-reopen"
  fi
  require_pattern "${AUTOMATIC_REL}" \
    "HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS" \
    "ordinary Huawei transport must warm the store after content ready, not on the 30s scroll timer"
  require_pattern "${AUTOMATIC_REL}" \
    "warmupHuaweiSpaceTransport" \
    "automatic runtime must warm Huawei transport before periodic freshness"
  require_pattern "${AUTOMATIC_REL}" \
    "AUTOMATIC_DRAIN_YIELD_MS" \
    "automatic drain must yield a frame before touching Huawei RDB on the timer turn"
  remote_read_section="$(sed -n "/async readState(/,/async writeState(/p" \
    "${REPO_ROOT}/${REMOTE_REL}")"
  if ! printf '%s\n' "${remote_read_section}" | grep -Eq "SYNC_MODE_CLOUD_FIRST"; then
    fail "Huawei History reads must start with CLOUD_FIRST Heads"
  fi
  remote_write_section="$(sed -n "/async writeState(/,/private async consumeFreshRows/p" \
    "${REPO_ROOT}/${REMOTE_REL}")"
  if ! printf '%s\n' "${remote_write_section}" | grep -Eq "runIncrementalCommitBarrier"; then
    fail "Huawei History writes must confirm dirty Head/Block tables with TIME_FIRST then CLOUD_FIRST"
  fi
  if ! printf '%s\n' "${remote_write_section}" | grep -Eq "assertProjectionAndDesiredStateConfirmed"; then
    fail "Huawei History writes must confirm the compact snapshot semantically"
  fi
  require_pattern "${REMOTE_REL}" \
    "HUAWEI_SPACE_HISTORY_HEAD_TABLE" \
    "Huawei History reads must synchronize Heads before Blocks"
  require_pattern "${REMOTE_REL}" \
    "needsBlockCloudSync" \
    "Huawei History must fetch Blocks only when Heads cannot already be materialized"
  require_pattern "${REMOTE_REL}" \
    "const currentRows = await this\.consumeFreshRows\(store, skipCloudTransport\)" \
    "Huawei History writes must consume the fresh physical rows owned by the current run"
  require_pattern "${REMOTE_REL}" \
    "new HuaweiSpaceHistorySnapshotCodec\(this\.uid, this\.deviceId\)\.decodeRows\(rows\)" \
    "ordinary Huawei History remote reads must decode once and retain the mirror for the write plan"
  require_pattern "${REMOTE_REL}" \
    "this\.freshRows = rows" \
    "ordinary Huawei History reads must retain raw rows locally instead of cloning a complete physical mirror"
  reject_pattern "${REMOTE_REL}" \
    "this\.freshMirror" \
    "ordinary Huawei History reads must not retain the duplicated complete physical mirror"
  require_pattern "${COMPUTE_REL}" \
    "new HuaweiSpaceHistorySnapshotCodec\(uid, deviceId\)\.decodeRows\(rows, now\)" \
    "Huawei History compute must strictly decode the complete physical mirror"
  require_pattern "${COMPUTE_REL}" \
    "state: mirror\.state" \
    "the bounded remote-state decoder must return only the validated logical state"
  require_pattern "${COMPUTE_REL}" \
    "estimateHuaweiHistoryRowsTransferBytes\(rows\)" \
    "the bounded remote-state decoder must preflight one serialized transfer direction"
  require_pattern "${COMPUTE_REL}" \
    "task\.setTransferList\(\[rowBuffer\]\)" \
    "bounded H1 rows must enter TaskPool through one zero-copy transferable buffer"
  require_pattern "${COMPUTE_REL}" \
    "afterBatchItem\(index \+ 1\)" \
    "H1 transferable-buffer packing must yield between bounded row batches"
  require_pattern "${REMOTE_REL}" \
    "afterBatchItem\(rows\.length\)" \
    "H1 RDB row materialization must yield between bounded batches"
  require_pattern "${COMPUTE_REL}" \
    "taskpool\.execute\(task, taskpool\.Priority\.LOW\)" \
    "Sync compute tasks must remain low priority"
  require_pattern "${COMPUTE_REL}" \
    "AIRA_SYNC_TASKPOOL_TRANSFER_BUDGET_BYTES: number = 8 \* 1024 \* 1024" \
    "History TaskPool work must preflight the bounded structured-clone payload"
  require_pattern "${COMPUTE_REL}" \
    "AIRA_SYNC_TASKPOOL_PACK_PREFLIGHT_BUDGET_BYTES: number = 16 \* 1024 \* 1024" \
    "History row packing must remain bounded before measuring the actual transferable bytes"
  require_pattern "${COMPUTE_REL}" \
    "fitsTaskpoolPackPreflightBudget\(estimatedBytes\)" \
    "History row decode must not reject a bounded UTF-8 transfer from a conservative object estimate"
  require_pattern "${COMPUTE_REL}" \
    "fitsTaskpoolTransferBudget\(estimatedBytes\)" \
    "History TaskPool merge work must preserve oversized-state correctness"
  require_pattern "${COMPUTE_REL}" \
    "rowBuffer\.byteLength \+ desiredBuffer\.byteLength" \
    "changed Huawei History write tasks must preflight their actual framed input bytes"
  require_pattern "${COMPUTE_REL}" \
    "task\.setTransferList\(\[rowBuffer, desiredBuffer\]\)" \
    "changed Huawei History write tasks must transfer physical rows and desired state without cloning"
  require_pattern "${COMPUTE_REL}" \
    "aira-sync-history-remote-write-plan" \
    "physical decode and compact projection must execute in one bounded TaskPool task"
  require_pattern "${COMPUTE_REL}" \
    "aira-sync-history-remote-write-confirm" \
    "fresh physical confirmation and local-apply equality must execute in one bounded TaskPool task"
  require_pattern "${COMPUTE_REL}" \
    "AiraHistoryTaskpoolTransferCodec\.decodeRows\(rowBuffer\)" \
    "History TaskPool functions must use an imported pure framed-row decoder"
  require_pattern "${TRANSFER_REL}" \
    "static decodeState\(stateBuffer: ArrayBuffer\)" \
    "History TaskPool state framing must be decoded behind an imported pure codec"
  reject_pattern "${RUNNER_REL}" \
    "planHuaweiHistoryConfirmationMerge" \
    "the runner must not repeat the full History confirmation merge after remote confirmation"
  require_pattern "${COMPUTE_REL}" \
    "decodeRowsCooperatively\(rows, this\.cooperativeThrottle, now\)" \
    "oversized Huawei History mirrors must decode cooperatively instead of blocking the caller"
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "mergeCooperatively\(compactState, legacyState, throttle, now\)" \
    "synchronous and cooperative Huawei History decode must share one frozen retention time"
  require_pattern "${COMPUTE_REL}" \
    "mergeKeepingPreferredVisitsCooperatively\(" \
    "oversized Huawei History initial merges must yield cooperatively"
  require_pattern "${COMPUTE_REL}" \
    "buildProjectionCooperatively\(" \
    "oversized Huawei History projections must be built cooperatively"
  require_pattern "${COMPUTE_REL}" \
    "sameStateCooperatively\(" \
    "oversized Huawei History confirmations must compare logical state cooperatively"
  require_pattern "${COMPUTE_REL}" \
    "batchSize: 16" \
    "oversized Huawei History work must keep a frame-conscious cooperative batch size"
  require_pattern "${THROTTLE_REL}" \
    "interface AiraSyncCooperativeThrottle" \
    "the cooperative throttle contract must remain owned by the shared Sync throttle module"
  reject_pattern "${THROTTLE_REL}" \
    "HistorySyncMergeService" \
    "the shared Sync throttle must not depend on the History merge owner"
  require_pattern "${MERGE_REL}" \
    "sortVisitsCooperatively\(" \
    "oversized History normalization and merge sorting must yield cooperatively"
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "buildBucketCooperatively\(" \
    "oversized Huawei History projection buckets must be built cooperatively"
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "sortSnapshotRecordsCooperatively\(" \
    "oversized Huawei History bucket records must be sorted cooperatively"
  require_pattern "${COMPUTE_REL}" \
    "packHuaweiHistoryStateForTransfer\(" \
    "History write compute must frame the logical state in bounded cooperative batches"
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "targetStateChecksum" \
    "History write confirmation must bind the selected compact Head to the projected state checksum"
  require_pattern "${REMOTE_REL}" \
    "error instanceof AiraHistoryMirrorDecodeError" \
    "TaskPool infrastructure failures must not be mislabeled as malformed Huawei History data"
  reject_pattern "${REMOTE_REL}" \
    "validateOuterRow\(" \
    "Huawei History row identity validation must remain inside codec execution"
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "validateOuterRow\(" \
    "Huawei History physical rows must remain identity-bound"
  cooperative_decode_section="$(sed -n "/async decodeRowsCooperatively(/,/  buildProjection(/p" \
    "${REPO_ROOT}/${SNAPSHOT_CODEC_REL}")"
  if ! printf '%s\n' "${cooperative_decode_section}" | grep -Eq "validateOuterRow\(row\)" || \
    ! printf '%s\n' "${cooperative_decode_section}" | grep -Eq "afterBatchItem\("; then
    fail "cooperative Huawei History decode must validate every row and yield between bounded batches"
  fi
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "HUAWEI_SPACE_HISTORY_BUCKET_COUNT: number = 64" \
    "Huawei History compact snapshots must keep a fixed stable bucket topology"
  require_pattern "${SNAPSHOT_CODEC_REL}" \
    "HUAWEI_SPACE_HISTORY_SLOT_COUNT: number = 2" \
    "Huawei History compact snapshots must preserve the confirmed fallback slot"
  require_pattern "${REMOTE_REL}" \
    "deleteConfirmedLegacyRows\(store, projection\)" \
    "legacy Huawei History rows may be removed only after compact publication confirmation"
  require_pattern "${RUNNER_REL}" \
    "remoteStore\.requiresMaintenance\(\)" \
    "unchanged legacy Huawei History mirrors must still run the confirmed compact migration"
  require_pattern "${DATABASE_REL}" \
    "history_sync_canonical_visits_v1" \
    "portable canonical visits must remain durable across Provider switching"
  require_pattern "${DATABASE_REL}" \
    "history_sync_tombstones_v1" \
    "exact History tombstones must remain durable after outbox acknowledgement"
  require_pattern "${DATABASE_REL}" \
    "history_sync_retention_v1" \
    "History retention must keep a stale-device resurrection frontier"
  require_pattern "${DATABASE_REL}" \
    "CURRENT_BROWSER_DATABASE_SCHEMA_VERSION = 5" \
    "Huawei History tables must advance the local browser database schema to version 5"
  require_pattern "${DATABASE_REL}" \
    "schemaVersion < 5" \
    "version-4 browser databases must run the idempotent History schema migration"
  require_pattern "${DATABASE_REL}" \
    "HISTORY_SYNC_CANONICAL_BACKFILL_STATE_PREFIX" \
    "History canonical backfill completion must remain durable per account"
  require_pattern "${DATABASE_REL}" \
    "ensureHistorySyncCanonicalVisitsBackfilled\(store, normalizedUid\)" \
    "History sync entry points must use the durable one-time canonical backfill gate"
  require_pattern "${DATABASE_REL}" \
    "hasMissingHistorySyncCanonicalVisits\(store, normalizedUid\)" \
    "the one-time History canonical backfill gate must prove whether any local row is missing"
  huawei_state_read_section="$(sed -n "/async readHuaweiSpaceHistorySyncState(/,/async applyHuaweiSpaceHistorySyncState(/p" \
    "${REPO_ROOT}/${DATABASE_REL}")"
  aira_enrollment_section="$(sed -n "/async prepareAiraHistorySyncProviderEnrollment(/,/async prepareHistorySyncEnrollment(/p" \
    "${REPO_ROOT}/${DATABASE_REL}")"
  if printf '%s\n%s\n' "${huawei_state_read_section}" "${aira_enrollment_section}" | \
    grep -Eq "backfillHistorySyncCanonicalVisitsInStore"; then
    fail "ordinary History sync entry points must not bypass the one-time canonical backfill gate"
  fi
  reject_pattern "${DATABASE_REL}" \
    "removeHistorySyncVisitsOutsideState" \
    "History set-union apply must never treat snapshot absence as deletion"
  require_pattern "${DATABASE_REL}" \
    "advanceHistorySyncRetentionFromRemotePrune" \
    "Aira retention pruning must advance the durable cross-Provider frontier"
  require_pattern "${MERGE_REL}" \
    "mergeKeepingPreferredVisits\(" \
    "Huawei remote/local merge must expose an explicit confirmed-remote preference"
  require_pattern "${MERGE_REL}" \
    "const visits = this\.mergeVisits\(\[\], Array\.isArray\(value\?\.visits\)" \
    "normalizing one Huawei mirror must still reject conflicting immutable visits"
  require_pattern "${RUNNER_REL}" \
    "this\.computeExecutor\.planHuaweiHistoryInitialMerge\(remote, local\)" \
    "Huawei History merge planning must run through the off-main-thread compute executor"
  require_pattern "${COMPUTE_REL}" \
    "mergeKeepingPreferredVisits\(remote, local, now\)" \
    "Huawei History must prefer the freshly confirmed remote mirror over stale local canonical metadata"
  require_pattern "${DATABASE_REL}" \
    "replaceCanonical = canonicalPayloads\.get\(visit\.visitId\) !== JSON\.stringify\(visit\)" \
    "Huawei History apply must detect stale local canonical payloads"
  require_pattern "${DATABASE_REL}" \
    "applyHistorySyncVisitUpsert\(store, normalizedUid, visit, replaceCanonical\)" \
    "Huawei History apply must repair stale local canonical payloads"
  require_pattern "${DATABASE_REL}" \
    "replaceCanonical: boolean = false" \
    "ordinary Aira History apply must retain first-accepted canonical payload semantics"
  require_pattern "${DATABASE_REL}" \
    "deviceName: visit\.syncOrigin === 'local' \? 'Aira HarmonyOS' : 'Aira device'" \
    "canonical backfill must not reinterpret a remote source client ID as a device label"
  reject_pattern "${MERGE_REL}" \
    "DEBUG-HIST-CONFLICT-825|HistoryConflictDiag" \
    "temporary History conflict diagnostics must be removed after device verification"
  reject_pattern "${RUNNER_REL}" \
    "DEBUG-HIST-CONFLICT-825|HistoryConflictDiag" \
    "temporary History stage diagnostics must be removed after device verification"
  require_pattern "${MERGE_REL}" \
    "isDeleted.*tombstones.*deleteRanges.*clearBefore.*retentionFrontier" \
    "one merge owner must apply all History deletion and retention rules"
  require_pattern "${SERVICE_REL}" \
    "identity.provider === 'huawei_space'" \
    "HistorySyncService must route Huawei runs behind the single facade"
  reject_pattern "${SERVICE_REL}" \
    "resetAiraHistorySyncForProviderSwitch" \
    "switching back to Aira Cloud must retain a valid incremental cursor"
  require_pattern "${SERVICE_REL}" \
    "providerEnrollmentUpdatedAfter" \
    "Aira target transitions must preserve the last confirmed enrollment boundary"
  require_pattern "${DATABASE_REL}" \
    "greaterThan\('updated_at', normalizedUpdatedAfter - 1\)" \
    "Aira target enrollment must select only visits observed since its last confirmed state"
  require_pattern "${RUNNER_REL}" \
    "initialPlan\.remoteWriteRequired \|\| remoteMaintenanceRequired" \
    "an unchanged Huawei History head must not run a redundant write confirmation cycle"
  require_pattern "${RUNNER_REL}" \
    "const confirmedState = remoteWriteRequired \? writeResult\.state : initialPlan\.merged" \
    "an unchanged Huawei History head must retain the already-proven initial merge"
  require_pattern "${RUNNER_REL}" \
    "const confirmedLocalApplyRequired = remoteWriteRequired && writeResult\.localApplyRequired" \
    "the runner must consume the remote confirmation task's local-apply decision"
  require_pattern "${RUNNER_REL}" \
    "localApplyRequired: false" \
    "the skipped remote-write path must not request a redundant local apply"
  require_pattern "${DATABASE_REL}" \
    "hasHistorySyncProjectionVictims\(store, normalizedUid, cutoff\)" \
    "History projection pruning must keep its no-victim path inside SQLite"
  require_pattern "${DATABASE_REL}" \
    "HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE" \
    "large local History state parsing must yield in bounded batches"
  require_pattern "${DATABASE_REL}" \
    "rowVisitIds\.length % HISTORY_SYNC_CANONICAL_READ_BATCH_SIZE" \
    "large local History row materialization must yield before JSON parsing"
  require_pattern "${COMPUTE_REL}" \
    "remoteWriteRequired: !mergeService\.sameState\(merged, remote\)" \
    "the compute plan must preserve semantic no-change detection for Huawei History"
  require_pattern "${SERVICE_REL}" \
    "huaweiSpaceRunner.run\(huaweiIdentity, runMode === 'ordinary'\)" \
    "switching to Huawei must retain the Aira outbox until Provider persistence"
  require_pattern "${RUNNER_REL}" \
    "if \(clearOutboxAfterSuccess\)" \
    "ordinary Huawei success may clear the Aira outbox only outside a Provider transition"
  require_pattern "${RUNNER_REL}" \
    "shouldUseCachedHuaweiHistoryRemote" \
    "ordinary Huawei History may reuse the confirmed remote instead of repeating CLOUD_FIRST"
  require_pattern "${AUTOMATIC_REL}" \
    "requestUnifiedAutomaticFreshnessRun" \
    "automatic periodic freshness must enqueue the same enabled-domain set"
  require_pattern "${AUTOMATIC_REL}" \
    "isHistoryDomainEnabled" \
    "manual History execution must use domain enablement rather than the automatic foreground scheduler"
  require_pattern "${PROVIDER_REL}" \
    "runHistoryProviderTransitionWithinCurrentOperation" \
    "Primary Provider switching must carry supported History transitions"
  require_pattern "${AUTOMATIC_REL}" \
    "runForProvider\(source, 'source_transition'\)" \
    "supported History Provider switching must refresh the bounded source state first"
  require_pattern "${AUTOMATIC_REL}" \
    "runForProvider\(target, 'target_transition'\)" \
    "supported History Provider switching must enroll and confirm the target before persistence"
  require_pattern "${SERVICE_REL}" \
    "retainAcknowledgedOutbox = runMode === 'source_transition'" \
    "an Aira source transition must retain acknowledged outbox mutations"
  require_pattern "${SERVICE_REL}" \
    "!retainAcknowledgedOutbox" \
    "ordinary Aira runs may remove acknowledgements while source transitions retain them"
  require_pattern "${DATABASE_REL}" \
    "if \(removeAcknowledgedMutations\)" \
    "Aira outbox acknowledgement removal must be controlled by the History run mode"
  require_pattern "${AUTOMATIC_REL}" \
    "setHistorySelected\(true, account.uid\)" \
    "supported History Provider transitions must preserve the confirmed account binding"
  require_pattern "${AUTOMATIC_REL}" \
    "clearHistorySelectionForWebdav" \
    "WebDAV selection must clear History state and automatic work"
  require_pattern "${PROVIDER_REL}" \
    "clearHistorySelectionForWebdav" \
    "selecting WebDAV must invoke the History clear owner"
  if ! sed -n "/deactivateCurrentSync()/,/requestProviderSelection(/p" \
    "${REPO_ROOT}/${PROVIDER_REL}" | grep -Eq "cancelHistoryAutomaticSync"; then
    fail "deactivating the Primary Provider must cancel History automatic work"
  fi
  if ! sed -n "/private scheduleHistoryPeriodicRun/,/private resolveHistoryRetryDelayMs/p" \
    "${REPO_ROOT}/${AUTOMATIC_REL}" | grep -Eq "!this\.isHistoryAutomaticSyncActive\(\)"; then
    fail "the History periodic callback must stop rescheduling after its runtime becomes inactive"
  fi
  require_pattern "${SERVICE_REL}" \
    "resolveHistorySyncProviderKind\(.*remoteKind" \
    "History must resolve its transport from the Primary Provider"
  reject_pattern "${STATE_REL}" \
    "historyProvider|setHistoryProvider" \
    "History must not persist an independent Provider selection"
  require_pattern "${VIEW_MODEL_REL}" \
    "historySupported: activeProvider !== 'webdav'" \
    "WebDAV must expose History as unsupported"
  require_pattern "${STATE_REL}" \
    "historyEnabled: boolean = true" \
    "History must default to selected on first use"
  require_pattern "${STATE_REL}" \
    "historySelected: value\?\.historySelected !== false" \
    "missing History selection must default on while an explicit false remains off"
  require_pattern "${COORDINATOR_REL}" \
    "async reconcileHistoryAccountBinding" \
    "one Sync Experience owner must reconcile the History account binding"
  require_pattern "${COORDINATOR_REL}" \
    "async reconcileHistoryAccountLifecycle" \
    "one Sync Experience owner must drain, normalize, detach, refresh, and resume History account state"
  require_pattern "${COORDINATOR_REL}" \
    "cancelForIdentityChange\(accountUid\)" \
    "History lifecycle reconciliation must pass the resolved account UID into the active-run drain"
  require_pattern "${SERVICE_REL}" \
    "const cancelActiveRun = this\.runAccountUid !== nextAccountUid\.trim\(\)" \
    "same-account History lifecycle reconciliation must drain without invalidating the active run"
  require_pattern "${SERVICE_REL}" \
    "if \(cancelActiveRun\)" \
    "History identity generation may advance only behind the account-mismatch decision"
  reject_pattern "${COORDINATOR_REL}" \
    "cancelForIdentityChange\(\)" \
    "History lifecycle reconciliation must not unconditionally cancel the active run"
  history_lifecycle_section="$(sed -n "/async reconcileHistoryAccountLifecycle/,/async reconcileHistoryAccountBinding/p" \
    "${REPO_ROOT}/${COORDINATOR_REL}")"
  cancel_line="$(printf '%s\n' "${history_lifecycle_section}" | awk \
    '/cancelForIdentityChange/ { print NR; exit }')"
  binding_line="$(printf '%s\n' "${history_lifecycle_section}" | awk \
    '/reconcileHistoryAccountBinding/ { print NR; exit }')"
  detach_line="$(printf '%s\n' "${history_lifecycle_section}" | awk \
    '/detachRemoteProjectionsExcept/ { print NR; exit }')"
  resume_line="$(printf '%s\n' "${history_lifecycle_section}" | awk \
    '/automaticRuntime\.notifyAccountChanged/ { print NR; exit }')"
  if [ -z "${cancel_line}" ] || [ -z "${binding_line}" ] || [ -z "${detach_line}" ] || \
    [ -z "${resume_line}" ] || [ "${cancel_line}" -ge "${binding_line}" ] || \
    [ "${binding_line}" -ge "${detach_line}" ] || [ "${detach_line}" -ge "${resume_line}" ]; then
    fail "History account lifecycle must drain, normalize binding, detach stale projections, then resume scheduling"
  fi
  require_pattern "${COORDINATOR_REL}" \
    "boundAccountUid\.length <= 0 && accountUid\.length > 0" \
    "an enabled legacy History selection must be recognized as unbound"
  require_pattern "${COORDINATOR_REL}" \
    "setHistorySelected\(true, accountUid\)" \
    "an enabled legacy History selection must bind to the current supported Provider account"
  require_pattern "${RUNTIME_REL}" \
    "sync_experience_history_account_lifecycle" \
    "cold startup must reconcile the complete History account lifecycle"
  history_startup_section="$(sed -n "/id: 'history_repository'/,/id: 'recently_closed_repository'/p" \
    "${REPO_ROOT}/${RUNTIME_REL}")"
  repository_line="$(printf '%s\n' "${history_startup_section}" | awk \
    "/id: 'history_repository'/ { print NR; exit }")"
  lifecycle_line="$(printf '%s\n' "${history_startup_section}" | awk \
    "/id: 'sync_experience_history_account_lifecycle'/ { print NR; exit }")"
  if [ -z "${repository_line}" ] || [ -z "${lifecycle_line}" ] || \
    [ "${repository_line}" -ge "${lifecycle_line}" ]; then
    fail "cold-start History account lifecycle must run after the History repository is initialized"
  fi
  require_pattern "${RUNTIME_REL}" \
    "sharedSyncExperienceCoordinator\.reconcileHistoryAccountLifecycle\(\)" \
    "cold startup and account-change handling must reuse the Sync Experience lifecycle owner"
  if [ -n "${AIRA_PRIVATE_BACKEND_ROOT:-}" ]; then
    server_route_path="${AIRA_PRIVATE_BACKEND_ROOT%/}/src/routes/history-sync-routes.js"
    if [ ! -f "${server_route_path}" ]; then
      fail "missing private backend History route at ${server_route_path}"
    else
      if ! grep -Eq "const identity = parseHistoryVisitIdentity\(visitId\)" "${server_route_path}"; then
        fail "Aira Provider enrollment must preserve the canonical visit source identity"
      fi
      if ! grep -Eq "clientId: identity\.clientId" "${server_route_path}"; then
        fail "the server must derive a relayed visit's source client from its canonical visit ID"
      fi
      if grep -Eqi "normalizeVisit\(raw\.visit, clientId\)|visitId\.startsWith\(prefix\)" "${server_route_path}"; then
        fail "Aira Provider enrollment must not require the uploader to be the visit's source device"
      fi
    fi
  fi
  require_pattern "${VIEW_MODEL_REL}" \
    "historySelected: true" \
    "the initial Sync view must show History selected"
  if ! sed -n "/id: 'history'/,+5p" "${REPO_ROOT}/${FIRST_ITEMS_REL}" | grep -Eq "enabled: true"; then
    fail "first activation must default History to selected"
  fi
  require_pattern "${COORDINATOR_REL}" \
    "remoteKind !== 'webdav' && selection.historySelected" \
    "first WebDAV activation must persist History as unselected"
  require_pattern "${COORDINATOR_REL}" \
    "clearHistorySelectionForWebdav\(settings.remoteKind, initializedState\)" \
    "loading a persisted WebDAV configuration must repair a stale History selection"
  if ! sed -n "/runHistoryProviderTransitionWithinCurrentOperation/,/runProviderTransition<T>/p" \
    "${REPO_ROOT}/${AUTOMATIC_REL}" | grep -Eq "historySelected !== true"; then
    fail "switching away from WebDAV must leave History off until the user explicitly enables it"
  fi
  require_pattern "${SCREEN_REL}" \
    "isEnabled: this.state.historySupported" \
    "the History card must be disabled when the active Provider does not support it"
  reject_pattern "${SCREEN_REL}" \
    "历史记录同步位置|onHistoryProviderSelected|history-sync-provider" \
    "the Sync surface must not expose a separate History Provider selector"
  reject_pattern "${COORDINATOR_REL}" \
    "setHistoryProvider" \
    "the coordinator must not expose independent History Provider selection"
  reject_pattern "${REMOTE_REL}" \
    "AiraG7BookmarkRecords|HuaweiSpaceBookmarkChunkRepository|manifest|index shard" \
    "Huawei History must not reuse the Bookmark G7 logical format"
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "History Sync contract passed."

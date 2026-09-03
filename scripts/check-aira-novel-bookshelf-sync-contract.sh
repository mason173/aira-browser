#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  echo "Novel Bookshelf Sync contract violation: $1" >&2
  failures=$((failures + 1))
}

require_file() {
  if [ ! -f "${REPO_ROOT}/$1" ]; then
    fail "missing $1"
  fi
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

MODEL_REL="AiraBrowser/entry/src/main/ets/common/models/PersonalizationSyncModels.ets"
SYNC_MODEL_REL="AiraBrowser/entry/src/main/ets/common/models/AiraSyncModels.ets"
BOOKSHELF_MODEL_REL="AiraBrowser/entry/src/main/ets/common/models/NovelBookshelfSyncModels.ets"
BOOKSHELF_MODULE_REL="AiraBrowser/entry/src/main/ets/services/sync/NovelBookshelfSyncModule.ets"
BOOKSHELF_SNAPSHOT_REL="AiraBrowser/entry/src/main/ets/services/sync/NovelBookshelfSyncSnapshotService.ets"
BOOKSHELF_MERGE_REL="AiraBrowser/entry/src/main/ets/services/sync/NovelBookshelfSyncMergeService.ets"
BOOKSHELF_CONTROLLER_REL="AiraBrowser/entry/src/main/ets/features/novel/NovelBookshelfController.ets"
LIBRARY_MODEL_REL="AiraBrowser/entry/src/main/ets/features/novel/NovelLibraryModels.ets"
RULE_CATALOG_REL="AiraBrowser/entry/src/main/ets/services/novel/NovelRuleCatalog.ets"
CHECKPOINT_REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/novel/NovelReadingCheckpointRepository.ets"
PERSONALIZATION_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncService.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
HUAWEI_OWNER_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceRdbStoreOwner.ets"
AIRA_BOOKMARK_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraCloudBookmarkRemoteStore.ets"
AIRA_PERSONALIZATION_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraCloudPersonalizationRemoteStore.ets"
AIRA_NOVEL_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraCloudNovelBookshelfRemoteStore.ets"
WEBDAV_BOOKMARK_STORE_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraWebdavRemoteStore.ets"
WEBDAV_PERSONALIZATION_STORE_REL="AiraBrowser/entry/src/main/ets/data/sync/WebdavPersonalizationSyncStore.ets"
WEBDAV_NOVEL_STORE_REL="AiraBrowser/entry/src/main/ets/data/sync/WebdavNovelBookshelfSyncStore.ets"
AIRA_TRANSPORT_REL="AiraBrowser/entry/src/main/ets/services/sync/AiraCloudConditionalSnapshotRemoteStore.ets"
WEBDAV_TRANSPORT_REL="AiraBrowser/entry/src/main/ets/data/sync/WebdavConditionalJsonSnapshotStore.ets"
HUAWEI_TRANSPORT_REL="AiraBrowser/entry/src/main/ets/data/sync/HuaweiSpaceConditionalSnapshotStore.ets"
ADR_REL="docs/adr/0063-novel-bookshelf-is-an-independent-personalization-companion.md"
PRIVATE_BACKEND_ROOT="${AIRA_PRIVATE_BACKEND_ROOT:-}"

for rel_path in "${MODEL_REL}" "${SYNC_MODEL_REL}" "${BOOKSHELF_MODEL_REL}" "${BOOKSHELF_MODULE_REL}" \
  "${BOOKSHELF_SNAPSHOT_REL}" "${BOOKSHELF_MERGE_REL}" "${BOOKSHELF_CONTROLLER_REL}" \
  "${LIBRARY_MODEL_REL}" "${RULE_CATALOG_REL}" "${AIRA_TRANSPORT_REL}" "${WEBDAV_TRANSPORT_REL}" \
  "${HUAWEI_TRANSPORT_REL}" "${CHECKPOINT_REPOSITORY_REL}" \
  "${PERSONALIZATION_SERVICE_REL}" "${RUNTIME_REL}" "${HUAWEI_OWNER_REL}" \
  "${AIRA_BOOKMARK_STORE_REL}" "${AIRA_PERSONALIZATION_STORE_REL}" "${AIRA_NOVEL_STORE_REL}" \
  "${WEBDAV_BOOKMARK_STORE_REL}" "${WEBDAV_PERSONALIZATION_STORE_REL}" "${WEBDAV_NOVEL_STORE_REL}" \
  "${ADR_REL}"; do
  require_file "${rel_path}"
done

if [ "${failures}" -eq 0 ]; then
  item_block="$(awk '
    /export const PERSONALIZATION_SYNC_ITEM_IDS/ { capture = 1 }
    capture { print }
    capture && /];/ { exit }
  ' "${REPO_ROOT}/${MODEL_REL}")"
  for item_id in home_shortcuts core_preferences activity_heatmap search; do
    item_count="$(printf '%s\n' "${item_block}" | grep -Ec "'${item_id}'" || true)"
    if [ "${item_count}" -ne 1 ]; then
      fail "PERSONALIZATION_SYNC_ITEM_IDS must contain ${item_id} exactly once"
    fi
  done
  if printf '%s\n' "${item_block}" | grep -q "novel_bookshelf"; then
    fail "novel_bookshelf must remain outside the exact-four G2 item array"
  fi

  require_pattern "${MODEL_REL}" \
    "PersonalizationSyncContentId = PersonalizationSyncItemId \\| 'novel_bookshelf'" \
    "the fifth UI selection must use the separate PersonalizationSyncContentId"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" "NovelBookshelfSyncModule" \
    "PersonalizationSyncService must remain the companion orchestration owner"
  require_pattern "${RUNTIME_REL}" "origin === 'local'" \
    "only local Novel Library mutations may trigger automatic companion sync"
  require_pattern "${RUNTIME_REL}" "sharedNovelReadingCheckpointRepository" \
    "the reader and companion must share one serialized checkpoint repository"
  require_pattern "${CHECKPOINT_REPOSITORY_REL}" "mutationTask" \
    "checkpoint read-modify-write operations must remain serialized"
  require_pattern "${HUAWEI_OWNER_REL}" "HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE" \
    "the shared Huawei RDB owner must register the independent Bookshelf table"
  require_pattern "${HUAWEI_OWNER_REL}" \
    "HUAWEI_SPACE_BOOKMARK_HEAD_TABLE: string = 'AiraG8BookmarkHeads'" \
    "Huawei Bookmark must keep its dedicated G8 Head table"
  require_pattern "${HUAWEI_OWNER_REL}" \
    "HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE: string = 'AiraG8BookmarkBlocks'" \
    "Huawei Bookmark must keep its dedicated G8 Block table"
  require_pattern "${HUAWEI_OWNER_REL}" \
    "HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE: string = 'AiraG2PersonalizationCommits'" \
    "Huawei Personalization must retain its dedicated commit table"
  require_pattern "${HUAWEI_OWNER_REL}" \
    "HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE: string = 'AiraG2NovelBookshelfCommits'" \
    "Huawei Novel Bookshelf must retain its dedicated commit table"
  require_pattern "${AIRA_BOOKMARK_STORE_REL}" \
    "AIRA_HOSTED_API_BASE_URL" \
    "Aira Bookmark must resolve through the distribution-owned hosted API base URL"
  require_pattern "${AIRA_BOOKMARK_STORE_REL}" \
    "'/sync/v4/bookmarks'" \
    "Aira Bookmark must retain its independent v4 endpoint path"
  require_pattern "${AIRA_PERSONALIZATION_STORE_REL}" \
    "AIRA_HOSTED_API_BASE_URL" \
    "Aira Personalization must resolve through the distribution-owned hosted API base URL"
  require_pattern "${AIRA_PERSONALIZATION_STORE_REL}" \
    "'/sync/v2/personalization'" \
    "Aira Personalization must retain its independent endpoint path"
  require_pattern "${AIRA_NOVEL_STORE_REL}" \
    "AIRA_HOSTED_API_BASE_URL" \
    "Aira Novel Bookshelf must resolve through the distribution-owned hosted API base URL"
  require_pattern "${AIRA_NOVEL_STORE_REL}" \
    "'/sync/v2/personalization/novel-bookshelf'" \
    "Aira Novel Bookshelf must retain its independent endpoint path"
  require_pattern "${SYNC_MODEL_REL}" \
    "AIRA_SYNC_DEFAULT_ROOT: string = 'aira/g3/bookmarks'" \
    "WebDAV Bookmark must retain its independent g3 root"
  require_pattern "${WEBDAV_BOOKMARK_STORE_REL}" \
    "BOOKMARK_WEBDAV_SNAPSHOT_FILE: string = 'snapshot\\.json'" \
    "WebDAV Bookmark must retain its dedicated snapshot file"
  require_pattern "${WEBDAV_PERSONALIZATION_STORE_REL}" \
    "PERSONALIZATION_WEBDAV_FILE: string = .*PERSONALIZATION_WEBDAV_ROOT.*/snapshot\\.json" \
    "WebDAV Personalization must retain its dedicated snapshot file"
  require_pattern "${WEBDAV_NOVEL_STORE_REL}" \
    "NOVEL_BOOKSHELF_WEBDAV_FILE: string = .*NOVEL_BOOKSHELF_WEBDAV_ROOT.*/novel-bookshelf\\.json" \
    "WebDAV Novel Bookshelf must retain its dedicated snapshot file"
  require_pattern "${BOOKSHELF_SNAPSHOT_REL}" "isValidNovelHttpUrl" \
    "portable Bookshelf URLs must require a non-empty HTTP authority"
  require_pattern "${BOOKSHELF_MODEL_REL}" "NOVEL_BOOKSHELF_SYNC_SCHEMA_VERSION: number = 2" \
    "the reading-progress companion must remain on schema version 2"
  require_pattern "${BOOKSHELF_MODEL_REL}" "NovelBookshelfSyncReadingProgress" \
    "the companion must keep reading progress on its independent merge clock"
  require_pattern "${BOOKSHELF_MERGE_REL}" \
    "NovelBookshelfSyncMergeIntent = 'ordinary' \| 'provider-switch'" \
    "Novel Bookshelf merge must distinguish ordinary sync from Provider switching"
  require_pattern "${BOOKSHELF_MERGE_REL}" \
    "tombstone.*intent !== 'provider-switch'" \
    "Novel Bookshelf Provider switching must preserve a live Book against an opposing tombstone"
  require_pattern "${BOOKSHELF_MODULE_REL}" \
    "mergeIntent: NovelBookshelfSyncMergeIntent = 'ordinary'" \
    "Novel Bookshelf orchestration must default to ordinary deletion propagation"
  require_pattern "${BOOKSHELF_MODULE_REL}" \
    "const confirmedState = await this.confirmRemoteSnapshot" \
    "Novel Bookshelf writes must receive a complete remote read-back"
  require_pattern "${BOOKSHELF_MODULE_REL}" \
    "await this.repository.applySyncedBookshelf" \
    "Novel Bookshelf local apply must remain explicit"
  require_pattern "${BOOKSHELF_MODULE_REL}" \
    "await this.stateStore.saveLineage" \
    "Novel Bookshelf lineage advancement must remain explicit"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" \
    "const confirmedState = await this.confirmRemoteSnapshot" \
    "Personalization writes must receive a complete remote read-back"
  require_pattern "${PERSONALIZATION_SERVICE_REL}" "mergeIntent" \
    "Personalization Provider switching must pass its merge intent to the Novel companion"
  require_pattern "${BOOKSHELF_SNAPSHOT_REL}" "readingProgress" \
    "the companion checksum and validation must include reading progress"
  require_pattern "${BOOKSHELF_CONTROLLER_REL}" "sharedNovelRuleCatalog" \
    "the local Novel Rule Catalog must own Bookshelf classification"
  require_pattern "${BOOKSHELF_CONTROLLER_REL}" "resolveContentKind" \
    "the Bookshelf controller must project locally recognized comics"
  require_pattern "${RULE_CATALOG_REL}" "resolveContentKind\(url: string\): 'novel' \| 'comic'" \
    "the Novel Rule Catalog must expose local content classification"
  require_pattern "${RULE_CATALOG_REL}" "resolveBundledNovelSiteRule\(url\).*kind === 'comic'" \
    "unknown Bookshelf URLs must fall back through bundled rules and then to novels"
  require_pattern "${LIBRARY_MODEL_REL}" "novels: NovelBookshelfBook\[\]" \
    "the Bookshelf state must expose an explicit novel projection"
  require_pattern "${LIBRARY_MODEL_REL}" "comics: NovelBookshelfBook\[\]" \
    "the Bookshelf state must expose an explicit comic projection"
  if [ -n "${PRIVATE_BACKEND_ROOT}" ]; then
    server_route_path="${PRIVATE_BACKEND_ROOT%/}/src/routes/novel-bookshelf-sync-routes.js"
    server_migration_path="${PRIVATE_BACKEND_ROOT%/}/migrations/022_novel_bookshelf_sync_v2.sql"
    server_app_path="${PRIVATE_BACKEND_ROOT%/}/src/app.js"
    for file_path in "${server_route_path}" "${server_migration_path}" "${server_app_path}"; do
      if [ ! -f "${file_path}" ]; then
        fail "missing private backend file ${file_path}"
      fi
    done
    if [ -f "${server_route_path}" ]; then
      if ! grep -Eq "NOVEL_BOOKSHELF_SYNC_SCHEMA_VERSION = 2" "${server_route_path}"; then
        fail "the Aira server companion must remain on schema version 2"
      fi
      if ! grep -Eq "canonicalizeReadingProgress" "${server_route_path}"; then
        fail "the Aira server must strictly validate portable reading progress"
      fi
      if ! grep -Eq "novel_bookshelf_sync_write_conflict" "${server_route_path}"; then
        fail "the Aira companion write path must enforce revision CAS"
      fi
      if grep -Eqi "contentKind|paragraph|chapterBody|catalogEntries|synopsis|category|latestChapter|palette|imageBytes" \
        "${server_route_path}"; then
        fail "the Aira server companion contract must not accept local classification, chapter bodies, rich metadata, or cover bytes"
      fi
    fi
    if [ -f "${server_app_path}" ] && ! grep -Eq "/sync/v2/personalization/novel-bookshelf/(read|write)" \
      "${server_app_path}"; then
      fail "the independent Aira companion endpoints must remain routed"
    fi
    if [ -f "${server_migration_path}" ] && ! grep -Eq "novel_bookshelf_sync_states_v2" \
      "${server_migration_path}"; then
      fail "the companion must use an independent Aira server table"
    fi
  fi
  require_pattern "${ADR_REL}" "live Book wins over an opposing tombstone" \
    "ADR-0063 must record live Book preservation during Provider switching"
  require_pattern "${ADR_REL}" "ordinary same-Provider" \
    "ADR-0063 must preserve ordinary explicit-deletion propagation"
  require_pattern "${ADR_REL}" \
    "complete remote read-back" \
    "ADR-0063 must require complete read-back before apply or lineage advancement"

  for rel_path in "${LIBRARY_MODEL_REL}" "${BOOKSHELF_MODEL_REL}" "${BOOKSHELF_SNAPSHOT_REL}" \
    "${BOOKSHELF_MERGE_REL}"; do
    reject_pattern "${rel_path}" "contentKind" \
      "novel/comic classification must remain local and outside persisted or portable Bookshelf records"
  done

  reject_pattern "${BOOKSHELF_MODEL_REL}" \
    "paragraph|chapterBody|catalog|synopsis|category|latestChapter|palette|imageBytes" \
    "portable Bookshelf models must not contain chapter bodies, catalogs, rich metadata, palettes, or image bytes"
  reject_pattern "AiraBrowser/entry/src/main/ets/services/sync/AiraCloudNovelBookshelfRemoteStore.ets" \
    "as Object as|AiraCloudPersonalizationRemoteStore" \
    "the Aira Bookshelf adapter must remain strongly typed and provider-neutral"
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Novel Bookshelf Sync contract passed."

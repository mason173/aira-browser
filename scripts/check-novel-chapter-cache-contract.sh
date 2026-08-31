#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/features/novel/NovelReaderModels.ets"
CONTROLLER="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/features/novel/NovelReaderController.ets"
REPOSITORY="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/data/novel/NovelChapterArtifactCacheRepository.ets"
CATALOG_REPOSITORY="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/data/novel/NovelCatalogCacheRepository.ets"
CATALOG_ENGINE="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/services/novel/NovelCatalogPageAcquisitionEngine.ets"
EXTRACTION="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/services/novel/NovelExtractionService.ets"
SITE_RULES="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/features/novel/NovelSiteRules.ets"
RULE_CATALOG="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/services/novel/NovelRuleCatalog.ets"
CATALOG_SHEET="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components/browser/NovelReaderCatalogSheet.ets"
NOVEL_OVERLAY="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components/browser/NovelReaderOverlay.ets"
IDENTITY="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/services/novel/NovelSourceIdentityService.ets"
OPEN_CENTER="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/features/novel/NovelBookshelfOpenRequestCenter.ets"
BOOKSHELF_PAGE="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages/NovelBookshelfPage.ets"
WINDOW_RUNTIME="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/runtime/BrowserWindowRuntime.ets"
COMPOSITION="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/BrowserWindowSessionApplication.ets"

failures=0

contains_text() {
  local file="$1"
  local text="$2"

  grep -F -q -- "${text}" "${file}"
}

first_line_number() {
  local file="$1"
  local text="$2"
  local match

  match="$(grep -F -n -- "${text}" "${file}" 2>/dev/null | sed -n '1p' || true)"
  printf '%s' "${match%%:*}"
}

require_text() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! contains_text "${file}" "${text}"; then
    echo "Novel Chapter Cache contract failure: ${message}" >&2
    failures=$((failures + 1))
  fi
}

require_text "${MODELS}" "export interface NovelChapterArtifactCachePort" \
  "the typed Chapter artifact persistence seam is missing."
require_text "${MODELS}" "readLatestForBook(detailUrl: string)" \
  "Bookshelf repeat-open can no longer resolve its recent cached Chapter."
require_text "${MODELS}" "markLatestForBook(value: NovelChapterArtifactCacheRecord)" \
  "cache-hit Chapter selection can no longer advance the Book's recent-Chapter reference."
require_text "${MODELS}" "catalogLoadingMore: boolean;" \
  "incremental Catalog loading can no longer preserve the visible Catalog surface."
require_text "${MODELS}" "ordinal: number;" \
  "Catalog metadata no longer preserves stable Chapter ordinals for sparse ranges."
require_text "${MODELS}" "catalogSupportsRandomAccess: boolean;" \
  "Catalog presentation can no longer distinguish random range paging from sequential fallback."
require_text "${MODELS}" "catalogRangeExtentHint: number;" \
  "Catalog presentation can no longer expose unloaded range groups from a trusted extent hint."
require_text "${MODELS}" "type: 'load_catalog_range';" \
  "an expanded Catalog range no longer reaches the Novel Session owner as a typed demand."
require_text "${SITE_RULES}" "catalogPageSource?: NovelCatalogPageSourceRule;" \
  "compiled paged-Catalog transports are no longer typed separately from packaged selectors."
require_text "${RULE_CATALOG}" "return this.isBlocked(url) ? undefined : resolveBundledNovelSiteRule(url);" \
  "Novel Rule resolution must remain package-owned and preserve bundled Book identity scope."
require_text "${SITE_RULES}" "id: 'site.mayitxt'" \
  "the complete package-owned Novel Rule catalog is missing site.mayitxt."
require_text "${SITE_RULES}" "id: 'site.trxsw'" \
  "the complete package-owned Novel Rule catalog is missing site.trxsw."
require_text "${SITE_RULES}" "id: 'site.80ge'" \
  "the complete package-owned Novel Rule catalog is missing site.80ge."
require_text "${SITE_RULES}" "pathPrefixes: ['/novel/', '/dir/']" \
  "site.80dzs must authorize both detail/Chapter and Catalog routes in the package-owned catalog."
require_text "${SITE_RULES}" "pathPrefixes: ['/video/', '/bangumi/play/']" \
  "the package-owned Bilibili exclusion must remain path-scoped instead of blocking the whole site."
require_text "${SITE_RULES}" "pathPrefixes: ['/v_', '/a_', '/w_', '/play/', '/lib/m_']" \
  "the package-owned iQIYI exclusion must remain path-scoped instead of blocking the whole site."
require_text "${CATALOG_ENGINE}" "export class NovelCatalogPageAcquisitionEngine" \
  "typed same-origin Catalog pagination no longer has a subordinate acquisition engine."
require_text "${REPOSITORY}" "implements NovelChapterArtifactCachePort" \
  "the persistent adapter no longer satisfies the Chapter cache interface."
require_text "${REPOSITORY}" "AppRuntimeContext.getApplicationContext().filesDir" \
  "Chapter artifacts are no longer stored in the durable app sandbox."
require_text "${REPOSITORY}" "await fileIo.fsync(file.fd)" \
  "Chapter artifact writes no longer flush the temporary file before replacement."
require_text "${REPOSITORY}" "refreshRecommended:" \
  "stale-while-revalidate freshness is missing from cache reads."
require_text "${REPOSITORY}" "result = await this.readLatestForBookNow(detailUrl);" \
  "Bookshelf reads must stay inside the repository operation tail."
require_text "${REPOSITORY}" "await this.writeBookReferenceNow(normalized);" \
  "cache-hit recent-reference mutations are no longer serialized by the repository."
require_text "${REPOSITORY}" "NOVEL_CHAPTER_CACHE_MAX_ARTIFACTS: number = 256" \
  "the bounded Chapter-count quota changed without an architecture decision."
require_text "${REPOSITORY}" "NOVEL_CHAPTER_CACHE_MAX_TOTAL_BYTES: number = 96 * 1024 * 1024" \
  "the bounded Chapter-byte quota changed without an architecture decision."
require_text "${IDENTITY}" "export class NovelSourceIdentityService" \
  "source-scoped Book and Chapter identity no longer has one owner."
require_text "${CONTROLLER}" "return scope.privacyMode === 'regular' && scope.dataScope === 'profile_persistent';" \
  "persistent Chapter caching is no longer explicitly limited to regular profile scope."
require_text "${CONTROLLER}" "this.createChapterExtractFromArtifact(cached.artifact)" \
  "cache hits no longer pass through the existing Chapter commit path."
require_text "${CONTROLLER}" "session.chapterTransition.status !== 'idle'" \
  "stale refresh can no longer prove that it will not supersede a newer Chapter request."
require_text "${CONTROLLER}" "this.markChapterArtifactAsLatest(cached.artifact);" \
  "a committed cache hit no longer advances the Book's recent-Chapter reference."
require_text "${CONTROLLER}" "await this.chapterArtifactCacheRepository.readLatestForBook(request.pageUrl)" \
  "an exact Book detail entry can no longer reuse its recent cached Chapter."
require_text "${CONTROLLER}" "scheduleNextChapterPrefetch(" \
  "a committed Chapter no longer schedules the bounded one-Chapter lookahead."
require_text "${CONTROLLER}" "next.catalogLoadingMore = true;" \
  "a Catalog range request can no longer publish a non-blocking loading state."
require_text "${CONTROLLER}" "loadCatalogRange(" \
  "the Novel Session owner no longer owns explicit Catalog range acquisition."
require_text "${CONTROLLER}" "requestDefaultCatalogRangeHydration(" \
  "the default expanded 1-100 range is no longer hydrated by the Novel Session owner."
require_text "${CONTROLLER}" "firstPageNumber: number = cursor.initialPage + Math.floor(startOrdinal / cursor.pageSize)" \
  "a random-access Catalog range can no longer jump directly to its first source page."
require_text "${CONTROLLER}" "const freshnessOnly: NovelChapterArtifactCacheRecord" \
  "unchanged stale refresh no longer limits persistence to the accepted artifact plus freshness time."
require_text "${CATALOG_REPOSITORY}" "mergeEntries(existing.entries, normalized.entries)" \
  "sparse Catalog ranges are no longer merged before persistent replacement."
require_text "${EXTRACTION}" "maximumEntries: number" \
  "generic Catalog acquisition no longer has a bounded metadata window."
require_text "${CATALOG_SHEET}" "toggleCatalogRange(" \
  "the reader Catalog no longer exposes collapsible 100-Chapter ranges."
require_text "${CATALOG_SHEET}" "this.onLoadRange(startOrdinal, endOrdinal);" \
  "expanding a reader Catalog range no longer requests exactly that range."
require_text "${CATALOG_SHEET}" "@State private expandedCatalogRangeStarts: number[] = [0];" \
  "the reader Catalog no longer expands 1-100 by default."
require_text "${NOVEL_OVERLAY}" "toggleBookCatalogRange(" \
  "the Book takeover Catalog no longer exposes collapsible 100-Chapter ranges."
require_text "${NOVEL_OVERLAY}" "type: 'load_catalog_range'" \
  "the Book takeover range expansion no longer forwards typed demand."
require_text "${NOVEL_OVERLAY}" "@State private expandedBookCatalogRangeStarts: number[] = [0];" \
  "the Book takeover Catalog no longer expands 1-100 by default."
require_text "${OPEN_CENTER}" "book: cloneNovelBookshelfBook(book)" \
  "Bookshelf open no longer carries persisted Book context to the Novel owner."
require_text "${WINDOW_RUNTIME}" "requestNovelBookshelfTakeover(book);" \
  "the Bookshelf open action no longer publishes the selected Book context."
require_text "${BOOKSHELF_PAGE}" "BrowserWindowRuntime.openNovelBookshelfBook(book)" \
  "Bookshelf repeat-open no longer starts cache hydration before Web navigation completes."
require_text "${CONTROLLER}" "openBookshelfFromPersistentCache(" \
  "the Novel Session owner no longer exposes the native Bookshelf cache-open entry point."
require_text "${COMPOSITION}" "options.chapterArtifactCacheRepository = sharedNovelChapterArtifactCacheRepository;" \
  "Browser Window Session composition no longer injects the persistent Chapter cache."

cache_read_line="$(first_line_number "${CONTROLLER}" \
  'await this.chapterArtifactCacheRepository.readChapter(')"
network_fetch_line="$(first_line_number "${CONTROLLER}" \
  'await this.extractionService.fetchChapter(')"
if [ -z "${cache_read_line}" ] || [ -z "${network_fetch_line}" ] ||
  [ "${cache_read_line}" -ge "${network_fetch_line}" ]; then
  echo "Novel Chapter Cache contract failure: loadChapterByUrl must read cache before network fetch." >&2
  failures=$((failures + 1))
fi

bookshelf_cache_line="$(first_line_number "${WINDOW_RUNTIME}" \
  'await session.openNovelBookshelfFromPersistentCache({')"
bookshelf_takeover_line="$(first_line_number "${WINDOW_RUNTIME}" \
  'requestNovelBookshelfTakeover(book);')"
bookshelf_navigation_line="$(first_line_number "${WINDOW_RUNTIME}" \
  'router.back({')"
if [ -z "${bookshelf_cache_line}" ] || [ -z "${bookshelf_takeover_line}" ] ||
  [ -z "${bookshelf_navigation_line}" ] ||
  [ "${bookshelf_cache_line}" -ge "${bookshelf_takeover_line}" ] ||
  [ "${bookshelf_takeover_line}" -ge "${bookshelf_navigation_line}" ]; then
  echo "Novel Chapter Cache contract failure: Bookshelf cache hydration must precede takeover publication and Web navigation." >&2
  failures=$((failures + 1))
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Novel Chapter Cache contract passed."

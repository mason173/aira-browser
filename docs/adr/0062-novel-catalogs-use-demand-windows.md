---
status: accepted
---

# Novel Catalogs Use Demand Ranges

## Context

Some Novel detail pages expose thousands of Chapter titles, while others expose only a 10-entry preview backed by a
numbered same-origin endpoint. Waiting for a complete Catalog delays first reading, and treating a short preview as a
replacement can erase a previously useful Catalog snapshot. Catalog metadata and Chapter body acquisition also have
different costs and must not share one eager loading policy.

## Decision

`NovelReaderController` remains the Novel Session narrative owner. It publishes any validated inline or persisted
Catalog immediately. Both Catalog surfaces group metadata into fixed 100-Chapter ranges (`1-100`, `101-200`, and so
on). The first range is expanded by default: already available titles render immediately, then the owner asynchronously
fills the remainder of `1-100` when the Web runtime is available. A temporarily unavailable runtime keeps this as a
pending owner operation instead of turning a cache hit into a failed Catalog surface. Later ranges stay collapsed and
issue no network request until expansion. Expanding one of them sends a typed `load_catalog_range` demand containing
only that range's zero-based start and end ordinals. Existing titles remain interactive while that range shows its own
loading state.

Catalog persistence contains only Book identity, Catalog URL, sparse Chapter ordinal/title/URL metadata, completeness,
total hint, freshness, and an optional opaque page cursor. Writes are monotonic: a late shorter partial snapshot cannot
replace a longer or complete snapshot, and disjoint loaded ranges are merged before atomic replacement. Existing
version-1 cache entries without an ordinal retain their prior array index as the stable ordinal. The cursor stores only
stable rule ID, same-origin Book token, initial/request page, page size, and total hints. Endpoint paths, query recipes,
response schema, headers, cookies, and executable code are never persisted.

`NovelExtractionService` remains the acquisition owner. Its subordinate `NovelCatalogPageAcquisitionEngine` may execute
only typed recipes compiled into `NovelSiteRules`. Cloud Novel rules cannot author Catalog transports. A remote override
may inherit a compiled transport only when stable rule ID and complete host/path scope exactly match the bundled rule,
preserving ADR-0057. Wuxianbook uses its DOM `data-bookid` token and same-origin numbered JSON pages. Wuxianbook maps an
expanded range directly to source pages, so `901-1000` requests pages 90-99 and never fetches `1-900`. A source without a
verified random-access recipe exposes only already loaded groups plus its next sequential group and may repeat bounded
prefix work through the existing extractor.

The Book surface and reader Catalog sheet render only expanded groups. A Reading Checkpoint or recent Chapter artifact
may resume a Chapter outside the loaded Catalog ranges; reading never waits for a range to contain the resumed Chapter.
Sparse navigation uses stable ordinals, so a distant loaded range cannot become the apparent next Chapter after a gap.

Catalog loading never fetches Chapter bodies. Chapter bodies remain cache-first/on-demand with only the single immediate
lookahead defined by ADR-0061.

## Identity

A bundled site rule that participates in remote override defines the complete stable route scope used by Book identity.
For 80dzs that scope contains `/novel/` detail/Chapter routes and the `/dir/` Catalog route. A narrower remote entry is
rejected by the existing exact-scope inheritance contract, so selector refresh timing cannot alternate one Book between
detail-derived and Catalog-derived identities.

## Consequences

- A 1600-Chapter Book becomes readable from its first available titles instead of a 169-page precondition.
- `1-100` is immediately visible and progressively filled; `101-200` and later ranges remain demand-only.
- Resume and next-Chapter reading depend on Chapter identity and adjacent links, not complete Catalog hydration.
- Catalog counts are total hints until completion; range loading never blocks already cached titles.
- No `BrowserShellPage.ets`, Window-Open/BFCache, tab/runtime lifecycle, or frozen Sync change is required.

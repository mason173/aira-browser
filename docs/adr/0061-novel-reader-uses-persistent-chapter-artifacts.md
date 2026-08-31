---
status: accepted
---

# Novel Reader Uses Persistent Chapter Artifacts

The Novel Reading Session may reuse a previously validated normalized Chapter artifact before any network or DOM
acquisition. This is a persistent cache for ordinary profile reading, not a second reading owner and not an archive of
raw Web content. A cached artifact contains the source-scoped Book and Chapter identities, canonical/request/final URLs,
title, normalized paragraphs, image URLs, adjacent Chapter and Catalog URLs, and cache timestamp. It never stores page
HTML, JavaScript, cookies, request headers, account data, or downloaded image binaries.

`NovelReaderController` remains the narrative owner. Every cache hit enters the existing
`NovelReadingSessionState.beginChapterTransition -> commitChapter` gate, so session generation, tab, privacy boundary,
Book identity, Chapter identity, transition intent, canonical content, and stale-request rejection stay authoritative.
The persistent repository is a subordinate adapter and cannot publish reader state itself. Network/DOM results are
persisted only after the same Session commit accepts them.

## Cache-first contract

- Regular `profile_persistent` reading checks the Chapter artifact repository before `fetchChapter`. A valid hit is
  committed immediately, including when the live Web runtime is temporarily unavailable.
- Private and `session_ephemeral` reading never read or write the persistent Chapter cache.
- Cache age never makes a validated artifact unusable. After six hours it remains the first render and only recommends a
  silent background refresh. A failed refresh preserves the visible artifact and does not turn the successful cache hit
  into a reader error.
- A changed stale result may replace the current artifact only while the same Session generation, Book, active Chapter,
  Web controller, runtime, and idle Chapter-transition state are still current. A newer user Chapter request always wins.
  An unchanged result only advances the persisted freshness timestamp.
- Bookshelf open carries the selected persisted Book metadata to the Novel owner. The repository's per-Book recent-
  Chapter reference can therefore hydrate the last cached Chapter before the underlying Web navigation completes,
  without waiting for page classification or overview extraction. This native Bookshelf-to-Reader transition is staged
  in a candidate Controller, so a miss or rejected artifact preserves the previous Session and falls back to the existing
  detection/acquisition path.
- Direct opens of an exact cached canonical Chapter URL may use the same cache-first path. Other Web URLs still run the
  conservative Novel detector.
- After Chapter N commits in regular `profile_persistent` scope, the Controller may schedule exactly one low-priority
  lookahead for the resolved Chapter N+1. The lookahead first checks the same repository, uses the normal extraction and
  identity-quality gates on a miss, writes only a normalized artifact, and never advances the Book's recent-Chapter
  reference. A user Chapter request may await an already matching lookahead instead of starting a duplicate request.
- A lookahead result is discarded unless Session generation, Book, active Chapter, target URL, Web controller/runtime,
  privacy/data scope, and idle Chapter-transition state still match. Jumping Chapters, replacing/closing/suspending the
  Session, crossing privacy scope, or replacing the runtime invalidates it. Lookahead never chains from N+1 to N+2.

## Persistence and bounds

`NovelChapterArtifactCacheRepository` stores versioned JSON documents under the application `filesDir`. It uses one
content file per canonical Chapter URL and one small recent-Chapter reference per Book detail URL. Writes go to a unique
temporary file, verify full length, call `fsync`, and replace through a recoverable backup before publishing the final
path. All reads, reference updates, content writes, and pruning are serialized through one repository-owned operation
tail, so a reader cannot delete a newer reference published by a concurrent writer. Reads reject and remove unsupported,
oversized, corrupt, identity-inconsistent, or content-empty documents. A committed cache hit advances only the small
per-Book recent-Chapter reference; it does not rewrite the Chapter body or make stale content appear freshly validated.

The cache is bounded to 256 Chapter artifacts, 500 Book references, 96 MiB total Chapter bytes, and 4 MiB per Chapter.
Oldest written artifacts are removed first. A dangling Book reference is removed on read. Images remain URL-backed in
this decision; binary media caching would need its own quota, privacy, expiry, and authorization design.

This cache is populated only by Chapters the user opens and the single immediate lookahead above. Catalog acquisition
stores titles and canonical URLs only; it never starts an all-Book Chapter-body crawl.

## Identity and ownership

`NovelSourceIdentityService` is the single owner of source URL, Book, Chapter, and authority normalization used by both
the Session owner and the persistent adapter. Cache validation must not reimplement or weaken these identities.

This decision does not add Chapter artifacts to the Bookshelf Preferences document, Reading Checkpoint, Recovery Marker,
Bookmark/Personalization Sync, Additional Backup, Huawei Space, WebDAV, or Aira Cloud. Removing a Book from Bookshelf
does not synchronously scan or rewrite the bounded cache. Clearing app data or uninstalling removes the cache through the
normal HarmonyOS sandbox lifecycle.

No `BrowserShellPage.ets`, Window-Open/BFCache, tab/runtime lifecycle, or frozen Sync contract changes are authorized or
required by this ADR.

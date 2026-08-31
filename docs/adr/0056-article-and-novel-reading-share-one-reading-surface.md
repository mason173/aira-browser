# Article and Novel Reading Share One Reading Surface

Accepted: 2026-07-28

## Context

Aira currently has separate Article Reader Mode and Novel Mode renderers. Article recognition and acquisition preserve
rich document structure such as headings, images, links, quotes, lists, and code, while Novel recognition and acquisition
own Book, Chapter, Catalog, continuous Chapter trails, checkpoints, and comic classification. These source semantics are
genuinely different and must not be merged.

The two modes nevertheless duplicate the same reading experience: typography, themes, page width, brightness, gestures,
progress presentation, horizontal paging, and vertical scrolling. Reusing `NovelReaderController` or converting an
Article into a Novel would create the wrong seam: the Novel path accepts text-oriented Chapter content, owns Novel-only
navigation, and may classify image-heavy content as comic. A multi-image Article must remain an Article, and Article
rich-content behavior must not be lost merely to reuse presentation.

## Decision

Article Reader Mode and Novel Mode retain separate recognition, acquisition, and semantic sessions but share one
source-independent **Reading Surface**. The Reading Surface owns reading presentation and ArkUI execution; it does not
identify the source, infer Article, Novel, or comic meaning, persist reading truth, or decide source-specific navigation.

The ownership flow is:

```text
Online/Offline Article Acquisition -> Article Reading Session --\
                                                          Reading Document -> Reading Surface
Novel/Chapter/Comic Acquisition   -> Novel Reading Session ---/
```

The window-scoped **Article Reading Session** owns the acquired Article, Article-specific capabilities, search and speech
state, image-preview intent, and stale-result rejection. Online ArkWeb content and offline HTML remain
distinct Article acquisition sources.

The existing **Novel Reading Session** remains the owner of Novel detection and acquisition, Book, Chapter, the loaded
Chapter trail, Catalog navigation, Novel behavior preferences, checkpoints, stale-result rejection, and explicit comic
classification. ADR-0055 remains authoritative for its window lifetime and relationship with Browser Window Session.

Each semantic session adapts its current readable content into a source-independent **Reading Document**. Reading
Document preserves ordered rich-content identity and the semantics required for paragraphs, headings, images, links,
quotes, lists, and code. It contains no Book, Chapter, Catalog, Article-acquisition, or comic-classification truth. Article
content must not be flattened into the existing Novel text-array model.

### Reading presentation

The Reading Surface provides three presentation modes for both Articles and Novels: horizontal paging, fast horizontal
paging, and vertical scrolling. Articles default to vertical scrolling on first use; later Article behavior choices remain
independent from Novel behavior choices.

Pagination preserves content structure ahead of filling every page. A heading should stay with following content where
practical, images remain atomic and retain their captions, and quotes, lists, and code preserve their semantics when
split. A page may contain unused space rather than reorder, flatten, or discard content.

Long Reading Documents become readable after the initial content is laid out and paginate progressively. A pending final
page count is presented as unfinished rather than estimated as fact. Layout invalidation caused by typography, page
width, or window geometry preserves the current Reading Anchor and recomputes only the affected presentation.

The Reading Surface may provide a continuous-image presentation, but only the Novel Reading Session may explicitly
select it after Novel comic classification. Article image count never implies comic content.

### Capabilities and chrome

The Reading Surface presents only capabilities declared by its owning reading session. Shared presentation includes the
reading canvas, the basic top and bottom chrome shape, progress and settings entry, appearance controls, reading-mode
selection, gestures, and immersive behavior.

Reading gestures and edge physics remain local to the Reading Surface. It does not publish frame-by-frame scroll deltas
to a semantic session, and a session must not change system-bar visibility, Chrome mounting, or content geometry while a
drag, fling, or spring edge effect is in progress. Article and Novel Chrome visibility changes use the same explicit
reading-surface tap intent; ordinary scrolling does not acquire a second Article-only Chrome state machine.

Article search, link opening, image preview, speech, source actions, and rich-block rendering remain Article capabilities.
Novel Book, Chapter, Catalog, previous/next Chapter, and checkpoint actions remain Novel capabilities. The Reading Surface
renders their declared affordances and reports user intent; it does not interpret their source semantics. User-visible
product names remain `阅读模式` and `小说模式`; Reading Surface is internal domain language.

Back is consumed in a fixed order: close transient full-screen presentation such as image preview, close the active
reading panel such as search, settings, or Catalog, ask the owning reading session to leave its current reading state, and
only then return Back to the Browser Window Session. The owning session, not the Reading Surface, decides whether leaving
returns to the original Web page, a Novel Book surface, or another source-specific destination.

### Preferences and reading position

Appearance values are shared across Article and Novel reading: font size, theme/background, line height, page width, and
brightness. Behavior values remain source-specific: reading-mode choice, automatic reading, volume-key paging, Chapter
name visibility, page-number visibility, and other source-only behavior. All reading preferences remain device-local and
outside Personalization Sync, preserving ADR-0029. The Reading Surface applies preferences but does not own their
persistence.

A **Reading Anchor**, not a rendered page number, Swiper index, or scroll percentage, preserves the live position across
repagination. The Reading Surface owns that position while mounted, measures it from the rendered content, and may report
it to an owning session that declares a persistence capability. A reported current anchor is an event, never an implicit
restore command; initial restore, search navigation, and other explicit location requests use separate one-way inputs.

Novel Chapter-plus-character checkpoints remain durable Novel semantics and supply the initial anchor when a Novel
Reading Surface mounts. Article Reader Mode deliberately does not retain position across sessions: it supplies no initial
checkpoint, discards the live anchor when the Surface leaves, and starts a later session at the Article beginning. Article
search remains an explicit in-session navigation capability and does not create persisted reading progress.

### Failure and migration policy

If an Article cannot be laid out safely in a horizontal mode because of unsupported rich content or measurement failure,
the current Article Reading Session falls back to vertical scrolling, preserves content and the Reading Anchor, and tells
the user that the current page changed presentation. The stored global preference is not overwritten, Article acquisition
is not repeated, and Reader Mode does not exit.

Migration proceeds in working slices but does not permit two permanent renderers:

1. Establish Reading Document, Reading Anchor, rich-content pagination, and their automated test surface.
2. Extract the shared Reading Surface from the proven Novel presentation through a Novel adapter without moving Novel
   semantic ownership into ArkUI.
3. Connect the Article adapter and preserve search, links, images, preview, speech, and rich blocks.
4. Move the Article entry to the shared Reading Surface and remove legacy Article position retention.
5. Delete the old Article renderer and reduce the Novel renderer to Novel-only Book, Chapter, Catalog, and comic surfaces,
   deleting any superseded reading renderer implementation.

The old renderer may be deleted only after the agreed equivalence matrix covers plain and long Articles, multi-image and
rich-block Articles, online and offline acquisition, Novel Chapters, comics, all three reading modes, preference and
geometry changes, Reading Anchor restoration, search, preview, speech, Back, progressive pagination, fallback, and
Article start-at-beginning behavior. Pagination and in-session anchor conservation require automated verification; ArkUI measurement, Swiper, Scroller,
InputKit, gestures, and device presentation require proportional true-device verification.

## Considered Options

- Reusing `NovelReaderController` directly for Articles was rejected because it would merge source semantics, discard
  Article rich content, and expose Articles to Novel comic-classification and navigation policy.
- Keeping two complete renderers with only shared colors or preference helpers was rejected because layout, paging,
  gestures, progress, and testing complexity would remain duplicated behind shallow modules.
- Moving Article and Novel recognition into the Reading Surface was rejected because presentation must not become a
  second semantic owner.
- Using rendered pages, indices, or scroll percentages as persisted position was rejected because all change when
  typography, mode, or window geometry changes.
- Waiting for complete pagination before opening was rejected because long and image-heavy content would unnecessarily
  delay first reading.
- Permanently maintaining legacy and shared renderers was rejected because every presentation change would again require
  two implementations and two acceptance paths.

## Consequences

The shared module must be deep: Article and Novel callers learn one small presentation interface while rich-content
layout, progressive pagination, anchor conservation, appearance, gestures, and fallback remain local to its
implementation. Article and Novel semantic owners keep separate interfaces and tests.

This decision requires a staged migration and adds a rich-content pagination test surface before renderer replacement.
It also requires a window-scoped Article Reading Session instead of placing new orchestration in
`BrowserShellPage.ets`. Any unavoidable page edit is limited to ArkUI/ArkWeb mounting, state binding, and one-line event
forwarding and must satisfy the repository's page-reduction rule.

This ADR records architecture and acceptance constraints. It does not by itself authorize product implementation, edits
to frozen Sync or Window-Open/BFCache contracts, or a specific class/method interface.

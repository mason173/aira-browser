import { describe, expect, it } from '@ohos/hypium';
import { ArticleReadingDocumentAdapter } from '../main/ets/features/reader/ArticleReadingDocumentAdapter';
import { ReaderModeArticle } from '../main/ets/features/reader/ReaderModeModels';
import { NovelReadingDocumentAdapter } from '../main/ets/features/novel/NovelReadingDocumentAdapter';
import { NovelSessionCommittedChapter } from '../main/ets/features/novel/NovelReadingSessionState';
import {
  ReadingDocument,
  ReadingDocumentBlock,
  ReadingAnchor
} from '../main/ets/features/reading/ReadingDocumentModels';
import {
  ReadingBlockMeasure,
  ReadingBlockMeasurement,
  ReadingDocumentPaginator,
  ReadingPage,
  ReadingPageFragment,
  ReadingPageMetrics,
  ReadingPaginationResult
} from '../main/ets/features/reading/ReadingDocumentPaginator';
import {
  ReadingDocumentFlow,
  ReadingSearchTextSegment,
  ReadingVerticalFragment
} from '../main/ets/features/reading/ReadingDocumentFlow';
import {
  BrowserShellBackCoordinator,
  BrowserShellBackState
} from '../main/ets/core/browser/BrowserShellBackCoordinator';

function richArticle(): ReaderModeArticle {
  return {
    title: 'A rich Article',
    byline: 'Aira',
    siteName: 'Example',
    publishedAt: '2026-07-28',
    url: 'https://example.com/rich',
    excerpt: 'Summary',
    blocks: [
      { id: 'heading', type: 'heading', text: 'Section', level: 2 },
      { id: 'paragraph', type: 'paragraph', text: 'Paragraph body' },
      {
        id: 'image',
        type: 'image',
        text: '',
        url: 'https://example.com/image.webp',
        originalUrl: 'https://example.com/image-original.webp',
        fallbackUrls: ['https://example.com/image-fallback.webp'],
        alt: 'Illustration',
        caption: 'Image caption',
        width: 1200,
        height: 800,
        renderedWidth: 960,
        renderedHeight: 640,
        qualityScore: 91,
        hiddenReason: 'network_unavailable',
        imageFailurePolicy: 'compact_placeholder'
      },
      { id: 'link', type: 'link', text: 'Related', url: 'https://example.com/related' },
      { id: 'quote', type: 'quote', text: 'A quote' },
      { id: 'list', type: 'list_item', text: 'First item' },
      { id: 'code', type: 'code', text: 'const answer = 42;' }
    ]
  };
}

function novelChapter(): NovelSessionCommittedChapter {
  return {
    id: 'chapter-7',
    bookId: 'book-1',
    canonicalUrl: 'https://example.com/chapter-7',
    requestedUrl: 'https://example.com/chapter-7',
    finalUrl: 'https://example.com/chapter-7',
    title: 'Chapter 7',
    contentKind: 'novel',
    paragraphs: ['First paragraph', 'Second paragraph'],
    images: [],
    prevUrl: '',
    nextUrl: '',
    catalogUrl: 'https://example.com/book-1',
    revision: 1
  };
}

function paginationDocument(): ReadingDocument {
  return {
    id: 'document-1',
    title: 'Pagination',
    subtitle: '',
    blocks: [
      { id: 'intro', type: 'paragraph', text: '12345678901234567890' },
      { id: 'heading', type: 'heading', text: 'Heading' },
      { id: 'body', type: 'paragraph', text: 'abcdefghijklmnopqrstuvwxyz' },
      {
        id: 'image',
        type: 'image',
        text: '',
        url: 'https://example.com/image.webp',
        width: 1200,
        height: 800
      },
      { id: 'code', type: 'code', text: 'const answer = 42; return answer;' }
    ]
  };
}

function pageMetrics(contentHeight: number): ReadingPageMetrics {
  return {
    contentWidth: 300,
    contentHeight: contentHeight,
    blockSpacing: 8
  };
}

const measureBlock: ReadingBlockMeasure = (
  block: ReadingDocumentBlock,
  startOffset: number,
  endOffset: number,
  _metrics: ReadingPageMetrics
): ReadingBlockMeasurement => {
  if (block.type === 'image') {
    return {
      height: 52,
      estimatedLineCount: 0
    };
  }
  const height = Math.max(18, (endOffset - startOffset) * 2);
  return {
    height: height,
    estimatedLineCount: Math.max(1, Math.ceil((endOffset - startOffset) / 6))
  };
};

export default function readingDocumentTest(): void {
  describe('ReadingDocument', () => {
    it('preserves Article rich-content semantics through the Article adapter', 0, () => {
      const document = new ArticleReadingDocumentAdapter().adapt(richArticle());

      expect(document.id).assertEqual('https://example.com/rich');
      expect(document.title).assertEqual('A rich Article');
      expect(document.blocks.length).assertEqual(7);
      expect(document.blocks[0].type).assertEqual('heading');
      expect(document.blocks[0].level).assertEqual(2);
      expect(document.blocks[2].type).assertEqual('image');
      expect(document.blocks[2].url).assertEqual('https://example.com/image.webp');
      expect(document.blocks[2].originalUrl).assertEqual('https://example.com/image-original.webp');
      const fallbackUrls: string[] = document.blocks[2].fallbackUrls ?? [];
      expect(fallbackUrls.length).assertEqual(1);
      expect(document.blocks[2].caption).assertEqual('Image caption');
      expect(document.blocks[2].renderedWidth).assertEqual(960);
      expect(document.blocks[2].renderedHeight).assertEqual(640);
      expect(document.blocks[2].qualityScore).assertEqual(91);
      expect(document.blocks[2].hiddenReason).assertEqual('network_unavailable');
      expect(document.blocks[2].imageFailurePolicy).assertEqual('compact_placeholder');
      expect(document.blocks[3].type).assertEqual('link');
      expect(document.blocks[4].type).assertEqual('quote');
      expect(document.blocks[5].type).assertEqual('list_item');
      expect(document.blocks[6].type).assertEqual('code');
    });

    it('maps a Novel Chapter checkpoint through a Reading Anchor without comic semantics', 0, () => {
      const adapter = new NovelReadingDocumentAdapter();
      const chapter = novelChapter();
      const document = adapter.adapt(chapter);
      const anchor = adapter.characterOffsetToAnchor(document, 18);

      expect(document.id).assertEqual('chapter-7');
      expect(document.title).assertEqual('Chapter 7');
      expect(document.blocks.length).assertEqual(2);
      expect(document.blocks[0].type).assertEqual('paragraph');
      expect(document.blocks[1].type).assertEqual('paragraph');
      expect(anchor.blockId).assertEqual(document.blocks[1].id);
      expect(anchor.characterOffset).assertEqual(2);
      expect(adapter.anchorToCharacterOffset(document, anchor)).assertEqual(18);
    });

    it('paginates rich content without losing text or splitting images', 0, () => {
      const paginator = new ReadingDocumentPaginator();
      const document: ReadingDocument = paginationDocument();
      const result: ReadingPaginationResult = paginator.paginate(document, pageMetrics(72), measureBlock);
      let bodyText: string = '';
      let imageFragments: number = 0;
      let headingPageIndex: number = -1;
      let bodyPageIndex: number = -1;

      for (let pageIndex: number = 0; pageIndex < result.pages.length; pageIndex++) {
        const page: ReadingPage = result.pages[pageIndex];
        for (let fragmentIndex: number = 0; fragmentIndex < page.fragments.length; fragmentIndex++) {
          const fragment: ReadingPageFragment = page.fragments[fragmentIndex];
          if (fragment.blockId === 'body') {
            bodyText = bodyText + document.blocks[2].text.substring(
              fragment.startCharacterOffset,
              fragment.endCharacterOffset
            );
            if (bodyPageIndex < 0) {
              bodyPageIndex = pageIndex;
            }
          }
          if (fragment.blockId === 'heading') {
            headingPageIndex = pageIndex;
          }
          if (fragment.blockId === 'image') {
            imageFragments += 1;
            expect(fragment.startCharacterOffset).assertEqual(0);
            expect(fragment.endCharacterOffset).assertEqual(0);
          }
        }
      }

      expect(bodyText).assertEqual('abcdefghijklmnopqrstuvwxyz');
      expect(imageFragments).assertEqual(1);
      expect(headingPageIndex).assertEqual(bodyPageIndex);
    });

    it('resolves the same Reading Anchor after repagination', 0, () => {
      const paginator = new ReadingDocumentPaginator();
      const document: ReadingDocument = paginationDocument();
      const compact: ReadingPaginationResult = paginator.paginate(document, pageMetrics(72), measureBlock);
      const expanded: ReadingPaginationResult = paginator.paginate(document, pageMetrics(120), measureBlock);
      const anchor: ReadingAnchor = { documentId: document.id, blockId: 'body', characterOffset: 12 };
      const compactPage: ReadingPage = compact.pages[paginator.findPageForAnchor(compact.pages, anchor)];
      const expandedPage: ReadingPage = expanded.pages[paginator.findPageForAnchor(expanded.pages, anchor)];

      expect(pageContainsAnchor(compactPage, anchor)).assertTrue();
      expect(pageContainsAnchor(expandedPage, anchor)).assertTrue();
    });

    it('splits vertical text into continuous fragments with non-zero character anchors', 0, () => {
      const flow = new ReadingDocumentFlow();
      const document: ReadingDocument = {
        id: 'vertical-document',
        title: 'Vertical',
        subtitle: '',
        blocks: [
          { id: 'long-block', type: 'paragraph', text: 'abcdefghijklmnop' },
          { id: 'atomic-image', type: 'image', text: '', url: 'https://example.com/image.webp' }
        ]
      };
      const fragments: ReadingVerticalFragment[] = flow.buildVerticalFragments(document, 5);
      let restoredText: string = '';

      for (let index: number = 0; index < fragments.length - 1; index++) {
        const fragment: ReadingVerticalFragment = fragments[index];
        restoredText = restoredText + document.blocks[0].text.substring(
          fragment.startCharacterOffset,
          fragment.endCharacterOffset
        );
        if (index > 0) {
          expect(fragment.startCharacterOffset).assertEqual(fragments[index - 1].endCharacterOffset);
        }
      }

      expect(restoredText).assertEqual(document.blocks[0].text);
      expect(fragments[1].startCharacterOffset > 0).assertTrue();
      expect(fragments[fragments.length - 1].atomic).assertTrue();
      expect(fragments[fragments.length - 1].blockId).assertEqual('atomic-image');
    });

    it('keeps one active search match highlighted across fragment edges', 0, () => {
      const flow = new ReadingDocumentFlow();
      const blockText: string = 'alpha cross boundary';
      const first: ReadingSearchTextSegment[] = flow.buildSearchSegments(blockText, 'cross', 0, 8, 0);
      const second: ReadingSearchTextSegment[] = flow.buildSearchSegments(blockText, 'cross', 8, blockText.length, 0);

      expect(joinHighlightedText(first)).assertEqual('cr');
      expect(joinHighlightedText(second)).assertEqual('oss');
      expect(hasActiveHighlight(first)).assertTrue();
      expect(hasActiveHighlight(second)).assertTrue();
      expect(flow.resolveMatchCharacterOffset(blockText, 'cross', 0)).assertEqual(6);
    });

    it('includes the Reading Anchor block in initial progressive pagination', 0, () => {
      const flow = new ReadingDocumentFlow();
      const blocks: ReadingDocumentBlock[] = [];
      for (let index: number = 0; index < 40; index++) {
        blocks.push({ id: `block-${index}`, type: 'paragraph', text: `Block ${index}` });
      }
      const document: ReadingDocument = {
        id: 'progressive-document',
        title: 'Progressive',
        subtitle: '',
        blocks: blocks
      };
      const anchor: ReadingAnchor = {
        documentId: document.id,
        blockId: 'block-30',
        characterOffset: 3
      };

      expect(flow.resolveInitialPaginationBlockCount(document, anchor, 24)).assertEqual(31);
    });

    it('dismisses a Novel reader panel before requesting reader exit', 0, () => {
      const state: BrowserShellBackState = {
        manualElementHideSelectionActive: false,
        readerModeVisible: false,
        readerModeImagePreviewVisible: false,
        readerModePanelVisible: false,
        novelReaderVisible: true,
        novelReaderPanelVisible: true,
        customHomepageTransientBackActive: false,
        tabsSheetVisible: false,
        downloadPromptGuid: '',
        externalNavigationPromptVisible: false
      };

      expect(new BrowserShellBackCoordinator().resolveBackAction(state)).assertEqual('dismiss_novel_reader_panel');
    });
  });
}

function pageContainsAnchor(page: ReadingPage, anchor: ReadingAnchor): boolean {
  for (let index: number = 0; index < page.fragments.length; index++) {
    const fragment: ReadingPageFragment = page.fragments[index];
    if (fragment.blockId === anchor.blockId && fragment.startCharacterOffset <= anchor.characterOffset &&
      fragment.endCharacterOffset >= anchor.characterOffset) {
      return true;
    }
  }
  return false;
}

function joinHighlightedText(segments: ReadingSearchTextSegment[]): string {
  let text: string = '';
  for (let index: number = 0; index < segments.length; index++) {
    if (segments[index].highlighted) {
      text = text + segments[index].text;
    }
  }
  return text;
}

function hasActiveHighlight(segments: ReadingSearchTextSegment[]): boolean {
  for (let index: number = 0; index < segments.length; index++) {
    if (segments[index].highlighted && segments[index].active) {
      return true;
    }
  }
  return false;
}

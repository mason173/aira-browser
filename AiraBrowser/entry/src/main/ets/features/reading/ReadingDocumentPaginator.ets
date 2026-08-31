import {
  ReadingAnchor,
  ReadingBlockType,
  ReadingDocument,
  ReadingDocumentBlock,
  buildReadingBlockFingerprint
} from './ReadingDocumentModels';

const READING_PAGINATION_CACHE_LIMIT: number = 6;
const READING_PAGINATION_CACHE_FRAGMENT_LIMIT: number = 12000;
const READING_PAGINATION_MIN_PARAGRAPH_LINES: number = 2;
const READING_PAGINATION_KEEP_TOGETHER_MAX_LINES: number = 4;
const READING_PAGINATION_HEADING_FOLLOWING_LINES: number = 2;
const READING_PAGINATION_MIN_TAIL_CHARACTER_COUNT: number = 6;
const READING_PAGINATION_MAX_BOUNDARY_RETREAT: number = 12;
const READING_PAGINATION_OPENING_PUNCTUATION: string =
  '([{<\u00AB\u2018\u201C\u2039\u3008\u300A\u300C\u300E\u3010\u3014\u3016\u3018\u301A\u301D\uFF08\uFF3B\uFF5B';
const READING_PAGINATION_CLOSING_PUNCTUATION: string =
  '.,!?;:%)]}>\u00BB\u2019\u201D\u2026\u2014\u203A\u3001\u3002\u3009\u300B\u300D\u300F\u3011\u3015\u3017' +
    '\u3019\u301B\u301E\u301F\uFF01\uFF05\uFF09\uFF0C\uFF0E\uFF1A\uFF1B\uFF1F\uFF3D\uFF5D';

interface ReadingPaginationCacheEntry {
  key: string;
  result: ReadingPaginationResult;
  fragmentCount: number;
}

export interface ReadingPageMetrics {
  contentWidth: number;
  contentHeight: number;
  blockSpacing: number;
}

export interface ReadingBlockMeasurement {
  height: number;
  estimatedLineCount: number;
}

export type ReadingBlockMeasure = (
  block: ReadingDocumentBlock,
  startCharacterOffset: number,
  endCharacterOffset: number,
  metrics: ReadingPageMetrics
) => ReadingBlockMeasurement;

export interface ReadingPageFragment {
  blockId: string;
  blockIndex: number;
  blockType: ReadingBlockType;
  startCharacterOffset: number;
  endCharacterOffset: number;
  atomic: boolean;
}

export interface ReadingPage {
  index: number;
  fragments: ReadingPageFragment[];
}

export interface ReadingPaginationResult {
  documentId: string;
  pages: ReadingPage[];
}

export class ReadingDocumentPaginator {
  private cachedResults: ReadingPaginationCacheEntry[] = [];
  private cachedFragmentCount: number = 0;

  paginateCached(
    document: ReadingDocument,
    metrics: ReadingPageMetrics,
    layoutSignature: string,
    measure: ReadingBlockMeasure
  ): ReadingPaginationResult {
    const cacheKey: string = this.buildCacheKey(document, metrics, layoutSignature);
    const cached: ReadingPaginationResult | undefined = this.takeCachedResult(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    const result: ReadingPaginationResult = this.paginate(document, metrics, measure);
    this.rememberResult(cacheKey, result);
    return result;
  }

  clearCache(): void {
    this.cachedResults = [];
    this.cachedFragmentCount = 0;
  }

  paginate(
    document: ReadingDocument,
    metrics: ReadingPageMetrics,
    measure: ReadingBlockMeasure
  ): ReadingPaginationResult {
    const pages: ReadingPage[] = [];
    let fragments: ReadingPageFragment[] = [];
    let usedHeight: number = 0;
    const pageHeight: number = Math.max(1, metrics.contentHeight);

    for (let blockIndex: number = 0; blockIndex < document.blocks.length; blockIndex++) {
      const block: ReadingDocumentBlock = document.blocks[blockIndex];
      if (block.type === 'image') {
        const atomicMeasurement: ReadingBlockMeasurement = measure(block, 0, 0, metrics);
        const gap: number = fragments.length > 0 ? metrics.blockSpacing : 0;
        if (fragments.length > 0 && usedHeight + gap + atomicMeasurement.height > pageHeight) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
        }
        fragments.push(this.createFragment(block, blockIndex, 0, 0, true));
        usedHeight = usedHeight + (fragments.length > 1 ? metrics.blockSpacing : 0) + atomicMeasurement.height;
        continue;
      }

      if (block.type === 'heading' && fragments.length > 0 && blockIndex + 1 < document.blocks.length &&
        this.shouldMoveHeadingToFreshPage(
          document,
          blockIndex,
          usedHeight,
          pageHeight,
          metrics,
          measure
        )) {
        pages.push(this.createPage(pages.length, fragments));
        fragments = [];
        usedHeight = 0;
      }

      let startOffset: number = 0;
      const textLength: number = block.text.length;
      if (textLength === 0) {
        const emptyMeasurement: ReadingBlockMeasurement = measure(block, 0, 0, metrics);
        const emptyGap: number = fragments.length > 0 ? metrics.blockSpacing : 0;
        if (fragments.length > 0 && usedHeight + emptyGap + emptyMeasurement.height > pageHeight) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
        }
        fragments.push(this.createFragment(block, blockIndex, 0, 0, false));
        usedHeight = usedHeight + (fragments.length > 1 ? metrics.blockSpacing : 0) + emptyMeasurement.height;
        continue;
      }

      while (startOffset < textLength) {
        const gap: number = fragments.length > 0 ? metrics.blockSpacing : 0;
        const availableHeight: number = pageHeight - usedHeight - gap;
        const remainingMeasurement: ReadingBlockMeasurement = measure(block, startOffset, textLength, metrics);
        if (remainingMeasurement.height <= availableHeight) {
          fragments.push(this.createFragment(block, blockIndex, startOffset, textLength, false));
          usedHeight = usedHeight + gap + remainingMeasurement.height;
          startOffset = textLength;
          continue;
        }

        if (block.type === 'paragraph' && startOffset === 0 && fragments.length > 0 &&
          remainingMeasurement.estimatedLineCount <= READING_PAGINATION_KEEP_TOGETHER_MAX_LINES &&
          remainingMeasurement.height <= pageHeight) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
          continue;
        }

        if (fragments.length > 0 && availableHeight <= 0) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
          continue;
        }

        const take: number = this.largestPrefixWithinHeight(
          block,
          startOffset,
          textLength,
          Math.max(1, availableHeight),
          metrics,
          measure
        );
        if (take <= 0 && fragments.length > 0) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
          continue;
        }
        const measuredEndOffset: number = take > 0
          ? Math.min(textLength, startOffset + take)
          : this.resolveMinimumTextEndOffset(block.text, startOffset);
        const lineProtectedEndOffset: number = this.resolveParagraphProtectedEndOffset(
          block,
          startOffset,
          measuredEndOffset,
          textLength,
          fragments.length > 0,
          metrics,
          measure
        );
        if (lineProtectedEndOffset <= startOffset && fragments.length > 0) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
          continue;
        }
        const endOffset: number = this.resolvePreferredTextEndOffset(
          block,
          startOffset,
          lineProtectedEndOffset > startOffset ? lineProtectedEndOffset : measuredEndOffset,
          textLength
        );
        const fragmentMeasurement: ReadingBlockMeasurement = measure(block, startOffset, endOffset, metrics);
        if (block.type === 'paragraph' && fragments.length > 0 &&
          fragmentMeasurement.estimatedLineCount < READING_PAGINATION_MIN_PARAGRAPH_LINES) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
          continue;
        }
        fragments.push(this.createFragment(block, blockIndex, startOffset, endOffset, false));
        usedHeight = usedHeight + gap + fragmentMeasurement.height;
        startOffset = endOffset;
        if (startOffset < textLength) {
          pages.push(this.createPage(pages.length, fragments));
          fragments = [];
          usedHeight = 0;
        }
      }
    }

    if (fragments.length > 0) {
      pages.push(this.createPage(pages.length, fragments));
    }
    return { documentId: document.id, pages: pages };
  }

  findPageForAnchor(pages: ReadingPage[], anchor: ReadingAnchor): number {
    let lastMatchingPage: number = -1;
    for (let pageIndex: number = 0; pageIndex < pages.length; pageIndex++) {
      const page: ReadingPage = pages[pageIndex];
      for (let fragmentIndex: number = 0; fragmentIndex < page.fragments.length; fragmentIndex++) {
        const fragment: ReadingPageFragment = page.fragments[fragmentIndex];
        if (fragment.blockId !== anchor.blockId) {
          continue;
        }
        lastMatchingPage = pageIndex;
        if (fragment.atomic ||
          (anchor.characterOffset >= fragment.startCharacterOffset &&
            anchor.characterOffset < fragment.endCharacterOffset)) {
          return pageIndex;
        }
        if (anchor.characterOffset === fragment.startCharacterOffset) {
          return pageIndex;
        }
      }
    }
    if (lastMatchingPage >= 0) {
      return lastMatchingPage;
    }
    return 0;
  }

  private buildCacheKey(
    document: ReadingDocument,
    metrics: ReadingPageMetrics,
    layoutSignature: string
  ): string {
    return `${this.buildDocumentFingerprint(document)}|${metrics.contentWidth.toFixed(3)}|` +
      `${metrics.contentHeight.toFixed(3)}|${metrics.blockSpacing.toFixed(3)}|${layoutSignature}`;
  }

  private buildDocumentFingerprint(document: ReadingDocument): string {
    let hash: number = 2166136261;
    hash = this.appendHash(hash, document.id);
    hash = this.appendHash(hash, document.title);
    hash = this.appendHash(hash, document.subtitle);
    hash = this.appendHash(hash, `${document.blocks.length}`);
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ReadingDocumentBlock = document.blocks[index];
      hash = this.appendHash(hash, block.id);
      hash = this.appendHash(hash, buildReadingBlockFingerprint(block));
    }
    return (hash >>> 0).toString(16);
  }

  private appendHash(seed: number, value: string): number {
    let hash: number = seed;
    for (let index: number = 0; index < value.length; index++) {
      hash = hash ^ value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return hash;
  }

  private takeCachedResult(cacheKey: string): ReadingPaginationResult | undefined {
    for (let index: number = 0; index < this.cachedResults.length; index++) {
      if (this.cachedResults[index].key !== cacheKey) {
        continue;
      }
      const entry: ReadingPaginationCacheEntry = this.cachedResults[index];
      this.cachedResults.splice(index, 1);
      this.cachedResults.push(entry);
      return entry.result;
    }
    return undefined;
  }

  private rememberResult(cacheKey: string, result: ReadingPaginationResult): void {
    const fragmentCount: number = this.countFragments(result);
    if (fragmentCount > READING_PAGINATION_CACHE_FRAGMENT_LIMIT) {
      return;
    }
    while (this.cachedResults.length > 0 &&
      (this.cachedResults.length >= READING_PAGINATION_CACHE_LIMIT ||
        this.cachedFragmentCount + fragmentCount > READING_PAGINATION_CACHE_FRAGMENT_LIMIT)) {
      const removed: ReadingPaginationCacheEntry | undefined = this.cachedResults.shift();
      if (removed !== undefined) {
        this.cachedFragmentCount = Math.max(0, this.cachedFragmentCount - removed.fragmentCount);
      }
    }
    this.cachedResults.push({ key: cacheKey, result: result, fragmentCount: fragmentCount });
    this.cachedFragmentCount += fragmentCount;
  }

  private countFragments(result: ReadingPaginationResult): number {
    let count: number = 0;
    for (let pageIndex: number = 0; pageIndex < result.pages.length; pageIndex++) {
      count += result.pages[pageIndex].fragments.length;
    }
    return count;
  }

  private shouldMoveHeadingToFreshPage(
    document: ReadingDocument,
    headingIndex: number,
    usedHeight: number,
    pageHeight: number,
    metrics: ReadingPageMetrics,
    measure: ReadingBlockMeasure
  ): boolean {
    const heading: ReadingDocumentBlock = document.blocks[headingIndex];
    const headingMeasurement: ReadingBlockMeasurement = measure(heading, 0, heading.text.length, metrics);
    let bundleHeight: number = headingMeasurement.height;
    let remainingLineCount: number = READING_PAGINATION_HEADING_FOLLOWING_LINES;
    for (let blockIndex: number = headingIndex + 1;
      blockIndex < document.blocks.length && remainingLineCount > 0;
      blockIndex++) {
      const following: ReadingDocumentBlock = document.blocks[blockIndex];
      const previewMeasurement: ReadingBlockMeasurement = this.resolveHeadingFollowingMeasurement(
        following,
        remainingLineCount,
        pageHeight,
        metrics,
        measure
      );
      bundleHeight += metrics.blockSpacing + previewMeasurement.height;
      if (following.type !== 'heading') {
        remainingLineCount = Math.max(0, remainingLineCount - previewMeasurement.estimatedLineCount);
      }
      if (bundleHeight > pageHeight) {
        return false;
      }
    }
    return usedHeight + metrics.blockSpacing + bundleHeight > pageHeight;
  }

  private resolveHeadingFollowingMeasurement(
    following: ReadingDocumentBlock,
    maximumLineCount: number,
    pageHeight: number,
    metrics: ReadingPageMetrics,
    measure: ReadingBlockMeasure
  ): ReadingBlockMeasurement {
    if (following.type === 'image' || following.text.length === 0) {
      return measure(following, 0, following.type === 'image' ? 0 : following.text.length, metrics);
    }
    const completeMeasurement: ReadingBlockMeasurement = measure(following, 0, following.text.length, metrics);
    if (following.type === 'heading') {
      return completeMeasurement;
    }
    const keepParagraphTogether: boolean = following.type === 'paragraph' &&
      completeMeasurement.estimatedLineCount <= READING_PAGINATION_KEEP_TOGETHER_MAX_LINES &&
      completeMeasurement.height <= pageHeight;
    if (keepParagraphTogether || completeMeasurement.estimatedLineCount <= maximumLineCount) {
      return completeMeasurement;
    }
    const followingTake: number = this.largestPrefixWithinLineCount(
      following,
      0,
      following.text.length,
      maximumLineCount,
      metrics,
      measure
    );
    const followingEnd: number = Math.max(this.resolveMinimumTextEndOffset(following.text, 0), followingTake);
    return measure(following, 0, followingEnd, metrics);
  }

  private largestPrefixWithinHeight(
    block: ReadingDocumentBlock,
    startOffset: number,
    endOffset: number,
    availableHeight: number,
    metrics: ReadingPageMetrics,
    measure: ReadingBlockMeasure
  ): number {
    let low: number = 1;
    let high: number = endOffset - startOffset;
    let best: number = 0;
    while (low <= high) {
      const mid: number = (low + high) >> 1;
      const measurement: ReadingBlockMeasurement = measure(block, startOffset, startOffset + mid, metrics);
      if (measurement.height <= availableHeight) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return this.resolveSafePrefixLength(block.text, startOffset, best);
  }

  private largestPrefixWithinLineCount(
    block: ReadingDocumentBlock,
    startOffset: number,
    endOffset: number,
    maximumLineCount: number,
    metrics: ReadingPageMetrics,
    measure: ReadingBlockMeasure
  ): number {
    let low: number = 1;
    let high: number = endOffset - startOffset;
    let best: number = 0;
    while (low <= high) {
      const mid: number = (low + high) >> 1;
      const measurement: ReadingBlockMeasurement = measure(block, startOffset, startOffset + mid, metrics);
      if (measurement.estimatedLineCount <= maximumLineCount) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return this.resolveSafePrefixLength(block.text, startOffset, best);
  }

  private resolveParagraphProtectedEndOffset(
    block: ReadingDocumentBlock,
    startOffset: number,
    measuredEndOffset: number,
    textLength: number,
    pageHasContent: boolean,
    metrics: ReadingPageMetrics,
    measure: ReadingBlockMeasure
  ): number {
    if (block.type !== 'paragraph' || measuredEndOffset >= textLength) {
      return measuredEndOffset;
    }
    const currentMeasurement: ReadingBlockMeasurement = measure(
      block,
      startOffset,
      measuredEndOffset,
      metrics
    );
    const tailMeasurement: ReadingBlockMeasurement = measure(block, measuredEndOffset, textLength, metrics);
    const currentLineCount: number = Math.max(1, currentMeasurement.estimatedLineCount);
    const tailLineCount: number = Math.max(1, tailMeasurement.estimatedLineCount);
    if (pageHasContent && currentLineCount < READING_PAGINATION_MIN_PARAGRAPH_LINES) {
      return startOffset;
    }
    if (tailLineCount >= READING_PAGINATION_MIN_PARAGRAPH_LINES) {
      return measuredEndOffset;
    }
    const requiredTailLines: number = READING_PAGINATION_MIN_PARAGRAPH_LINES - tailLineCount;
    const retainedCurrentLines: number = currentLineCount - requiredTailLines;
    if (retainedCurrentLines < READING_PAGINATION_MIN_PARAGRAPH_LINES) {
      return pageHasContent ? startOffset : measuredEndOffset;
    }
    const protectedTake: number = this.largestPrefixWithinLineCount(
      block,
      startOffset,
      measuredEndOffset,
      retainedCurrentLines,
      metrics,
      measure
    );
    return protectedTake > 0 ? startOffset + protectedTake : (pageHasContent ? startOffset : measuredEndOffset);
  }

  private resolvePreferredTextEndOffset(
    block: ReadingDocumentBlock,
    startOffset: number,
    measuredEndOffset: number,
    textLength: number
  ): number {
    if (block.type === 'code' || measuredEndOffset >= textLength) {
      return measuredEndOffset;
    }
    const minimumEndOffset: number = this.resolveMinimumTextEndOffset(block.text, startOffset);
    const retreatFloor: number = Math.max(
      minimumEndOffset,
      measuredEndOffset - READING_PAGINATION_MAX_BOUNDARY_RETREAT
    );
    let preferredEndOffset: number = measuredEndOffset;
    const tailLength: number = textLength - preferredEndOffset;
    if (block.type !== 'paragraph' && tailLength > 0 &&
      tailLength < READING_PAGINATION_MIN_TAIL_CHARACTER_COUNT) {
      const retreatCount: number = READING_PAGINATION_MIN_TAIL_CHARACTER_COUNT - tailLength;
      for (let index: number = 0; index < retreatCount; index++) {
        const nextEndOffset: number = this.retreatTextEndOffset(block.text, preferredEndOffset, retreatFloor);
        if (nextEndOffset === preferredEndOffset) {
          break;
        }
        preferredEndOffset = nextEndOffset;
      }
    }
    while (preferredEndOffset > retreatFloor &&
      this.isProhibitedTextBoundary(block.text, preferredEndOffset)) {
      const nextEndOffset: number = this.retreatTextEndOffset(block.text, preferredEndOffset, retreatFloor);
      if (nextEndOffset === preferredEndOffset) {
        break;
      }
      preferredEndOffset = nextEndOffset;
    }
    return Math.max(minimumEndOffset, preferredEndOffset);
  }

  private resolveMinimumTextEndOffset(text: string, startOffset: number): number {
    const firstCodeUnit: number = text.charCodeAt(startOffset);
    const secondCodeUnit: number = startOffset + 1 < text.length ? text.charCodeAt(startOffset + 1) : 0;
    const startsSurrogatePair: boolean = firstCodeUnit >= 0xD800 && firstCodeUnit <= 0xDBFF &&
      secondCodeUnit >= 0xDC00 && secondCodeUnit <= 0xDFFF;
    return Math.min(text.length, startOffset + (startsSurrogatePair ? 2 : 1));
  }

  private resolveSafePrefixLength(text: string, startOffset: number, prefixLength: number): number {
    if (prefixLength <= 0) {
      return 0;
    }
    const endOffset: number = startOffset + prefixLength;
    if (endOffset >= text.length) {
      return prefixLength;
    }
    const previousCodeUnit: number = text.charCodeAt(endOffset - 1);
    const nextCodeUnit: number = text.charCodeAt(endOffset);
    const splitsSurrogatePair: boolean = previousCodeUnit >= 0xD800 && previousCodeUnit <= 0xDBFF &&
      nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF;
    return splitsSurrogatePair ? Math.max(0, prefixLength - 1) : prefixLength;
  }

  private retreatTextEndOffset(text: string, endOffset: number, minimumEndOffset: number): number {
    const nextEndOffset: number = endOffset - 1;
    if (nextEndOffset < minimumEndOffset) {
      return endOffset;
    }
    const nextCodeUnit: number = text.charCodeAt(nextEndOffset);
    const previousCodeUnit: number = nextEndOffset > 0 ? text.charCodeAt(nextEndOffset - 1) : 0;
    const splitsSurrogatePair: boolean = nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF &&
      previousCodeUnit >= 0xD800 && previousCodeUnit <= 0xDBFF;
    if (splitsSurrogatePair) {
      return nextEndOffset - 1 >= minimumEndOffset ? nextEndOffset - 1 : endOffset;
    }
    return nextEndOffset;
  }

  private isProhibitedTextBoundary(text: string, endOffset: number): boolean {
    const pageEndCharacter: string = text.charAt(endOffset - 1);
    const nextPageStartCharacter: string = text.charAt(endOffset);
    return READING_PAGINATION_OPENING_PUNCTUATION.indexOf(pageEndCharacter) >= 0 ||
      READING_PAGINATION_CLOSING_PUNCTUATION.indexOf(nextPageStartCharacter) >= 0;
  }

  private createPage(index: number, fragments: ReadingPageFragment[]): ReadingPage {
    return { index: index, fragments: fragments.slice() };
  }

  private createFragment(
    block: ReadingDocumentBlock,
    blockIndex: number,
    startCharacterOffset: number,
    endCharacterOffset: number,
    atomic: boolean
  ): ReadingPageFragment {
    return {
      blockId: block.id,
      blockIndex: blockIndex,
      blockType: block.type,
      startCharacterOffset: startCharacterOffset,
      endCharacterOffset: endCharacterOffset,
      atomic: atomic
    };
  }
}

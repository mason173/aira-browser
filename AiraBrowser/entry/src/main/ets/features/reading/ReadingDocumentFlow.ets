import {
  ReadingAnchor,
  ReadingDocument,
  ReadingDocumentBlock,
  buildReadingBlockFingerprint,
  createReadingAnchor
} from './ReadingDocumentModels';

const READING_ANCHOR_CONTEXT_LENGTH: number = 24;

interface ReadingAnchorResolution {
  blockIndex: number;
  characterOffset: number;
}

export interface ReadingVerticalFragment {
  blockId: string;
  blockIndex: number;
  startCharacterOffset: number;
  endCharacterOffset: number;
  atomic: boolean;
  lastInBlock: boolean;
}

export interface ReadingSearchTextSegment {
  text: string;
  highlighted: boolean;
  active: boolean;
}

export class ReadingDocumentFlow {
  createAnchor(document: ReadingDocument, blockId: string, characterOffset: number): ReadingAnchor {
    const blockIndex: number = this.findBlockIndex(document, blockId);
    if (blockIndex < 0) {
      return createReadingAnchor(document.id, blockId, characterOffset);
    }
    const block: ReadingDocumentBlock = document.blocks[blockIndex];
    const offset: number = this.clampOffset(characterOffset, block.text.length);
    return createReadingAnchor(
      document.id,
      block.id,
      offset,
      buildReadingBlockFingerprint(block),
      blockIndex,
      block.text.substring(Math.max(0, offset - READING_ANCHOR_CONTEXT_LENGTH), offset),
      block.text.substring(offset, Math.min(block.text.length, offset + READING_ANCHOR_CONTEXT_LENGTH))
    );
  }

  resolveAnchor(document: ReadingDocument, candidate: ReadingAnchor): ReadingAnchor {
    const resolution: ReadingAnchorResolution | undefined = this.findAnchorResolution(document, candidate);
    if (resolution === undefined) {
      return this.resolveDocumentStartAnchor(document);
    }
    const block: ReadingDocumentBlock = document.blocks[resolution.blockIndex];
    return this.createAnchor(document, block.id, resolution.characterOffset);
  }

  isAnchorRecoverable(document: ReadingDocument, candidate: ReadingAnchor): boolean {
    return this.findAnchorResolution(document, candidate) !== undefined;
  }

  buildAnchorSignature(anchor: ReadingAnchor): string {
    return `${anchor.documentId}|${anchor.blockId}|${anchor.characterOffset}|${anchor.blockFingerprint ?? ''}`;
  }

  findBlockIndex(document: ReadingDocument, blockId: string): number {
    for (let index: number = 0; index < document.blocks.length; index++) {
      if (document.blocks[index].id === blockId) {
        return index;
      }
    }
    return -1;
  }

  buildVerticalFragments(document: ReadingDocument, maximumTextLength: number): ReadingVerticalFragment[] {
    const fragments: ReadingVerticalFragment[] = [];
    const fragmentLength: number = Math.max(1, Math.floor(maximumTextLength));
    for (let blockIndex: number = 0; blockIndex < document.blocks.length; blockIndex++) {
      const block: ReadingDocumentBlock = document.blocks[blockIndex];
      if (block.type === 'image' || block.text.length === 0) {
        fragments.push(this.createVerticalFragment(block, blockIndex, 0, 0, block.type === 'image', true));
        continue;
      }
      let startOffset: number = 0;
      while (startOffset < block.text.length) {
        const endOffset: number = this.resolveVerticalFragmentEnd(block.text, startOffset, fragmentLength);
        fragments.push(this.createVerticalFragment(
          block,
          blockIndex,
          startOffset,
          endOffset,
          false,
          endOffset >= block.text.length
        ));
        startOffset = endOffset;
      }
    }
    return fragments;
  }

  resolveInitialPaginationBlockCount(
    document: ReadingDocument,
    anchor: ReadingAnchor,
    initialBlockCount: number
  ): number {
    let anchorBlockIndex: number = -1;
    for (let index: number = 0; index < document.blocks.length; index++) {
      if (document.blocks[index].id === anchor.blockId) {
        anchorBlockIndex = index;
        break;
      }
    }
    const requiredCount: number = anchorBlockIndex < 0 ? 0 : anchorBlockIndex + 1;
    return Math.min(
      document.blocks.length,
      Math.max(Math.max(1, Math.floor(initialBlockCount)), requiredCount)
    );
  }

  resolveMatchCharacterOffset(blockText: string, query: string, matchIndex: number): number {
    const normalizedQuery: string = query.trim().toLowerCase();
    if (normalizedQuery.length === 0 || matchIndex < 0) {
      return 0;
    }
    const normalizedText: string = blockText.toLowerCase();
    let cursor: number = 0;
    let currentIndex: number = 0;
    let matchStart: number = normalizedText.indexOf(normalizedQuery, cursor);
    while (matchStart >= 0) {
      if (currentIndex === matchIndex) {
        return matchStart;
      }
      currentIndex += 1;
      cursor = matchStart + normalizedQuery.length;
      matchStart = normalizedText.indexOf(normalizedQuery, cursor);
    }
    return 0;
  }

  buildSearchSegments(
    blockText: string,
    query: string,
    fragmentStart: number,
    fragmentEnd: number,
    activeMatchIndex: number
  ): ReadingSearchTextSegment[] {
    const startOffset: number = Math.max(0, Math.min(blockText.length, fragmentStart));
    const endOffset: number = Math.max(startOffset, Math.min(blockText.length, fragmentEnd));
    const normalizedQuery: string = query.trim().toLowerCase();
    if (normalizedQuery.length === 0) {
      return [this.createSearchSegment(blockText.substring(startOffset, endOffset), false, false)];
    }
    const normalizedText: string = blockText.toLowerCase();
    const segments: ReadingSearchTextSegment[] = [];
    let fragmentCursor: number = startOffset;
    let matchIndex: number = 0;
    let searchCursor: number = 0;
    let matchStart: number = normalizedText.indexOf(normalizedQuery, searchCursor);
    while (matchStart >= 0) {
      const matchEnd: number = matchStart + normalizedQuery.length;
      if (matchEnd > startOffset && matchStart < endOffset) {
        const visibleMatchStart: number = Math.max(startOffset, matchStart);
        const visibleMatchEnd: number = Math.min(endOffset, matchEnd);
        if (visibleMatchStart > fragmentCursor) {
          segments.push(this.createSearchSegment(
            blockText.substring(fragmentCursor, visibleMatchStart),
            false,
            false
          ));
        }
        segments.push(this.createSearchSegment(
          blockText.substring(visibleMatchStart, visibleMatchEnd),
          true,
          matchIndex === activeMatchIndex
        ));
        fragmentCursor = visibleMatchEnd;
      }
      matchIndex += 1;
      searchCursor = matchEnd;
      matchStart = normalizedText.indexOf(normalizedQuery, searchCursor);
    }
    if (fragmentCursor < endOffset) {
      segments.push(this.createSearchSegment(blockText.substring(fragmentCursor, endOffset), false, false));
    }
    if (segments.length === 0) {
      segments.push(this.createSearchSegment(blockText.substring(startOffset, endOffset), false, false));
    }
    return segments;
  }

  private findAnchorResolution(
    document: ReadingDocument,
    candidate: ReadingAnchor
  ): ReadingAnchorResolution | undefined {
    if (candidate.documentId !== document.id || document.blocks.length === 0) {
      return undefined;
    }
    const exactBlockIndex: number = this.findBlockIndex(document, candidate.blockId);
    if (exactBlockIndex >= 0) {
      return {
        blockIndex: exactBlockIndex,
        characterOffset: this.resolveOffsetWithinBlock(document.blocks[exactBlockIndex], candidate)
      };
    }
    const fingerprintBlockIndex: number = this.findFingerprintBlockIndex(document, candidate);
    if (fingerprintBlockIndex >= 0) {
      return {
        blockIndex: fingerprintBlockIndex,
        characterOffset: this.resolveOffsetWithinBlock(document.blocks[fingerprintBlockIndex], candidate)
      };
    }
    return this.findContextResolution(document, candidate);
  }

  private findFingerprintBlockIndex(document: ReadingDocument, candidate: ReadingAnchor): number {
    const fingerprint: string = candidate.blockFingerprint ?? '';
    if (fingerprint.length === 0) {
      return -1;
    }
    const preferredIndex: number = candidate.blockIndex === undefined ? -1 : candidate.blockIndex;
    let selectedIndex: number = -1;
    let selectedDistance: number = Number.MAX_SAFE_INTEGER;
    for (let index: number = 0; index < document.blocks.length; index++) {
      if (buildReadingBlockFingerprint(document.blocks[index]) !== fingerprint) {
        continue;
      }
      const distance: number = preferredIndex < 0 ? index : Math.abs(index - preferredIndex);
      if (distance < selectedDistance) {
        selectedIndex = index;
        selectedDistance = distance;
      }
    }
    return selectedIndex;
  }

  private findContextResolution(
    document: ReadingDocument,
    candidate: ReadingAnchor
  ): ReadingAnchorResolution | undefined {
    const preferredIndex: number = candidate.blockIndex === undefined ? -1 : candidate.blockIndex;
    let selected: ReadingAnchorResolution | undefined = undefined;
    let selectedDistance: number = Number.MAX_SAFE_INTEGER;
    for (let index: number = 0; index < document.blocks.length; index++) {
      const contextOffset: number = this.findContextOffset(document.blocks[index].text, candidate);
      if (contextOffset < 0) {
        continue;
      }
      const distance: number = preferredIndex < 0 ? index : Math.abs(index - preferredIndex);
      if (distance < selectedDistance) {
        selected = { blockIndex: index, characterOffset: contextOffset };
        selectedDistance = distance;
      }
    }
    return selected;
  }

  private resolveOffsetWithinBlock(block: ReadingDocumentBlock, candidate: ReadingAnchor): number {
    const fingerprint: string = candidate.blockFingerprint ?? '';
    if (fingerprint.length === 0 || buildReadingBlockFingerprint(block) === fingerprint) {
      return this.clampOffset(candidate.characterOffset, block.text.length);
    }
    const contextOffset: number = this.findContextOffset(block.text, candidate);
    return contextOffset >= 0
      ? contextOffset
      : this.clampOffset(candidate.characterOffset, block.text.length);
  }

  private findContextOffset(text: string, candidate: ReadingAnchor): number {
    const before: string = candidate.contextBefore ?? '';
    const after: string = candidate.contextAfter ?? '';
    const expectedOffset: number = this.clampOffset(candidate.characterOffset, text.length);
    if (before.length > 0 && after.length > 0) {
      const combinedIndex: number = this.findClosestOccurrence(
        text,
        `${before}${after}`,
        Math.max(0, expectedOffset - before.length)
      );
      if (combinedIndex >= 0) {
        return combinedIndex + before.length;
      }
    }
    if (before.length > 0) {
      const beforeIndex: number = this.findClosestOccurrence(
        text,
        before,
        Math.max(0, expectedOffset - before.length)
      );
      if (beforeIndex >= 0) {
        return beforeIndex + before.length;
      }
    }
    if (after.length > 0) {
      return this.findClosestOccurrence(text, after, expectedOffset);
    }
    return -1;
  }

  private findClosestOccurrence(text: string, value: string, expectedStart: number): number {
    if (value.length === 0) {
      return -1;
    }
    let selectedIndex: number = -1;
    let selectedDistance: number = Number.MAX_SAFE_INTEGER;
    let searchStart: number = 0;
    let matchIndex: number = text.indexOf(value, searchStart);
    while (matchIndex >= 0) {
      const distance: number = Math.abs(matchIndex - expectedStart);
      if (distance < selectedDistance) {
        selectedIndex = matchIndex;
        selectedDistance = distance;
      }
      searchStart = matchIndex + 1;
      matchIndex = text.indexOf(value, searchStart);
    }
    return selectedIndex;
  }

  private resolveDocumentStartAnchor(document: ReadingDocument): ReadingAnchor {
    if (document.blocks.length === 0) {
      return createReadingAnchor(document.id, '', 0);
    }
    return this.createAnchor(document, document.blocks[0].id, 0);
  }

  private clampOffset(value: number, textLength: number): number {
    return Math.max(0, Math.min(textLength, Math.floor(value)));
  }

  private resolveVerticalFragmentEnd(text: string, startOffset: number, maximumLength: number): number {
    const targetEnd: number = Math.min(text.length, startOffset + maximumLength);
    if (targetEnd >= text.length) {
      return text.length;
    }
    const minimumBreak: number = startOffset + Math.floor(maximumLength * 0.75);
    for (let index: number = targetEnd - 1; index >= minimumBreak; index--) {
      if (this.isPreferredBreakCharacter(text.charAt(index))) {
        return index + 1;
      }
    }
    return targetEnd;
  }

  private isPreferredBreakCharacter(value: string): boolean {
    return value === ' ' || value === '\n' || value === '\t' || value === '，' || value === '。' ||
      value === '；' || value === '！' || value === '？' || value === ',' || value === '.' ||
      value === ';' || value === '!' || value === '?';
  }

  private createVerticalFragment(
    block: ReadingDocumentBlock,
    blockIndex: number,
    startCharacterOffset: number,
    endCharacterOffset: number,
    atomic: boolean,
    lastInBlock: boolean
  ): ReadingVerticalFragment {
    return {
      blockId: block.id,
      blockIndex: blockIndex,
      startCharacterOffset: startCharacterOffset,
      endCharacterOffset: endCharacterOffset,
      atomic: atomic,
      lastInBlock: lastInBlock
    };
  }

  private createSearchSegment(text: string, highlighted: boolean, active: boolean): ReadingSearchTextSegment {
    return {
      text: text,
      highlighted: highlighted,
      active: active
    };
  }
}

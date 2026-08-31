import {
  ReadingAnchor,
  ReadingDocument,
  ReadingDocumentBlock,
  buildReadingTextFingerprint,
  createReadingAnchor
} from '../reading/ReadingDocumentModels';
import { ReadingDocumentFlow } from '../reading/ReadingDocumentFlow';
import { NovelSessionCommittedChapter } from './NovelReadingSessionState';
import { NovelReadingPosition } from './NovelReaderModels';

export class NovelReadingDocumentAdapter {
  private readonly documentFlow: ReadingDocumentFlow = new ReadingDocumentFlow();

  adapt(chapter: NovelSessionCommittedChapter): ReadingDocument {
    const blocks: ReadingDocumentBlock[] = [];
    this.appendParagraphBlocks(blocks, chapter);
    return {
      id: chapter.id,
      title: chapter.title,
      subtitle: '',
      blocks: blocks
    };
  }

  adaptTrail(chapters: NovelSessionCommittedChapter[], bookTitle: string): ReadingDocument {
    const blocks: ReadingDocumentBlock[] = [];
    for (let chapterIndex: number = 0; chapterIndex < chapters.length; chapterIndex++) {
      const chapter: NovelSessionCommittedChapter = chapters[chapterIndex];
      blocks.push({
        id: this.buildChapterTitleId(chapter.id),
        type: 'heading',
        text: chapter.title,
        level: 2
      });
      this.appendParagraphBlocks(blocks, chapter);
    }
    return {
      id: this.resolveTrailDocumentId(chapters),
      title: bookTitle,
      subtitle: '',
      blocks: blocks
    };
  }

  characterOffsetToAnchor(document: ReadingDocument, characterOffset: number): ReadingAnchor {
    if (document.blocks.length === 0) {
      return createReadingAnchor(document.id, '', 0);
    }
    let remaining: number = Math.max(0, Math.floor(characterOffset));
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ReadingDocumentBlock = document.blocks[index];
      if (remaining <= block.text.length || index === document.blocks.length - 1) {
        return this.documentFlow.createAnchor(document, block.id, Math.min(remaining, block.text.length));
      }
      remaining = remaining - block.text.length - 1;
    }
    const lastBlock: ReadingDocumentBlock = document.blocks[document.blocks.length - 1];
    return this.documentFlow.createAnchor(document, lastBlock.id, lastBlock.text.length);
  }

  anchorToCharacterOffset(document: ReadingDocument, anchor: ReadingAnchor): number {
    const resolvedAnchor: ReadingAnchor = this.documentFlow.resolveAnchor(document, anchor);
    let offset: number = 0;
    for (let index: number = 0; index < document.blocks.length; index++) {
      const block: ReadingDocumentBlock = document.blocks[index];
      if (block.id === resolvedAnchor.blockId) {
        return offset + Math.min(Math.max(0, resolvedAnchor.characterOffset), block.text.length);
      }
      offset = offset + block.text.length;
      if (index + 1 < document.blocks.length) {
        offset = offset + 1;
      }
    }
    return 0;
  }

  anchorToTrailPosition(
    chapters: NovelSessionCommittedChapter[],
    anchor: ReadingAnchor
  ): NovelReadingPosition | undefined {
    const trailDocument: ReadingDocument = this.adaptTrail(chapters, '');
    const resolvedAnchor: ReadingAnchor = this.documentFlow.resolveAnchor(trailDocument, anchor);
    for (let chapterIndex: number = 0; chapterIndex < chapters.length; chapterIndex++) {
      const chapter: NovelSessionCommittedChapter = chapters[chapterIndex];
      const document: ReadingDocument = this.adapt(chapter);
      for (let blockIndex: number = 0; blockIndex < document.blocks.length; blockIndex++) {
        if (document.blocks[blockIndex].id === resolvedAnchor.blockId) {
          const chapterAnchor: ReadingAnchor = this.documentFlow.createAnchor(
            document,
            resolvedAnchor.blockId,
            resolvedAnchor.characterOffset
          );
          return {
            chapterId: chapter.id,
            characterOffset: this.anchorToCharacterOffset(document, chapterAnchor)
          };
        }
      }
      if (this.buildChapterTitleId(chapter.id) === resolvedAnchor.blockId) {
        return {
          chapterId: chapter.id,
          characterOffset: 0
        };
      }
    }
    return undefined;
  }

  trailPositionToAnchor(
    chapters: NovelSessionCommittedChapter[],
    position: NovelReadingPosition
  ): ReadingAnchor {
    for (let chapterIndex: number = 0; chapterIndex < chapters.length; chapterIndex++) {
      const chapter: NovelSessionCommittedChapter = chapters[chapterIndex];
      if (chapter.id === position.chapterId) {
        const chapterAnchor: ReadingAnchor = this.characterOffsetToAnchor(
          this.adapt(chapter),
          position.characterOffset
        );
        const trailDocument: ReadingDocument = this.adaptTrail(chapters, '');
        return this.documentFlow.createAnchor(
          trailDocument,
          chapterAnchor.blockId,
          chapterAnchor.characterOffset
        );
      }
    }
    if (chapters.length === 0) {
      return createReadingAnchor('', '', 0);
    }
    const trailDocument: ReadingDocument = this.adaptTrail(chapters, '');
    return this.documentFlow.createAnchor(
      trailDocument,
      trailDocument.blocks.length > 0 ? trailDocument.blocks[0].id : '',
      0
    );
  }

  private appendParagraphBlocks(
    blocks: ReadingDocumentBlock[],
    chapter: NovelSessionCommittedChapter
  ): void {
    const occurrenceByFingerprint: Map<string, number> = new Map();
    for (let index: number = 0; index < chapter.paragraphs.length; index++) {
      const text: string = chapter.paragraphs[index];
      const fingerprint: string = buildReadingTextFingerprint(text);
      const occurrence: number = occurrenceByFingerprint.get(fingerprint) ?? 0;
      occurrenceByFingerprint.set(fingerprint, occurrence + 1);
      blocks.push({
        id: this.buildParagraphId(chapter.id, fingerprint, occurrence),
        type: 'paragraph',
        text: text
      });
    }
  }

  private buildParagraphId(chapterId: string, fingerprint: string, occurrence: number): string {
    return `${chapterId}:paragraph:${fingerprint}:${occurrence}`;
  }

  private buildChapterTitleId(chapterId: string): string {
    return `${chapterId}:title`;
  }

  private resolveTrailDocumentId(chapters: NovelSessionCommittedChapter[]): string {
    if (chapters.length === 0) {
      return '';
    }
    const bookId: string = chapters[0].bookId.trim();
    return bookId.length > 0 ? bookId : chapters[0].id;
  }
}

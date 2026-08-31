import {
  ReaderModeArticle,
  ReaderModeBlock,
  ReaderModeBlockType
} from './ReaderModeModels';

const READER_SPEECH_MAX_CHUNK_LENGTH: number = 220;
const READER_SPEECH_MIN_SENTENCE_CHUNK_LENGTH: number = 40;

export class ReaderSpeechTextBuilder {
  buildChunks(article: ReaderModeArticle): string[] {
    const sections = this.collectSpeakableSections(article);
    const chunks: string[] = [];
    sections.forEach((section: string) => {
      this.appendSectionChunks(section, chunks);
    });
    return chunks;
  }

  private collectSpeakableSections(article: ReaderModeArticle): string[] {
    const sections: string[] = [];
    this.appendText(sections, article.title);
    this.appendText(sections, article.byline);
    article.blocks.forEach((block: ReaderModeBlock) => {
      if (!this.isSpeakableBlock(block.type)) {
        return;
      }
      this.appendText(sections, block.text);
    });
    return sections;
  }

  private appendText(sections: string[], text: string): void {
    const normalized = this.normalizeWhitespace(text);
    if (normalized.length <= 0) {
      return;
    }
    const last = sections.length > 0 ? sections[sections.length - 1] : '';
    if (last === normalized) {
      return;
    }
    sections.push(normalized);
  }

  private appendSectionChunks(section: string, chunks: string[]): void {
    const sentences = this.splitSentences(section);
    let pending = '';
    sentences.forEach((sentence: string) => {
      if (pending.length <= 0) {
        pending = sentence;
        return;
      }
      if (pending.length + sentence.length + 1 <= READER_SPEECH_MAX_CHUNK_LENGTH) {
        pending = `${pending} ${sentence}`;
        return;
      }
      this.appendLongSafeChunk(pending, chunks);
      pending = sentence;
    });
    this.appendLongSafeChunk(pending, chunks);
  }

  private appendLongSafeChunk(text: string, chunks: string[]): void {
    const normalized = text.trim();
    if (normalized.length <= 0) {
      return;
    }
    if (normalized.length <= READER_SPEECH_MAX_CHUNK_LENGTH) {
      chunks.push(normalized);
      return;
    }
    let cursor = 0;
    while (cursor < normalized.length) {
      const end = Math.min(normalized.length, cursor + READER_SPEECH_MAX_CHUNK_LENGTH);
      chunks.push(normalized.substring(cursor, end).trim());
      cursor = end;
    }
  }

  private splitSentences(text: string): string[] {
    const sentences: string[] = [];
    let cursor = 0;
    for (let index = 0; index < text.length; index += 1) {
      const ch = text.charAt(index);
      if (!this.isSentenceBoundary(ch)) {
        continue;
      }
      const sentence = text.substring(cursor, index + 1).trim();
      if (sentence.length > 0) {
        sentences.push(sentence);
      }
      cursor = index + 1;
    }
    const tail = text.substring(cursor).trim();
    if (tail.length > 0) {
      if (sentences.length > 0 && tail.length < READER_SPEECH_MIN_SENTENCE_CHUNK_LENGTH) {
        const lastIndex = sentences.length - 1;
        if (sentences[lastIndex].length + tail.length + 1 <= READER_SPEECH_MAX_CHUNK_LENGTH) {
          sentences[lastIndex] = `${sentences[lastIndex]} ${tail}`;
          return sentences;
        }
      }
      sentences.push(tail);
    }
    return sentences;
  }

  private normalizeWhitespace(text: string): string {
    return text.replace(/\s+/g, ' ').trim();
  }

  private isSpeakableBlock(type: ReaderModeBlockType): boolean {
    return type === 'heading' || type === 'paragraph' || type === 'quote' || type === 'list_item';
  }

  private isSentenceBoundary(ch: string): boolean {
    return ch === '。' || ch === '！' || ch === '？' || ch === '.' || ch === '!' || ch === '?' || ch === ';' ||
      ch === '；';
  }
}

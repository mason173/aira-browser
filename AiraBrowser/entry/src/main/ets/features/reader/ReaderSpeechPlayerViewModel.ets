import { ReaderModeArticle, ReaderModeBlock } from './ReaderModeModels';
import { ReaderSpeechState } from './ReaderSpeechModels';

export interface ReaderSpeechPlayerSnapshot {
  title: string;
  subtitle: string;
  source: string;
  coverImageUrl: string;
  currentText: string;
  progressLabel: string;
  progressPercent: number;
  statusLabel: string;
}

export class ReaderSpeechPlayerViewModel {
  buildSnapshot(article: ReaderModeArticle, chunks: string[], speechState: ReaderSpeechState): ReaderSpeechPlayerSnapshot {
    const currentIndex = this.resolveCurrentChunkIndex(speechState, chunks.length);
    return {
      title: this.resolveTitle(article),
      subtitle: this.resolveSubtitle(article),
      source: this.resolveSource(article),
      coverImageUrl: this.resolveCoverImageUrl(article),
      currentText: this.resolveCurrentText(chunks, currentIndex),
      progressLabel: this.resolveProgressLabel(speechState, chunks.length),
      progressPercent: this.resolveProgressPercent(speechState, chunks.length),
      statusLabel: this.resolveStatusLabel(speechState)
    };
  }

  resolvePreviousChunkIndex(speechState: ReaderSpeechState, totalChunks: number): number {
    const currentIndex = this.resolveCurrentChunkIndex(speechState, totalChunks);
    return Math.max(0, currentIndex - 1);
  }

  resolveNextChunkIndex(speechState: ReaderSpeechState, totalChunks: number): number {
    const currentIndex = this.resolveCurrentChunkIndex(speechState, totalChunks);
    return Math.min(Math.max(0, totalChunks - 1), currentIndex + 1);
  }

  resolveCurrentChunkStartIndex(speechState: ReaderSpeechState, totalChunks: number): number {
    return this.resolveCurrentChunkIndex(speechState, totalChunks);
  }

  private resolveCurrentChunkIndex(speechState: ReaderSpeechState, totalChunks: number): number {
    if (totalChunks <= 0) {
      return 0;
    }
    const index = speechState.currentChunkIndex > 0 ? speechState.currentChunkIndex - 1 : 0;
    return Math.max(0, Math.min(index, totalChunks - 1));
  }

  private resolveTitle(article: ReaderModeArticle): string {
    const title = article.title.trim();
    return title.length > 0 ? title : '听读正文';
  }

  private resolveSubtitle(article: ReaderModeArticle): string {
    const parts: string[] = [];
    if (article.siteName.trim().length > 0) {
      parts.push(article.siteName.trim());
    }
    if (article.byline.trim().length > 0) {
      parts.push(article.byline.trim());
    }
    return parts.length > 0 ? parts.join(' · ') : '阅读模式';
  }

  private resolveSource(article: ReaderModeArticle): string {
    if (article.url.trim().length <= 0) {
      return 'Aira';
    }
    const source = article.url.replace(/^https?:\/\//, '').split('/')[0];
    return source.length > 0 ? source : 'Aira';
  }

  private resolveCoverImageUrl(article: ReaderModeArticle): string {
    for (let index = 0; index < article.blocks.length; index += 1) {
      const block = article.blocks[index];
      if (block.type !== 'image') {
        continue;
      }
      const imageUrl = this.resolveBlockImageUrl(block);
      if (imageUrl.length > 0) {
        return imageUrl;
      }
    }
    return '';
  }

  private resolveBlockImageUrl(block: ReaderModeBlock): string {
    const urls: string[] = [];
    this.addImageUrl(urls, block.url ?? '');
    this.addImageUrl(urls, block.originalUrl ?? '');
    (block.fallbackUrls ?? []).forEach((url: string) => {
      this.addImageUrl(urls, url);
    });
    return urls.length > 0 ? urls[0] : '';
  }

  private addImageUrl(urls: string[], url: string): void {
    const normalized = url.trim();
    if (normalized.length <= 0 || urls.indexOf(normalized) >= 0) {
      return;
    }
    urls.push(normalized);
  }

  private resolveCurrentText(chunks: string[], currentIndex: number): string {
    if (chunks.length <= 0) {
      return '正文整理完成后即可开始朗读。';
    }
    return chunks[currentIndex] ?? chunks[0];
  }

  private resolveProgressLabel(speechState: ReaderSpeechState, totalChunks: number): string {
    if (totalChunks <= 0) {
      return '暂无可朗读正文';
    }
    const current = Math.max(1, Math.min(speechState.currentChunkIndex > 0 ? speechState.currentChunkIndex : 1, totalChunks));
    return `第 ${current} 段 / 共 ${totalChunks} 段`;
  }

  private resolveProgressPercent(speechState: ReaderSpeechState, totalChunks: number): number {
    if (totalChunks <= 0) {
      return 0;
    }
    const current = Math.max(0, Math.min(speechState.currentChunkIndex, totalChunks));
    return Math.round((current / totalChunks) * 100);
  }

  private resolveStatusLabel(speechState: ReaderSpeechState): string {
    if (speechState.status === 'preparing') {
      return '准备朗读';
    }
    if (speechState.status === 'speaking') {
      return '正在朗读';
    }
    if (speechState.status === 'paused') {
      return '已暂停';
    }
    if (speechState.status === 'stopping') {
      return '正在停止';
    }
    if (speechState.status === 'error') {
      return speechState.message.length > 0 ? speechState.message : '朗读失败';
    }
    return '未开始';
  }
}

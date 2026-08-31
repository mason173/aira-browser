import {
  ReaderModeArticle,
  ReaderModeArticleDiagnostics,
  ReaderModeBlock
} from './ReaderModeModels';

const MIN_PARAGRAPH_TEXT_LENGTH: number = 18;
const MIN_LIST_ITEM_TEXT_LENGTH: number = 8;
const MIN_LINK_TEXT_LENGTH: number = 12;
const MIN_HEADING_TEXT_LENGTH: number = 2;
const MAX_MERGED_PARAGRAPH_LENGTH: number = 360;

interface ReaderPostProcessStats {
  rawBlockCount: number;
  retainedBlockCount: number;
  removedDuplicateCount: number;
  removedCaptionDuplicateCount: number;
  removedShortTextCount: number;
  removedNoiseCount: number;
  removedLinkCount: number;
  mergedParagraphCount: number;
}

interface ReaderBlockRetentionDecision {
  keep: boolean;
  reason: string;
}

export class ReaderArticlePostProcessor {
  process(article: ReaderModeArticle): ReaderModeArticle {
    const stats: ReaderPostProcessStats = {
      rawBlockCount: article.blocks.length,
      retainedBlockCount: 0,
      removedDuplicateCount: 0,
      removedCaptionDuplicateCount: 0,
      removedShortTextCount: 0,
      removedNoiseCount: 0,
      removedLinkCount: 0,
      mergedParagraphCount: 0
    };
    const titleKey = this.normalizeComparableText(article.title);
    const seenTextKeys: Record<string, boolean> = {};
    const filteredBlocks: ReaderModeBlock[] = [];
    const imageCaptionKeys = this.buildImageCaptionKeys(article.blocks);

    article.blocks.forEach((block: ReaderModeBlock) => {
      const decision = this.shouldRetainBlock(block, titleKey, seenTextKeys, imageCaptionKeys);
      if (!decision.keep) {
        this.recordRemoval(stats, decision.reason);
        return;
      }
      filteredBlocks.push(block);
    });

    const mergedBlocks = this.mergeAdjacentShortParagraphs(filteredBlocks, stats);
    stats.retainedBlockCount = mergedBlocks.length;

    return {
      title: article.title,
      byline: article.byline,
      siteName: article.siteName,
      publishedAt: article.publishedAt,
      url: article.url,
      excerpt: article.excerpt,
      diagnostics: this.buildDiagnostics(article.diagnostics, stats),
      blocks: mergedBlocks
    };
  }

  private shouldRetainBlock(
    block: ReaderModeBlock,
    titleKey: string,
    seenTextKeys: Record<string, boolean>,
    imageCaptionKeys: Record<string, boolean>
  ): ReaderBlockRetentionDecision {
    if (block.type === 'image') {
      return this.buildRetentionDecision(true, '');
    }
    const text = block.text.trim();
    const textKey = this.normalizeComparableText(text);
    if (text.length <= 0) {
      return this.buildRetentionDecision(false, 'short_text');
    }
    if (this.isNoiseText(text)) {
      return this.buildRetentionDecision(false, 'noise');
    }
    if (this.isImageCaptionDuplicate(block, textKey, imageCaptionKeys)) {
      return this.buildRetentionDecision(false, 'caption_duplicate');
    }
    if (block.type === 'heading' && (text.length < MIN_HEADING_TEXT_LENGTH || textKey === titleKey)) {
      return this.buildRetentionDecision(false, textKey === titleKey ? 'duplicate' : 'short_text');
    }
    if (block.type === 'paragraph' && text.length < MIN_PARAGRAPH_TEXT_LENGTH) {
      return this.buildRetentionDecision(false, 'short_text');
    }
    if (block.type === 'list_item' && text.length < MIN_LIST_ITEM_TEXT_LENGTH) {
      return this.buildRetentionDecision(false, 'short_text');
    }
    if (block.type === 'link' && !this.isUsefulStandaloneLink(block)) {
      return this.buildRetentionDecision(false, 'link');
    }
    if (textKey.length > 0 && seenTextKeys[textKey]) {
      return this.buildRetentionDecision(false, 'duplicate');
    }
    if (textKey.length > 0) {
      seenTextKeys[textKey] = true;
    }
    return this.buildRetentionDecision(true, '');
  }

  private buildRetentionDecision(keep: boolean, reason: string): ReaderBlockRetentionDecision {
    return {
      keep: keep,
      reason: reason
    };
  }

  private mergeAdjacentShortParagraphs(blocks: ReaderModeBlock[], stats: ReaderPostProcessStats): ReaderModeBlock[] {
    const merged: ReaderModeBlock[] = [];
    blocks.forEach((block: ReaderModeBlock) => {
      if (block.type !== 'paragraph' || merged.length <= 0) {
        merged.push(block);
        return;
      }
      const previous = merged[merged.length - 1];
      if (previous.type !== 'paragraph') {
        merged.push(block);
        return;
      }
      const previousText = previous.text.trim();
      const currentText = block.text.trim();
      if (previousText.length + currentText.length > MAX_MERGED_PARAGRAPH_LENGTH) {
        merged.push(block);
        return;
      }
      if (!this.shouldMergeParagraph(previousText, currentText)) {
        merged.push(block);
        return;
      }
      merged[merged.length - 1] = this.cloneBlockWithText(previous, `${previousText}${this.resolveParagraphJoiner(previousText)}${currentText}`);
      stats.mergedParagraphCount += 1;
    });
    return merged;
  }

  private shouldMergeParagraph(previousText: string, currentText: string): boolean {
    if (previousText.length >= MIN_PARAGRAPH_TEXT_LENGTH && currentText.length >= MIN_PARAGRAPH_TEXT_LENGTH) {
      return false;
    }
    return !this.endsAsCompleteSentence(previousText);
  }

  private resolveParagraphJoiner(previousText: string): string {
    if (previousText.endsWith('，') || previousText.endsWith(',') || previousText.endsWith('、')) {
      return '';
    }
    return ' ';
  }

  private endsAsCompleteSentence(text: string): boolean {
    if (text.length <= 0) {
      return false;
    }
    const last = text.charAt(text.length - 1);
    return last === '。' || last === '！' || last === '？' || last === '.' || last === '!' || last === '?' ||
      last === '；' || last === ';';
  }

  private cloneBlockWithText(block: ReaderModeBlock, text: string): ReaderModeBlock {
    return {
      id: block.id,
      type: block.type,
      text: text,
      url: block.url,
      originalUrl: block.originalUrl,
      fallbackUrls: block.fallbackUrls,
      alt: block.alt,
      caption: block.caption,
      level: block.level,
      width: block.width,
      height: block.height,
      renderedWidth: block.renderedWidth,
      renderedHeight: block.renderedHeight,
      qualityScore: block.qualityScore,
      hiddenReason: block.hiddenReason,
      imageFailurePolicy: block.imageFailurePolicy,
      sourceTagName: block.sourceTagName,
      sourceClassName: block.sourceClassName,
      sourceId: block.sourceId,
      sourceRole: block.sourceRole
    };
  }

  private isUsefulStandaloneLink(block: ReaderModeBlock): boolean {
    const text = block.text.trim();
    const url = (block.url ?? '').trim();
    if (text.length < MIN_LINK_TEXT_LENGTH || url.length <= 0) {
      return false;
    }
    if (this.isNoiseText(text)) {
      return false;
    }
    const normalizedUrl = url.toLowerCase();
    return normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://');
  }

  private isNoiseText(text: string): boolean {
    const normalized = text.trim().toLowerCase();
    if (normalized.length <= 0) {
      return true;
    }
    const compact = normalized.replace(/\s+/g, '');
    if (/^(图|表)\\s*\\d+[:：.．]/.test(compact)) {
      return false;
    }
    return compact === '展开阅读全文' || compact === '阅读全文' || compact === '点击阅读全文' ||
      compact === '阅读原文' || compact === '查看原文' || compact === '打开app' ||
      compact === '下载app' || compact === '分享' || compact === '点赞' ||
      compact === '收藏' || compact === '评论' || compact === '相关推荐' ||
      compact === '推荐阅读' || compact === '热门推荐' || compact === '广告' ||
      compact === '赞赏' || compact === '写评论' || compact === '发布评论' ||
      compact === '登录后评论' || compact === '全部评论' || compact === '更多精彩内容';
  }

  private buildImageCaptionKeys(blocks: ReaderModeBlock[]): Record<string, boolean> {
    const keys: Record<string, boolean> = {};
    blocks.forEach((block: ReaderModeBlock) => {
      if (block.type !== 'image') {
        return;
      }
      const captionKey = this.normalizeComparableText(block.caption ?? '');
      if (captionKey.length > 0) {
        keys[captionKey] = true;
      }
      const altKey = this.normalizeComparableText(block.alt ?? '');
      if (altKey.length > 0) {
        keys[altKey] = true;
      }
    });
    return keys;
  }

  private isImageCaptionDuplicate(
    block: ReaderModeBlock,
    textKey: string,
    imageCaptionKeys: Record<string, boolean>
  ): boolean {
    if (block.type === 'heading' || block.type === 'code' || block.type === 'quote') {
      return false;
    }
    if (textKey.length <= 0 || !imageCaptionKeys[textKey]) {
      return false;
    }
    return block.text.trim().length <= 80;
  }

  private normalizeComparableText(text: string): string {
    return text.trim().toLowerCase()
      .replace(/\s+/g, '')
      .replace(/[，。！？、；：,.!?;:"'“”‘’（）()[\]{}<>《》]/g, '');
  }

  private recordRemoval(stats: ReaderPostProcessStats, reason: string): void {
    if (reason === 'duplicate') {
      stats.removedDuplicateCount += 1;
      return;
    }
    if (reason === 'caption_duplicate') {
      stats.removedCaptionDuplicateCount += 1;
      return;
    }
    if (reason === 'short_text') {
      stats.removedShortTextCount += 1;
      return;
    }
    if (reason === 'noise') {
      stats.removedNoiseCount += 1;
      return;
    }
    if (reason === 'link') {
      stats.removedLinkCount += 1;
    }
  }

  private buildDiagnostics(
    diagnostics: ReaderModeArticleDiagnostics | undefined,
    stats: ReaderPostProcessStats
  ): ReaderModeArticleDiagnostics {
    const base: ReaderModeArticleDiagnostics = diagnostics ?? {
      adapterId: '',
      sourceTagName: '',
      sourceClassName: '',
      sourceTextLength: 0,
      sourceScore: 0,
      candidateCount: 0,
      extractionStrategy: ''
    };
    const previousSummary = base.postProcessSummary ?? '';
    const summary = `blocks:${stats.retainedBlockCount}/${stats.rawBlockCount},duplicate:${stats.removedDuplicateCount},` +
      `caption:${stats.removedCaptionDuplicateCount},` +
      `short:${stats.removedShortTextCount},noise:${stats.removedNoiseCount},links:${stats.removedLinkCount},` +
      `merged:${stats.mergedParagraphCount}`;
    return {
      adapterId: base.adapterId,
      sourceTagName: base.sourceTagName,
      sourceClassName: base.sourceClassName,
      sourceTextLength: base.sourceTextLength,
      sourceScore: base.sourceScore,
      candidateCount: base.candidateCount,
      extractionStrategy: base.extractionStrategy,
      rawBlockCount: stats.rawBlockCount,
      retainedBlockCount: stats.retainedBlockCount,
      rawImageCount: base.rawImageCount,
      retainedImageCount: base.retainedImageCount,
      hiddenImageCount: base.hiddenImageCount,
      postProcessSummary: previousSummary.length > 0 ? `${previousSummary};${summary}` : summary
    };
  }
}

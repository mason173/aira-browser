import {
  ReaderModeArticle,
  ReaderModeArticleDiagnostics,
  ReaderModeBlock
} from './ReaderModeModels';

const MIN_READER_IMAGE_WIDTH: number = 120;
const MIN_READER_IMAGE_HEIGHT: number = 80;
const MIN_READER_RENDERED_WIDTH: number = 80;
const MIN_READER_RENDERED_HEIGHT: number = 60;
const MIN_READER_IMAGE_AREA: number = 18000;
const IMAGE_TEXT_SIGNAL_MIN_LENGTH: number = 8;

interface ReaderImageQualityDecision {
  keep: boolean;
  score: number;
  reason: string;
}

export class ReaderImageQualityService {
  filterArticleImages(article: ReaderModeArticle): ReaderModeArticle {
    let rawImageCount = 0;
    let retainedImageCount = 0;
    let hiddenImageCount = 0;
    const retainedBlocks: ReaderModeBlock[] = [];

    article.blocks.forEach((block: ReaderModeBlock) => {
      if (block.type !== 'image') {
        retainedBlocks.push(block);
        return;
      }
      rawImageCount += 1;
      const decision = this.evaluateImage(block);
      if (!decision.keep) {
        hiddenImageCount += 1;
        return;
      }
      retainedImageCount += 1;
      retainedBlocks.push({
        id: block.id,
        type: block.type,
        text: block.text,
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
        qualityScore: decision.score,
        hiddenReason: '',
        imageFailurePolicy: this.resolveFailurePolicy(block, decision.score),
        sourceTagName: block.sourceTagName,
        sourceClassName: block.sourceClassName,
        sourceId: block.sourceId,
        sourceRole: block.sourceRole
      });
    });

    return {
      title: article.title,
      byline: article.byline,
      siteName: article.siteName,
      publishedAt: article.publishedAt,
      url: article.url,
      excerpt: article.excerpt,
      diagnostics: this.buildDiagnostics(
        article.diagnostics,
        article.blocks.length,
        retainedBlocks.length,
        rawImageCount,
        retainedImageCount,
        hiddenImageCount
      ),
      blocks: retainedBlocks
    };
  }

  evaluateImage(block: ReaderModeBlock): ReaderImageQualityDecision {
    const url = (block.url ?? '').trim();
    if (url.length <= 0) {
      return this.reject('empty_url', -100);
    }
    if (this.isDecorativeUrl(url)) {
      return this.reject('decorative_url', -90);
    }

    const width = block.width ?? 0;
    const height = block.height ?? 0;
    const renderedWidth = block.renderedWidth ?? 0;
    const renderedHeight = block.renderedHeight ?? 0;
    const knownWidth = width > 0 ? width : renderedWidth;
    const knownHeight = height > 0 ? height : renderedHeight;
    const area = knownWidth * knownHeight;
    const sourceSignal = this.buildSourceSignal(block);

    if (this.hasDecorativeSourceSignal(sourceSignal)) {
      return this.reject('decorative_source', -80);
    }
    const hasCaption = this.hasReadableCaption(block);
    const hasAlt = this.hasReadableAlt(block);
    if (this.isTinyImage(knownWidth, knownHeight, area, renderedWidth, renderedHeight) &&
      !this.hasStrongArticleImageSignal(sourceSignal, hasCaption)) {
      return this.reject('small_image', -70);
    }
    if (this.isLikelyIconShape(knownWidth, knownHeight, sourceSignal, block)) {
      return this.reject('icon_like_shape', -50);
    }

    let score = 35;
    score += Math.min(35, Math.floor(area / 18000));
    if (hasCaption) {
      score += 28;
    }
    if (hasAlt) {
      score += 12;
    }
    if (knownWidth >= 320 && knownHeight >= 160) {
      score += 18;
    }
    if (sourceSignal.indexOf('figure') >= 0 || sourceSignal.indexOf('content') >= 0 ||
      sourceSignal.indexOf('article') >= 0) {
      score += 12;
    }

    return {
      keep: score >= 45,
      score: score,
      reason: score >= 45 ? '' : 'low_quality_score'
    };
  }

  private buildDiagnostics(
    diagnostics: ReaderModeArticleDiagnostics | undefined,
    rawBlockCount: number,
    retainedBlockCount: number,
    rawImageCount: number,
    retainedImageCount: number,
    hiddenImageCount: number
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
    return {
      adapterId: base.adapterId,
      sourceTagName: base.sourceTagName,
      sourceClassName: base.sourceClassName,
      sourceTextLength: base.sourceTextLength,
      sourceScore: base.sourceScore,
      candidateCount: base.candidateCount,
      extractionStrategy: base.extractionStrategy,
      rawBlockCount: rawBlockCount,
      retainedBlockCount: retainedBlockCount,
      rawImageCount: rawImageCount,
      retainedImageCount: retainedImageCount,
      hiddenImageCount: hiddenImageCount,
      postProcessSummary: this.mergeSummary(
        base.postProcessSummary ?? '',
        `images:${retainedImageCount}/${rawImageCount},hidden:${hiddenImageCount}`
      )
    };
  }

  private mergeSummary(previous: string, next: string): string {
    if (previous.length <= 0) {
      return next;
    }
    if (next.length <= 0) {
      return previous;
    }
    return `${previous};${next}`;
  }

  private reject(reason: string, score: number): ReaderImageQualityDecision {
    return {
      keep: false,
      score: score,
      reason: reason
    };
  }

  private isDecorativeUrl(url: string): boolean {
    const normalized = url.toLowerCase();
    if (normalized.startsWith('data:')) {
      return true;
    }
    return normalized.indexOf('.svg') >= 0 || normalized.indexOf('spacer') >= 0 ||
      normalized.indexOf('pixel') >= 0 || normalized.indexOf('avatar') >= 0 ||
      normalized.indexOf('logo') >= 0 || normalized.indexOf('icon') >= 0 ||
      normalized.indexOf('qrcode') >= 0 || normalized.indexOf('/qr') >= 0;
  }

  private buildSourceSignal(block: ReaderModeBlock): string {
    return `${block.sourceTagName ?? ''} ${block.sourceClassName ?? ''} ${block.sourceId ?? ''} ` +
      `${block.sourceRole ?? ''} ${block.alt ?? ''} ${block.caption ?? ''}`.toLowerCase();
  }

  private hasDecorativeSourceSignal(signal: string): boolean {
    return signal.indexOf('avatar') >= 0 || signal.indexOf('icon') >= 0 || signal.indexOf('logo') >= 0 ||
      signal.indexOf('qrcode') >= 0 || signal.indexOf('qr-code') >= 0 || signal.indexOf('share') >= 0 ||
      signal.indexOf('badge') >= 0 || signal.indexOf('sponsor') >= 0 || signal.indexOf('advert') >= 0 ||
      signal.indexOf('banner') >= 0 || signal.indexOf('emoji') >= 0 || signal.indexOf('toolbar') >= 0 ||
      signal.indexOf('comment') >= 0 || signal.indexOf('recommend') >= 0 || signal.indexOf('related') >= 0;
  }

  private isTinyImage(
    width: number,
    height: number,
    area: number,
    renderedWidth: number,
    renderedHeight: number
  ): boolean {
    if (width > 0 && width < MIN_READER_IMAGE_WIDTH) {
      return true;
    }
    if (height > 0 && height < MIN_READER_IMAGE_HEIGHT) {
      return true;
    }
    if (renderedWidth > 0 && renderedWidth < MIN_READER_RENDERED_WIDTH) {
      return true;
    }
    if (renderedHeight > 0 && renderedHeight < MIN_READER_RENDERED_HEIGHT) {
      return true;
    }
    return area > 0 && area < MIN_READER_IMAGE_AREA;
  }

  private isLikelyIconShape(
    width: number,
    height: number,
    sourceSignal: string,
    block: ReaderModeBlock
  ): boolean {
    if (width <= 0 || height <= 0) {
      return false;
    }
    const ratio = width > height ? width / height : height / width;
    const hasTextSignal = this.hasReadableAlt(block) || this.hasReadableCaption(block);
    return ratio <= 1.18 && Math.max(width, height) <= 180 &&
      !hasTextSignal && sourceSignal.indexOf('figure') < 0;
  }

  private hasReadableAlt(block: ReaderModeBlock): boolean {
    return (block.alt ?? block.text ?? '').trim().length >= IMAGE_TEXT_SIGNAL_MIN_LENGTH;
  }

  private hasReadableCaption(block: ReaderModeBlock): boolean {
    return (block.caption ?? '').trim().length >= IMAGE_TEXT_SIGNAL_MIN_LENGTH;
  }

  private hasStrongArticleImageSignal(sourceSignal: string, hasReadableCaption: boolean): boolean {
    if (!hasReadableCaption) {
      return false;
    }
    return sourceSignal.indexOf('figure') >= 0 || sourceSignal.indexOf('image') >= 0 ||
      sourceSignal.indexOf('photo') >= 0 || sourceSignal.indexOf('content') >= 0 ||
      sourceSignal.indexOf('article') >= 0 || sourceSignal.indexOf('ss-img-wrapper') >= 0;
  }

  private resolveFailurePolicy(block: ReaderModeBlock, score: number): string {
    const sourceSignal = this.buildSourceSignal(block);
    if (score >= 76 || this.hasStrongArticleImageSignal(sourceSignal, this.hasReadableCaption(block))) {
      return 'compact_placeholder';
    }
    if (this.hasReadableCaption(block) || this.hasReadableAlt(block)) {
      return 'caption_only';
    }
    return 'hide';
  }
}

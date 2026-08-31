import {
  ReadingDocument,
  ReadingDocumentBlock
} from '../reading/ReadingDocumentModels';
import { ReaderModeArticle, ReaderModeBlock } from './ReaderModeModels';

export class ArticleReadingDocumentAdapter {
  adapt(article: ReaderModeArticle): ReadingDocument {
    const blocks: ReadingDocumentBlock[] = [];
    for (let index: number = 0; index < article.blocks.length; index++) {
      blocks.push(this.adaptBlock(article.blocks[index]));
    }
    return {
      id: article.url,
      title: article.title,
      subtitle: this.buildSubtitle(article),
      blocks: blocks
    };
  }

  private adaptBlock(block: ReaderModeBlock): ReadingDocumentBlock {
    const fallbackUrls: string[] | undefined = block.fallbackUrls === undefined
      ? undefined
      : block.fallbackUrls.slice();
    return {
      id: block.id,
      type: block.type,
      text: block.text,
      url: block.url,
      originalUrl: block.originalUrl,
      fallbackUrls: fallbackUrls,
      alt: block.alt,
      caption: block.caption,
      level: block.level,
      width: block.width,
      height: block.height,
      renderedWidth: block.renderedWidth,
      renderedHeight: block.renderedHeight,
      qualityScore: block.qualityScore,
      hiddenReason: block.hiddenReason,
      imageFailurePolicy: block.imageFailurePolicy
    };
  }

  private buildSubtitle(article: ReaderModeArticle): string {
    const parts: string[] = [];
    if (article.siteName.trim().length > 0) {
      parts.push(article.siteName.trim());
    }
    if (article.byline.trim().length > 0) {
      parts.push(article.byline.trim());
    }
    if (article.publishedAt.trim().length > 0) {
      parts.push(article.publishedAt.trim());
    }
    return parts.join(' · ');
  }
}

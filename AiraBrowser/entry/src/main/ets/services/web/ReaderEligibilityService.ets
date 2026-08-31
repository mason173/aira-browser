import {
  ReaderEligibilityResult,
  ReaderModeProbeCandidate,
  ReaderModeProbeResult
} from '../../features/reader/ReaderModeModels';

const MIN_READER_TEXT_LENGTH: number = 420;
const MIN_READER_PARAGRAPH_COUNT: number = 3;
const MAX_READER_LINK_TEXT_RATIO: number = 0.45;

export class ReaderEligibilityService {
  evaluate(probe: ReaderModeProbeResult): ReaderEligibilityResult {
    const bestCandidate = this.resolveBestCandidate(probe.candidates);
    const textLength = Math.max(probe.textLength, bestCandidate?.textLength ?? 0);
    const paragraphCount = Math.max(probe.paragraphCount, bestCandidate?.paragraphCount ?? 0);
    const linkTextLength = bestCandidate?.linkTextLength ?? probe.linkTextLength;
    const linkTextRatio = textLength <= 0 ? 1 : linkTextLength / textLength;
    let score = 0;

    if (textLength >= MIN_READER_TEXT_LENGTH) {
      score += Math.min(45, Math.floor(textLength / 120));
    }
    if (paragraphCount >= MIN_READER_PARAGRAPH_COUNT) {
      score += Math.min(30, paragraphCount * 5);
    }
    if (linkTextRatio <= MAX_READER_LINK_TEXT_RATIO) {
      score += 20;
    } else {
      score -= 30;
    }
    if (bestCandidate !== undefined && this.isSemanticArticleCandidate(bestCandidate)) {
      score += 16;
    }
    if (this.isUnsupportedUrl(probe.url)) {
      score -= 80;
    }

    const readable = score >= 50 &&
      textLength >= MIN_READER_TEXT_LENGTH &&
      paragraphCount >= MIN_READER_PARAGRAPH_COUNT &&
      linkTextRatio <= MAX_READER_LINK_TEXT_RATIO &&
      !this.isUnsupportedUrl(probe.url);

    return {
      readable: readable,
      score: score,
      reason: this.buildReason(readable, textLength, paragraphCount, linkTextRatio),
      bestSelector: bestCandidate?.selector ?? ''
    };
  }

  private resolveBestCandidate(candidates: ReaderModeProbeCandidate[]): ReaderModeProbeCandidate | undefined {
    if (candidates.length <= 0) {
      return undefined;
    }
    return candidates.reduce((best: ReaderModeProbeCandidate, item: ReaderModeProbeCandidate) => {
      return item.score > best.score ? item : best;
    }, candidates[0]);
  }

  private isSemanticArticleCandidate(candidate: ReaderModeProbeCandidate): boolean {
    const tagName = candidate.tagName.toLowerCase();
    return tagName === 'article' || tagName === 'main' || candidate.selector.indexOf('role=main') >= 0;
  }

  private isUnsupportedUrl(url: string): boolean {
    const normalizedUrl = url.trim().toLowerCase();
    if (normalizedUrl.length <= 0 || normalizedUrl.startsWith('aira://')) {
      return true;
    }
    if (normalizedUrl.indexOf('/search?') >= 0 || normalizedUrl.indexOf('?q=') >= 0) {
      return true;
    }
    return !normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://');
  }

  private buildReason(
    readable: boolean,
    textLength: number,
    paragraphCount: number,
    linkTextRatio: number
  ): string {
    if (readable) {
      return 'reader_candidate';
    }
    if (textLength < MIN_READER_TEXT_LENGTH) {
      return 'text_too_short';
    }
    if (paragraphCount < MIN_READER_PARAGRAPH_COUNT) {
      return 'paragraphs_too_few';
    }
    if (linkTextRatio > MAX_READER_LINK_TEXT_RATIO) {
      return 'link_density_too_high';
    }
    return 'unsupported_page';
  }
}

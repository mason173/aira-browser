import {
  OfflinePageSnapshotResult
} from '../../common/models/OfflinePageModels';
import {
  WebLoadErrorPresentation
} from '../web/WebLoadErrorPresentationService';
import { WebLoadErrorDocumentService } from '../web/WebLoadErrorDocumentService';

export class OfflineErrorDocumentSnapshotService {
  private documentService: WebLoadErrorDocumentService = new WebLoadErrorDocumentService();

  build(presentation: WebLoadErrorPresentation, targetUrl: string): OfflinePageSnapshotResult {
    const normalizedUrl = targetUrl.trim();
    const html = this.documentService.buildHtml(presentation, normalizedUrl);
    return {
      ok: true,
      reason: '',
      metadata: {
        pageUrl: normalizedUrl,
        title: presentation.title,
        siteName: presentation.host,
        host: presentation.host,
        description: presentation.summary,
        htmlLength: html.length,
        visibleTextLength: `${presentation.title}${presentation.summary}`.length,
        imageElementCount: 0,
        mediaElementCount: 0,
        formElementCount: 0,
        resourceUrls: [],
        imageUrls: [],
        inlinedImageUrls: [],
        faviconUrls: []
      },
      html: html
    };
  }

  buildFromCandidates(presentation: WebLoadErrorPresentation, targetUrlCandidates: string[]): OfflinePageSnapshotResult {
    return this.build(presentation, this.resolveTargetUrl(targetUrlCandidates));
  }

  private resolveTargetUrl(candidates: string[]): string {
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index].trim();
      if (value.length > 0) {
        return value;
      }
    }
    return 'about:blank';
  }
}

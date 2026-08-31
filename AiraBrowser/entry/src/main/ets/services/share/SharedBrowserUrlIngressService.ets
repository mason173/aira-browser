import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import urlUtils from '@ohos.url';
import { DocumentViewerService } from '../viewer/DocumentViewerService';

export type SharedBrowserUrlIngressKind = 'browser_url' | 'shared_file' | 'unsupported';

export interface SharedBrowserUrlIngressResolution {
  kind: SharedBrowserUrlIngressKind;
  url: string;
}

const WANT_ACTION_SEND_DATA: string = 'ohos.want.action.sendData';
const HYPERLINK_UTD: string = 'general.hyperlink';
const PLAIN_TEXT_UTD: string = 'general.plain-text';
const HTML_UTD: string = 'general.html';
const XHTML_UTD: string = 'general.xhtml';
const HTML_MIME_TYPE: string = 'text/html';
const XHTML_MIME_TYPE: string = 'application/xhtml+xml';
const ZIP_UTD: string = 'general.zip-archive';
const ZIP_MIME_TYPE: string = 'application/zip';

export class SharedBrowserUrlIngressService {
  private documentViewerService: DocumentViewerService = new DocumentViewerService();

  isCandidate(want: Want): boolean {
    return String(want.action ?? '').trim() === WANT_ACTION_SEND_DATA;
  }

  async resolve(want: Want): Promise<SharedBrowserUrlIngressResolution> {
    let records: systemShare.SharedRecord[] = [];
    try {
      const sharedData = await systemShare.getSharedData(want);
      records = sharedData.getRecords();
    } catch (_error) {
    }
    const preferredRecordUrl = this.resolvePreferredRecordUrl(records);
    if (preferredRecordUrl.length > 0) {
      return {
        kind: 'browser_url',
        url: preferredRecordUrl
      };
    }
    const documentUrl = this.resolveSharedDocumentUrl(records, want);
    if (documentUrl.length > 0) {
      return {
        kind: 'browser_url',
        url: documentUrl
      };
    }
    const fallbackRecordUrl = this.resolveFallbackRecordUrl(records);
    if (fallbackRecordUrl.length > 0) {
      return {
        kind: 'browser_url',
        url: fallbackRecordUrl
      };
    }
    const directUrl = this.extractWebUrl(String(want.uri ?? ''));
    if (directUrl.length > 0) {
      return {
        kind: 'browser_url',
        url: directUrl
      };
    }
    const directDocumentUrl = this.resolveDocumentUrl(
      String(want.uri ?? ''),
      String(want.type ?? ''),
      ''
    );
    if (directDocumentUrl.length > 0) {
      return {
        kind: 'browser_url',
        url: directDocumentUrl
      };
    }
    if (this.hasSharedFile(records, want)) {
      return {
        kind: 'shared_file',
        url: ''
      };
    }
    return {
      kind: 'unsupported',
      url: ''
    };
  }

  private resolvePreferredRecordUrl(records: systemShare.SharedRecord[]): string {
    const preferredDescriptors: string[] = [HYPERLINK_UTD, PLAIN_TEXT_UTD];
    for (let descriptorIndex = 0; descriptorIndex < preferredDescriptors.length; descriptorIndex += 1) {
      const descriptor = preferredDescriptors[descriptorIndex];
      for (let recordIndex = 0; recordIndex < records.length; recordIndex += 1) {
        const record = records[recordIndex];
        if (String(record.utd ?? '').trim().toLowerCase() !== descriptor) {
          continue;
        }
        const url = this.resolveUrlFromRecord(record);
        if (url.length > 0) {
          return url;
        }
      }
    }
    return '';
  }

  private resolveFallbackRecordUrl(records: systemShare.SharedRecord[]): string {
    for (let recordIndex = 0; recordIndex < records.length; recordIndex += 1) {
      const url = this.resolveUrlFromRecord(records[recordIndex]);
      if (url.length > 0) {
        return url;
      }
    }
    return '';
  }

  private resolveSharedDocumentUrl(records: systemShare.SharedRecord[], want: Want): string {
    for (let recordIndex = 0; recordIndex < records.length; recordIndex += 1) {
      const record = records[recordIndex];
      const url = this.resolveDocumentUrl(
        String(record.uri ?? ''),
        this.resolveDocumentMimeType([String(record.utd ?? ''), String(want.type ?? '')]),
        String(record.title ?? record.label ?? '')
      );
      if (url.length > 0) {
        return url;
      }
    }
    return '';
  }

  private resolveDocumentUrl(rawUri: string, rawDescriptor: string, displayName: string): string {
    const uri = rawUri.trim();
    if (uri.length === 0 || this.extractWebUrl(uri).length > 0) {
      return '';
    }
    const mimeType = this.resolveDocumentMimeType([rawDescriptor]);
    if (!this.documentViewerService.isDocumentSourceUrl(uri, mimeType)) {
      return '';
    }
    const viewerUrl = this.documentViewerService.buildViewerUrl(uri, mimeType, displayName);
    return viewerUrl !== uri ? viewerUrl : '';
  }

  private resolveDocumentMimeType(descriptors: string[]): string {
    for (let index = 0; index < descriptors.length; index += 1) {
      const descriptor = descriptors[index].split(';')[0].trim().toLowerCase();
      if (descriptor === HTML_UTD || descriptor === HTML_MIME_TYPE) {
        return HTML_MIME_TYPE;
      }
      if (descriptor === XHTML_UTD || descriptor === XHTML_MIME_TYPE) {
        return XHTML_MIME_TYPE;
      }
    }
    return '';
  }

  private resolveUrlFromRecord(record: systemShare.SharedRecord): string {
    const contentUrl = this.extractWebUrl(String(record.content ?? ''));
    if (contentUrl.length > 0) {
      return contentUrl;
    }
    return this.extractWebUrl(String(record.uri ?? ''));
  }

  private extractWebUrl(rawValue: string): string {
    const exactUrl = this.normalizeWebUrl(rawValue);
    if (exactUrl.length > 0) {
      return exactUrl;
    }
    const match = /https?:\/\/[^\s<>"']+/i.exec(rawValue);
    if (match === null || match.length === 0) {
      return '';
    }
    return this.normalizeWebUrl(match[0]);
  }

  private normalizeWebUrl(rawValue: string): string {
    let candidate = rawValue.trim();
    const trailingPunctuation = '.,;:!?)]}，。；：！？、）》】';
    while (candidate.length > 0 && trailingPunctuation.includes(candidate.charAt(candidate.length - 1))) {
      candidate = candidate.slice(0, candidate.length - 1);
    }
    const lower = candidate.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return '';
    }
    try {
      const parsed = urlUtils.URL.parseURL(candidate);
      const protocol = parsed.protocol.trim().toLowerCase();
      if ((protocol !== 'http:' && protocol !== 'https:') || parsed.hostname.trim().length === 0) {
        return '';
      }
      return candidate;
    } catch (_error) {
      return '';
    }
  }

  private hasSharedFile(records: systemShare.SharedRecord[], want: Want): boolean {
    for (let recordIndex = 0; recordIndex < records.length; recordIndex += 1) {
      const recordUri = String(records[recordIndex].uri ?? '').trim();
      if (recordUri.length > 0 && this.extractWebUrl(recordUri).length === 0) {
        return true;
      }
    }
    const directUri = String(want.uri ?? '').trim();
    if (directUri.length > 0 && this.extractWebUrl(directUri).length === 0) {
      return true;
    }
    const descriptor = String(want.type ?? '').trim().toLowerCase();
    return descriptor === ZIP_UTD || descriptor === ZIP_MIME_TYPE;
  }
}

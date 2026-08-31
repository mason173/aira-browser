import {
  AdBlockResourceType
} from '../../common/models/BrowserModels';

export type AdBlockRequestClassificationConfidence = 'high' | 'medium' | 'low' | 'unknown';

export interface AdBlockRequestClassificationInput {
  url: string;
  pageUrl: string;
  method: string;
  isMainFrame: boolean;
  isRedirect: boolean;
  request: WebResourceRequest;
}

export interface AdBlockRequestClassification {
  resourceType: AdBlockResourceType | undefined;
  confidence: AdBlockRequestClassificationConfidence;
  evidence: string[];
}

interface AdBlockRequestClassificationCandidate {
  resourceType: AdBlockResourceType;
  confidence: AdBlockRequestClassificationConfidence;
  evidence: string;
}

const IMAGE_EXTENSIONS: string[] = [
  'apng',
  'avif',
  'bmp',
  'gif',
  'ico',
  'jpeg',
  'jpg',
  'png',
  'svg',
  'tif',
  'tiff',
  'webp'
];
const SCRIPT_EXTENSIONS: string[] = ['js', 'mjs'];
const STYLESHEET_EXTENSIONS: string[] = ['css'];
const FONT_EXTENSIONS: string[] = ['eot', 'otf', 'ttf', 'woff', 'woff2'];
const MEDIA_EXTENSIONS: string[] = [
  'aac',
  'avi',
  'dash',
  'flac',
  'm3u8',
  'm4a',
  'm4s',
  'mov',
  'mp3',
  'mp4',
  'mpd',
  'oga',
  'ogg',
  'ogv',
  'opus',
  'ts',
  'wav',
  'webm'
];
const DATA_EXTENSIONS: string[] = ['json', 'jsonp', 'xml'];
const OBJECT_EXTENSIONS: string[] = ['swf'];

export class AdBlockRequestClassifierService {
  classify(input: AdBlockRequestClassificationInput): AdBlockRequestClassification {
    if (input.isMainFrame) {
      return this.buildResult('document', 'high', ['main_frame']);
    }

    const headers = this.readHeaders(input.request);
    const fetchDest = this.readHeader(headers, 'sec-fetch-dest');
    const fetchDestCandidate = this.classifyFetchDest(fetchDest);
    if (fetchDestCandidate !== undefined) {
      return this.buildResult(
        fetchDestCandidate.resourceType,
        fetchDestCandidate.confidence,
        [fetchDestCandidate.evidence]
      );
    }

    const requestedWith = this.readHeader(headers, 'x-requested-with');
    if (requestedWith.toLowerCase() === 'xmlhttprequest') {
      return this.buildResult('xmlhttprequest', 'high', ['x_requested_with']);
    }

    const acceptCandidate = this.classifyAccept(this.readHeader(headers, 'accept'));
    if (acceptCandidate !== undefined) {
      return this.buildResult(
        acceptCandidate.resourceType,
        acceptCandidate.confidence,
        [acceptCandidate.evidence]
      );
    }

    const extensionCandidate = this.classifyExtension(input.url);
    if (extensionCandidate !== undefined) {
      return this.buildResult(
        extensionCandidate.resourceType,
        extensionCandidate.confidence,
        [extensionCandidate.evidence]
      );
    }

    const pathCandidate = this.classifyPath(input.url);
    if (pathCandidate !== undefined) {
      return this.buildResult(
        pathCandidate.resourceType,
        pathCandidate.confidence,
        [pathCandidate.evidence]
      );
    }

    return this.buildResult(undefined, 'unknown', []);
  }

  private classifyFetchDest(value: string): AdBlockRequestClassificationCandidate | undefined {
    if (value.length === 0 || value === 'empty') {
      return undefined;
    }
    if (value === 'document') {
      return this.buildCandidate('document', 'high', 'sec_fetch_dest');
    }
    if (value === 'iframe' || value === 'frame' || value === 'nested-document') {
      return this.buildCandidate('subdocument', 'high', 'sec_fetch_dest');
    }
    if (value === 'script' ||
      value === 'worker' ||
      value === 'sharedworker' ||
      value === 'serviceworker' ||
      value === 'audioworklet' ||
      value === 'paintworklet') {
      return this.buildCandidate('script', 'high', 'sec_fetch_dest');
    }
    if (value === 'style' || value === 'xslt') {
      return this.buildCandidate('stylesheet', 'high', 'sec_fetch_dest');
    }
    if (value === 'image') {
      return this.buildCandidate('image', 'high', 'sec_fetch_dest');
    }
    if (value === 'font') {
      return this.buildCandidate('font', 'high', 'sec_fetch_dest');
    }
    if (value === 'audio' || value === 'video' || value === 'track') {
      return this.buildCandidate('media', 'high', 'sec_fetch_dest');
    }
    if (value === 'object' || value === 'embed') {
      return this.buildCandidate('object', 'high', 'sec_fetch_dest');
    }
    if (value === 'manifest' || value === 'report') {
      return this.buildCandidate('other', 'medium', 'sec_fetch_dest');
    }
    return undefined;
  }

  private classifyAccept(value: string): AdBlockRequestClassificationCandidate | undefined {
    const accept = value.toLowerCase();
    if (accept.length === 0) {
      return undefined;
    }
    if (accept.indexOf('text/css') >= 0) {
      return this.buildCandidate('stylesheet', 'medium', 'accept');
    }
    if (accept.indexOf('javascript') >= 0 || accept.indexOf('ecmascript') >= 0) {
      return this.buildCandidate('script', 'medium', 'accept');
    }
    if (accept.indexOf('image/') >= 0) {
      return this.buildCandidate('image', 'medium', 'accept');
    }
    if (accept.indexOf('font/') >= 0 ||
      accept.indexOf('application/font') >= 0 ||
      accept.indexOf('application/vnd.ms-fontobject') >= 0 ||
      accept.indexOf('application/x-font') >= 0) {
      return this.buildCandidate('font', 'medium', 'accept');
    }
    if (accept.indexOf('audio/') >= 0 ||
      accept.indexOf('video/') >= 0 ||
      accept.indexOf('application/vnd.apple.mpegurl') >= 0 ||
      accept.indexOf('application/x-mpegurl') >= 0 ||
      accept.indexOf('application/dash+xml') >= 0) {
      return this.buildCandidate('media', 'medium', 'accept');
    }
    if (accept.indexOf('application/json') >= 0 ||
      accept.indexOf('text/json') >= 0 ||
      accept.indexOf('text/event-stream') >= 0) {
      return this.buildCandidate('xmlhttprequest', 'medium', 'accept');
    }
    return undefined;
  }

  private classifyExtension(url: string): AdBlockRequestClassificationCandidate | undefined {
    const extension = this.extractExtension(url);
    if (extension.length === 0) {
      return undefined;
    }
    if (SCRIPT_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('script', 'medium', 'extension');
    }
    if (STYLESHEET_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('stylesheet', 'medium', 'extension');
    }
    if (IMAGE_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('image', 'medium', 'extension');
    }
    if (FONT_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('font', 'medium', 'extension');
    }
    if (MEDIA_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('media', 'medium', 'extension');
    }
    if (DATA_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('xmlhttprequest', 'medium', 'extension');
    }
    if (OBJECT_EXTENSIONS.includes(extension)) {
      return this.buildCandidate('object', 'medium', 'extension');
    }
    return undefined;
  }

  private classifyPath(url: string): AdBlockRequestClassificationCandidate | undefined {
    const path = this.extractPath(url);
    if (path.indexOf('/api/') >= 0 ||
      path.indexOf('/ajax/') >= 0 ||
      path.indexOf('/xhr/') >= 0 ||
      path.endsWith('/graphql') ||
      path.indexOf('/graphql?') >= 0) {
      return this.buildCandidate('xmlhttprequest', 'low', 'path_token');
    }
    return undefined;
  }

  private readHeaders(request: WebResourceRequest): Record<string, string> {
    const result: Record<string, string> = {};
    try {
      const headers = request.getRequestHeader();
      if (headers === undefined || headers === null) {
        return result;
      }
      for (let index = 0; index < headers.length; index += 1) {
        const key = headers[index].headerKey?.trim().toLowerCase() ?? '';
        const value = headers[index].headerValue?.trim() ?? '';
        if (key.length > 0 && value.length > 0 && result[key] === undefined) {
          result[key] = value;
        }
      }
    } catch (_error) {
      return result;
    }
    return result;
  }

  private readHeader(headers: Record<string, string>, name: string): string {
    return headers[name] ?? '';
  }

  private extractExtension(url: string): string {
    const path = this.extractPath(url);
    const slashIndex = path.lastIndexOf('/');
    const segment = slashIndex >= 0 ? path.substring(slashIndex + 1) : path;
    const dotIndex = segment.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= segment.length - 1) {
      return '';
    }
    return segment.substring(dotIndex + 1);
  }

  private extractPath(url: string): string {
    let path = url.trim().toLowerCase();
    const hashIndex = path.indexOf('#');
    if (hashIndex >= 0) {
      path = path.substring(0, hashIndex);
    }
    const queryIndex = path.indexOf('?');
    if (queryIndex >= 0) {
      path = path.substring(0, queryIndex);
    }
    if (path.startsWith('http://')) {
      path = path.substring(7);
    } else if (path.startsWith('https://')) {
      path = path.substring(8);
    }
    const slashIndex = path.indexOf('/');
    return slashIndex >= 0 ? path.substring(slashIndex) : '/';
  }

  private buildCandidate(
    resourceType: AdBlockResourceType,
    confidence: AdBlockRequestClassificationConfidence,
    evidence: string
  ): AdBlockRequestClassificationCandidate {
    return {
      resourceType: resourceType,
      confidence: confidence,
      evidence: evidence
    };
  }

  private buildResult(
    resourceType: AdBlockResourceType | undefined,
    confidence: AdBlockRequestClassificationConfidence,
    evidence: string[]
  ): AdBlockRequestClassification {
    return {
      resourceType: resourceType,
      confidence: confidence,
      evidence: evidence
    };
  }
}

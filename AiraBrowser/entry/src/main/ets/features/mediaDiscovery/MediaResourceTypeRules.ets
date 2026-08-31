import {
  MediaCandidateFamily,
  MediaCandidateKind
} from './MediaCandidateModels';
import {
  MediaResourceDomSignal,
  MediaResourceEvidence
} from './MediaResourceClassificationModels';

const VIDEO_EXTENSIONS: string[] = [
  'mp4', 'm4v', 'mov', 'webm', 'flv', 'hlv', 'f4v', 'mkv', 'avi', 'wmv', 'asf', 'mpeg', 'mpg', 'mpeg4', 'divx', 'ogv'
];
const VIDEO_MIME_TYPES: string[] = [
  'video/mp4',
  'video/webm',
  'video/quicktime',
  'video/x-flv',
  'video/x-f4v',
  'video/x-matroska',
  'video/x-msvideo',
  'video/x-ms-wmv',
  'video/x-ms-asf',
  'video/mpeg',
  'video/ogg'
];
const AUDIO_MIME_TYPES: string[] = [
  'audio/mp4',
  'audio/aac',
  'audio/mpeg',
  'audio/wav',
  'audio/flac',
  'audio/ogg',
  'audio/webm',
  'audio/opus',
  'audio/x-ms-wma',
  'application/ogg'
];
const IMAGE_MIME_TYPES: string[] = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/avif', 'image/svg+xml'];
const DOCUMENT_MIME_TYPES: string[] = [
  'application/pdf',
  'text/plain',
  'text/csv',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation'
];
const ARCHIVE_MIME_TYPES: string[] = ['application/zip', 'application/x-rar-compressed', 'application/x-7z-compressed', 'application/gzip'];
const PACKAGE_MIME_TYPES: string[] = ['application/vnd.android.package-archive'];
const IMAGE_EXTENSIONS: string[] = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'svg'];
const AUDIO_EXTENSIONS: string[] = ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'weba', 'opus', 'wma'];
const DOCUMENT_EXTENSIONS: string[] = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'];
const ARCHIVE_EXTENSIONS: string[] = ['zip', 'rar', '7z', 'tar', 'gz'];
const PACKAGE_EXTENSIONS: string[] = ['apk', 'hap'];
const MANIFEST_NOISE_EXTENSIONS: string[] = ['webmanifest'];
const TEXT_NOISE_EXTENSIONS: string[] = ['html', 'htm', 'js', 'mjs', 'css', 'json', 'map', 'xml', 'wasm'];
const ROUTE_LIKE_EXTENSIONS: string[] = ['php', 'asp', 'aspx', 'jsp', 'cgi', 'do', 'action'];

const NOISE_KEYWORDS: string[] = [
  '/analytics',
  '/track',
  '/beacon',
  '/log/',
  '/stat/',
  'doubleclick',
  'googletagmanager',
  'adservice',
  'pixel.',
  'spacer.',
  'blank.gif',
  'favicon'
];

export interface MediaResourceClassification {
  family: MediaCandidateFamily;
  kind: MediaCandidateKind;
  extension?: string;
  evidence: MediaResourceEvidence;
  noise: boolean;
}

export class MediaResourceTypeRules {
  classifyByUrl(url: string): MediaResourceClassification {
    const noise = this.isNoiseUrl(url);
    if (this.isManifestNoiseUrl(url)) {
      return { family: 'unknown', kind: 'unknown', extension: this.extractExtension(url), evidence: 'negative', noise: true };
    }
    const extension = this.extractExtension(url);
    const queryMediaExtension = this.extractQueryMediaExtension(url);
    if (queryMediaExtension !== undefined && (extension === undefined || this.isRouteLikeExtension(extension)) &&
      !this.isLikelyEmbeddedPlayerUrl(url)) {
      const queryClassification = this.classifyMediaExtension(queryMediaExtension, noise);
      if (queryClassification !== undefined) {
        return queryClassification;
      }
    }
    if (extension === undefined) {
      return this.classifyByUrlHints(url, noise);
    }
    if (MANIFEST_NOISE_EXTENSIONS.indexOf(extension) >= 0 || TEXT_NOISE_EXTENSIONS.indexOf(extension) >= 0) {
      return { family: 'unknown', kind: 'unknown', extension: extension, evidence: 'negative', noise: true };
    }
    const mediaClassification = this.classifyMediaExtension(extension, noise);
    if (mediaClassification !== undefined) {
      return mediaClassification;
    }
    return this.classifyOtherExtension(extension, noise);
  }

  classifyByMime(mimeType: string | undefined): MediaResourceClassification | undefined {
    if (mimeType === undefined) {
      return undefined;
    }
    const normalized = mimeType.split(';')[0].trim().toLowerCase();
    if (normalized.length === 0) {
      return undefined;
    }
    switch (normalized) {
      case 'application/vnd.apple.mpegurl':
      case 'application/x-mpegurl':
      case 'application/mpegurl':
      case 'application/octet-stream-m3u8':
      case 'audio/mpegurl':
      case 'audio/x-mpegurl': return { family: 'manifest', kind: 'hls', evidence: 'mime', noise: false };
      case 'application/dash+xml': return { family: 'manifest', kind: 'dash', evidence: 'mime', noise: false };
      case 'video/mp2t':
      case 'application/m4s': return { family: 'segment', kind: 'segment', evidence: 'mime', noise: false };
      case 'application/manifest+json':
      case 'text/html':
      case 'application/json':
      case 'text/css':
      case 'application/javascript':
      case 'text/javascript': return { family: 'unknown', kind: 'unknown', evidence: 'negative', noise: true };
      default: return this.classifyKnownMime(normalized);
    }
  }

  classifyByDomSignal(
    url: string,
    signal: MediaResourceDomSignal | undefined,
    hasMediaMetadata: boolean = false
  ): MediaResourceClassification | undefined {
    if (signal === undefined) {
      return undefined;
    }
    const urlClassification = this.classifyByUrl(url);
    if (urlClassification.evidence === 'negative' && urlClassification.noise) {
      return urlClassification;
    }
    switch (signal) {
      case 'image_element':
      case 'css_background':
      case 'image_performance':
        return {
          family: 'image',
          kind: 'image',
          extension: urlClassification.extension,
          evidence: 'image_element',
          noise: urlClassification.noise
        };
      case 'video_element':
        if ((urlClassification.family === 'unknown' && !hasMediaMetadata) ||
          urlClassification.family === 'image' || urlClassification.family === 'file' || urlClassification.family === 'audio') {
          return undefined;
        }
        return {
          family: 'video',
          kind: urlClassification.kind !== 'unknown' ? urlClassification.kind : 'unknown',
          extension: urlClassification.extension,
          evidence: 'media_element',
          noise: urlClassification.noise
        };
      case 'audio_element':
        if ((urlClassification.family === 'unknown' && !hasMediaMetadata) ||
          urlClassification.family === 'image' || urlClassification.family === 'file' || urlClassification.family === 'video') {
          return undefined;
        }
        return {
          family: 'audio',
          kind: 'audio',
          extension: urlClassification.extension,
          evidence: 'media_element',
          noise: urlClassification.noise
        };
      case 'embedded_attribute':
        if (this.isLikelyEmbeddedPlayerUrl(url)) {
          return {
            family: 'video',
            kind: 'unknown',
            extension: urlClassification.extension,
            evidence: 'streaming_url_hint',
            noise: urlClassification.noise
          };
        }
        return undefined;
      default:
        return undefined;
    }
  }

  classifyEmbeddedPlayerUrl(url: string): MediaResourceClassification | undefined {
    if (!this.isLikelyEmbeddedPlayerUrl(url)) {
      return undefined;
    }
    const noise = this.isNoiseUrl(url);
    const directExtension = this.extractExtension(url);
    if (directExtension !== undefined &&
      (MANIFEST_NOISE_EXTENSIONS.indexOf(directExtension) >= 0 || TEXT_NOISE_EXTENSIONS.indexOf(directExtension) >= 0)) {
      return undefined;
    }
    if (directExtension !== undefined && !this.isRouteLikeExtension(directExtension)) {
      const directMediaClassification = this.classifyMediaExtension(directExtension, noise);
      if (directMediaClassification !== undefined) {
        return directMediaClassification;
      }
      return undefined;
    }
    if (noise) {
      return undefined;
    }
    return {
      family: 'video',
      kind: 'unknown',
      extension: directExtension,
      evidence: 'streaming_url_hint',
      noise: false
    };
  }

  isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
  }

  resolveHost(url: string): string {
    try {
      const normalizedUrl = url.trim();
      const schemeIndex = normalizedUrl.indexOf('://');
      if (schemeIndex < 0) {
        return '未知来源';
      }
      const hostStart = schemeIndex + 3;
      const pathStart = normalizedUrl.indexOf('/', hostStart);
      const authority = pathStart >= 0 ? normalizedUrl.substring(hostStart, pathStart) : normalizedUrl.substring(hostStart);
      const host = authority.split('@').pop()?.split(':')[0]?.trim() ?? '';
      return host.length > 0 ? host : '未知来源';
    } catch (_error) {
      return '未知来源';
    }
  }

  resolveDisplayName(url: string): string {
    const normalizedUrl = url.trim();
    const queryTrimmed = normalizedUrl.split('?')[0].split('#')[0];
    const segments = queryTrimmed.split('/');
    const candidate = segments.length > 0 ? segments[segments.length - 1].trim() : '';
    if (candidate.length <= 0) {
      return this.resolveHost(normalizedUrl);
    }
    try {
      return decodeURIComponent(candidate);
    } catch (_error) {
      return candidate;
    }
  }

  private classifyOtherExtension(extension: string, noise: boolean): MediaResourceClassification {
    if (IMAGE_EXTENSIONS.indexOf(extension) >= 0) {
      return { family: 'image', kind: 'image', extension: extension, evidence: 'explicit_extension', noise: noise };
    }
    if (AUDIO_EXTENSIONS.indexOf(extension) >= 0) {
      return { family: 'audio', kind: 'audio', extension: extension, evidence: 'explicit_extension', noise: noise };
    }
    if (DOCUMENT_EXTENSIONS.indexOf(extension) >= 0) {
      return { family: 'file', kind: 'document', extension: extension, evidence: 'explicit_extension', noise: noise };
    }
    if (ARCHIVE_EXTENSIONS.indexOf(extension) >= 0) {
      return { family: 'file', kind: 'archive', extension: extension, evidence: 'explicit_extension', noise: noise };
    }
    if (PACKAGE_EXTENSIONS.indexOf(extension) >= 0) {
      return { family: 'file', kind: 'package', extension: extension, evidence: 'explicit_extension', noise: noise };
    }
    return { family: 'unknown', kind: 'unknown', extension: extension, evidence: 'negative', noise: noise };
  }

  private classifyMediaExtension(extension: string, noise: boolean): MediaResourceClassification | undefined {
    switch (extension) {
      case 'm3u8':
      case 'm3u': return { family: 'manifest', kind: 'hls', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'mpd': return { family: 'manifest', kind: 'dash', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'mp4':
      case 'm4v': return { family: 'video', kind: 'mp4', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'mov': return { family: 'video', kind: 'mov', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'webm': return { family: 'video', kind: 'webm', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'flv':
      case 'hlv':
      case 'f4v': return { family: 'video', kind: 'flv', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'mkv': return { family: 'video', kind: 'mkv', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'avi':
      case 'divx': return { family: 'video', kind: 'avi', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'mpeg':
      case 'mpg':
      case 'mpeg4': return { family: 'video', kind: 'mpeg', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'wmv':
      case 'asf': return { family: 'video', kind: 'wmv', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'ogv': return { family: 'video', kind: 'ogv', extension: extension, evidence: 'explicit_extension', noise: noise };
      case 'ts':
      case 'm2t':
      case 'm2ts':
      case 'm4s': return { family: 'segment', kind: 'segment', extension: extension, evidence: 'explicit_extension', noise: noise };
      default: return undefined;
    }
  }

  private classifyByUrlHints(url: string, noise: boolean): MediaResourceClassification {
    const lower = this.extractLowerPathAndQuery(url.toLowerCase());
    if (this.hasPathToken(lower, 'm3u8') || this.hasPathToken(lower, 'hls') || this.hasPathToken(lower, 'playlist') ||
      this.hasPathToken(lower, 'master')) {
      return { family: 'manifest', kind: 'hls', evidence: 'streaming_url_hint', noise: noise };
    }
    if (this.hasPathToken(lower, 'mpd') || this.hasPathToken(lower, 'dash')) {
      return { family: 'manifest', kind: 'dash', evidence: 'streaming_url_hint', noise: noise };
    }
    if (this.hasPathToken(lower, 'video') || this.hasPathToken(lower, 'stream') || this.hasPathToken(lower, 'media')) {
      return { family: 'video', kind: 'unknown', evidence: 'generic_url_hint', noise: noise };
    }
    return { family: 'unknown', kind: 'unknown', evidence: 'negative', noise: noise };
  }

  private classifyKnownMime(normalized: string): MediaResourceClassification | undefined {
    if (VIDEO_MIME_TYPES.indexOf(normalized) >= 0) {
      if (normalized === 'video/x-flv' || normalized === 'video/x-f4v') {
        return { family: 'video', kind: 'flv', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/x-matroska') {
        return { family: 'video', kind: 'mkv', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/x-msvideo') {
        return { family: 'video', kind: 'avi', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/x-ms-wmv' || normalized === 'video/x-ms-asf') {
        return { family: 'video', kind: 'wmv', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/mpeg') {
        return { family: 'video', kind: 'mpeg', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/ogg') {
        return { family: 'video', kind: 'ogv', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/webm') {
        return { family: 'video', kind: 'webm', evidence: 'mime', noise: false };
      }
      if (normalized === 'video/quicktime') {
        return { family: 'video', kind: 'mov', evidence: 'mime', noise: false };
      }
      return { family: 'video', kind: 'mp4', evidence: 'mime', noise: false };
    }
    if (AUDIO_MIME_TYPES.indexOf(normalized) >= 0) {
      return { family: 'audio', kind: 'audio', evidence: 'mime', noise: false };
    }
    if (normalized.indexOf('video/') === 0) {
      return { family: 'video', kind: 'unknown', evidence: 'mime', noise: false };
    }
    if (normalized.indexOf('audio/') === 0) {
      return { family: 'audio', kind: 'audio', evidence: 'mime', noise: false };
    }
    if (IMAGE_MIME_TYPES.indexOf(normalized) >= 0) {
      return { family: 'image', kind: 'image', evidence: 'mime', noise: false };
    }
    if (DOCUMENT_MIME_TYPES.indexOf(normalized) >= 0) {
      return { family: 'file', kind: 'document', evidence: 'mime', noise: false };
    }
    if (ARCHIVE_MIME_TYPES.indexOf(normalized) >= 0) {
      return { family: 'file', kind: 'archive', evidence: 'mime', noise: false };
    }
    if (PACKAGE_MIME_TYPES.indexOf(normalized) >= 0) {
      return { family: 'file', kind: 'package', evidence: 'mime', noise: false };
    }
    return undefined;
  }

  private hasPathToken(lowerUrl: string, token: string): boolean {
    const pattern = new RegExp('(^|[\\\\/._?&=#:-])' + token + '($|[\\\\/._?&=#:-])');
    return pattern.test(lowerUrl);
  }

  private extractLowerPathAndQuery(lowerUrl: string): string {
    const schemeIndex = lowerUrl.indexOf('://');
    if (schemeIndex < 0) {
      return lowerUrl.split('#')[0];
    }
    const pathStart = lowerUrl.indexOf('/', schemeIndex + 3);
    if (pathStart < 0) {
      return '/';
    }
    const hashStart = lowerUrl.indexOf('#', pathStart);
    return hashStart >= 0 ? lowerUrl.substring(pathStart, hashStart) : lowerUrl.substring(pathStart);
  }

  private extractExtension(url: string): string | undefined {
    if (url.length === 0) {
      return undefined;
    }
    try {
      const queryIdx = url.indexOf('?');
      const hashIdx = url.indexOf('#');
      let cut = url.length;
      if (queryIdx >= 0 && queryIdx < cut) cut = queryIdx;
      if (hashIdx >= 0 && hashIdx < cut) cut = hashIdx;
      const path = url.substring(0, cut);
      const lastSlash = path.lastIndexOf('/');
      const lastSegment = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
      const dotIdx = lastSegment.lastIndexOf('.');
      if (dotIdx < 0 || dotIdx === lastSegment.length - 1) {
        return undefined;
      }
      const ext = lastSegment.substring(dotIdx + 1).toLowerCase();
      if (ext.length === 0 || ext.length > 16) {
        return undefined;
      }
      return ext;
    } catch (_error) {
      return undefined;
    }
  }

  private extractQueryMediaExtension(url: string): string | undefined {
    const queryStart = url.indexOf('?');
    if (queryStart < 0 || queryStart >= url.length - 1) {
      return undefined;
    }
    const hashStart = url.indexOf('#', queryStart + 1);
    const query = url.substring(queryStart + 1, hashStart >= 0 ? hashStart : url.length);
    const parts = query.split(/[&;]/);
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      const equalsIndex = part.indexOf('=');
      const rawValue = equalsIndex >= 0 ? part.substring(equalsIndex + 1) : part;
      const decodedValue = this.safeDecodeLoose(rawValue);
      const extension = this.extractExtension(decodedValue);
      if (extension !== undefined && this.classifyMediaExtension(extension, false) !== undefined) {
        return extension;
      }
    }
    return undefined;
  }

  private safeDecodeLoose(value: string): string {
    let text = value.trim();
    for (let i = 0; i < 3; i++) {
      try {
        const decoded = decodeURIComponent(text.replace(/\+/g, '%20'));
        if (decoded === text) {
          break;
        }
        text = decoded;
      } catch (_error) {
        break;
      }
    }
    return text;
  }

  private isRouteLikeExtension(extension: string): boolean {
    return ROUTE_LIKE_EXTENSIONS.indexOf(extension) >= 0;
  }

  private isLikelyEmbeddedPlayerUrl(url: string): boolean {
    if (!this.isHttpUrl(url)) {
      return false;
    }
    const lower = url.trim().toLowerCase();
    if (this.hasEmbeddedMediaParameter(lower)) {
      return true;
    }
    return this.hasPlayerHostOrPath(lower);
  }

  private hasEmbeddedMediaParameter(lowerUrl: string): boolean {
    return lowerUrl.indexOf('?url=') >= 0 ||
      lowerUrl.indexOf('&url=') >= 0 ||
      lowerUrl.indexOf('?src=') >= 0 ||
      lowerUrl.indexOf('&src=') >= 0 ||
      lowerUrl.indexOf('?file=') >= 0 ||
      lowerUrl.indexOf('&file=') >= 0 ||
      lowerUrl.indexOf('?video=') >= 0 ||
      lowerUrl.indexOf('&video=') >= 0;
  }

  private hasPlayerHostOrPath(lowerUrl: string): boolean {
    const host = this.extractLowerHost(lowerUrl);
    const path = this.extractLowerPath(lowerUrl);
    return host.startsWith('player.') ||
      host.indexOf('.player.') >= 0 ||
      host.startsWith('play.') ||
      host.indexOf('.play.') >= 0 ||
      path.indexOf('/player/') >= 0 ||
      path.indexOf('/embed/') >= 0 ||
      path.indexOf('/v2player') >= 0 ||
      path.endsWith('/player') ||
      path.endsWith('/embed');
  }

  private extractLowerHost(lowerUrl: string): string {
    const schemeIndex = lowerUrl.indexOf('://');
    if (schemeIndex < 0) {
      return '';
    }
    const hostStart = schemeIndex + 3;
    const pathStart = lowerUrl.indexOf('/', hostStart);
    const authority = pathStart >= 0 ? lowerUrl.substring(hostStart, pathStart) : lowerUrl.substring(hostStart);
    return authority.split('@').pop()?.split(':')[0]?.trim() ?? '';
  }

  private extractLowerPath(lowerUrl: string): string {
    const schemeIndex = lowerUrl.indexOf('://');
    if (schemeIndex < 0) {
      return lowerUrl;
    }
    const pathStart = lowerUrl.indexOf('/', schemeIndex + 3);
    if (pathStart < 0) {
      return '/';
    }
    const queryStart = lowerUrl.indexOf('?', pathStart);
    const hashStart = lowerUrl.indexOf('#', pathStart);
    let pathEnd = lowerUrl.length;
    if (queryStart >= 0 && queryStart < pathEnd) {
      pathEnd = queryStart;
    }
    if (hashStart >= 0 && hashStart < pathEnd) {
      pathEnd = hashStart;
    }
    return lowerUrl.substring(pathStart, pathEnd);
  }

  private isNoiseUrl(url: string): boolean {
    const lower = url.toLowerCase();
    for (let i = 0; i < NOISE_KEYWORDS.length; i++) {
      if (lower.indexOf(NOISE_KEYWORDS[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private isManifestNoiseUrl(url: string): boolean {
    const lower = url.toLowerCase().split('?')[0].split('#')[0];
    return lower.endsWith('.webmanifest') || lower.endsWith('/manifest.json') || lower.endsWith('/site.webmanifest');
  }
}

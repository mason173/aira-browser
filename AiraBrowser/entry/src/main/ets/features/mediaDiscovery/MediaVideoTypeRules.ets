import { MediaCandidateKind } from './MediaCandidateModels';

function kindForExtension(ext: string): MediaCandidateKind {
  switch (ext) {
    case 'm3u8':
    case 'm3u': return 'hls';
    case 'mpd': return 'dash';
    case 'mp4':
    case 'm4v':
    case 'mov': return 'mp4';
    case 'webm': return 'webm';
    case 'm4a':
    case 'mp3':
    case 'aac':
    case 'weba':
    case 'opus':
    case 'wma': return 'audio';
    case 'ts':
    case 'm2t':
    case 'm2ts':
    case 'm4s': return 'segment';
    default: return 'unknown';
  }
}

function kindForMime(mime: string): MediaCandidateKind {
  switch (mime) {
    case 'application/vnd.apple.mpegurl':
    case 'application/x-mpegurl':
    case 'application/mpegurl':
    case 'application/octet-stream-m3u8':
    case 'audio/mpegurl':
    case 'audio/x-mpegurl': return 'hls';
    case 'application/dash+xml': return 'dash';
    case 'video/mp4': return 'mp4';
    case 'video/webm': return 'webm';
    case 'video/mp2t':
    case 'application/m4s': return 'segment';
    case 'audio/mp4':
    case 'audio/aac':
    case 'audio/mpeg':
    case 'audio/ogg':
    case 'audio/webm':
    case 'audio/opus':
    case 'audio/x-ms-wma':
    case 'application/ogg': return 'audio';
    default: return 'unknown';
  }
}

const NOISE_KEYWORDS: string[] = [
  '/analytics',
  '/track',
  '/beacon',
  '/log/',
  '/stat/',
  'doubleclick',
  'googletagmanager',
  'adservice',
  'preload-image'
];

export interface VideoClassification {
  kind: MediaCandidateKind;
  extension?: string;
  noise: boolean;
  urlHint?: 'explicit_video_mime' | 'opaque_media_path';
}

export class MediaVideoTypeRules {
  classifyByUrl(url: string): VideoClassification {
    const noise = this.isNoiseUrl(url);
    const extension = this.extractExtension(url);
    if (extension !== undefined) {
      const kind = kindForExtension(extension);
      if (kind !== 'unknown') {
        return { kind: kind, extension: extension, noise: noise };
      }
    }
    const urlHint = this.resolveVideoUrlHint(url);
    if (urlHint !== undefined) {
      return { kind: 'mp4', extension: extension, noise: noise, urlHint: urlHint };
    }
    return { kind: 'unknown', extension: extension, noise: noise };
  }

  classifyByDomMediaMetadata(
    url: string,
    fromBlob: boolean,
    durationMs: number | undefined,
    width: number | undefined,
    height: number | undefined
  ): VideoClassification {
    const classification = this.classifyByUrl(url);
    if (classification.kind !== 'unknown' || fromBlob) {
      return classification;
    }
    if (!this.isHttpUrl(url)) {
      return classification;
    }
    if (!this.hasPlaybackMetadata(durationMs, width, height)) {
      return classification;
    }
    return { kind: 'mp4', extension: classification.extension, noise: classification.noise };
  }

  classifyByMime(mimeType: string | undefined): MediaCandidateKind {
    if (mimeType === undefined) {
      return 'unknown';
    }
    const normalized = mimeType.split(';')[0].trim().toLowerCase();
    return kindForMime(normalized);
  }

  isMediaVideoUrl(url: string): boolean {
    const classification = this.classifyByUrl(url);
    return classification.kind !== 'unknown';
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0;
  }

  private hasPlaybackMetadata(
    durationMs: number | undefined,
    width: number | undefined,
    height: number | undefined
  ): boolean {
    if (durationMs !== undefined && durationMs > 0) {
      return true;
    }
    return width !== undefined && width > 0 && height !== undefined && height > 0;
  }

  private resolveVideoUrlHint(url: string): 'explicit_video_mime' | 'opaque_media_path' | undefined {
    try {
      const decodedLowerUrl = this.decodeLoose(url).toLowerCase();
      if (/(?:^|[?&;])(?:mime|content[_-]?type|type)=video\/[a-z0-9.+-]+/.test(decodedLowerUrl)) {
        return 'explicit_video_mime';
      }
      const schemeIndex = url.indexOf('://');
      if (schemeIndex < 0) {
        return undefined;
      }
      const pathStart = url.indexOf('/', schemeIndex + 3);
      if (pathStart < 0) {
        return undefined;
      }
      const queryStart = url.indexOf('?', pathStart);
      const hashStart = url.indexOf('#', pathStart);
      let pathEnd = url.length;
      if (queryStart >= 0 && queryStart < pathEnd) {
        pathEnd = queryStart;
      }
      if (hashStart >= 0 && hashStart < pathEnd) {
        pathEnd = hashStart;
      }
      const path = url.substring(pathStart, pathEnd);
      const segments = path.split('/');
      const lastSegment = segments.length > 0 ? segments[segments.length - 1] : '';
      if (lastSegment.indexOf('.') >= 0) {
        return undefined;
      }
      if (this.hasMediaPathHint(path) && this.isLongOpaqueMediaToken(lastSegment)) {
        return 'opaque_media_path';
      }
      return undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private decodeLoose(value: string): string {
    let decoded = value;
    for (let i = 0; i < 2; i++) {
      try {
        const next = decodeURIComponent(decoded);
        if (next === decoded) {
          return decoded;
        }
        decoded = next;
      } catch (_error) {
        return decoded;
      }
    }
    return decoded;
  }

  private hasMediaPathHint(path: string): boolean {
    const lowerPath = path.toLowerCase();
    return lowerPath.indexOf('/obj/') >= 0 ||
      lowerPath.indexOf('/media/') >= 0 ||
      lowerPath.indexOf('/stream/') >= 0 ||
      lowerPath.indexOf('/video/') >= 0;
  }

  private isLongOpaqueMediaToken(segment: string): boolean {
    return /^[A-Fa-f0-9]{24,}$/.test(segment) ||
      /^[A-Za-z0-9_-]{32,}$/.test(segment);
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
      if (ext.length === 0 || ext.length > 8) {
        return undefined;
      }
      return ext;
    } catch (_error) {
      return undefined;
    }
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
}

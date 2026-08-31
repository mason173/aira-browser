import urlUtils from '@ohos.url';

export interface DownloadFileNameResolutionInput {
  suggestedFileName?: string;
  url?: string;
  mimeType?: string;
  contentDisposition?: string;
}

export class DownloadFileNameService {
  resolveFileName(input: DownloadFileNameResolutionInput): string {
    const dispositionFileName = this.resolveFileNameFromContentDisposition(input.contentDisposition ?? '');
    const rawName = dispositionFileName.length > 0
      ? dispositionFileName
      : this.resolveRawFileName(input.suggestedFileName ?? '', input.url ?? '');
    return this.ensureExtension(rawName, input.mimeType, input.url);
  }

  sanitizeFileName(fileName: string): string {
    const sanitized = fileName
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, ' ')
      .trim();
    return sanitized.length > 0 ? sanitized : 'download.bin';
  }

  resolveFileNameFromContentDisposition(value: string): string {
    const encodedMatch = /filename\*\s*=\s*(?:UTF-8''|utf-8'')?([^;]+)/i.exec(value);
    if (encodedMatch !== null) {
      const decoded = this.safeDecodeURIComponent(this.stripQuotes(encodedMatch[1]).replace(/\+/g, '%20'));
      if (decoded.length > 0) {
        return decoded;
      }
    }
    const plainMatch = /filename\s*=\s*([^;]+)/i.exec(value);
    if (plainMatch !== null) {
      const plain = this.safeDecodeURIComponent(this.stripQuotes(plainMatch[1]));
      if (plain.length > 0) {
        return plain;
      }
    }
    return '';
  }

  resolveFileNameFromUrl(url: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(url);
      const explicitName = this.resolveNameFromQuery(parsed.search);
      if (explicitName.length > 0) {
        return explicitName;
      }
      return this.resolveNameFromPath(parsed.pathname);
    } catch (_error) {
      const queryIndex = url.indexOf('?');
      if (queryIndex >= 0) {
        const explicitName = this.resolveNameFromQuery(url.substring(queryIndex));
        if (explicitName.length > 0) {
          return explicitName;
        }
      }
      const queryTrimmed = url.split('?')[0];
      return this.resolveNameFromPath(queryTrimmed);
    }
  }

  ensureExtension(fileName: string, mimeType?: string, url?: string): string {
    const normalizedName = this.sanitizeFileName(fileName);
    if (this.hasLikelyExtension(normalizedName)) {
      return normalizedName;
    }
    const extension = this.resolveExtension(mimeType, url, normalizedName);
    return extension.length > 0 ? `${normalizedName}${extension}` : normalizedName;
  }

  private resolveRawFileName(suggestedFileName: string, url: string): string {
    const trimmed = suggestedFileName.trim();
    if (trimmed.length > 0 && !this.isGenericFileName(trimmed)) {
      return trimmed;
    }
    const urlName = this.resolveFileNameFromUrl(url);
    return urlName.length > 0 ? urlName : 'download.bin';
  }

  private resolveNameFromPath(path: string): string {
    const segments = path.split('/');
    const candidate = segments[segments.length - 1]?.trim() ?? '';
    return this.safeDecodeURIComponent(candidate);
  }

  private resolveNameFromQuery(query: string): string {
    const normalized = query.startsWith('?') ? query.substring(1) : query;
    if (normalized.length <= 0) {
      return '';
    }
    const parts = normalized.split('&');
    const nameKeys = ['filename', 'file_name', 'name', 'download', 'fn'];
    for (let keyIndex = 0; keyIndex < nameKeys.length; keyIndex += 1) {
      const targetKey = nameKeys[keyIndex];
      for (let partIndex = 0; partIndex < parts.length; partIndex += 1) {
        const pair = parts[partIndex];
        const separator = pair.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        const key = this.safeDecodeURIComponent(pair.substring(0, separator)).toLowerCase();
        if (key !== targetKey) {
          continue;
        }
        const value = this.safeDecodeURIComponent(pair.substring(separator + 1).replace(/\+/g, '%20'));
        if (value.length > 0) {
          return value;
        }
      }
    }
    return '';
  }

  private hasLikelyExtension(fileName: string): boolean {
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= fileName.length - 1) {
      return false;
    }
    const extension = fileName.substring(dotIndex + 1).trim();
    return /^[A-Za-z0-9]{1,8}$/.test(extension);
  }

  private isGenericFileName(fileName: string): boolean {
    const normalized = fileName.trim().toLowerCase();
    return normalized === 'download' ||
      normalized === 'download.bin' ||
      normalized === 'file' ||
      normalized === 'file.bin' ||
      normalized === 'index' ||
      normalized === 'index.html' ||
      normalized === '未命名下载';
  }

  private resolveExtension(mimeType?: string, url?: string, fileName?: string): string {
    const normalizedMimeType = (mimeType ?? '').split(';')[0].trim().toLowerCase();
    switch (normalizedMimeType) {
      case 'application/zip':
      case 'application/x-zip':
      case 'application/x-zip-compressed':
      case 'multipart/x-zip':
        return '.zip';
      case 'application/vnd.rar':
      case 'application/x-rar':
      case 'application/x-rar-compressed':
        return '.rar';
      case 'application/x-7z-compressed':
        return '.7z';
      case 'application/gzip':
      case 'application/x-gzip':
        return '.gz';
      case 'application/pdf':
        return '.pdf';
      case 'application/vnd.android.package-archive':
        return '.apk';
      case 'application/json':
        return '.json';
      case 'text/plain':
        return '.txt';
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      case 'video/mp4':
        return '.mp4';
      case 'audio/mpeg':
        return '.mp3';
      default:
        break;
    }
    return this.resolveExtensionFromHints(url ?? '', fileName ?? '');
  }

  private resolveExtensionFromHints(url: string, fileName: string): string {
    const hints = `${url} ${fileName}`.toLowerCase();
    if (hints.includes('.zip') || hints.includes('zip')) {
      return '.zip';
    }
    if (hints.includes('.rar') || hints.includes('rar')) {
      return '.rar';
    }
    if (hints.includes('.7z') || hints.includes('7z')) {
      return '.7z';
    }
    if (hints.includes('.apk') || hints.includes('apk')) {
      return '.apk';
    }
    return '';
  }

  private stripQuotes(value: string): string {
    const trimmed = value.trim();
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  private safeDecodeURIComponent(value: string): string {
    try {
      return decodeURIComponent(value).trim();
    } catch (_error) {
      return value.trim();
    }
  }
}

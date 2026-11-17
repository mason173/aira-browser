import urlUtils from '@ohos.url';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

const MAX_FILE_NAME_UTF8_BYTES: number = 255;
const MAX_EXTENSION_UTF8_BYTES: number = 32;

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
    return this.buildFileNameWithSuffix(fileName, '');
  }

  // Reserve the generated conflict suffix before truncating the basename so a
  // full-length name can still become "name (1).ext" in the final directory.
  buildConflictFileName(fileName: string, conflictIndex: number): string {
    return this.buildFileNameWithSuffix(fileName, ` (${conflictIndex})`);
  }

  private buildFileNameWithSuffix(fileName: string, suffix: string): string {
    const sanitized = this.normalizeUnicode(fileName)
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, ' ')
      .replace(/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, '_')
      .trim()
      .replace(/[. ]+$/g, '');
    const normalizedName = sanitized.length > 0 ? sanitized : 'download.bin';
    const extensionStart = this.resolveExtensionStart(normalizedName);
    const extension = extensionStart > 0 ? normalizedName.substring(extensionStart) : '';
    const baseName = extensionStart > 0 ? normalizedName.substring(0, extensionStart) : normalizedName;
    const baseBudget = MAX_FILE_NAME_UTF8_BYTES - this.utf8ByteLength(extension) - this.utf8ByteLength(suffix);
    const limitedBaseName = this.truncateUtf8(baseName, baseBudget);
    const result = `${limitedBaseName}${suffix}${extension}`.replace(/[. ]+$/g, '');
    return result.length > 0 ? result : `download${suffix}${extension}`;
  }

  private resolveExtensionStart(fileName: string): number {
    const lowerName = fileName.toLowerCase();
    const compoundExtensions: string[] = ['.tar.gz', '.tar.bz2', '.tar.xz'];
    for (let index = 0; index < compoundExtensions.length; index += 1) {
      const extension = compoundExtensions[index];
      if (lowerName.endsWith(extension) && fileName.length > extension.length) {
        return fileName.length - extension.length;
      }
    }
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= fileName.length - 1) {
      return -1;
    }
    // An arbitrarily long dotted title segment must not consume the basename's
    // entire byte budget as though it were a file extension.
    return this.utf8ByteLength(fileName.substring(dotIndex)) <= MAX_EXTENSION_UTF8_BYTES ? dotIndex : -1;
  }

  private normalizeUnicode(value: string): string {
    let normalized = '';
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = value.charCodeAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          normalized += value.substring(index, index + 2);
          index += 1;
        } else {
          normalized += '_';
        }
      } else {
        normalized += code >= 0xdc00 && code <= 0xdfff ? '_' : value.charAt(index);
      }
    }
    return normalized;
  }

  private utf8ByteLength(value: string): number {
    let bytes = 0;
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      bytes += code <= 0x7f ? 1 : (code <= 0x7ff ? 2 : (code >= 0xd800 && code <= 0xdbff ? 4 : 3));
      if (code >= 0xd800 && code <= 0xdbff) index += 1;
    }
    return bytes;
  }

  private truncateUtf8(value: string, byteBudget: number): string {
    let bytes = 0;
    let end = 0;
    while (end < value.length) {
      const code = value.charCodeAt(end);
      const isPair = code >= 0xd800 && code <= 0xdbff;
      const width = code <= 0x7f ? 1 : (code <= 0x7ff ? 2 : (isPair ? 4 : 3));
      if (bytes + width > byteBudget) break;
      bytes += width;
      end += isPair ? 2 : 1;
    }
    return value.substring(0, end);
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
    return extension.length > 0 ? this.sanitizeFileName(`${normalizedName}${extension}`) : normalizedName;
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
      normalized === '未命名下载' ||
      normalized === resolveAppResourceText($r('app.string.download_status_unnamed')).trim().toLowerCase();
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

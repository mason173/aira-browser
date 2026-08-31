import { util } from '@kit.ArkTS';

export interface OfflinePagePreviewImageResult {
  fileName: string;
  bytes: ArrayBuffer;
  mimeType: string;
}

const MAX_PREVIEW_DATA_URL_CHARS: number = 1400 * 1024;

export class OfflinePagePreviewImageService {
  private base64Helper: util.Base64Helper = new util.Base64Helper();

  extractPreviewImage(html: string): OfflinePagePreviewImageResult | undefined {
    const dataUrl = this.findFirstImageDataUrl(html);
    if (dataUrl === undefined) {
      return undefined;
    }
    return this.decodeDataUrl(dataUrl);
  }

  private findFirstImageDataUrl(html: string): string | undefined {
    const regex = /<img\b[^>]*\ssrc\s*=\s*["'](data:image\/[^"']+)["'][^>]*>/gi;
    let match: RegExpExecArray | null = regex.exec(html);
    while (match !== null) {
      const dataUrl = match[1].trim();
      if (dataUrl.length > 0 && dataUrl.length <= MAX_PREVIEW_DATA_URL_CHARS) {
        return dataUrl;
      }
      match = regex.exec(html);
    }
    return undefined;
  }

  private decodeDataUrl(dataUrl: string): OfflinePagePreviewImageResult | undefined {
    const commaIndex = dataUrl.indexOf(',');
    if (commaIndex <= 0) {
      return undefined;
    }
    const header = dataUrl.substring(0, commaIndex).toLowerCase();
    if (!header.includes(';base64')) {
      return undefined;
    }
    const mimeType = this.resolveMimeType(header);
    if (mimeType.length === 0) {
      return undefined;
    }
    try {
      const payload = dataUrl.substring(commaIndex + 1);
      const decoded = this.base64Helper.decodeSync(payload);
      return {
        fileName: `preview${this.resolveExtension(mimeType)}`,
        bytes: decoded.buffer.slice(decoded.byteOffset, decoded.byteOffset + decoded.byteLength),
        mimeType: mimeType
      };
    } catch (_error) {
      return undefined;
    }
  }

  private resolveMimeType(header: string): string {
    const match = /^data:(image\/[a-z0-9.+-]+)(?:;|$)/i.exec(header);
    if (match === null) {
      return '';
    }
    const mimeType = match[1].toLowerCase();
    if (mimeType === 'image/jpeg' || mimeType === 'image/png' || mimeType === 'image/webp' ||
      mimeType === 'image/gif') {
      return mimeType;
    }
    return '';
  }

  private resolveExtension(mimeType: string): string {
    if (mimeType === 'image/png') {
      return '.png';
    }
    if (mimeType === 'image/webp') {
      return '.webp';
    }
    if (mimeType === 'image/gif') {
      return '.gif';
    }
    return '.jpg';
  }
}

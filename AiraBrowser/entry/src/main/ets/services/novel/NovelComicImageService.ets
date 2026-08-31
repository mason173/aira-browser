import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { AIRA_COMPAT_MOBILE_USER_AGENT } from '../web/BrowserUserAgentService';

const NOVEL_COMIC_IMAGE_REQUEST_TIMEOUT_MS: number = 15000;
const NOVEL_COMIC_IMAGE_MAX_BYTES: number = 30 * 1024 * 1024;

/**
 * Loads one comic page through native HTTP so sites can receive the source
 * chapter as Referer before the bytes are decoded for ArkUI.
 */
export class NovelComicImageService {
  async load(imageUrl: string, pageUrl: string): Promise<image.PixelMap | undefined> {
    const payload: ArrayBuffer = await this.fetchImageBytes(imageUrl.trim(), pageUrl.trim());
    let source: image.ImageSource | undefined = undefined;
    try {
      source = image.createImageSource(payload);
      return await source.createPixelMap({
        index: 0,
        editable: false
      });
    } finally {
      if (source !== undefined) {
        await source.release().catch((_error: Error): void => {});
      }
    }
  }

  private async fetchImageBytes(imageUrl: string, pageUrl: string): Promise<ArrayBuffer> {
    if (!this.isRemoteUrl(imageUrl)) {
      throw new Error('comic-image-url');
    }
    const request = http.createHttp();
    try {
      const response = await request.request(imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: NOVEL_COMIC_IMAGE_REQUEST_TIMEOUT_MS,
        readTimeout: NOVEL_COMIC_IMAGE_REQUEST_TIMEOUT_MS,
        usingCache: true,
        maxLimit: NOVEL_COMIC_IMAGE_MAX_BYTES,
        header: this.buildRequestHeaders(imageUrl, pageUrl)
      });
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer)) {
        throw new Error(`comic-image-http-${response.responseCode}`);
      }
      const payload: ArrayBuffer = response.result;
      if (payload.byteLength <= 0 || payload.byteLength > NOVEL_COMIC_IMAGE_MAX_BYTES ||
        !this.isLikelyImagePayload(payload)) {
        throw new Error('comic-image-payload');
      }
      return payload;
    } finally {
      request.destroy();
    }
  }

  private buildRequestHeaders(imageUrl: string, pageUrl: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/gif,image/*;q=0.8,*/*;q=0.4',
      'User-Agent': AIRA_COMPAT_MOBILE_USER_AGENT
    };
    if (pageUrl.length > 0 && pageUrl !== imageUrl) {
      headers['Referer'] = pageUrl;
    }
    try {
      const cookie: string = webview.WebCookieManager.fetchCookieSync(imageUrl, false).trim();
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
    } catch (_error) {
    }
    return headers;
  }

  private isRemoteUrl(value: string): boolean {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  private isLikelyImagePayload(data: ArrayBuffer): boolean {
    const bytes = new Uint8Array(data);
    if (bytes.length < 4) {
      return false;
    }
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return true;
    }
    if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return true;
    }
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return true;
    }
    return bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
      bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50;
  }
}

export const sharedNovelComicImageService: NovelComicImageService = new NovelComicImageService();

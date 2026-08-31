import { uniformTypeDescriptor } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';
import { webview } from '@kit.ArkWeb';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const WEB_IMAGE_CONTEXT_CACHE_DIR_NAME: string = 'web-image-context-actions';
const WEB_IMAGE_CONTEXT_REQUEST_TIMEOUT_MS: number = 10000;
const WEB_IMAGE_CONTEXT_MAX_BYTES: number = 30 * 1024 * 1024;
const WEB_IMAGE_CONTEXT_COPY_CHUNK_BYTES: number = 512 * 1024;
const WEB_IMAGE_CONTEXT_LOG_DOMAIN: number = 0xA17A;
const WEB_IMAGE_CONTEXT_LOG_TAG: string = 'AiraWebImageContext';
const WEB_IMAGE_CONTEXT_DEFAULT_TITLE: string = '网页图片';

export interface WebImageContextActionInput {
  imageUrl: string;
  pageUrl?: string;
  title?: string;
}

export interface WebImageContextActionResult {
  ok: boolean;
  message: string;
}

interface WebImageContextCachedFile {
  path: string;
  uri: string;
  extension: string;
  title: string;
  data: ArrayBuffer;
}

export class WebImageContextActionService {
  async saveToGallery(input: WebImageContextActionInput): Promise<WebImageContextActionResult> {
    try {
      const file = await this.prepareImageFile(input);
      const helper = photoAccessHelper.getPhotoAccessHelper(AppRuntimeContext.getUIAbilityContext());
      const savedUris = await helper.showAssetsCreationDialog([file.uri], [{
        title: file.title,
        fileNameExtension: file.extension,
        photoType: photoAccessHelper.PhotoType.IMAGE
      }]);
      if (savedUris.length <= 0) {
        return {
          ok: false,
          message: '未保存图片。'
        };
      }
      const destinationUri = savedUris[0].trim();
      if (destinationUri.length === 0 || destinationUri.indexOf('-') === 0) {
        throw new Error(`invalid-gallery-uri:${destinationUri}`);
      }
      await this.writeDataToUri(destinationUri, file.data);
      hilog.info(WEB_IMAGE_CONTEXT_LOG_DOMAIN, WEB_IMAGE_CONTEXT_LOG_TAG,
        'save_to_gallery wrote uri=%{public}s bytes=%{public}d ext=%{public}s',
        destinationUri, file.data.byteLength, file.extension);
      return {
        ok: true,
        message: '已保存至图库。'
      };
    } catch (error) {
      this.logActionFailure('save_to_gallery', error);
      return {
        ok: false,
        message: '保存图片失败，请稍后重试。'
      };
    }
  }

  async copyImage(input: WebImageContextActionInput): Promise<WebImageContextActionResult> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const bytes = await this.fetchImageBytes(input.imageUrl, input.pageUrl ?? '');
      imageSource = image.createImageSource(bytes);
      pixelMap = await imageSource.createPixelMap({
        editable: false
      });
      const data = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
      await pasteboard.getSystemPasteboard().setData(data);
      return {
        ok: true,
        message: '图片已复制。'
      };
    } catch (error) {
      this.logActionFailure('copy_image', error);
      return {
        ok: false,
        message: '复制图片失败，请稍后重试。'
      };
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release().catch((_error: Error) => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {});
      }
    }
  }

  async shareImage(input: WebImageContextActionInput): Promise<WebImageContextActionResult> {
    try {
      const file = await this.prepareImageFile(input);
      const data = new systemShare.SharedData({
        utd: this.resolveShareUtd(file.extension),
        uri: file.uri,
        title: file.title,
        label: file.title,
        description: file.title
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(AppRuntimeContext.getUIAbilityContext(), {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
      return {
        ok: true,
        message: '已打开分享面板。'
      };
    } catch (error) {
      this.logActionFailure('share_image', error);
      return {
        ok: false,
        message: '分享图片失败，请稍后重试。'
      };
    }
  }

  private async prepareImageFile(input: WebImageContextActionInput): Promise<WebImageContextCachedFile> {
    const imageUrl = input.imageUrl.trim();
    if (imageUrl.length === 0) {
      throw new Error('empty-image-url');
    }
    const bytes = await this.fetchImageBytes(imageUrl, input.pageUrl ?? '');
    const extension = this.resolveImageExtension(imageUrl, bytes);
    const title = this.resolveImageTitle(input.title ?? '', imageUrl, extension);
    const path = `${this.getCacheDir()}/${this.hashString(imageUrl)}-${Date.now()}.${extension}`;
    await this.writeFile(path, bytes);
    return {
      path: path,
      uri: fileUri.getUriFromPath(path),
      extension: extension,
      title: title,
      data: bytes
    };
  }

  private async fetchImageBytes(imageUrl: string, pageUrl: string): Promise<ArrayBuffer> {
    if (imageUrl.trim().toLowerCase().indexOf('data:image/') === 0) {
      return this.decodeDataImageUrl(imageUrl);
    }
    const request = http.createHttp();
    try {
      const response = await request.request(imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: WEB_IMAGE_CONTEXT_REQUEST_TIMEOUT_MS,
        readTimeout: WEB_IMAGE_CONTEXT_REQUEST_TIMEOUT_MS,
        usingCache: true,
        header: this.buildRequestHeaders(imageUrl, pageUrl)
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
        throw new Error('image-http-failed');
      }
      this.assertImagePayload(response.result);
      return response.result;
    } finally {
      request.destroy();
    }
  }

  private buildRequestHeaders(imageUrl: string, pageUrl: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/gif,image/*;q=0.8,*/*;q=0.4',
      'User-Agent': 'AiraBrowser/1.0'
    };
    const referer = pageUrl.trim();
    if (referer.length > 0 && referer !== imageUrl.trim()) {
      headers['Referer'] = referer;
    }
    const cookie = this.resolveCookieHeader(imageUrl);
    if (cookie.length > 0) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  private resolveCookieHeader(url: string): string {
    try {
      return webview.WebCookieManager.fetchCookieSync(url, false).trim();
    } catch (_error) {
      return '';
    }
  }

  private async writeFile(path: string, data: ArrayBuffer): Promise<void> {
    this.assertImagePayload(data);
    await this.ensureCacheDir();
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, data);
    } finally {
      await fileIo.close(file);
    }
  }

  private async writeDataToUri(uri: string, data: ArrayBuffer): Promise<void> {
    this.assertImagePayload(data);
    const file = await this.openWritableUri(uri);
    try {
      let offset = 0;
      while (offset < data.byteLength) {
        const nextOffset = Math.min(data.byteLength, offset + WEB_IMAGE_CONTEXT_COPY_CHUNK_BYTES);
        const chunk = data.slice(offset, nextOffset);
        const written = await fileIo.write(file.fd, chunk, {
          offset: offset,
          length: chunk.byteLength
        });
        if (written <= 0) {
          throw new Error('gallery-write-stalled');
        }
        offset += written;
      }
    } finally {
      await fileIo.close(file);
    }
  }

  private async openWritableUri(uri: string): Promise<fileIo.File> {
    try {
      return await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    } catch (_error) {
      return await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY);
    }
  }

  private assertImagePayload(data: ArrayBuffer): void {
    if (data.byteLength <= 0 || data.byteLength > WEB_IMAGE_CONTEXT_MAX_BYTES || !this.isLikelyImagePayload(data)) {
      throw new Error('invalid-image-payload');
    }
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
    if (this.isAvifPayload(bytes)) {
      return true;
    }
    if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return true;
    }
    const prefix = this.arrayBufferPrefixToAscii(bytes, 64).trim().toLowerCase();
    return prefix.indexOf('<svg') === 0 || prefix.indexOf('<?xml') === 0;
  }

  private decodeDataImageUrl(url: string): ArrayBuffer {
    const commaIndex = url.indexOf(',');
    if (commaIndex <= 0) {
      throw new Error('invalid-data-image');
    }
    const metadata = url.substring(0, commaIndex).toLowerCase();
    if (metadata.indexOf('base64') < 0) {
      throw new Error('unsupported-data-image');
    }
    const bytes = this.decodeBase64(url.substring(commaIndex + 1));
    this.assertImagePayload(bytes);
    return bytes;
  }

  private decodeBase64(value: string): ArrayBuffer {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const clean = value.replace(/\s/g, '');
    const output: number[] = [];
    let buffer = 0;
    let bits = 0;
    for (let index = 0; index < clean.length; index += 1) {
      const char = clean.charAt(index);
      if (char === '=') {
        break;
      }
      const code = alphabet.indexOf(char);
      if (code < 0) {
        continue;
      }
      buffer = (buffer << 6) | code;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        output.push((buffer >> bits) & 0xFF);
      }
    }
    return new Uint8Array(output).buffer as ArrayBuffer;
  }

  private resolveImageExtension(url: string, data: ArrayBuffer): string {
    const extensionFromPayload = this.resolveImageExtensionFromPayload(data);
    if (extensionFromPayload.length > 0) {
      return extensionFromPayload;
    }
    const normalized = url.toLowerCase();
    if (normalized.indexOf('image/jpeg') >= 0 || normalized.indexOf('.jpg') >= 0 || normalized.indexOf('.jpeg') >= 0) {
      return 'jpg';
    }
    if (normalized.indexOf('image/webp') >= 0 || normalized.indexOf('.webp') >= 0) {
      return 'webp';
    }
    if (normalized.indexOf('image/gif') >= 0 || normalized.indexOf('.gif') >= 0) {
      return 'gif';
    }
    if (normalized.indexOf('image/svg') >= 0 || normalized.indexOf('.svg') >= 0) {
      return 'svg';
    }
    if (normalized.indexOf('image/avif') >= 0 || normalized.indexOf('.avif') >= 0) {
      return 'avif';
    }
    return 'png';
  }

  private resolveImageExtensionFromPayload(data: ArrayBuffer): string {
    const bytes = new Uint8Array(data);
    if (bytes.length < 4) {
      return '';
    }
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return 'png';
    }
    if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return 'jpg';
    }
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return 'webp';
    }
    if (this.isAvifPayload(bytes)) {
      return 'avif';
    }
    const prefix = this.arrayBufferPrefixToAscii(bytes, 64).trim().toLowerCase();
    if (prefix.indexOf('<svg') === 0 || prefix.indexOf('<?xml') === 0) {
      return 'svg';
    }
    return '';
  }

  private isAvifPayload(bytes: Uint8Array): boolean {
    return bytes.length >= 12 &&
      bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70 &&
      bytes[8] === 0x61 && bytes[9] === 0x76 && bytes[10] === 0x69 && bytes[11] === 0x66;
  }

  private resolveShareUtd(extension: string): string {
    if (extension === 'jpg' || extension === 'jpeg') {
      return uniformTypeDescriptor.UniformDataType.JPEG;
    }
    if (extension === 'png') {
      return uniformTypeDescriptor.UniformDataType.PNG;
    }
    if (extension === 'gif') {
      return uniformTypeDescriptor.UniformDataType.GIF;
    }
    return uniformTypeDescriptor.UniformDataType.IMAGE;
  }

  private resolveImageTitle(title: string, imageUrl: string, extension: string): string {
    const fileName = this.resolveFileNameFromUrl(imageUrl);
    const fileTitle = this.stripKnownExtension(fileName);
    if (fileTitle.length > 0) {
      return this.sanitizeAssetTitle(fileTitle);
    }
    const normalizedTitle = this.sanitizeAssetTitle(title);
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }
    return `${WEB_IMAGE_CONTEXT_DEFAULT_TITLE}-${Date.now().toString()}`;
  }

  private resolveFileNameFromUrl(imageUrl: string): string {
    try {
      const withoutQuery = imageUrl.split('?')[0].split('#')[0];
      const slashIndex = withoutQuery.lastIndexOf('/');
      const fileName = slashIndex >= 0 ? withoutQuery.substring(slashIndex + 1) : withoutQuery;
      return decodeURIComponent(fileName).trim();
    } catch (_error) {
      return '';
    }
  }

  private stripKnownExtension(fileName: string): string {
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName.trim();
    }
    const extension = fileName.substring(dotIndex + 1).toLowerCase();
    if (extension === 'jpg' || extension === 'jpeg' || extension === 'png' || extension === 'webp' ||
      extension === 'gif' || extension === 'svg' || extension === 'avif') {
      return fileName.substring(0, dotIndex).trim();
    }
    return fileName.trim();
  }

  private sanitizeAssetTitle(value: string): string {
    const normalized = value.trim()
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, ' ')
      .replace(/^\.+/, '')
      .trim();
    if (normalized.length <= 80) {
      return normalized;
    }
    return normalized.substring(0, 80).trim();
  }

  private async ensureCacheDir(): Promise<void> {
    const dir = this.getCacheDir();
    try {
      if (await fileIo.access(dir)) {
        return;
      }
    } catch (_error) {
    }
    await fileIo.mkdir(dir, true);
  }

  private getCacheDir(): string {
    return `${AppRuntimeContext.getApplicationContext().cacheDir}/${WEB_IMAGE_CONTEXT_CACHE_DIR_NAME}`;
  }

  private hashString(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private arrayBufferPrefixToAscii(bytes: Uint8Array, maxLength: number): string {
    let text = '';
    const length = Math.min(bytes.length, maxLength);
    for (let index = 0; index < length; index += 1) {
      text += String.fromCharCode(bytes[index]);
    }
    return text;
  }

  private logActionFailure(action: string, error: Object): void {
    hilog.warn(WEB_IMAGE_CONTEXT_LOG_DOMAIN, WEB_IMAGE_CONTEXT_LOG_TAG,
      '%{public}s failed: %{public}s', action, JSON.stringify(error));
  }
}

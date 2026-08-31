import { fileIo, fileUri } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  BrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';
import {
  HomeWallpaperForegroundAnalysis,
  WallpaperAsset
} from '../../common/models/WallpaperModels';

const WALLPAPER_ROOT_DIR: string = 'wallpapers';
const WALLPAPER_ORIGINAL_DIR: string = 'original';
const WALLPAPER_DOWNLOAD_DIR: string = 'downloads';
const MAX_IMPORTED_IMAGE_BYTES: number = 30 * 1024 * 1024;

export class WallpaperAssetStore {
  async saveDownloadedImage(
    source: 'bing',
    assetId: string,
    payload: ArrayBuffer,
    title: string,
    attribution: string,
    foregroundAnalysis: HomeWallpaperForegroundAnalysis,
    appearanceLight?: BrowserHomepageBackdropAppearanceState,
    appearanceDark?: BrowserHomepageBackdropAppearanceState,
    nowMs: number = Date.now()
  ): Promise<WallpaperAsset> {
    if (assetId.trim().length === 0 || payload.byteLength <= 0 || payload.byteLength > MAX_IMPORTED_IMAGE_BYTES) {
      throw new Error('壁纸图片下载失败。');
    }

    await this.ensureDirectories();
    const id = this.sanitizeAssetId(assetId);
    const contentSignature = this.sanitizeAssetId(foregroundAnalysis.contentSignature);
    if (contentSignature.length <= 0) {
      throw new Error('壁纸图片内容标识无效。');
    }
    const fileName = `${id}-${contentSignature}.jpg`;
    const tempPath = `${this.getDownloadsDir()}/${fileName}.download`;
    const finalPath = `${this.getOriginalDir()}/${fileName}`;

    await this.deleteIfExists(tempPath);
    const file = await fileIo.open(tempPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }

    if (await this.fileExists(finalPath)) {
      await this.deleteIfExists(tempPath);
    } else {
      await fileIo.rename(tempPath, finalPath);
    }
    const finalUri = fileUri.getUriFromPath(finalPath);
    return {
      id: id,
      source: source,
      mediaType: 'image',
      originalPath: finalUri,
      displayPath: finalUri,
      thumbPath: finalUri,
      contentSignature: foregroundAnalysis.contentSignature,
      foregroundTone: foregroundAnalysis.foregroundTone,
      foregroundToneContentSignature: foregroundAnalysis.contentSignature,
      foregroundToneCropSignature: foregroundAnalysis.cropSignature,
      foregroundToneSampleSignature: foregroundAnalysis.sampleSignature,
      foregroundToneAlgorithmVersion: foregroundAnalysis.algorithmVersion,
      appearanceLight: appearanceLight,
      appearanceDark: appearanceDark,
      width: 0,
      height: 0,
      mimeType: 'image/jpeg',
      byteSize: payload.byteLength,
      title: title.trim().length > 0 ? title.trim() : 'Bing 每日壁纸',
      attribution: attribution.trim(),
      createdAt: nowMs,
      updatedAt: nowMs,
      isFavorite: false
    };
  }

  async pruneObsoleteDownloadedImages(activeAsset: WallpaperAsset): Promise<void> {
    const activeFileName = `${this.sanitizeAssetId(activeAsset.id)}-${this.sanitizeAssetId(activeAsset.contentSignature)}.jpg`;
    const prefix = `${this.sanitizeAssetId(activeAsset.id)}-`;
    const fileNames = await fileIo.listFile(this.getOriginalDir());
    for (let index = 0; index < fileNames.length; index += 1) {
      const fileName = fileNames[index];
      if (fileName === activeFileName || !fileName.startsWith(prefix) || !fileName.endsWith('.jpg')) {
        continue;
      }
      await this.deleteIfExists(`${this.getOriginalDir()}/${fileName}`);
    }
  }

  async saveImportedImage(
    sourceUri: string,
    sourceFileName: string,
    assetId: string,
    width: number,
    height: number,
    foregroundAnalysis: HomeWallpaperForegroundAnalysis,
    nowMs: number = Date.now()
  ): Promise<WallpaperAsset> {
    const normalizedSourceUri = sourceUri.trim();
    if (normalizedSourceUri.length <= 0 || assetId.trim().length <= 0) {
      throw new Error('未选择壁纸图片。');
    }
    await this.ensureDirectories();
    const id = this.sanitizeAssetId(assetId);
    const contentSignature = this.sanitizeAssetId(foregroundAnalysis.contentSignature);
    if (contentSignature.length <= 0) {
      throw new Error('壁纸图片内容标识无效。');
    }
    const extension = this.resolveImportedImageExtension(sourceFileName);
    const fileName = `${id}-${contentSignature}.${extension}`;
    const tempPath = `${this.getDownloadsDir()}/${fileName}.import`;
    const finalPath = `${this.getOriginalDir()}/${fileName}`;
    await this.deleteIfExists(tempPath);
    try {
      await fileIo.copy(normalizedSourceUri, fileUri.getUriFromPath(tempPath));
      const stat = await fileIo.stat(tempPath);
      if (stat.isDirectory() || stat.size <= 0) {
        throw new Error('壁纸图片不可用。');
      }
      if (stat.size > MAX_IMPORTED_IMAGE_BYTES) {
        throw new Error('壁纸图片超过 30 MB。');
      }
      if (await this.fileExists(finalPath)) {
        await this.deleteIfExists(tempPath);
      } else {
        await fileIo.rename(tempPath, finalPath);
      }
      const finalUri = fileUri.getUriFromPath(finalPath);
      return {
        id: id,
        source: 'custom',
        mediaType: 'image',
        originalPath: finalUri,
        displayPath: finalUri,
        thumbPath: finalUri,
        contentSignature: foregroundAnalysis.contentSignature,
        foregroundTone: foregroundAnalysis.foregroundTone,
        foregroundToneContentSignature: foregroundAnalysis.contentSignature,
        foregroundToneCropSignature: foregroundAnalysis.cropSignature,
        foregroundToneSampleSignature: foregroundAnalysis.sampleSignature,
        foregroundToneAlgorithmVersion: foregroundAnalysis.algorithmVersion,
        width: Math.max(1, Math.floor(width)),
        height: Math.max(1, Math.floor(height)),
        mimeType: this.resolveImportedMimeType(extension),
        byteSize: Math.max(0, Math.floor(stat.size)),
        title: '自定义壁纸',
        attribution: '',
        createdAt: nowMs,
        updatedAt: nowMs,
        isFavorite: false
      };
    } catch (error) {
      await this.deleteIfExists(tempPath);
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error('无法保存这张壁纸，请换一张再试。');
    }
  }

  async pruneObsoleteImportedImages(activeAsset: WallpaperAsset): Promise<void> {
    const prefix = `${this.sanitizeAssetId(activeAsset.id)}-`;
    const activeUri = activeAsset.originalPath;
    const fileNames = await fileIo.listFile(this.getOriginalDir());
    for (let index = 0; index < fileNames.length; index += 1) {
      const fileName = fileNames[index];
      const path = `${this.getOriginalDir()}/${fileName}`;
      if (!fileName.startsWith(prefix) || fileUri.getUriFromPath(path) === activeUri) {
        continue;
      }
      await this.deleteIfExists(path);
    }
  }

  async discardStoredImage(asset: WallpaperAsset): Promise<void> {
    await this.deleteIfExists(asset.originalPath);
  }

  private async ensureDirectories(): Promise<void> {
    await this.ensureDirectory(this.getRootDir());
    await this.ensureDirectory(this.getOriginalDir());
    await this.ensureDirectory(this.getDownloadsDir());
  }

  private async ensureDirectory(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        return;
      }
    } catch (_error) {
    }
    await fileIo.mkdir(path, true);
  }

  private async deleteIfExists(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        await fileIo.unlink(path);
      }
    } catch (_error) {
    }
  }

  private async fileExists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }

  private getRootDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${WALLPAPER_ROOT_DIR}`;
  }

  private getOriginalDir(): string {
    return `${this.getRootDir()}/${WALLPAPER_ORIGINAL_DIR}`;
  }

  private getDownloadsDir(): string {
    return `${this.getRootDir()}/${WALLPAPER_DOWNLOAD_DIR}`;
  }

  private sanitizeAssetId(value: string): string {
    const normalized = value
      .replace(/[^a-zA-Z0-9_-]/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');
    return normalized.length > 0 ? normalized : `wallpaper-${Math.max(0, Math.floor(Date.now()))}`;
  }

  private resolveImportedImageExtension(fileName: string): string {
    const normalized = fileName.trim().toLowerCase().split('?')[0].split('#')[0];
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'jpg';
    }
    if (normalized.endsWith('.png')) {
      return 'png';
    }
    if (normalized.endsWith('.webp')) {
      return 'webp';
    }
    if (normalized.endsWith('.heic')) {
      return 'heic';
    }
    if (normalized.endsWith('.heif')) {
      return 'heif';
    }
    return 'image';
  }

  private resolveImportedMimeType(extension: string): string {
    if (extension === 'jpg') {
      return 'image/jpeg';
    }
    if (extension === 'png') {
      return 'image/png';
    }
    if (extension === 'webp') {
      return 'image/webp';
    }
    if (extension === 'heic' || extension === 'heif') {
      return 'image/heif';
    }
    return 'image/*';
  }
}

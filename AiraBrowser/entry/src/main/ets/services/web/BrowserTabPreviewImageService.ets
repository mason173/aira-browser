import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BROWSER_TAB_SHARED_SNAPSHOT_MAX_PIXEL_WIDTH } from '../../core/browser/BrowserTabPreviewMetrics';
import { BrowserTabPreviewCaptureSource } from './BrowserTabPreviewTypes';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TabPreviewImage';
const SHARED_SNAPSHOT_MAX_EDGE_CROP_RATIO: number = 0.04;
const SHARED_SNAPSHOT_ASPECT_EPSILON: number = 0.002;

export interface BrowserTabSharedSnapshotNormalizeOptions {
  targetAspectRatio?: number;
  edgeCropRatio?: number;
  maxPixelWidth?: number;
}

interface BrowserTabSharedSnapshotCropRegion {
  x: number;
  y: number;
  size: BrowserTabSharedSnapshotCropSize;
}

interface BrowserTabSharedSnapshotCropSize {
  width: number;
  height: number;
}

export class BrowserTabPreviewImageService {
  async normalizeForSharedSnapshot(
    snapshot: image.PixelMap,
    tabId: string,
    source: BrowserTabPreviewCaptureSource,
    options?: BrowserTabSharedSnapshotNormalizeOptions
  ): Promise<image.PixelMap> {
    let imageInfo: image.ImageInfo;
    try {
      imageInfo = snapshot.getImageInfoSync();
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'shared snapshot info failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
      return snapshot;
    }

    const width = Math.floor(imageInfo.size.width);
    const height = Math.floor(imageInfo.size.height);
    if (width <= 0 || height <= 0) {
      return snapshot;
    }

    const normalizeOptions = options ?? {};
    const cropRegion = this.resolveCropRegion(width, height, normalizeOptions);
    const cropWidth = Math.max(1, Math.floor(cropRegion.size.width));
    const cropHeight = Math.max(1, Math.floor(cropRegion.size.height));
    const maxPixelWidth = this.resolveMaxPixelWidth(normalizeOptions);
    const scale = cropWidth > maxPixelWidth ? maxPixelWidth / cropWidth : 1;
    if (this.isFullCropRegion(cropRegion, width, height) && scale >= 1) {
      return snapshot;
    }

    const targetWidth = Math.max(1, Math.round(cropWidth * scale));
    const targetHeight = Math.max(1, Math.round(cropHeight * scale));
    try {
      const sharedSnapshot = await snapshot.createCroppedAndScaledPixelMap(cropRegion, scale, scale,
        image.AntiAliasingLevel.LOW);
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'shared snapshot normalized tab=%{public}s source=%{public}s width=%{public}d height=%{public}d cropX=%{public}d cropY=%{public}d cropW=%{public}d cropH=%{public}d targetW=%{public}d targetH=%{public}d',
        tabId, source, width, height, cropRegion.x, cropRegion.y, cropWidth, cropHeight, targetWidth, targetHeight);
      return sharedSnapshot;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'shared snapshot normalize failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
      return snapshot;
    }
  }

  private resolveMaxPixelWidth(options: BrowserTabSharedSnapshotNormalizeOptions): number {
    const maxPixelWidth = Math.floor(options.maxPixelWidth ?? BROWSER_TAB_SHARED_SNAPSHOT_MAX_PIXEL_WIDTH);
    return Number.isFinite(maxPixelWidth) && maxPixelWidth > 0 ?
      maxPixelWidth : BROWSER_TAB_SHARED_SNAPSHOT_MAX_PIXEL_WIDTH;
  }

  private resolveCropRegion(
    width: number,
    height: number,
    options: BrowserTabSharedSnapshotNormalizeOptions
  ): BrowserTabSharedSnapshotCropRegion {
    const edgeCropRatio = this.clampNumber(options.edgeCropRatio ?? 0, 0, SHARED_SNAPSHOT_MAX_EDGE_CROP_RATIO);
    let x = Math.floor(width * edgeCropRatio);
    let y = Math.floor(height * edgeCropRatio);
    let cropWidth = Math.max(1, width - x * 2);
    let cropHeight = Math.max(1, height - y * 2);
    const targetAspectRatio = options.targetAspectRatio ?? 0;
    if (Number.isFinite(targetAspectRatio) && targetAspectRatio > 0) {
      const currentAspectRatio = cropWidth / cropHeight;
      if (Math.abs(currentAspectRatio - targetAspectRatio) > SHARED_SNAPSHOT_ASPECT_EPSILON) {
        if (currentAspectRatio > targetAspectRatio) {
          const nextWidth = Math.max(1, Math.round(cropHeight * targetAspectRatio));
          x += Math.floor((cropWidth - nextWidth) / 2);
          cropWidth = nextWidth;
        } else {
          const nextHeight = Math.max(1, Math.round(cropWidth / targetAspectRatio));
          y += Math.floor((cropHeight - nextHeight) / 2);
          cropHeight = nextHeight;
        }
      }
    }
    const size: BrowserTabSharedSnapshotCropSize = {
      width: Math.max(1, Math.min(cropWidth, width - x)),
      height: Math.max(1, Math.min(cropHeight, height - y))
    };
    const cropRegion: BrowserTabSharedSnapshotCropRegion = {
      x: this.clampNumber(x, 0, Math.max(0, width - 1)),
      y: this.clampNumber(y, 0, Math.max(0, height - 1)),
      size: size
    };
    return cropRegion;
  }

  private isFullCropRegion(
    cropRegion: BrowserTabSharedSnapshotCropRegion,
    width: number,
    height: number
  ): boolean {
    return cropRegion.x === 0 &&
      cropRegion.y === 0 &&
      cropRegion.size.width === width &&
      cropRegion.size.height === height;
  }

  private clampNumber(value: number, min: number, max: number): number {
    if (!Number.isFinite(value)) {
      return min;
    }
    return Math.max(min, Math.min(max, value));
  }

}

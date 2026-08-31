import { image } from '@kit.ImageKit';
import {
  HOME_WALLPAPER_FOREGROUND_ALGORITHM_VERSION,
  HomeWallpaperForegroundAnalysis,
  HomeWallpaperForegroundTone,
  HomeWallpaperVisibleCropInput
} from '../../common/models/WallpaperModels';
import { resolveHomeWallpaperRenderedMaskOpacity } from './HomeWallpaperAnalysisPolicy';

interface WallpaperSampleSize {
  width: number;
  height: number;
}

const WALLPAPER_SAMPLE_LONG_EDGE: number = 72;
const WALLPAPER_MIN_VIEWPORT_EDGE: number = 1;
const WALLPAPER_DARK_TEXT_MIN_MEAN_LUMINANCE: number = 0.7;
const WALLPAPER_DARK_TEXT_MIN_PIXEL_CONTRAST: number = 5.5;
const WALLPAPER_DARK_TEXT_MAX_RISK_COVERAGE: number = 0.05;
const WALLPAPER_MASK_RED: number = 0;
const WALLPAPER_MASK_GREEN: number = 0;
const WALLPAPER_MASK_BLUE: number = 0;

export class WallpaperForegroundToneService {
  async createVisibleCropSample(
    imageSource: image.ImageSource,
    cropInput: HomeWallpaperVisibleCropInput
  ): Promise<image.PixelMap> {
    const sourceInfo = await imageSource.getImageInfo();
    const sourceWidth = Math.max(1, Math.floor(sourceInfo.size.width));
    const sourceHeight = Math.max(1, Math.floor(sourceInfo.size.height));
    const viewportWidth = this.normalizeViewportEdge(cropInput.viewportWidth);
    const viewportHeight = this.normalizeViewportEdge(cropInput.viewportHeight);
    const cropRegion = this.resolveCoverCropRegion(sourceWidth, sourceHeight, viewportWidth, viewportHeight);
    const targetSize = this.resolveSampleSize(viewportWidth, viewportHeight);
    return imageSource.createPixelMap({
      index: 0,
      desiredRegion: cropRegion,
      desiredSize: targetSize,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
    });
  }

  async resolveToneFromPixelMap(
    pixelMap: image.PixelMap,
    cropInput: HomeWallpaperVisibleCropInput,
    contentSignature: string
  ): Promise<HomeWallpaperForegroundAnalysis> {
    const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
    await pixelMap.readPixelsToBuffer(buffer);
    return this.resolveToneFromRgbaBuffer(buffer, cropInput, contentSignature);
  }

  resolveToneFromRgbaBuffer(
    pixelBuffer: ArrayBuffer,
    cropInput: HomeWallpaperVisibleCropInput,
    contentSignature: string
  ): HomeWallpaperForegroundAnalysis {
    const normalizedContentSignature = contentSignature.trim();
    if (normalizedContentSignature.length <= 0) {
      throw new Error('wallpaper-content-signature-missing');
    }
    const pixels = new Uint8Array(pixelBuffer);
    const maskOpacity = resolveHomeWallpaperRenderedMaskOpacity(cropInput.maskOpacity);
    let signatureHash = 2166136261;
    let luminanceTotal = 0;
    let darkTextRiskCount = 0;
    let visiblePixelCount = 0;
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      const alpha = pixels[index + 3] / 255;
      if (alpha <= 0.05) {
        continue;
      }
      const red = this.compositeMaskChannel(pixels[index] / 255, WALLPAPER_MASK_RED, maskOpacity);
      const green = this.compositeMaskChannel(pixels[index + 1] / 255, WALLPAPER_MASK_GREEN, maskOpacity);
      const blue = this.compositeMaskChannel(pixels[index + 2] / 255, WALLPAPER_MASK_BLUE, maskOpacity);
      const luminance = 0.2126 * this.toLinearChannel(red) +
        0.7152 * this.toLinearChannel(green) +
        0.0722 * this.toLinearChannel(blue);
      const darkTextContrast = (luminance + 0.05) / 0.05;
      luminanceTotal += luminance;
      visiblePixelCount += 1;
      if (darkTextContrast <= WALLPAPER_DARK_TEXT_MIN_PIXEL_CONTRAST) {
        darkTextRiskCount += 1;
      }
      signatureHash = this.hashPixel(signatureHash, pixels[index], pixels[index + 1], pixels[index + 2]);
    }
    const cropSignature = this.buildCropSignature(cropInput);
    if (visiblePixelCount <= 0) {
      throw new Error('wallpaper-foreground-analysis-empty');
    }
    const meanLuminance = luminanceTotal / visiblePixelCount;
    const darkTextRiskCoverage = darkTextRiskCount / visiblePixelCount;
    return {
      foregroundTone: this.resolveTone(meanLuminance, darkTextRiskCoverage),
      contentSignature: normalizedContentSignature,
      cropSignature: cropSignature,
      sampleSignature: this.hashToString(signatureHash),
      algorithmVersion: HOME_WALLPAPER_FOREGROUND_ALGORITHM_VERSION
    };
  }

  buildCropSignature(cropInput: HomeWallpaperVisibleCropInput): string {
    const width = this.normalizeViewportEdge(cropInput.viewportWidth);
    const height = this.normalizeViewportEdge(cropInput.viewportHeight);
    const aspectBucket = Math.max(1, Math.round((width / height) * 1000));
    const maskBucket = Math.round(Math.max(0, Math.min(100, cropInput.maskOpacity)));
    return `cover:${aspectBucket}:mask-${maskBucket}`;
  }

  private resolveCoverCropRegion(
    sourceWidth: number,
    sourceHeight: number,
    viewportWidth: number,
    viewportHeight: number
  ): image.Region {
    const sourceAspect = sourceWidth / sourceHeight;
    const viewportAspect = viewportWidth / viewportHeight;
    if (sourceAspect > viewportAspect) {
      const cropWidth = Math.max(1, Math.min(sourceWidth, Math.round(sourceHeight * viewportAspect)));
      return {
        x: Math.max(0, Math.floor((sourceWidth - cropWidth) / 2)),
        y: 0,
        size: { width: cropWidth, height: sourceHeight }
      };
    }
    const cropHeight = Math.max(1, Math.min(sourceHeight, Math.round(sourceWidth / viewportAspect)));
    return {
      x: 0,
      y: Math.max(0, Math.floor((sourceHeight - cropHeight) / 2)),
      size: { width: sourceWidth, height: cropHeight }
    };
  }

  private resolveSampleSize(viewportWidth: number, viewportHeight: number): WallpaperSampleSize {
    const aspect = viewportWidth / viewportHeight;
    if (aspect >= 1) {
      return {
        width: WALLPAPER_SAMPLE_LONG_EDGE,
        height: Math.max(1, Math.round(WALLPAPER_SAMPLE_LONG_EDGE / aspect))
      };
    }
    return {
      width: Math.max(1, Math.round(WALLPAPER_SAMPLE_LONG_EDGE * aspect)),
      height: WALLPAPER_SAMPLE_LONG_EDGE
    };
  }

  private resolveTone(
    meanLuminance: number,
    darkTextRiskCoverage: number
  ): HomeWallpaperForegroundTone {
    const supportsDarkText = meanLuminance > WALLPAPER_DARK_TEXT_MIN_MEAN_LUMINANCE &&
      darkTextRiskCoverage <= WALLPAPER_DARK_TEXT_MAX_RISK_COVERAGE;
    return supportsDarkText ? 'darkText' : 'lightText';
  }

  private compositeMaskChannel(channel: number, maskChannel: number, maskOpacity: number): number {
    return channel * (1 - maskOpacity) + maskChannel * maskOpacity;
  }

  private toLinearChannel(channel: number): number {
    const clamped = Math.max(0, Math.min(1, channel));
    if (clamped <= 0.04045) {
      return clamped / 12.92;
    }
    return Math.pow((clamped + 0.055) / 1.055, 2.4);
  }

  private normalizeViewportEdge(value: number): number {
    if (!Number.isFinite(value) || value < WALLPAPER_MIN_VIEWPORT_EDGE) {
      return WALLPAPER_MIN_VIEWPORT_EDGE;
    }
    return value;
  }

  private hashPixel(hash: number, red: number, green: number, blue: number): number {
    let next = Math.imul(hash ^ red, 16777619);
    next = Math.imul(next ^ green, 16777619);
    return Math.imul(next ^ blue, 16777619);
  }

  private hashToString(hash: number): string {
    return (hash >>> 0).toString(16);
  }
}

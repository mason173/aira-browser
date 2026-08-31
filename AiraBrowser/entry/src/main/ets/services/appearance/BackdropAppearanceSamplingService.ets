import { image } from '@kit.ImageKit';
import {
  BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
  BrowserHomepageBackdropAppearanceEffectInput,
  BrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';

interface BackdropAppearanceRgbColor {
  red: number;
  green: number;
  blue: number;
}

interface BackdropAppearanceSampleBucket {
  redTotal: number;
  greenTotal: number;
  blueTotal: number;
  alphaTotal: number;
  count: number;
}

interface BackdropAppearanceSamplingResult {
  toolbarColor: BackdropAppearanceRgbColor;
  snapshotSignature: string;
}

export interface BackdropAppearanceSamplingInput {
  pixelMap: image.PixelMap;
  sourceKey: string;
  effect: BrowserHomepageBackdropAppearanceEffectInput;
  volatileOnly: boolean;
  nowMs?: number;
}

const APPEARANCE_SAMPLE_WIDTH: number = 48;
const APPEARANCE_SAMPLE_HEIGHT: number = 72;
const TOOLBAR_SAMPLE_START_RATIO: number = 0.58;
const TOOLBAR_LIGHTNESS_THRESHOLD: number = 0.57;

export class BackdropAppearanceSamplingService {
  async sample(input: BackdropAppearanceSamplingInput): Promise<BrowserHomepageBackdropAppearanceState | undefined> {
    const samplingResult = await this.samplePixelMap(input.pixelMap);
    if (samplingResult === undefined) {
      return undefined;
    }
    const toolbarSurface = this.applyEffect(samplingResult.toolbarColor, input.effect);
    const foregroundTone = this.resolveForegroundTone(toolbarSurface);
    return {
      available: true,
      sourceKey: input.sourceKey,
      snapshotSignature: samplingResult.snapshotSignature,
      algorithmVersion: BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
      resolvedThemeMode: input.effect.resolvedThemeMode,
      toolbarSurfaceColor: this.toHexColor(toolbarSurface),
      toolbarForegroundTone: foregroundTone,
      toolbarLabelTextColor: foregroundTone === 'light' ? '#FFFFFFFF' : '#FF000000',
      toolbarPrimaryTextColor: foregroundTone === 'light' ? '#FFFFFFFF' : '#FF000000',
      toolbarSecondaryTextColor: foregroundTone === 'light' ? '#B3FFFFFF' : '#99000000',
      toolbarPressedOverlayColor: foregroundTone === 'light' ? '#18FFFFFF' : '#14000000',
      toolbarOutlineColor: foregroundTone === 'light' ? '#24FFFFFF' : '#18000000',
      updatedAt: input.nowMs ?? Date.now(),
      volatileOnly: input.volatileOnly
    };
  }

  private async samplePixelMap(pixelMap: image.PixelMap): Promise<BackdropAppearanceSamplingResult | undefined> {
    let sample: image.PixelMap | undefined = undefined;
    try {
      const info = pixelMap.getImageInfoSync();
      const width = Math.max(1, Math.floor(info.size.width));
      const height = Math.max(1, Math.floor(info.size.height));
      const targetWidth = Math.min(APPEARANCE_SAMPLE_WIDTH, width);
      const targetHeight = Math.min(APPEARANCE_SAMPLE_HEIGHT, height);
      sample = await pixelMap.createCroppedAndScaledPixelMap({
        x: 0,
        y: 0,
        size: {
          width: width,
          height: height
        }
      }, targetWidth / width, targetHeight / height, image.AntiAliasingLevel.LOW);
      const buffer = new ArrayBuffer(sample.getPixelBytesNumber());
      await sample.readPixelsToBuffer(buffer);
      return this.resolveSampledColors(buffer, targetWidth, targetHeight);
    } catch (_error) {
      return undefined;
    } finally {
      if (sample !== undefined && sample !== pixelMap) {
        void sample.release().catch((_releaseError: Error) => {});
      }
    }
  }

  private resolveSampledColors(
    buffer: ArrayBuffer,
    width: number,
    height: number
  ): BackdropAppearanceSamplingResult | undefined {
    const pixels = new Uint8Array(buffer);
    if (pixels.length < 4 || width <= 0 || height <= 0) {
      return undefined;
    }
    const whole = this.createBucket();
    const toolbar = this.createBucket();
    const toolbarStartY = Math.max(0, Math.min(height - 1, Math.floor(height * TOOLBAR_SAMPLE_START_RATIO)));
    let signatureHash = 2166136261;
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      const pixelIndex = Math.floor(index / 4);
      const y = Math.floor(pixelIndex / width);
      const alpha = pixels[index + 3] / 255;
      if (alpha <= 0.05) {
        continue;
      }
      const red = pixels[index] / 255;
      const green = pixels[index + 1] / 255;
      const blue = pixels[index + 2] / 255;
      this.addPixel(whole, red, green, blue, alpha);
      if (y >= toolbarStartY) {
        this.addPixel(toolbar, red, green, blue, alpha);
      }
      signatureHash = this.hashSignaturePixel(signatureHash, pixels[index], pixels[index + 1], pixels[index + 2], y);
    }
    if (whole.count <= 0) {
      return undefined;
    }
    const wholeColor = this.resolveBucketColor(whole);
    return {
      toolbarColor: toolbar.count > 0 ? this.resolveBucketColor(toolbar) : wholeColor,
      snapshotSignature: this.hashToString(signatureHash)
    };
  }

  private createBucket(): BackdropAppearanceSampleBucket {
    return {
      redTotal: 0,
      greenTotal: 0,
      blueTotal: 0,
      alphaTotal: 0,
      count: 0
    };
  }

  private addPixel(
    bucket: BackdropAppearanceSampleBucket,
    red: number,
    green: number,
    blue: number,
    alpha: number
  ): void {
    bucket.redTotal += red * alpha;
    bucket.greenTotal += green * alpha;
    bucket.blueTotal += blue * alpha;
    bucket.alphaTotal += alpha;
    bucket.count += 1;
  }

  private resolveBucketColor(bucket: BackdropAppearanceSampleBucket): BackdropAppearanceRgbColor {
    const divisor = Math.max(0.0001, bucket.alphaTotal);
    return {
      red: this.clamp01(bucket.redTotal / divisor),
      green: this.clamp01(bucket.greenTotal / divisor),
      blue: this.clamp01(bucket.blueTotal / divisor)
    };
  }

  private applyEffect(
    color: BackdropAppearanceRgbColor,
    effect: BrowserHomepageBackdropAppearanceEffectInput
  ): BackdropAppearanceRgbColor {
    const tint = this.parseHexColor(effect.tintColor);
    const tintOpacity = this.clamp01(effect.tintOpacity);
    if (tint === undefined || tintOpacity <= 0) {
      return color;
    }
    return {
      red: this.clamp01(color.red * (1 - tintOpacity) + tint.red * tintOpacity),
      green: this.clamp01(color.green * (1 - tintOpacity) + tint.green * tintOpacity),
      blue: this.clamp01(color.blue * (1 - tintOpacity) + tint.blue * tintOpacity)
    };
  }

  private resolveForegroundTone(color: BackdropAppearanceRgbColor): 'light' | 'dark' {
    return this.resolveLuminance(color) >= TOOLBAR_LIGHTNESS_THRESHOLD ? 'dark' : 'light';
  }

  private resolveLuminance(color: BackdropAppearanceRgbColor): number {
    return 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue;
  }

  private parseHexColor(value: string): BackdropAppearanceRgbColor | undefined {
    let normalized = value.trim();
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    if (normalized.length === 8) {
      normalized = normalized.substring(2);
    }
    if (normalized.length !== 6 || !this.isHexColor(normalized)) {
      return undefined;
    }
    return {
      red: Number.parseInt(normalized.substring(0, 2), 16) / 255,
      green: Number.parseInt(normalized.substring(2, 4), 16) / 255,
      blue: Number.parseInt(normalized.substring(4, 6), 16) / 255
    };
  }

  private toHexColor(color: BackdropAppearanceRgbColor): string {
    return `#${this.channelToHex(color.red)}${this.channelToHex(color.green)}${this.channelToHex(color.blue)}`;
  }

  private channelToHex(value: number): string {
    const hex = Math.round(this.clamp01(value) * 255).toString(16).toUpperCase();
    return hex.length === 1 ? `0${hex}` : hex;
  }

  private isHexColor(value: string): boolean {
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const digit = code >= 48 && code <= 57;
      const upper = code >= 65 && code <= 70;
      const lower = code >= 97 && code <= 102;
      if (!digit && !upper && !lower) {
        return false;
      }
    }
    return true;
  }

  private hashSignaturePixel(hash: number, red: number, green: number, blue: number, y: number): number {
    let next = hash ^ red;
    next = Math.imul(next, 16777619);
    next = next ^ green;
    next = Math.imul(next, 16777619);
    next = next ^ blue;
    next = Math.imul(next, 16777619);
    next = next ^ y;
    return Math.imul(next, 16777619);
  }

  private hashToString(hash: number): string {
    return (hash >>> 0).toString(16);
  }

  private clamp01(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }
}

import { image } from '@kit.ImageKit';
import {
  NovelBookCoverPalette,
  NovelBookPaletteThemeMode
} from '../../features/novel/NovelLibraryModels';
import {
  NovelBookCoverRequestService,
  sharedNovelBookCoverRequestService
} from './NovelBookCoverRequestService';

interface NovelBookCoverRgbColor {
  red: number;
  green: number;
  blue: number;
}

interface NovelBookCoverHslColor {
  hue: number;
  saturation: number;
  lightness: number;
}

interface NovelBookCoverColorBucket {
  redTotal: number;
  greenTotal: number;
  blueTotal: number;
  saturationTotal: number;
  count: number;
}

const COVER_SAMPLE_WIDTH: number = 48;
const COVER_SAMPLE_HEIGHT: number = 64;
const COVER_BUCKET_STEP: number = 32;
const COVER_MIN_ALPHA: number = 0.8;
const COVER_MIN_LIGHTNESS: number = 0.06;
const COVER_MAX_LIGHTNESS: number = 0.94;
const COVER_WHITE_TEXT_MIN_CONTRAST: number = 5.2;

export class NovelBookCoverPaletteService {
  private readonly requestService: NovelBookCoverRequestService;

  constructor(requestService: NovelBookCoverRequestService = sharedNovelBookCoverRequestService) {
    this.requestService = requestService;
  }

  async resolve(
    coverUrl: string,
    refererUrl: string,
    themeMode: NovelBookPaletteThemeMode
  ): Promise<NovelBookCoverPalette | undefined> {
    const candidates: string[] = this.requestService.resolveCoverCandidates(coverUrl, refererUrl);
    for (let index: number = 0; index < candidates.length; index += 1) {
      try {
        const payload: ArrayBuffer = await this.requestService.downloadCandidate(candidates[index], refererUrl);
        const palette: NovelBookCoverPalette | undefined = await this.resolvePayload(payload, themeMode);
        if (palette !== undefined) {
          return palette;
        }
      } catch (_error) {
        // 继续尝试下一个安全候选。
      }
    }
    return undefined;
  }

  private async resolvePayload(
    payload: ArrayBuffer,
    themeMode: NovelBookPaletteThemeMode
  ): Promise<NovelBookCoverPalette | undefined> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      imageSource = image.createImageSource(payload);
      pixelMap = await imageSource.createPixelMap({
        index: 0,
        editable: false,
        desiredSize: {
          width: COVER_SAMPLE_WIDTH,
          height: COVER_SAMPLE_HEIGHT
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readPixelsToBuffer(buffer);
      const dominantColor = this.resolveDominantColor(buffer, true) ?? this.resolveDominantColor(buffer, false);
      if (dominantColor === undefined) {
        return undefined;
      }
      return this.buildPalette(dominantColor, themeMode);
    } catch (_error) {
      return undefined;
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release().catch((_error: Error): void => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error): void => {});
      }
    }
  }

  private resolveDominantColor(buffer: ArrayBuffer, filterExtremes: boolean): NovelBookCoverRgbColor | undefined {
    const pixels = new Uint8Array(buffer);
    const buckets: NovelBookCoverColorBucket[] = [];
    const bucketIndexes: Record<string, number> = {};
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      const alpha = pixels[index + 3] / 255;
      if (alpha < COVER_MIN_ALPHA) {
        continue;
      }
      const red = pixels[index] / 255;
      const green = pixels[index + 1] / 255;
      const blue = pixels[index + 2] / 255;
      const hsl = this.rgbToHsl({ red: red, green: green, blue: blue });
      if (filterExtremes && (hsl.lightness < COVER_MIN_LIGHTNESS || hsl.lightness > COVER_MAX_LIGHTNESS)) {
        continue;
      }
      const key = this.buildBucketKey(pixels[index], pixels[index + 1], pixels[index + 2]);
      let bucketIndex = bucketIndexes[key];
      if (bucketIndex === undefined) {
        bucketIndex = buckets.length;
        bucketIndexes[key] = bucketIndex;
        buckets.push({
          redTotal: 0,
          greenTotal: 0,
          blueTotal: 0,
          saturationTotal: 0,
          count: 0
        });
      }
      const bucket = buckets[bucketIndex];
      bucket.redTotal += red;
      bucket.greenTotal += green;
      bucket.blueTotal += blue;
      bucket.saturationTotal += hsl.saturation;
      bucket.count += 1;
    }
    let bestBucket: NovelBookCoverColorBucket | undefined = undefined;
    let bestScore: number = -1;
    for (let index = 0; index < buckets.length; index += 1) {
      const bucket = buckets[index];
      const meanSaturation = bucket.saturationTotal / Math.max(1, bucket.count);
      const score = bucket.count * (0.72 + 0.28 * meanSaturation);
      if (score > bestScore) {
        bestScore = score;
        bestBucket = bucket;
      }
    }
    if (bestBucket === undefined || bestBucket.count <= 0) {
      return undefined;
    }
    return {
      red: bestBucket.redTotal / bestBucket.count,
      green: bestBucket.greenTotal / bestBucket.count,
      blue: bestBucket.blueTotal / bestBucket.count
    };
  }

  private buildPalette(source: NovelBookCoverRgbColor, themeMode: NovelBookPaletteThemeMode): NovelBookCoverPalette {
    const sourceHsl = this.rgbToHsl(source);
    const saturation = sourceHsl.saturation < 0.06 ? 0 :
      Math.max(themeMode === 'dark' ? 0.12 : 0.16, Math.min(themeMode === 'dark' ? 0.34 : 0.42,
        sourceHsl.saturation * 0.72));
    let background = this.hslToRgb({
      hue: sourceHsl.hue,
      saturation: saturation,
      lightness: themeMode === 'dark' ? 0.2 : 0.34
    });
    background = this.ensureWhiteTextContrast(background);
    const surface = this.mix(background, { red: 0, green: 0, blue: 0 }, themeMode === 'dark' ? 0.18 : 0.13);
    return {
      backgroundColor: this.toHexColor(background),
      surfaceColor: this.toHexColor(surface),
      primaryTextColor: '#FFFFFFFF',
      secondaryTextColor: '#C7FFFFFF',
      dividerColor: '#26FFFFFF',
      glassTintColor: this.toArgbColor(background, themeMode === 'dark' ? 0.74 : 0.66)
    };
  }

  private ensureWhiteTextContrast(color: NovelBookCoverRgbColor): NovelBookCoverRgbColor {
    let resolved = color;
    for (let attempt = 0; attempt < 8; attempt += 1) {
      if (this.resolveContrastWithWhite(resolved) >= COVER_WHITE_TEXT_MIN_CONTRAST) {
        break;
      }
      resolved = this.mix(resolved, { red: 0, green: 0, blue: 0 }, 0.1);
    }
    return resolved;
  }

  private resolveContrastWithWhite(color: NovelBookCoverRgbColor): number {
    return 1.05 / (this.resolveRelativeLuminance(color) + 0.05);
  }

  private resolveRelativeLuminance(color: NovelBookCoverRgbColor): number {
    return 0.2126 * this.toLinearChannel(color.red) +
      0.7152 * this.toLinearChannel(color.green) +
      0.0722 * this.toLinearChannel(color.blue);
  }

  private toLinearChannel(value: number): number {
    const channel = this.clamp01(value);
    return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
  }

  private rgbToHsl(color: NovelBookCoverRgbColor): NovelBookCoverHslColor {
    const maximum = Math.max(color.red, color.green, color.blue);
    const minimum = Math.min(color.red, color.green, color.blue);
    const delta = maximum - minimum;
    const lightness = (maximum + minimum) / 2;
    let hue = 0;
    let saturation = 0;
    if (delta > 0.0001) {
      saturation = delta / (1 - Math.abs(2 * lightness - 1));
      if (maximum === color.red) {
        hue = ((color.green - color.blue) / delta) % 6;
      } else if (maximum === color.green) {
        hue = (color.blue - color.red) / delta + 2;
      } else {
        hue = (color.red - color.green) / delta + 4;
      }
      hue /= 6;
      if (hue < 0) {
        hue += 1;
      }
    }
    return {
      hue: hue,
      saturation: this.clamp01(saturation),
      lightness: this.clamp01(lightness)
    };
  }

  private hslToRgb(color: NovelBookCoverHslColor): NovelBookCoverRgbColor {
    const chroma = (1 - Math.abs(2 * color.lightness - 1)) * color.saturation;
    const hueSection = color.hue * 6;
    const secondary = chroma * (1 - Math.abs((hueSection % 2) - 1));
    let red = 0;
    let green = 0;
    let blue = 0;
    if (hueSection < 1) {
      red = chroma;
      green = secondary;
    } else if (hueSection < 2) {
      red = secondary;
      green = chroma;
    } else if (hueSection < 3) {
      green = chroma;
      blue = secondary;
    } else if (hueSection < 4) {
      green = secondary;
      blue = chroma;
    } else if (hueSection < 5) {
      red = secondary;
      blue = chroma;
    } else {
      red = chroma;
      blue = secondary;
    }
    const match = color.lightness - chroma / 2;
    return {
      red: this.clamp01(red + match),
      green: this.clamp01(green + match),
      blue: this.clamp01(blue + match)
    };
  }

  private mix(
    source: NovelBookCoverRgbColor,
    target: NovelBookCoverRgbColor,
    amount: number
  ): NovelBookCoverRgbColor {
    const ratio = this.clamp01(amount);
    return {
      red: source.red * (1 - ratio) + target.red * ratio,
      green: source.green * (1 - ratio) + target.green * ratio,
      blue: source.blue * (1 - ratio) + target.blue * ratio
    };
  }

  private buildBucketKey(red: number, green: number, blue: number): string {
    return `${Math.floor(red / COVER_BUCKET_STEP)}:${Math.floor(green / COVER_BUCKET_STEP)}:` +
      `${Math.floor(blue / COVER_BUCKET_STEP)}`;
  }

  private toHexColor(color: NovelBookCoverRgbColor): string {
    return `#${this.channelToHex(color.red)}${this.channelToHex(color.green)}${this.channelToHex(color.blue)}`;
  }

  private toArgbColor(color: NovelBookCoverRgbColor, alpha: number): string {
    return `#${this.channelToHex(alpha)}${this.channelToHex(color.red)}` +
      `${this.channelToHex(color.green)}${this.channelToHex(color.blue)}`;
  }

  private channelToHex(value: number): string {
    const hex = Math.round(this.clamp01(value) * 255).toString(16).toUpperCase();
    return hex.length === 1 ? `0${hex}` : hex;
  }

  private clamp01(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }

}

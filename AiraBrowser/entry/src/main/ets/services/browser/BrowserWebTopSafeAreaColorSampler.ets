import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface BrowserWebTopSafeAreaColorSampleRequest {
  uiContext: UIContext;
  componentSnapshotId: string;
  systemTopInsetPx: number;
  contentGapPx: number;
}

export interface BrowserWebTopSafeAreaColorSampleResult {
  color: string;
  reason: string;
  sampleWidth: number;
  sampleHeight: number;
  dominantRatio: number;
  confidence: number;
}

interface BrowserWebTopSafeAreaBucket {
  red: number;
  green: number;
  blue: number;
  count: number;
  luminanceTotal: number;
}

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'WebTopSafeColor';
const SNAPSHOT_SCALE: number = 0.18;
const SAMPLE_WIDTH: number = 48;
const SAMPLE_MIN_HEIGHT: number = 10;
const SAMPLE_MAX_HEIGHT: number = 28;
const SAMPLE_DEFAULT_HEIGHT: number = 18;
const MIN_VISIBLE_PIXEL_COUNT: number = 24;
const MIN_DOMINANT_RATIO: number = 0.34;
const MIN_CONFIDENCE: number = 0.42;
const BUCKET_SIZE: number = 24;

export class BrowserWebTopSafeAreaColorSampler {
  async sample(request: BrowserWebTopSafeAreaColorSampleRequest): Promise<BrowserWebTopSafeAreaColorSampleResult> {
    let snapshot: image.PixelMap | undefined = undefined;
    let sample: image.PixelMap | undefined = undefined;
    try {
      const snapshotId = request.componentSnapshotId.trim();
      if (snapshotId.length <= 0) {
        return this.emptyResult('missing_snapshot_id');
      }
      snapshot = await request.uiContext.getComponentSnapshot().get(snapshotId, {
        scale: SNAPSHOT_SCALE,
        waitUntilRenderFinished: false
      });
      const imageInfo = snapshot.getImageInfoSync();
      const width = Math.max(1, Math.floor(imageInfo.size.width));
      const height = Math.max(1, Math.floor(imageInfo.size.height));
      const targetWidth = Math.min(SAMPLE_WIDTH, width);
      const targetHeight = Math.min(this.resolveSampleHeight(request), height);
      sample = await snapshot.createCroppedAndScaledPixelMap({
        x: 0,
        y: 0,
        size: {
          width: width,
          height: targetHeight
        }
      }, targetWidth / width, targetHeight / Math.max(1, targetHeight), image.AntiAliasingLevel.LOW);
      const buffer = new ArrayBuffer(sample.getPixelBytesNumber());
      await sample.readPixelsToBuffer(buffer);
      return this.resolveColorFromBuffer(buffer, targetWidth, targetHeight);
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'top safe area color sample failed %{public}s', JSON.stringify(error));
      return this.emptyResult('sample_failed');
    } finally {
      if (sample !== undefined && sample !== snapshot) {
        await sample.release().catch((_error: Error) => {});
      }
      if (snapshot !== undefined) {
        await snapshot.release().catch((_error: Error) => {});
      }
    }
  }

  private resolveSampleHeight(request: BrowserWebTopSafeAreaColorSampleRequest): number {
    const requestedHeight = Math.max(0, Math.ceil(request.systemTopInsetPx + request.contentGapPx));
    if (requestedHeight <= 0) {
      return SAMPLE_DEFAULT_HEIGHT;
    }
    return Math.max(SAMPLE_MIN_HEIGHT, Math.min(SAMPLE_MAX_HEIGHT, requestedHeight));
  }

  private resolveColorFromBuffer(
    buffer: ArrayBuffer,
    sampleWidth: number,
    sampleHeight: number
  ): BrowserWebTopSafeAreaColorSampleResult {
    const pixels = new Uint8Array(buffer);
    const buckets: Record<string, BrowserWebTopSafeAreaBucket> = {};
    let visiblePixelCount = 0;
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      const alpha = pixels[index + 3] / 255;
      if (alpha < 0.92) {
        continue;
      }
      const red = pixels[index];
      const green = pixels[index + 1];
      const blue = pixels[index + 2];
      const key = this.buildBucketKey(red, green, blue);
      const bucket = buckets[key] ?? {
        red: 0,
        green: 0,
        blue: 0,
        count: 0,
        luminanceTotal: 0
      };
      bucket.red += red;
      bucket.green += green;
      bucket.blue += blue;
      bucket.count += 1;
      bucket.luminanceTotal += this.resolveLuminance(red, green, blue);
      buckets[key] = bucket;
      visiblePixelCount += 1;
    }
    if (visiblePixelCount < MIN_VISIBLE_PIXEL_COUNT) {
      return this.emptyResult('too_few_pixels', sampleWidth, sampleHeight);
    }
    const dominantBucket = this.resolveDominantBucket(buckets);
    if (dominantBucket === undefined) {
      return this.emptyResult('no_dominant_color', sampleWidth, sampleHeight);
    }
    const dominantRatio = dominantBucket.count / visiblePixelCount;
    const confidence = this.resolveConfidence(dominantBucket, dominantRatio);
    if (dominantRatio < MIN_DOMINANT_RATIO || confidence < MIN_CONFIDENCE) {
      return {
        color: '',
        reason: 'low_confidence',
        sampleWidth: sampleWidth,
        sampleHeight: sampleHeight,
        dominantRatio: dominantRatio,
        confidence: confidence
      };
    }
    return {
      color: this.toHexColor(
        Math.round(dominantBucket.red / dominantBucket.count),
        Math.round(dominantBucket.green / dominantBucket.count),
        Math.round(dominantBucket.blue / dominantBucket.count)
      ),
      reason: 'sampled',
      sampleWidth: sampleWidth,
      sampleHeight: sampleHeight,
      dominantRatio: dominantRatio,
      confidence: confidence
    };
  }

  private resolveDominantBucket(
    buckets: Record<string, BrowserWebTopSafeAreaBucket>
  ): BrowserWebTopSafeAreaBucket | undefined {
    let bestBucket: BrowserWebTopSafeAreaBucket | undefined = undefined;
    Object.keys(buckets).forEach((key: string) => {
      const bucket = buckets[key];
      if (bestBucket === undefined || bucket.count > bestBucket.count) {
        bestBucket = bucket;
      }
    });
    return bestBucket;
  }

  private resolveConfidence(bucket: BrowserWebTopSafeAreaBucket, dominantRatio: number): number {
    const averageLuminance = bucket.luminanceTotal / Math.max(1, bucket.count);
    const edgeLuminancePenalty = averageLuminance < 0.03 || averageLuminance > 0.98 ? 0.08 : 0;
    return Math.max(0, Math.min(1, dominantRatio - edgeLuminancePenalty));
  }

  private buildBucketKey(red: number, green: number, blue: number): string {
    return [
      Math.floor(red / BUCKET_SIZE),
      Math.floor(green / BUCKET_SIZE),
      Math.floor(blue / BUCKET_SIZE)
    ].join(':');
  }

  private resolveLuminance(red: number, green: number, blue: number): number {
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
  }

  private toHexColor(red: number, green: number, blue: number): string {
    return `#${this.toHexChannel(red)}${this.toHexChannel(green)}${this.toHexChannel(blue)}`.toUpperCase();
  }

  private toHexChannel(value: number): string {
    return Math.max(0, Math.min(255, value)).toString(16).padStart(2, '0');
  }

  private emptyResult(
    reason: string,
    sampleWidth: number = 0,
    sampleHeight: number = 0
  ): BrowserWebTopSafeAreaColorSampleResult {
    return {
      color: '',
      reason: reason,
      sampleWidth: sampleWidth,
      sampleHeight: sampleHeight,
      dominantRatio: 0,
      confidence: 0
    };
  }
}

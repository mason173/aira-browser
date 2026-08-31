import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export type BrowserBottomToolbarLabelTone = 'light' | 'dark';

export interface BrowserBottomToolbarLabelContrastRequest {
  uiContext: UIContext;
  componentSnapshotId: string;
  sessionId: string;
  backdropRevision: string;
  currentTone: BrowserBottomToolbarLabelTone;
  expanded: boolean;
  backdropAvailable: boolean;
}

export type BrowserBottomToolbarLabelToneApplier = (tone: BrowserBottomToolbarLabelTone) => void;

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'BottomLabelContrast';
const SNAPSHOT_SCALE: number = 0.12;
const SAMPLE_START_RATIO: number = 0.46;
const MIN_VISIBLE_PIXELS: number = 24;
const WHITE_BLACK_EQUAL_CONTRAST_LUMINANCE: number = 0.179;
const KEEP_LIGHT_TEXT_MAX_LUMINANCE: number = 0.22;
const KEEP_DARK_TEXT_MIN_LUMINANCE: number = 0.14;

export class BrowserBottomToolbarLabelContrastCoordinator {
  private generation: number = 0;
  private activeSessionKey: string = '';
  private samplePending: boolean = false;

  updateExpansion(
    request: BrowserBottomToolbarLabelContrastRequest,
    forceRefresh: boolean,
    applyTone: BrowserBottomToolbarLabelToneApplier
  ): void {
    if (!this.shouldSample(request)) {
      this.endExpansion();
      return;
    }
    const sessionKey = this.buildSessionKey(request);
    if (!forceRefresh) {
      if (this.activeSessionKey === sessionKey && this.samplePending) {
        return;
      }
      if (this.activeSessionKey === sessionKey) {
        return;
      }
    }
    this.startSample(request, applyTone);
  }

  dispose(): void {
    this.endExpansion();
  }

  private endExpansion(): void {
    this.generation += 1;
    this.activeSessionKey = '';
    this.samplePending = false;
  }

  private startSample(
    request: BrowserBottomToolbarLabelContrastRequest,
    applyTone: BrowserBottomToolbarLabelToneApplier
  ): void {
    const sessionKey = this.buildSessionKey(request);
    const generation = ++this.generation;
    this.activeSessionKey = sessionKey;
    this.samplePending = true;
    void this.sampleTone(request).then((tone: BrowserBottomToolbarLabelTone) => {
      if (generation !== this.generation || this.activeSessionKey !== sessionKey) {
        return;
      }
      this.samplePending = false;
      applyTone(tone);
    });
  }

  private async sampleTone(
    request: BrowserBottomToolbarLabelContrastRequest
  ): Promise<BrowserBottomToolbarLabelTone> {
    let snapshot: image.PixelMap | undefined = undefined;
    try {
      if (request.componentSnapshotId.trim().length <= 0) {
        return request.currentTone;
      }
      snapshot = await request.uiContext.getComponentSnapshot().get(request.componentSnapshotId, {
        scale: SNAPSHOT_SCALE,
        waitUntilRenderFinished: false
      });
      const info = snapshot.getImageInfoSync();
      const width = Math.max(1, Math.floor(info.size.width));
      const height = Math.max(1, Math.floor(info.size.height));
      const buffer = new ArrayBuffer(snapshot.getPixelBytesNumber());
      await snapshot.readPixelsToBuffer(buffer);
      return this.resolveToneFromBuffer(
        buffer,
        width,
        height,
        request.currentTone
      );
    } catch (error) {
      hilog.warn(
        LOG_DOMAIN,
        LOG_TAG,
        'label contrast sample failed error=%{public}s',
        JSON.stringify(error)
      );
      return request.currentTone;
    } finally {
      if (snapshot !== undefined) {
        await snapshot.release().catch((_error: Error) => {});
      }
    }
  }

  private resolveToneFromBuffer(
    buffer: ArrayBuffer,
    width: number,
    height: number,
    currentTone: BrowserBottomToolbarLabelTone
  ): BrowserBottomToolbarLabelTone {
    const pixels = new Uint8Array(buffer);
    const startY = Math.max(0, Math.min(height - 1, Math.floor(height * SAMPLE_START_RATIO)));
    let redTotal = 0;
    let greenTotal = 0;
    let blueTotal = 0;
    let alphaTotal = 0;
    let visiblePixels = 0;
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      const pixelIndex = Math.floor(index / 4);
      const y = Math.floor(pixelIndex / width);
      if (y < startY) {
        continue;
      }
      const alpha = pixels[index + 3] / 255;
      if (alpha <= 0.05) {
        continue;
      }
      redTotal += (pixels[index] / 255) * alpha;
      greenTotal += (pixels[index + 1] / 255) * alpha;
      blueTotal += (pixels[index + 2] / 255) * alpha;
      alphaTotal += alpha;
      visiblePixels += 1;
    }
    if (visiblePixels < MIN_VISIBLE_PIXELS || alphaTotal <= 0) {
      return currentTone;
    }
    const red = redTotal / alphaTotal;
    const green = greenTotal / alphaTotal;
    const blue = blueTotal / alphaTotal;
    const luminance = 0.2126 * this.toLinearChannel(red) +
      0.7152 * this.toLinearChannel(green) +
      0.0722 * this.toLinearChannel(blue);
    return this.resolveToneForLuminance(luminance, currentTone);
  }

  private resolveToneForLuminance(
    luminance: number,
    currentTone: BrowserBottomToolbarLabelTone
  ): BrowserBottomToolbarLabelTone {
    if (currentTone === 'light' && luminance <= KEEP_LIGHT_TEXT_MAX_LUMINANCE) {
      return 'light';
    }
    if (currentTone === 'dark' && luminance >= KEEP_DARK_TEXT_MIN_LUMINANCE) {
      return 'dark';
    }
    return luminance < WHITE_BLACK_EQUAL_CONTRAST_LUMINANCE ? 'light' : 'dark';
  }

  private toLinearChannel(channel: number): number {
    const clamped = Math.max(0, Math.min(1, channel));
    if (clamped <= 0.04045) {
      return clamped / 12.92;
    }
    return Math.pow((clamped + 0.055) / 1.055, 2.4);
  }

  private buildSessionKey(request: BrowserBottomToolbarLabelContrastRequest): string {
    return `${request.sessionId}:${request.componentSnapshotId}:${request.backdropRevision}`;
  }

  private shouldSample(request: BrowserBottomToolbarLabelContrastRequest): boolean {
    return request.expanded &&
      request.backdropAvailable &&
      request.sessionId.trim().length > 0 &&
      request.componentSnapshotId.trim().length > 0;
  }
}

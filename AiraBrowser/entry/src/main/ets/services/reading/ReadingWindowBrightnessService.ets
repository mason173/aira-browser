import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ReaderModeBrightnessMode } from '../../common/models/BrowserModels';

export type ReadingWindowBrightnessOwner = 'article' | 'novel';

interface ReadingWindowBrightnessRequest {
  context: common.UIAbilityContext;
  value: number;
}

const READING_WINDOW_BRIGHTNESS_MIN_PERCENT: number = 20;
const READING_WINDOW_BRIGHTNESS_MAX_PERCENT: number = 100;
const FOLLOW_SYSTEM_WINDOW_BRIGHTNESS: number = -1;

export class ReadingWindowBrightnessService {
  private activeOwner: '' | ReadingWindowBrightnessOwner = '';
  private requestedValue: number = FOLLOW_SYSTEM_WINDOW_BRIGHTNESS;
  private pendingRequest?: ReadingWindowBrightnessRequest = undefined;
  private requestRunning: boolean = false;

  apply(
    owner: ReadingWindowBrightnessOwner,
    context: common.UIAbilityContext,
    brightnessMode: ReaderModeBrightnessMode,
    brightnessPercent: number
  ): void {
    const normalizedPercent: number = this.normalizePercent(brightnessPercent);
    const brightness: number = brightnessMode === 'manual'
      ? normalizedPercent / READING_WINDOW_BRIGHTNESS_MAX_PERCENT
      : FOLLOW_SYSTEM_WINDOW_BRIGHTNESS;
    if (this.activeOwner === owner && this.requestedValue === brightness) {
      return;
    }
    this.activeOwner = owner;
    this.requestedValue = brightness;
    this.enqueue(context, brightness);
  }

  release(owner: ReadingWindowBrightnessOwner, context: common.UIAbilityContext): void {
    if (this.activeOwner !== owner) {
      return;
    }
    this.activeOwner = '';
    this.requestedValue = FOLLOW_SYSTEM_WINDOW_BRIGHTNESS;
    this.enqueue(context, FOLLOW_SYSTEM_WINDOW_BRIGHTNESS);
  }

  private enqueue(context: common.UIAbilityContext, value: number): void {
    this.pendingRequest = {
      context: context,
      value: value
    };
    if (!this.requestRunning) {
      void this.flushLatestRequest();
    }
  }

  private async flushLatestRequest(): Promise<void> {
    this.requestRunning = true;
    try {
      while (this.pendingRequest !== undefined) {
        const request: ReadingWindowBrightnessRequest = this.pendingRequest;
        this.pendingRequest = undefined;
        try {
          const mainWindow: window.Window = await window.getLastWindow(request.context);
          await mainWindow.setWindowBrightness(request.value);
        } catch (_error) {
        }
      }
    } finally {
      this.requestRunning = false;
      if (this.pendingRequest !== undefined) {
        void this.flushLatestRequest();
      }
    }
  }

  private normalizePercent(value: number): number {
    if (!Number.isFinite(value)) {
      return READING_WINDOW_BRIGHTNESS_MAX_PERCENT;
    }
    return Math.max(
      READING_WINDOW_BRIGHTNESS_MIN_PERCENT,
      Math.min(READING_WINDOW_BRIGHTNESS_MAX_PERCENT, Math.round(value))
    );
  }
}

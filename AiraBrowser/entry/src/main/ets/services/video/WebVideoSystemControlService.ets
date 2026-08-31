import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { audio } from '@kit.AudioKit';

export type WebVideoSystemControlKind = 'brightness' | 'volume';

export interface WebVideoSystemControlSnapshot {
  kind: WebVideoSystemControlKind;
  value: number;
  available: boolean;
}

interface WebVideoSystemControlSetResult {
  value: number;
  available: boolean;
}

const DEFAULT_BRIGHTNESS_VALUE: number = 0.55;
const DEFAULT_VOLUME_VALUE: number = 0.5;
const MIN_BRIGHTNESS_VALUE: number = 0.02;
const MAX_PERCENT_VALUE: number = 1;

export class WebVideoSystemControlService {
  private brightnessValue: number = DEFAULT_BRIGHTNESS_VALUE;
  private volumeValue: number = DEFAULT_VOLUME_VALUE;

  read(context: common.UIAbilityContext, kind: WebVideoSystemControlKind): WebVideoSystemControlSnapshot {
    if (kind === 'brightness') {
      return this.readBrightness(context);
    }
    return this.readVolume();
  }

  set(context: common.UIAbilityContext, kind: WebVideoSystemControlKind, value: number): WebVideoSystemControlSnapshot {
    const normalizedValue = this.clampPercent(value, kind === 'brightness' ? MIN_BRIGHTNESS_VALUE : 0);
    if (kind === 'brightness') {
      const result = this.setBrightness(context, normalizedValue);
      return {
        kind: kind,
        value: result.value,
        available: result.available
      };
    }
    const volumeSnapshot = this.setVolume(normalizedValue);
    return {
      kind: kind,
      value: volumeSnapshot.value,
      available: volumeSnapshot.available
    };
  }

  private readBrightness(context: common.UIAbilityContext): WebVideoSystemControlSnapshot {
    void this.refreshBrightness(context);
    return {
      kind: 'brightness',
      value: this.brightnessValue,
      available: true
    };
  }

  private setBrightness(context: common.UIAbilityContext, value: number): WebVideoSystemControlSetResult {
    this.brightnessValue = value;
    try {
      window.getLastWindow(context).then((mainWindow) => {
        mainWindow.setWindowBrightness(value).then(() => {
          try {
            const brightness = mainWindow.getWindowProperties().brightness;
            this.brightnessValue = this.clampPercent(
              brightness >= 0 ? brightness : value,
              MIN_BRIGHTNESS_VALUE
            );
          } catch (_propertyError) {
            this.brightnessValue = value;
          }
        }).catch((_error: Error) => {
          void this.refreshBrightness(context);
        });
      }).catch((_error: Error) => {
      });
      return {
        value: value,
        available: true
      };
    } catch (_error) {
      return {
        value: this.brightnessValue,
        available: false
      };
    }
  }

  private readVolume(): WebVideoSystemControlSnapshot {
    void this.refreshVolume();
    return {
      kind: 'volume',
      value: this.volumeValue,
      available: true
    };
  }

  private setVolume(value: number): WebVideoSystemControlSnapshot {
    this.volumeValue = value;
    void this.setVolumeAsync(value);
    return {
      kind: 'volume',
      value: value,
      available: true
    };
  }

  private async refreshBrightness(context: common.UIAbilityContext): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(context);
      const brightness = mainWindow.getWindowProperties().brightness;
      this.brightnessValue = this.clampPercent(
        brightness >= 0 ? brightness : this.brightnessValue,
        MIN_BRIGHTNESS_VALUE
      );
    } catch (_error) {
    }
  }

  private async refreshVolume(): Promise<void> {
    try {
      const audioManager = audio.getAudioManager();
      const current = await audioManager.getVolume(audio.AudioVolumeType.MEDIA);
      const min = await audioManager.getMinVolume(audio.AudioVolumeType.MEDIA);
      const max = await audioManager.getMaxVolume(audio.AudioVolumeType.MEDIA);
      this.volumeValue = this.normalizeVolumeLevel(current, min, max);
    } catch (_error) {
    }
  }

  private async setVolumeAsync(value: number): Promise<void> {
    try {
      const audioManager = audio.getAudioManager();
      const min = await audioManager.getMinVolume(audio.AudioVolumeType.MEDIA);
      const max = await audioManager.getMaxVolume(audio.AudioVolumeType.MEDIA);
      const targetLevel = this.resolveVolumeLevel(value, min, max);
      await audioManager.setVolume(audio.AudioVolumeType.MEDIA, targetLevel);
      this.volumeValue = this.normalizeVolumeLevel(targetLevel, min, max);
    } catch (_error) {
    }
  }

  private resolveVolumeLevel(value: number, min: number, max: number): number {
    if (max <= min) {
      return Math.round(value * 15);
    }
    return Math.round(min + this.clampPercent(value, 0) * (max - min));
  }

  private normalizeVolumeLevel(level: number, min: number, max: number): number {
    if (max <= min) {
      return this.clampPercent(level / 15, 0);
    }
    return this.clampPercent((level - min) / (max - min), 0);
  }

  private clampPercent(value: number, minValue: number): number {
    if (!Number.isFinite(value)) {
      return minValue;
    }
    return Math.max(minValue, Math.min(MAX_PERCENT_VALUE, value));
  }

}

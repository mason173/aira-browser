import { BusinessError } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserExperimentSettings } from '../../common/models/BrowserModels';

const DOMAIN = 0x0000;
const TAG = 'BrowserSmartGrip';
const MOTION_CAPABILITY = 'SystemCapability.MultimodalAwareness.Motion';

export type BrowserSmartGripHand = 'left' | 'right' | 'both' | 'not_held' | 'unknown';

export interface BrowserSmartGripState {
  enabled: boolean;
  supported: boolean;
  hand: BrowserSmartGripHand;
}

export class BrowserSmartGripCoordinator {
  private state: BrowserSmartGripState = {
    enabled: false,
    supported: false,
    hand: 'unknown'
  };
  private listening: boolean = false;
  private onStateChange?: (state: BrowserSmartGripState) => void;
  private readonly holdingHandCallback: Callback<motion.HoldingHandStatus> =
    (status: motion.HoldingHandStatus): void => {
      this.updateHand(this.resolveHand(status));
    };

  createState(): BrowserSmartGripState {
    return this.copyState();
  }

  bind(onStateChange: (state: BrowserSmartGripState) => void): void {
    this.onStateChange = onStateChange;
    this.publish();
  }

  unbind(): void {
    this.stopListening();
    this.onStateChange = undefined;
    this.state = {
      enabled: this.state.enabled,
      supported: this.state.supported,
      hand: 'unknown'
    };
  }

  applyExperimentSettings(settings: BrowserExperimentSettings): void {
    const enabled = settings.smartGripTabsActionsEnabled;
    if (!enabled) {
      this.stopListening();
      this.updateState({
        enabled: false,
        supported: this.isCapabilityAvailable(),
        hand: 'unknown'
      });
      return;
    }
    const supported = this.isCapabilityAvailable();
    this.updateState({
      enabled: true,
      supported: supported,
      hand: supported ? this.state.hand : 'unknown'
    });
    if (supported) {
      this.startListening();
    }
  }

  private startListening(): void {
    if (this.listening) {
      return;
    }
    try {
      motion.on('holdingHandChanged', this.holdingHandCallback);
      this.listening = true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'holdingHandChanged on failed: %{public}d %{public}s', err.code, err.message);
      this.updateState({
        enabled: this.state.enabled,
        supported: false,
        hand: 'unknown'
      });
    }
  }

  private stopListening(): void {
    if (!this.listening) {
      return;
    }
    try {
      motion.off('holdingHandChanged', this.holdingHandCallback);
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'holdingHandChanged off failed: %{public}d %{public}s', err.code, err.message);
    }
    this.listening = false;
  }

  private updateHand(hand: BrowserSmartGripHand): void {
    this.updateState({
      enabled: this.state.enabled,
      supported: this.state.supported,
      hand: hand
    });
  }

  private resolveHand(status: motion.HoldingHandStatus): BrowserSmartGripHand {
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      return 'left';
    }
    if (status === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
      return 'right';
    }
    if (status === motion.HoldingHandStatus.BOTH_HANDS_HELD) {
      return 'both';
    }
    if (status === motion.HoldingHandStatus.NOT_HELD) {
      return 'not_held';
    }
    return 'unknown';
  }

  private isCapabilityAvailable(): boolean {
    try {
      return canIUse(MOTION_CAPABILITY);
    } catch (_error) {
      return false;
    }
  }

  private updateState(next: BrowserSmartGripState): void {
    if (this.state.enabled === next.enabled &&
      this.state.supported === next.supported &&
      this.state.hand === next.hand) {
      return;
    }
    this.state = {
      enabled: next.enabled,
      supported: next.supported,
      hand: next.hand
    };
    this.publish();
  }

  private publish(): void {
    if (this.onStateChange === undefined) {
      return;
    }
    this.onStateChange(this.copyState());
  }

  private copyState(): BrowserSmartGripState {
    return {
      enabled: this.state.enabled,
      supported: this.state.supported,
      hand: this.state.hand
    };
  }
}

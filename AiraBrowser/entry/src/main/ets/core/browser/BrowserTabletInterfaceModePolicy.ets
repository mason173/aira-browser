import {
  BrowserFoldPresentationState,
  BrowserTabletInterfaceMode
} from '../../common/models/BrowserDevicePresentationModels';
import { BrowserDeviceFormFactor } from './BrowserDeviceFormFactorCoordinator';

export interface BrowserTabletInterfaceModePolicyInput {
  detectedFormFactor: BrowserDeviceFormFactor;
  selectedMode: BrowserTabletInterfaceMode;
  pointerAvailable: boolean;
  foldState?: BrowserFoldPresentationState;
}

export interface BrowserTabletInterfaceModePolicyDecision {
  shellFamily: 'phone' | 'large_screen';
  settingVisible: boolean;
  decisionReason: string;
}

export class BrowserTabletInterfaceModePolicy {
  /**
   * Explicit device preference wins; automatic fold state then wins over the
   * legacy pointer-based heuristic for devices that expose fold events.
   */
  resolve(input: BrowserTabletInterfaceModePolicyInput): BrowserTabletInterfaceModePolicyDecision {
    if (input.detectedFormFactor === 'pc' || input.detectedFormFactor === 'two_in_one') {
      return this.decision('large_screen', false, 'desktop-device');
    }
    const explicitDecision = this.resolveExplicitMode(input);
    if (explicitDecision !== undefined) {
      return explicitDecision;
    }
    if (input.foldState === 'expanded') {
      return this.decision('large_screen', true, 'fold-expanded-auto-desktop');
    }
    if (input.foldState === 'folded') {
      return this.decision('phone', true, 'folded-auto-touch');
    }
    if (input.detectedFormFactor === 'phone') {
      return this.decision('phone', true, 'phone-auto-touch');
    }
    if (input.detectedFormFactor === 'tablet') {
      return this.resolvePointerAuto(input, 'tablet');
    }
    return this.resolvePointerAuto(input, 'unknown');
  }

  private resolveExplicitMode(
    input: BrowserTabletInterfaceModePolicyInput
  ): BrowserTabletInterfaceModePolicyDecision | undefined {
    if (input.selectedMode === 'desktop') {
      return this.decision('large_screen', true, `${input.detectedFormFactor}-desktop-override`);
    }
    if (input.selectedMode === 'touch') {
      return this.decision('phone', true, `${input.detectedFormFactor}-touch-override`);
    }
    return undefined;
  }

  private resolvePointerAuto(
    input: BrowserTabletInterfaceModePolicyInput,
    formFactor: BrowserDeviceFormFactor
  ): BrowserTabletInterfaceModePolicyDecision {
    return input.pointerAvailable
      ? this.decision('large_screen', true, `${formFactor}-auto-pointer`)
      : this.decision('phone', true, `${formFactor}-auto-touch`);
  }

  private decision(
    shellFamily: 'phone' | 'large_screen',
    settingVisible: boolean,
    decisionReason: string
  ): BrowserTabletInterfaceModePolicyDecision {
    return {
      shellFamily: shellFamily,
      settingVisible: settingVisible,
      decisionReason: decisionReason
    };
  }
}

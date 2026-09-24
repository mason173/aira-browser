import {
  BrowserFoldPresentationState,
  BrowserTabletInterfaceMode
} from '../../common/models/BrowserDevicePresentationModels';
import { resolveCockpitShellFamily } from './BrowserCockpitWindowSpanPolicy';
import { BrowserDeviceFormFactor } from './BrowserDeviceFormFactorCoordinator';

/**
 * Huawei pocket ("small") foldables that must keep the touch shell when
 * unfolded, identified the way HarmonyOS actually reports a device.
 *
 * Pixel geometry cannot separate these from the large foldables: a pocket
 * foldable's cover screen and a wide book foldable's inner screen land in the
 * same aspect-ratio band, so Pura X (a 6.3" pocket fold, 1.61) sits below Pura
 * X Max (a 7.7" book fold, 1.41) and the 10.2" Mate XT tri-fold (1.43) - any
 * ratio threshold that admits the first also admits the last two. Device
 * identity is the reliable signal, so it is what this policy keys on.
 *
 * Matching uses two independent identifiers because either can be missing:
 * `marketName` is the marketing name and is usually populated but falls back to
 * a generic value on unconfigured builds, and `productModel` is the per-SKU code
 * (`VDE-AL00`) whose leading series token is stable across a model's regional
 * SKUs. A match on either is enough.
 *
 * To cover a future pocket foldable, add its marketing name and series token
 * here. Only Huawei is listed; other vendors keep their previous behavior.
 */
export const SMALL_FOLDABLE_MARKET_NAMES: string[] = [
  'HUAWEI P50 POCKET',
  'HUAWEI POCKET S',
  'HUAWEI POCKET 2',
  'HUAWEI NOVA FLIP',
  'HUAWEI NOVA FLIP S',
  'HUAWEI PURA X'
];

/**
 * Leading series tokens of the small-foldable SKU codes, matched as
 * `<token>-`. `BAL` covers P50 Pocket and Pocket S; `LEM` Pocket 2; `PSD` nova
 * Flip and nova Flip S; `VDE` Pura X.
 */
export const SMALL_FOLDABLE_MODEL_PREFIXES: string[] = ['BAL', 'LEM', 'PSD', 'VDE'];

/**
 * Vendor prefixes to strip before comparing a marketing name. The comparison is
 * exact after stripping, never a substring test: "HUAWEI PURA X" is a prefix of
 * the *large* "HUAWEI PURA X MAX", so a substring match would demote a book
 * foldable by mistake.
 */
const DEVICE_MARKET_NAME_BRAND_PREFIXES: string[] = ['HUAWEI', '华为'];

export interface BrowserTabletInterfaceModePolicyInput {
  detectedFormFactor: BrowserDeviceFormFactor;
  selectedMode: BrowserTabletInterfaceMode;
  pointerAvailable: boolean;
  foldState?: BrowserFoldPresentationState;
  deviceMarketName?: string;
  deviceProductModel?: string;
  windowWidthVp?: number;
}

export interface BrowserTabletInterfaceModePolicyDecision {
  shellFamily: 'phone' | 'large_screen';
  settingVisible: boolean;
  decisionReason: string;
}

export class BrowserTabletInterfaceModePolicy {
  /**
   * Explicit device preference wins; automatic fold state then wins over the
   * legacy pointer-based heuristic for devices that expose fold events. A
   * pocket foldable is exempt from the automatic promotion: unfolding it does
   * not produce a large screen, so its auto mode stays on the touch shell.
   */
  resolve(input: BrowserTabletInterfaceModePolicyInput): BrowserTabletInterfaceModePolicyDecision {
    if (input.detectedFormFactor === 'pc' || input.detectedFormFactor === 'two_in_one') {
      return this.decision('large_screen', false, 'desktop-device');
    }
    // A cockpit stays on the touch shell. Width must not promote it to the PC
    // chrome, and a synced desktop preference must not either.
    if (input.detectedFormFactor === 'car') {
      return this.decision(resolveCockpitShellFamily(), false, 'car-touch-locked');
    }
    const explicitDecision = this.resolveExplicitMode(input);
    if (explicitDecision !== undefined) {
      return explicitDecision;
    }
    if (input.foldState === 'expanded') {
      if (this.isSmallFoldableDevice(input)) {
        return this.decision('phone', true, 'small-fold-expanded-auto-touch');
      }
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

  /**
   * Whether a reported device identity names a known pocket foldable. Public so
   * the interface-mode setting describes the same device the runtime switches.
   */
  isKnownSmallFoldable(deviceMarketName: string, deviceProductModel: string): boolean {
    return this.matchesSmallFoldableMarketName(deviceMarketName) ||
      this.matchesSmallFoldableModelCode(deviceProductModel);
  }

  private isSmallFoldableDevice(input: BrowserTabletInterfaceModePolicyInput): boolean {
    // Phone-class only: a tablet that reports a fold state keeps its own path.
    if (input.detectedFormFactor !== 'phone') {
      return false;
    }
    return this.isKnownSmallFoldable(input.deviceMarketName ?? '', input.deviceProductModel ?? '');
  }

  private matchesSmallFoldableMarketName(deviceMarketName: string): boolean {
    const normalized = this.normalizeMarketName(deviceMarketName);
    if (normalized.length <= 0) {
      return false;
    }
    // Both sides are normalized, so the catalog stays readable with the brand
    // spelled out and a device that omits the brand still matches.
    return SMALL_FOLDABLE_MARKET_NAMES.some((candidate: string): boolean => {
      return this.normalizeMarketName(candidate) === normalized;
    });
  }

  private matchesSmallFoldableModelCode(deviceProductModel: string): boolean {
    const normalized = deviceProductModel.trim().toUpperCase();
    if (normalized.length <= 0) {
      return false;
    }
    return SMALL_FOLDABLE_MODEL_PREFIXES.some((prefix: string): boolean => {
      return normalized.startsWith(`${prefix}-`);
    });
  }

  private normalizeMarketName(deviceMarketName: string): string {
    let normalized = deviceMarketName.trim().toUpperCase().replace(/\s+/g, ' ');
    DEVICE_MARKET_NAME_BRAND_PREFIXES.forEach((brand: string): void => {
      const uppercaseBrand = brand.toUpperCase();
      if (normalized === uppercaseBrand) {
        normalized = '';
        return;
      }
      if (normalized.startsWith(`${uppercaseBrand} `)) {
        normalized = normalized.slice(uppercaseBrand.length + 1).trim();
      }
    });
    return normalized;
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

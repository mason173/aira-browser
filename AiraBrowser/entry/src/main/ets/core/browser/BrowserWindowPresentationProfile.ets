import {
  BrowserDeviceFormFactor,
  BrowserDeviceFormFactorCoordinator,
  BrowserShellEligibility
} from './BrowserDeviceFormFactorCoordinator';
import {
  BrowserFoldPresentationState,
  BrowserTabletInterfaceMode
} from '../../common/models/BrowserDevicePresentationModels';
import {
  BrowserTabletInterfaceModePolicy,
  BrowserTabletInterfaceModePolicyDecision
} from './BrowserTabletInterfaceModePolicy';

export type BrowserShellFamily = 'phone' | 'large_screen';

export interface BrowserWindowPresentationProfileInput {
  platformDeviceType?: string;
  windowWidthVp?: number;
  windowHeightVp?: number;
  pointerAvailable?: boolean;
  tabletInterfaceMode?: BrowserTabletInterfaceMode;
  foldState?: BrowserFoldPresentationState;
}

export interface BrowserShellFamilyAvailability {
  phoneShellAvailable: boolean;
  largeScreenShellAvailable: boolean;
}

export interface BrowserWindowPresentationProfile {
  revision: number;
  shellFamily: BrowserShellFamily;
  uiMode: 'phone_ui' | 'large_screen_ui';
  detectedFormFactor: BrowserDeviceFormFactor;
  huaweiPcUiEligible: boolean;
  windowWidthVp: number;
  windowHeightVp: number;
  phoneShellAvailable: boolean;
  largeScreenShellAvailable: boolean;
  familyLocked: boolean;
  decisionReason: string;
}

/**
 * Converts WindowStage/device facts into the one profile the active browser
 * Session exposes to Shell adapters. The first decision selects a Shell
 * Family. Switchable device revisions may move between Phone and Large-Screen
 * adapters when an explicit interface preference, live pointer availability,
 * or a foldable's stable physical state changes.
 */
export class BrowserWindowPresentationProfileCoordinator {
  private readonly deviceFormFactorCoordinator: BrowserDeviceFormFactorCoordinator =
    new BrowserDeviceFormFactorCoordinator();
  private readonly tabletInterfaceModePolicy: BrowserTabletInterfaceModePolicy =
    new BrowserTabletInterfaceModePolicy();
  private currentProfile?: BrowserWindowPresentationProfile;

  reconcile(
    input: BrowserWindowPresentationProfileInput,
    availability: BrowserShellFamilyAvailability,
    revision: number
  ): BrowserWindowPresentationProfile {
    const normalizedRevision = Number.isFinite(revision) && revision > 0 ? Math.floor(revision) : 1;
    if (this.currentProfile !== undefined && normalizedRevision <= this.currentProfile.revision) {
      return this.currentProfile;
    }

    const eligibility = this.deviceFormFactorCoordinator.resolveShellEligibility({
      platformDeviceType: input.platformDeviceType,
      windowWidthVp: input.windowWidthVp
    });
    const normalizedAvailability: BrowserShellFamilyAvailability = {
      phoneShellAvailable: availability.phoneShellAvailable === true,
      largeScreenShellAvailable: availability.largeScreenShellAvailable === true
    };
    const tabletModeDecision = this.tabletInterfaceModePolicy.resolve({
      detectedFormFactor: eligibility.detectedFormFactor,
      selectedMode: input.tabletInterfaceMode ?? 'auto',
      pointerAvailable: input.pointerAvailable === true,
      foldState: input.foldState ?? 'unknown'
    });
    const family = this.resolveFamily(tabletModeDecision, normalizedAvailability);
    const familyLocked = eligibility.detectedFormFactor === 'pc' || eligibility.detectedFormFactor === 'two_in_one';
    const decisionReason = this.resolveDecisionReason(tabletModeDecision, normalizedAvailability, family);

    const profile: BrowserWindowPresentationProfile = {
      revision: normalizedRevision,
      shellFamily: family,
      uiMode: family === 'large_screen' ? 'large_screen_ui' : 'phone_ui',
      detectedFormFactor: eligibility.detectedFormFactor,
      huaweiPcUiEligible: eligibility.huaweiPcUiEligible,
      windowWidthVp: this.normalizeDimension(input.windowWidthVp),
      windowHeightVp: this.normalizeDimension(input.windowHeightVp),
      phoneShellAvailable: normalizedAvailability.phoneShellAvailable,
      largeScreenShellAvailable: normalizedAvailability.largeScreenShellAvailable,
      familyLocked: familyLocked,
      decisionReason: decisionReason
    };
    this.currentProfile = profile;
    return profile;
  }

  snapshot(): BrowserWindowPresentationProfile | undefined {
    return this.currentProfile === undefined ? undefined : this.copyProfile(this.currentProfile);
  }

  clear(): void {
    this.currentProfile = undefined;
  }

  private resolveFamily(
    decision: BrowserTabletInterfaceModePolicyDecision,
    availability: BrowserShellFamilyAvailability
  ): BrowserShellFamily {
    if (decision.shellFamily === 'large_screen' && availability.largeScreenShellAvailable) {
      return 'large_screen';
    }
    if (decision.shellFamily === 'phone' && availability.phoneShellAvailable) {
      return 'phone';
    }
    return availability.phoneShellAvailable ? 'phone' : 'large_screen';
  }

  private resolveDecisionReason(
    decision: BrowserTabletInterfaceModePolicyDecision,
    availability: BrowserShellFamilyAvailability,
    family: BrowserShellFamily
  ): string {
    if (family === decision.shellFamily) {
      return decision.decisionReason;
    }
    if (decision.shellFamily === 'large_screen' && !availability.largeScreenShellAvailable) {
      return `${decision.decisionReason}:large-screen-adapter-unavailable`;
    }
    if (!availability.phoneShellAvailable) {
      return `${decision.decisionReason}:phone-adapter-unavailable`;
    }
    return decision.decisionReason;
  }

  private normalizeDimension(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.max(1, Math.round(value));
  }

  private copyProfile(profile: BrowserWindowPresentationProfile): BrowserWindowPresentationProfile {
    return {
      revision: profile.revision,
      shellFamily: profile.shellFamily,
      uiMode: profile.uiMode,
      detectedFormFactor: profile.detectedFormFactor,
      huaweiPcUiEligible: profile.huaweiPcUiEligible,
      windowWidthVp: profile.windowWidthVp,
      windowHeightVp: profile.windowHeightVp,
      phoneShellAvailable: profile.phoneShellAvailable,
      largeScreenShellAvailable: profile.largeScreenShellAvailable,
      familyLocked: profile.familyLocked,
      decisionReason: profile.decisionReason
    };
  }
}

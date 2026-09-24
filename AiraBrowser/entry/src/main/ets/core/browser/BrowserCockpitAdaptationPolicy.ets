import { BrowserDeviceFormFactor } from './BrowserDeviceFormFactorCoordinator';
import {
  COCKPIT_MIN_HIT_TARGET_VP,
  BrowserCockpitWindowSpan,
  resolveCockpitWindowSpan
} from './BrowserCockpitWindowSpanPolicy';

/**
 * Cockpit-only treatments. Identity comes from BrowserDeviceFormFactorCoordinator:
 * platform device type `car` or `cockpit` is `'car'`. Window width never qualifies
 * a phone, and never turns a cockpit into the PC shell.
 *
 * The seat guides require floating controls to clear the system dock. They do not
 * publish a dock height. On the HarmonyOS car emulator the app window is immersive,
 * 3402x1620 at density 2.7. Two different bottom windows overlap it:
 * Gesture2dBottomBar is the invisible hit rect, [0, 1361, 3401, 259], 96vp.
 * ToolBar20 is the visible button row, [0, 1490, 3401, 129], 48vp.
 * Clearing the gesture rect leaves the floating bar a full button-row above the
 * buttons. The floor is the visible toolbar. The existing 25vp floating gap stays
 * above that floor and is not part of this lift. A reported avoid area shorter
 * than the floor cannot drop the bar back into the buttons.
 *
 * The same emulator's visible StatusBar is [0, 0, 3401, 129], also 48vp.
 * Gesture2dTopBar is only 96px, 36vp, and sits inside that status bar, so it is
 * not a safe top floor. Docs do not publish a status-bar height; they require
 * TYPE_SYSTEM topRect, and a zero report must not leave controls in the bar.
 */
export const COCKPIT_UNREPORTED_BOTTOM_DOCK_VP: number = 48;
export const COCKPIT_UNREPORTED_TOP_STATUS_BAR_VP: number = 48;

export interface BrowserCockpitAdaptationInput {
  detectedFormFactor: BrowserDeviceFormFactor;
  windowWidthVp?: number;
  reportedBottomAvoidVp: number;
  reportedTopAvoidVp?: number;
}

export interface BrowserCockpitAdaptation {
  active: boolean;
  span: BrowserCockpitWindowSpan;
  contentTopInsetVp: number;
  floatingChromeBottomLiftVp: number;
  hitTargetFloorVp: number;
  enableFloatNavigationAvoidArea: boolean;
  decisionReason: string;
}

export function resolveCockpitAdaptation(input: BrowserCockpitAdaptationInput): BrowserCockpitAdaptation {
  if (input.detectedFormFactor !== 'car') {
    return {
      active: false,
      span: 'full',
      contentTopInsetVp: 0,
      floatingChromeBottomLiftVp: 0,
      hitTargetFloorVp: 0,
      enableFloatNavigationAvoidArea: false,
      decisionReason: 'not-cockpit'
    };
  }
  const reportedBottomAvoidVp = normalizeAvoidInsetVp(input.reportedBottomAvoidVp);
  const reportedTopAvoidVp = normalizeAvoidInsetVp(input.reportedTopAvoidVp ?? 0);
  const reportedCoversDock = reportedBottomAvoidVp >= COCKPIT_UNREPORTED_BOTTOM_DOCK_VP;
  const reportedCoversStatusBar = reportedTopAvoidVp >= COCKPIT_UNREPORTED_TOP_STATUS_BAR_VP;
  return {
    active: true,
    span: resolveCockpitWindowSpan(input.windowWidthVp),
    contentTopInsetVp: reportedCoversStatusBar ?
      reportedTopAvoidVp : COCKPIT_UNREPORTED_TOP_STATUS_BAR_VP,
    floatingChromeBottomLiftVp: reportedCoversDock ?
      reportedBottomAvoidVp : COCKPIT_UNREPORTED_BOTTOM_DOCK_VP,
    hitTargetFloorVp: COCKPIT_MIN_HIT_TARGET_VP,
    enableFloatNavigationAvoidArea: true,
    decisionReason: reportedCoversDock ? 'system-avoid-area' : 'dock-floor'
  };
}

function normalizeAvoidInsetVp(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.ceil(value);
}

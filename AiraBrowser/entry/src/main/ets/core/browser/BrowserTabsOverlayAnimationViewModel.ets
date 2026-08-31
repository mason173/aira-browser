import { curves } from '@kit.ArkUI';
import { BROWSER_TABS_OVERVIEW_IDENTITY_MORPH_OFFSET_Y } from './BrowserTabsOverviewVisualTokens';

export interface BrowserTabsOverviewDirectWebEntryState {
  webEntryProgress: number;
  overlayOpacity: number;
  webLayerOpacity: number;
  homeExitProgress: number;
}

export interface BrowserTabsOverviewHomeRevealExitState {
  homeExitProgress: number;
  backdropProgress: number;
}

export interface BrowserTabsOverviewHomeRevealExitAnimationPlan {
  durationMs: number;
  completionDelayMs: number;
  curve: Curve | string | ICurve;
  targetState: BrowserTabsOverviewHomeRevealExitState;
}

export interface BrowserTabsOverviewIdentityMotionInput {
  coveredByMorph: boolean;
  transitionMounted: boolean;
  direction: 'enter' | 'exit';
  progress: number;
}

export interface BrowserTabsOverviewIdentityMotionState {
  opacity: number;
  translateY: number;
}

const TABS_OVERLAY_ENTRY_START_DELAY_MS: number = 16;
const TABS_OVERLAY_EXIT_DURATION_MS: number = 280;
const TABS_OVERLAY_EXIT_CURVE: Curve = Curve.Friction;
const TABS_OVERLAY_SHARED_SNAPSHOT_ENTER_DURATION_MS: number = 350;
const TABS_OVERLAY_SHARED_SNAPSHOT_EXIT_DURATION_MS: number = 400;
const TABS_OVERLAY_SHARED_SNAPSHOT_ENTER_HANDOFF_DELAY_MS: number = 0;
const TABS_OVERLAY_SHARED_SNAPSHOT_EXIT_HANDOFF_DELAY_MS: number = 120;
const TABS_OVERLAY_WEB_CHROME_SELECTION_REVEAL_DURATION_MS: number = 160;
const TABS_OVERLAY_WEB_CHROME_SELECTION_REVEAL_CURVE: Curve = Curve.FastOutSlowIn;
const TABS_OVERLAY_HOME_REVEAL_DURATION_MS: number = 120;
const TABS_OVERLAY_HOME_REVEAL_SETTLE_GRACE_MS: number = 260;
const TABS_OVERLAY_HOME_REVEAL_CURVE: string = 'cubic-bezier(0.2, 0, 0, 1)';
const TABS_OVERLAY_HOME_REVEAL_EXIT_DURATION_MS: number = 360;
const TABS_OVERLAY_HOME_REVEAL_EXIT_COMPLETION_GRACE_MS: number = 48;
const TABS_OVERLAY_HOME_ENTRY_SPRING_RESPONSE: number = 0.5;
const TABS_OVERLAY_HOME_ENTRY_SIDE_CARD_SPRING_DAMPING: number = 0.86;
const TABS_OVERLAY_HOME_REVEAL_INITIAL_SCALE: number = 1;
const TABS_OVERLAY_BACKDROP_SCALE: number = 1;
const TABS_OVERLAY_BACKDROP_SETTLE_MAX_DURATION_MS: number = 220;
const TABS_OVERLAY_BACKDROP_SETTLE_MIN_DURATION_MS: number = 72;
const TABS_OVERLAY_BACKDROP_ENTRY_DURATION_MS: number = 250;
const TABS_OVERLAY_FLOATING_CARD_ENTRY_DURATION_MS: number = 360;
const TABS_OVERLAY_FLOATING_CARD_COLUMN_DELAY_MS: number = 24;
const TABS_OVERLAY_FLOATING_CARD_ROW_DELAY_MS: number = 6;
const TABS_OVERLAY_FLOATING_CARD_MAX_DELAY_MS: number = 80;
const TABS_OVERLAY_FLOATING_CARD_SPRING_RESPONSE: number = 0.48;
const TABS_OVERLAY_FLOATING_CARD_SPRING_DAMPING: number = 0.74;
const TABS_OVERLAY_IDENTITY_ENTRY_START_PROGRESS: number = 0.55;
const TABS_OVERLAY_IDENTITY_EXIT_END_PROGRESS: number = 0.3;

export class BrowserTabsOverlayAnimationViewModel {
  buildIdentityMotionState(
    input: BrowserTabsOverviewIdentityMotionInput
  ): BrowserTabsOverviewIdentityMotionState {
    if (!input.coveredByMorph || !input.transitionMounted) {
      return { opacity: 1, translateY: 0 };
    }
    const progress = Math.max(0, Math.min(1, input.progress));
    if (input.direction === 'exit') {
      const opacity = 1 - this.normalizeProgress(progress, 0, TABS_OVERLAY_IDENTITY_EXIT_END_PROGRESS);
      return { opacity: opacity, translateY: 0 };
    }
    const revealProgress = this.normalizeProgress(
      progress,
      TABS_OVERLAY_IDENTITY_ENTRY_START_PROGRESS,
      1
    );
    return {
      opacity: revealProgress,
      translateY: BROWSER_TABS_OVERVIEW_IDENTITY_MORPH_OFFSET_Y * (1 - revealProgress)
    };
  }
  buildDirectWebEntryState(): BrowserTabsOverviewDirectWebEntryState {
    return {
      webEntryProgress: 0,
      overlayOpacity: 1,
      webLayerOpacity: 1,
      homeExitProgress: 0
    };
  }

  buildHomeRevealExitState(): BrowserTabsOverviewHomeRevealExitState {
    return {
      homeExitProgress: 1,
      backdropProgress: 0
    };
  }

  buildHomeRevealExitAnimationPlan(): BrowserTabsOverviewHomeRevealExitAnimationPlan {
    return {
      durationMs: this.getHomeRevealExitDurationMs(),
      completionDelayMs: this.getHomeRevealExitDurationMs() + TABS_OVERLAY_HOME_REVEAL_EXIT_COMPLETION_GRACE_MS,
      curve: this.getHomeRevealExitCurve(),
      targetState: this.buildHomeRevealExitState()
    };
  }

  getSelectionSheetReleasedOpacity(): number {
    return 0;
  }

  getEntryStartDelayMs(): number {
    return TABS_OVERLAY_ENTRY_START_DELAY_MS;
  }

  getExitDurationMs(): number {
    return TABS_OVERLAY_EXIT_DURATION_MS;
  }

  getExitCurve(): Curve | string {
    return TABS_OVERLAY_EXIT_CURVE;
  }

  getSharedSnapshotEnterDurationMs(): number {
    return TABS_OVERLAY_SHARED_SNAPSHOT_ENTER_DURATION_MS;
  }

  getSharedSnapshotEnterCurve(): Curve | string | ICurve {
    return Curve.Smooth;
  }

  getSharedSnapshotExitDurationMs(): number {
    return TABS_OVERLAY_SHARED_SNAPSHOT_EXIT_DURATION_MS;
  }

  getSharedSnapshotExitCurve(): Curve | string | ICurve {
    return Curve.FastOutSlowIn;
  }

  getSharedSnapshotEnterHandoffDelayMs(): number {
    return TABS_OVERLAY_SHARED_SNAPSHOT_ENTER_HANDOFF_DELAY_MS;
  }

  getSharedSnapshotExitHandoffDelayMs(): number {
    return TABS_OVERLAY_SHARED_SNAPSHOT_EXIT_HANDOFF_DELAY_MS;
  }

  getWebChromeSelectionRevealDurationMs(): number {
    return TABS_OVERLAY_WEB_CHROME_SELECTION_REVEAL_DURATION_MS;
  }

  getWebChromeSelectionRevealCurve(): Curve | string {
    return TABS_OVERLAY_WEB_CHROME_SELECTION_REVEAL_CURVE;
  }

  getHomeRevealDurationMs(): number {
    return TABS_OVERLAY_HOME_REVEAL_DURATION_MS;
  }

  getHomeRevealSettleDelayMs(): number {
    return TABS_OVERLAY_HOME_REVEAL_DURATION_MS + TABS_OVERLAY_HOME_REVEAL_SETTLE_GRACE_MS;
  }

  getHomeRevealExitDurationMs(): number {
    return TABS_OVERLAY_HOME_REVEAL_EXIT_DURATION_MS;
  }

  getHomeRevealExitCurve(): Curve | string | ICurve {
    return TABS_OVERLAY_HOME_REVEAL_CURVE;
  }

  getFloatingCardEntryDurationMs(): number {
    return TABS_OVERLAY_FLOATING_CARD_ENTRY_DURATION_MS;
  }

  getFloatingCardMaxDelayMs(): number {
    return TABS_OVERLAY_FLOATING_CARD_MAX_DELAY_MS;
  }

  getFloatingCardEntryCurve(): Curve | string | ICurve {
    return curves.springMotion(
      TABS_OVERLAY_FLOATING_CARD_SPRING_RESPONSE,
      TABS_OVERLAY_FLOATING_CARD_SPRING_DAMPING
    );
  }

  getFloatingCardExitCurve(): Curve | string | ICurve {
    return 'cubic-bezier(0.32, 0, 0.67, 0)';
  }

  resolveFloatingCardDelayMs(index: number, columnCount: number): number {
    const safeColumnCount = Math.max(1, Math.floor(columnCount));
    const safeIndex = Math.max(0, Math.floor(index));
    const column = safeIndex % safeColumnCount;
    const row = Math.floor(safeIndex / safeColumnCount);
    return Math.min(
      TABS_OVERLAY_FLOATING_CARD_MAX_DELAY_MS,
      (column * TABS_OVERLAY_FLOATING_CARD_COLUMN_DELAY_MS) +
        (row * TABS_OVERLAY_FLOATING_CARD_ROW_DELAY_MS)
    );
  }

  getHomeRevealCurve(): Curve | string {
    return TABS_OVERLAY_HOME_REVEAL_CURVE;
  }

  getHomeEntryCurve(): Curve | string | ICurve {
    return TABS_OVERLAY_HOME_REVEAL_CURVE;
  }

  getHomeEntrySideCardCurve(): Curve | string | ICurve {
    return curves.springMotion(
      TABS_OVERLAY_HOME_ENTRY_SPRING_RESPONSE,
      TABS_OVERLAY_HOME_ENTRY_SIDE_CARD_SPRING_DAMPING
    );
  }

  resolveHomeRevealScale(progress: number): number {
    const safeProgress = Math.max(0, Math.min(1, progress));
    return TABS_OVERLAY_HOME_REVEAL_INITIAL_SCALE +
      (1 - TABS_OVERLAY_HOME_REVEAL_INITIAL_SCALE) * safeProgress;
  }

  resolveBackdropScale(progress: number): number {
    const safeProgress = Math.max(0, Math.min(1, progress));
    return 1 - (1 - TABS_OVERLAY_BACKDROP_SCALE) * safeProgress;
  }

  resolveBackdropBlurRadius(_progress: number): number {
    return 0;
  }

  resolveBackdropSettleDurationMs(currentProgress: number, targetProgress: number): number {
    const distance = Math.abs(
      Math.max(0, Math.min(1, targetProgress)) - Math.max(0, Math.min(1, currentProgress))
    );
    if (distance <= 0.001) {
      return 0;
    }
    return Math.max(
      TABS_OVERLAY_BACKDROP_SETTLE_MIN_DURATION_MS,
      Math.round(TABS_OVERLAY_BACKDROP_SETTLE_MAX_DURATION_MS * distance)
    );
  }

  resolveBackdropEntryDurationMs(currentProgress: number, targetProgress: number): number {
    const distance = Math.abs(
      Math.max(0, Math.min(1, targetProgress)) - Math.max(0, Math.min(1, currentProgress))
    );
    if (distance <= 0.001) {
      return 0;
    }
    return Math.round(TABS_OVERLAY_BACKDROP_ENTRY_DURATION_MS * distance);
  }

  private normalizeProgress(value: number, start: number, end: number): number {
    if (end <= start) {
      return value >= end ? 1 : 0;
    }
    return Math.max(0, Math.min(1, (value - start) / (end - start)));
  }

}

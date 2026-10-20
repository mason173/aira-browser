import { resolveBrowserTabSurfaceHandoffDelayMs } from './BrowserTabSurfaceHandoffPolicy';
import { curves } from '@kit.ArkUI';
import { BROWSER_TABS_OVERVIEW_IDENTITY_MORPH_OFFSET_Y } from './BrowserTabsOverviewVisualTokens';
import { BrowserTabsOverviewSnapshotMotion } from './tabsOverview/BrowserTabsOverviewStyleEntryPolicy';

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

export interface BrowserTabsOverviewSnapshotMotionPlan {
  durationMs: number;
  curve: Curve | string | ICurve;
  handoffDelayMs: number;
}

const TABS_OVERLAY_ENTRY_START_DELAY_MS: number = 16;
const TABS_OVERLAY_EXIT_DURATION_MS: number = 280;
const TABS_OVERLAY_EXIT_CURVE: Curve = Curve.Friction;
const TABS_OVERLAY_SHARED_SNAPSHOT_ENTER_DURATION_MS: number = 350;
const TABS_OVERLAY_SHARED_SNAPSHOT_EXIT_DURATION_MS: number = 400;
const TABS_OVERLAY_SHARED_SNAPSHOT_ENTER_HANDOFF_DELAY_MS: number = 0;
// List mode clips a stationary page down to the row. Ease-out, no spring: a bounce would
// move the window past the row and then back, which reads as the picture shifting.
const TABS_OVERLAY_LIST_CLIP_DURATION_MS: number = 340;
const TABS_OVERLAY_LIST_CLIP_CURVE: string = 'cubic-bezier(0.22, 1, 0.36, 1)';
// Returning to the page should feel quicker than the open shrink.
const TABS_OVERLAY_LIST_EXIT_DURATION_MS: number = 280;
const TABS_OVERLAY_LIST_EXIT_CURVE: string = 'cubic-bezier(0.2, 0, 0, 1)';
const TABS_OVERLAY_LIST_EXIT_HANDOFF_DELAY_MS: number = 48;
// Entry waits out the icon, title and close fade. Unmounting earlier paints them at full opacity.
const TABS_OVERLAY_LIST_ENTRY_HANDOFF_DELAY_MS: number = 240;
// Start the title as soon as the window has landed, not after a long hold.
const TABS_OVERLAY_LIST_ENTRY_CHROME_REVEAL_DELAY_MS: number = 48;
const TABS_OVERLAY_LIST_ENTRY_CROSSFADE_START_PROGRESS: number = 1;
const TABS_OVERLAY_LIST_ENTRY_DISSOLVE_DURATION_MS: number = 140;
const TABS_OVERLAY_LIST_ENTRY_DISSOLVE_CURVE: string = 'cubic-bezier(0.2, 0, 0, 1)';
const TABS_OVERLAY_LIST_ENTRY_IMAGE_BLUR: number = 0;
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

  /**
   * Timing for the active style's snapshot motion.
   *
   * Callers pass the motion from the style entry profile. They do not re-check the style name,
   * so list clip timing cannot be copied onto a card shrink by the next edit.
   */
  resolveSharedSnapshotMotion(
    motion: BrowserTabsOverviewSnapshotMotion,
    direction: 'enter' | 'exit'
  ): BrowserTabsOverviewSnapshotMotionPlan {
    if (motion === 'clip') {
      return direction === 'enter' ? {
        durationMs: this.getListEntryDurationMs(),
        curve: this.getListEntryCurve(),
        handoffDelayMs: this.getListEntryHandoffDelayMs()
      } : {
        durationMs: this.getListExitDurationMs(),
        curve: this.getListExitCurve(),
        handoffDelayMs: this.getListExitHandoffDelayMs()
      };
    }
    return direction === 'enter' ? {
      durationMs: this.getSharedSnapshotEnterDurationMs(),
      curve: this.getSharedSnapshotEnterCurve(),
      handoffDelayMs: this.getSharedSnapshotEnterHandoffDelayMs()
    } : {
      durationMs: this.getSharedSnapshotExitDurationMs(),
      curve: this.getSharedSnapshotExitCurve(),
      handoffDelayMs: this.getSharedSnapshotExitHandoffDelayMs()
    };
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

  getListEntryDurationMs(): number {
    return TABS_OVERLAY_LIST_CLIP_DURATION_MS;
  }

  getListEntryCurve(): string {
    return TABS_OVERLAY_LIST_CLIP_CURVE;
  }

  getListEntryHandoffDelayMs(): number {
    return TABS_OVERLAY_LIST_ENTRY_HANDOFF_DELAY_MS;
  }

  getListExitDurationMs(): number {
    return TABS_OVERLAY_LIST_EXIT_DURATION_MS;
  }

  getListExitCurve(): string {
    return TABS_OVERLAY_LIST_EXIT_CURVE;
  }

  getListExitHandoffDelayMs(): number {
    return TABS_OVERLAY_LIST_EXIT_HANDOFF_DELAY_MS;
  }

  getListEntryCrossfadeStartProgress(): number {
    return TABS_OVERLAY_LIST_ENTRY_CROSSFADE_START_PROGRESS;
  }

  getListEntryChromeRevealDelayMs(): number {
    return TABS_OVERLAY_LIST_ENTRY_CHROME_REVEAL_DELAY_MS;
  }

  getListEntryDissolveDurationMs(): number {
    return TABS_OVERLAY_LIST_ENTRY_DISSOLVE_DURATION_MS;
  }

  getListEntryDissolveCurve(): string {
    return TABS_OVERLAY_LIST_ENTRY_DISSOLVE_CURVE;
  }

  getListEntryImageBlur(): number {
    return TABS_OVERLAY_LIST_ENTRY_IMAGE_BLUR;
  }

  getSharedSnapshotExitHandoffDelayMs(): number {
    return resolveBrowserTabSurfaceHandoffDelayMs();
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

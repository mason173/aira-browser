export interface BrowserScrollPerformanceState {
  activeUntil: number;
  lastActivatedAt: number;
}

export type BrowserScrollDeferredTaskKind =
  'page_chrome_theme_probe' |
  'page_favicon_visual_update' |
  'page_navigation_state_update' |
  'page_progress_visual_update' |
  'page_restorable_navigation_probe' |
  'page_session_scroll_state_sync' |
  'page_title_visual_update' |
  'page_tracking_protection_status_update' |
  'page_translation_offer_probe' |
  'page_session_snapshot';

export class BrowserScrollPerformanceCoordinator {
  createState(): BrowserScrollPerformanceState {
    return {
      activeUntil: 0,
      lastActivatedAt: 0
    };
  }

  activate(
    state: BrowserScrollPerformanceState,
    quietWindowMs: number,
    now: number = Date.now()
  ): BrowserScrollPerformanceState {
    const normalizedWindowMs = Math.max(0, Math.floor(quietWindowMs));
    return {
      activeUntil: now + normalizedWindowMs,
      lastActivatedAt: now
    };
  }

  activateForMove(
    state: BrowserScrollPerformanceState,
    quietWindowMs: number,
    moveRefreshIntervalMs: number,
    now: number = Date.now()
  ): BrowserScrollPerformanceState {
    const normalizedRefreshIntervalMs = Math.max(0, Math.floor(moveRefreshIntervalMs));
    if (now - Math.max(0, state.lastActivatedAt) < normalizedRefreshIntervalMs) {
      return state;
    }
    return this.activate(state, quietWindowMs, now);
  }

  getQuietDelayMs(
    state: BrowserScrollPerformanceState,
    baseDelayMs: number,
    now: number = Date.now()
  ): number {
    const quietDelayMs = Math.max(0, Math.floor(state.activeUntil - now));
    return Math.max(Math.max(0, Math.floor(baseDelayMs)), quietDelayMs);
  }

  isQuiet(state: BrowserScrollPerformanceState, now: number = Date.now()): boolean {
    return now >= state.activeUntil;
  }

  shouldDeferTask(
    state: BrowserScrollPerformanceState,
    _kind: BrowserScrollDeferredTaskKind,
    now: number = Date.now()
  ): boolean {
    return !this.isQuiet(state, now);
  }
}

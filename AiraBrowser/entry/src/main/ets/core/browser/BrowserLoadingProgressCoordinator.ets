export interface BrowserLoadingProgressState {
  realProgress: number;
  displayProgress: number;
  isLoading: boolean;
  startedAt: number;
  lastUpdatedAt: number;
  completionPending: boolean;
  visualState: BrowserLoadingProgressVisualState;
}

export type BrowserLoadingProgressVisualState = 'idle' | 'loading' | 'completing' | 'complete' | 'error';

export interface BrowserLoadingProgressHost {
  getLoadingProgressState: () => BrowserLoadingProgressState;
  applyLoadingProgressState: (state: BrowserLoadingProgressState) => void;
}

export interface BrowserLoadingProgressCoordinatorOptions {
  terminalHoldMs: number;
}

const ESTIMATED_PROGRESS_START: number = 10;
const ESTIMATED_PROGRESS_CAP: number = 90;
const ESTIMATED_PROGRESS_TICK_MS: number = 50;
const ESTIMATED_PROGRESS_TIME_CONSTANT_MS: number = 1500;
const HUAWEI_TERMINAL_CLEAR_MS: number = 100;
const DOWNLOAD_HANDOFF_COMPLETE_DELAY_MS: number = 80;

export class BrowserLoadingProgressCoordinator {
  private visualTimer: number = -1;
  private terminalClearTimer: number = -1;
  private downloadHandoffTimer: number = -1;
  private generation: number = 0;
  private navigationIntentAwaitingPageBegin: boolean = false;
  private readonly terminalHoldMs: number;

  constructor(options?: BrowserLoadingProgressCoordinatorOptions) {
    this.terminalHoldMs = options?.terminalHoldMs ?? HUAWEI_TERMINAL_CLEAR_MS;
  }

  createState(): BrowserLoadingProgressState {
    return this.createIdleState();
  }

  createStateFromProgress(
    progress: number,
    isLoading: boolean,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const clampedProgress = this.clampProgress(progress);
    if (!isLoading || clampedProgress <= 0 || clampedProgress >= 100) {
      return this.createIdleState(now);
    }
    return this.createLoadingState(
      clampedProgress,
      Math.max(ESTIMATED_PROGRESS_START, clampedProgress),
      now,
      now
    );
  }

  createStateFromProgressAndSchedule(
    progress: number,
    isLoading: boolean,
    host: BrowserLoadingProgressHost,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    this.cancelTimers();
    this.generation += 1;
    const nextState = this.createStateFromProgress(progress, isLoading, now);
    this.applyStateAndSchedule(nextState, host);
    return nextState;
  }

  beginLoad(isDifferentDocument: boolean, now: number = Date.now()): BrowserLoadingProgressState {
    this.cancelTimers();
    this.generation += 1;
    if (!isDifferentDocument) {
      return this.createIdleState(now);
    }
    return this.createLoadingState(0, ESTIMATED_PROGRESS_START, now, now);
  }

  beginLoadAndSchedule(
    isDifferentDocument: boolean,
    host: BrowserLoadingProgressHost,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    if (isDifferentDocument && this.navigationIntentAwaitingPageBegin) {
      this.navigationIntentAwaitingPageBegin = false;
      const currentState = host.getLoadingProgressState();
      if (currentState.isLoading && currentState.visualState === 'loading') {
        return currentState;
      }
    }
    const nextState = this.beginLoad(isDifferentDocument, now);
    this.applyStateAndSchedule(nextState, host);
    return nextState;
  }

  applyRealProgress(
    state: BrowserLoadingProgressState,
    progress: number,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const realProgress = this.clampProgress(progress);
    if (this.shouldIgnoreLateProgress(state, realProgress)) {
      return state;
    }

    const startedAt = state.isLoading && state.startedAt > 0 ? state.startedAt : now;
    if (realProgress >= 100) {
      return this.finishLoad(state, now);
    }

    const currentDisplayProgress = state.isLoading
      ? Math.min(100, Math.max(0, state.displayProgress))
      : 0;
    const estimatedProgress = this.resolveEstimatedProgress(startedAt, now);
    const displayProgress = Math.max(currentDisplayProgress, estimatedProgress, realProgress);
    return this.createLoadingState(
      realProgress,
      Math.min(99, displayProgress),
      startedAt,
      now
    );
  }

  applyRealProgressAndSchedule(
    progress: number,
    host: BrowserLoadingProgressHost,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const nextState = this.applyRealProgress(host.getLoadingProgressState(), progress, now);
    this.applyStateAndSchedule(nextState, host);
    return nextState;
  }

  beginNavigationIntent(
    _state: BrowserLoadingProgressState,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const nextState = this.beginLoad(true, now);
    this.navigationIntentAwaitingPageBegin = true;
    return nextState;
  }

  beginNavigationIntentAndSchedule(
    host: BrowserLoadingProgressHost,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const nextState = this.beginNavigationIntent(host.getLoadingProgressState(), now);
    this.applyStateAndSchedule(nextState, host);
    return nextState;
  }

  pulseDownloadHandoffAndSchedule(
    host: BrowserLoadingProgressHost,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const nextState = this.beginNavigationIntentAndSchedule(host, now);
    const timerGeneration = this.generation;
    this.downloadHandoffTimer = setTimeout(() => {
      this.downloadHandoffTimer = -1;
      if (timerGeneration !== this.generation) {
        return;
      }
      this.finishLoadAndSchedule(host);
    }, DOWNLOAD_HANDOFF_COMPLETE_DELAY_MS);
    return nextState;
  }

  finishLoad(state: BrowserLoadingProgressState, now: number = Date.now()): BrowserLoadingProgressState {
    const startedAt = state.startedAt > 0 ? state.startedAt : now;
    return {
      realProgress: 100,
      displayProgress: 100,
      isLoading: true,
      startedAt: startedAt,
      lastUpdatedAt: now,
      completionPending: true,
      visualState: 'complete'
    };
  }

  finishLoadAndSchedule(host: BrowserLoadingProgressHost, now: number = Date.now()): BrowserLoadingProgressState {
    this.navigationIntentAwaitingPageBegin = false;
    this.cancelVisualTick();
    const nextState = this.finishLoad(host.getLoadingProgressState(), now);
    host.applyLoadingProgressState(nextState);
    this.scheduleTerminalClearIfNeeded(host);
    return nextState;
  }

  advanceVisualProgress(
    state: BrowserLoadingProgressState,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    if (!this.shouldScheduleVisualTick(state)) {
      return state;
    }
    const nextDisplayProgress = Math.max(
      state.displayProgress,
      state.realProgress,
      this.resolveEstimatedProgress(state.startedAt, now)
    );
    return this.createLoadingState(
      state.realProgress,
      nextDisplayProgress,
      state.startedAt > 0 ? state.startedAt : now,
      now
    );
  }

  applyError(state: BrowserLoadingProgressState, now: number = Date.now()): BrowserLoadingProgressState {
    return {
      realProgress: 0,
      displayProgress: Math.max(ESTIMATED_PROGRESS_START, state.displayProgress),
      isLoading: true,
      startedAt: state.startedAt > 0 ? state.startedAt : now,
      lastUpdatedAt: now,
      completionPending: true,
      visualState: 'error'
    };
  }

  applyErrorAndSchedule(host: BrowserLoadingProgressHost, now: number = Date.now()): BrowserLoadingProgressState {
    this.navigationIntentAwaitingPageBegin = false;
    this.cancelVisualTick();
    this.cancelTerminalClear();
    this.cancelDownloadHandoff();
    this.generation += 1;
    const nextState = this.applyError(host.getLoadingProgressState(), now);
    host.applyLoadingProgressState(nextState);
    this.scheduleTerminalClearIfNeeded(host);
    return nextState;
  }

  resetForNonWebSurface(now: number = Date.now()): BrowserLoadingProgressState {
    this.cancelTimers();
    this.generation += 1;
    return this.createIdleState(now);
  }

  resetForNonWebSurfaceAndSchedule(
    host: BrowserLoadingProgressHost,
    now: number = Date.now()
  ): BrowserLoadingProgressState {
    const nextState = this.resetForNonWebSurface(now);
    host.applyLoadingProgressState(nextState);
    return nextState;
  }

  clearTerminalVisualState(state: BrowserLoadingProgressState, now: number = Date.now()): BrowserLoadingProgressState {
    if (state.visualState !== 'complete' && state.visualState !== 'error') {
      return state;
    }
    return this.createIdleState(now);
  }

  shouldScheduleVisualTick(state: BrowserLoadingProgressState): boolean {
    return state.isLoading &&
      state.visualState === 'loading' &&
      state.displayProgress < ESTIMATED_PROGRESS_CAP;
  }

  getNextVisualTickDelayMs(_state: BrowserLoadingProgressState): number {
    return ESTIMATED_PROGRESS_TICK_MS;
  }

  shouldShowVisualState(state: BrowserLoadingProgressState): boolean {
    return state.isLoading && state.displayProgress > 0 && state.displayProgress <= 100;
  }

  cancelTimers(): void {
    this.navigationIntentAwaitingPageBegin = false;
    this.cancelVisualTick();
    this.cancelTerminalClear();
    this.cancelDownloadHandoff();
  }

  private applyStateAndSchedule(
    state: BrowserLoadingProgressState,
    host: BrowserLoadingProgressHost
  ): void {
    host.applyLoadingProgressState(state);
    this.scheduleVisualTickIfNeeded(host);
    this.scheduleTerminalClearIfNeeded(host);
  }

  private scheduleVisualTickIfNeeded(host: BrowserLoadingProgressHost): void {
    this.cancelVisualTick();
    const currentState = host.getLoadingProgressState();
    if (!this.shouldScheduleVisualTick(currentState)) {
      return;
    }
    const timerGeneration = this.generation;
    this.visualTimer = setTimeout(() => {
      this.visualTimer = -1;
      if (timerGeneration !== this.generation) {
        return;
      }
      const previousState = host.getLoadingProgressState();
      const nextState = this.advanceVisualProgress(previousState);
      host.applyLoadingProgressState(nextState);
      this.scheduleVisualTickIfNeeded(host);
    }, this.getNextVisualTickDelayMs(currentState));
  }

  private cancelVisualTick(): void {
    if (this.visualTimer >= 0) {
      clearTimeout(this.visualTimer);
      this.visualTimer = -1;
    }
  }

  private scheduleTerminalClearIfNeeded(host: BrowserLoadingProgressHost): void {
    const currentState = host.getLoadingProgressState();
    if (currentState.visualState !== 'complete' && currentState.visualState !== 'error') {
      this.cancelTerminalClear();
      return;
    }
    if (this.terminalClearTimer >= 0) {
      return;
    }
    const timerGeneration = this.generation;
    this.terminalClearTimer = setTimeout(() => {
      this.terminalClearTimer = -1;
      if (timerGeneration !== this.generation) {
        return;
      }
      host.applyLoadingProgressState(this.clearTerminalVisualState(host.getLoadingProgressState()));
    }, this.terminalHoldMs);
  }

  private cancelTerminalClear(): void {
    if (this.terminalClearTimer >= 0) {
      clearTimeout(this.terminalClearTimer);
      this.terminalClearTimer = -1;
    }
  }

  private cancelDownloadHandoff(): void {
    if (this.downloadHandoffTimer >= 0) {
      clearTimeout(this.downloadHandoffTimer);
      this.downloadHandoffTimer = -1;
    }
  }

  private createLoadingState(
    realProgress: number,
    displayProgress: number,
    startedAt: number,
    now: number
  ): BrowserLoadingProgressState {
    return {
      realProgress: this.clampProgress(realProgress),
      displayProgress: this.clampProgress(displayProgress),
      isLoading: true,
      startedAt: startedAt,
      lastUpdatedAt: now,
      completionPending: false,
      visualState: 'loading'
    };
  }

  private createIdleState(now: number = Date.now()): BrowserLoadingProgressState {
    return {
      realProgress: 0,
      displayProgress: 0,
      isLoading: false,
      startedAt: 0,
      lastUpdatedAt: now,
      completionPending: false,
      visualState: 'idle'
    };
  }

  private shouldIgnoreLateProgress(state: BrowserLoadingProgressState, progress: number): boolean {
    if (state.visualState !== 'complete' && state.visualState !== 'error') {
      return false;
    }
    return progress < 100;
  }

  private resolveEstimatedProgress(startedAt: number, now: number): number {
    const elapsedMs = Math.max(0, now - startedAt);
    const estimatedProgress = ESTIMATED_PROGRESS_START +
      (ESTIMATED_PROGRESS_CAP - ESTIMATED_PROGRESS_START) *
      (1 - Math.exp(-elapsedMs / ESTIMATED_PROGRESS_TIME_CONSTANT_MS));
    return Math.min(ESTIMATED_PROGRESS_CAP, Math.max(ESTIMATED_PROGRESS_START, Math.round(estimatedProgress)));
  }

  private clampProgress(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round(progress)));
  }
}

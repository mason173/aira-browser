import { MediaDeepProbePlan } from '../../../services/media/MediaProbePolicyService';

const DEEP_PROBE_IN_FLIGHT_RETRY_MS: number = 120;

export interface BrowserMediaDeepProbeScheduleInput {
  tabId: string;
  url: string;
  pageTitle: string;
  plan: MediaDeepProbePlan;
}

export interface BrowserMediaInteractionQuietTaskInput {
  tabId: string;
  url: string;
  taskKey: string;
  delayMs?: number;
}

export interface BrowserMediaInteractionQuietTaskHost {
  isActiveTab: (tabId: string) => boolean;
  shouldRun: (tabId: string, url: string) => boolean;
  resolveInteractionQuietDelayMs: (tabId: string) => number;
  runTask: (tabId: string, url: string, isCurrent: () => boolean) => Promise<void>;
}

export interface BrowserMediaProbeSchedulerHost {
  isActiveTab: (tabId: string) => boolean;
  shouldRun: (tabId: string, url: string) => boolean;
  resolveInteractionQuietDelayMs: (tabId: string) => number;
  runDeepProbe: (
    tabId: string,
    url: string,
    pageTitle: string,
    isCurrent: () => boolean
  ) => Promise<void>;
}

interface BrowserMediaProbeScheduleState {
  generation: number;
  timerIds: number[];
  startedCount: number;
  inFlightCount: number;
  maxStarts: number;
  maxInFlight: number;
}

interface BrowserMediaInteractionQuietTaskState {
  tabId: string;
  generation: number;
  timerId: number;
}

export class BrowserMediaProbeScheduler {
  private generationByTab: Map<string, number> = new Map();
  private stateByTab: Map<string, BrowserMediaProbeScheduleState> = new Map();
  private quietTaskStateByKey: Map<string, BrowserMediaInteractionQuietTaskState> = new Map();

  cancelTab(tabId: string): void {
    const state = this.stateByTab.get(tabId);
    if (state !== undefined) {
      this.clearTimers(state);
    }
    this.stateByTab.delete(tabId);
    this.clearInteractionQuietTasksForTab(tabId);
    this.bumpGeneration(tabId);
  }

  clearTab(tabId: string): void {
    this.cancelTab(tabId);
    this.generationByTab.delete(tabId);
  }

  scheduleDeepProbes(input: BrowserMediaDeepProbeScheduleInput, host: BrowserMediaProbeSchedulerHost): void {
    this.cancelTab(input.tabId);
    if (!input.plan.enabled || input.plan.delayMsList.length <= 0) {
      return;
    }
    const generation = this.currentGeneration(input.tabId);
    const maxStarts = Math.max(
      0,
      Math.floor(input.plan.budget.maxDeepProbeRunsPerNavigation)
    );
    const maxInFlight = Math.max(
      1,
      Math.floor(input.plan.budget.maxInFlightDeepProbes)
    );
    if (maxStarts <= 0) {
      return;
    }
    const state: BrowserMediaProbeScheduleState = {
      generation: generation,
      timerIds: [],
      startedCount: 0,
      inFlightCount: 0,
      maxStarts: maxStarts,
      maxInFlight: maxInFlight
    };
    this.stateByTab.set(input.tabId, state);
    input.plan.delayMsList.forEach((delayMs: number) => {
      if (state.timerIds.length < maxStarts) {
        this.scheduleOne(input, Math.max(0, Math.floor(delayMs)), state, host);
      }
    });
  }

  scheduleInteractionQuietTask(
    input: BrowserMediaInteractionQuietTaskInput,
    host: BrowserMediaInteractionQuietTaskHost
  ): void {
    const stateKey = this.buildQuietTaskStateKey(input.tabId, input.taskKey);
    this.cancelInteractionQuietTask(stateKey);
    const state: BrowserMediaInteractionQuietTaskState = {
      tabId: input.tabId,
      generation: this.currentGeneration(input.tabId),
      timerId: -1
    };
    this.quietTaskStateByKey.set(stateKey, state);
    this.scheduleInteractionQuietTaskTimer(stateKey, input, state, host, input.delayMs ?? 0);
  }

  private scheduleInteractionQuietTaskTimer(
    stateKey: string,
    input: BrowserMediaInteractionQuietTaskInput,
    state: BrowserMediaInteractionQuietTaskState,
    host: BrowserMediaInteractionQuietTaskHost,
    delayMs: number
  ): void {
    state.timerId = setTimeout(() => {
      const activeState = this.quietTaskStateByKey.get(stateKey);
      if (activeState !== state ||
        this.currentGeneration(input.tabId) !== state.generation) {
        return;
      }
      if (!host.isActiveTab(input.tabId) || !host.shouldRun(input.tabId, input.url)) {
        this.quietTaskStateByKey.delete(stateKey);
        return;
      }
      const quietDelayMs = Math.max(0, Math.floor(host.resolveInteractionQuietDelayMs(input.tabId)));
      if (quietDelayMs > 0) {
        this.scheduleInteractionQuietTaskTimer(stateKey, input, activeState, host, quietDelayMs);
        return;
      }
      activeState.timerId = -1;
      const isCurrent = (): boolean => this.isInteractionQuietTaskCurrent(
        stateKey,
        state
      );
      void host.runTask(input.tabId, input.url, isCurrent)
        .then(() => {
          this.finishInteractionQuietTask(stateKey, state);
        })
        .catch(() => {
          this.finishInteractionQuietTask(stateKey, state);
        });
    }, Math.max(0, Math.floor(delayMs)));
  }

  private scheduleOne(
    input: BrowserMediaDeepProbeScheduleInput,
    delayMs: number,
    state: BrowserMediaProbeScheduleState,
    host: BrowserMediaProbeSchedulerHost
  ): void {
    let timerId = -1;
    timerId = setTimeout(() => {
      this.removeTimer(input.tabId, state.generation, timerId);
      const activeState = this.stateByTab.get(input.tabId);
      if (activeState === undefined || activeState.generation !== state.generation) {
        return;
      }
      if (activeState.startedCount >= activeState.maxStarts) {
        this.clearIdleState(input.tabId, state.generation);
        return;
      }
      if (!host.isActiveTab(input.tabId) || !host.shouldRun(input.tabId, input.url)) {
        this.clearIdleState(input.tabId, state.generation);
        return;
      }
      const quietDelayMs = Math.max(0, Math.floor(host.resolveInteractionQuietDelayMs(input.tabId)));
      if (quietDelayMs > 0) {
        this.scheduleOne(input, quietDelayMs, activeState, host);
        return;
      }
      if (activeState.inFlightCount >= activeState.maxInFlight) {
        this.scheduleOne(input, DEEP_PROBE_IN_FLIGHT_RETRY_MS, activeState, host);
        return;
      }
      activeState.startedCount += 1;
      activeState.inFlightCount += 1;
      const isCurrent = (): boolean => this.isDeepProbeCurrent(input.tabId, state.generation);
      void host.runDeepProbe(input.tabId, input.url, input.pageTitle, isCurrent)
        .then(() => {
          this.finishProbe(input.tabId, state.generation);
        })
        .catch(() => {
          this.finishProbe(input.tabId, state.generation);
        });
    }, delayMs);
    state.timerIds.push(timerId);
  }

  private finishProbe(tabId: string, generation: number): void {
    const state = this.stateByTab.get(tabId);
    if (state === undefined || state.generation !== generation) {
      return;
    }
    state.inFlightCount = Math.max(0, state.inFlightCount - 1);
    if (state.timerIds.length <= 0 && state.inFlightCount <= 0) {
      this.stateByTab.delete(tabId);
    }
  }

  private isDeepProbeCurrent(tabId: string, generation: number): boolean {
    const state = this.stateByTab.get(tabId);
    return state !== undefined && state.generation === generation && this.currentGeneration(tabId) === generation;
  }

  private clearIdleState(tabId: string, generation: number): void {
    const state = this.stateByTab.get(tabId);
    if (state === undefined || state.generation !== generation) {
      return;
    }
    if (state.timerIds.length <= 0 && state.inFlightCount <= 0) {
      this.stateByTab.delete(tabId);
    }
  }

  private removeTimer(tabId: string, generation: number, timerId: number): void {
    const state = this.stateByTab.get(tabId);
    if (state === undefined || state.generation !== generation) {
      return;
    }
    for (let i = state.timerIds.length - 1; i >= 0; i--) {
      if (state.timerIds[i] === timerId) {
        state.timerIds.splice(i, 1);
        return;
      }
    }
  }

  private clearTimers(state: BrowserMediaProbeScheduleState): void {
    for (let i = 0; i < state.timerIds.length; i++) {
      clearTimeout(state.timerIds[i]);
    }
    state.timerIds = [];
  }

  private buildQuietTaskStateKey(tabId: string, taskKey: string): string {
    return tabId + ':' + taskKey;
  }

  private cancelInteractionQuietTask(stateKey: string): void {
    const state = this.quietTaskStateByKey.get(stateKey);
    if (state !== undefined) {
      clearTimeout(state.timerId);
      this.quietTaskStateByKey.delete(stateKey);
    }
  }

  private isInteractionQuietTaskCurrent(
    stateKey: string,
    expectedState: BrowserMediaInteractionQuietTaskState
  ): boolean {
    const state = this.quietTaskStateByKey.get(stateKey);
    return state === expectedState && this.currentGeneration(expectedState.tabId) === expectedState.generation;
  }

  private finishInteractionQuietTask(
    stateKey: string,
    expectedState: BrowserMediaInteractionQuietTaskState
  ): void {
    if (this.isInteractionQuietTaskCurrent(stateKey, expectedState)) {
      this.quietTaskStateByKey.delete(stateKey);
    }
  }

  private clearInteractionQuietTasksForTab(tabId: string): void {
    const entries = Array.from(this.quietTaskStateByKey.entries());
    for (let i = 0; i < entries.length; i++) {
      if (entries[i][1].tabId === tabId) {
        clearTimeout(entries[i][1].timerId);
        this.quietTaskStateByKey.delete(entries[i][0]);
      }
    }
  }

  private currentGeneration(tabId: string): number {
    return this.generationByTab.get(tabId) ?? 0;
  }

  private bumpGeneration(tabId: string): void {
    const current = this.currentGeneration(tabId);
    this.generationByTab.set(tabId, current + 1);
  }
}

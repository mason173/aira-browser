import { resolveBrowserTabSurfaceHandoffDelayMs } from './BrowserTabSurfaceHandoffPolicy';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserAddressBarTabSwipeEvent, BrowserAddressBarTabSwipePolicy } from './BrowserAddressBarTabSwipePolicy';

export type BrowserAddressBarTabSwipeStage = 'idle' | 'dragging' | 'settling' | 'committing' | 'handoff';

export interface BrowserAddressBarTabSwipeState {
  stage: BrowserAddressBarTabSwipeStage;
  offsetX: number;
  width: number;
  direction: number;
  targetTabId: string;
  targetTitle: string;
  targetAddress: string;
  previewOpacity: number;
  reduceMotion: boolean;
  loadingPlaceholder: boolean;
}

export function createIdleAddressBarTabSwipeState(): BrowserAddressBarTabSwipeState {
  // ArkUI removes the cover after this state reaches the child. Keep the retiring node transparent;
  // resetting opacity to 1 here can submit an opaque screenshot frame during removal.
  return { stage: 'idle', offsetX: 0, width: 1, direction: 0, targetTabId: '',
    targetTitle: '', targetAddress: '', previewOpacity: 0, reduceMotion: false, loadingPlaceholder: false };
}

export interface BrowserAddressBarTabSwipeFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  windowId: string;
  enabled: boolean;
  width: number;
  height: number;
}

export interface BrowserAddressBarTabSwipeHost {
  readFacts: () => BrowserAddressBarTabSwipeFacts;
  readReduceMotion: () => boolean;
  publish: (state: BrowserAddressBarTabSwipeState) => void;
  animate: (duration: number, update: () => void, finish: () => void) => void;
  switchToTab: (tabId: string, canApply: () => boolean) => Promise<void>;
  isTargetReady: (tabId: string) => boolean;
  afterFrame: (callback: () => void) => void;
  lockPreview: (tabId: string) => void;
  prepareOutgoingPreview?: () => void;
  unlockPreview: (tabId: string) => void;
}

const PAGE_GAP_VP: number = 12;
// ArkUI can drop a settle animation's onFinish when another animation preempts the property.
// The monitor recovers that gesture and retains the opaque cover while the target is unready.
const SETTLE_STALL_GRACE_MS: number = 900;

/** Owns one reversible gesture. Active tab state changes only after the settle animation. */
export class BrowserAddressBarTabSwipeCoordinator {
  private policy: BrowserAddressBarTabSwipePolicy = new BrowserAddressBarTabSwipePolicy();
  private state: BrowserAddressBarTabSwipeState = createIdleAddressBarTabSwipeState();
  private sessionFacts?: BrowserAddressBarTabSwipeFacts = undefined;
  private previousTab?: BrowserTabState = undefined;
  private nextTab?: BrowserTabState = undefined;
  private generation: number = 0;
  private monitorTimer: number = -1;
  private handoffTimer: number = -1;
  private settleStartedAt: number = 0;
  private settlingCommit: boolean = false;
  private handoffStartedAt: number = 0;
  private waitingForFrames: boolean = false;
  private handoffFrameVersion: number = 0;
  private previewsLocked: boolean = false;
  private visibleSurfaceGenerations: Map<string, number> = new Map<string, number>();
  private knownTabs?: BrowserTabState[] = undefined;

  private readonly host: BrowserAddressBarTabSwipeHost;

  constructor(host: BrowserAddressBarTabSwipeHost) {
    this.host = host;
  }

  handleLoadingStopped(tabId: string): void {
    if ((this.state.stage === 'handoff' || this.state.stage === 'committing') &&
      this.state.targetTabId === tabId && this.host.readFacts().activeTabId === tabId) {
      // Explicit stop is a terminal user action: return control to the existing (possibly partial) document.
      this.cancel();
    }
  }

  noteSurfaceVisible(tabId: string, generation: number): void {
    this.visibleSurfaceGenerations.set(tabId, generation);
  }

  noteDocumentBegin(tabId: string): void {
    this.visibleSurfaceGenerations.delete(tabId);
    if (tabId === this.state.targetTabId) {
      this.invalidateHandoffFrames();
    }
  }

  hasVisibleSurface(tabId: string, generation: number): boolean {
    return this.visibleSurfaceGenerations.get(tabId) === generation;
  }

  canStart(): boolean {
    const facts = this.host.readFacts();
    return this.state.stage === 'idle' && facts.enabled && facts.width > 1 &&
      this.policy.canStart(facts.tabs, facts.activeTabId);
  }

  handle(event: BrowserAddressBarTabSwipeEvent): void {
    if (event.phase === 'start') {
      if (!this.canStart()) {
        return;
      }
      this.begin();
    }
    if (this.state.stage !== 'dragging') {
      return;
    }
    if (!this.isSessionValid(false)) {
      this.cancel();
      return;
    }
    if (event.phase === 'cancel') {
      this.settle(false);
      return;
    }
    this.update(event.offsetX);
    if (event.phase === 'end') {
      this.settle(this.policy.shouldCommit(event.offsetX, event.velocityX, this.state.width,
        this.state.targetTabId.length > 0));
    }
  }

  /** Called on lifecycle/geometry/tab changes; stale animation callbacks become harmless. */
  cancel(): void {
    this.generation += 1;
    if (this.monitorTimer >= 0) {
      clearTimeout(this.monitorTimer);
      this.monitorTimer = -1;
    }
    this.clearHandoffTimer();
    this.releasePreviews();
    this.previousTab = undefined;
    this.nextTab = undefined;
    this.sessionFacts = undefined;
    this.settlingCommit = false;
    this.waitingForFrames = false;
    if (this.state.stage !== 'idle') {
      this.publish(createIdleAddressBarTabSwipeState());
    }
  }

  reconcile(): void {
    const tabs = this.host.readFacts().tabs;
    if (tabs !== this.knownTabs) {
      this.knownTabs = tabs;
      const tabIds = new Set<string>(tabs.map((tab: BrowserTabState): string => tab.id));
      this.visibleSurfaceGenerations.forEach((_generation: number, tabId: string): void => {
        if (!tabIds.has(tabId)) {
          this.visibleSurfaceGenerations.delete(tabId);
        }
      });
    }
    if (this.state.stage !== 'idle' && !this.isSessionValid(
      this.state.stage === 'committing' || this.state.stage === 'handoff')) {
      this.cancel();
    }
  }

  private begin(): void {
    const facts = this.host.readFacts();
    this.generation += 1;
    this.sessionFacts = facts;
    this.previousTab = this.policy.resolveNeighbor(facts.tabs, facts.activeTabId, 1);
    this.nextTab = this.policy.resolveNeighbor(facts.tabs, facts.activeTabId, -1);
    if (this.previousTab !== undefined) {
      this.host.lockPreview(this.previousTab.id);
    }
    if (this.nextTab !== undefined) {
      this.host.lockPreview(this.nextTab.id);
    }
    this.previewsLocked = true;
    this.host.prepareOutgoingPreview?.();
    this.publish({ stage: 'dragging', offsetX: 0, width: facts.width, direction: 0,
      targetTabId: '', targetTitle: '', targetAddress: '', previewOpacity: 1,
      reduceMotion: this.host.readReduceMotion(), loadingPlaceholder: false });
    this.scheduleMonitor(this.generation);
  }

  private update(offsetX: number): void {
    const target = offsetX < 0 ? this.nextTab : offsetX > 0 ? this.previousTab : undefined;
    this.publish({ stage: 'dragging', offsetX: this.policy.resolveOffset(offsetX, this.state.width,
      target !== undefined), width: this.state.width, direction: offsetX < 0 ? -1 : offsetX > 0 ? 1 : 0,
      targetTabId: target?.id ?? '', targetTitle: target?.title ?? '',
      targetAddress: this.resolveAddress(target), previewOpacity: 1, reduceMotion: this.state.reduceMotion,
      loadingPlaceholder: false });
  }

  private settle(commit: boolean): void {
    const run = this.generation;
    const duration = this.policy.resolveSettleDuration(this.state.offsetX, this.state.width,
      commit, this.state.reduceMotion);
    const targetOffset = commit ? this.state.direction * (this.state.width + PAGE_GAP_VP) : 0;
    this.settlingCommit = commit;
    this.settleStartedAt = Date.now();
    this.publish(this.motionState('settling'));
    this.host.animate(duration, () => {
      if (run === this.generation) {
        this.publish(this.motionState(this.state.stage, targetOffset));
      }
    }, () => {
      this.finishSettle(run, commit);
    });
  }

  private finishSettle(run: number, commit: boolean): void {
    if (run !== this.generation || this.state.stage !== 'settling') {
      return;
    }
    this.settlingCommit = false;
    if (!commit || !this.isSessionValid(false)) {
      this.cancel();
      return;
    }
    void this.commit(run);
  }

  private async commit(run: number): Promise<void> {
    const targetTabId = this.state.targetTabId;
    this.publish(this.motionState('committing'));
    try {
      await this.host.switchToTab(targetTabId, (): boolean =>
        run === this.generation && this.isSessionValid(false));
    } catch (_) {
      if (run === this.generation) {
        this.cancel();
      }
      return;
    }
    if (run !== this.generation) {
      return;
    }
    if (!this.isSessionValid(true) || this.host.readFacts().activeTabId !== targetTabId) {
      this.cancel();
      return;
    }
    this.handoffStartedAt = Date.now();
    this.publish(this.motionState('handoff'));
  }

  private scheduleMonitor(run: number): void {
    this.monitorTimer = setTimeout(() => {
      this.monitorTimer = -1;
      if (run !== this.generation) {
        return;
      }
      try {
        this.tickMonitor(run);
      } catch (_error) {
        // A throwing frame host must never stop the monitor chain; the stall guards below still run
        // on the next tick, and the chain is rescheduled outside this try block.
      }
      if (run === this.generation) {
        this.scheduleMonitor(run);
      }
    }, this.state.loadingPlaceholder ? 100 : 32);
  }

  private tickMonitor(run: number): void {
    this.reconcile();
    if (run !== this.generation) {
      return;
    }
    const now = Date.now();
    // Recovery for a dropped onFinish: the animation is far past its duration, so decide from
    // current state instead of leaving the surface frozen mid-transition.
    if (this.state.stage === 'settling' && now - this.settleStartedAt >= SETTLE_STALL_GRACE_MS) {
      this.finishSettle(run, this.settlingCommit);
    }
    if (this.state.stage === 'handoff') {
      const ready = this.host.isTargetReady(this.state.targetTabId);
      if (!ready && this.waitingForFrames) {
        this.invalidateHandoffFrames();
      }
      if (ready && !this.waitingForFrames) {
        this.waitingForFrames = true;
        const frameVersion = ++this.handoffFrameVersion;
        this.host.afterFrame(() => {
          if (!this.isHandoffFrameCurrent(run, frameVersion)) {
            return;
          }
          if (!this.host.isTargetReady(this.state.targetTabId)) {
            this.invalidateHandoffFrames();
            return;
          }
          this.host.afterFrame(() => this.finishHandoffAfterFrames(run, frameVersion));
        });
      } else if (!this.state.loadingPlaceholder && now - this.handoffStartedAt >= 900) {
        // Cold tabs can take arbitrarily long. Replace the cached cover with explicit loading UI;
        // keep it mounted until Web reports visible content, and release the toolbar action lock.
        this.publish(this.motionState('handoff', this.state.offsetX, 1, true));
      }
    }
  }

  private invalidateHandoffFrames(): void {
    this.handoffFrameVersion += 1;
    this.waitingForFrames = false;
    this.clearHandoffTimer();
  }

  private clearHandoffTimer(): void {
    if (this.handoffTimer >= 0) {
      clearTimeout(this.handoffTimer);
      this.handoffTimer = -1;
    }
  }

  private isHandoffFrameCurrent(run: number, frameVersion: number): boolean {
    return run === this.generation && frameVersion === this.handoffFrameVersion &&
      this.state.stage === 'handoff';
  }

  private finishHandoffAfterFrames(run: number, frameVersion: number): void {
    if (!this.isHandoffFrameCurrent(run, frameVersion) || this.handoffTimer >= 0) {
      return;
    }
    if (!this.isSessionValid(true)) {
      this.cancel();
      return;
    }
    if (!this.host.isTargetReady(this.state.targetTabId)) {
      this.invalidateHandoffFrames();
      return;
    }
    // Use the same opaque handoff interval as overview card selection. This replaces the old
    // opacity-animation interval; it does not add another delay or wait for a new screenshot.
    this.handoffTimer = setTimeout(() => {
      if (!this.isHandoffFrameCurrent(run, frameVersion)) {
        return;
      }
      this.handoffTimer = -1;
      if (!this.isSessionValid(true)) {
        this.cancel();
        return;
      }
      if (!this.host.isTargetReady(this.state.targetTabId)) {
        this.invalidateHandoffFrames();
        return;
      }
      // Like the overview's final publish: remove the opaque picture and reveal the already
      // mounted live page together, without blending two separately rendered page surfaces.
      this.cancel();
    }, resolveBrowserTabSurfaceHandoffDelayMs(this.state.reduceMotion));
  }

  private releasePreviews(): void {
    if (!this.previewsLocked) {
      return;
    }
    this.previewsLocked = false;
    if (this.previousTab !== undefined) {
      this.host.unlockPreview(this.previousTab.id);
    }
    if (this.nextTab !== undefined) {
      this.host.unlockPreview(this.nextTab.id);
    }
  }

  private isSessionValid(allowTarget: boolean): boolean {
    const start = this.sessionFacts;
    const facts = this.host.readFacts();
    if (start === undefined || !facts.enabled || facts.windowId !== start.windowId ||
      Math.abs(facts.width - start.width) > 1 || Math.abs(facts.height - start.height) > 1 ||
      (facts.activeTabId !== start.activeTabId && (!allowTarget || facts.activeTabId !== this.state.targetTabId))) {
      return false;
    }
    if (!facts.tabs.some((tab: BrowserTabState) => tab.id === start.activeTabId)) {
      return false;
    }
    if (this.state.targetTabId.length === 0) {
      return true;
    }
    // Re-evaluate the original adjacency and privacy boundary before applying any asynchronous result.
    return this.policy.resolveNeighbor(facts.tabs, start.activeTabId, this.state.direction)?.id ===
      this.state.targetTabId;
  }

  private resolveAddress(tab?: BrowserTabState): string {
    if (tab === undefined) {
      return '';
    }
    const url = tab.url ?? '';
    return url.replace(/^https?:\/\//i, '').split('/')[0] || tab?.title || '标签页';
  }

  private motionState(
    stage: BrowserAddressBarTabSwipeStage,
    offsetX: number = this.state.offsetX,
    previewOpacity: number = this.state.previewOpacity,
    loadingPlaceholder: boolean = this.state.loadingPlaceholder
  ): BrowserAddressBarTabSwipeState {
    return { stage: stage, offsetX: offsetX, width: this.state.width, direction: this.state.direction,
      targetTabId: this.state.targetTabId, targetTitle: this.state.targetTitle,
      targetAddress: this.state.targetAddress, previewOpacity: previewOpacity, reduceMotion: this.state.reduceMotion,
      loadingPlaceholder: loadingPlaceholder };
  }

  private publish(state: BrowserAddressBarTabSwipeState): void {
    this.state = state;
    this.host.publish(state);
  }
}

import { UIContext } from '@kit.ArkUI';
import {
  BrowserPageChromeThemeProbe,
  BrowserPageChromeThemeProbeDispatchHost,
  BrowserPageChromeThemeSnapshot
} from './BrowserPageChromeThemeProbe';
import { BrowserTabState, BrowserTabManagerPort } from '../tabs/TabManager';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import {
  BrowserChromeRuntimeCoordinator,
  BrowserChromeRuntimeState
} from './BrowserChromeRuntimeCoordinator';
import { BrowserWebScrollInteractionCoordinator } from './BrowserWebScrollInteractionCoordinator';
import {
  BrowserWebTopSafeAreaColorSampler,
  BrowserWebTopSafeAreaColorSampleResult
} from '../../services/browser/BrowserWebTopSafeAreaColorSampler';
import { buildBrowserTabPreviewComponentSnapshotId } from '../../services/web/BrowserTabPreviewCaptureService';

type BrowserPageChromeThemeSamplingTaskKind = 'script_probe' | 'visual_top_strip';

interface BrowserPageChromeThemeSamplingRequest {
  tabId: string;
  activeTabId: string;
  webPageVisible: boolean;
  showTabsSheet: boolean;
  shouldDeferForScrollPerformance: boolean;
  now: number;
}

interface BrowserPageChromeThemeSamplingScheduleResult {
  shouldSchedule: boolean;
  delayMs: number;
  token: number;
  reason: string;
}

interface BrowserPageChromeThemeSamplingRunResult {
  shouldRun: boolean;
  shouldReschedule: boolean;
  reason: string;
}

export interface BrowserPageChromeThemeVisualSamplingContext {
  uiContext: UIContext;
  systemTopInsetPx: number;
  contentGapPx: number;
}

export interface BrowserPageChromeThemeSamplingFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  webPageVisible: boolean;
  showTabsSheet: boolean;
  chromeRuntimeState: BrowserChromeRuntimeState;
  visualSamplingSuppressed: boolean;
}

export interface BrowserPageChromeThemeSamplingHost {
  readFacts: () => BrowserPageChromeThemeSamplingFacts;
  resolveVisualSamplingContext: () => BrowserPageChromeThemeVisualSamplingContext;
  publishChromeRuntimeState: (state: BrowserChromeRuntimeState) => void;
  syncBottomPanelStatusBarStyle: () => void;
}

interface BrowserPageChromeThemeSamplingDependencies {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  tabManager: BrowserTabManagerPort;
  chromeRuntimeCoordinator: BrowserChromeRuntimeCoordinator;
  resolveWebScrollInteractionCoordinator: () => BrowserWebScrollInteractionCoordinator;
  colorSampler: BrowserWebTopSafeAreaColorSampler;
}

interface BrowserPageChromeThemeTaskState {
  token: number;
  lastRunAt: number;
}

const MIN_SCRIPT_PROBE_INTERVAL_MS: number = 900;
const MIN_VISUAL_SAMPLE_INTERVAL_MS: number = 1200;
const DEFERRED_SCRIPT_PROBE_DELAY_MS: number = 1600;
const THEME_SIGNAL_FALLBACK_DELAY_MS: number = 180;
const VISUAL_SAMPLE_DELAY_MS: number = 120;

export class BrowserPageChromeThemeSamplingCoordinator {
  private readonly probe: BrowserPageChromeThemeProbe = new BrowserPageChromeThemeProbe();
  private readonly dependencies: BrowserPageChromeThemeSamplingDependencies;
  private readonly host: BrowserPageChromeThemeSamplingHost;
  private scriptProbeTimer: number = -1;
  private visualSampleTimer: number = -1;
  private scriptProbeState: BrowserPageChromeThemeTaskState = {
    token: 0,
    lastRunAt: 0
  };
  private visualSampleState: BrowserPageChromeThemeTaskState = {
    token: 0,
    lastRunAt: 0
  };

  constructor(
    dependencies: BrowserPageChromeThemeSamplingDependencies,
    host: BrowserPageChromeThemeSamplingHost
  ) {
    this.dependencies = dependencies;
    this.host = host;
  }

  private cancelScriptProbe(): void {
    this.cancel('script_probe');
    if (this.scriptProbeTimer >= 0) {
      clearTimeout(this.scriptProbeTimer);
      this.scriptProbeTimer = -1;
    }
  }

  private cancelVisualSample(resetSampleWindow: boolean = false): void {
    if (resetSampleWindow) {
      this.reset('visual_top_strip');
    } else {
      this.cancel('visual_top_strip');
    }
    if (this.visualSampleTimer >= 0) {
      clearTimeout(this.visualSampleTimer);
      this.visualSampleTimer = -1;
    }
  }

  scheduleScriptProbe(tabId: string): void {
    this.scheduleScriptProbeWithDelay(tabId, DEFERRED_SCRIPT_PROBE_DELAY_MS);
  }

  scheduleVisualSample(tabId: string): void {
    const facts = this.host.readFacts();
    if (facts.visualSamplingSuppressed) {
      return;
    }
    const schedule = this.schedule(
      'visual_top_strip',
      this.buildRequest(tabId, facts, false),
      this.dependencies.resolveWebScrollInteractionCoordinator().getQuietDelayMs(VISUAL_SAMPLE_DELAY_MS)
    );
    if (!schedule.shouldSchedule) {
      return;
    }
    if (this.visualSampleTimer >= 0) {
      clearTimeout(this.visualSampleTimer);
      this.visualSampleTimer = -1;
    }
    this.visualSampleTimer = setTimeout(() => {
      this.visualSampleTimer = -1;
      const runFacts = this.host.readFacts();
      const run = this.shouldRun(
        'visual_top_strip',
        this.buildRequest(
          tabId,
          runFacts,
          this.dependencies.resolveWebScrollInteractionCoordinator()
            .shouldDeferTask('page_chrome_theme_probe')
        ),
        schedule.token
      );
      if (run.shouldReschedule) {
        this.scheduleVisualSample(tabId);
        return;
      }
      if (!run.shouldRun || runFacts.visualSamplingSuppressed) {
        return;
      }
      this.samplePageChromeVisualTopColor(tabId);
    }, schedule.delayMs);
  }

  handleThemeSignal(tabId: string, payloadJson: string): void {
    const facts = this.host.readFacts();
    if (!this.isActiveVisibleTabId(tabId, facts)) {
      return;
    }
    const snapshot = this.probe.parseProbeResult(payloadJson);
    const hasColorSignal = snapshot.themeColor.length > 0 || snapshot.pageBackgroundColor.length > 0;
    if (hasColorSignal) {
      this.applyPageChromeTheme(tabId, this.toSnapshot(snapshot));
      return;
    }
    this.scheduleScriptProbeWithDelay(tabId, THEME_SIGNAL_FALLBACK_DELAY_MS);
  }

  clearTab(tabId: string): void {
    const facts = this.host.readFacts();
    const isActiveTab = tabId === facts.activeTabId;
    if (isActiveTab) {
      this.cancelScriptProbe();
      this.cancelVisualSample(true);
    }
    const nextState = this.dependencies.chromeRuntimeCoordinator.clearPageChromeTheme(
      facts.chromeRuntimeState,
      tabId
    );
    if (nextState === facts.chromeRuntimeState) {
      return;
    }
    this.host.publishChromeRuntimeState(nextState);
    if (isActiveTab) {
      this.host.syncBottomPanelStatusBarStyle();
    }
  }

  private scheduleScriptProbeWithDelay(tabId: string, baseDelayMs: number): void {
    const facts = this.host.readFacts();
    const schedule = this.schedule(
      'script_probe',
      this.buildRequest(tabId, facts, false),
      this.dependencies.resolveWebScrollInteractionCoordinator().getQuietDelayMs(baseDelayMs)
    );
    if (!schedule.shouldSchedule) {
      return;
    }
    if (this.scriptProbeTimer >= 0) {
      clearTimeout(this.scriptProbeTimer);
      this.scriptProbeTimer = -1;
    }
    this.scriptProbeTimer = setTimeout(() => {
      this.scriptProbeTimer = -1;
      const runFacts = this.host.readFacts();
      const run = this.shouldRun(
        'script_probe',
        this.buildRequest(
          tabId,
          runFacts,
          this.dependencies.resolveWebScrollInteractionCoordinator()
            .shouldDeferTask('page_chrome_theme_probe')
        ),
        schedule.token
      );
      if (run.shouldReschedule) {
        this.scheduleScriptProbeWithDelay(tabId, baseDelayMs);
        return;
      }
      if (!run.shouldRun) {
        return;
      }
      this.probe.runPageChromeThemeProbe(tabId, this.buildProbeDispatchHost());
    }, schedule.delayMs);
  }

  private samplePageChromeVisualTopColor(tabId: string): void {
    const context = this.host.resolveVisualSamplingContext();
    void this.dependencies.colorSampler.sample({
      uiContext: context.uiContext,
      componentSnapshotId: buildBrowserTabPreviewComponentSnapshotId(tabId),
      systemTopInsetPx: context.systemTopInsetPx,
      contentGapPx: context.contentGapPx
    }).then((result: BrowserWebTopSafeAreaColorSampleResult) => {
      this.handleVisualSampleResult(tabId, result);
    }).catch((_error: Error) => {
    });
  }

  private handleVisualSampleResult(
    tabId: string,
    result: BrowserWebTopSafeAreaColorSampleResult
  ): void {
    const facts = this.host.readFacts();
    if (!this.isActiveVisibleTabId(tabId, facts) || facts.visualSamplingSuppressed || result.color.length <= 0) {
      return;
    }
    this.applyPageChromeVisualTopColor(tabId, result.color);
  }

  private applyPageChromeTheme(tabId: string, snapshot: BrowserPageChromeThemeSnapshot): boolean {
    const facts = this.host.readFacts();
    const nextState = this.dependencies.chromeRuntimeCoordinator.applyPageChromeTheme(
      facts.chromeRuntimeState,
      tabId,
      {
        themeColor: snapshot.themeColor,
        pageBackgroundColor: snapshot.pageBackgroundColor,
        prefersDarkScheme: snapshot.prefersDarkScheme,
        supportsDarkAppearance: snapshot.supportsDarkAppearance
      }
    );
    if (nextState === facts.chromeRuntimeState) {
      return false;
    }
    this.host.publishChromeRuntimeState(nextState);
    if (tabId === facts.activeTabId) {
      this.host.syncBottomPanelStatusBarStyle();
      this.scheduleVisualSample(tabId);
    }
    return true;
  }

  private applyPageChromeVisualTopColor(tabId: string, color: string): boolean {
    const facts = this.host.readFacts();
    const nextState = this.dependencies.chromeRuntimeCoordinator.applyPageChromeVisualTopColor(
      facts.chromeRuntimeState,
      tabId,
      color
    );
    if (nextState === facts.chromeRuntimeState) {
      return false;
    }
    this.host.publishChromeRuntimeState(nextState);
    if (tabId === facts.activeTabId) {
      this.host.syncBottomPanelStatusBarStyle();
    }
    return true;
  }

  private cancel(kind: BrowserPageChromeThemeSamplingTaskKind): void {
    this.getState(kind).token += 1;
  }

  private reset(kind: BrowserPageChromeThemeSamplingTaskKind): void {
    const state = this.getState(kind);
    state.token += 1;
    state.lastRunAt = 0;
  }

  private schedule(
    kind: BrowserPageChromeThemeSamplingTaskKind,
    request: BrowserPageChromeThemeSamplingRequest,
    baseDelayMs: number
  ): BrowserPageChromeThemeSamplingScheduleResult {
    if (!this.isActiveVisibleTab(request)) {
      return {
        shouldSchedule: false,
        delayMs: 0,
        token: this.getState(kind).token,
        reason: 'inactive'
      };
    }
    const state = this.getState(kind);
    state.token += 1;
    const minIntervalMs = this.resolveMinIntervalMs(kind);
    const elapsedMs = request.now - state.lastRunAt;
    const cooldownDelayMs = elapsedMs >= minIntervalMs ? 0 : minIntervalMs - Math.max(0, elapsedMs);
    return {
      shouldSchedule: true,
      delayMs: Math.max(0, Math.ceil(Math.max(baseDelayMs, cooldownDelayMs))),
      token: state.token,
      reason: cooldownDelayMs > baseDelayMs ? 'cooldown' : 'scheduled'
    };
  }

  private shouldRun(
    kind: BrowserPageChromeThemeSamplingTaskKind,
    request: BrowserPageChromeThemeSamplingRequest,
    token: number
  ): BrowserPageChromeThemeSamplingRunResult {
    const state = this.getState(kind);
    if (token !== state.token) {
      return {
        shouldRun: false,
        shouldReschedule: false,
        reason: 'stale'
      };
    }
    if (!this.isActiveVisibleTab(request)) {
      return {
        shouldRun: false,
        shouldReschedule: false,
        reason: 'inactive'
      };
    }
    if (request.shouldDeferForScrollPerformance) {
      return {
        shouldRun: false,
        shouldReschedule: true,
        reason: 'scroll_deferred'
      };
    }
    state.lastRunAt = request.now;
    return {
      shouldRun: true,
      shouldReschedule: false,
      reason: 'ready'
    };
  }

  private isActiveVisibleTab(input: BrowserPageChromeThemeSamplingRequest): boolean {
    return input.tabId.length > 0 &&
      input.tabId === input.activeTabId &&
      input.webPageVisible &&
      !input.showTabsSheet;
  }

  private isActiveVisibleTabId(tabId: string, facts: BrowserPageChromeThemeSamplingFacts): boolean {
    return tabId.length > 0 &&
      tabId === facts.activeTabId &&
      facts.webPageVisible &&
      !facts.showTabsSheet;
  }

  private buildRequest(
    tabId: string,
    facts: BrowserPageChromeThemeSamplingFacts,
    shouldDeferForScrollPerformance: boolean
  ): BrowserPageChromeThemeSamplingRequest {
    return {
      tabId: tabId,
      activeTabId: facts.activeTabId,
      webPageVisible: facts.webPageVisible,
      showTabsSheet: facts.showTabsSheet,
      shouldDeferForScrollPerformance: shouldDeferForScrollPerformance,
      now: Date.now()
    };
  }

  private buildProbeDispatchHost(): BrowserPageChromeThemeProbeDispatchHost {
    return {
      resolveTab: (tabId: string): BrowserTabState | undefined => {
        return this.dependencies.tabManager.getTab(this.host.readFacts().tabs, tabId);
      },
      resolveController: (tabId: string) => this.dependencies.runtimeLifecyclePort.resolveController(tabId),
      applyPageChromeTheme: (tabId: string, snapshot: BrowserPageChromeThemeSnapshot): void => {
        this.applyPageChromeTheme(tabId, snapshot);
      }
    };
  }

  private toSnapshot(snapshot: BrowserPageChromeThemeSnapshot): BrowserPageChromeThemeSnapshot {
    return {
      themeColor: snapshot.themeColor,
      pageBackgroundColor: snapshot.pageBackgroundColor,
      prefersDarkScheme: snapshot.prefersDarkScheme,
      supportsDarkAppearance: snapshot.supportsDarkAppearance
    };
  }

  private resolveMinIntervalMs(kind: BrowserPageChromeThemeSamplingTaskKind): number {
    if (kind === 'visual_top_strip') {
      return MIN_VISUAL_SAMPLE_INTERVAL_MS;
    }
    return MIN_SCRIPT_PROBE_INTERVAL_MS;
  }

  private getState(kind: BrowserPageChromeThemeSamplingTaskKind): BrowserPageChromeThemeTaskState {
    if (kind === 'visual_top_strip') {
      return this.visualSampleState;
    }
    return this.scriptProbeState;
  }
}

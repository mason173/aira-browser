import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import {
  buildDocumentZoomScript,
  buildPageScaleReadScript,
  isDocumentZoomApplied,
  normalizeObservedWebZoomPercent,
  resolveBaselinePageScale,
  resolvePageScalePercentFromViewport,
  resolveWebZoomPlan
} from './BrowserLargeScreenWebZoomPolicy';

export const BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT: number = 100;
const BROWSER_LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_DURATION_MS: number = 1500;
const WEB_ZOOM_DIAG_DOMAIN: number = 0x0000;
const WEB_ZOOM_DIAG_TAG: string = 'DesktopZoomDiag';
const WEB_ZOOM_DIAG_PREFIX: string = '[DEBUG-desktop-zoom-20260726]';

const BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS: number[] = [
  25,
  33,
  50,
  67,
  75,
  80,
  90,
  100,
  110,
  125,
  150,
  175,
  200,
  250,
  300,
  400,
  500
];

export type BrowserLargeScreenWebZoomAction = 'decrease' | 'increase' | 'reset';

export interface BrowserLargeScreenWebZoomSnapshot {
  tabId: string;
  percent: number;
  percentLabel: string;
  percentKnown: boolean;
  canDecrease: boolean;
  canIncrease: boolean;
  available: boolean;
  shortcutNotificationVisible: boolean;
  shortcutNotificationLabel: string;
  revision: number;
}

export interface BrowserLargeScreenWebZoomApplyResult {
  snapshot: BrowserLargeScreenWebZoomSnapshot;
  changed: boolean;
  applied: boolean;
  unavailableReason: string;
}

export function createBrowserLargeScreenWebZoomSnapshot(): BrowserLargeScreenWebZoomSnapshot {
  return {
    tabId: '',
    percent: BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT,
    percentLabel: `${BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT}%`,
    percentKnown: true,
    canDecrease: false,
    canIncrease: false,
    available: false,
    shortcutNotificationVisible: false,
    shortcutNotificationLabel: '',
    revision: 0
  };
}

interface BrowserLargeScreenWebZoomTabState {
  percent: number;
  enginePercent: number;
  baselinePercent: number;
  runtimeId: number;
  percentKnown: boolean;
  owned: boolean;
  zoomEpoch: number;
}

interface BrowserLargeScreenWebZoomRuntimeSnapshot {
  available: boolean;
  runtimeId: number;
  reason: string;
}

interface BrowserLargeScreenWebZoomExecutionResult {
  applied: boolean;
  runtimeId: number;
  reason: string;
  percent: number;
}

export class BrowserLargeScreenWebZoomCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  private readonly publishRevision: () => void;
  private statesByTabId: Record<string, BrowserLargeScreenWebZoomTabState | undefined> = {};
  private revision: number = 0;
  private debugSequence: number = 0;
  private shortcutNotificationTabId: string = '';
  private shortcutNotificationVisible: boolean = false;
  private shortcutNotificationLabel: string = '';
  private shortcutNotificationDismissTimer: number = -1;
  private shortcutNotificationGeneration: number = 0;
  private scaleObservationGeneration: number = 0;
  private lastObservedScaleByTabId: Record<string, number | undefined> = {};

  constructor(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort,
    publishRevision: () => void
  ) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.hostedRuntimeSurfacePort = hostedRuntimeSurfacePort;
    this.publishRevision = publishRevision;
  }

  snapshot(tabId: string, _presentationRevision: number = 0): BrowserLargeScreenWebZoomSnapshot {
    const normalizedTabId = tabId.trim();
    const runtime = this.resolveRuntime(normalizedTabId);
    const state = this.resolveTabState(normalizedTabId, runtime);
    return this.buildSnapshot(normalizedTabId, state.percent, state.percentKnown, runtime.available);
  }

  resolveForceEnableWebZoom(configuredForceEnableWebZoom: boolean, largeScreenShellActive: boolean): boolean {
    return largeScreenShellActive || configuredForceEnableWebZoom;
  }

  // 键盘 Ctrl +/-/0 与弹窗按钮走同一条目标缩放路径。档位写入 document zoom，
  // 不把请求百分比当成已经生效；引擎没动时界面保持上一次确认的比例。
  applyShortcut(
    tabId: string,
    action: BrowserLargeScreenWebZoomAction
  ): BrowserLargeScreenWebZoomApplyResult {
    const result = this.apply(tabId, action);
    if (result.applied) {
      this.presentShortcutNotification(
        result.snapshot.tabId,
        this.resolveShortcutNotificationLabel(action)
      );
    }
    return {
      snapshot: this.snapshot(result.snapshot.tabId),
      changed: result.changed,
      applied: result.applied,
      unavailableReason: result.unavailableReason
    };
  }

  dispose(): void {
    this.clearShortcutNotificationDismissTimer();
    this.shortcutNotificationVisible = false;
    this.shortcutNotificationTabId = '';
    this.shortcutNotificationLabel = '';
    this.shortcutNotificationGeneration += 1;
  }

  apply(tabId: string, action: BrowserLargeScreenWebZoomAction): BrowserLargeScreenWebZoomApplyResult {
    const normalizedTabId = tabId.trim();
    this.debugSequence += 1;
    const traceId = this.debugSequence;
    const runtime = this.resolveRuntime(normalizedTabId, 'apply-entry', traceId);
    const currentState = this.resolveTabState(normalizedTabId, runtime);
    const targetPercent = this.resolveTargetPercent(currentState.percent, action);
    if (!runtime.available) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s apply-result id=%{public}d applied=false changed=false reason=%{public}s percent=%{public}d',
        WEB_ZOOM_DIAG_PREFIX,
        traceId,
        runtime.reason,
        currentState.percent
      );
      return this.buildApplyResult(normalizedTabId, currentState.percent, false, false, runtime.reason);
    }
    // 100% 是页面刚打开时的基准。高于基准用 zoom()，低于 100% 才用 CSS zoom。
    const execution = this.applyTargetZoom(normalizedTabId, targetPercent, traceId);
    if (!execution.applied) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s apply-result id=%{public}d applied=false changed=false reason=%{public}s percent=%{public}d runtimeId=%{public}d',
        WEB_ZOOM_DIAG_PREFIX,
        traceId,
        execution.reason,
        currentState.percent,
        execution.runtimeId
      );
      return this.buildExecutionFailureResult(normalizedTabId, currentState.percent, execution);
    }
    const changed = execution.percent !== currentState.percent;
    this.revision += 1;
    this.publishRevision();
    return this.buildApplyResult(normalizedTabId, execution.percent, changed, true, '');
  }

  handleDocumentBegin(tabId: string): void {
    const normalizedTabId = tabId.trim();
    const state = this.statesByTabId[normalizedTabId];
    if (state === undefined) {
      return;
    }
    this.lastObservedScaleByTabId[normalizedTabId] = undefined;
    this.statesByTabId[normalizedTabId] = {
      percent: state.percent,
      enginePercent: 0,
      baselinePercent: 0,
      runtimeId: state.runtimeId,
      percentKnown: state.percentKnown,
      owned: state.owned,
      zoomEpoch: state.zoomEpoch
    };
  }

  handleDocumentEnd(tabId: string): void {
    const normalizedTabId = tabId.trim();
    const state = this.statesByTabId[normalizedTabId];
    if (state === undefined || !state.owned || state.percent === BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT) {
      return;
    }
    this.applyTargetZoom(normalizedTabId, state.percent, this.debugSequence);
  }

  observePageScale(tabId: string, scalePercent: number): boolean {
    const normalizedTabId = tabId.trim();
    const displayPercent = normalizeObservedWebZoomPercent(scalePercent);
    if (normalizedTabId.length === 0 || displayPercent <= 0) {
      return false;
    }
    this.scaleObservationGeneration += 1;
    this.lastObservedScaleByTabId[normalizedTabId] = scalePercent;
    const runtime = this.resolveRuntime(normalizedTabId);
    const currentState = this.resolveTabState(normalizedTabId, runtime);
    const baselinePercent = currentState.baselinePercent > 0 ? currentState.baselinePercent :
      (!currentState.owned ? scalePercent : 0);
    this.statesByTabId[normalizedTabId] = {
      percent: currentState.percent,
      enginePercent: scalePercent,
      baselinePercent: baselinePercent,
      runtimeId: runtime.runtimeId > 0 ? runtime.runtimeId : currentState.runtimeId,
      percentKnown: currentState.percentKnown,
      owned: currentState.owned,
      zoomEpoch: currentState.zoomEpoch
    };
    return false;
  }

  private resolveTabState(
    tabId: string,
    runtime: BrowserLargeScreenWebZoomRuntimeSnapshot
  ): BrowserLargeScreenWebZoomTabState {
    const storedState = this.statesByTabId[tabId];
    if (storedState === undefined) {
      return {
        percent: BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT,
        enginePercent: 0,
        baselinePercent: 0,
        runtimeId: runtime.runtimeId,
        percentKnown: true,
        owned: false,
        zoomEpoch: 0
      };
    }
    if (runtime.available && storedState.runtimeId > 0 && runtime.runtimeId !== storedState.runtimeId) {
      const resetState: BrowserLargeScreenWebZoomTabState = {
        percent: BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT,
        enginePercent: 0,
        baselinePercent: 0,
        runtimeId: runtime.runtimeId,
        percentKnown: true,
        owned: false,
        zoomEpoch: 0
      };
      this.statesByTabId[tabId] = resetState;
      return resetState;
    }
    return storedState;
  }

  private resolveTargetPercent(currentPercent: number, action: BrowserLargeScreenWebZoomAction): number {
    if (action === 'reset') {
      return BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT;
    }
    if (action === 'increase') {
      return BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS.find((percent: number): boolean => percent > currentPercent) ??
        BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS[BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS.length - 1];
    }
    for (let index = BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS.length - 1; index >= 0; index--) {
      if (BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS[index] < currentPercent) {
        return BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS[index];
      }
    }
    return BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS[0];
  }

  private buildExecutionFailureResult(
    tabId: string,
    percent: number,
    execution: BrowserLargeScreenWebZoomExecutionResult
  ): BrowserLargeScreenWebZoomApplyResult {
    return this.buildApplyResult(tabId, percent, false, false, execution.reason);
  }

  private buildApplyResult(
    tabId: string,
    percent: number,
    changed: boolean,
    applied: boolean,
    unavailableReason: string
  ): BrowserLargeScreenWebZoomApplyResult {
    const state = this.statesByTabId[tabId];
    return {
      snapshot: this.buildSnapshot(
        tabId,
        percent,
        state?.percentKnown ?? true,
        this.resolveRuntime(tabId).available
      ),
      changed: changed,
      applied: applied,
      unavailableReason: unavailableReason
    };
  }

  private buildSnapshot(
    tabId: string,
    percent: number,
    percentKnown: boolean,
    available: boolean
  ): BrowserLargeScreenWebZoomSnapshot {
    return {
      tabId: tabId,
      percent: percent,
      percentLabel: percentKnown ? `${percent}%` : '—',
      percentKnown: percentKnown,
      canDecrease: available && (!percentKnown || percent > BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS[0]),
      canIncrease: available && (!percentKnown || percent <
        BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS[BROWSER_LARGE_SCREEN_WEB_ZOOM_LEVELS.length - 1]),
      available: available,
      shortcutNotificationVisible: this.shortcutNotificationVisible && this.shortcutNotificationTabId === tabId,
      shortcutNotificationLabel: this.shortcutNotificationLabel,
      revision: this.revision
    };
  }

  private resolveShortcutNotificationLabel(action: BrowserLargeScreenWebZoomAction): string {
    if (action === 'increase') {
      return '网页已放大';
    }
    if (action === 'decrease') {
      return '网页已缩小';
    }
    return '网页已恢复默认缩放';
  }

  private presentShortcutNotification(tabId: string, label: string): void {
    this.clearShortcutNotificationDismissTimer();
    this.shortcutNotificationTabId = tabId;
    this.shortcutNotificationVisible = true;
    this.shortcutNotificationLabel = label;
    this.shortcutNotificationGeneration += 1;
    const notificationGeneration = this.shortcutNotificationGeneration;
    this.revision += 1;
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s notification-present tab=%{public}s label=%{public}s revision=%{public}d',
      WEB_ZOOM_DIAG_PREFIX,
      tabId,
      label,
      this.revision
    );
    this.publishRevision();
    this.shortcutNotificationDismissTimer = setTimeout(() => {
      if (notificationGeneration !== this.shortcutNotificationGeneration ||
        this.shortcutNotificationTabId !== tabId) {
        return;
      }
      this.shortcutNotificationDismissTimer = -1;
      this.shortcutNotificationVisible = false;
      this.revision += 1;
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s notification-dismiss tab=%{public}s revision=%{public}d',
        WEB_ZOOM_DIAG_PREFIX,
        tabId,
        this.revision
      );
      this.publishRevision();
    }, BROWSER_LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_DURATION_MS);
  }

  private clearShortcutNotificationDismissTimer(): void {
    if (this.shortcutNotificationDismissTimer < 0) {
      return;
    }
    clearTimeout(this.shortcutNotificationDismissTimer);
    this.shortcutNotificationDismissTimer = -1;
  }

  private resolveRuntime(
    tabId: string,
    traceStage: string = '',
    traceId: number = -1
  ): BrowserLargeScreenWebZoomRuntimeSnapshot {
    const attached = tabId.length > 0 && this.hostedRuntimeSurfacePort.isHostedControllerAttached(tabId);
    const controllerAvailable = tabId.length > 0 && this.runtimeLifecyclePort.resolveController(tabId) !== undefined;
    const runtimeId = controllerAvailable ? this.runtimeLifecyclePort.resolveWebId(tabId) : -1;
    let snapshot: BrowserLargeScreenWebZoomRuntimeSnapshot;
    if (tabId.length <= 0) {
      snapshot = { available: false, runtimeId: -1, reason: 'missing_tab' };
    } else if (!attached) {
      snapshot = { available: false, runtimeId: runtimeId, reason: 'controller_detached' };
    } else if (!controllerAvailable) {
      snapshot = { available: false, runtimeId: -1, reason: 'missing_controller' };
    } else {
      snapshot = { available: true, runtimeId: runtimeId, reason: '' };
    }
    if (traceStage.length > 0) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s runtime id=%{public}d stage=%{public}s tab=%{public}s attached=%{public}s controller=%{public}s runtimeId=%{public}d available=%{public}s reason=%{public}s',
        WEB_ZOOM_DIAG_PREFIX,
        traceId,
        traceStage,
        tabId,
        attached ? 'true' : 'false',
        controllerAvailable ? 'true' : 'false',
        snapshot.runtimeId,
        snapshot.available ? 'true' : 'false',
        snapshot.reason
      );
    }
    return snapshot;
  }

  private applyTargetZoom(
    tabId: string,
    percent: number,
    traceId: number
  ): BrowserLargeScreenWebZoomExecutionResult {
    const runtime = this.resolveRuntime(tabId, 'zoom-call', traceId);
    if (!runtime.available) {
      return { applied: false, runtimeId: runtime.runtimeId, reason: runtime.reason, percent: percent };
    }
    const currentState = this.resolveTabState(tabId, runtime);
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    if (controller === undefined) {
      return { applied: false, runtimeId: -1, reason: 'missing_controller', percent: currentState.percent };
    }
    const zoomEpoch = currentState.zoomEpoch + 1;
    const knownPageScale = this.resolveKnownPageScale(tabId, currentState);
    this.statesByTabId[tabId] = {
      percent: percent,
      enginePercent: knownPageScale,
      baselinePercent: currentState.baselinePercent,
      runtimeId: runtime.runtimeId,
      percentKnown: true,
      owned: true,
      zoomEpoch: zoomEpoch
    };
    try {
      const pending = controller.runJavaScript(buildPageScaleReadScript());
      pending.then((raw: string) => {
        this.finishZoomChoice(tabId, zoomEpoch, percent, currentState.percent, knownPageScale, raw, runtime.runtimeId);
      }).catch((_error: Error) => {
        this.finishZoomChoice(tabId, zoomEpoch, percent, currentState.percent, knownPageScale, '', runtime.runtimeId);
      });
      return { applied: true, runtimeId: runtime.runtimeId, reason: '', percent: percent };
    } catch (_error) {
      const baseline = resolveBaselinePageScale(currentState.baselinePercent, knownPageScale);
      return this.applyChosenZoom(
        tabId, zoomEpoch, percent, currentState.percent, knownPageScale, baseline, runtime.runtimeId);
    }
  }

  private finishZoomChoice(
    tabId: string,
    zoomEpoch: number,
    percent: number,
    previousPercent: number,
    knownPageScale: number,
    raw: string,
    runtimeId: number
  ): void {
    const state = this.statesByTabId[tabId];
    if (state === undefined || state.zoomEpoch !== zoomEpoch) {
      return;
    }
    const readScale = resolvePageScalePercentFromViewport(raw);
    const pageScale = readScale > 0 ? readScale : knownPageScale;
    const baseline = resolveBaselinePageScale(state.baselinePercent, readScale);
    const resolvedBaseline = baseline > 0 ? baseline : pageScale;
    this.applyChosenZoom(
      tabId, zoomEpoch, percent, previousPercent, pageScale, resolvedBaseline, runtimeId);
  }

  private applyChosenZoom(
    tabId: string,
    zoomEpoch: number,
    percent: number,
    previousPercent: number,
    pageScale: number,
    baseline: number,
    runtimeId: number
  ): BrowserLargeScreenWebZoomExecutionResult {
    const state = this.resolveTabState(tabId, { available: true, runtimeId: runtimeId, reason: '' });
    this.statesByTabId[tabId] = {
      percent: state.percent,
      enginePercent: pageScale,
      baselinePercent: baseline,
      runtimeId: state.runtimeId,
      percentKnown: true,
      owned: true,
      zoomEpoch: state.zoomEpoch
    };
    const plan = resolveWebZoomPlan(baseline, pageScale, percent);
    if (plan.pageScaleTarget <= 0 || plan.zoomFactor <= 0) {
      this.restoreUnappliedZoom(tabId, previousPercent, pageScale, baseline, state.runtimeId, state.zoomEpoch);
      return {
        applied: false,
        runtimeId: runtimeId,
        reason: 'invalid_factor',
        percent: previousPercent
      };
    }
    if (plan.mechanism === 'document') {
      if (Math.abs(plan.zoomFactor - 1) > 0.01) {
        this.zoomEngine(tabId, plan.zoomFactor);
      }
      return this.applyDocumentZoom(
        tabId, zoomEpoch, percent, previousPercent, plan.pageScaleTarget, plan.cssRatio, runtimeId);
    }
    return this.applyPageScaleZoom(
      tabId, percent, state, pageScale, plan.pageScaleTarget, plan.zoomFactor, plan.clearCss, runtimeId);
  }

  private applyDocumentZoom(
    tabId: string,
    zoomEpoch: number,
    percent: number,
    previousPercent: number,
    pageScale: number,
    ratio: number,
    runtimeId: number
  ): BrowserLargeScreenWebZoomExecutionResult {
    const script = buildDocumentZoomScript(ratio);
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    const state = this.resolveTabState(tabId, { available: true, runtimeId: runtimeId, reason: '' });
    if (script.length === 0 || controller === undefined) {
      this.restoreUnappliedZoom(tabId, previousPercent, pageScale, state.baselinePercent, runtimeId, zoomEpoch);
      return {
        applied: false,
        runtimeId: runtimeId,
        reason: controller === undefined ? 'missing_controller' : 'invalid_factor',
        percent: previousPercent
      };
    }
    try {
      const pending = controller.runJavaScript(script);
      this.statesByTabId[tabId] = {
        percent: percent,
        enginePercent: pageScale,
        baselinePercent: state.baselinePercent,
        runtimeId: runtimeId,
        percentKnown: true,
        owned: true,
        zoomEpoch: zoomEpoch
      };
      pending.then((raw: string) => {
        this.finishDocumentZoom(tabId, zoomEpoch, percent, previousPercent, pageScale, ratio, raw);
      }).catch((_error: Error) => {
        this.finishDocumentZoom(tabId, zoomEpoch, percent, previousPercent, pageScale, ratio, '');
      });
      return { applied: true, runtimeId: runtimeId, reason: '', percent: percent };
    } catch (_error) {
      this.restoreUnappliedZoom(tabId, previousPercent, pageScale, state.baselinePercent, runtimeId, zoomEpoch);
      return {
        applied: false,
        runtimeId: runtimeId,
        reason: 'platform_error',
        percent: previousPercent
      };
    }
  }

  private restoreUnappliedZoom(
    tabId: string,
    previousPercent: number,
    pageScale: number,
    baseline: number,
    runtimeId: number,
    zoomEpoch: number
  ): void {
    this.statesByTabId[tabId] = {
      percent: previousPercent,
      enginePercent: pageScale,
      baselinePercent: baseline,
      runtimeId: runtimeId,
      percentKnown: previousPercent > 0,
      owned: false,
      zoomEpoch: zoomEpoch
    };
    this.revision += 1;
    this.publishRevision();
  }

  private finishDocumentZoom(
    tabId: string,
    zoomEpoch: number,
    percent: number,
    previousPercent: number,
    pageScalePercent: number,
    ratio: number,
    raw: string
  ): void {
    const state = this.statesByTabId[tabId];
    if (state === undefined || state.zoomEpoch !== zoomEpoch) {
      return;
    }
    const applied = isDocumentZoomApplied(raw, ratio);
    if (applied) {
      return;
    }
    this.statesByTabId[tabId] = {
      percent: previousPercent,
      enginePercent: pageScalePercent,
      baselinePercent: state.baselinePercent,
      runtimeId: state.runtimeId,
      percentKnown: true,
      owned: false,
      zoomEpoch: state.zoomEpoch
    };
    this.revision += 1;
    this.publishRevision();
  }

  private applyPageScaleZoom(
    tabId: string,
    percent: number,
    currentState: BrowserLargeScreenWebZoomTabState,
    currentEnginePercent: number,
    desiredPageScale: number,
    factor: number,
    clearCss: boolean,
    runtimeId: number
  ): BrowserLargeScreenWebZoomExecutionResult {
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    if (desiredPageScale <= 0 || factor <= 0 || controller === undefined) {
      return {
        applied: false,
        runtimeId: runtimeId,
        reason: controller === undefined ? 'missing_controller' : 'invalid_factor',
        percent: currentState.percent
      };
    }
    const shouldZoom = Math.abs(factor - 1) > 0.01;
    try {
      if (clearCss) {
        void controller.runJavaScript("(function(){var root=document.documentElement;if(root){root.style.removeProperty('zoom');}return '';})()");
      }
      if (shouldZoom) {
        controller.zoom(factor);
      }
    } catch (_error) {
      return { applied: false, runtimeId: runtimeId, reason: 'platform_error', percent: currentState.percent };
    }
    const baselinePercent = this.statesByTabId[tabId]?.baselinePercent ?? currentState.baselinePercent;
    this.statesByTabId[tabId] = {
      percent: percent,
      enginePercent: shouldZoom ? desiredPageScale : currentEnginePercent,
      baselinePercent: baselinePercent,
      runtimeId: runtimeId > 0 ? runtimeId : currentState.runtimeId,
      percentKnown: true,
      owned: true,
      zoomEpoch: currentState.zoomEpoch
    };
    return { applied: true, runtimeId: runtimeId, reason: '', percent: percent };
  }

  private zoomEngine(tabId: string, factor: number): void {
    if (factor <= 0 || Math.abs(factor - 1) <= 0.01) {
      return;
    }
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    if (controller === undefined) {
      return;
    }
    try {
      controller.zoom(factor);
    } catch (_error) {
    }
  }

  private resolveKnownPageScale(tabId: string, state: BrowserLargeScreenWebZoomTabState): number {
    const observed = this.lastObservedScaleByTabId[tabId];
    if (observed !== undefined && Number.isFinite(observed) && observed > 0) {
      return observed;
    }
    return this.resolveEnginePercent(state);
  }

  private resolveEnginePercent(state: BrowserLargeScreenWebZoomTabState): number {
    if (Number.isFinite(state.enginePercent) && state.enginePercent > 0) {
      return state.enginePercent;
    }
    if (state.percent > 0) {
      return state.percent;
    }
    return BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT;
  }
}

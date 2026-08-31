import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';

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
  runtimeId: number;
  percentKnown: boolean;
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

  // 键盘 Ctrl +/-/0 与弹窗按钮走同一条“绝对缩放”执行路径：Aira 是页面缩放的唯一写入者，
  // 因此本地记录的百分比始终等于引擎真实比例，不会再漂移，也能可靠恢复默认（zoom(1)）。
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
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s apply id=%{public}d action=%{public}s tab=%{public}s currentPercent=%{public}d currentRuntimeId=%{public}d targetPercent=%{public}d',
      WEB_ZOOM_DIAG_PREFIX,
      traceId,
      action,
      normalizedTabId,
      currentState.percent,
      currentState.runtimeId,
      targetPercent
    );
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
    // 绝对缩放：controller.zoom(factor) 的 factor 相对“原始页面”，factor=1 即 100%（未缩放）。
    // 目标级别直接写入 zoom(targetPercent / 100)，恢复默认即 zoom(1)，无需依赖本地旧比例做相对推算，
    // 因此每一次都能精确落到目标级别、缩到最小档、真实归位，不会再出现 UI 与页面不一致。
    const execution = this.applyAbsoluteZoom(normalizedTabId, targetPercent, traceId);
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
    const changed = targetPercent !== currentState.percent;
    this.statesByTabId[normalizedTabId] = {
      percent: targetPercent,
      runtimeId: execution.runtimeId,
      percentKnown: true
    };
    this.revision += 1;
    this.publishRevision();
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s apply-result id=%{public}d applied=true changed=%{public}s percent=%{public}d runtimeId=%{public}d revision=%{public}d',
      WEB_ZOOM_DIAG_PREFIX,
      traceId,
      changed ? 'true' : 'false',
      targetPercent,
      execution.runtimeId,
      this.revision
    );
    return this.buildApplyResult(normalizedTabId, targetPercent, changed, true, '');
  }

  private resolveTabState(
    tabId: string,
    runtime: BrowserLargeScreenWebZoomRuntimeSnapshot
  ): BrowserLargeScreenWebZoomTabState {
    const storedState = this.statesByTabId[tabId];
    if (storedState === undefined) {
      return {
        percent: BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT,
        runtimeId: runtime.runtimeId,
        percentKnown: true
      };
    }
    if (runtime.available && storedState.runtimeId > 0 && runtime.runtimeId !== storedState.runtimeId) {
      const resetState: BrowserLargeScreenWebZoomTabState = {
        percent: BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT,
        runtimeId: runtime.runtimeId,
        percentKnown: true
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

  private applyAbsoluteZoom(
    tabId: string,
    percent: number,
    traceId: number
  ): BrowserLargeScreenWebZoomExecutionResult {
    // factor 相对“原始页面”，非相对当前缩放：percent=100 → zoom(1)（恢复默认），percent=25 → zoom(0.25)。
    // 公开 API 文档明确 “The value 1 indicates that the page is not zoomed. Value range: (0, 100]”。
    const factor = percent / BROWSER_LARGE_SCREEN_WEB_ZOOM_DEFAULT_PERCENT;
    if (!Number.isFinite(factor) || factor <= 0 || factor > 100) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s zoom-call id=%{public}d tab=%{public}s percent=%{public}d factor=%{public}s outcome=invalid-factor',
        WEB_ZOOM_DIAG_PREFIX,
        traceId,
        tabId,
        percent,
        factor.toString()
      );
      return { applied: false, runtimeId: -1, reason: 'invalid_factor' };
    }
    const runtime = this.resolveRuntime(tabId, 'zoom-call', traceId);
    if (!runtime.available) {
      return { applied: false, runtimeId: runtime.runtimeId, reason: runtime.reason };
    }
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    if (controller === undefined) {
      return { applied: false, runtimeId: -1, reason: 'missing_controller' };
    }
    hilog.info(
      WEB_ZOOM_DIAG_DOMAIN,
      WEB_ZOOM_DIAG_TAG,
      '%{public}s zoom-call id=%{public}d tab=%{public}s runtimeId=%{public}d percent=%{public}d factor=%{public}s outcome=invoke',
      WEB_ZOOM_DIAG_PREFIX,
      traceId,
      tabId,
      runtime.runtimeId,
      percent,
      factor.toString()
    );
    try {
      controller.zoom(factor);
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s zoom-call id=%{public}d tab=%{public}s runtimeId=%{public}d percent=%{public}d factor=%{public}s outcome=returned',
        WEB_ZOOM_DIAG_PREFIX,
        traceId,
        tabId,
        runtime.runtimeId,
        percent,
        factor.toString()
      );
      return { applied: true, runtimeId: runtime.runtimeId, reason: '' };
    } catch (_error) {
      hilog.info(
        WEB_ZOOM_DIAG_DOMAIN,
        WEB_ZOOM_DIAG_TAG,
        '%{public}s zoom-call id=%{public}d tab=%{public}s runtimeId=%{public}d percent=%{public}d factor=%{public}s outcome=threw',
        WEB_ZOOM_DIAG_PREFIX,
        traceId,
        tabId,
        runtime.runtimeId,
        percent,
        factor.toString()
      );
      return { applied: false, runtimeId: runtime.runtimeId, reason: 'platform_error' };
    }
  }
}

import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserTabPageBehaviorPrioritySignal,
  BrowserTabPageBehaviorPrioritySummary,
  BrowserTabPageBehaviorState,
  PAGE_BEHAVIOR_PRIORITY_DOWNLOAD,
  PAGE_BEHAVIOR_PRIORITY_EDITING,
  PAGE_BEHAVIOR_PRIORITY_MEDIA,
  PAGE_BEHAVIOR_PRIORITY_SCREEN_CAPTURE
} from './BrowserTabBackgroundTypes';

export type BrowserRuntimeTransactionKind =
  'screen_capture' |
  'media' |
  'auth' |
  'payment' |
  'form' |
  'download' |
  'permission' |
  'file_selector';

export type BrowserRuntimeTransactionSignalSource =
  'explicit' |
  'page_state' |
  'heuristic';

export interface BrowserRuntimeTransactionSignal {
  kind: BrowserRuntimeTransactionKind;
  source: BrowserRuntimeTransactionSignalSource;
  reason: string;
}

export interface BrowserRuntimeProtectionPlanInput {
  tabs: BrowserTabState[];
  activeTabId: string;
  activeDownloadCount: number;
  explicitReasonsByTabId?: Record<string, string>;
  pageBehaviorByTabId?: Record<string, BrowserTabPageBehaviorState>;
}

export interface BrowserRuntimeProtectionSummary {
  total: number;
  explicitCount: number;
  pageStateCount: number;
  heuristicCount: number;
  downloadCount: number;
  permissionCount: number;
  fileSelectorCount: number;
  screenCaptureCount: number;
  mediaCount: number;
  authCount: number;
  paymentCount: number;
  formCount: number;
  tabIds: string[];
  summaryLine: string;
}

export class BrowserRuntimeTransactionSignalService {
  buildProtectionReasons(input: BrowserRuntimeProtectionPlanInput): Record<string, string> {
    const signals = this.buildProtectionSignals(input);
    const reasons: Record<string, string> = {};
    Object.keys(signals).forEach((tabId: string) => {
      reasons[tabId] = this.formatSignal(signals[tabId]);
    });
    return reasons;
  }

  buildProtectionSummary(input: BrowserRuntimeProtectionPlanInput): BrowserRuntimeProtectionSummary {
    const signals = this.buildProtectionSignals(input);
    const tabIds = Object.keys(signals);
    let explicitCount = 0;
    let pageStateCount = 0;
    let heuristicCount = 0;
    let downloadCount = 0;
    let permissionCount = 0;
    let fileSelectorCount = 0;
    let screenCaptureCount = 0;
    let mediaCount = 0;
    let authCount = 0;
    let paymentCount = 0;
    let formCount = 0;
    tabIds.forEach((tabId: string) => {
      const signal = signals[tabId];
      if (signal.source === 'explicit') {
        explicitCount += 1;
      } else if (signal.source === 'page_state') {
        pageStateCount += 1;
      } else if (signal.source === 'heuristic') {
        heuristicCount += 1;
      }
      switch (signal.kind) {
        case 'download':
          downloadCount += 1;
          break;
        case 'permission':
          permissionCount += 1;
          break;
        case 'file_selector':
          fileSelectorCount += 1;
          break;
        case 'screen_capture':
          screenCaptureCount += 1;
          break;
        case 'media':
          mediaCount += 1;
          break;
        case 'auth':
          authCount += 1;
          break;
        case 'payment':
          paymentCount += 1;
          break;
        case 'form':
          formCount += 1;
          break;
      }
    });
    const summaryLine = `runtimeProtection total=${tabIds.length} explicit=${explicitCount} pageState=${pageStateCount} ` +
      `heuristic=${heuristicCount} download=${downloadCount} permission=${permissionCount} fileSelector=${fileSelectorCount} ` +
      `screenCapture=${screenCaptureCount} media=${mediaCount} auth=${authCount} payment=${paymentCount} ` +
      `form=${formCount} tabs=${tabIds.join(',') || 'none'}`;
    return {
      total: tabIds.length,
      explicitCount: explicitCount,
      pageStateCount: pageStateCount,
      heuristicCount: heuristicCount,
      downloadCount: downloadCount,
      permissionCount: permissionCount,
      fileSelectorCount: fileSelectorCount,
      screenCaptureCount: screenCaptureCount,
      mediaCount: mediaCount,
      authCount: authCount,
      paymentCount: paymentCount,
      formCount: formCount,
      tabIds: tabIds,
      summaryLine: summaryLine
    };
  }

  buildProtectionSignals(input: BrowserRuntimeProtectionPlanInput): Record<string, BrowserRuntimeTransactionSignal> {
    const signals: Record<string, BrowserRuntimeTransactionSignal> = {};
    const explicitReasonsByTabId = input.explicitReasonsByTabId ?? {};
    Object.keys(explicitReasonsByTabId).forEach((tabId: string) => {
      const reason = explicitReasonsByTabId[tabId] ?? '';
      if (reason.length > 0) {
        signals[tabId] = this.resolveExplicitSignal(reason);
      }
    });
    const pageBehaviorByTabId = input.pageBehaviorByTabId ?? {};
    Object.keys(pageBehaviorByTabId).forEach((tabId: string) => {
      if (signals[tabId] !== undefined) {
        return;
      }
      const signal = this.resolvePageBehaviorSignal(pageBehaviorByTabId[tabId]);
      if (signal !== undefined) {
        signals[tabId] = signal;
      }
    });
    if (input.activeDownloadCount > 0 && input.activeTabId.length > 0) {
      signals[input.activeTabId] = {
        kind: 'download',
        source: 'explicit',
        reason: '当前窗口存在进行中的下载任务，暂不回收活动下载相关 runtime。'
      };
    }
    input.tabs.forEach((tab: BrowserTabState) => {
      if (signals[tab.id] !== undefined) {
        return;
      }
      const reason = this.resolveProtectionReason(tab, input.activeTabId);
      if (reason.length > 0) {
        const signal = this.resolveSignal(tab);
        if (signal !== undefined) {
          signals[tab.id] = signal;
        }
      }
    });
    return signals;
  }

  resolveSignal(tab: BrowserTabState, explicitReason: string = '', activeDownloadCount: number = 0): BrowserRuntimeTransactionSignal | undefined {
    if (tab.isHome || tab.runtimeState === 'cold' || tab.runtimeState === 'discarded' || tab.runtimeState === 'suspended') {
      return undefined;
    }
    if (explicitReason.length > 0) {
      return this.resolveExplicitSignal(explicitReason);
    }
    if (activeDownloadCount > 0) {
      return {
        kind: 'download',
        source: 'explicit',
        reason: '当前窗口存在进行中的下载任务，暂不回收活动下载相关 runtime。'
      };
    }
    return this.resolveHeuristicSignal(tab);
  }

  formatSignal(signal: BrowserRuntimeTransactionSignal): string {
    return `${signal.reason} signal=${signal.kind} source=${signal.source}`;
  }

  resolveProtectionReason(tab: BrowserTabState, activeTabId: string): string {
    if (tab.isHome || tab.id === activeTabId || tab.runtimeState === 'cold' || tab.runtimeState === 'discarded' ||
      tab.runtimeState === 'suspended') {
      return '';
    }
    const signal = this.resolveSignal(tab, '', 0);
    if (signal === undefined) {
      return '';
    }
    return this.formatSignal(signal);
  }

  private resolveExplicitSignal(reason: string): BrowserRuntimeTransactionSignal {
    const normalized = reason.toLowerCase();
    if (this.containsAny(normalized, ['文件', 'file'])) {
      return {
        kind: 'file_selector',
        source: 'explicit',
        reason: reason
      };
    }
    if (this.containsAny(normalized, ['权限', 'permission', '定位', '摄像', '麦克风'])) {
      return {
        kind: 'permission',
        source: 'explicit',
        reason: reason
      };
    }
    if (this.containsAny(normalized, ['下载', 'download'])) {
      return {
        kind: 'download',
        source: 'explicit',
        reason: reason
      };
    }
    if (this.containsAny(normalized, ['录屏', '投屏', 'screen', 'capture'])) {
      return {
        kind: 'screen_capture',
        source: 'explicit',
        reason: reason
      };
    }
    if (this.containsAny(normalized, ['认证', 'auth', '证书', 'ssl'])) {
      return {
        kind: 'auth',
        source: 'explicit',
        reason: reason
      };
    }
    return {
      kind: 'form',
      source: 'explicit',
      reason: reason
    };
  }

  private resolveHeuristicSignal(tab: BrowserTabState): BrowserRuntimeTransactionSignal | undefined {
    const signal = `${tab.url} ${tab.pendingUrl} ${tab.title}`.toLowerCase();
    if (this.containsAny(signal, ['video', 'music', 'audio', 'player', 'live', 'media', '播放', '音乐', '视频', '直播'])) {
      return {
        kind: 'media',
        source: 'heuristic',
        reason: '疑似媒体播放标签页，暂不回收 runtime。'
      };
    }
    if (this.containsAny(signal, ['login', 'signin', 'sign-in', 'account', 'auth', 'passport', '登录', '账户', '验证'])) {
      return {
        kind: 'auth',
        source: 'heuristic',
        reason: '疑似登录验证流程，暂不回收 runtime。'
      };
    }
    if (this.containsAny(signal, ['pay', 'checkout', 'order', 'billing', 'alipay', 'wechatpay', '支付', '订单', '收银台'])) {
      return {
        kind: 'payment',
        source: 'heuristic',
        reason: '疑似支付或订单流程，暂不回收 runtime。'
      };
    }
    if (this.containsAny(signal, ['form', 'submit', 'editor', 'compose', 'draft', '表单', '提交', '编辑', '草稿'])) {
      return {
        kind: 'form',
        source: 'heuristic',
        reason: '疑似表单编辑流程，暂不回收 runtime。'
      };
    }
    return undefined;
  }

  private resolvePageBehaviorSignal(
    state: BrowserTabPageBehaviorState | undefined
  ): BrowserRuntimeTransactionSignal | undefined {
    const prioritySummary = this.resolvePageBehaviorPrioritySummary(state);
    if (prioritySummary === undefined) {
      return undefined;
    }
    return {
      kind: this.mapPageBehaviorKindToRuntimeKind(prioritySummary.primaryKind),
      source: 'page_state',
      reason: this.formatPageBehaviorProtectionReason(state)
    };
  }

  resolvePageBehaviorPrioritySummary(
    state: BrowserTabPageBehaviorState | undefined
  ): BrowserTabPageBehaviorPrioritySummary | undefined {
    if (state === undefined) {
      return undefined;
    }
    const signals: BrowserTabPageBehaviorPrioritySignal[] = [];
    if (state.isScreenCapture) {
      signals.push({
        kind: 'screen_capture',
        priority: PAGE_BEHAVIOR_PRIORITY_SCREEN_CAPTURE
      });
    }
    if (state.isMediaPlaying) {
      signals.push({
        kind: 'media',
        priority: PAGE_BEHAVIOR_PRIORITY_MEDIA
      });
    }
    if (state.isUserEditing) {
      signals.push({
        kind: 'editing',
        priority: PAGE_BEHAVIOR_PRIORITY_EDITING
      });
    }
    if (state.isDownloading) {
      signals.push({
        kind: 'download',
        priority: PAGE_BEHAVIOR_PRIORITY_DOWNLOAD
      });
    }
    if (signals.length <= 0) {
      return undefined;
    }
    let totalPriority = 0;
    signals.forEach((signal: BrowserTabPageBehaviorPrioritySignal) => {
      totalPriority += signal.priority;
    });
    return {
      signals: signals,
      totalPriority: totalPriority,
      primaryKind: signals[0].kind
    };
  }

  formatPageBehaviorProtectionReason(state: BrowserTabPageBehaviorState | undefined): string {
    const prioritySummary = this.resolvePageBehaviorPrioritySummary(state);
    if (prioritySummary === undefined) {
      return '';
    }
    return '页面行为保护：标签页存在受保护页面行为，暂不回收 runtime。 ' +
      `signals=${this.formatPageBehaviorSignalList(prioritySummary)} behaviorScore=${prioritySummary.totalPriority}`;
  }

  formatPageBehaviorSignalList(prioritySummary: BrowserTabPageBehaviorPrioritySummary | undefined): string {
    if (prioritySummary === undefined || prioritySummary.signals.length <= 0) {
      return 'none';
    }
    return prioritySummary.signals
      .map((signal: BrowserTabPageBehaviorPrioritySignal): string => `${signal.kind}:${signal.priority}`)
      .join(',');
  }

  private mapPageBehaviorKindToRuntimeKind(kind: string): BrowserRuntimeTransactionKind {
    if (kind === 'screen_capture') {
      return 'screen_capture';
    }
    if (kind === 'media') {
      return 'media';
    }
    if (kind === 'download') {
      return 'download';
    }
    return 'form';
  }

  private containsAny(value: string, keywords: string[]): boolean {
    return keywords.some((keyword: string) => value.indexOf(keyword) >= 0);
  }
}

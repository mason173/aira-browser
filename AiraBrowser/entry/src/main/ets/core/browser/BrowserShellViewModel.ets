import { BrowserTabState } from '../tabs/TabManager';

export type BrowserRuntimeTone = 'primary' | 'secondary' | 'warning';

export interface BrowserTabRuntimePresentation {
  label: string;
  helperMessage: string;
  tone: BrowserRuntimeTone;
  evidenceLine: string;
}

export interface BrowserTabRuntimeEvidenceInput {
  retentionReason?: string;
  retentionScore?: number;
  restorePriority?: number;
  isWebStateRestoreCandidate?: boolean;
  hasLiveController?: boolean;
}

export class BrowserShellViewModel {
  resolveLiveRuntimeHelperMessage(
    tab: BrowserTabState,
    activeTabId: string,
    helperMessage: string
  ): string {
    if (helperMessage.length > 0) {
      return helperMessage;
    }
    return this.getTabRuntimePresentation(tab, activeTabId).helperMessage;
  }

  getTabRuntimePresentation(
    tab: BrowserTabState,
    activeTabId: string,
    evidence: BrowserTabRuntimeEvidenceInput = {}
  ): BrowserTabRuntimePresentation {
    return {
      label: this.getRuntimeLabel(tab, activeTabId),
      helperMessage: this.getRuntimeHelperMessage(tab),
      tone: this.getRuntimeTone(tab),
      evidenceLine: this.buildTabRuntimeEvidenceLine(tab, activeTabId, evidence)
    };
  }

  buildTabRuntimeEvidenceLine(
    tab: BrowserTabState,
    activeTabId: string,
    evidence: BrowserTabRuntimeEvidenceInput = {}
  ): string {
    const isWebStateRestoreCandidate = evidence.isWebStateRestoreCandidate ?? false;
    const hasLiveController = evidence.hasLiveController ?? false;
    const retentionReason = this.normalizeEvidenceValue(evidence.retentionReason ?? '');
    const retentionScore = evidence.retentionScore ?? 0;
    const restorePriority = evidence.restorePriority ?? 0;
    return `tabRuntime tab=${tab.id} active=${tab.id === activeTabId ? 'true' : 'false'} state=${tab.runtimeState} ` +
      `discard=${tab.lastDiscardReason.length > 0 ? tab.lastDiscardReason : 'none'} webStateRestoreCandidate=${isWebStateRestoreCandidate ? 'true' : 'false'} ` +
      `live=${hasLiveController ? 'true' : 'false'} score=${retentionScore} restorePriority=${restorePriority} ` +
      `reason=${retentionReason.length > 0 ? retentionReason : 'none'}`;
  }

  private normalizeEvidenceValue(value: string): string {
    return value.trim().split(' ').join('_');
  }

  private getRuntimeLabel(tab: BrowserTabState, activeTabId: string): string {
    switch (tab.runtimeState) {
      case 'active':
        return tab.id === activeTabId ? '当前活动中' : '已就绪';
      case 'background-hot':
        return '后台保热';
      case 'background-warm':
        return '后台温态';
      case 'cold':
        if (tab.lastDiscardReason === 'retention_stale') {
          return '已过期冷却';
        }
        if (tab.lastDiscardReason === 'retention_budget' || tab.lastDiscardReason === 'retention_cold') {
          return '已冷却待恢复';
        }
        return '已冷却';
      case 'discarded':
        if (tab.lastDiscardReason === 'retention_stale' || tab.lastDiscardReason === 'retention_budget' ||
          tab.lastDiscardReason === 'retention_cold') {
          return '已回收待恢复';
        }
        return '已回收';
      case 'crashed':
        return this.getCrashLabel(tab);
      case 'loading':
        return '正在加载';
      case 'restoring':
        return '正在恢复页面';
      case 'error':
        return tab.lastError.length > 0 ? `加载失败：${tab.lastError}` : '加载失败';
      case 'background':
        return '后台待命';
      case 'suspended':
        return '已挂起';
      default:
        return '状态未知';
    }
  }

  private getRuntimeHelperMessage(tab: BrowserTabState): string {
    switch (tab.runtimeState) {
      case 'restoring':
        return this.getRestoreHelperMessage(tab);
      case 'loading':
        return '标签页正在加载';
      case 'error':
        return '标签页上次加载失败';
      case 'background-hot':
        return '标签页保留在热运行态';
      case 'background-warm':
        return '标签页已降为温态，切回时会优先恢复';
      case 'cold':
        if (tab.lastDiscardReason === 'retention_stale') {
          return '标签页长时间后台停留，已主动冷却释放内存';
        }
        if (tab.lastDiscardReason === 'retention_budget') {
          return '标签页超出后台保活预算，切回时会恢复';
        }
        return '标签页已冷却，切回时会重新恢复';
      case 'discarded':
        if (tab.lastDiscardReason === 'retention_stale') {
          return '标签页后台停留过久，已正式回收 live runtime，切回时会恢复';
        }
        if (tab.lastDiscardReason === 'retention_budget' || tab.lastDiscardReason === 'retention_cold') {
          return '标签页已被后台回收释放 live runtime，切回时会恢复';
        }
        return '标签页已被后台回收，切回时会重新恢复';
      case 'crashed':
        return this.getCrashHelperMessage(tab);
      case 'suspended':
      case 'background':
      case 'active':
      default:
        return '已切换标签页';
    }
  }

  private getRuntimeTone(tab: BrowserTabState): BrowserRuntimeTone {
    if (tab.runtimeState === 'error' || tab.runtimeState === 'crashed') {
      return 'warning';
    }
    if (tab.runtimeState === 'active' || tab.runtimeState === 'loading' || tab.runtimeState === 'restoring') {
      return 'primary';
    }
    return 'secondary';
  }

  private getRestoreHelperMessage(tab: BrowserTabState): string {
    switch (tab.lastRestoreReason) {
      case 'controller_attach':
        return '控制器已接管，正在恢复标签页内容';
      case 'tab_switch':
        return '正在切回标签页内容';
      case 'discard_restore':
        return '正在恢复已回收标签页';
      case 'crash_restore':
        return '正在从异常状态恢复标签页';
      case 'snapshot_restore':
        return '正在从页面快照恢复标签页';
      case 'snapshot_fallback_reload':
        return '快照恢复不可用，正在重新加载页面';
      case 'cold_start':
        return '正在恢复上次浏览会话';
      case 'manual_reload':
        return '正在重新加载页面';
      case 'external_launch':
        return '正在处理系统交给浏览器的链接';
      default:
        return '正在恢复标签页内容';
    }
  }

  private getCrashLabel(tab: BrowserTabState): string {
    switch (tab.lastCrashReason) {
      case 'snapshot_restore_failed':
        return '恢复异常';
      case 'navigation_failed':
        return '导航异常';
      case 'render_process_terminated':
        return '渲染中断';
      default:
        return '渲染异常';
    }
  }

  private getCrashHelperMessage(tab: BrowserTabState): string {
    switch (tab.lastCrashReason) {
      case 'snapshot_restore_failed':
        return '标签页快照恢复失败，等待重新加载';
      case 'navigation_failed':
        return '标签页导航失败，等待重新恢复';
      case 'render_process_terminated':
        return '标签页渲染进程已终止，等待恢复';
      case 'main_frame_error':
        return '主框架加载失败，标签页已进入保护态';
      case 'recovery_degraded_to_home':
        return '标签页连续恢复失败，已回到首页';
      default:
        return '标签页运行时异常，等待恢复';
    }
  }
}

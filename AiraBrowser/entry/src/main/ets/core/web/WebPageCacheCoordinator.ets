import { WebSessionRestoreType } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { WebTabRuntimeRecord } from './WebTabRuntime';

export type WebPageCacheRestoreType = WebSessionRestoreType;
export type WebPageCacheDecisionKind = 'none' | 'live_hit' | 'snapshot_fallback' | 'reload_fallback';

export interface WebPageCacheActivationPlan {
  restoreType: WebPageCacheRestoreType;
  decisionKind: WebPageCacheDecisionKind;
  reasonCode: string;
  diagnosticLine: string;
  shouldReuseLiveRuntime: boolean;
  shouldRestoreActiveSession: boolean;
  helperMessage: string;
}

export class WebPageCacheCoordinator {
  resolveActivation(tab: BrowserTabState, runtime: WebTabRuntimeRecord): WebPageCacheActivationPlan {
    if (this.canReuseLiveRuntime(tab, runtime)) {
      return {
        restoreType: 'live_page_cache',
        decisionKind: 'live_hit',
        reasonCode: 'live_controller_available',
        diagnosticLine: this.buildDiagnosticLine('live_hit', 'live_controller_available', tab, runtime),
        shouldReuseLiveRuntime: true,
        shouldRestoreActiveSession: false,
        helperMessage: '命中页面缓存，已快速切回。'
      };
    }

    if (tab.webStatePath.length > 0) {
      return {
        restoreType: 'snapshot_restore',
        decisionKind: 'snapshot_fallback',
        reasonCode: this.resolveLiveRuntimeMissReason(tab, runtime),
        diagnosticLine: this.buildDiagnosticLine(
          'snapshot_fallback',
          this.resolveLiveRuntimeMissReason(tab, runtime),
          tab,
          runtime
        ),
        shouldReuseLiveRuntime: false,
        shouldRestoreActiveSession: runtime.hasLiveController,
        helperMessage: '准备从页面快照恢复。'
      };
    }

    return {
      restoreType: 'reload',
      decisionKind: 'reload_fallback',
      reasonCode: this.resolveLiveRuntimeMissReason(tab, runtime),
      diagnosticLine: this.buildDiagnosticLine('reload_fallback', this.resolveLiveRuntimeMissReason(tab, runtime), tab, runtime),
      shouldReuseLiveRuntime: false,
      shouldRestoreActiveSession: runtime.hasLiveController,
      helperMessage: '页面缓存不可用，准备重新加载。'
    };
  }

  private canReuseLiveRuntime(tab: BrowserTabState, runtime: WebTabRuntimeRecord): boolean {
    if (!runtime.hasLiveController) {
      return false;
    }
    return tab.runtimeState !== 'cold' &&
      tab.runtimeState !== 'discarded' &&
      tab.runtimeState !== 'crashed' &&
      tab.runtimeState !== 'restoring';
  }

  private resolveLiveRuntimeMissReason(tab: BrowserTabState, runtime: WebTabRuntimeRecord): string {
    if (!runtime.hasLiveController) {
      return 'live_controller_missing';
    }
    if (tab.runtimeState === 'cold') {
      return 'tab_runtime_cold';
    }
    if (tab.runtimeState === 'discarded') {
      return 'tab_runtime_discarded';
    }
    if (tab.runtimeState === 'crashed') {
      return 'tab_runtime_crashed';
    }
    if (tab.runtimeState === 'restoring') {
      return 'tab_runtime_restoring';
    }
    if (tab.runtimeState === 'suspended') {
      return 'tab_runtime_suspended';
    }
    return 'live_runtime_not_reusable';
  }

  private buildDiagnosticLine(
    decisionKind: WebPageCacheDecisionKind,
    reasonCode: string,
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord
  ): string {
    return `decision=${decisionKind} reason=${reasonCode} restoreType=${decisionKind === 'live_hit' ? 'live_page_cache' : tab.webStatePath.length > 0 ? 'snapshot_restore' : 'reload'} state=${tab.runtimeState} live=${runtime.hasLiveController} snapshot=${tab.webStatePath.length > 0}`;
  }
}

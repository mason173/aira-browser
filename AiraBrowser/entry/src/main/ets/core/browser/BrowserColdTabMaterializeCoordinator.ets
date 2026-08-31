import { TabRestoreReason } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { WebPageCacheActivationPlan } from '../web/WebPageCacheCoordinator';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';

export type BrowserColdTabMaterializeReason =
  'none' |
  'cold_start_old_tab' |
  'cold_tab' |
  'discarded_tab' |
  'suspended_tab' |
  'restoring_tab' |
  'crashed_tab' |
  'missing_live_controller' |
  'live_runtime_not_reusable';

export interface BrowserColdTabMaterializePlan {
  shouldMaterialize: boolean;
  reasonCode: BrowserColdTabMaterializeReason;
  restoreReason: TabRestoreReason;
  diagnosticLine: string;
}

export class BrowserColdTabMaterializeCoordinator {
  buildMaterializePlan(
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord,
    activationPlan: WebPageCacheActivationPlan,
    fallbackRestoreReason: TabRestoreReason = 'tab_switch'
  ): BrowserColdTabMaterializePlan {
    if (activationPlan.shouldReuseLiveRuntime || activationPlan.restoreType === 'none') {
      return this.buildPlan(false, 'none', fallbackRestoreReason, activationPlan.diagnosticLine);
    }
    const reasonCode = this.resolveMaterializeReason(tab, runtime);
    return this.buildPlan(
      reasonCode !== 'none',
      reasonCode,
      this.resolveRestoreReason(tab, reasonCode, fallbackRestoreReason),
      activationPlan.diagnosticLine
    );
  }

  resolveControllerAttachRestoreReason(
    tab: BrowserTabState | undefined,
    fallbackRestoreReason: TabRestoreReason = 'controller_attach'
  ): TabRestoreReason {
    if (tab === undefined) {
      return fallbackRestoreReason;
    }
    if (tab.lastRestoreReason === 'cold_start') {
      return 'cold_start';
    }
    return fallbackRestoreReason;
  }

  private resolveMaterializeReason(
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord
  ): BrowserColdTabMaterializeReason {
    if (tab.lastRestoreReason === 'cold_start') {
      return 'cold_start_old_tab';
    }
    if (tab.runtimeState === 'cold') {
      return 'cold_tab';
    }
    if (tab.runtimeState === 'discarded') {
      return 'discarded_tab';
    }
    if (tab.runtimeState === 'suspended') {
      return 'suspended_tab';
    }
    if (tab.runtimeState === 'restoring') {
      return 'restoring_tab';
    }
    if (tab.runtimeState === 'crashed' || tab.runtimeState === 'error') {
      return 'crashed_tab';
    }
    if (!runtime.hasLiveController) {
      return 'missing_live_controller';
    }
    return 'live_runtime_not_reusable';
  }

  private resolveRestoreReason(
    tab: BrowserTabState,
    reasonCode: BrowserColdTabMaterializeReason,
    fallbackRestoreReason: TabRestoreReason
  ): TabRestoreReason {
    if (reasonCode === 'cold_start_old_tab') {
      return 'cold_start';
    }
    if (reasonCode === 'crashed_tab') {
      return 'crash_restore';
    }
    if (tab.lastDiscardReason.length > 0 || reasonCode === 'discarded_tab') {
      return 'discard_restore';
    }
    return fallbackRestoreReason;
  }

  private buildPlan(
    shouldMaterialize: boolean,
    reasonCode: BrowserColdTabMaterializeReason,
    restoreReason: TabRestoreReason,
    pageCacheDiagnosticLine: string
  ): BrowserColdTabMaterializePlan {
    return {
      shouldMaterialize: shouldMaterialize,
      reasonCode: reasonCode,
      restoreReason: restoreReason,
      diagnosticLine: `materialize=${shouldMaterialize ? 1 : 0} reason=${reasonCode} ` +
        `restoreReason=${restoreReason} ${pageCacheDiagnosticLine}`
    };
  }
}

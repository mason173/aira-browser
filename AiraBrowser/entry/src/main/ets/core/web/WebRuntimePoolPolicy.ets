import { TabDiscardReason, TabRuntimeState } from '../../common/models/BrowserModels';
import { BrowserRuntimeStateTransitionTable } from '../browser/BrowserRuntimeStateTransitionTable';
import { BrowserTabState } from '../tabs/TabManager';

export interface WebRuntimePoolPolicyConfig {
  maxHotBackgroundTabs: number;
  maxWarmBackgroundTabs: number;
}

export type WebRuntimeRetentionPressureLevel =
  'idle' |
  'low' |
  'medium' |
  'high';

export interface WebRuntimeRetentionPressureAssist {
  level: WebRuntimeRetentionPressureLevel;
  extraWarmSlots: number;
  extraMountedSlots: number;
  warmTabIds: string[];
  mountedTabIds: string[];
  summaryLine: string;
}

export interface WebRuntimeRetentionSiteComplexitySummary {
  complexTabCount: number;
  topTabId: string;
  topScore: number;
  topLevel: string;
  retainedTabIds: string[];
  webStateRestoreCandidateTabIds: string[];
  summaryLine: string;
}

export interface WebRuntimeRetentionPlan {
  activeTabId: string;
  mountedTabIds: string[];
  hotTabIds: string[];
  warmTabIds: string[];
  coldTabIds: string[];
  forcedDiscardTabIds: string[];
  webStateRestoreCandidateTabIds: string[];
  runtimeStates: Record<string, TabRuntimeState>;
  retentionReasonsByTabId: Record<string, string>;
  retentionScoresByTabId: Record<string, number>;
  restorePrioritiesByTabId: Record<string, number>;
  nonReclaimableReasonsByTabId: Record<string, string>;
  discardReasonsByTabId: Record<string, TabDiscardReason | ''>;
  pressureAssist?: WebRuntimeRetentionPressureAssist;
  siteComplexitySummary?: WebRuntimeRetentionSiteComplexitySummary;
}

const DEFAULT_POLICY_CONFIG: WebRuntimePoolPolicyConfig = {
  maxHotBackgroundTabs: 5,
  maxWarmBackgroundTabs: 10
};

export class WebRuntimePoolPolicy {
  private config: WebRuntimePoolPolicyConfig;
  private runtimeStateTransitionTable: BrowserRuntimeStateTransitionTable = new BrowserRuntimeStateTransitionTable();

  constructor(config: WebRuntimePoolPolicyConfig = DEFAULT_POLICY_CONFIG) {
    this.config = config;
  }

  updateConfig(config: WebRuntimePoolPolicyConfig): void {
    this.config = {
      maxHotBackgroundTabs: config.maxHotBackgroundTabs,
      maxWarmBackgroundTabs: config.maxWarmBackgroundTabs
    };
  }

  buildPlan(tabs: BrowserTabState[], activeTabId: string): WebRuntimeRetentionPlan {
    const runtimeStates: Record<string, TabRuntimeState> = {};
    const mountedTabIds: string[] = [];
    const hotTabIds: string[] = [];
    const warmTabIds: string[] = [];
    const coldTabIds: string[] = [];
    const forcedDiscardTabIds: string[] = [];
    const nonReclaimableReasonsByTabId: Record<string, string> = {};
    const retentionReasonsByTabId: Record<string, string> = {};
    const retentionScoresByTabId: Record<string, number> = {};
    const restorePrioritiesByTabId: Record<string, number> = {};
    const discardReasonsByTabId: Record<string, TabDiscardReason | ''> = {};

    const activeTab = tabs.find((tab: BrowserTabState) => tab.id === activeTabId);
    if (activeTab !== undefined && !activeTab.isHome) {
      runtimeStates[activeTab.id] = this.resolveActiveRuntimeState(activeTab);
      mountedTabIds.push(activeTab.id);
      retentionReasonsByTabId[activeTab.id] = '前台活动标签页。';
      retentionScoresByTabId[activeTab.id] = 1000;
      restorePrioritiesByTabId[activeTab.id] = 1000;
      discardReasonsByTabId[activeTab.id] = '';
    }

    const backgroundTabs = tabs
      .filter((tab: BrowserTabState) => !tab.isHome && tab.id !== activeTabId)
      .sort((left: BrowserTabState, right: BrowserTabState) => right.lastActiveAt - left.lastActiveAt);

    backgroundTabs.forEach((tab: BrowserTabState, index: number) => {
      const pinnedState = this.resolvePinnedBackgroundState(tab);
      if (pinnedState !== undefined) {
        runtimeStates[tab.id] = pinnedState;
        retentionReasonsByTabId[tab.id] = '异常标签页保持当前保护状态。';
        retentionScoresByTabId[tab.id] = 120;
        restorePrioritiesByTabId[tab.id] = 80;
        discardReasonsByTabId[tab.id] = '';
        return;
      }

      if (index < this.config.maxHotBackgroundTabs) {
        runtimeStates[tab.id] = 'background-hot';
        mountedTabIds.push(tab.id);
        hotTabIds.push(tab.id);
        retentionReasonsByTabId[tab.id] = '后台热态保留。';
        retentionScoresByTabId[tab.id] = 320 - index * 10;
        restorePrioritiesByTabId[tab.id] = 900 - index * 20;
        discardReasonsByTabId[tab.id] = '';
        return;
      }

      if (index < this.config.maxHotBackgroundTabs + this.config.maxWarmBackgroundTabs) {
        runtimeStates[tab.id] = 'background-warm';
        warmTabIds.push(tab.id);
        retentionReasonsByTabId[tab.id] = '后台温态保留。';
        retentionScoresByTabId[tab.id] = 220 - index * 10;
        restorePrioritiesByTabId[tab.id] = 700 - index * 20;
        discardReasonsByTabId[tab.id] = '';
        return;
      }

      runtimeStates[tab.id] = 'cold';
      coldTabIds.push(tab.id);
      retentionReasonsByTabId[tab.id] = '超出后台保活预算。';
      retentionScoresByTabId[tab.id] = 100 - index * 10;
      restorePrioritiesByTabId[tab.id] = tab.webStatePath.length > 0 ? 420 - index * 10 : 260 - index * 10;
      discardReasonsByTabId[tab.id] = 'retention_cold';
    });

    return {
      activeTabId: activeTabId,
      mountedTabIds: mountedTabIds,
      hotTabIds: hotTabIds,
      warmTabIds: warmTabIds,
      coldTabIds: coldTabIds,
      forcedDiscardTabIds: forcedDiscardTabIds,
      webStateRestoreCandidateTabIds: this.buildWebStateRestoreCandidates(coldTabIds, restorePrioritiesByTabId),
      runtimeStates: runtimeStates,
      retentionReasonsByTabId: retentionReasonsByTabId,
      retentionScoresByTabId: retentionScoresByTabId,
      restorePrioritiesByTabId: restorePrioritiesByTabId,
      nonReclaimableReasonsByTabId: nonReclaimableReasonsByTabId,
      discardReasonsByTabId: discardReasonsByTabId
    };
  }

  getConfig(): WebRuntimePoolPolicyConfig {
    return {
      maxHotBackgroundTabs: this.config.maxHotBackgroundTabs,
      maxWarmBackgroundTabs: this.config.maxWarmBackgroundTabs
    };
  }

  private resolveActiveRuntimeState(tab: BrowserTabState): TabRuntimeState {
    return this.runtimeStateTransitionTable.resolveForegroundState(tab.runtimeState, tab.isHome);
  }

  private resolvePinnedBackgroundState(tab: BrowserTabState): TabRuntimeState | undefined {
    if (tab.runtimeState === 'error' || tab.runtimeState === 'crashed') {
      return tab.runtimeState;
    }
    return undefined;
  }

  private buildWebStateRestoreCandidates(coldTabIds: string[], restorePrioritiesByTabId: Record<string, number>): string[] {
    return coldTabIds.slice().sort((left: string, right: string) => {
      return (restorePrioritiesByTabId[right] ?? 0) - (restorePrioritiesByTabId[left] ?? 0);
    });
  }
}

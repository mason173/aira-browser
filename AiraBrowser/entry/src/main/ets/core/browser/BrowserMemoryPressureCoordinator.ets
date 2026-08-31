import { TabDiscardReason, TabRuntimeState } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import {
  WebRuntimePoolPolicy,
  WebRuntimePoolPolicyConfig,
  WebRuntimeRetentionPlan,
  WebRuntimeRetentionPressureAssist,
  WebRuntimeRetentionPressureLevel,
  WebRuntimeRetentionSiteComplexitySummary
} from '../web/WebRuntimePoolPolicy';
import { BrowserRuntimeStateTransitionTable } from './BrowserRuntimeStateTransitionTable';
import { BrowserSiteComplexityScore, BrowserSiteComplexityScoringService } from './BrowserSiteComplexityScoringService';
import {
  BrowserSystemMemoryPressureLevel,
  BrowserTabAppLifecycleState,
  BrowserTabWindowVisibility
} from './BrowserTabBackgroundTypes';

export interface BrowserMemoryPressureConfig {
  staleAfterMs: number;
  unstableTabGraceMs: number;
  hotBackgroundMaxAgeMs: number;
  warmBackgroundMaxAgeMs: number;
  loadingTabGraceMs: number;
  maxMountedRuntimeTabs: number;
}

export interface BrowserMemoryPressureOptions {
  protectedReasonsByTabId?: Record<string, string>;
  windowVisibility?: BrowserTabWindowVisibility;
  appLifecycle?: BrowserTabAppLifecycleState;
  systemMemoryPressureLevel?: BrowserSystemMemoryPressureLevel;
}

interface ForcedColdDecision {
  discardReason: TabDiscardReason;
  reason: string;
}

interface NonReclaimableDecision {
  runtimeState: TabRuntimeState;
  mounted: boolean;
  reason: string;
}

interface BrowserBackgroundRetentionCandidate {
  tab: BrowserTabState;
  ageMs: number;
  complexity: BrowserSiteComplexityScore;
  retentionScore: number;
  restorePriority: number;
}

interface BrowserRetentionPressureAdjustment {
  pressureLevel: WebRuntimeRetentionPressureLevel;
  extraWarmSlots: number;
  extraMountedSlots: number;
}

interface BrowserLifecycleRetentionBudget {
  maxHotBackgroundTabs: number;
  maxWarmBackgroundTabs: number;
  maxMountedRuntimeTabs: number;
}

const HUAWEI_PHONE_NORMAL_RUNTIME_TAB_LIMIT: number = 15;
const HUAWEI_PHONE_MEMORY_PRESSURE_RUNTIME_TAB_LIMIT: number = 8;
const HUAWEI_PHONE_CRITICAL_RUNTIME_TAB_LIMIT: number = 3;
const HUAWEI_TAB_MAX_LIVE_TIME_MS: number = 24 * 60 * 60 * 1000;

const DEFAULT_BROWSER_MEMORY_PRESSURE_CONFIG: BrowserMemoryPressureConfig = {
  staleAfterMs: HUAWEI_TAB_MAX_LIVE_TIME_MS,
  unstableTabGraceMs: 3 * 60 * 1000,
  hotBackgroundMaxAgeMs: 30 * 60 * 1000,
  warmBackgroundMaxAgeMs: HUAWEI_TAB_MAX_LIVE_TIME_MS,
  loadingTabGraceMs: 45 * 1000,
  maxMountedRuntimeTabs: HUAWEI_PHONE_NORMAL_RUNTIME_TAB_LIMIT
};

export class BrowserMemoryPressureCoordinator {
  private config: BrowserMemoryPressureConfig;
  private runtimeStateTransitionTable: BrowserRuntimeStateTransitionTable = new BrowserRuntimeStateTransitionTable();
  private siteComplexityScoringService: BrowserSiteComplexityScoringService = new BrowserSiteComplexityScoringService();

  constructor(config: BrowserMemoryPressureConfig = DEFAULT_BROWSER_MEMORY_PRESSURE_CONFIG) {
    this.config = config;
  }

  updateConfig(config: BrowserMemoryPressureConfig): void {
    this.config = {
      staleAfterMs: config.staleAfterMs,
      unstableTabGraceMs: config.unstableTabGraceMs,
      hotBackgroundMaxAgeMs: config.hotBackgroundMaxAgeMs,
      warmBackgroundMaxAgeMs: config.warmBackgroundMaxAgeMs,
      loadingTabGraceMs: config.loadingTabGraceMs,
      maxMountedRuntimeTabs: config.maxMountedRuntimeTabs
    };
  }

  getConfig(): BrowserMemoryPressureConfig {
    return {
      staleAfterMs: this.config.staleAfterMs,
      unstableTabGraceMs: this.config.unstableTabGraceMs,
      hotBackgroundMaxAgeMs: this.config.hotBackgroundMaxAgeMs,
      warmBackgroundMaxAgeMs: this.config.warmBackgroundMaxAgeMs,
      loadingTabGraceMs: this.config.loadingTabGraceMs,
      maxMountedRuntimeTabs: this.config.maxMountedRuntimeTabs
    };
  }

  buildRetentionPlan(
    runtimePoolPolicy: WebRuntimePoolPolicy,
    tabs: BrowserTabState[],
    activeTabId: string,
    now: number = Date.now(),
    options: BrowserMemoryPressureOptions = {}
  ): WebRuntimeRetentionPlan {
    const poolConfig = runtimePoolPolicy.getConfig();
    const lifecycleBudget = this.resolveLifecycleBudget(poolConfig, options);
    const protectedReasonsByTabId = options.protectedReasonsByTabId ?? {};
    const pressureAdjustment = this.resolveLifecyclePressureAdjustment(options);
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
    const pressureAdjustedWarmTabIds: string[] = [];

    const activeTab = tabs.find((tab: BrowserTabState) => tab.id === activeTabId);
    if (activeTab !== undefined && !activeTab.isHome) {
      runtimeStates[activeTab.id] = this.resolveActiveRuntimeState(activeTab);
      mountedTabIds.push(activeTab.id);
      retentionScoresByTabId[activeTab.id] = 1000;
      restorePrioritiesByTabId[activeTab.id] = 1000;
      retentionReasonsByTabId[activeTab.id] = '前台活动标签页，保留 live runtime。';
      nonReclaimableReasonsByTabId[activeTab.id] = '前台活动标签页不可回收。';
      discardReasonsByTabId[activeTab.id] = '';
    }

    let hotCount = 0;
    let warmCount = 0;
    const backgroundCandidates = tabs
      .filter((tab: BrowserTabState) => !tab.isHome && tab.id !== activeTabId)
      .map((tab: BrowserTabState): BrowserBackgroundRetentionCandidate => {
        const ageMs = Math.max(0, now - tab.lastActiveAt);
        const complexity = this.siteComplexityScoringService.evaluateTab(tab);
        return {
          tab: tab,
          ageMs: ageMs,
          complexity: complexity,
          retentionScore: this.computeRetentionScore(tab, ageMs, complexity.score),
          restorePriority: this.computeRestorePriority(tab, ageMs, complexity.score)
        };
      })
      .sort((left: BrowserBackgroundRetentionCandidate, right: BrowserBackgroundRetentionCandidate) => {
        if (right.retentionScore !== left.retentionScore) {
          return right.retentionScore - left.retentionScore;
        }
        return right.tab.lastActiveAt - left.tab.lastActiveAt;
      });

    backgroundCandidates.forEach((candidate: BrowserBackgroundRetentionCandidate) => {
      const tab = candidate.tab;
      const ageMs = candidate.ageMs;
      retentionScoresByTabId[tab.id] = candidate.retentionScore;
      restorePrioritiesByTabId[tab.id] = candidate.restorePriority;
      const nonReclaimableDecision = this.resolveNonReclaimableDecision(tab, ageMs, protectedReasonsByTabId[tab.id] ?? '');
      if (nonReclaimableDecision !== undefined) {
        runtimeStates[tab.id] = nonReclaimableDecision.runtimeState;
        if (nonReclaimableDecision.mounted) {
          mountedTabIds.push(tab.id);
          hotTabIds.push(tab.id);
          hotCount += 1;
        } else {
          warmTabIds.push(tab.id);
          warmCount += 1;
        }
        retentionReasonsByTabId[tab.id] = this.appendComplexityReason(nonReclaimableDecision.reason, candidate.complexity);
        nonReclaimableReasonsByTabId[tab.id] = this.appendComplexityReason(nonReclaimableDecision.reason, candidate.complexity);
        discardReasonsByTabId[tab.id] = '';
        return;
      }
      const forcedColdDecision = this.resolveForcedColdDecision(tab, ageMs);
      if (forcedColdDecision !== undefined) {
        runtimeStates[tab.id] = this.resolveQueuedDiscardRuntimeState(tab);
        coldTabIds.push(tab.id);
        retentionReasonsByTabId[tab.id] = this.appendComplexityReason(forcedColdDecision.reason, candidate.complexity);
        discardReasonsByTabId[tab.id] = forcedColdDecision.discardReason;
        return;
      }

      if (hotCount < lifecycleBudget.maxHotBackgroundTabs && this.canStayHot(ageMs)) {
        runtimeStates[tab.id] = 'background-hot';
        mountedTabIds.push(tab.id);
        hotTabIds.push(tab.id);
        hotCount += 1;
        retentionReasonsByTabId[tab.id] = this.appendComplexityReason(
          '最近活跃的后台标签页，保留热态 runtime 直接切回。',
          candidate.complexity
        );
        discardReasonsByTabId[tab.id] = '';
        return;
      }

      if (warmCount < lifecycleBudget.maxWarmBackgroundTabs + pressureAdjustment.extraWarmSlots && this.canStayWarm(ageMs)) {
        runtimeStates[tab.id] = 'background-warm';
        mountedTabIds.push(tab.id);
        warmTabIds.push(tab.id);
        warmCount += 1;
        const warmReason = warmCount <= lifecycleBudget.maxWarmBackgroundTabs
          ? '处于温态保留区，保留 live runtime；切回时直接重新挂载，不走恢复。'
          : '临时放宽 warm 保活槽位，避免继续扩大后台回收候选。';
        if (warmCount > poolConfig.maxWarmBackgroundTabs) {
          pressureAdjustedWarmTabIds.push(tab.id);
        }
        retentionReasonsByTabId[tab.id] = this.appendComplexityReason(warmReason, candidate.complexity);
        discardReasonsByTabId[tab.id] = '';
        return;
      }

      runtimeStates[tab.id] = this.resolveQueuedDiscardRuntimeState(tab);
      coldTabIds.push(tab.id);
      retentionReasonsByTabId[tab.id] = this.appendComplexityReason(
        tab.webStatePath.length > 0
          ? '超出后台保活预算，已释放 live runtime，仅保留快照。'
          : '超出后台保活预算，已释放 live runtime，切回时重新恢复。',
        candidate.complexity
      );
      discardReasonsByTabId[tab.id] = 'retention_budget';
    });

    this.enforceMountedRuntimeThreshold(
      activeTabId,
      mountedTabIds,
      hotTabIds,
      warmTabIds,
      coldTabIds,
      forcedDiscardTabIds,
      runtimeStates,
      retentionReasonsByTabId,
      retentionScoresByTabId,
      nonReclaimableReasonsByTabId,
      discardReasonsByTabId,
      this.buildComplexityReasonMap(backgroundCandidates),
      lifecycleBudget.maxMountedRuntimeTabs + pressureAdjustment.extraMountedSlots
    );
    const pressureAssist = this.buildPressureAssist(
      pressureAdjustment,
      activeTabId,
      mountedTabIds,
      retentionScoresByTabId,
      nonReclaimableReasonsByTabId,
      pressureAdjustedWarmTabIds
    );
    const siteComplexitySummary = this.buildSiteComplexitySummary(
      backgroundCandidates,
      mountedTabIds,
      coldTabIds,
      restorePrioritiesByTabId
    );

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
      discardReasonsByTabId: discardReasonsByTabId,
      pressureAssist: pressureAssist,
      siteComplexitySummary: siteComplexitySummary
    };
  }

  private resolveActiveRuntimeState(tab: BrowserTabState): TabRuntimeState {
    return this.runtimeStateTransitionTable.resolveForegroundState(tab.runtimeState, tab.isHome);
  }

  private resolveLifecycleBudget(
    poolConfig: WebRuntimePoolPolicyConfig,
    options: BrowserMemoryPressureOptions
  ): BrowserLifecycleRetentionBudget {
    let baseBudget: BrowserLifecycleRetentionBudget;
    if (options.appLifecycle === 'background' || options.windowVisibility === 'hidden') {
      baseBudget = {
        maxHotBackgroundTabs: 0,
        maxWarmBackgroundTabs: 0,
        maxMountedRuntimeTabs: 1
      };
    } else if (options.windowVisibility === 'showing' || options.windowVisibility === 'visible') {
      baseBudget = {
        maxHotBackgroundTabs: Math.max(1, poolConfig.maxHotBackgroundTabs),
        maxWarmBackgroundTabs: poolConfig.maxWarmBackgroundTabs,
        maxMountedRuntimeTabs: this.config.maxMountedRuntimeTabs
      };
    } else {
      baseBudget = {
        maxHotBackgroundTabs: poolConfig.maxHotBackgroundTabs,
        maxWarmBackgroundTabs: poolConfig.maxWarmBackgroundTabs,
        maxMountedRuntimeTabs: this.config.maxMountedRuntimeTabs
      };
    }
    return this.applySystemMemoryPressureBudget(baseBudget, options.systemMemoryPressureLevel);
  }

  private applySystemMemoryPressureBudget(
    budget: BrowserLifecycleRetentionBudget,
    pressureLevel?: BrowserSystemMemoryPressureLevel
  ): BrowserLifecycleRetentionBudget {
    if (pressureLevel === 'critical') {
      return {
        maxHotBackgroundTabs: 0,
        maxWarmBackgroundTabs: Math.min(2, budget.maxWarmBackgroundTabs),
        maxMountedRuntimeTabs: Math.min(HUAWEI_PHONE_CRITICAL_RUNTIME_TAB_LIMIT, budget.maxMountedRuntimeTabs)
      };
    }
    if (pressureLevel === 'low') {
      return {
        maxHotBackgroundTabs: Math.min(2, budget.maxHotBackgroundTabs),
        maxWarmBackgroundTabs: Math.min(6, budget.maxWarmBackgroundTabs),
        maxMountedRuntimeTabs: Math.min(HUAWEI_PHONE_MEMORY_PRESSURE_RUNTIME_TAB_LIMIT, budget.maxMountedRuntimeTabs)
      };
    }
    if (pressureLevel === 'moderate') {
      return {
        maxHotBackgroundTabs: Math.min(2, budget.maxHotBackgroundTabs),
        maxWarmBackgroundTabs: Math.min(6, budget.maxWarmBackgroundTabs),
        maxMountedRuntimeTabs: Math.min(HUAWEI_PHONE_MEMORY_PRESSURE_RUNTIME_TAB_LIMIT, budget.maxMountedRuntimeTabs)
      };
    }
    return budget;
  }

  private resolveNonReclaimableDecision(
    tab: BrowserTabState,
    ageMs: number,
    explicitProtectionReason: string
  ): NonReclaimableDecision | undefined {
    if (explicitProtectionReason.length > 0) {
      return {
        runtimeState: tab.runtimeState === 'cold' || tab.runtimeState === 'suspended' ? 'background-hot' : tab.runtimeState,
        mounted: true,
        reason: explicitProtectionReason
      };
    }

    if ((tab.runtimeState === 'loading' || tab.runtimeState === 'restoring') && ageMs < this.config.loadingTabGraceMs) {
      return {
        runtimeState: tab.runtimeState,
        mounted: true,
        reason: '后台标签页仍在加载或恢复保护窗口内，暂不回收 live runtime。'
      };
    }

    if ((tab.runtimeState === 'error' || tab.runtimeState === 'crashed') && ageMs < this.config.unstableTabGraceMs) {
      return {
        runtimeState: tab.runtimeState,
        mounted: false,
        reason: '异常标签页仍在保护窗口内，保留故障状态等待用户处理。'
      };
    }
    return undefined;
  }

  private resolveForcedColdDecision(tab: BrowserTabState, ageMs: number): ForcedColdDecision | undefined {
    if (ageMs >= this.config.warmBackgroundMaxAgeMs) {
      return {
        discardReason: 'retention_stale',
        reason: '后台标签页超过温态保留时长，主动冷却释放内存预算。'
      };
    }

    if (ageMs >= this.config.staleAfterMs) {
      return {
        discardReason: 'retention_stale',
        reason: '后台停留时间过长，主动冷却释放内存预算。'
      };
    }

    if ((tab.runtimeState === 'error' || tab.runtimeState === 'crashed') && ageMs >= this.config.unstableTabGraceMs) {
      return {
        discardReason: 'retention_stale',
        reason: '异常后台标签页超过保护时长，不再占用保活预算。'
      };
    }
    return undefined;
  }

  private resolveQueuedDiscardRuntimeState(tab: BrowserTabState): TabRuntimeState {
    return tab.runtimeState === 'discarded' ? 'discarded' : 'cold';
  }

  private canStayHot(ageMs: number): boolean {
    return ageMs < this.config.hotBackgroundMaxAgeMs;
  }

  private canStayWarm(ageMs: number): boolean {
    return ageMs < this.config.warmBackgroundMaxAgeMs;
  }

  private enforceMountedRuntimeThreshold(
    activeTabId: string,
    mountedTabIds: string[],
    hotTabIds: string[],
    warmTabIds: string[],
    coldTabIds: string[],
    forcedDiscardTabIds: string[],
    runtimeStates: Record<string, TabRuntimeState>,
    retentionReasonsByTabId: Record<string, string>,
    retentionScoresByTabId: Record<string, number>,
    nonReclaimableReasonsByTabId: Record<string, string>,
    discardReasonsByTabId: Record<string, TabDiscardReason | ''>,
    complexityReasonsByTabId: Record<string, string>,
    effectiveMaxMountedRuntimeTabs: number
  ): void {
    if (mountedTabIds.length <= effectiveMaxMountedRuntimeTabs) {
      return;
    }
    const candidates = mountedTabIds
      .filter((tabId: string) => tabId !== activeTabId && (nonReclaimableReasonsByTabId[tabId] ?? '').length === 0)
      .sort((left: string, right: string) => (retentionScoresByTabId[left] ?? 0) - (retentionScoresByTabId[right] ?? 0));

    while (mountedTabIds.length > effectiveMaxMountedRuntimeTabs && candidates.length > 0) {
      const tabId = candidates.shift() ?? '';
      if (tabId.length === 0) {
        continue;
      }
      this.removeFromList(mountedTabIds, tabId);
      this.removeFromList(hotTabIds, tabId);
      this.removeFromList(warmTabIds, tabId);
      if (!coldTabIds.includes(tabId)) {
        coldTabIds.push(tabId);
      }
      if (!forcedDiscardTabIds.includes(tabId)) {
        forcedDiscardTabIds.push(tabId);
      }
      runtimeStates[tabId] = 'cold';
      retentionReasonsByTabId[tabId] = this.appendReasonSuffix(
        '超过强制 mounted runtime 阈值，按 retention score 释放 live runtime。',
        complexityReasonsByTabId[tabId] ?? ''
      );
      discardReasonsByTabId[tabId] = 'retention_budget';
    }
  }

  private removeFromList(items: string[], value: string): void {
    const index = items.indexOf(value);
    if (index >= 0) {
      items.splice(index, 1);
    }
  }

  private buildWebStateRestoreCandidates(coldTabIds: string[], restorePrioritiesByTabId: Record<string, number>): string[] {
    return coldTabIds.slice().sort((left: string, right: string) => {
      return (restorePrioritiesByTabId[right] ?? 0) - (restorePrioritiesByTabId[left] ?? 0);
    });
  }

  private buildComplexityReasonMap(
    candidates: BrowserBackgroundRetentionCandidate[]
  ): Record<string, string> {
    const result: Record<string, string> = {};
    candidates.forEach((candidate: BrowserBackgroundRetentionCandidate) => {
      result[candidate.tab.id] = candidate.complexity.reasonLine;
    });
    return result;
  }

  private buildSiteComplexitySummary(
    candidates: BrowserBackgroundRetentionCandidate[],
    mountedTabIds: string[],
    coldTabIds: string[],
    restorePrioritiesByTabId: Record<string, number>
  ): WebRuntimeRetentionSiteComplexitySummary | undefined {
    const complexCandidates = candidates
      .filter((candidate: BrowserBackgroundRetentionCandidate) => candidate.complexity.score > 0)
      .sort((left: BrowserBackgroundRetentionCandidate, right: BrowserBackgroundRetentionCandidate) => {
        if (right.complexity.score !== left.complexity.score) {
          return right.complexity.score - left.complexity.score;
        }
        return (restorePrioritiesByTabId[right.tab.id] ?? 0) - (restorePrioritiesByTabId[left.tab.id] ?? 0);
      });
    if (complexCandidates.length === 0) {
      return undefined;
    }
    const topCandidate = complexCandidates[0];
    const retainedTabIds = complexCandidates
      .filter((candidate: BrowserBackgroundRetentionCandidate) => mountedTabIds.includes(candidate.tab.id))
      .map((candidate: BrowserBackgroundRetentionCandidate) => candidate.tab.id);
    const webStateRestoreCandidateTabIds = complexCandidates
      .filter((candidate: BrowserBackgroundRetentionCandidate) => coldTabIds.includes(candidate.tab.id))
      .map((candidate: BrowserBackgroundRetentionCandidate) => candidate.tab.id);
    const summaryLine =
      `siteComplexity total=${complexCandidates.length} top=${topCandidate.tab.id} ` +
      `level=${topCandidate.complexity.level} score=${topCandidate.complexity.score} ` +
      `retained=${this.formatSummaryTabIds(retainedTabIds)} webStateRestoreCandidates=${this.formatSummaryTabIds(webStateRestoreCandidateTabIds)} ` +
      `topReason=${this.formatSummaryReason(topCandidate.complexity.reasonLine)}`;
    return {
      complexTabCount: complexCandidates.length,
      topTabId: topCandidate.tab.id,
      topScore: topCandidate.complexity.score,
      topLevel: topCandidate.complexity.level,
      retainedTabIds: retainedTabIds,
      webStateRestoreCandidateTabIds: webStateRestoreCandidateTabIds,
      summaryLine: summaryLine
    };
  }

  private appendComplexityReason(baseReason: string, complexity: BrowserSiteComplexityScore): string {
    return this.appendReasonSuffix(baseReason, complexity.reasonLine);
  }

  private appendReasonSuffix(baseReason: string, suffix: string): string {
    if (suffix.length === 0 || suffix === 'complexity=none score=0') {
      return baseReason;
    }
    return `${baseReason} ${suffix}`;
  }

  private buildPressureAssist(
    pressureAdjustment: BrowserRetentionPressureAdjustment,
    activeTabId: string,
    mountedTabIds: string[],
    retentionScoresByTabId: Record<string, number>,
    nonReclaimableReasonsByTabId: Record<string, string>,
    pressureAdjustedWarmTabIds: string[]
  ): WebRuntimeRetentionPressureAssist {
    const pressureAdjustedMountedTabIds = this.resolvePressureAdjustedMountedTabIds(
      activeTabId,
      mountedTabIds,
      retentionScoresByTabId,
      nonReclaimableReasonsByTabId
    );
    return {
      level: pressureAdjustment.pressureLevel,
      extraWarmSlots: pressureAdjustment.extraWarmSlots,
      extraMountedSlots: pressureAdjustment.extraMountedSlots,
      warmTabIds: pressureAdjustedWarmTabIds.slice(),
      mountedTabIds: pressureAdjustedMountedTabIds,
      summaryLine:
        `retentionPressure level=${pressureAdjustment.pressureLevel} ` +
        `extraWarm=${pressureAdjustment.extraWarmSlots} extraMounted=${pressureAdjustment.extraMountedSlots} ` +
        `aidedWarm=${pressureAdjustedWarmTabIds.length} aidedMounted=${pressureAdjustedMountedTabIds.length} ` +
        `warmTabs=${this.formatPressureAssistTabIds(pressureAdjustedWarmTabIds)} ` +
        `mountedTabs=${this.formatPressureAssistTabIds(pressureAdjustedMountedTabIds)}`
    };
  }

  private formatPressureAssistTabIds(tabIds: string[]): string {
    if (tabIds.length === 0) {
      return 'none';
    }
    return tabIds.join(',');
  }

  private formatSummaryTabIds(tabIds: string[]): string {
    if (tabIds.length === 0) {
      return 'none';
    }
    return tabIds.join(',');
  }

  private formatSummaryReason(reasonLine: string): string {
    return reasonLine.replace(/\s+/g, '_');
  }

  private resolvePressureAdjustedMountedTabIds(
    activeTabId: string,
    mountedTabIds: string[],
    retentionScoresByTabId: Record<string, number>,
    nonReclaimableReasonsByTabId: Record<string, string>
  ): string[] {
    const preservedCount = mountedTabIds.length - this.config.maxMountedRuntimeTabs;
    if (preservedCount <= 0) {
      return [];
    }
    const candidates = mountedTabIds
      .filter((tabId: string) => tabId !== activeTabId && (nonReclaimableReasonsByTabId[tabId] ?? '').length === 0)
      .sort((left: string, right: string) => (retentionScoresByTabId[left] ?? 0) - (retentionScoresByTabId[right] ?? 0));
    if (candidates.length === 0) {
      return [];
    }
    return candidates.slice(0, preservedCount);
  }

  private computeRetentionScore(tab: BrowserTabState, ageMs: number, complexityScore: number): number {
    if (tab.runtimeState === 'active') {
      return 1000;
    }
    let score = 400;
    score -= Math.min(220, Math.floor(ageMs / 60000) * 12);
    if (tab.webStatePath.length > 0) {
      score += 18;
    }
    if (tab.runtimeState === 'background-hot') {
      score += 24;
    }
    if (tab.runtimeState === 'background-warm') {
      score += 10;
    }
    if (tab.runtimeState === 'error' || tab.runtimeState === 'crashed') {
      score -= 80;
    }
    score += complexityScore;
    return Math.max(0, Math.min(1000, score));
  }

  private computeRestorePriority(tab: BrowserTabState, ageMs: number, complexityScore: number): number {
    let priority = 520;
    priority -= Math.min(260, Math.floor(ageMs / 60000) * 10);
    if (tab.runtimeState === 'background-hot') {
      priority += 260;
    }
    if (tab.runtimeState === 'background-warm') {
      priority += 160;
    }
    if (tab.webStatePath.length > 0) {
      priority += 90;
    }
    if (tab.lastGoodUrl.length > 0) {
      priority += 60;
    }
    if (tab.runtimeState === 'error' || tab.runtimeState === 'crashed') {
      priority -= 140;
    }
    priority += Math.min(220, complexityScore * 2);
    return Math.max(0, Math.min(1000, priority));
  }

  private resolveLifecyclePressureAdjustment(_options: BrowserMemoryPressureOptions): BrowserRetentionPressureAdjustment {
    return {
      pressureLevel: 'idle',
      extraWarmSlots: 0,
      extraMountedSlots: 0
    };
  }
}

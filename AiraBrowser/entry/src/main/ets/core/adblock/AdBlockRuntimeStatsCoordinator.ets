import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDataScope,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import { normalizeNavigationTarget } from '../browser/AddressDisplayFormatter';

const PROTECTION_DEBUG_DOMAIN: number = 0x0000;
const PROTECTION_DEBUG_TAG: string = 'ProtectionCountDiag';
const PROTECTION_DEBUG_PREFIX: string = '[DEBUG-protection-count-20260808]';

export interface AdBlockRuntimeNetworkBlockedEvent {
  tabId: string;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

export interface AdBlockRuntimeUrlParameterRemovedEvent {
  tabId: string;
  removedParameterCount: number;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

export interface AdBlockRuntimeCosmeticStatsContext {
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

export interface AdBlockRuntimeManualHiddenEvent {
  tabId: string;
  hiddenElementCount: number;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

export interface AdBlockRuntimeCosmeticHiddenEvent {
  tabId: string;
  pageUrl: string;
  currentPageUrl: string;
  hiddenElementCount: number;
}

export interface AdBlockRuntimeCosmeticHiddenResult {
  totalActionCount: number;
  hiddenElementCount: number;
  placeholderCollapsedCount: number;
}

/**
 * A fresh, per-document measurement. It is copied on read so renderers cannot
 * mutate the accounting state that drives the current-page report.
 */
export interface AdBlockRuntimePageProtectionSnapshot {
  tabId: string;
  navigationGeneration: number;
  dataScope: BrowserDataScope;
  requestBlockingCount: number;
  linkCleaningCount: number;
  elementHidingCount: number;
  totalActionCount: number;
}


export class AdBlockRuntimeStatsCoordinator {
  private repository: AdBlockRepository;
  private tabProtectionSnapshots: Map<string, AdBlockRuntimePageProtectionSnapshot> = new Map();
  private tabNavigationGenerations: Map<string, number> = new Map();
  private pendingNavigationLinkCleaningCounts: Map<string, number> = new Map();
  private cosmeticStatsContexts: Map<string, AdBlockRuntimeCosmeticStatsContext> = new Map();

  constructor(repository: AdBlockRepository) {
    this.repository = repository;
  }

  resetPageStats(tabId: string): void {
    const navigationGeneration = (this.tabNavigationGenerations.get(tabId) ?? 0) + 1;
    this.tabNavigationGenerations.set(tabId, navigationGeneration);
    const snapshot = this.buildEmptyPageSnapshot(tabId, navigationGeneration);
    const pendingLinkCleaningCount = this.pendingNavigationLinkCleaningCounts.get(tabId) ?? 0;
    if (pendingLinkCleaningCount > 0) {
      snapshot.linkCleaningCount = pendingLinkCleaningCount;
      snapshot.totalActionCount = pendingLinkCleaningCount;
      this.pendingNavigationLinkCleaningCounts.delete(tabId);
    }
    this.tabProtectionSnapshots.set(tabId, snapshot);
    this.clearCosmeticStatsContext(tabId);
    hilog.info(
      PROTECTION_DEBUG_DOMAIN,
      PROTECTION_DEBUG_TAG,
      '%{public}s reset generation=%{public}d linkCleaning=%{public}d total=%{public}d',
      PROTECTION_DEBUG_PREFIX,
      navigationGeneration,
      snapshot.linkCleaningCount,
      snapshot.totalActionCount
    );
  }

  getPageBlockedCount(tabId: string): number {
    return this.getPageProtectionSnapshot(tabId).totalActionCount;
  }

  getPageProtectionSnapshot(tabId: string): AdBlockRuntimePageProtectionSnapshot {
    const snapshot = this.resolvePageSnapshot(tabId);
    return this.copyPageSnapshot(snapshot);
  }

  buildPageSummary(baseSummary: string, tabId: string): string {
    if (baseSummary.indexOf('未开启') >= 0 ||
      baseSummary.indexOf('不可用') >= 0 ||
      baseSummary.indexOf('不支持') >= 0 ||
      baseSummary.indexOf('例外') >= 0 ||
      baseSummary.indexOf('没有启用') >= 0) {
      return baseSummary;
    }
    const actionCount = this.getPageProtectionSnapshot(tabId).totalActionCount;
    if (actionCount > 0) {
      return `本页已保护 ${actionCount} 项`;
    }
    return '已开启，暂无拦截';
  }

  recordNetworkBlocked(event: AdBlockRuntimeNetworkBlockedEvent): void {
    this.incrementPageActions(event.tabId, 1, 0, 0, event.dataScope);
    const snapshot = this.getPageProtectionSnapshot(event.tabId);
    hilog.info(
      PROTECTION_DEBUG_DOMAIN,
      PROTECTION_DEBUG_TAG,
      '%{public}s network generation=%{public}d total=%{public}d request=%{public}d',
      PROTECTION_DEBUG_PREFIX,
      snapshot.navigationGeneration,
      snapshot.totalActionCount,
      snapshot.requestBlockingCount
    );
    void this.repository.recordBlockedRequest(
      event.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      event.dataScope
    );
  }

  recordUrlParametersRemoved(event: AdBlockRuntimeUrlParameterRemovedEvent): void {
    this.incrementPageActions(event.tabId, 0, 1, 0, event.dataScope);
    void this.repository.recordUrlParametersRemoved(
      event.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      event.dataScope,
      this.normalizeCount(event.removedParameterCount)
    );
  }

  recordNavigationUrlCleaned(event: AdBlockRuntimeUrlParameterRemovedEvent): void {
    const current = this.pendingNavigationLinkCleaningCounts.get(event.tabId) ?? 0;
    this.pendingNavigationLinkCleaningCounts.set(event.tabId, current + 1);
    void this.repository.recordUrlParametersRemoved(
      event.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      event.dataScope,
      this.normalizeCount(event.removedParameterCount)
    );
  }

  recordCosmeticSelectors(
    tabId: string,
    _selectors: string[],
    hiddenElementCount: number,
    _placeholderCollapsedCount: number = 0
  ): void {
    const hiddenCount = this.normalizeCount(hiddenElementCount);
    this.recordCosmeticHiddenElements(tabId, hiddenCount);
  }

  recordCosmeticHiddenElements(tabId: string, hiddenElementCount: number): void {
    const count = this.normalizeCount(hiddenElementCount);
    if (count <= 0) {
      return;
    }
    const context = this.cosmeticStatsContexts.get(tabId);
    this.incrementPageActions(tabId, 0, 0, count, context?.dataScope);
    if (context !== undefined) {
      void this.repository.recordCosmeticElementsHidden(context.profileId, context.dataScope, count);
    }
  }

  recordCosmeticHiddenFromRuntime(
    event: AdBlockRuntimeCosmeticHiddenEvent
  ): AdBlockRuntimeCosmeticHiddenResult {
    if (!this.isSameNavigationTarget(event.pageUrl, event.currentPageUrl)) {
      return this.emptyCosmeticHiddenResult();
    }
    const hiddenCount = this.normalizeCount(event.hiddenElementCount);
    if (hiddenCount <= 0) {
      return this.emptyCosmeticHiddenResult();
    }
    this.recordCosmeticHiddenElements(event.tabId, hiddenCount);
    return {
      totalActionCount: hiddenCount,
      hiddenElementCount: hiddenCount,
      placeholderCollapsedCount: 0
    };
  }

  recordManualElementsHidden(event: AdBlockRuntimeManualHiddenEvent): void {
    const count = this.normalizeCount(event.hiddenElementCount);
    if (count <= 0) {
      return;
    }
    this.incrementPageActions(event.tabId, 0, 0, count, event.dataScope);
    void this.repository.recordManualElementsHidden(
      event.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      event.dataScope,
      count
    );
  }

  setCosmeticStatsContext(
    tabId: string,
    profileId: BrowserProfileId,
    dataScope: BrowserDataScope
  ): void {
    const context: AdBlockRuntimeCosmeticStatsContext = {
      profileId: profileId,
      dataScope: dataScope
    };
    this.cosmeticStatsContexts.set(tabId, context);
  }

  clearCosmeticStatsContext(tabId: string): void {
    this.cosmeticStatsContexts.delete(tabId);
  }

  private incrementPageActions(
    tabId: string,
    requestBlockingDelta: number,
    linkCleaningDelta: number,
    elementHidingDelta: number,
    dataScope?: BrowserDataScope
  ): void {
    const current = this.resolvePageSnapshot(tabId);
    const requestBlockingCount = current.requestBlockingCount + this.normalizeCount(requestBlockingDelta);
    const linkCleaningCount = current.linkCleaningCount + this.normalizeCount(linkCleaningDelta);
    const elementHidingCount = current.elementHidingCount + this.normalizeCount(elementHidingDelta);
    this.tabProtectionSnapshots.set(tabId, {
      tabId: current.tabId,
      navigationGeneration: current.navigationGeneration,
      dataScope: dataScope ?? current.dataScope,
      requestBlockingCount: requestBlockingCount,
      linkCleaningCount: linkCleaningCount,
      elementHidingCount: elementHidingCount,
      totalActionCount: requestBlockingCount + linkCleaningCount + elementHidingCount
    });
  }

  private resolvePageSnapshot(tabId: string): AdBlockRuntimePageProtectionSnapshot {
    const existing = this.tabProtectionSnapshots.get(tabId);
    if (existing !== undefined) {
      return existing;
    }
    const navigationGeneration = this.tabNavigationGenerations.get(tabId) ?? 0;
    const created = this.buildEmptyPageSnapshot(tabId, navigationGeneration);
    this.tabProtectionSnapshots.set(tabId, created);
    return created;
  }

  private buildEmptyPageSnapshot(
    tabId: string,
    navigationGeneration: number
  ): AdBlockRuntimePageProtectionSnapshot {
    return {
      tabId: tabId,
      navigationGeneration: navigationGeneration,
      dataScope: 'profile_persistent',
      requestBlockingCount: 0,
      linkCleaningCount: 0,
      elementHidingCount: 0,
      totalActionCount: 0
    };
  }

  private copyPageSnapshot(
    value: AdBlockRuntimePageProtectionSnapshot
  ): AdBlockRuntimePageProtectionSnapshot {
    return {
      tabId: value.tabId,
      navigationGeneration: value.navigationGeneration,
      dataScope: value.dataScope,
      requestBlockingCount: value.requestBlockingCount,
      linkCleaningCount: value.linkCleaningCount,
      elementHidingCount: value.elementHidingCount,
      totalActionCount: value.totalActionCount
    };
  }

  private isSameNavigationTarget(left: string, right: string): boolean {
    const normalizedLeft = normalizeNavigationTarget(left);
    const normalizedRight = normalizeNavigationTarget(right);
    return normalizedLeft.length > 0 && normalizedLeft === normalizedRight;
  }

  private normalizeCount(value: number): number {
    return typeof value === 'number' && !Number.isNaN(value) && value > 0 ? Math.round(value) : 0;
  }

  private emptyCosmeticHiddenResult(): AdBlockRuntimeCosmeticHiddenResult {
    return {
      totalActionCount: 0,
      hiddenElementCount: 0,
      placeholderCollapsedCount: 0
    };
  }

}

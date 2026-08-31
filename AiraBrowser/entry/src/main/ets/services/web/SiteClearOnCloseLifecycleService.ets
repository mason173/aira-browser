import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  BrowserSitePrivacyRule,
  DEFAULT_BROWSER_PROFILE_ID,
  TabRecord
} from '../../common/models/BrowserModels';
import { BrowserTabState } from '../../core/tabs/TabManager';
import { BrowserSitePrivacyRuleRepository } from '../../data/browser/BrowserSitePrivacyRuleRepository';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import { SiteDataClearResult, SiteDataControlService } from './SiteDataControlService';
import { SiteInteractionLogicService } from './SiteInteractionLogicService';

export interface SiteClearOnCloseMatch {
  rule: BrowserSitePrivacyRule;
  url: string;
  origin: string;
  host: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface SiteClearOnCloseExitResult {
  matched: boolean;
  match?: SiteClearOnCloseMatch;
  clearResult?: SiteDataClearResult;
}

export interface SiteClearOnCloseFilterResult {
  records: TabRecord[];
  removedCount: number;
  removedRecords: TabRecord[];
}

export interface SiteClearOnCloseRecordsCleanupResult {
  matchedCount: number;
  hosts: string[];
  origins: string[];
  clearResults: SiteDataClearResult[];
}

export class SiteClearOnCloseLifecycleService {
  private ruleRepository: BrowserSitePrivacyRuleRepository;
  private siteDataControlService: SiteDataControlService;
  private siteInteractionLogicService: SiteInteractionLogicService;
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  constructor(
    ruleRepository: BrowserSitePrivacyRuleRepository,
    siteDataControlService: SiteDataControlService,
    siteInteractionLogicService: SiteInteractionLogicService = new SiteInteractionLogicService()
  ) {
    this.ruleRepository = ruleRepository;
    this.siteDataControlService = siteDataControlService;
    this.siteInteractionLogicService = siteInteractionLogicService;
  }

  shouldSkipRecentlyClosed(tab: BrowserTabState | undefined): boolean {
    return this.resolveMatchForTab(tab) !== undefined;
  }

  handleExplicitSiteExit(tab: BrowserTabState | undefined): SiteClearOnCloseExitResult {
    const match = this.resolveMatchForTab(tab);
    if (match === undefined) {
      return { matched: false };
    }
    const clearResult = this.siteDataControlService.clearSiteDataOnClose(
      match.origin.length > 0 ? match.origin : match.rule.origin,
      match.url,
      match.profileId,
      match.privacyMode,
      match.dataScope
    );
    return {
      matched: true,
      match: match,
      clearResult: clearResult
    };
  }

  filterPersistableTabRecords(records: TabRecord[]): SiteClearOnCloseFilterResult {
    let removedCount = 0;
    const removedRecords: TabRecord[] = [];
    const retainedRecords = records.filter((record: TabRecord) => {
      if (this.resolveMatchForRecord(record) === undefined) {
        return true;
      }
      removedCount += 1;
      removedRecords.push(record);
      return false;
    });
    return {
      records: retainedRecords,
      removedCount: removedCount,
      removedRecords: removedRecords
    };
  }

  cleanupMatchedRecords(records: TabRecord[]): SiteClearOnCloseRecordsCleanupResult {
    const hosts: string[] = [];
    const origins: string[] = [];
    const clearResults: SiteDataClearResult[] = [];
    const seenOrigins = new Set<string>();
    records.forEach((record: TabRecord) => {
      const match = this.resolveMatchForRecord(record);
      if (match === undefined) {
        return;
      }
      const cleanupOrigin = match.origin.length > 0 ? match.origin : match.rule.origin;
      const cleanupKey = `${match.profileId}|${cleanupOrigin}`;
      if (seenOrigins.has(cleanupKey)) {
        return;
      }
      seenOrigins.add(cleanupKey);
      if (match.host.length > 0 && !hosts.includes(match.host)) {
        hosts.push(match.host);
      }
      if (cleanupOrigin.length > 0 && !origins.includes(cleanupOrigin)) {
        origins.push(cleanupOrigin);
      }
      clearResults.push(this.siteDataControlService.clearSiteDataOnClose(
        cleanupOrigin,
        match.url,
        match.profileId,
        match.privacyMode,
        match.dataScope
      ));
    });
    return {
      matchedCount: seenOrigins.size,
      hosts: hosts,
      origins: origins,
      clearResults: clearResults
    };
  }

  shouldSkipHistoryVisit(
    url: string,
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): boolean {
    return this.resolveMatch(url, profileId, privacyMode, dataScope) !== undefined;
  }

  matchesHost(url: string, fallbackOrigin: string, targetHost: string): boolean {
    const normalizedTargetHost = targetHost.trim().toLowerCase();
    if (normalizedTargetHost.length <= 0) {
      return false;
    }
    return this.resolveHost(url, fallbackOrigin) === normalizedTargetHost;
  }

  resolveHost(url: string, fallbackOrigin: string = ''): string {
    const host = this.siteInteractionLogicService.getHostFromUrl(url).trim().toLowerCase();
    if (host.length > 0) {
      return host;
    }
    return this.siteInteractionLogicService.getHostFromUrl(fallbackOrigin).trim().toLowerCase();
  }

  private resolveMatchForTab(tab: BrowserTabState | undefined): SiteClearOnCloseMatch | undefined {
    if (tab === undefined || tab.isHome || this.profileBoundaryService.isSessionEphemeral({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    })) {
      return undefined;
    }
    return this.resolveMatch(tab.url, tab.profileId, tab.privacyMode, tab.dataScope);
  }

  private resolveMatchForRecord(record: TabRecord): SiteClearOnCloseMatch | undefined {
    if (record.isHome === true || this.profileBoundaryService.isSessionEphemeral({
      profileId: record.profileId,
      privacyMode: record.privacyMode,
      dataScope: record.dataScope,
      sessionId: record.id
    })) {
      return undefined;
    }
    return this.resolveMatch(
      record.url,
      record.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      record.privacyMode ?? 'regular',
      record.dataScope ?? 'profile_persistent'
    );
  }

  private resolveMatch(
    url: string,
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): SiteClearOnCloseMatch | undefined {
    const matchedRule = this.ruleRepository.findMatchingRule(url, profileId);
    if (matchedRule === undefined || matchedRule.mode !== 'clear_on_close') {
      return undefined;
    }
    const origin = this.siteInteractionLogicService.resolveOrigin(url);
    const host = this.resolveHost(url, matchedRule.origin);
    return {
      rule: matchedRule,
      url: url,
      origin: origin,
      host: host,
      profileId: profileId,
      privacyMode: privacyMode,
      dataScope: dataScope
    };
  }
}

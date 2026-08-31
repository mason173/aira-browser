import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserProfileId, BrowserUserAgentSettings } from '../../common/models/BrowserModels';
import { SavedSiteSettingEntry, SiteSettingTarget } from '../../common/models/SiteSettingModels';
import { BrowserUserAgentSettingsReader } from '../../data/browser/BrowserUserAgentSettingsRepository';
import { SavedSiteSettingRepository } from '../../data/browser/SavedSiteSettingRepository';
import {
  BrowserBrowsingIdentityCandidate,
  BrowserBrowsingIdentityDecision,
  BrowserBrowsingIdentityDecisionService,
  BrowserBrowsingIdentityPolicySnapshot,
  BrowserBrowsingIdentityPrecedenceSource
} from '../../services/web/BrowserBrowsingIdentityDecisionService';
import { BrowserUserAgentHostPolicyService } from '../../services/web/BrowserUserAgentHostPolicyService';
import {
  AIRA_DEFAULT_BROWSER_IDENTITY_ID,
  BrowserDesktopSiteMode,
  BrowserUserAgentApplicationFamily,
  BrowserUserAgentIdentity,
  BrowserUserAgentMandatoryCompatibility,
  BrowserUserAgentResolution,
  BrowserUserAgentService,
  BrowserUserAgentSiteOverride,
  DEFAULT_BROWSER_USER_AGENT_SETTINGS,
  FOLLOW_GLOBAL_BROWSER_IDENTITY_ID,
  SYSTEM_DEFAULT_USER_AGENT_PRESET_ID
} from '../../services/web/BrowserUserAgentService';

const BROWSING_IDENTITY_DIAGNOSTIC_LOG_DOMAIN: number = 0x0000;
const BROWSING_IDENTITY_DIAGNOSTIC_LOG_TAG: string = 'BrowsingIdentity';
const BROWSING_IDENTITY_DIAGNOSTIC_PREFIX: string = '[BROWSING-IDENTITY-DIAG]';

export interface BrowserBrowsingIdentityPolicyRequest {
  tabId: string;
  currentUrl: string;
  profileId: BrowserProfileId;
  privateBrowsing: boolean;
  systemDefaultUserAgent: string;
}

export interface BrowserBrowsingIdentityHostPolicyAdapter {
  resolveApplicationFamily(): BrowserUserAgentApplicationFamily;
  resolveMandatoryCompatibility(
    host: string,
    requestedApplicationFamily?: BrowserUserAgentApplicationFamily
  ): BrowserUserAgentMandatoryCompatibility | undefined;
}

class DefaultBrowsingIdentityHostPolicyAdapter implements BrowserBrowsingIdentityHostPolicyAdapter {
  resolveApplicationFamily(): BrowserUserAgentApplicationFamily {
    return BrowserUserAgentHostPolicyService.resolveCurrentApplicationFamily();
  }

  resolveMandatoryCompatibility(
    host: string,
    requestedApplicationFamily?: BrowserUserAgentApplicationFamily
  ): BrowserUserAgentMandatoryCompatibility | undefined {
    return BrowserUserAgentHostPolicyService.resolveMandatoryCompatibilityForHost(
      host,
      requestedApplicationFamily
    );
  }
}

export class BrowserBrowsingIdentityPolicyCoordinator {
  private readonly settingsRepository: BrowserUserAgentSettingsReader;
  private readonly savedSiteSettingRepository: SavedSiteSettingRepository;
  private readonly userAgentService: BrowserUserAgentService;
  private readonly decisionService: BrowserBrowsingIdentityDecisionService;
  private readonly hostPolicyAdapter: BrowserBrowsingIdentityHostPolicyAdapter;
  private currentTabIdentityIdByTabId: Record<string, string | undefined> = {};
  private currentTabGenerationByTabId: Record<string, number | undefined> = {};

  constructor(
    settingsRepository: BrowserUserAgentSettingsReader,
    savedSiteSettingRepository: SavedSiteSettingRepository,
    userAgentService: BrowserUserAgentService,
    decisionService: BrowserBrowsingIdentityDecisionService = new BrowserBrowsingIdentityDecisionService(),
    hostPolicyAdapter: BrowserBrowsingIdentityHostPolicyAdapter = new DefaultBrowsingIdentityHostPolicyAdapter()
  ) {
    this.settingsRepository = settingsRepository;
    this.savedSiteSettingRepository = savedSiteSettingRepository;
    this.userAgentService = userAgentService;
    this.decisionService = decisionService;
    this.hostPolicyAdapter = hostPolicyAdapter;
  }

  setCurrentTabIdentity(tabId: string, identityId: string | undefined): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    const normalizedIdentityId = identityId?.trim() ?? '';
    const nextIdentityId = normalizedIdentityId.length > 0 &&
      normalizedIdentityId !== FOLLOW_GLOBAL_BROWSER_IDENTITY_ID ? normalizedIdentityId : undefined;
    if (this.currentTabIdentityIdByTabId[normalizedTabId] === nextIdentityId) {
      return;
    }
    this.currentTabIdentityIdByTabId[normalizedTabId] = nextIdentityId;
    this.currentTabGenerationByTabId[normalizedTabId] =
      (this.currentTabGenerationByTabId[normalizedTabId] ?? 0) + 1;
  }

  getCurrentTabIdentityId(tabId: string): string {
    return this.currentTabIdentityIdByTabId[tabId.trim()] ?? '';
  }

  releaseTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    this.currentTabIdentityIdByTabId[normalizedTabId] = undefined;
    this.currentTabGenerationByTabId[normalizedTabId] = undefined;
  }

  resolveWithSystemDefault(
    tabId: string,
    currentUrl: string,
    profileId: BrowserProfileId,
    privateBrowsing: boolean
  ): BrowserBrowsingIdentityDecision {
    let systemDefaultUserAgent = '';
    try {
      systemDefaultUserAgent = webview.WebviewController.getDefaultUserAgent();
    } catch (_error) {
    }
    return this.resolve({
      tabId: tabId,
      currentUrl: currentUrl,
      profileId: profileId,
      privateBrowsing: privateBrowsing,
      systemDefaultUserAgent: systemDefaultUserAgent
    });
  }

  resolve(request: BrowserBrowsingIdentityPolicyRequest): BrowserBrowsingIdentityDecision {
    const decision = this.decisionService.decide(this.buildSnapshot(request));
    hilog.info(
      BROWSING_IDENTITY_DIAGNOSTIC_LOG_DOMAIN,
      BROWSING_IDENTITY_DIAGNOSTIC_LOG_TAG,
      `${BROWSING_IDENTITY_DIAGNOSTIC_PREFIX} policy tab=%{public}s host=%{public}s winner=%{public}s ` +
        'identity=%{public}s presentation=%{public}s uaMode=%{public}s hints=%{public}s private=%{public}s',
      request.tabId,
      this.userAgentService.extractHost(request.currentUrl),
      decision.winningSource,
      decision.profile.identityId,
      decision.profile.presentationMode,
      decision.profile.uaStringMode,
      decision.profile.clientHintsMode,
      request.privateBrowsing ? '1' : '0'
    );
    return decision;
  }

  resolveDisplayedMode(
    tabId: string,
    currentUrl: string,
    profileId: BrowserProfileId,
    privateBrowsing: boolean
  ): BrowserDesktopSiteMode {
    const settings = this.settingsRepository.getSettings();
    const currentTabIdentityId = this.getCurrentTabIdentityId(tabId);
    if (currentTabIdentityId.length > 0) {
      return this.resolveIdentityDisplayMode(currentTabIdentityId, settings);
    }
    if (!privateBrowsing) {
      const target = this.userAgentService.resolveSiteSettingTarget(currentUrl);
      const siteIdentityId = target === undefined ? '' :
        this.savedSiteSettingRepository.findEntry(target, profileId)?.overrides.userAgentIdentityId ?? '';
      if (siteIdentityId.length > 0 && siteIdentityId !== FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
        return this.resolveIdentityDisplayMode(siteIdentityId, settings);
      }
    }
    return 'default';
  }

  private buildSnapshot(request: BrowserBrowsingIdentityPolicyRequest): BrowserBrowsingIdentityPolicySnapshot {
    const settings = this.userAgentService.normalizeSettings(this.settingsRepository.getSettings());
    const applicationFamily = this.hostPolicyAdapter.resolveApplicationFamily();
    const target = this.userAgentService.resolveSiteSettingTarget(request.currentUrl);
    const host = this.userAgentService.extractHost(request.currentUrl);
    const siteEntry = request.privateBrowsing || target === undefined ? undefined :
      this.savedSiteSettingRepository.findEntry(target, request.profileId);
    const currentTabIdentityId = this.getCurrentTabIdentityId(request.tabId);
    const managedHostApplicationFamily = this.resolveManagedHostApplicationFamily(
      settings,
      applicationFamily,
      currentTabIdentityId,
      siteEntry?.overrides.userAgentIdentityId ?? ''
    );
    const mandatoryCompatibility = this.hostPolicyAdapter.resolveMandatoryCompatibility(
      host,
      managedHostApplicationFamily
    );
    const mandatoryHost = this.buildMandatoryCandidate(
      request,
      settings,
      applicationFamily,
      mandatoryCompatibility
    );
    const currentTab = this.buildIdentityCandidate(
      'current_tab',
      currentTabIdentityId,
      request,
      settings,
      applicationFamily,
      target,
      undefined
    );
    const exactOriginIdentityId = siteEntry?.overrides.userAgentIdentityId ?? '';
    const exactOrigin = this.buildIdentityCandidate(
      'exact_origin',
      exactOriginIdentityId,
      request,
      settings,
      applicationFamily,
      target,
      siteEntry
    );
    const global = this.buildGlobalCandidate(request, settings, applicationFamily);
    const applicableDefault = this.buildApplicableDefaultCandidate(request, applicationFamily);
    return {
      policySnapshotKey: this.buildPolicySnapshotKey(
        request,
        settings,
        mandatoryCompatibility,
        siteEntry,
        target
      ),
      mandatoryHost: mandatoryHost,
      currentTab: currentTab,
      exactOrigin: exactOrigin,
      global: global,
      airaCompatibility: this.emptyCandidate('aira_compatibility'),
      applicableDefault: applicableDefault
    };
  }

  private buildMandatoryCandidate(
    request: BrowserBrowsingIdentityPolicyRequest,
    settings: BrowserUserAgentSettings,
    applicationFamily: BrowserUserAgentApplicationFamily,
    mandatoryCompatibility: BrowserUserAgentMandatoryCompatibility | undefined
  ): BrowserBrowsingIdentityCandidate {
    if (mandatoryCompatibility === undefined) {
      return this.emptyCandidate('mandatory_host');
    }
    const resolution = this.userAgentService.resolveUserAgent({
      settings: settings,
      systemDefaultUserAgent: request.systemDefaultUserAgent,
      applicationFamily: applicationFamily,
      pageUrl: request.currentUrl,
      mandatoryCompatibility: mandatoryCompatibility
    });
    return this.availableCandidate('mandatory_host', mandatoryCompatibility.identityId, resolution);
  }

  private buildIdentityCandidate(
    source: BrowserBrowsingIdentityPrecedenceSource,
    identityId: string,
    request: BrowserBrowsingIdentityPolicyRequest,
    settings: BrowserUserAgentSettings,
    applicationFamily: BrowserUserAgentApplicationFamily,
    target: SiteSettingTarget | undefined,
    siteEntry: SavedSiteSettingEntry | undefined
  ): BrowserBrowsingIdentityCandidate {
    const normalizedIdentityId = identityId.trim();
    if (normalizedIdentityId.length <= 0 || normalizedIdentityId === FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      return this.emptyCandidate(source);
    }
    if (!this.hasIdentity(normalizedIdentityId, settings)) {
      return this.unavailableCandidate(source, normalizedIdentityId, 'The referenced Browsing Identity is unavailable.');
    }
    let resolution: BrowserUserAgentResolution;
    if (source === 'exact_origin' && target !== undefined && siteEntry !== undefined) {
      const siteOverride: BrowserUserAgentSiteOverride = {
        profileId: siteEntry.profileId,
        target: target,
        identityId: normalizedIdentityId,
        updatedAt: siteEntry.updatedAt
      };
      resolution = this.userAgentService.resolveUserAgent({
        settings: settings,
        systemDefaultUserAgent: request.systemDefaultUserAgent,
        applicationFamily: applicationFamily,
        pageUrl: request.currentUrl,
        siteSettingTarget: target,
        siteOverrides: [siteOverride],
        profileId: request.profileId
      });
    } else {
      resolution = this.userAgentService.resolveUserAgent({
        settings: settings,
        systemDefaultUserAgent: request.systemDefaultUserAgent,
        applicationFamily: applicationFamily,
        pageUrl: request.currentUrl,
        temporaryIdentityId: normalizedIdentityId
      });
    }
    if ((resolution.identityId ?? '').trim() !== normalizedIdentityId) {
      return this.unavailableCandidate(source, normalizedIdentityId, 'The referenced Browsing Identity could not be resolved.');
    }
    return this.availableCandidate(source, normalizedIdentityId, resolution);
  }

  private buildGlobalCandidate(
    request: BrowserBrowsingIdentityPolicyRequest,
    settings: BrowserUserAgentSettings,
    applicationFamily: BrowserUserAgentApplicationFamily
  ): BrowserBrowsingIdentityCandidate {
    if (!this.hasExplicitGlobalChoice(settings)) {
      return this.emptyCandidate('global');
    }
    const resolution = this.userAgentService.resolveUserAgent({
      settings: settings,
      systemDefaultUserAgent: request.systemDefaultUserAgent,
      applicationFamily: applicationFamily,
      pageUrl: request.currentUrl
    });
    return this.availableCandidate('global', resolution.profile.identityId, resolution);
  }

  private buildApplicableDefaultCandidate(
    request: BrowserBrowsingIdentityPolicyRequest,
    applicationFamily: BrowserUserAgentApplicationFamily
  ): BrowserBrowsingIdentityCandidate {
    const resolution = this.userAgentService.resolveUserAgent({
      settings: DEFAULT_BROWSER_USER_AGENT_SETTINGS,
      systemDefaultUserAgent: request.systemDefaultUserAgent,
      applicationFamily: applicationFamily,
      pageUrl: request.currentUrl
    });
    return this.availableCandidate('applicable_default', AIRA_DEFAULT_BROWSER_IDENTITY_ID, resolution);
  }

  private hasExplicitGlobalChoice(settings: BrowserUserAgentSettings): boolean {
    if (settings.defaultMode === 'custom' || settings.defaultMode === 'desktop') {
      return true;
    }
    return settings.selectedPresetId !== SYSTEM_DEFAULT_USER_AGENT_PRESET_ID;
  }

  private hasIdentity(identityId: string, settings: BrowserUserAgentSettings): boolean {
    if (identityId === AIRA_DEFAULT_BROWSER_IDENTITY_ID) {
      return true;
    }
    return this.userAgentService.getIdentityCatalog(settings)
      .some((identity: BrowserUserAgentIdentity): boolean => identity.id === identityId);
  }

  private resolveIdentityDisplayMode(
    identityId: string,
    settings: BrowserUserAgentSettings
  ): BrowserDesktopSiteMode {
    return this.userAgentService.resolvePresentationModeForIdentity(
      identityId,
      settings,
      this.hostPolicyAdapter.resolveApplicationFamily()
    );
  }

  private resolveManagedHostApplicationFamily(
    settings: BrowserUserAgentSettings,
    applicationFamily: BrowserUserAgentApplicationFamily,
    currentTabIdentityId: string,
    exactOriginIdentityId: string
  ): BrowserUserAgentApplicationFamily {
    const tabMode = this.userAgentService.resolvePresentationModeForIdentity(
      currentTabIdentityId,
      settings,
      applicationFamily
    );
    if (tabMode === 'desktop') {
      return 'desktop';
    }
    if (tabMode === 'mobile') {
      return 'mobile';
    }

    const siteMode = this.userAgentService.resolvePresentationModeForIdentity(
      exactOriginIdentityId,
      settings,
      applicationFamily
    );
    if (siteMode === 'desktop') {
      return 'desktop';
    }
    if (siteMode === 'mobile') {
      return 'mobile';
    }

    if (this.hasExplicitGlobalChoice(settings)) {
      const globalMode = this.userAgentService.resolvePresentationModeForSettings(
        settings,
        applicationFamily
      );
      if (globalMode === 'desktop') {
        return 'desktop';
      }
      if (globalMode === 'mobile') {
        return 'mobile';
      }
    }
    // Follow Global / Aira Default uses the physical family as the cloud
    // profile default: phone -> mobile, tablet/desktop -> desktop.
    return applicationFamily;
  }

  private availableCandidate(
    source: BrowserBrowsingIdentityPrecedenceSource,
    identityId: string,
    resolution: BrowserUserAgentResolution
  ): BrowserBrowsingIdentityCandidate {
    return {
      source: source,
      identityId: identityId,
      resolution: resolution,
      unavailableReason: ''
    };
  }

  private unavailableCandidate(
    source: BrowserBrowsingIdentityPrecedenceSource,
    identityId: string,
    unavailableReason: string
  ): BrowserBrowsingIdentityCandidate {
    return {
      source: source,
      identityId: identityId,
      unavailableReason: unavailableReason
    };
  }

  private emptyCandidate(source: BrowserBrowsingIdentityPrecedenceSource): BrowserBrowsingIdentityCandidate {
    return {
      source: source,
      identityId: '',
      unavailableReason: ''
    };
  }

  private buildPolicySnapshotKey(
    request: BrowserBrowsingIdentityPolicyRequest,
    settings: BrowserUserAgentSettings,
    mandatoryCompatibility: BrowserUserAgentMandatoryCompatibility | undefined,
    siteEntry: SavedSiteSettingEntry | undefined,
    target: SiteSettingTarget | undefined
  ): string {
    const tabId = request.tabId.trim();
    const hostRevision = mandatoryCompatibility === undefined ? 'none' :
      `${mandatoryCompatibility.ruleId}:${mandatoryCompatibility.identityId}:` +
      `${mandatoryCompatibility.userAgent}:${mandatoryCompatibility.reason}`;
    return [
      `catalog:${settings.updatedAt}`,
      `host:${hostRevision}`,
      `global:${settings.updatedAt}`,
      `site:${siteEntry?.revision ?? 0}`,
      `tab:${this.currentTabGenerationByTabId[tabId] ?? 0}`,
      `target:${target?.canonicalOrigin ?? ''}`,
      `profile:${request.profileId}`,
      `private:${request.privateBrowsing ? '1' : '0'}`
    ].join('|');
  }
}

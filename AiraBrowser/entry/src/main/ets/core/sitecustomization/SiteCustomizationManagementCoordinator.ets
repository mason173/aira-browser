import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSitePrivacyRule,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  ExternalNavigationAppOpenPolicy,
  ExternalNavigationSiteRule,
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserSitePrivacyRuleRepository } from '../../data/browser/BrowserSitePrivacyRuleRepository';
import { BrowserUserAgentSettingsRepository } from '../../data/browser/BrowserUserAgentSettingsRepository';
import {
  SavedSiteSettingRepository,
  SiteSettingCommitResult,
  SavedSiteSettingUnreadableEntry
} from '../../data/browser/SavedSiteSettingRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  BrowserDesktopSiteMode,
  BrowserUserAgentIdentity,
  AIRA_DEFAULT_BROWSER_IDENTITY_ID,
  DESKTOP_CHROME_USER_AGENT_PRESET_ID,
  FOLLOW_GLOBAL_BROWSER_IDENTITY_ID,
  BrowserUserAgentService
} from '../../services/web/BrowserUserAgentService';
import {
  BrowserSitePrivacyRuleMode,
  BrowserSitePrivacyRuleService
} from '../../services/web/BrowserSitePrivacyRuleService';
import {
  SiteCapabilityCatalogService,
  SiteCustomizationCapabilityFilterId,
  SitePermissionRuleOption
} from '../../services/web/SiteCapabilityCatalogService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import { SiteIdentityService } from '../../services/web/SiteIdentityService';
import {
  SiteControlCapabilityState,
  SiteControlsCoordinator,
  SiteControlsState
} from '../sitecontrols/SiteControlsCoordinator';
import { SiteCustomizationRefreshSignal } from './SiteCustomizationRefreshSignal';
import {
  SavedSiteSettingEntry,
  SavedSiteSettingOverrides,
  SiteSettingTarget
} from '../../common/models/SiteSettingModels';

export interface SiteCustomizationListRowState {
  id: string;
  host: string;
  origin: string;
  title: string;
  value: string;
  helperText: string;
  updatedAt: number;
  isEnabled: boolean;
}

export interface SiteCustomizationListState {
  query: string;
  totalCount: number;
  filteredCount: number;
  rows: SiteCustomizationListRowState[];
  hasRows: boolean;
  hasFilteredRows: boolean;
}

export interface SiteCustomizationPermissionOptionState {
  value: SitePermissionRule;
  label: string;
  helperText: string;
}

export interface SiteCustomizationPermissionGroupState {
  kind: SitePermissionKind;
  title: string;
  selectedRule: SitePermissionRule;
  options: SiteCustomizationPermissionOptionState[];
}

export type SiteJavaScriptPolicy = 'default' | 'allow' | 'block';

export interface SiteCustomizationDetailState {
  host: string;
  origin: string;
  title: string;
  summary: string;
  externalNavigationPolicy: ExternalNavigationAppOpenPolicy;
  hasExternalNavigationRule: boolean;
  desktopSiteSummary: string;
  hasDesktopSiteRule: boolean;
  javaScriptPolicy: SiteJavaScriptPolicy;
  hasJavaScriptRule: boolean;
  javaScriptCanApply: boolean;
  privateSiteEnabled: boolean;
  preserveCookiesOnClose: boolean;
  hasPrivateSiteRule: boolean;
  permissionGroups: SiteCustomizationPermissionGroupState[];
  hasAnyRules: boolean;
  resetEnabled: boolean;
  hasUnreadableEntry: boolean;
}

export interface SiteCustomizationUserAgentState {
  target?: SiteSettingTarget;
  revision: number;
  selectedIdentityId: string;
  identities: BrowserUserAgentIdentity[];
  canApply: boolean;
}

export interface SiteCustomizationManualTargetResult {
  target?: SiteSettingTarget;
  errorMessage: string;
}

interface SiteCustomizationAggregate {
  host: string;
  origin: string;
  externalNavigationRule?: ExternalNavigationSiteRule;
  privateSiteRule?: BrowserSitePrivacyRule;
  permissionSettings: SitePermissionSettings[];
  savedEntry?: SavedSiteSettingEntry;
  unreadableEntry?: SavedSiteSettingUnreadableEntry;
  updatedAt: number;
}

export class SiteCustomizationManagementCoordinator {
  private preferencesRepository: PreferencesRepository;
  private userAgentSettingsRepository: BrowserUserAgentSettingsRepository;
  private savedSiteSettingRepository: SavedSiteSettingRepository;
  private sitePrivacyRuleRepository: BrowserSitePrivacyRuleRepository;
  private userAgentService: BrowserUserAgentService = new BrowserUserAgentService();
  private sitePrivacyRuleService: BrowserSitePrivacyRuleService = new BrowserSitePrivacyRuleService();
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();
  private siteControlsCoordinator: SiteControlsCoordinator;
  private sitePolicyService?: SitePolicyService;
  private refreshSignal: SiteCustomizationRefreshSignal = new SiteCustomizationRefreshSignal();

  constructor(
    preferencesRepository: PreferencesRepository,
    userAgentSettingsRepository: BrowserUserAgentSettingsRepository,
    sitePrivacyRuleRepository: BrowserSitePrivacyRuleRepository,
    sitePolicyService: SitePolicyService | undefined,
    savedSiteSettingRepository: SavedSiteSettingRepository
  ) {
    this.preferencesRepository = preferencesRepository;
    this.userAgentSettingsRepository = userAgentSettingsRepository;
    this.sitePrivacyRuleRepository = sitePrivacyRuleRepository;
    this.sitePolicyService = sitePolicyService;
    this.savedSiteSettingRepository = savedSiteSettingRepository;
    this.siteControlsCoordinator = new SiteControlsCoordinator(preferencesRepository);
  }

  async retireLegacySingleSiteRules(): Promise<void> {
    await this.userAgentSettingsRepository.clearLegacySiteRules();
    await this.sitePrivacyRuleRepository.clearAllSiteRules();
    await this.preferencesRepository.clearAllSitePermissionSettingsForAllProfiles();
    await this.preferencesRepository.clearAllExternalNavigationSiteRules();
  }

  buildListState(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    query: string = ''
  ): SiteCustomizationListState {
    const aggregates = this.collectAggregates(profileId);
    const rows = aggregates
      .map((aggregate: SiteCustomizationAggregate) => this.buildListRow(aggregate))
      .filter((row: SiteCustomizationListRowState) => this.matchesQuery(row, query))
      .sort((left: SiteCustomizationListRowState, right: SiteCustomizationListRowState) => {
        if (left.updatedAt !== right.updatedAt) {
          return right.updatedAt - left.updatedAt;
        }
        return left.title.localeCompare(right.title);
      });
    return {
      query: query,
      totalCount: aggregates.length,
      filteredCount: rows.length,
      rows: rows,
      hasRows: rows.length > 0,
      hasFilteredRows: rows.length > 0
    };
  }

  resolveManualTarget(value: string): SiteCustomizationManualTargetResult {
    const trimmed = value.trim();
    if (trimmed.length <= 0) {
      return { errorMessage: '请输入站点地址。' };
    }
    const target = this.resolveTarget(trimmed);
    if (target === undefined) {
      return { errorMessage: '请输入有效的 HTTP 或 HTTPS 站点地址。' };
    }
    return {
      target: target,
      errorMessage: ''
    };
  }

  buildCapabilityListState(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    capabilityId: SiteCustomizationCapabilityFilterId,
    query: string = ''
  ): SiteCustomizationListState {
    const aggregates = this.collectAggregates(profileId)
      .filter((aggregate: SiteCustomizationAggregate) => this.matchesCapabilityFilter(aggregate, capabilityId));
    const rows = aggregates
      .map((aggregate: SiteCustomizationAggregate) => this.buildCapabilityListRow(aggregate, capabilityId))
      .filter((row: SiteCustomizationListRowState) => this.matchesQuery(row, query))
      .sort((left: SiteCustomizationListRowState, right: SiteCustomizationListRowState) => {
        if (left.updatedAt !== right.updatedAt) {
          return right.updatedAt - left.updatedAt;
        }
        return left.title.localeCompare(right.title);
      });
    return {
      query: query,
      totalCount: aggregates.length,
      filteredCount: rows.length,
      rows: rows,
      hasRows: rows.length > 0,
      hasFilteredRows: rows.length > 0
    };
  }

  buildDetailState(
    host: string,
    origin: string = '',
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): SiteCustomizationDetailState {
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin);
    const normalizedDataScope = this.resolveDataScope(dataScope, privacyMode);
    const siteControls = this.siteControlsCoordinator.buildState(normalizedHost, normalizedOrigin, profileId);
    const externalNavigationState = this.findCapabilityState(siteControls, 'open_app');
    const privateSiteRule = this.findPrivateSiteRule(normalizedHost, normalizedOrigin, profileId);
    const sessionPermissionSettings = this.resolveSessionPermissionSettings(
      normalizedHost,
      normalizedOrigin,
      profileId,
      normalizedDataScope
    );
    const permissionGroups = sessionPermissionSettings === undefined
      ? this.buildPermissionGroupsFromControls(siteControls)
      : this.buildPermissionGroupsFromSettings(sessionPermissionSettings);
    const savedTarget = this.resolveTarget(normalizedOrigin);
    const savedEntry = savedTarget === undefined
      ? undefined
      : this.savedSiteSettingRepository.findEntry(savedTarget, profileId);
    const unreadableEntry = this.savedSiteSettingRepository.findUnreadableEntry(
      normalizedOrigin,
      profileId
    );
    const isUnreadable = unreadableEntry !== undefined;
    const summaryParts: string[] = [];
    if (isUnreadable) {
      summaryParts.push('站点设置数据不可读，请重置后重新设置');
    } else if (savedEntry !== undefined && savedEntry.overrides.userAgentIdentityId !== undefined) {
      summaryParts.push(this.resolveSavedIdentitySummary(savedEntry));
    }
    if (typeof savedEntry?.overrides.javaScriptEnabled === 'boolean') {
      summaryParts.push(savedEntry.overrides.javaScriptEnabled ? 'JavaScript 已允许' : 'JavaScript 已阻止');
    }
    if (privateSiteRule !== undefined) {
      summaryParts.push(privateSiteRule.preserveCookiesOnClose ? '关闭后清除，保留 Cookie' : '关闭后清除');
    }
    const sessionPermissionSummary = this.buildPermissionSettingsSummary(sessionPermissionSettings);
    if (sessionPermissionSummary.length > 0) {
      summaryParts.push(sessionPermissionSummary);
    } else if (siteControls.summary.length > 0) {
      summaryParts.push(siteControls.summary);
    }
    return {
      host: normalizedHost,
      origin: siteControls.origin.length > 0 ? siteControls.origin : normalizedOrigin,
      title: normalizedOrigin.length > 0 ? normalizedOrigin : normalizedHost.length > 0 ? normalizedHost : '当前站点',
      summary: summaryParts.length > 0 ? summaryParts.join(' · ') : '还没有为这个站点设置过任何规则',
      externalNavigationPolicy: this.resolveExternalNavigationPolicy(externalNavigationState),
      hasExternalNavigationRule: externalNavigationState?.hasSiteRule ?? false,
      desktopSiteSummary: savedEntry !== undefined && savedEntry.overrides.userAgentIdentityId !== undefined
        ? this.resolveSavedIdentitySummary(savedEntry)
        : '跟随全局',
      hasDesktopSiteRule: savedEntry !== undefined && savedEntry.overrides.userAgentIdentityId !== undefined,
      javaScriptPolicy: this.resolveJavaScriptPolicy(savedEntry),
      hasJavaScriptRule: typeof savedEntry?.overrides.javaScriptEnabled === 'boolean',
      javaScriptCanApply: normalizedDataScope === 'profile_persistent',
      privateSiteEnabled: privateSiteRule !== undefined,
      preserveCookiesOnClose: privateSiteRule?.preserveCookiesOnClose === true,
      hasPrivateSiteRule: privateSiteRule !== undefined,
      permissionGroups: permissionGroups,
      hasAnyRules: isUnreadable || savedEntry !== undefined || siteControls.hasAnySiteRules ||
        privateSiteRule !== undefined,
      resetEnabled: isUnreadable || savedEntry !== undefined || siteControls.hasAnySiteRules ||
        privateSiteRule !== undefined,
      hasUnreadableEntry: isUnreadable
    };
  }

  resolveSiteUserAgentMode(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): BrowserDesktopSiteMode {
    const target = this.resolveTarget(origin.length > 0 ? origin : host);
    const entry = target === undefined
      ? undefined
      : this.savedSiteSettingRepository.findEntry(target, profileId);
    const identityId = entry?.overrides.userAgentIdentityId ?? '';
    if (target === undefined || identityId.length <= 0) {
      return 'default';
    }
    const identity = this.userAgentService.getIdentityCatalog(this.userAgentSettingsRepository.getSettings())
      .find((item: BrowserUserAgentIdentity) => item.id === identityId);
    if (identity === undefined) {
      return 'default';
    }
    return identity.mode === 'desktop' ? 'desktop' : 'mobile';
  }

  async setSiteUserAgentMode(
    host: string,
    origin: string,
    mode: BrowserDesktopSiteMode,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<SiteSettingCommitResult> {
    const identityId = mode === 'desktop'
      ? DESKTOP_CHROME_USER_AGENT_PRESET_ID
      : mode === 'mobile'
        ? AIRA_DEFAULT_BROWSER_IDENTITY_ID
        : FOLLOW_GLOBAL_BROWSER_IDENTITY_ID;
    const state = this.buildUserAgentState(host, origin, profileId);
    return this.commitUserAgentIdentity(host, origin, identityId, state.revision, profileId);
  }

  private async resetSiteUserAgent(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    const state = this.buildUserAgentState(host, origin, profileId);
    if (state.target === undefined || state.revision <= 0) {
      return;
    }
    await this.commitUserAgentIdentity(
      host,
      origin,
      FOLLOW_GLOBAL_BROWSER_IDENTITY_ID,
      state.revision,
      profileId
    );
  }

  buildUserAgentState(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): SiteCustomizationUserAgentState {
    const target = this.resolveTarget(origin.length > 0 ? origin : host);
    const persistentAllowed = this.resolveDataScope(dataScope, privacyMode) === 'profile_persistent';
    const entry = !persistentAllowed || target === undefined
      ? undefined
      : this.savedSiteSettingRepository.findEntry(target, profileId);
    return {
      target: target,
      revision: entry?.revision ?? 0,
      selectedIdentityId: entry?.overrides.userAgentIdentityId ?? FOLLOW_GLOBAL_BROWSER_IDENTITY_ID,
      identities: this.userAgentService.getIdentityCatalog(this.userAgentSettingsRepository.getSettings()),
      canApply: persistentAllowed && target !== undefined
    };
  }

  async commitUserAgentIdentity(
    host: string,
    origin: string,
    identityId: string,
    expectedRevision: number,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): Promise<SiteSettingCommitResult> {
    const target = this.resolveTarget(origin.length > 0 ? origin : host);
    if (this.resolveDataScope(dataScope, privacyMode) !== 'profile_persistent' || target === undefined) {
      return { status: 'invalid' };
    }
    const normalizedIdentityId = identityId.trim();
    const knownIdentity = this.userAgentService.getIdentityCatalog(this.userAgentSettingsRepository.getSettings())
      .some((identity: BrowserUserAgentIdentity) => identity.id === normalizedIdentityId);
    if (!knownIdentity) {
      return { status: 'invalid' };
    }
    const current = this.savedSiteSettingRepository.findEntry(target, profileId);
    const nextOverrides: SavedSiteSettingOverrides = current === undefined
      ? {}
      : this.copyOverrides(current.overrides);
    if (normalizedIdentityId === FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      nextOverrides.userAgentIdentityId = undefined;
    } else {
      nextOverrides.userAgentIdentityId = normalizedIdentityId;
    }
    return this.savedSiteSettingRepository.commit(target, profileId, nextOverrides, expectedRevision);
  }

  async setJavaScriptPolicy(
    host: string,
    origin: string,
    policy: SiteJavaScriptPolicy,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): Promise<SiteSettingCommitResult> {
    const target = this.resolveTarget(origin.length > 0 ? origin : host);
    if (this.resolveDataScope(dataScope, privacyMode) !== 'profile_persistent' || target === undefined) {
      return { status: 'invalid' };
    }
    const current = this.savedSiteSettingRepository.findEntry(target, profileId);
    const nextOverrides: SavedSiteSettingOverrides = current === undefined
      ? {}
      : this.copyOverrides(current.overrides);
    if (policy === 'default') {
      nextOverrides.javaScriptEnabled = undefined;
    } else {
      nextOverrides.javaScriptEnabled = policy === 'allow';
    }
    const result = await this.savedSiteSettingRepository.commit(
      target,
      profileId,
      nextOverrides,
      current?.revision ?? 0
    );
    if (result.status === 'saved' || result.status === 'deleted') {
      this.refreshSignal.bump('javascript', target.canonicalOrigin, profileId);
    }
    return result;
  }

  async setPrivateSiteMode(
    host: string,
    origin: string,
    mode: BrowserSitePrivacyRuleMode,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    if (mode === 'default') {
      await this.resetPrivateSiteRule(host, origin, profileId);
      return;
    }
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin.length > 0 ? origin : host);
    const ruleOrigin = normalizedOrigin.length > 0 ? normalizedOrigin : `https://${normalizedHost}`;
    if (ruleOrigin.length === 0) {
      return;
    }
    const existingRule = this.findPrivateSiteRule(normalizedHost, normalizedOrigin, profileId);
    await this.sitePrivacyRuleRepository.upsertSiteRule(
      profileId,
      ruleOrigin,
      mode,
      false,
      existingRule?.preserveCookiesOnClose === true
    );
  }

  async setPrivateSitePreserveCookies(
    host: string,
    origin: string,
    preserveCookies: boolean,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin.length > 0 ? origin : host);
    const ruleOrigin = normalizedOrigin.length > 0 ? normalizedOrigin : `https://${normalizedHost}`;
    if (ruleOrigin.length === 0) {
      return;
    }
    await this.sitePrivacyRuleRepository.upsertSiteRule(
      profileId,
      ruleOrigin,
      'clear_on_close',
      false,
      preserveCookies
    );
  }

  async resetPrivateSiteRule(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    const existingRule = this.findPrivateSiteRule(
      this.normalizeHostKey(host),
      this.normalizeOriginKey(origin),
      profileId
    );
    if (existingRule === undefined) {
      return;
    }
    await this.sitePrivacyRuleRepository.removeSiteRule(existingRule.origin, profileId);
  }

  async updatePermissionRule(
    host: string,
    origin: string,
    kind: SitePermissionKind,
    rule: SitePermissionRule,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): Promise<void> {
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin.length > 0 ? origin : host);
    const permissionOrigins = this.resolvePermissionTargetOrigins(normalizedHost, normalizedOrigin, profileId);
    if (permissionOrigins.length === 0) {
      return;
    }
    const normalizedDataScope = this.resolveDataScope(dataScope, privacyMode);
    if (this.sitePolicyService !== undefined) {
      await this.sitePolicyService.persistPermissionRuleForOrigins(
        permissionOrigins,
        [kind],
        rule,
        profileId,
        normalizedDataScope
      );
      return;
    }
    for (let index = 0; index < permissionOrigins.length; index += 1) {
      const permissionOrigin = permissionOrigins[index];
      await this.preferencesRepository.updateSitePermissionRule(permissionOrigin, kind, rule, profileId);
      this.applySitePermissionRuleSideEffects(permissionOrigin, kind, rule, profileId);
    }
  }

  async updateExternalNavigationPolicy(
    host: string,
    origin: string,
    policy: ExternalNavigationAppOpenPolicy,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin.length > 0 ? origin : host);
    const identity = this.siteIdentityService.resolve(normalizedOrigin.length > 0 ? normalizedOrigin : normalizedHost);
    if (identity.primaryOrigin.length === 0) {
      return;
    }
    const currentSettings = this.preferencesRepository.getPreferences().externalNavigation;
    const nextRules = currentSettings.siteRules
      .filter((rule: ExternalNavigationSiteRule) => rule.primaryOrigin !== identity.primaryOrigin ||
        rule.profileId !== profileId)
      .concat([{
        profileId: profileId,
        origin: identity.primaryOrigin,
        siteKey: identity.siteKey,
        displayHost: identity.displayHost,
        primaryOrigin: identity.primaryOrigin,
        policy: policy,
        updatedAt: Date.now()
      }])
      .slice(-120);
    await this.preferencesRepository.updateExternalNavigationSettings({
      appOpenPolicy: currentSettings.appOpenPolicy,
      suppressAfterCancelMs: currentSettings.suppressAfterCancelMs,
      siteRules: nextRules
    });
  }

  async resetExternalNavigationPolicy(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<void> {
    const normalizedOrigin = this.normalizeOriginKey(origin);
    const currentSettings = this.preferencesRepository.getPreferences().externalNavigation;
    const nextRules = currentSettings.siteRules.filter((rule: ExternalNavigationSiteRule) => {
      if (rule.profileId !== profileId) {
        return true;
      }
      return normalizedOrigin.length <= 0 || rule.primaryOrigin !== normalizedOrigin;
    });
    if (nextRules.length === currentSettings.siteRules.length) {
      return;
    }
    await this.preferencesRepository.updateExternalNavigationSettings({
      appOpenPolicy: currentSettings.appOpenPolicy,
      suppressAfterCancelMs: currentSettings.suppressAfterCancelMs,
      siteRules: nextRules
    });
  }

  async resetSiteCustomizations(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): Promise<void> {
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin);
    const normalizedDataScope = this.resolveDataScope(dataScope, privacyMode);
    const unreadableEntry = this.savedSiteSettingRepository.findUnreadableEntry(normalizedOrigin, profileId);
    if (unreadableEntry !== undefined) {
      const reset = await this.savedSiteSettingRepository.resetUnreadableEntry(normalizedOrigin, profileId);
      if (!reset) {
        throw new Error('站点设置已被其他窗口修改，请刷新后重试。');
      }
    }
    const externalNavigationSettings = this.preferencesRepository.getPreferences().externalNavigation;
    const nextExternalNavigationRules = externalNavigationSettings.siteRules.filter((rule: ExternalNavigationSiteRule) => {
      if (rule.profileId !== profileId) {
        return true;
      }
      return normalizedOrigin.length <= 0 || rule.primaryOrigin !== normalizedOrigin;
    });
    if (nextExternalNavigationRules.length !== externalNavigationSettings.siteRules.length) {
      await this.preferencesRepository.updateExternalNavigationSettings({
        appOpenPolicy: externalNavigationSettings.appOpenPolicy,
        suppressAfterCancelMs: externalNavigationSettings.suppressAfterCancelMs,
        siteRules: nextExternalNavigationRules
      });
    }
    if (unreadableEntry === undefined) {
      await this.resetSiteUserAgent(normalizedHost, normalizedOrigin, profileId);
      await this.resetSiteJavaScript(normalizedHost, normalizedOrigin, profileId);
    }
    await this.resetPrivateSiteRule(normalizedHost, normalizedOrigin, profileId);
    await this.resetPermissionSettingsForSite(normalizedHost, normalizedOrigin, profileId, normalizedDataScope);
  }

  async resetSiteControls(
    host: string,
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope | string = 'profile_persistent',
    privacyMode: BrowserSessionPrivacyMode | string = 'regular'
  ): Promise<void> {
    const normalizedHost = this.normalizeHostKey(host);
    const normalizedOrigin = this.normalizeOriginKey(origin);
    const normalizedDataScope = this.resolveDataScope(dataScope, privacyMode);
    const unreadableEntry = this.savedSiteSettingRepository.findUnreadableEntry(normalizedOrigin, profileId);
    if (unreadableEntry !== undefined) {
      const reset = await this.savedSiteSettingRepository.resetUnreadableEntry(normalizedOrigin, profileId);
      if (!reset) {
        throw new Error('站点设置已被其他窗口修改，请刷新后重试。');
      }
    }
    const externalNavigationSettings = this.preferencesRepository.getPreferences().externalNavigation;
    const nextExternalNavigationRules = externalNavigationSettings.siteRules.filter((rule: ExternalNavigationSiteRule) => {
      if (rule.profileId !== profileId) {
        return true;
      }
      return normalizedOrigin.length <= 0 || rule.primaryOrigin !== normalizedOrigin;
    });
    if (nextExternalNavigationRules.length !== externalNavigationSettings.siteRules.length) {
      await this.preferencesRepository.updateExternalNavigationSettings({
        appOpenPolicy: externalNavigationSettings.appOpenPolicy,
        suppressAfterCancelMs: externalNavigationSettings.suppressAfterCancelMs,
        siteRules: nextExternalNavigationRules
      });
    }
    await this.resetSiteJavaScript(normalizedHost, normalizedOrigin, profileId);
    await this.resetPermissionSettingsForSite(normalizedHost, normalizedOrigin, profileId, normalizedDataScope);
  }

  private async resetPermissionSettingsForSite(
    normalizedHost: string,
    normalizedOrigin: string,
    profileId: BrowserProfileId,
    dataScope: BrowserDataScope
  ): Promise<void> {
    if (dataScope === 'session_ephemeral') {
      const origins = this.resolvePermissionTargetOrigins(normalizedHost, normalizedOrigin, profileId);
      this.sitePolicyService?.clearSessionSitePermissionSettingsForOrigins(origins, profileId);
      return;
    }
    const permissionSettings = this.preferencesRepository.listSitePermissionSettings(profileId);
    const targets = permissionSettings.filter((item: SitePermissionSettings) => {
      return normalizedOrigin.length > 0 && item.primaryOrigin === normalizedOrigin;
    });
    for (let index = 0; index < targets.length; index += 1) {
      await this.preferencesRepository.removeSitePermissionSettings(targets[index].primaryOrigin, profileId);
    }
    this.clearRemovedPermissionTargets(targets, profileId);
  }

  private applySitePermissionRuleSideEffects(
    origin: string,
    kind: SitePermissionKind,
    rule: SitePermissionRule,
    profileId: BrowserProfileId
  ): void {
    if (this.sitePolicyService === undefined || origin.length === 0) {
      return;
    }
    if (rule !== 'allow') {
      this.sitePolicyService.clearPermissionSessionGrants({
        origins: [origin],
        kinds: [kind],
        profileId: profileId,
        dataScope: 'profile_persistent'
      });
    }
  }

  private clearRemovedPermissionTargets(targets: SitePermissionSettings[], profileId: BrowserProfileId): void {
    if (this.sitePolicyService === undefined || targets.length === 0) {
      return;
    }
    const origins = targets.map((settings: SitePermissionSettings) => settings.primaryOrigin);
    this.sitePolicyService.clearPermissionSessionGrants({
      origins: origins,
      profileId: profileId,
      dataScope: 'profile_persistent'
    });
  }

  private collectAggregates(profileId: BrowserProfileId): SiteCustomizationAggregate[] {
    const map: Map<string, SiteCustomizationAggregate> = new Map<string, SiteCustomizationAggregate>();

    this.savedSiteSettingRepository.listEntries(profileId)
      .forEach((entry: SavedSiteSettingEntry) => {
        const origin = entry.target.canonicalOrigin;
        const next = this.getOrCreateAggregate(map, origin, entry.target.displayHost);
        next.savedEntry = entry;
        next.origin = origin;
        next.host = entry.target.displayHost;
        next.updatedAt = Math.max(next.updatedAt, entry.updatedAt);
      });

    this.preferencesRepository.getPreferences().externalNavigation.siteRules
      .filter((item: ExternalNavigationSiteRule) => item.profileId === profileId)
      .forEach((item: ExternalNavigationSiteRule) => {
        const origin = this.normalizeOriginKey(item.primaryOrigin);
        const host = this.normalizeHostKey(item.displayHost);
        if (origin.length === 0 || host.length === 0) {
          return;
        }
        const next = this.getOrCreateAggregate(map, origin, host);
        next.externalNavigationRule = item;
        next.origin = item.primaryOrigin;
        next.updatedAt = Math.max(next.updatedAt, item.updatedAt);
        map.set(this.exactAggregateKey(origin), next);
      });

    this.savedSiteSettingRepository.listUnreadableEntries(profileId)
      .forEach((entry: SavedSiteSettingUnreadableEntry) => {
        const origin = entry.canonicalOrigin;
        const target = this.resolveTarget(origin);
        const host = target?.displayHost ?? this.normalizeHostKey(origin);
        const next = this.getOrCreateAggregate(map, origin, host);
        next.unreadableEntry = entry;
        next.origin = origin;
        next.host = host;
        next.updatedAt = Math.max(next.updatedAt, entry.updatedAt);
      });

    this.preferencesRepository.listSitePermissionSettings(profileId)
      .forEach((item: SitePermissionSettings) => {
        const origin = this.normalizeOriginKey(item.primaryOrigin);
        const host = this.normalizeHostKey(item.displayHost);
        if (origin.length === 0 || host.length === 0) {
          return;
        }
        const next = this.getOrCreateAggregate(map, origin, host);
        next.permissionSettings.push(item);
        if (item.updatedAt >= next.updatedAt) {
          next.origin = item.primaryOrigin;
        }
        next.updatedAt = Math.max(next.updatedAt, item.updatedAt);
        map.set(this.exactAggregateKey(origin), next);
      });

    this.sitePrivacyRuleRepository.listSiteRules(profileId)
      .forEach((item: BrowserSitePrivacyRule) => {
        const origin = this.normalizeOriginKey(item.primaryOrigin);
        const host = this.normalizeHostKey(item.displayHost);
        if (origin.length === 0 || host.length === 0) {
          return;
        }
        const next = this.getOrCreateAggregate(map, origin, host);
        next.privateSiteRule = item;
        next.origin = origin;
        next.updatedAt = Math.max(next.updatedAt, item.updatedAt);
        map.set(this.exactAggregateKey(origin), next);
      });

    return Array.from(map.values());
  }

  private buildListRow(aggregate: SiteCustomizationAggregate): SiteCustomizationListRowState {
    if (aggregate.unreadableEntry !== undefined) {
      return {
        id: aggregate.origin.length > 0 ? aggregate.origin : aggregate.host,
        host: aggregate.host,
        origin: aggregate.origin,
        title: aggregate.origin.length > 0 ? aggregate.origin : aggregate.host.length > 0 ? aggregate.host : '未知站点',
        value: '站点设置数据不可读',
        helperText: '打开后可重置此记录',
        updatedAt: aggregate.updatedAt,
        isEnabled: true
      };
    }
    const valueParts: string[] = [];
    if (aggregate.externalNavigationRule !== undefined) {
      valueParts.push(`打开应用${this.getExternalNavigationPolicyLabel(aggregate.externalNavigationRule.policy)}`);
    }
    if (aggregate.savedEntry !== undefined && aggregate.savedEntry.overrides.userAgentIdentityId !== undefined) {
      valueParts.push(this.resolveSavedIdentitySummary(aggregate.savedEntry));
    }
    if (typeof aggregate.savedEntry?.overrides.javaScriptEnabled === 'boolean') {
      valueParts.push(aggregate.savedEntry.overrides.javaScriptEnabled ? 'JavaScript 允许' : 'JavaScript 阻止');
    }
    if (aggregate.privateSiteRule !== undefined) {
      valueParts.push(aggregate.privateSiteRule.preserveCookiesOnClose ? '关闭后清除，保留 Cookie' : '关闭后清除');
    }
    if (aggregate.permissionSettings.length > 0) {
      valueParts.push(`${aggregate.permissionSettings.length} 项权限`);
    }
    const helperParts: string[] = [];
    if (aggregate.externalNavigationRule !== undefined) {
      helperParts.push('打开应用');
    }
    if (aggregate.savedEntry !== undefined && aggregate.savedEntry.overrides.userAgentIdentityId !== undefined) {
      helperParts.push('网页标识');
    }
    if (typeof aggregate.savedEntry?.overrides.javaScriptEnabled === 'boolean') {
      helperParts.push('JavaScript');
    }
    if (aggregate.privateSiteRule !== undefined) {
      helperParts.push('关闭后清除');
    }
    if (aggregate.permissionSettings.length > 0) {
      helperParts.push('权限');
    }
    return {
      id: aggregate.origin.length > 0 ? aggregate.origin : aggregate.host,
      host: aggregate.host,
      origin: aggregate.origin,
      title: aggregate.origin.length > 0 ? aggregate.origin : aggregate.host.length > 0 ? aggregate.host : '未知站点',
      value: valueParts.length > 0 ? valueParts.join(' · ') : '已自定义',
      helperText: helperParts.length > 0 ? helperParts.join(' · ') : '点开继续管理',
      updatedAt: aggregate.updatedAt,
      isEnabled: true
    };
  }

  private buildCapabilityListRow(
    aggregate: SiteCustomizationAggregate,
    capabilityId: SiteCustomizationCapabilityFilterId
  ): SiteCustomizationListRowState {
    return {
      id: `${capabilityId}:${aggregate.origin.length > 0 ? aggregate.origin : aggregate.host}`,
      host: aggregate.host,
      origin: aggregate.origin,
      title: aggregate.origin.length > 0 ? aggregate.origin : aggregate.host.length > 0 ? aggregate.host : '未知站点',
      value: this.buildCapabilityValue(aggregate, capabilityId),
      helperText: '',
      updatedAt: this.resolveCapabilityUpdatedAt(aggregate, capabilityId),
      isEnabled: true
    };
  }

  private matchesCapabilityFilter(
    aggregate: SiteCustomizationAggregate,
    capabilityId: SiteCustomizationCapabilityFilterId
  ): boolean {
    if (capabilityId === 'external_actions') {
      return aggregate.externalNavigationRule !== undefined;
    }
    if (capabilityId === 'desktop_site') {
      return aggregate.savedEntry?.overrides.userAgentIdentityId !== undefined;
    }
    if (capabilityId === 'javascript') {
      return typeof aggregate.savedEntry?.overrides.javaScriptEnabled === 'boolean';
    }
    return aggregate.privateSiteRule !== undefined;
  }

  private buildCapabilityValue(
    aggregate: SiteCustomizationAggregate,
    capabilityId: SiteCustomizationCapabilityFilterId
  ): string {
    if (capabilityId === 'external_actions') {
      return aggregate.externalNavigationRule === undefined
        ? '询问'
        : this.getExternalNavigationPolicyLabel(aggregate.externalNavigationRule.policy);
    }
    if (capabilityId === 'desktop_site') {
      return aggregate.savedEntry === undefined ? '跟随全局' : this.resolveSavedIdentitySummary(aggregate.savedEntry);
    }
    if (capabilityId === 'javascript') {
      return aggregate.savedEntry?.overrides.javaScriptEnabled === true ? '允许' : '阻止';
    }
    return this.sitePrivacyRuleService.resolveRuleSummary(aggregate.privateSiteRule);
  }

  private resolveCapabilityUpdatedAt(
    aggregate: SiteCustomizationAggregate,
    capabilityId: SiteCustomizationCapabilityFilterId
  ): number {
    if (capabilityId === 'external_actions') {
      return aggregate.externalNavigationRule?.updatedAt ?? aggregate.updatedAt;
    }
    if (capabilityId === 'desktop_site') {
      return aggregate.savedEntry?.updatedAt ?? aggregate.updatedAt;
    }
    if (capabilityId === 'javascript') {
      return aggregate.savedEntry?.updatedAt ?? aggregate.updatedAt;
    }
    return aggregate.privateSiteRule?.updatedAt ?? aggregate.updatedAt;
  }

  private buildPermissionGroupsFromControls(
    siteControls: SiteControlsState
  ): SiteCustomizationPermissionGroupState[] {
    return siteControls.devicePermissions.map((capability: SiteControlCapabilityState) => {
      return this.buildPermissionGroup(capability.id as SitePermissionKind, capability.rule as SitePermissionRule);
    });
  }

  private buildPermissionGroupsFromSettings(settings: SitePermissionSettings): SiteCustomizationPermissionGroupState[] {
    return this.capabilityCatalog.listDevicePermissionKinds().map((kind: SitePermissionKind) => {
      return this.buildPermissionGroup(kind, this.getPermissionRule(settings, kind));
    });
  }

  private buildPermissionGroup(
    kind: SitePermissionKind,
    selectedRule: SitePermissionRule
  ): SiteCustomizationPermissionGroupState {
    return {
      kind: kind,
      title: this.capabilityCatalog.getPermissionTitle(kind),
      selectedRule: selectedRule,
      options: this.capabilityCatalog.buildDefaultPermissionOptions().map((option: SitePermissionRuleOption) => {
        const nextOption: SiteCustomizationPermissionOptionState = {
          value: option.value,
          label: option.label,
          helperText: option.helperText
        };
        return nextOption;
      })
    };
  }

  private resolveSessionPermissionSettings(
    host: string,
    origin: string,
    profileId: BrowserProfileId,
    dataScope: BrowserDataScope
  ): SitePermissionSettings | undefined {
    if (dataScope !== 'session_ephemeral' || this.sitePolicyService === undefined) {
      return undefined;
    }
    const permissionOrigin = this.resolvePermissionOrigin(host, origin);
    if (permissionOrigin.length === 0) {
      return undefined;
    }
    return this.sitePolicyService.getEffectiveSitePermissionSettings(permissionOrigin, profileId, dataScope);
  }

  private buildPermissionSettingsSummary(settings: SitePermissionSettings | undefined): string {
    if (settings === undefined || settings.updatedAt <= 0) {
      return '';
    }
    const parts: string[] = [];
    this.capabilityCatalog.listDevicePermissionKinds().forEach((kind: SitePermissionKind) => {
      const rule = this.getPermissionRule(settings, kind);
      if (rule === this.getDefaultPermissionRule(kind)) {
        return;
      }
      parts.push(`${this.capabilityCatalog.getPermissionTitle(kind)}${this.capabilityCatalog.getPermissionRuleLabel(rule)}`);
    });
    return parts.join(' · ');
  }

  private getPermissionRule(settings: SitePermissionSettings, kind: SitePermissionKind): SitePermissionRule {
    if (kind === 'camera') {
      return settings.camera;
    }
    if (kind === 'microphone') {
      return settings.microphone;
    }
    if (kind === 'location') {
      return settings.location;
    }
    if (kind === 'sensor') {
      return settings.sensor;
    }
    return settings.clipboard;
  }

  private getDefaultPermissionRule(kind: SitePermissionKind): SitePermissionRule {
    const defaults = this.preferencesRepository.getPreferences().sitePermissionDefaults;
    if (kind === 'camera') {
      return defaults.camera;
    }
    if (kind === 'microphone') {
      return defaults.microphone;
    }
    if (kind === 'location') {
      return defaults.location;
    }
    if (kind === 'sensor') {
      return defaults.sensor;
    }
    return defaults.clipboard;
  }

  private resolveDataScope(
    dataScope: BrowserDataScope | string,
    privacyMode: BrowserSessionPrivacyMode | string
  ): BrowserDataScope {
    const normalizedPrivacyMode = normalizeBrowserSessionPrivacyMode(privacyMode);
    return normalizeBrowserDataScope(dataScope, normalizedPrivacyMode);
  }

  private resolvePermissionTargetOrigins(
    host: string,
    origin: string,
    profileId: BrowserProfileId
  ): string[] {
    const hostKey = host.length > 0 ? host : this.extractHostKey(origin);
    const primaryOrigin = this.resolvePermissionOrigin(hostKey, origin);
    let origins: string[] = [];
    origins = this.addOriginIfMissing(origins, primaryOrigin);
    return origins;
  }

  private resolvePermissionOrigin(host: string, origin: string): string {
    const normalizedOrigin = this.normalizeOriginKey(origin);
    const originMatch = /^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/?#]+)/.exec(normalizedOrigin);
    if (originMatch !== null) {
      return originMatch[1];
    }
    const originHost = this.extractHostKey(normalizedOrigin);
    const targetHost = host.length > 0 ? host : originHost;
    if (targetHost.length === 0) {
      return '';
    }
    return `https://${targetHost}`;
  }

  private addOriginIfMissing(origins: string[], origin: string): string[] {
    const normalizedOrigin = this.normalizeOriginKey(origin);
    if (normalizedOrigin.length === 0 || origins.indexOf(normalizedOrigin) >= 0) {
      return origins;
    }
    return origins.concat([normalizedOrigin]);
  }

  private findPrivateSiteRule(
    _host: string,
    origin: string,
    profileId: BrowserProfileId
  ): BrowserSitePrivacyRule | undefined {
    const rules = this.sitePrivacyRuleRepository.listSiteRules(profileId);
    return origin.length > 0
      ? rules.find((rule: BrowserSitePrivacyRule) => rule.primaryOrigin === origin)
      : undefined;
  }

  private getExternalNavigationPolicyLabel(policy: ExternalNavigationAppOpenPolicy): string {
    return this.capabilityCatalog.getExternalNavigationPolicyLabel(policy);
  }

  private findCapabilityState(siteControls: SiteControlsState, id: string): SiteControlCapabilityState | undefined {
    return siteControls.capabilities.find((item: SiteControlCapabilityState) => item.id === id);
  }

  private resolveExternalNavigationPolicy(
    state: SiteControlCapabilityState | undefined
  ): ExternalNavigationAppOpenPolicy {
    if (state?.rule === 'allow' || state?.rule === 'block' || state?.rule === 'ask') {
      return state.rule;
    }
    return 'ask';
  }

  private matchesQuery(row: SiteCustomizationListRowState, query: string): boolean {
    const normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.length === 0) {
      return true;
    }
    const haystack = `${row.title} ${row.value} ${row.helperText}`.toLowerCase();
    return haystack.indexOf(normalizedQuery) >= 0;
  }

  private extractHostKey(value: string): string {
    const normalized = this.normalizeOriginKey(value);
    const schemeMatch = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/?#]+)/.exec(normalized);
    if (schemeMatch !== null) {
      return this.normalizeHostKey(schemeMatch[1]);
    }
    return this.normalizeHostKey(normalized);
  }

  private normalizeHostKey(value: string): string {
    return value.trim().toLowerCase()
      .replace(/^https?:\/\//, '')
      .split('/')[0]
      .split(':')[0]
      .replace(/^\.+|\.+$/g, '');
  }

  private normalizeOriginKey(value: string): string {
    return this.siteIdentityService.resolveSiteSettingTarget(value)?.canonicalOrigin ?? value.trim().toLowerCase();
  }

  private resolveTarget(value: string): SiteSettingTarget | undefined {
    return this.siteIdentityService.resolveSiteSettingTarget(value);
  }

  private exactAggregateKey(origin: string): string {
    return `origin:${this.normalizeOriginKey(origin)}`;
  }

  private getOrCreateAggregate(
    map: Map<string, SiteCustomizationAggregate>,
    origin: string,
    host: string
  ): SiteCustomizationAggregate {
    const key = this.exactAggregateKey(origin);
    const existing = map.get(key);
    if (existing !== undefined) {
      return existing;
    }
    const aggregate: SiteCustomizationAggregate = {
      host: host,
      origin: this.normalizeOriginKey(origin),
      permissionSettings: [],
      updatedAt: 0
    };
    map.set(key, aggregate);
    return aggregate;
  }

  private resolveSavedIdentitySummary(entry: SavedSiteSettingEntry): string {
    const identityId = entry.overrides.userAgentIdentityId ?? '';
    const identity = this.userAgentService.getIdentityCatalog(this.userAgentSettingsRepository.getSettings())
      .find((item: BrowserUserAgentIdentity) => item.id === identityId);
    return identity?.title ?? '不可用的网页标识';
  }

  private resolveJavaScriptPolicy(entry: SavedSiteSettingEntry | undefined): SiteJavaScriptPolicy {
    if (entry?.overrides.javaScriptEnabled === true) {
      return 'allow';
    }
    if (entry?.overrides.javaScriptEnabled === false) {
      return 'block';
    }
    return 'default';
  }

  private async resetSiteJavaScript(
    host: string,
    origin: string,
    profileId: BrowserProfileId
  ): Promise<void> {
    const target = this.resolveTarget(origin.length > 0 ? origin : host);
    if (target === undefined) {
      return;
    }
    const current = this.savedSiteSettingRepository.findEntry(target, profileId);
    if (current === undefined || typeof current.overrides.javaScriptEnabled !== 'boolean') {
      return;
    }
    const nextOverrides = this.copyOverrides(current.overrides);
    nextOverrides.javaScriptEnabled = undefined;
    await this.savedSiteSettingRepository.commit(target, profileId, nextOverrides, current.revision);
  }

  private copyOverrides(overrides: SavedSiteSettingOverrides): SavedSiteSettingOverrides {
    return {
      userAgentIdentityId: overrides.userAgentIdentityId,
      javaScriptEnabled: overrides.javaScriptEnabled,
      clearOnClose: overrides.clearOnClose,
      preserveCookiesOnClose: overrides.preserveCookiesOnClose,
      externalNavigationPolicy: overrides.externalNavigationPolicy,
      camera: overrides.camera,
      microphone: overrides.microphone,
      location: overrides.location,
      sensor: overrides.sensor,
      clipboard: overrides.clipboard
    };
  }
}

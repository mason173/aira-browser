import {
  BrowserDataBoundaryInput,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  SitePermissionDefaultSettings,
  SitePermissionKind,
  SitePermissionRule,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { SiteDataControlService } from '../../services/web/SiteDataControlService';
import { SiteCapabilityCatalogService } from '../../services/web/SiteCapabilityCatalogService';
import {
  BrowserHttpsFirstNavigationService,
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import { sharedBrowserSslDecisionCacheRuntime } from '../../services/web/BrowserSslDecisionCacheRuntime';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  SiteControlsCoordinator,
  SiteControlsDefaultCapabilityState,
  SiteControlsOverviewState
} from '../sitecontrols/SiteControlsCoordinator';

export interface SettingsSitePermissionsBoundary {
  profileId?: BrowserProfileId | string;
  privacyMode?: BrowserSessionPrivacyMode | string;
  dataScope?: BrowserDataScope | string;
}

export interface SettingsSitePermissionsState {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  savedOriginCount: number;
  allowRuleCount: number;
  blockRuleCount: number;
  askRuleCount: number;
  defaults: SitePermissionDefaultSettings;
  defaultCapabilities: SiteControlsDefaultCapabilityState[];
  canClearPermissions: boolean;
  summaryLine: string;
}

export interface SettingsSitePermissionsResetResult {
  hasError: boolean;
  message: string;
}

export interface SettingsSitePermissionsResetState {
  title: string;
  message: string;
  confirmLabel: string;
  canResetPermissions: boolean;
}

export interface SettingsSitePermissionDefaultOption {
  value: SitePermissionRule;
  label: string;
  helperText: string;
}

export interface SettingsSitePermissionDefaultPageState {
  kind: SitePermissionKind;
  title: string;
  selectedRule: SitePermissionRule;
  options: SettingsSitePermissionDefaultOption[];
}

export class SettingsSitePermissionsCoordinator {
  private preferencesRepository: PreferencesRepository;
  private siteDataControlService: SiteDataControlService;
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  private siteControlsCoordinator: SiteControlsCoordinator;
  private sitePolicyService?: SitePolicyService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private httpsFirstNavigationService: BrowserHttpsFirstNavigationService;

  constructor(
    preferencesRepository: PreferencesRepository,
    sitePolicyService?: SitePolicyService,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService(),
    httpsFirstNavigationService: BrowserHttpsFirstNavigationService = sharedBrowserHttpsFirstNavigationService
  ) {
    this.preferencesRepository = preferencesRepository;
    this.siteDataControlService = new SiteDataControlService(preferencesRepository);
    this.siteControlsCoordinator = new SiteControlsCoordinator(preferencesRepository);
    this.sitePolicyService = sitePolicyService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.httpsFirstNavigationService = httpsFirstNavigationService;
  }

  buildState(boundary: SettingsSitePermissionsBoundary = {}): SettingsSitePermissionsState {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    const profileId = normalizeBrowserProfileId(boundary.profileId ?? DEFAULT_BROWSER_PROFILE_ID);
    if (dataScope === 'session_ephemeral') {
      const sessionSnapshot = this.sitePolicyService?.buildSessionSitePermissionSnapshot(profileId);
      const sessionOverview = this.siteControlsCoordinator.buildSessionOverview(
        profileId,
        sessionSnapshot?.originCount ?? 0,
        sessionSnapshot?.totalRuleCount ?? 0,
        sessionSnapshot?.allowRuleCount ?? 0,
        sessionSnapshot?.blockRuleCount ?? 0
      );
      const summary = this.siteDataControlService.buildPermissionSummaryForBoundary(
        profileId,
        privacyMode,
        dataScope,
        [],
        sessionSnapshot?.totalRuleCount ?? 0
      );
      return {
        profileId: profileId,
        privacyMode: privacyMode,
        dataScope: dataScope,
        savedOriginCount: sessionSnapshot?.originCount ?? 0,
        allowRuleCount: sessionSnapshot?.allowRuleCount ?? 0,
        blockRuleCount: sessionSnapshot?.blockRuleCount ?? 0,
        askRuleCount: 0,
        defaults: sessionOverview.defaults,
        defaultCapabilities: sessionOverview.defaultCapabilities,
        canClearPermissions: sessionOverview.canClearPermissions,
        summaryLine: sessionOverview.summaryLine.length > 0 ? sessionOverview.summaryLine : summary.summaryLine
      };
    }

    const overview: SiteControlsOverviewState = this.siteControlsCoordinator.buildOverview(profileId);
    const summary = this.siteDataControlService.buildPermissionSummaryForBoundary(
      profileId,
      privacyMode,
      dataScope,
      this.preferencesRepository.listSitePermissionSettings(profileId),
      0
    );
    return {
      profileId: profileId,
      privacyMode: privacyMode,
      dataScope: dataScope,
      savedOriginCount: overview.savedOriginCount,
      allowRuleCount: overview.allowRuleCount,
      blockRuleCount: overview.blockRuleCount,
      askRuleCount: overview.askRuleCount,
      defaults: overview.defaults,
      defaultCapabilities: overview.defaultCapabilities,
      canClearPermissions: overview.canClearPermissions,
      summaryLine: overview.summaryLine.length > 0 ? overview.summaryLine : summary.summaryLine
    };
  }

  buildDefaultPageState(kind: SitePermissionKind): SettingsSitePermissionDefaultPageState {
    const defaults = this.preferencesRepository.getPreferences().sitePermissionDefaults;
    return {
      kind: kind,
      title: this.getDefaultPageTitle(kind),
      selectedRule: this.getDefaultRule(defaults, kind),
      options: this.capabilityCatalog.buildDefaultPermissionOptions()
    };
  }

  async updateDefaultRule(
    kind: SitePermissionKind,
    rule: SitePermissionRule,
    boundary: SettingsSitePermissionsBoundary
  ): Promise<SitePermissionDefaultSettings> {
    if (!this.canWriteDevicePreference(boundary)) {
      throw new Error('Site permission default write privacy effect was not allowed.');
    }
    const currentDefaults = this.preferencesRepository.getPreferences().sitePermissionDefaults;
    const nextDefaults: SitePermissionDefaultSettings = {
      camera: kind === 'camera' ? rule : currentDefaults.camera,
      microphone: kind === 'microphone' ? rule : currentDefaults.microphone,
      location: kind === 'location' ? rule : currentDefaults.location,
      sensor: kind === 'sensor' ? rule : currentDefaults.sensor,
      clipboard: kind === 'clipboard' ? rule : currentDefaults.clipboard
    };
    const preferences = await this.preferencesRepository.updateSitePermissionDefaultSettings(nextDefaults);
    return preferences.sitePermissionDefaults;
  }

  async resetAll(boundary: SettingsSitePermissionsBoundary): Promise<SettingsSitePermissionsResetResult> {
    const state = this.buildState(boundary);
    if (state.dataScope === 'session_ephemeral') {
      try {
        const cleanupResult = this.sitePolicyService?.clearSessionSitePermissionSettings(state.profileId);
        await this.httpsFirstNavigationService.clearSiteDecisions({
          profileId: state.profileId,
          privacyMode: state.privacyMode,
          dataScope: state.dataScope
        });
        sharedBrowserSslDecisionCacheRuntime.requestClear();
        if (cleanupResult !== undefined) {
          return {
            hasError: false,
            message: cleanupResult.removed > 0
              ? `已清除 ${cleanupResult.removed} 条本次私密会话权限。`
              : '当前没有需要清除的私密会话权限'
          };
        }
        return {
          hasError: false,
          message: '私密会话权限会在关闭所有私密标签页后清除'
        };
      } catch (_error) {
        return {
          hasError: true,
          message: '站点权限重置失败'
        };
      }
    }
    try {
      await this.preferencesRepository.clearAllSitePermissionSettings(state.profileId);
      this.sitePolicyService?.clearPermissionSessionGrants({
        profileId: state.profileId,
        dataScope: state.dataScope
      });
      this.sitePolicyService?.clearArkWebGeolocationPermissions(false);
      await this.httpsFirstNavigationService.clearSiteDecisions({
        profileId: state.profileId,
        privacyMode: state.privacyMode,
        dataScope: state.dataScope
      });
      sharedBrowserSslDecisionCacheRuntime.requestClear();
      return {
        hasError: false,
        message: '站点权限已重置'
      };
    } catch (_error) {
      return {
        hasError: true,
        message: '站点权限重置失败'
      };
    }
  }

  buildResetState(boundary: SettingsSitePermissionsBoundary = {}): SettingsSitePermissionsResetState {
    const state = this.buildState(boundary);
    if (state.dataScope === 'session_ephemeral') {
      return {
        title: '私密会话权限',
        message: state.canClearPermissions
          ? '清除本次临时站点权限'
          : '私密权限关闭后自动清除',
        confirmLabel: state.canClearPermissions ? '清除' : '知道了',
        canResetPermissions: state.canClearPermissions
      };
    }
    return {
      title: '重置站点权限',
      message: '清除已保存的站点权限',
      confirmLabel: '重置',
      canResetPermissions: state.canClearPermissions
    };
  }

  private getDefaultPageTitle(kind: SitePermissionKind): string {
    return this.capabilityCatalog.getPermissionTitle(kind);
  }

  private getDefaultRule(defaults: SitePermissionDefaultSettings, kind: SitePermissionKind): SitePermissionRule {
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

  private canWriteDevicePreference(boundary: SettingsSitePermissionsBoundary): boolean {
    const boundaryInput: BrowserDataBoundaryInput = {
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope
    };
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }
}

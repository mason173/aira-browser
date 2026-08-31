import {
  BrowserCustomUserAgentRecord,
  BrowserProfileId,
  BrowserUserAgentMode,
  BrowserUserAgentPresetId,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import { SiteSettingTarget } from '../../common/models/SiteSettingModels';
import { SiteIdentityService } from './SiteIdentityService';

export interface BrowserUserAgentPreset {
  id: BrowserUserAgentPresetId;
  title: string;
  subtitle: string;
  mode: BrowserUserAgentMode;
  userAgent: string;
}

export interface BrowserUserAgentRiskNotice {
  title: string;
  message: string;
  confirmText: string;
  cancelText: string;
}

export interface BrowserCustomUserAgentDraft {
  name: string;
  userAgent: string;
}

export interface BrowserUserAgentResolutionInput {
  settings: BrowserUserAgentSettings;
  systemDefaultUserAgent: string;
  applicationFamily?: BrowserUserAgentApplicationFamily;
  pageUrl?: string;
  mandatoryCompatibility?: BrowserUserAgentMandatoryCompatibility;
  siteSettingTarget?: SiteSettingTarget;
  siteOverrides?: BrowserUserAgentSiteOverride[];
  temporaryIdentityId?: string;
  profileId?: BrowserProfileId;
}

export interface BrowserUserAgentSiteOverride {
  profileId: BrowserProfileId;
  target: SiteSettingTarget;
  identityId: string;
  updatedAt: number;
}

export interface BrowserUserAgentMandatoryCompatibility {
  host: string;
  ruleId: string;
  identityId: string;
  reason: string;
  userAgent: string;
  mode: BrowserUserAgentMode;
}

export interface BrowserUserAgentIdentity {
  id: string;
  title: string;
  subtitle: string;
  mode: BrowserUserAgentMode;
  userAgent: string;
  source: 'global' | 'preset' | 'custom' | 'arkweb_original';
}

export type BrowserUserAgentResolutionSource =
  'mandatory_compatibility' |
  'site_setting' |
  'custom' | 'preset' | 'app_default' | 'system_default';

export type BrowserDesktopSiteMode = 'default' | 'mobile' | 'desktop';
export type BrowserUserAgentApplicationFamily = 'mobile' | 'tablet' | 'desktop';

export type BrowserUserAgentStringMode = 'system_untouched' | 'known_preset' | 'custom';
export type BrowserUserAgentClientHintsMode = 'system' | 'known_metadata' | 'low_entropy_only';
export type BrowserUserAgentScopeCapability = 'application' | 'host' | 'runtime';

export interface BrowserUserAgentClientHintsMetadata {
  brand: string;
  majorVersion: string;
  fullVersion: string;
  platform: string;
  platformVersion: string;
  mobile: boolean;
  architecture: string;
  bitness: string;
  model: string;
  wow64: boolean;
}

export interface BrowserUserAgentProfile {
  identityId: string;
  uaStringMode: BrowserUserAgentStringMode;
  uaString: string;
  clientHintsMode: BrowserUserAgentClientHintsMode;
  metadata?: BrowserUserAgentClientHintsMetadata;
  presentationMode: 'mobile' | 'desktop-request';
  scopeCapability: BrowserUserAgentScopeCapability;
  compatibilityNotice: string;
}

export interface BrowserUserAgentResolution {
  userAgent: string;
  mode: BrowserUserAgentMode;
  source: BrowserUserAgentResolutionSource;
  reason: string;
  matchedHost: string;
  identityId?: string;
  targetOrigin?: string;
  profile: BrowserUserAgentProfile;
}

export const FOLLOW_GLOBAL_BROWSER_IDENTITY_ID: string = 'follow_global';
export const AIRA_DEFAULT_BROWSER_IDENTITY_ID: string = 'aira_default';
export const AIRA_DESKTOP_DEFAULT_BROWSER_IDENTITY_ID: string = 'aira_default_desktop';

export const SYSTEM_DEFAULT_USER_AGENT_PRESET_ID: BrowserUserAgentPresetId = 'system_default';
export const DESKTOP_CHROME_USER_AGENT_PRESET_ID: BrowserUserAgentPresetId = 'desktop_chrome_windows';
export const ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID: BrowserUserAgentPresetId = 'arkweb_original';
export const AIRA_COMPAT_MOBILE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 12; SGT-AL10 Build/HUAWEISGT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.130 Mobile HuaweiBrowser/6.1.1.303';
export const HUAWEI_BROWSER_USER_AGENT: string =
  'Mozilla/5.0 (Phone; OpenHarmony 6.0; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.130 Mobile HuaweiBrowser/6.1.1.303';
export const CHROME_ANDROID_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36';
export const AIRA_COMPAT_DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

export const BROWSER_USER_AGENT_RISK_NOTICE: BrowserUserAgentRiskNotice = {
  title: '网页标识兼容性提醒',
  message: '切换为桌面端、自定义或伪装其它浏览器的 UA，可能让 Cloudflare、Turnstile 等验证认为浏览器环境不一致，导致验证码循环或验证失败。遇到登录、支付或验证异常时，请先改回 Aira 默认；如果仍异常，再选择 ArkWeb 原始标识重试。',
  confirmText: '继续使用',
  cancelText: '取消'
};

export const DEFAULT_BROWSER_USER_AGENT_SETTINGS: BrowserUserAgentSettings = {
  defaultMode: 'mobile',
  selectedPresetId: SYSTEM_DEFAULT_USER_AGENT_PRESET_ID,
  customUserAgent: '',
  selectedCustomUserAgentId: '',
  customUserAgents: [],
  updatedAt: 0
};

const MAX_CUSTOM_USER_AGENT_RECORDS: number = 24;

export const BROWSER_USER_AGENT_PRESETS: BrowserUserAgentPreset[] = [
  {
    id: SYSTEM_DEFAULT_USER_AGENT_PRESET_ID,
    title: 'Aira默认',
    subtitle: '使用 ArkWeb 系统网页标识，可按站点选择兼容标识',
    mode: 'mobile',
    userAgent: AIRA_COMPAT_MOBILE_USER_AGENT
  },
  {
    id: ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID,
    title: 'ArkWeb 原始标识',
    subtitle: '直接使用系统网页标识，用于网页登录验证或问题排查',
    mode: 'mobile',
    userAgent: ''
  },
  {
    id: 'mobile_huawei_browser',
    title: '华为浏览器',
    subtitle: '使用 OpenHarmony/HuaweiBrowser 原始兼容标识',
    mode: 'mobile',
    userAgent: HUAWEI_BROWSER_USER_AGENT
  },
  {
    id: 'mobile_chrome_android',
    title: 'Chrome Android',
    subtitle: '常见 Android 手机上的 Chrome 标识',
    mode: 'mobile',
    userAgent: CHROME_ANDROID_USER_AGENT
  },
  {
    id: 'mobile_safari_iphone',
    title: 'Safari iPhone',
    subtitle: '常见 iPhone Safari 标识',
    mode: 'mobile',
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1'
  },
  {
    id: DESKTOP_CHROME_USER_AGENT_PRESET_ID,
    title: 'Chrome Windows',
    subtitle: '适合请求桌面版网页',
    mode: 'desktop',
    userAgent: AIRA_COMPAT_DESKTOP_USER_AGENT
  },
  {
    id: 'desktop_edge_windows',
    title: 'Microsoft Edge Windows',
    subtitle: '桌面 Edge 兼容标识',
    mode: 'desktop',
    userAgent: `${AIRA_COMPAT_DESKTOP_USER_AGENT} Edg/140.0.0.0`
  },
  {
    id: 'desktop_safari_mac',
    title: 'Safari macOS',
    subtitle: '桌面 Safari 兼容标识',
    mode: 'desktop',
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15'
  },
  {
    id: 'desktop_firefox_windows',
    title: 'Firefox Windows',
    subtitle: '桌面 Firefox 兼容标识',
    mode: 'desktop',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:139.0) Gecko/20100101 Firefox/139.0'
  }
];

export class BrowserUserAgentService {
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();

  normalizeSettings(settings: BrowserUserAgentSettings | undefined): BrowserUserAgentSettings {
    const selectedPresetId = this.normalizePresetId(settings?.selectedPresetId ?? '');
    const preset = this.findPreset(selectedPresetId);
    const defaultMode = this.normalizeMode(settings?.defaultMode ?? preset.mode);
    const customUserAgents = this.normalizeCustomUserAgentRecords(settings?.customUserAgents ?? []);
    const legacyCustomUserAgent = this.normalizeCustomUserAgent(settings?.customUserAgent ?? '');
    const selectedCustomUserAgentId = this.normalizeSelectedCustomUserAgentId(
      settings?.selectedCustomUserAgentId ?? '',
      customUserAgents
    );
    const selectedCustomUserAgent = this.findCustomUserAgent(customUserAgents, selectedCustomUserAgentId);
    const customUserAgent = selectedCustomUserAgent?.userAgent ?? legacyCustomUserAgent;
    return {
      defaultMode: defaultMode,
      selectedPresetId: selectedPresetId,
      customUserAgent: customUserAgent,
      selectedCustomUserAgentId: selectedCustomUserAgentId,
      customUserAgents: customUserAgents,
      updatedAt: Number(settings?.updatedAt) > 0 ? Number(settings?.updatedAt) : 0
    };
  }

  getPresets(): BrowserUserAgentPreset[] {
    return BROWSER_USER_AGENT_PRESETS.map((preset: BrowserUserAgentPreset) => {
      const nextPreset: BrowserUserAgentPreset = {
        id: preset.id,
        title: preset.title,
        subtitle: preset.subtitle,
        mode: preset.mode,
        userAgent: preset.userAgent
      };
      return nextPreset;
    });
  }

  getIdentityCatalog(settings: BrowserUserAgentSettings): BrowserUserAgentIdentity[] {
    const normalized = this.normalizeSettings(settings);
    const identities: BrowserUserAgentIdentity[] = [{
      id: FOLLOW_GLOBAL_BROWSER_IDENTITY_ID,
      title: '跟随全局',
      subtitle: '使用全局网页标识设置',
      mode: normalized.defaultMode,
      userAgent: '',
      source: 'global'
    }];
    this.getPresets().forEach((preset: BrowserUserAgentPreset) => {
      identities.push({
        id: preset.id === SYSTEM_DEFAULT_USER_AGENT_PRESET_ID ? AIRA_DEFAULT_BROWSER_IDENTITY_ID : preset.id,
        title: preset.title,
        subtitle: preset.subtitle,
        mode: preset.mode,
        userAgent: preset.userAgent,
        source: preset.id === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID ? 'arkweb_original' : 'preset'
      });
    });
    normalized.customUserAgents.forEach((record: BrowserCustomUserAgentRecord) => {
      identities.push({
        id: record.id,
        title: record.name,
        subtitle: '自定义网页标识',
        mode: 'custom',
        userAgent: record.userAgent,
        source: 'custom'
      });
    });
    return identities;
  }

  resolveSiteSettingTarget(value: string): SiteSettingTarget | undefined {
    return this.siteIdentityService.resolveSiteSettingTarget(value);
  }

  findPreset(id: BrowserUserAgentPresetId): BrowserUserAgentPreset {
    return BROWSER_USER_AGENT_PRESETS.find((preset: BrowserUserAgentPreset) => preset.id === id) ??
      BROWSER_USER_AGENT_PRESETS[0];
  }

  buildPresetSettings(
    presetId: BrowserUserAgentPresetId,
    currentSettings?: BrowserUserAgentSettings
  ): BrowserUserAgentSettings {
    const preset = this.findPreset(this.normalizePresetId(presetId));
    const normalizedCurrent = this.normalizeSettings(currentSettings);
    return {
      defaultMode: preset.mode,
      selectedPresetId: preset.id,
      customUserAgent: normalizedCurrent.customUserAgent,
      selectedCustomUserAgentId: normalizedCurrent.selectedCustomUserAgentId,
      customUserAgents: normalizedCurrent.customUserAgents,
      updatedAt: Date.now()
    };
  }

  buildCustomSettings(
    userAgent: string,
    currentSettings?: BrowserUserAgentSettings,
    customUserAgentId?: string
  ): BrowserUserAgentSettings {
    const normalizedCurrent = this.normalizeSettings(currentSettings);
    const normalizedId = this.normalizeSelectedCustomUserAgentId(customUserAgentId ?? '', normalizedCurrent.customUserAgents);
    const selectedRecord = this.findCustomUserAgent(normalizedCurrent.customUserAgents, normalizedId);
    const normalizedUserAgent = this.normalizeCustomUserAgent(userAgent);
    return {
      defaultMode: 'custom',
      selectedPresetId: 'custom',
      customUserAgent: selectedRecord?.userAgent ?? normalizedUserAgent,
      selectedCustomUserAgentId: selectedRecord?.id ?? normalizedId,
      customUserAgents: normalizedCurrent.customUserAgents,
      updatedAt: Date.now()
    };
  }

  buildCustomUserAgentRecord(
    draft: BrowserCustomUserAgentDraft,
    existingRecord?: BrowserCustomUserAgentRecord
  ): BrowserCustomUserAgentRecord | undefined {
    const userAgent = this.normalizeCustomUserAgent(draft.userAgent);
    if (userAgent.length <= 0) {
      return undefined;
    }
    const now = Date.now();
    const name = this.normalizeCustomUserAgentName(draft.name, userAgent);
    return {
      id: existingRecord?.id ?? this.buildCustomUserAgentId(now, name, userAgent),
      name: name,
      userAgent: userAgent,
      createdAt: Number(existingRecord?.createdAt) > 0 ? Number(existingRecord?.createdAt) : now,
      updatedAt: now
    };
  }

  buildSettingsForCustomRecord(
    record: BrowserCustomUserAgentRecord,
    currentSettings?: BrowserUserAgentSettings
  ): BrowserUserAgentSettings {
    const normalizedCurrent = this.normalizeSettings(currentSettings);
    return {
      defaultMode: 'custom',
      selectedPresetId: 'custom',
      customUserAgent: record.userAgent,
      selectedCustomUserAgentId: record.id,
      customUserAgents: this.normalizeCustomUserAgentRecords(
        normalizedCurrent.customUserAgents
          .filter((item: BrowserCustomUserAgentRecord) => item.id !== record.id)
          .concat([record])
      ),
      updatedAt: Date.now()
    };
  }

  shouldWarnForSettings(settings: BrowserUserAgentSettings): boolean {
    const normalized = this.normalizeSettings(settings);
    if (normalized.defaultMode === 'custom' || normalized.defaultMode === 'desktop') {
      return true;
    }
    return normalized.selectedPresetId !== SYSTEM_DEFAULT_USER_AGENT_PRESET_ID;
  }

  shouldWarnForModeSwitch(targetMode: BrowserUserAgentMode): boolean {
    return this.normalizeMode(targetMode) === 'desktop';
  }

  getRiskNotice(): BrowserUserAgentRiskNotice {
    return {
      title: BROWSER_USER_AGENT_RISK_NOTICE.title,
      message: BROWSER_USER_AGENT_RISK_NOTICE.message,
      confirmText: BROWSER_USER_AGENT_RISK_NOTICE.confirmText,
      cancelText: BROWSER_USER_AGENT_RISK_NOTICE.cancelText
    };
  }

  resolveEffectiveUserAgent(
    settings: BrowserUserAgentSettings,
    systemDefaultUserAgent: string
  ): string {
    const resolution = this.resolveUserAgent({
      settings: settings,
      systemDefaultUserAgent: systemDefaultUserAgent
    });
    if (resolution.source === 'system_default') {
      return this.resolveApplicationDefaultUserAgent(settings, systemDefaultUserAgent);
    }
    return resolution.userAgent;
  }

  resolveApplicationDefaultUserAgent(
    _settings: BrowserUserAgentSettings,
    _systemDefaultUserAgent: string,
    applicationFamily: BrowserUserAgentApplicationFamily = 'mobile'
  ): string {
    if (applicationFamily !== 'mobile') {
      return AIRA_COMPAT_DESKTOP_USER_AGENT;
    }
    return AIRA_COMPAT_MOBILE_USER_AGENT;
  }

  resolveApplicationFamilyForDevice(detectedFormFactor: string): BrowserUserAgentApplicationFamily {
    const normalizedFormFactor = detectedFormFactor.trim().toLowerCase();
    if (normalizedFormFactor === 'tablet') {
      return 'tablet';
    }
    if (normalizedFormFactor === 'two_in_one' || normalizedFormFactor === '2in1' ||
      normalizedFormFactor === 'two-in-one' || normalizedFormFactor === 'pc' ||
      normalizedFormFactor === 'desktop') {
      return 'desktop';
    }
    return 'mobile';
  }

  resolveApplicationFamilyForShell(shellFamily: string): BrowserUserAgentApplicationFamily {
    return shellFamily.trim().toLowerCase() === 'large_screen' ? 'desktop' : 'mobile';
  }

  /**
   * Managed Host rules deliberately expose only two runtime shapes.  The
   * regular identity catalog remains user-facing and can contain many
   * concrete presets, so callers use this helper to translate an identity
   * reference into the opaque cloud profile shape without exposing that
   * mapping in presentation or persistence.
   */
  resolvePresentationModeForIdentity(
    identityId: string,
    settings: BrowserUserAgentSettings,
    applicationFamily: BrowserUserAgentApplicationFamily
  ): BrowserDesktopSiteMode {
    const normalizedIdentityId = identityId.trim();
    if (normalizedIdentityId.length <= 0 || normalizedIdentityId === FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      return 'default';
    }
    if (normalizedIdentityId === AIRA_DEFAULT_BROWSER_IDENTITY_ID ||
      normalizedIdentityId === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID) {
      // These references are used by the current-tab/site website-version
      // controls as their explicit mobile shape. The browser-wide Follow
      // Global/default path is handled separately by
      // resolvePresentationModeForSettings(), where the physical family is
      // still the fallback.
      return 'mobile';
    }
    const identity = this.getIdentityCatalog(settings)
      .find((candidate: BrowserUserAgentIdentity): boolean => candidate.id === normalizedIdentityId);
    if (identity === undefined) {
      return 'default';
    }
    if (identity.mode === 'desktop') {
      return 'desktop';
    }
    if (identity.mode === 'mobile') {
      return 'mobile';
    }
    return this.resolveCustomPresentationMode(identity.userAgent, applicationFamily);
  }

  resolvePresentationModeForSettings(
    settings: BrowserUserAgentSettings,
    applicationFamily: BrowserUserAgentApplicationFamily
  ): BrowserDesktopSiteMode {
    const normalized = this.normalizeSettings(settings);
    if (normalized.defaultMode === 'desktop') {
      return 'desktop';
    }
    if (normalized.defaultMode === 'custom') {
      const selected = this.findCustomUserAgent(
        normalized.customUserAgents,
        normalized.selectedCustomUserAgentId
      );
      return this.resolveCustomPresentationMode(selected?.userAgent ?? normalized.customUserAgent, applicationFamily);
    }
    if (normalized.selectedPresetId === SYSTEM_DEFAULT_USER_AGENT_PRESET_ID) {
      return applicationFamily === 'mobile' ? 'mobile' : 'desktop';
    }
    return this.resolvePresentationModeForIdentity(
      normalized.selectedPresetId,
      normalized,
      applicationFamily
    );
  }

  resolveUserAgent(input: BrowserUserAgentResolutionInput): BrowserUserAgentResolution {
    const settings = this.normalizeSettings(input.settings);
    const pageUrl = input.pageUrl ?? '';
    const applicationFamily = this.normalizeApplicationFamily(input.applicationFamily);
    const mode = this.normalizeMode(settings.defaultMode);

    const mandatoryCompatibility = input.mandatoryCompatibility;
    if (mandatoryCompatibility !== undefined &&
      this.hostMatches(
        this.extractHost(pageUrl),
        mandatoryCompatibility.host,
        false
      )) {
      return this.buildResolution(
        mandatoryCompatibility.userAgent,
        mandatoryCompatibility.mode,
        'mandatory_compatibility',
        mandatoryCompatibility.reason,
        mandatoryCompatibility.host,
        mandatoryCompatibility.identityId
      );
    }

    const temporaryIdentityId = input.temporaryIdentityId?.trim() ?? '';
    const hasTemporaryIdentity = temporaryIdentityId.length > 0;
    if (hasTemporaryIdentity && temporaryIdentityId !== FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      const temporary = this.resolveIdentity(
        temporaryIdentityId,
        settings,
        input.systemDefaultUserAgent,
        applicationFamily
      );
      if (temporary !== undefined) {
        return this.buildResolution(
          temporary.userAgent,
          temporary.mode,
          temporary.source === 'arkweb_original' ? 'system_default' : 'preset',
          'The current tab temporarily selected a browsing identity.',
          this.extractHost(pageUrl),
          temporary.id,
          input.siteSettingTarget?.canonicalOrigin
        );
      }
    }

    const siteOverride = hasTemporaryIdentity
      ? undefined
      : this.findSiteOverride(
        pageUrl,
        input.siteSettingTarget,
        input.siteOverrides ?? [],
        input.profileId
      );
    if (siteOverride !== undefined && siteOverride.identityId !== FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      const siteIdentity = this.resolveIdentity(
        siteOverride.identityId,
        settings,
        input.systemDefaultUserAgent,
        applicationFamily
      );
      if (siteIdentity !== undefined) {
        return this.buildResolution(
          siteIdentity.userAgent,
          siteIdentity.mode,
          siteIdentity.source === 'arkweb_original' ? 'system_default' : 'site_setting',
          'The exact Origin selected a site browsing identity.',
          this.extractHost(siteOverride.target.canonicalOrigin),
          siteIdentity.id,
          siteOverride.target.canonicalOrigin
        );
      }
    }

    if (mode === 'custom') {
      const selectedCustomUserAgent = this.findCustomUserAgent(
        settings.customUserAgents,
        settings.selectedCustomUserAgentId
      );
      const customUserAgent = this.normalizeCustomUserAgent(selectedCustomUserAgent?.userAgent ?? settings.customUserAgent);
      return this.buildResolution(
        customUserAgent.length > 0 ? customUserAgent : this.resolvePresetUserAgent(settings, input.systemDefaultUserAgent),
        'custom',
        customUserAgent.length > 0 ? 'custom' : 'preset',
        customUserAgent.length > 0 ? 'User selected a custom UA.' : 'Custom UA is empty; using selected preset.',
        '',
        customUserAgent.length > 0 ? settings.selectedCustomUserAgentId : settings.selectedPresetId
      );
    }
    if (mode === 'desktop') {
      return this.buildResolution(
        this.findPreset(DESKTOP_CHROME_USER_AGENT_PRESET_ID).userAgent,
        'desktop',
        'preset',
        'User requested desktop pages.',
        '',
        DESKTOP_CHROME_USER_AGENT_PRESET_ID
      );
    }
    if (settings.selectedPresetId !== SYSTEM_DEFAULT_USER_AGENT_PRESET_ID &&
      this.findPreset(settings.selectedPresetId).mode === 'mobile') {
      return this.buildResolution(
        this.resolvePresetUserAgent(settings, input.systemDefaultUserAgent),
        'mobile',
        settings.selectedPresetId === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID ? 'system_default' : 'preset',
        settings.selectedPresetId === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID
          ? 'User selected ArkWeb original UA.'
          : 'User selected a mobile UA preset.',
        '',
        settings.selectedPresetId
      );
    }
    if (applicationFamily !== 'mobile') {
      return this.buildResolution(
        AIRA_COMPAT_DESKTOP_USER_AGENT,
        'desktop',
        'app_default',
        this.resolveApplicationDefaultReason(applicationFamily),
        '',
        AIRA_DESKTOP_DEFAULT_BROWSER_IDENTITY_ID
      );
    }
    return this.buildResolution(
      AIRA_COMPAT_MOBILE_USER_AGENT,
      'mobile',
      'app_default',
      this.resolveApplicationDefaultReason(applicationFamily),
      '',
      AIRA_DEFAULT_BROWSER_IDENTITY_ID
    );
  }

  resolveMenuTitle(mode: BrowserUserAgentMode): string {
    return this.normalizeMode(mode) === 'desktop' ? '请求移动端网页' : '请求桌面版网页';
  }

  resolveSettingsSummary(settings: BrowserUserAgentSettings): string {
    const normalized = this.normalizeSettings(settings);
    if (normalized.defaultMode === 'custom') {
      const selectedCustomUserAgent = this.findCustomUserAgent(
        normalized.customUserAgents,
        normalized.selectedCustomUserAgentId
      );
      if (selectedCustomUserAgent !== undefined) {
        return selectedCustomUserAgent.name;
      }
      return normalized.customUserAgent.length > 0 ? '自定义 UA' : '自定义 UA 未填写';
    }
    return this.findPreset(normalized.selectedPresetId).title;
  }

  extractOrigin(url: string): string {
    return this.siteIdentityService.resolveSiteSettingTarget(url)?.canonicalOrigin ?? '';
  }

  private resolvePresetUserAgent(settings: BrowserUserAgentSettings, systemDefaultUserAgent: string): string {
    const preset = this.findPreset(settings.selectedPresetId);
    if (preset.userAgent.length > 0) {
      return preset.userAgent;
    }
    return systemDefaultUserAgent.trim();
  }

  private normalizeMode(mode: BrowserUserAgentMode | string): BrowserUserAgentMode {
    if (mode === 'desktop' || mode === 'custom') {
      return mode;
    }
    return 'mobile';
  }

  private normalizeApplicationFamily(
    applicationFamily: BrowserUserAgentApplicationFamily | undefined
  ): BrowserUserAgentApplicationFamily {
    if (applicationFamily === 'tablet' || applicationFamily === 'desktop') {
      return applicationFamily;
    }
    return 'mobile';
  }

  private resolveApplicationDefaultReason(applicationFamily: BrowserUserAgentApplicationFamily): string {
    if (applicationFamily === 'tablet') {
      return 'Aira defaults a physical tablet to its desktop compatibility identity.';
    }
    if (applicationFamily === 'desktop') {
      return 'Aira defaults a physical desktop device to its desktop compatibility identity.';
    }
    return 'Aira defaults a physical phone to its Android-compatible mobile identity.';
  }

  private resolveCustomPresentationMode(
    userAgent: string,
    applicationFamily: BrowserUserAgentApplicationFamily = 'mobile'
  ): BrowserDesktopSiteMode {
    const normalized = userAgent.trim().toLowerCase();
    if (normalized.length <= 0) {
      return 'default';
    }
    if (normalized.includes('mobile') || normalized.includes('android') || normalized.includes('iphone') ||
      normalized.includes('ipad')) {
      return 'mobile';
    }
    if (normalized.includes('windows') || normalized.includes('macintosh') || normalized.includes('x11') ||
      normalized.includes('linux x86_64')) {
      return 'desktop';
    }
    return applicationFamily === 'mobile' ? 'mobile' : 'desktop';
  }

  private normalizePresetId(id: BrowserUserAgentPresetId): BrowserUserAgentPresetId {
    if (id === 'custom') {
      return SYSTEM_DEFAULT_USER_AGENT_PRESET_ID;
    }
    const normalized = id.trim();
    return BROWSER_USER_AGENT_PRESETS.some((preset: BrowserUserAgentPreset) => preset.id === normalized)
      ? normalized
      : SYSTEM_DEFAULT_USER_AGENT_PRESET_ID;
  }

  normalizeCustomUserAgent(userAgent: string): string {
    return userAgent.trim().replace(/\s+/g, ' ').slice(0, 512);
  }

  normalizeCustomUserAgentName(name: string, userAgent: string = ''): string {
    const normalized = name.trim().replace(/\s+/g, ' ').slice(0, 40);
    if (normalized.length > 0) {
      return normalized;
    }
    return this.resolveFallbackCustomUserAgentName(userAgent);
  }

  normalizeCustomUserAgentRecords(records: BrowserCustomUserAgentRecord[]): BrowserCustomUserAgentRecord[] {
    const normalizedRecords: BrowserCustomUserAgentRecord[] = [];
    records.forEach((record: BrowserCustomUserAgentRecord) => {
      const userAgent = this.normalizeCustomUserAgent(record.userAgent);
      if (userAgent.length <= 0) {
        return;
      }
      const id = `${record.id}`.trim().length > 0
        ? `${record.id}`.trim()
        : this.buildCustomUserAgentId(Number(record.createdAt) > 0 ? Number(record.createdAt) : Date.now(), record.name, userAgent);
      const existingIndex = normalizedRecords.findIndex((item: BrowserCustomUserAgentRecord) => item.id === id);
      const nextRecord: BrowserCustomUserAgentRecord = {
        id: id,
        name: this.normalizeCustomUserAgentName(record.name, userAgent),
        userAgent: userAgent,
        createdAt: Number(record.createdAt) > 0 ? Number(record.createdAt) : Date.now(),
        updatedAt: Number(record.updatedAt) > 0 ? Number(record.updatedAt) : Date.now()
      };
      if (existingIndex >= 0) {
        normalizedRecords[existingIndex] = nextRecord;
        return;
      }
      normalizedRecords.push(nextRecord);
    });
    return normalizedRecords
      .sort((left: BrowserCustomUserAgentRecord, right: BrowserCustomUserAgentRecord) => left.createdAt - right.createdAt)
      .slice(-MAX_CUSTOM_USER_AGENT_RECORDS);
  }

  findCustomUserAgent(
    records: BrowserCustomUserAgentRecord[],
    id: string
  ): BrowserCustomUserAgentRecord | undefined {
    const normalizedId = id.trim();
    if (normalizedId.length <= 0) {
      return undefined;
    }
    return records.find((record: BrowserCustomUserAgentRecord) => record.id === normalizedId);
  }

  private normalizeSelectedCustomUserAgentId(
    id: string,
    records: BrowserCustomUserAgentRecord[]
  ): string {
    const normalizedId = id.trim();
    if (normalizedId.length <= 0) {
      return '';
    }
    return records.some((record: BrowserCustomUserAgentRecord) => record.id === normalizedId) ? normalizedId : '';
  }

  private resolveFallbackCustomUserAgentName(userAgent: string): string {
    const normalizedUserAgent = this.normalizeCustomUserAgent(userAgent);
    if (normalizedUserAgent.includes('iPhone')) {
      return '自定义 iPhone';
    }
    if (normalizedUserAgent.includes('Windows')) {
      return '自定义 Windows';
    }
    if (normalizedUserAgent.includes('Macintosh')) {
      return '自定义 macOS';
    }
    if (normalizedUserAgent.includes('Android')) {
      return '自定义 Android';
    }
    return '自定义 UA';
  }

  private buildCustomUserAgentId(createdAt: number, name: string, userAgent: string): string {
    const seed = `${name}:${userAgent}`.split('').reduce((hash: number, char: string) => {
      return ((hash << 5) - hash + char.charCodeAt(0)) >>> 0;
    }, 0);
    return `custom_${createdAt}_${seed}`;
  }

  private buildResolution(
    userAgent: string,
    mode: BrowserUserAgentMode,
    source: BrowserUserAgentResolutionSource,
    reason: string,
    matchedHost: string,
    identityId: string = '',
    targetOrigin: string = ''
  ): BrowserUserAgentResolution {
    const normalizedUserAgent = userAgent.trim();
    const normalizedIdentityId = identityId.trim();
    const profile = this.buildProfile(
      normalizedIdentityId,
      normalizedUserAgent,
      mode,
      source,
      reason
    );
    return {
      userAgent: normalizedUserAgent,
      mode: mode,
      source: source,
      reason: reason,
      matchedHost: matchedHost,
      identityId: normalizedIdentityId,
      targetOrigin: targetOrigin,
      profile: profile
    };
  }

  private buildProfile(
    identityId: string,
    userAgent: string,
    mode: BrowserUserAgentMode,
    source: BrowserUserAgentResolutionSource,
    reason: string
  ): BrowserUserAgentProfile {
    const normalizedIdentityId = identityId.length > 0 ? identityId : source;
    if (source === 'system_default') {
      return {
        identityId: normalizedIdentityId,
        uaStringMode: 'system_untouched',
        uaString: userAgent,
        clientHintsMode: 'system',
        presentationMode: mode === 'desktop' ? 'desktop-request' : 'mobile',
        scopeCapability: 'application',
        compatibilityNotice: reason
      };
    }
    const metadata = this.resolveKnownClientHintsMetadata(normalizedIdentityId);
    return {
      identityId: normalizedIdentityId,
      uaStringMode: source === 'custom' ? 'custom' : 'known_preset',
      uaString: userAgent,
      clientHintsMode: metadata === undefined ? 'low_entropy_only' : 'known_metadata',
      metadata: metadata,
      presentationMode: mode === 'desktop' ? 'desktop-request' : 'mobile',
      scopeCapability: source === 'mandatory_compatibility' ? 'host' : 'runtime',
      compatibilityNotice: source === 'custom'
        ? '自定义 UA 只保证字符串兼容，不承诺完整浏览器指纹一致。'
        : reason
    };
  }

  private resolveKnownClientHintsMetadata(identityId: string): BrowserUserAgentClientHintsMetadata | undefined {
    if (identityId === AIRA_DEFAULT_BROWSER_IDENTITY_ID) {
      return {
        brand: 'Google Chrome',
        majorVersion: '132',
        fullVersion: '132.0.0.0',
        platform: 'Android',
        platformVersion: '12',
        mobile: true,
        architecture: '',
        bitness: '',
        model: 'SGT-AL10',
        wow64: false
      };
    }
    if (identityId === 'mobile_huawei_browser') {
      return {
        brand: 'Google Chrome',
        majorVersion: '132',
        fullVersion: '132.0.0.0',
        platform: 'Android',
        platformVersion: '10',
        mobile: true,
        architecture: '',
        bitness: '',
        model: '',
        wow64: false
      };
    }
    if (identityId === 'mobile_chrome_android') {
      return {
        brand: 'Google Chrome',
        majorVersion: '148',
        fullVersion: '148.0.0.0',
        platform: 'Android',
        platformVersion: '10',
        mobile: true,
        architecture: '',
        bitness: '',
        model: 'K',
        wow64: false
      };
    }
    if (identityId === DESKTOP_CHROME_USER_AGENT_PRESET_ID ||
      identityId === AIRA_DESKTOP_DEFAULT_BROWSER_IDENTITY_ID) {
      return {
        brand: 'Google Chrome',
        majorVersion: '148',
        fullVersion: '148.0.0.0',
        platform: 'Windows',
        platformVersion: '10.0.0',
        mobile: false,
        architecture: 'x86',
        bitness: '64',
        model: '',
        wow64: false
      };
    }
    return undefined;
  }

  private resolveIdentity(
    identityId: string,
    settings: BrowserUserAgentSettings,
    systemDefaultUserAgent: string,
    applicationFamily: BrowserUserAgentApplicationFamily
  ): BrowserUserAgentIdentity | undefined {
    const normalizedId = identityId.trim();
    if (normalizedId === AIRA_DEFAULT_BROWSER_IDENTITY_ID) {
      return {
        id: normalizedId,
        title: 'Aira默认',
        subtitle: '使用 Android 兼容移动网页标识',
        mode: 'mobile',
        userAgent: AIRA_COMPAT_MOBILE_USER_AGENT,
        source: 'preset'
      };
    }
    const catalog = this.getIdentityCatalog(settings);
    const catalogIdentity = catalog.find((identity: BrowserUserAgentIdentity) => identity.id === normalizedId);
    if (catalogIdentity === undefined || catalogIdentity.id === FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      return undefined;
    }
    if (catalogIdentity.source === 'arkweb_original') {
      return {
        id: catalogIdentity.id,
        title: catalogIdentity.title,
        subtitle: catalogIdentity.subtitle,
        mode: applicationFamily === 'mobile' ? 'mobile' : 'desktop',
        userAgent: systemDefaultUserAgent.trim(),
        source: 'arkweb_original'
      };
    }
    return catalogIdentity;
  }

  private findSiteOverride(
    url: string,
    target: SiteSettingTarget | undefined,
    overrides: BrowserUserAgentSiteOverride[],
    profileId: BrowserProfileId | undefined
  ): BrowserUserAgentSiteOverride | undefined {
    const resolvedTarget = target ?? this.siteIdentityService.resolveSiteSettingTarget(url);
    if (resolvedTarget === undefined) {
      return undefined;
    }
    return overrides.find((override: BrowserUserAgentSiteOverride) => {
      return (profileId === undefined || override.profileId === profileId) &&
        override.target.canonicalOrigin === resolvedTarget.canonicalOrigin;
    });
  }

  extractHost(url: string): string {
    return this.siteIdentityService.extractHost(url);
  }

  private hostMatches(actualHost: string, ruleHost: string, includeSubdomains: boolean): boolean {
    return this.siteIdentityService.hostMatches(actualHost, ruleHost, includeSubdomains);
  }
}

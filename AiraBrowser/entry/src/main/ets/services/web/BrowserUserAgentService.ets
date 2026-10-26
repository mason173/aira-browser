import {
  BrowserCustomUserAgentRecord,
  BrowserUserAgentMode,
  BrowserUserAgentPresetId,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import { SiteSettingTarget } from '../../common/models/SiteSettingModels';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import { SiteIdentityService } from './SiteIdentityService';

export type BrowserUserAgentPresetKind = 'application_default' | 'native' | 'preset';
export type BrowserUserAgentIdentityKind = 'follow_global' | 'native' | 'preset' | 'custom';

export interface BrowserUserAgentPreset {
  id: BrowserUserAgentPresetId;
  title: string;
  subtitle: string;
  kind: BrowserUserAgentPresetKind;
  presentationMode: BrowserDesktopSiteMode;
  userAgent: string;
}

export interface BrowserUserAgentRiskNotice {
  title: ResourceStr;
  message: ResourceStr;
  confirmText: ResourceStr;
  cancelText: ResourceStr;
}

export interface BrowserCustomUserAgentDraft {
  name: string;
  userAgent: string;
}

// One already-selected scoped identity, not a second policy/precedence input.
export interface BrowserUserAgentIdentityResolutionInput {
  identityId: string;
  settings: BrowserUserAgentSettings;
  systemDefaultUserAgent: string;
  applicationFamily: BrowserUserAgentApplicationFamily;
  scope: 'current_tab' | 'exact_origin';
  pageUrl: string;
  targetOrigin?: string;
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
  kind: BrowserUserAgentIdentityKind;
  presentationMode: BrowserDesktopSiteMode;
  userAgent: string;
}

// Legacy execution classification retained for runtime/history and redirect-affinity compatibility.
// It is not policy precedence: BrowserBrowsingIdentityDecision.winningSource records that separately.
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

// Keep the stored ID for existing preferences; this is Aira's automatic choice, not native ArkWeb.
export const APPLICATION_DEFAULT_USER_AGENT_PRESET_ID: BrowserUserAgentPresetId = 'system_default';
export const DESKTOP_CHROME_USER_AGENT_PRESET_ID: BrowserUserAgentPresetId = 'desktop_chrome_windows';
export const ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID: BrowserUserAgentPresetId = 'arkweb_original';
export const AIRA_COMPAT_MOBILE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 12; SGT-AL10 Build/HUAWEISGT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.130 Mobile HuaweiBrowser/6.1.1.303';
export const HUAWEI_BROWSER_USER_AGENT: string =
  'Mozilla/5.0 (Phone; OpenHarmony 6.0; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.130 Mobile HuaweiBrowser/6.1.1.303';
// Native ArkWeb publishes a `Phone; OpenHarmony ... Mobile` identity. Pages that pick an
// app-launch scheme from the platform token must see that shape instead of an Android one, so
// this identity deliberately carries no `Android` token while keeping ArkWeb and Mobile.
export const AIRA_COMPAT_HARMONY_MOBILE_USER_AGENT: string =
  'Mozilla/5.0 (Phone; OpenHarmony 6.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 ArkWeb/6.0.0.130 Mobile';
export const CHROME_ANDROID_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Mobile Safari/537.36';
export const AIRA_COMPAT_DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36';

export const BROWSER_USER_AGENT_RISK_NOTICE: BrowserUserAgentRiskNotice = {
  title: $r('app.string.web_ua_settings_risk_title'),
  message: $r('app.string.web_ua_settings_risk_message'),
  confirmText: $r('app.string.web_ua_settings_risk_confirm'),
  cancelText: $r('app.string.settings_account_cancel')
};

export const DEFAULT_BROWSER_USER_AGENT_SETTINGS: BrowserUserAgentSettings = {
  defaultMode: 'mobile',
  selectedPresetId: APPLICATION_DEFAULT_USER_AGENT_PRESET_ID,
  customUserAgent: '',
  selectedCustomUserAgentId: '',
  customUserAgents: [],
  updatedAt: 0
};

const MAX_CUSTOM_USER_AGENT_RECORDS: number = 24;

interface BrowserUserAgentPresetCopy {
  title: string;
  subtitle: string;
}

export const BROWSER_USER_AGENT_PRESETS: BrowserUserAgentPreset[] = [
  {
    id: APPLICATION_DEFAULT_USER_AGENT_PRESET_ID,
    title: 'Aira默认',
    subtitle: '使用 Aira 默认网页标识，可按站点单独设置',
    kind: 'application_default',
    presentationMode: 'default',
    userAgent: AIRA_COMPAT_MOBILE_USER_AGENT
  },
  {
    id: ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID,
    title: 'ArkWeb 原始标识',
    subtitle: '直接使用系统网页标识，用于网页登录验证或问题排查',
    kind: 'native',
    presentationMode: 'default',
    userAgent: ''
  },
  {
    id: 'mobile_huawei_browser',
    title: '华为浏览器',
    subtitle: '使用 OpenHarmony/HuaweiBrowser 原始兼容标识',
    kind: 'preset',
    presentationMode: 'mobile',
    userAgent: HUAWEI_BROWSER_USER_AGENT
  },
  {
    id: 'mobile_chrome_android',
    title: 'Chrome Android',
    subtitle: '常见 Android 手机上的 Chrome 标识',
    kind: 'preset',
    presentationMode: 'mobile',
    userAgent: CHROME_ANDROID_USER_AGENT
  },
  {
    id: 'mobile_safari_iphone',
    title: 'Safari iPhone',
    subtitle: '常见 iPhone Safari 标识',
    kind: 'preset',
    presentationMode: 'mobile',
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1'
  },
  {
    id: DESKTOP_CHROME_USER_AGENT_PRESET_ID,
    title: 'Chrome Windows',
    subtitle: '适合请求桌面版网页',
    kind: 'preset',
    presentationMode: 'desktop',
    userAgent: AIRA_COMPAT_DESKTOP_USER_AGENT
  },
  {
    id: 'desktop_edge_windows',
    title: 'Microsoft Edge Windows',
    subtitle: '桌面 Edge 兼容标识',
    kind: 'preset',
    presentationMode: 'desktop',
    userAgent: `${AIRA_COMPAT_DESKTOP_USER_AGENT} Edg/140.0.0.0`
  },
  {
    id: 'desktop_safari_mac',
    title: 'Safari macOS',
    subtitle: '桌面 Safari 兼容标识',
    kind: 'preset',
    presentationMode: 'desktop',
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15'
  },
  {
    id: 'desktop_firefox_windows',
    title: 'Firefox Windows',
    subtitle: '桌面 Firefox 兼容标识',
    kind: 'preset',
    presentationMode: 'desktop',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:139.0) Gecko/20100101 Firefox/139.0'
  }
];

export class BrowserUserAgentService {
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();

  normalizeSettings(settings: BrowserUserAgentSettings | undefined): BrowserUserAgentSettings {
    const selectedPresetId = this.normalizePresetId(settings?.selectedPresetId ?? '');
    const preset = this.findPreset(selectedPresetId);
    const defaultMode = this.normalizeMode(settings?.defaultMode ?? this.resolvePresetSettingsMode(preset.id));
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
    return BROWSER_USER_AGENT_PRESETS.map((preset: BrowserUserAgentPreset) => this.localizePreset(preset));
  }

  getIdentityCatalog(settings: BrowserUserAgentSettings): BrowserUserAgentIdentity[] {
    const normalized = this.normalizeSettings(settings);
    const identities: BrowserUserAgentIdentity[] = [{
      id: FOLLOW_GLOBAL_BROWSER_IDENTITY_ID,
      title: resolveAppResourceText($r('app.string.settings_site_customization_follow_global')),
      subtitle: resolveAppResourceText($r('app.string.web_ua_follow_global_desc')),
      kind: 'follow_global',
      presentationMode: 'default',
      userAgent: ''
    }];
    this.getPresets().forEach((preset: BrowserUserAgentPreset) => {
      identities.push({
        id: preset.id === APPLICATION_DEFAULT_USER_AGENT_PRESET_ID ? AIRA_DEFAULT_BROWSER_IDENTITY_ID : preset.id,
        title: preset.title,
        subtitle: preset.subtitle,
        kind: preset.kind === 'native' ? 'native' : 'preset',
        // The explicit site/tab Aira identity remains the established mobile compatibility choice.
        presentationMode: preset.kind === 'application_default' ? 'mobile' : preset.presentationMode,
        userAgent: preset.userAgent
      });
    });
    normalized.customUserAgents.forEach((record: BrowserCustomUserAgentRecord) => {
      identities.push({
        id: record.id,
        title: record.name,
        subtitle: resolveAppResourceText($r('app.string.web_ua_custom_identity')),
        kind: 'custom',
        presentationMode: 'default',
        userAgent: record.userAgent
      });
    });
    return identities;
  }

  resolveSiteSettingTarget(value: string): SiteSettingTarget | undefined {
    return this.siteIdentityService.resolveSiteSettingTarget(value);
  }

  findPreset(id: BrowserUserAgentPresetId): BrowserUserAgentPreset {
    const preset = BROWSER_USER_AGENT_PRESETS.find((item: BrowserUserAgentPreset) => item.id === id) ??
      BROWSER_USER_AGENT_PRESETS[0];
    return this.localizePreset(preset);
  }

  private localizePreset(preset: BrowserUserAgentPreset): BrowserUserAgentPreset {
    const copy = this.resolvePresetCopy(preset.id);
    return {
      id: preset.id,
      title: copy.title,
      subtitle: copy.subtitle,
      kind: preset.kind,
      presentationMode: preset.presentationMode,
      userAgent: preset.userAgent
    };
  }

  private resolvePresetCopy(id: string): BrowserUserAgentPresetCopy {
    switch (id) {
      case ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID:
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_arkweb_original')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_arkweb_original_desc'))
        };
      case 'mobile_huawei_browser':
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_huawei_browser')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_huawei_browser_desc'))
        };
      case 'mobile_chrome_android':
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_chrome_android')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_chrome_android_desc'))
        };
      case 'mobile_safari_iphone':
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_safari_iphone')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_safari_iphone_desc'))
        };
      case DESKTOP_CHROME_USER_AGENT_PRESET_ID:
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_chrome_windows')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_chrome_windows_desc'))
        };
      case 'desktop_edge_windows':
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_edge_windows')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_edge_windows_desc'))
        };
      case 'desktop_safari_mac':
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_safari_mac')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_safari_mac_desc'))
        };
      case 'desktop_firefox_windows':
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_firefox_windows')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_firefox_windows_desc'))
        };
      default:
        return {
          title: resolveAppResourceText($r('app.string.web_ua_preset_aira_default')),
          subtitle: resolveAppResourceText($r('app.string.web_ua_preset_aira_default_desc'))
        };
    }
  }

  buildPresetSettings(
    presetId: BrowserUserAgentPresetId,
    currentSettings?: BrowserUserAgentSettings
  ): BrowserUserAgentSettings {
    const preset = this.findPreset(this.normalizePresetId(presetId));
    const normalizedCurrent = this.normalizeSettings(currentSettings);
    return {
      defaultMode: this.resolvePresetSettingsMode(preset.id),
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
    return normalized.selectedPresetId !== APPLICATION_DEFAULT_USER_AGENT_PRESET_ID;
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

  // Storage/UI selection compatibility only. A native or automatic identity is not a mobile preset.
  // Existing preferences encode both as defaultMode=mobile; preserve that on reads and writes.
  resolvePresetSettingsMode(presetId: BrowserUserAgentPresetId): BrowserUserAgentMode {
    return this.findPreset(presetId).presentationMode === 'desktop' ? 'desktop' : 'mobile';
  }

  resolveApplicationFamilyForDevice(detectedFormFactor: string): BrowserUserAgentApplicationFamily {
    const normalizedFormFactor = detectedFormFactor.trim().toLowerCase();
    if (normalizedFormFactor === 'car' || normalizedFormFactor === 'cockpit') {
      return 'mobile';
    }
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
    if (identity.presentationMode === 'desktop') {
      return 'desktop';
    }
    if (identity.presentationMode === 'mobile') {
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
    if (normalized.selectedPresetId === APPLICATION_DEFAULT_USER_AGENT_PRESET_ID) {
      return applicationFamily === 'mobile' ? 'mobile' : 'desktop';
    }
    return this.resolvePresentationModeForIdentity(
      normalized.selectedPresetId,
      normalized,
      applicationFamily
    );
  }

  buildMandatoryUserAgent(compatibility: BrowserUserAgentMandatoryCompatibility): BrowserUserAgentResolution {
    return this.buildResolution(
      compatibility.userAgent,
      compatibility.mode,
      'mandatory_compatibility',
      compatibility.reason,
      compatibility.host,
      compatibility.identityId
    );
  }

  resolveIdentityUserAgent(input: BrowserUserAgentIdentityResolutionInput): BrowserUserAgentResolution | undefined {
    const identity = this.resolveIdentity(
      input.identityId,
      input.settings,
      input.systemDefaultUserAgent,
      input.applicationFamily
    );
    if (identity === undefined) {
      return undefined;
    }
    const isSite = input.scope === 'exact_origin';
    return this.buildResolution(
      identity.userAgent,
      identity.kind === 'custom' ? 'custom' : identity.presentationMode === 'desktop' ? 'desktop' : 'mobile',
      identity.kind === 'native' ? 'system_default' : isSite ? 'site_setting' : 'preset',
      isSite ? 'The exact Origin selected a site browsing identity.' :
        'The current tab temporarily selected a browsing identity.',
      this.extractHost(isSite ? input.targetOrigin ?? input.pageUrl : input.pageUrl),
      identity.id,
      input.targetOrigin
    );
  }

  /**
   * Resolve only the global choice and its application default. Tab/Origin/Host precedence
   * belongs to the browsing-identity policy; these candidates must not re-enter that policy.
   * Legacy settings modes are decoded here, independently of the catalog's identity kind.
   */
  resolveGlobalUserAgent(
    inputSettings: BrowserUserAgentSettings,
    systemDefaultUserAgent: string,
    applicationFamily: BrowserUserAgentApplicationFamily = 'mobile'
  ): BrowserUserAgentResolution {
    const settings = this.normalizeSettings(inputSettings);
    const mode = settings.defaultMode;
    if (mode === 'custom') {
      const selectedCustomUserAgent = this.findCustomUserAgent(
        settings.customUserAgents,
        settings.selectedCustomUserAgentId
      );
      const customUserAgent = this.normalizeCustomUserAgent(selectedCustomUserAgent?.userAgent ?? settings.customUserAgent);
      return this.buildResolution(
        customUserAgent.length > 0 ? customUserAgent : this.resolvePresetUserAgent(settings, systemDefaultUserAgent),
        'custom',
        customUserAgent.length > 0 ? 'custom' : 'preset',
        customUserAgent.length > 0 ? 'User selected a custom UA.' : 'Custom UA is empty; using selected preset.',
        '',
        customUserAgent.length > 0 ? settings.selectedCustomUserAgentId : settings.selectedPresetId
      );
    }
    const selectedPreset = this.findPreset(settings.selectedPresetId);
    if (mode === 'desktop') {
      // Older settings can request desktop pages without naming a desktop preset.
      // Keep Chrome as that fallback, while honoring every explicitly selected desktop preset.
      const desktopPreset = selectedPreset.presentationMode === 'desktop'
        ? selectedPreset
        : this.findPreset(DESKTOP_CHROME_USER_AGENT_PRESET_ID);
      return this.buildResolution(
        desktopPreset.userAgent,
        'desktop',
        'preset',
        'User requested desktop pages.',
        '',
        desktopPreset.id
      );
    }
    if (settings.selectedPresetId !== APPLICATION_DEFAULT_USER_AGENT_PRESET_ID &&
      (selectedPreset.kind === 'native' || selectedPreset.presentationMode === 'mobile')) {
      return this.buildResolution(
        this.resolvePresetUserAgent(settings, systemDefaultUserAgent),
        'mobile',
        settings.selectedPresetId === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID ? 'system_default' : 'preset',
        settings.selectedPresetId === ARKWEB_ORIGINAL_USER_AGENT_PRESET_ID
          ? 'User selected ArkWeb original UA.'
          : 'User selected a mobile UA preset.',
        '',
        settings.selectedPresetId
      );
    }
    return this.resolveApplicationDefault(systemDefaultUserAgent, applicationFamily);
  }

  resolveApplicationDefault(
    systemDefaultUserAgent: string,
    applicationFamily: BrowserUserAgentApplicationFamily = 'mobile'
  ): BrowserUserAgentResolution {
    if (applicationFamily !== 'mobile') {
      // Keep the native Controller untouched, including its real platform and engine identity.
      // Passing this text through the custom-UA setter would not restore native identity.
      return this.buildResolution(
        systemDefaultUserAgent.trim(),
        'desktop',
        'system_default',
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
    return this.normalizeMode(mode) === 'desktop'
      ? resolveAppResourceText($r('app.string.web_ua_request_mobile'))
      : resolveAppResourceText($r('app.string.web_ua_request_desktop'));
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
      return normalized.customUserAgent.length > 0
        ? resolveAppResourceText($r('app.string.settings_custom_ua'))
        : resolveAppResourceText($r('app.string.web_ua_custom_ua_empty'));
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

  private resolveApplicationDefaultReason(applicationFamily: BrowserUserAgentApplicationFamily): string {
    if (applicationFamily !== 'mobile') {
      return 'Aira defaults the large-screen presentation to untouched ArkWeb identity.';
    }
    return 'Aira defaults the phone presentation to its Android-compatible mobile identity.';
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
      return APPLICATION_DEFAULT_USER_AGENT_PRESET_ID;
    }
    const normalized = id.trim();
    return BROWSER_USER_AGENT_PRESETS.some((preset: BrowserUserAgentPreset) => preset.id === normalized)
      ? normalized
      : APPLICATION_DEFAULT_USER_AGENT_PRESET_ID;
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
      return resolveAppResourceText($r('app.string.web_ua_custom_iphone'));
    }
    if (normalizedUserAgent.includes('Windows')) {
      return resolveAppResourceText($r('app.string.web_ua_custom_windows'));
    }
    if (normalizedUserAgent.includes('Macintosh')) {
      return resolveAppResourceText($r('app.string.web_ua_custom_macos'));
    }
    if (normalizedUserAgent.includes('Android')) {
      return resolveAppResourceText($r('app.string.web_ua_custom_android'));
    }
    return resolveAppResourceText($r('app.string.settings_custom_ua'));
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
        ? resolveAppResourceText($r('app.string.web_ua_custom_notice'))
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
    if (identityId === DESKTOP_CHROME_USER_AGENT_PRESET_ID) {
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
        title: resolveAppResourceText($r('app.string.web_ua_preset_aira_default')),
        subtitle: resolveAppResourceText($r('app.string.web_ua_android_compat')),
        kind: 'preset',
        presentationMode: 'mobile',
        userAgent: AIRA_COMPAT_MOBILE_USER_AGENT
      };
    }
    const catalog = this.getIdentityCatalog(settings);
    const catalogIdentity = catalog.find((identity: BrowserUserAgentIdentity) => identity.id === normalizedId);
    if (catalogIdentity === undefined || catalogIdentity.id === FOLLOW_GLOBAL_BROWSER_IDENTITY_ID) {
      return undefined;
    }
    if (catalogIdentity.kind === 'native') {
      return {
        id: catalogIdentity.id,
        title: catalogIdentity.title,
        subtitle: catalogIdentity.subtitle,
        kind: 'native',
        presentationMode: applicationFamily === 'mobile' ? 'mobile' : 'desktop',
        userAgent: systemDefaultUserAgent.trim(),
      };
    }
    return catalogIdentity;
  }

  extractHost(url: string): string {
    return this.siteIdentityService.extractHost(url);
  }
}

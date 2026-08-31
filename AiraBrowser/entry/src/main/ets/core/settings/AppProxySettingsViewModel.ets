import {
  BrowserAppProxyProfile,
  BrowserAppProxyScheme,
  BrowserAppProxySettings,
  BrowserExperimentSettings
} from '../../common/models/BrowserModels';
import { DEFAULT_BROWSER_APP_PROXY_SETTINGS } from '../../data/preferences/PreferencesRepository';

export interface AppProxyProfileDraft {
  id: string;
  name: string;
  scheme: BrowserAppProxyScheme;
  host: string;
  portText: string;
  username: string;
  password: string;
  bypassHosts: string;
}

export interface AppProxySettingsValidationResult {
  valid: boolean;
  message: string;
}

export interface AppProxyProfileListItemState {
  id: string;
  title: string;
  summary: string;
  isActive: boolean;
  canSelect: boolean;
}

export interface AppProxySettingsPageState {
  globalEnabled: boolean;
  activeProfileName: string;
  activeSummary: string;
  hasProfiles: boolean;
  profileItems: AppProxyProfileListItemState[];
  helperText: string;
}

interface AppProxyProfileDraftPatch {
  id?: string;
  name?: string;
  scheme?: BrowserAppProxyScheme;
  host?: string;
  portText?: string;
  username?: string;
  password?: string;
  bypassHosts?: string;
}

export class AppProxySettingsViewModel {
  buildPageState(settings: BrowserExperimentSettings): AppProxySettingsPageState {
    const activeProfile = this.resolveActiveProfile(settings);
    const profileItems: AppProxyProfileListItemState[] = [];
    for (let index = 0; index < settings.appProxyProfiles.length; index += 1) {
      const profile = settings.appProxyProfiles[index];
      profileItems.push({
        id: profile.id,
        title: profile.name,
        summary: this.buildProfileSummary(profile),
        isActive: profile.id === settings.appProxyActiveProfileId,
        canSelect: settings.appProxyEnabled
      });
    }
    return {
      globalEnabled: settings.appProxyEnabled,
      activeProfileName: activeProfile?.name ?? '未选择代理',
      activeSummary: activeProfile !== undefined ? this.buildProfileSummary(activeProfile) : '关闭',
      hasProfiles: settings.appProxyProfiles.length > 0,
      profileItems: profileItems,
      helperText: settings.appProxyProfiles.length > 0
        ? '点击条目只是选择代理配置；只有打开总开关后，当前选择才会应用到网页请求。右侧按钮进入详细设置。'
        : '还没有已保存的代理，先添加一个代理配置。'
    };
  }

  buildDraftForCreate(): AppProxyProfileDraft {
    return {
      id: '',
      name: '',
      scheme: DEFAULT_BROWSER_APP_PROXY_SETTINGS.scheme,
      host: DEFAULT_BROWSER_APP_PROXY_SETTINGS.host,
      portText: '',
      username: DEFAULT_BROWSER_APP_PROXY_SETTINGS.username,
      password: DEFAULT_BROWSER_APP_PROXY_SETTINGS.password,
      bypassHosts: DEFAULT_BROWSER_APP_PROXY_SETTINGS.bypassHosts
    };
  }

  buildDraftForEdit(settings: BrowserExperimentSettings, profileId: string): AppProxyProfileDraft {
    const profile = this.findProfile(settings, profileId);
    if (profile === undefined) {
      return this.buildDraftForCreate();
    }
    return {
      id: profile.id,
      name: profile.name,
      scheme: profile.settings.scheme,
      host: profile.settings.host,
      portText: profile.settings.port > 0 ? `${profile.settings.port}` : '',
      username: profile.settings.username,
      password: profile.settings.password,
      bypassHosts: profile.settings.bypassHosts
    };
  }

  updateDraftName(draft: AppProxyProfileDraft, name: string): AppProxyProfileDraft {
    return this.copyDraft(draft, { name: name });
  }

  updateDraftScheme(draft: AppProxyProfileDraft, scheme: BrowserAppProxyScheme): AppProxyProfileDraft {
    return this.copyDraft(draft, { scheme: scheme });
  }

  updateDraftHost(draft: AppProxyProfileDraft, host: string): AppProxyProfileDraft {
    return this.copyDraft(draft, { host: host });
  }

  updateDraftPortText(draft: AppProxyProfileDraft, portText: string): AppProxyProfileDraft {
    return this.copyDraft(draft, { portText: portText });
  }

  updateDraftUsername(draft: AppProxyProfileDraft, username: string): AppProxyProfileDraft {
    return this.copyDraft(draft, { username: username });
  }

  updateDraftPassword(draft: AppProxyProfileDraft, password: string): AppProxyProfileDraft {
    return this.copyDraft(draft, { password: password });
  }

  updateDraftBypassHosts(draft: AppProxyProfileDraft, bypassHosts: string): AppProxyProfileDraft {
    return this.copyDraft(draft, { bypassHosts: bypassHosts });
  }

  buildSettingsWithActiveProfile(
    current: BrowserExperimentSettings,
    profileId: string
  ): BrowserExperimentSettings {
    if (!current.appProxyEnabled) {
      return current;
    }
    const activeProfile = this.findProfile(current, profileId) ?? current.appProxyProfiles[0];
    if (activeProfile === undefined) {
      return this.buildSettingsWithNoActiveProfile(current);
    }
    return this.buildSettingsWithProfiles(
      current,
      current.appProxyProfiles,
      activeProfile.id
    );
  }

  buildSettingsWithSavedDraft(
    current: BrowserExperimentSettings,
    draft: AppProxyProfileDraft
  ): BrowserExperimentSettings {
    const validation = this.validate(draft);
    if (!validation.valid) {
      return current;
    }
    const now = Date.now();
    const nextProfile: BrowserAppProxyProfile = {
      id: draft.id.trim().length > 0 ? draft.id : this.buildProfileId(now),
      name: draft.name.trim(),
      settings: this.buildProxySettingsFromDraft(draft, now),
      createdAt: draft.id.trim().length > 0
        ? (this.findProfile(current, draft.id)?.createdAt ?? now)
        : now,
      updatedAt: now
    };

    const nextProfiles: BrowserAppProxyProfile[] = [];
    let replaced = false;
    for (let index = 0; index < current.appProxyProfiles.length; index += 1) {
      const profile = current.appProxyProfiles[index];
      if (profile.id === nextProfile.id) {
        nextProfiles.push(nextProfile);
        replaced = true;
        continue;
      }
      nextProfiles.push(profile);
    }
    if (!replaced) {
      nextProfiles.push(nextProfile);
    }
    const nextActiveProfileId = current.appProxyActiveProfileId.length > 0
      ? current.appProxyActiveProfileId
      : nextProfile.id;
    return this.buildSettingsWithProfiles(current, nextProfiles, nextActiveProfileId);
  }

  buildSettingsWithGlobalEnabled(
    current: BrowserExperimentSettings,
    enabled: boolean
  ): BrowserExperimentSettings {
    const activeProfile = this.resolveActiveProfile(current);
    return {
      pauseWebAnimationsDuringScroll: current.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: current.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: current.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: current.pullRefreshEnabled,
      forceEnableWebZoom: current.forceEnableWebZoom,
      smartGripTabsActionsEnabled: current.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: current.webVideoTakeoverEnabled,
      novelModeEnabled: current.novelModeEnabled,
      novelAutoTakeoverEnabled: current.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: current.appProxyActiveProfileId,
      appProxyProfiles: current.appProxyProfiles,
      appProxyEnabled: enabled && activeProfile !== undefined,
      appProxy: activeProfile?.settings ?? current.appProxy
    };
  }

  buildSettingsWithDeletedProfile(
    current: BrowserExperimentSettings,
    profileId: string
  ): BrowserExperimentSettings {
    const nextProfiles: BrowserAppProxyProfile[] = [];
    for (let index = 0; index < current.appProxyProfiles.length; index += 1) {
      const profile = current.appProxyProfiles[index];
      if (profile.id !== profileId) {
        nextProfiles.push(profile);
      }
    }
    if (nextProfiles.length <= 0) {
      return this.buildSettingsWithNoActiveProfile(current);
    }
    const nextActiveProfileId = current.appProxyActiveProfileId === profileId
      ? nextProfiles[0].id
      : current.appProxyActiveProfileId;
    return this.buildSettingsWithProfiles(current, nextProfiles, nextActiveProfileId);
  }

  validate(draft: AppProxyProfileDraft): AppProxySettingsValidationResult {
    if (draft.name.trim().length <= 0) {
      return { valid: false, message: '请输入代理名称。' };
    }
    if (draft.host.trim().length === 0) {
      return { valid: false, message: '请填写服务器地址。' };
    }
    const port = this.parsePort(draft.portText);
    if (port <= 0 || port > 65535) {
      return { valid: false, message: '端口需要在 1-65535 之间。' };
    }
    return { valid: true, message: '' };
  }

  buildSummary(settings: BrowserExperimentSettings): string {
    const activeProfile = this.resolveActiveProfile(settings);
    if (activeProfile === undefined) {
      return '关闭';
    }
    if (!settings.appProxyEnabled) {
      return `${activeProfile.name} · 已关闭`;
    }
    if (activeProfile.settings.host.trim().length === 0 || activeProfile.settings.port <= 0) {
      return `${activeProfile.name} · 待配置`;
    }
    const scheme = activeProfile.settings.scheme === 'socks5' ? 'socks' : activeProfile.settings.scheme;
    return `${activeProfile.name} · ${scheme}://${activeProfile.settings.host}:${activeProfile.settings.port}`;
  }

  buildProfileSummary(profile: BrowserAppProxyProfile): string {
    if (profile.settings.host.trim().length === 0 || profile.settings.port <= 0) {
      return '待配置';
    }
    const scheme = profile.settings.scheme === 'socks5' ? 'socks' : profile.settings.scheme;
    return `${scheme}://${profile.settings.host}:${profile.settings.port}`;
  }

  buildCapabilityNote(settings: BrowserExperimentSettings): string {
    const activeProfile = this.resolveActiveProfile(settings);
    if (activeProfile === undefined) {
      return '还没有已保存的代理。';
    }
    if (!settings.appProxyEnabled) {
      return `当前选中 ${activeProfile.name}，打开总开关后会应用到 ArkWeb。`;
    }
    return `当前选中 ${activeProfile.name}，开启总开关后会应用到 ArkWeb；用户名和密码会用于匹配的代理认证请求。`;
  }

  resolveSchemeLabel(scheme: BrowserAppProxyScheme): string {
    if (scheme === 'https') {
      return 'HTTPS';
    }
    if (scheme === 'socks5') {
      return 'SOCKS5';
    }
    return 'HTTP';
  }

  findProfile(settings: BrowserExperimentSettings, profileId: string): BrowserAppProxyProfile | undefined {
    for (let index = 0; index < settings.appProxyProfiles.length; index += 1) {
      const profile = settings.appProxyProfiles[index];
      if (profile.id === profileId) {
        return profile;
      }
    }
    return undefined;
  }

  private resolveActiveProfile(settings: BrowserExperimentSettings): BrowserAppProxyProfile | undefined {
    return this.findProfile(settings, settings.appProxyActiveProfileId) ?? settings.appProxyProfiles[0];
  }

  private buildSettingsWithProfiles(
    current: BrowserExperimentSettings,
    profiles: BrowserAppProxyProfile[],
    requestedActiveProfileId: string
  ): BrowserExperimentSettings {
    const activeProfile = this.findProfileInProfiles(profiles, requestedActiveProfileId) ?? profiles[0];
    if (activeProfile === undefined) {
      return this.buildSettingsWithNoActiveProfile(current);
    }
    return {
      pauseWebAnimationsDuringScroll: current.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: current.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: current.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: current.pullRefreshEnabled,
      forceEnableWebZoom: current.forceEnableWebZoom,
      smartGripTabsActionsEnabled: current.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: current.webVideoTakeoverEnabled,
      novelModeEnabled: current.novelModeEnabled,
      novelAutoTakeoverEnabled: current.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: activeProfile.id,
      appProxyProfiles: profiles,
      appProxyEnabled: current.appProxyEnabled,
      appProxy: activeProfile.settings
    };
  }

  private buildSettingsWithNoActiveProfile(current: BrowserExperimentSettings): BrowserExperimentSettings {
    return {
      pauseWebAnimationsDuringScroll: current.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: current.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: current.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: current.pullRefreshEnabled,
      forceEnableWebZoom: current.forceEnableWebZoom,
      smartGripTabsActionsEnabled: current.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: current.webVideoTakeoverEnabled,
      novelModeEnabled: current.novelModeEnabled,
      novelAutoTakeoverEnabled: current.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: '',
      appProxyProfiles: [],
      appProxyEnabled: false,
      appProxy: DEFAULT_BROWSER_APP_PROXY_SETTINGS
    };
  }

  private buildProxySettingsFromDraft(draft: AppProxyProfileDraft, updatedAt: number): BrowserAppProxySettings {
    return {
      scheme: draft.scheme,
      host: draft.host.trim(),
      port: this.parsePort(draft.portText),
      username: draft.username.trim(),
      password: draft.password,
      bypassHosts: draft.bypassHosts.trim(),
      updatedAt: updatedAt
    };
  }

  private buildProfileId(now: number): string {
    return `proxy-${now}-${Math.floor(Math.random() * 1000000)}`;
  }

  private copyDraft(
    draft: AppProxyProfileDraft,
    patch: AppProxyProfileDraftPatch
  ): AppProxyProfileDraft {
    return {
      id: patch.id ?? draft.id,
      name: patch.name ?? draft.name,
      scheme: patch.scheme ?? draft.scheme,
      host: patch.host ?? draft.host,
      portText: patch.portText ?? draft.portText,
      username: patch.username ?? draft.username,
      password: patch.password ?? draft.password,
      bypassHosts: patch.bypassHosts ?? draft.bypassHosts
    };
  }

  private findProfileInProfiles(
    profiles: BrowserAppProxyProfile[],
    profileId: string
  ): BrowserAppProxyProfile | undefined {
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      if (profile.id === profileId) {
        return profile;
      }
    }
    return undefined;
  }

  private parsePort(value: string): number {
    const numberValue = Number(value.trim());
    if (!Number.isFinite(numberValue)) {
      return 0;
    }
    return Math.floor(numberValue);
  }
}

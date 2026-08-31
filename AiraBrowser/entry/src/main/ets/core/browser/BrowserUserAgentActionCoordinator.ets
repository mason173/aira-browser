import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserProfileId,
  BrowserUserAgentMode,
  BrowserUserAgentPresetId,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import { BrowserUserAgentSettingsRepository } from '../../data/browser/BrowserUserAgentSettingsRepository';
import {
  BrowserUserAgentSettingsViewModel,
  BrowserUserAgentSettingsViewState
} from '../settings/BrowserUserAgentSettingsViewModel';
import {
  BrowserDesktopSiteMode,
  BrowserUserAgentRiskNotice,
  BrowserUserAgentService,
  AIRA_DEFAULT_BROWSER_IDENTITY_ID,
  DESKTOP_CHROME_USER_AGENT_PRESET_ID,
} from '../../services/web/BrowserUserAgentService';
import {
  BrowserDesktopSiteModeSheetState,
  BrowserDesktopSiteModeSheetViewModel
} from './BrowserDesktopSiteModeSheetViewModel';
import { BrowserWebPageToolsCoordinator } from './BrowserWebPageToolsCoordinator';
import { BrowserBrowsingIdentityPolicyCoordinator } from './BrowserBrowsingIdentityPolicyCoordinator';
import {
  BrowserUserAgentRuntimePolicyCoordinator,
  BrowserUserAgentRuntimePolicyResult
} from './BrowserUserAgentRuntimePolicyCoordinator';

const USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN: number = 0x0000;
const USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG: string = 'BrowsingIdentity';
const USER_AGENT_ACTION_DIAGNOSTIC_PREFIX: string = '[DEBUG-UA-ACTION-20260828]';

export interface BrowserUserAgentActionFacts {
  activeTabId: string;
  activeTabIsWebPage: boolean;
  currentUrl: string;
  profileId: BrowserProfileId;
  privateTabIds: string[];
}

export interface BrowserUserAgentActionPresentation {
  desktopSiteMode: BrowserDesktopSiteMode;
  desktopSiteActionVersion: number;
  settings: BrowserUserAgentSettings;
  userAgentPresetActionVersion: number;
  desktopSiteModeSheetState: BrowserDesktopSiteModeSheetState;
  userAgentPresetSheetState: BrowserUserAgentSettingsViewState;
  selectedPresetId: BrowserUserAgentPresetId;
  selectedMode: BrowserUserAgentMode;
}

export interface BrowserUserAgentActionSink {
  resolveFacts: () => BrowserUserAgentActionFacts;
  publishPresentation: (presentation: BrowserUserAgentActionPresentation) => void;
  confirmRisk: (notice: BrowserUserAgentRiskNotice, onConfirm: () => void, onCancel?: () => void) => void;
  showToast: (message: string) => void;
}

interface BrowserDesktopSiteActionResult {
  ok: boolean;
  message: string;
}

export class BrowserUserAgentActionCoordinator {
  private readonly settingsRepository: BrowserUserAgentSettingsRepository;
  private readonly userAgentService: BrowserUserAgentService;
  private readonly browsingIdentityPolicyCoordinator: BrowserBrowsingIdentityPolicyCoordinator;
  private readonly pageToolsCoordinator: BrowserWebPageToolsCoordinator;
  private readonly runtimePolicyCoordinator: BrowserUserAgentRuntimePolicyCoordinator;
  private readonly desktopSiteModeSheetViewModel: BrowserDesktopSiteModeSheetViewModel =
    new BrowserDesktopSiteModeSheetViewModel();
  private readonly userAgentSettingsViewModel: BrowserUserAgentSettingsViewModel =
    new BrowserUserAgentSettingsViewModel();
  private readonly sink: BrowserUserAgentActionSink;
  private optimisticDesktopSiteMode: BrowserDesktopSiteMode | '' = '';
  private optimisticSettings?: BrowserUserAgentSettings;
  private desktopSiteActionVersion: number = 0;
  private userAgentPresetActionVersion: number = 0;

  constructor(
    settingsRepository: BrowserUserAgentSettingsRepository,
    userAgentService: BrowserUserAgentService,
    pageToolsCoordinator: BrowserWebPageToolsCoordinator,
    runtimePolicyCoordinator: BrowserUserAgentRuntimePolicyCoordinator,
    browsingIdentityPolicyCoordinator: BrowserBrowsingIdentityPolicyCoordinator,
    sink: BrowserUserAgentActionSink
  ) {
    this.settingsRepository = settingsRepository;
    this.userAgentService = userAgentService;
    this.pageToolsCoordinator = pageToolsCoordinator;
    this.runtimePolicyCoordinator = runtimePolicyCoordinator;
    this.browsingIdentityPolicyCoordinator = browsingIdentityPolicyCoordinator;
    this.sink = sink;
  }

  snapshot(): BrowserUserAgentActionPresentation {
    return this.buildPresentation('default', this.settingsRepository.getSettings());
  }

  synchronize(): void {
    this.optimisticDesktopSiteMode = '';
    this.desktopSiteActionVersion += 1;
    this.publishPresentation();
  }

  openDesktopSiteModeSheet(): void {
    this.publishPresentation();
    this.pageToolsCoordinator.open('desktopSiteMode');
  }

  selectDesktopSiteMode(mode: BrowserDesktopSiteMode): void {
    const facts = this.sink.resolveFacts();
    const displayedMode = this.resolveDisplayedDesktopSiteMode(facts);
    hilog.info(
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN,
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG,
      `${USER_AGENT_ACTION_DIAGNOSTIC_PREFIX} select tab=%{public}s host=%{public}s ` +
        'requested=%{public}s displayed=%{public}s',
      facts.activeTabId,
      this.userAgentService.extractHost(facts.currentUrl),
      mode,
      displayedMode
    );
    if (mode === displayedMode) {
      hilog.info(
        USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN,
        USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG,
        `${USER_AGENT_ACTION_DIAGNOSTIC_PREFIX} select-noop tab=%{public}s requested=%{public}s`,
        facts.activeTabId,
        mode
      );
      this.pageToolsCoordinator.reset();
      return;
    }
    this.optimisticDesktopSiteMode = mode;
    this.desktopSiteActionVersion += 1;
    this.publishPresentation(facts);
    if (mode === 'desktop' && this.userAgentService.shouldWarnForModeSwitch(mode)) {
      this.sink.confirmRisk(
        this.userAgentService.getRiskNotice(),
        (): void => {
          this.applyDesktopSiteMode(mode);
        },
        (): void => {
          this.cancelDesktopSiteModeSelection();
        }
      );
      return;
    }
    this.applyDesktopSiteMode(mode);
  }

  private applyDesktopSiteMode(mode: BrowserDesktopSiteMode): void {
    this.pageToolsCoordinator.reset();
    const facts = this.sink.resolveFacts();
    const result = this.applyTransientMode(facts.activeTabId, facts.currentUrl, mode);
    hilog.info(
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN,
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG,
      `${USER_AGENT_ACTION_DIAGNOSTIC_PREFIX} apply tab=%{public}s host=%{public}s ` +
        'requested=%{public}s ok=%{public}s',
      facts.activeTabId,
      this.userAgentService.extractHost(facts.currentUrl),
      mode,
      result.ok ? '1' : '0'
    );
    this.optimisticDesktopSiteMode = '';
    this.desktopSiteActionVersion += 1;
    this.publishPresentation(facts);
    if (!result.ok) {
      this.showToast(result.message);
      return;
    }
    void this.handleRuntimeChangeCommitted(result.message, true);
  }

  private cancelDesktopSiteModeSelection(): void {
    this.optimisticDesktopSiteMode = '';
    this.desktopSiteActionVersion += 1;
    this.publishPresentation();
  }

  openUserAgentPresetSheet(replaceCurrentSheet: boolean = false): void {
    this.publishPresentation();
    this.pageToolsCoordinator.open('userAgentPreset', replaceCurrentSheet);
  }

  selectUserAgentPreset(presetId: BrowserUserAgentPresetId): void {
    const settings = this.userAgentService.buildPresetSettings(presetId, this.resolveDisplayedSettings());
    this.confirmAndApplySettings(settings);
  }

  selectCustomUserAgent(recordId: string): void {
    const settings = this.userAgentService.buildCustomSettings('', this.resolveDisplayedSettings(), recordId);
    this.confirmAndApplySettings(settings);
  }

  private confirmAndApplySettings(settings: BrowserUserAgentSettings): void {
    if (!this.userAgentService.shouldWarnForSettings(settings)) {
      void this.applySettings(settings);
      return;
    }
    this.sink.confirmRisk(
      this.userAgentService.getRiskNotice(),
      (): void => {
        void this.applySettings(settings);
      }
    );
  }

  private async applySettings(settings: BrowserUserAgentSettings): Promise<void> {
    this.runtimePolicyCoordinator.cancelPending();
    const previousOptimisticSettings = this.optimisticSettings;
    this.optimisticSettings = settings;
    this.userAgentPresetActionVersion += 1;
    this.publishPresentation();
    this.pageToolsCoordinator.reset();
    let savedSettings: BrowserUserAgentSettings;
    try {
      savedSettings = await this.settingsRepository.saveSettings(settings);
    } catch (_error) {
      this.optimisticSettings = previousOptimisticSettings;
      this.userAgentPresetActionVersion += 1;
      this.publishPresentation();
      this.showToast('网页标识保存失败。');
      return;
    }
    this.optimisticSettings = undefined;
    this.optimisticDesktopSiteMode = '';
    this.desktopSiteActionVersion += 1;
    this.userAgentPresetActionVersion += 1;
    this.publishPresentation(undefined, savedSettings);
    await this.handleRuntimeChangeCommitted(`已切换为${this.userAgentService.resolveSettingsSummary(savedSettings)}。`);
  }

  private publishPresentation(
    facts: BrowserUserAgentActionFacts = this.sink.resolveFacts(),
    settingsOverride?: BrowserUserAgentSettings
  ): void {
    const settings = settingsOverride ?? this.resolveDisplayedSettings();
    this.sink.publishPresentation(
      this.buildPresentation(this.resolveDisplayedDesktopSiteMode(facts), settings)
    );
  }

  private buildPresentation(
    desktopSiteMode: BrowserDesktopSiteMode,
    settings: BrowserUserAgentSettings
  ): BrowserUserAgentActionPresentation {
    const normalizedSettings = this.userAgentService.normalizeSettings(settings);
    return {
      desktopSiteMode: desktopSiteMode,
      desktopSiteActionVersion: this.desktopSiteActionVersion,
      settings: normalizedSettings,
      userAgentPresetActionVersion: this.userAgentPresetActionVersion,
      desktopSiteModeSheetState: this.desktopSiteModeSheetViewModel.buildState(
        desktopSiteMode,
        this.userAgentService.resolveSettingsSummary(normalizedSettings)
      ),
      userAgentPresetSheetState: this.userAgentSettingsViewModel.buildState(normalizedSettings),
      selectedPresetId: normalizedSettings.defaultMode === 'custom'
        ? normalizedSettings.selectedCustomUserAgentId
        : normalizedSettings.selectedPresetId,
      selectedMode: normalizedSettings.defaultMode
    };
  }

  private resolveDisplayedDesktopSiteMode(facts: BrowserUserAgentActionFacts): BrowserDesktopSiteMode {
    if (this.optimisticDesktopSiteMode !== '') {
      return this.optimisticDesktopSiteMode;
    }
    return this.resolveCurrentMode(facts.activeTabId, facts.currentUrl, facts.profileId);
  }

  private resolveDisplayedSettings(): BrowserUserAgentSettings {
    return this.optimisticSettings ?? this.settingsRepository.getSettings();
  }

  private applyTransientMode(
    tabId: string,
    currentUrl: string,
    mode: BrowserDesktopSiteMode
  ): BrowserDesktopSiteActionResult {
    const normalizedTabId = tabId.trim();
    const origin = this.userAgentService.extractOrigin(currentUrl);
    const host = this.userAgentService.extractHost(origin);
    if (normalizedTabId.length === 0 || host.length === 0 || origin.length === 0) {
      return {
        ok: false,
        message: '打开网页后可设置网站版本。'
      };
    }
    const identityId = mode === 'desktop' ? DESKTOP_CHROME_USER_AGENT_PRESET_ID :
      mode === 'mobile' ? AIRA_DEFAULT_BROWSER_IDENTITY_ID : undefined;
    this.browsingIdentityPolicyCoordinator.setCurrentTabIdentity(normalizedTabId, identityId);
    return {
      ok: true,
      message: this.resolveSavedMessage(mode)
    };
  }

  private resolveCurrentMode(
    tabId: string,
    currentUrl: string,
    profileId: BrowserProfileId
  ): BrowserDesktopSiteMode {
    return this.browsingIdentityPolicyCoordinator.resolveDisplayedMode(
      tabId,
      currentUrl,
      profileId,
      this.sink.resolveFacts().privateTabIds.includes(tabId)
    );
  }

  private resolveSavedMessage(mode: BrowserDesktopSiteMode): string {
    if (mode === 'desktop') {
      return '当前标签页已临时使用桌面版。';
    }
    if (mode === 'mobile') {
      return '当前标签页已临时使用移动版。';
    }
    return '当前标签页已跟随默认。';
  }

  private async handleRuntimeChangeCommitted(
    message: string,
    reloadIfIdentityUnchanged: boolean = false
  ): Promise<void> {
    const result: BrowserUserAgentRuntimePolicyResult =
      await this.runtimePolicyCoordinator.reconcile('user_manual_reload', reloadIfIdentityUnchanged);
    if (result.status === 'non_web_tab_skipped' || result.resolution === undefined) {
      return;
    }
    if (result.status === 'identity_unchanged') {
      this.showToast(result.resolution.winningSource === 'mandatory_host'
        ? '网页标识选择已保存；当前网站继续使用 Aira 兼容标识。'
        : message);
      return;
    }
    if (result.status === 'transition_superseded') {
      return;
    }
    if (result.status === 'transition_deferred') {
      this.showToast('网页标识选择已保存。为保留返回与前进历史，当前标签仍使用原网页标识；Web 运行时重建后生效。');
      return;
    }
    this.showToast(message);
  }

  private showToast(message: string): void {
    if (message.length > 0) {
      this.sink.showToast(message);
    }
  }
}

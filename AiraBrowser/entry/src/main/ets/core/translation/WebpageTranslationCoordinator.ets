import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TranslationProviderConfig,
  TranslationProviderTemplateId,
  TranslationSettings,
  TranslationSettingsPreferences
} from '../../common/models/BrowserModels';
import { TranslationSettingsRepository } from '../../data/translation/TranslationSettingsRepository';
import { TranslationSecretStore } from '../../data/translation/TranslationSecretStore';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationApplyResult,
  WebpageTranslationExtractionResult,
  WebpageTranslationTextItem
} from '../../services/web/WebpageTranslationRuntimeModels';
import { WebpageTranslationRuntimeBridge } from '../../services/web/WebpageTranslationRuntimeBridge';
import { TranslationProviderError } from '../../services/translation/TranslationProviderFailureClassifierService';
import { WebpageTranslationLanguageService } from '../../services/translation/WebpageTranslationLanguageService';
import {
  WebpageTranslationManualPolicyDecision,
  WebpageTranslationManualPolicyInput,
  WebpageTranslationPolicyService
} from '../../services/translation/WebpageTranslationPolicyService';
import {
  WebpageTranslationCacheContext
} from '../../services/translation/WebpageTranslationPersistentCacheService';
import {
  WebpageTranslationCacheCoordinator,
  WebpageTranslationCachePipeline
} from './WebpageTranslationCacheCoordinator';
import { WebpageTranslationLifecycleCoordinator } from './WebpageTranslationLifecycleCoordinator';
import { WebpageTranslationRequestCoordinator } from './WebpageTranslationRequestCoordinator';
import {
  WebpageTranslationSessionCoordinator
} from './WebpageTranslationSessionCoordinator';
import {
  TranslationLanguageOptionView,
  WebpageTranslationSettingsViewModel
} from './WebpageTranslationSettingsViewModel';
import { BrowserTransientSurfaceCoordinator } from '../browser/BrowserTransientSurfaceCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import {
  TranslationSettingsBoundary,
  TranslationSettingsCoordinator,
  TranslationSettingsMutationResult
} from './TranslationSettingsCoordinator';

const WEBPAGE_TRANSLATION_LOG_DOMAIN: number = 0x0000;
const WEBPAGE_TRANSLATION_LOG_TAG: string = 'QFWebTranslate';
const CLOUD_TRANSLATION_MAX_ITEM_CHARS: number = 500;
const CLOUD_TRANSLATION_MAX_QUEUE_ROUNDS: number = 8;
const CLOUD_TRANSLATION_MAX_TOTAL_CHARS: number = 30000;
const CLOUD_TRANSLATION_DYNAMIC_PENDING_NODE_LIMIT: number = 16;
const CLOUD_TRANSLATION_DYNAMIC_PENDING_CHAR_LIMIT: number = 2000;

interface WebpageTranslationCachedApplySummary {
  appliedCount: number;
  appliedChars: number;
  cacheHitCount: number;
}

interface WebpageTranslationProgress {
  appliedCount: number;
  appliedChars: number;
  attemptedCount: number;
  attemptedChars: number;
  requestedCount: number;
  requestedChars: number;
  cacheHitCount: number;
  stoppedAfterProviderFailure: boolean;
  hasMore: boolean;
}

interface WebpageTranslationAggregateProgress {
  appliedCount: number;
  appliedChars: number;
  attemptedCount: number;
  attemptedChars: number;
  requestedCount: number;
  requestedChars: number;
  cacheHitCount: number;
  stoppedAfterProviderFailure: boolean;
  extractedCount: number;
  extractedChars: number;
  hasMore: boolean;
  lastExtraction: WebpageTranslationExtractionResult;
}

interface WebpageTranslationPanelOpenResult {
  state: WebpageTranslationPanelState;
  shouldResumeDynamicTranslation: boolean;
}

interface WebpageTranslationTabLifecycleInput {
  tabId: string;
  activeTabId: string;
  url: string;
  controller?: webview.WebviewController;
  wasActive?: boolean;
}

interface WebpageTranslationActiveTabChangedInput {
  previousTabId: string;
  activeTabId: string;
  activeUrl: string;
}

export type WebpageTranslationUserAction =
  'open_panel' |
  'close_panel' |
  'translate' |
  'restore_original' |
  'show_bilingual' |
  'show_translation_only' |
  'cancel' |
  'open_target_language' |
  'dismiss_target_language' |
  'select_target_language';

export interface WebpageTranslationTargetLanguageAction {
  type: 'dismiss' | 'select';
  languageCode?: string;
}

export interface WebpageTranslationApplicationContext {
  activeTabId: string;
  activeUrl: string;
  appServiceModeFull: boolean;
  privateMode: boolean;
  tabsSheetVisible: boolean;
  promptSurfaceAvailable: boolean;
}

interface WebpageTranslationPanelOriginState {
  tabId: string;
  url: string;
}

interface WebpageTranslationTargetLanguagePresentation {
  helperText: string;
  options: TranslationLanguageOptionView[];
}

export interface WebpageTranslationApplicationSnapshot {
  panel: WebpageTranslationPanelState;
  origin: WebpageTranslationPanelOriginState;
  targetLanguage: WebpageTranslationTargetLanguagePresentation;
}

export interface WebpageTranslationCloudDisclosureRequest {
  title: string;
  message: string;
  cancelLabel: string;
  acceptLabel: string;
  onAccept: () => void;
}

interface WebpageTranslationApplicationShell {
  readContext: () => WebpageTranslationApplicationContext;
  publishSnapshot: (snapshot: WebpageTranslationApplicationSnapshot) => void;
  showToast: (message: string) => void;
  showCloudDisclosure: (request: WebpageTranslationCloudDisclosureRequest) => void;
}

interface WebpageTranslationApplicationDependencies {
  settingsRepository: TranslationSettingsRepository;
  transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  targetLanguageRevealDelayMs: number;
  targetLanguageDismissDurationMs: number;
}

type WebpageTranslationStatus =
  'idle' |
  'extracting' |
  'translating' |
  'partially_translated' |
  'translated' |
  'restored' |
  'error';

type WebpageTranslationDisplayMode =
  'none' |
  'bilingual' |
  'translation_only' |
  'original';

export interface WebpageTranslationPanelState {
  visible: boolean;
  status: WebpageTranslationStatus;
  displayMode: WebpageTranslationDisplayMode;
  title: string;
  message: string;
  providerTemplateId: TranslationProviderTemplateId;
  providerDisplayName: string;
  sourceLanguage: string;
  targetLanguage: string;
  translatedCount: number;
  canTranslate: boolean;
  canRestore: boolean;
  canCancel: boolean;
}

export const DEFAULT_WEBPAGE_TRANSLATION_PANEL_STATE: WebpageTranslationPanelState = {
  visible: false,
  status: 'idle',
  displayMode: 'none',
  title: '网页翻译',
  message: '准备翻译当前网页',
  providerTemplateId: 'custom_http',
  providerDisplayName: '未配置翻译服务',
  sourceLanguage: '',
  targetLanguage: 'zh-CN',
  translatedCount: 0,
  canTranslate: true,
  canRestore: false,
  canCancel: false
};

const DEFAULT_WEBPAGE_TRANSLATION_APPLICATION_SNAPSHOT: WebpageTranslationApplicationSnapshot = {
  panel: DEFAULT_WEBPAGE_TRANSLATION_PANEL_STATE,
  origin: {
    tabId: '',
    url: ''
  },
  targetLanguage: {
    helperText: '',
    options: []
  }
};

export class WebpageTranslationCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly settingsRepository: TranslationSettingsRepository;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly targetLanguageRevealDelayMs: number;
  private readonly targetLanguageDismissDurationMs: number;
  private readonly applicationShell: WebpageTranslationApplicationShell;
  private runtimeBridge: WebpageTranslationRuntimeBridge = new WebpageTranslationRuntimeBridge();
  private requestCoordinator: WebpageTranslationRequestCoordinator;
  private languageService: WebpageTranslationLanguageService = new WebpageTranslationLanguageService();
  private policyService: WebpageTranslationPolicyService = new WebpageTranslationPolicyService();
  private cacheCoordinator: WebpageTranslationCacheCoordinator = new WebpageTranslationCacheCoordinator();
  private lifecycleCoordinator: WebpageTranslationLifecycleCoordinator = new WebpageTranslationLifecycleCoordinator();
  private sessionCoordinator: WebpageTranslationSessionCoordinator = new WebpageTranslationSessionCoordinator();
  private settingsViewModel: WebpageTranslationSettingsViewModel = new WebpageTranslationSettingsViewModel();
  private readonly translationSettingsCoordinator: TranslationSettingsCoordinator;
  private applicationSnapshot: WebpageTranslationApplicationSnapshot =
    DEFAULT_WEBPAGE_TRANSLATION_APPLICATION_SNAPSHOT;
  private applicationSurfaceVersion: number = 0;

  constructor(
    secretStore: TranslationSecretStore | undefined,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    applicationDependencies: WebpageTranslationApplicationDependencies,
    applicationShell: WebpageTranslationApplicationShell
  ) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.settingsRepository = applicationDependencies.settingsRepository;
    this.transientSurfaceCoordinator = applicationDependencies.transientSurfaceCoordinator;
    this.targetLanguageRevealDelayMs = applicationDependencies.targetLanguageRevealDelayMs;
    this.targetLanguageDismissDurationMs = applicationDependencies.targetLanguageDismissDurationMs;
    this.applicationShell = applicationShell;
    this.requestCoordinator = new WebpageTranslationRequestCoordinator(secretStore);
    this.translationSettingsCoordinator = new TranslationSettingsCoordinator(this.settingsRepository, secretStore);
  }

  getApplicationSnapshot(): WebpageTranslationApplicationSnapshot {
    return this.applicationSnapshot;
  }

  isPanelSurfaceVisible(
    snapshot: WebpageTranslationApplicationSnapshot,
    context: WebpageTranslationApplicationContext
  ): boolean {
    const originTabId = snapshot.origin.tabId.trim();
    const tabId = originTabId.length > 0 ? originTabId : context.activeTabId;
    return this.isSurfaceActive(tabId, snapshot.origin.url, context);
  }

  handleUserAction(action: WebpageTranslationUserAction, value: string = ''): void {
    switch (action) {
      case 'open_panel':
        this.openApplicationPanel();
        return;
      case 'close_panel':
        this.closeApplicationSurface();
        return;
      case 'translate':
        void this.translateCurrentWebpage();
        return;
      case 'restore_original':
        void this.restoreOriginalWebpageText();
        return;
      case 'show_bilingual':
        void this.showBilingualWebpageTranslation();
        return;
      case 'show_translation_only':
        void this.showTranslationOnlyWebpageTranslation();
        return;
      case 'cancel':
        void this.cancelWebpageTranslation();
        return;
      case 'open_target_language':
        this.openTargetLanguageSurface();
        return;
      case 'dismiss_target_language':
        this.transientSurfaceCoordinator.dismiss('translation_target_language');
        return;
      case 'select_target_language':
        void this.selectTargetLanguage(value);
        return;
      default:
        return;
    }
  }

  handleTargetLanguageAction(action: WebpageTranslationTargetLanguageAction): void {
    if (action.type === 'dismiss') {
      this.handleUserAction('dismiss_target_language');
      return;
    }
    if (action.languageCode !== undefined) {
      this.handleUserAction('select_target_language', action.languageCode);
    }
  }

  handleShellDisappear(): void {
    this.pauseDynamicTranslation();
  }

  private openApplicationPanel(): void {
    const context = this.applicationShell.readContext();
    if (!this.isSurfaceActive(context.activeTabId, '', context)) {
      return;
    }
    const origin = this.buildOrigin(context.activeTabId, context.activeUrl);
    const settings = this.settingsRepository.getSettings();
    const canResumeCurrentPage = this.originMatches(this.applicationSnapshot.origin, origin);
    if (!canResumeCurrentPage) {
      this.cancelCurrentTask();
    }
    this.applicationSurfaceVersion += 1;
    const surfaceVersion = this.applicationSurfaceVersion;
    const openResult: WebpageTranslationPanelOpenResult = canResumeCurrentPage
      ? this.openPanelFromToolbar(this.applicationSnapshot.panel, settings)
      : {
        state: this.openPanel(settings),
        shouldResumeDynamicTranslation: false
      };
    this.publishApplicationSnapshot(
      openResult.state,
      origin,
      this.applicationSnapshot.targetLanguage
    );
    if (!openResult.shouldResumeDynamicTranslation) {
      return;
    }
    void this.resumeDynamicTranslationForCurrentPage(
      this.runtimeLifecyclePort.resolveController(origin.tabId),
      settings,
      openResult.state,
      (state: WebpageTranslationPanelState): void => {
        this.publishPanelStateForOrigin(state, origin, surfaceVersion);
      }
    );
  }

  private closeApplicationSurface(): void {
    this.applicationSurfaceVersion += 1;
    const panel = this.closePanel(this.applicationSnapshot.panel);
    this.transientSurfaceCoordinator.reset('translation_target_language');
    this.publishApplicationSnapshot(
      panel,
      this.applicationSnapshot.origin,
      this.applicationSnapshot.targetLanguage
    );
  }

  private async cancelWebpageTranslation(): Promise<void> {
    const origin = this.applicationSnapshot.origin;
    const surfaceVersion = this.applicationSurfaceVersion;
    const state = await this.cancelCurrentPageTranslation(
      this.runtimeLifecyclePort.resolveActiveController(),
      this.applicationSnapshot.panel
    );
    this.publishPanelStateForOrigin(state, origin, surfaceVersion);
  }

  private async translateCurrentWebpage(): Promise<void> {
    const context = this.applicationShell.readContext();
    const settings = this.settingsRepository.getSettings();
    const origin = this.buildOrigin(context.activeTabId, context.activeUrl);
    const surfaceVersion = this.applicationSurfaceVersion;
    const policyInput: WebpageTranslationManualPolicyInput = {
      settings: settings,
      appServiceModeFull: context.appServiceModeFull,
      privateMode: context.privateMode,
      currentUrl: origin.url
    };
    const decision: WebpageTranslationManualPolicyDecision =
      this.policyService.resolveManualTranslationDecision(policyInput);
    if (!decision.allowed) {
      this.applicationShell.showToast(decision.message);
      return;
    }
    if (decision.requiresCloudDisclosure) {
      this.showCloudDisclosure(settings, decision, origin, surfaceVersion);
      return;
    }
    await this.runWebpageTranslationForOrigin(settings, origin, surfaceVersion);
  }

  private showCloudDisclosure(
    settings: TranslationSettings,
    decision: WebpageTranslationManualPolicyDecision,
    origin: WebpageTranslationPanelOriginState,
    surfaceVersion: number
  ): void {
    const providerName = this.policyService.buildCloudDisclosureProviderName(decision.provider);
    const request: WebpageTranslationCloudDisclosureRequest = {
      title: '确认网页翻译',
      message: `当前页面文字将发送到 ${providerName} 处理。确认后会直接开始翻译。`,
      cancelLabel: '取消',
      acceptLabel: '同意并翻译',
      onAccept: (): void => {
        void this.acceptCloudDisclosureAndTranslate(settings, origin, surfaceVersion);
      }
    };
    this.applicationShell.showCloudDisclosure(request);
  }

  private async acceptCloudDisclosureAndTranslate(
    currentSettings: TranslationSettings,
    origin: WebpageTranslationPanelOriginState,
    surfaceVersion: number
  ): Promise<void> {
    if (!this.isExpectedOriginCurrent(origin, surfaceVersion)) {
      return;
    }
    const nextPreferences = this.policyService.buildCloudDisclosureAcceptedPreferences(
      currentSettings.preferences,
      Date.now()
    );
    try {
      const result = await this.translationSettingsCoordinator.updatePreferences(
        nextPreferences,
        this.buildTranslationSettingsBoundary()
      );
      if (!result.allowed) {
        return;
      }
      const nextSettings = result.settings;
      if (!this.isExpectedOriginCurrent(origin, surfaceVersion)) {
        return;
      }
      await this.runWebpageTranslationForOrigin(nextSettings, origin, surfaceVersion);
    } catch (_error) {
      if (this.isExpectedOriginCurrent(origin, surfaceVersion)) {
        this.applicationShell.showToast('暂时无法保存翻译确认，请稍后再试。');
      }
    }
  }

  private async runWebpageTranslationForOrigin(
    settings: TranslationSettings,
    origin: WebpageTranslationPanelOriginState,
    surfaceVersion: number
  ): Promise<void> {
    await this.translateCurrentPage(
      this.runtimeLifecyclePort.resolveController(origin.tabId),
      settings,
      (state: WebpageTranslationPanelState): void => {
        this.publishPanelStateForOrigin(state, origin, surfaceVersion);
      }
    );
  }

  private async restoreOriginalWebpageText(): Promise<void> {
    const origin = this.applicationSnapshot.origin;
    const surfaceVersion = this.applicationSurfaceVersion;
    const state = await this.restoreOriginals(
      this.runtimeLifecyclePort.resolveActiveController(),
      this.applicationSnapshot.panel
    );
    this.publishPanelStateForOrigin(state, origin, surfaceVersion);
  }

  private async showBilingualWebpageTranslation(): Promise<void> {
    const origin = this.applicationSnapshot.origin;
    const surfaceVersion = this.applicationSurfaceVersion;
    const state = await this.showBilingualTranslations(
      this.runtimeLifecyclePort.resolveActiveController(),
      this.applicationSnapshot.panel
    );
    this.publishPanelStateForOrigin(state, origin, surfaceVersion);
  }

  private async showTranslationOnlyWebpageTranslation(): Promise<void> {
    const origin = this.applicationSnapshot.origin;
    const surfaceVersion = this.applicationSurfaceVersion;
    const state = await this.showTranslationOnly(
      this.runtimeLifecyclePort.resolveActiveController(),
      this.applicationSnapshot.panel
    );
    this.publishPanelStateForOrigin(state, origin, surfaceVersion);
  }

  private openTargetLanguageSurface(): void {
    const settings = this.settingsRepository.getSettings();
    const activeProvider = this.policyService.resolveActiveProvider(settings);
    const normalizedLanguage = this.settingsViewModel.normalizePreferredTargetLanguageForProvider(
      activeProvider,
      settings.preferences.preferredTargetLanguage
    );
    const state = this.applicationSnapshot.panel;
    const panel: WebpageTranslationPanelState = {
      visible: state.visible,
      status: state.status,
      displayMode: state.displayMode,
      title: state.title,
      message: state.message,
      providerTemplateId: state.providerTemplateId,
      providerDisplayName: state.providerDisplayName,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: normalizedLanguage,
      translatedCount: state.translatedCount,
      canTranslate: state.canTranslate,
      canRestore: state.canRestore,
      canCancel: state.canCancel
    };
    const targetLanguage: WebpageTranslationTargetLanguagePresentation = {
      helperText: this.settingsViewModel.buildTargetLanguageSheetHelperText(),
      options: this.settingsViewModel.buildTargetLanguageOptions()
    };
    this.publishApplicationSnapshot(panel, this.applicationSnapshot.origin, targetLanguage);
    this.transientSurfaceCoordinator.present({
      id: 'translation_target_language',
      revealDelayMs: this.targetLanguageRevealDelayMs,
      dismissDurationMs: this.targetLanguageDismissDurationMs
    });
  }

  private async selectTargetLanguage(languageCode: string): Promise<void> {
    this.transientSurfaceCoordinator.reset('translation_target_language');
    const origin = this.applicationSnapshot.origin;
    const panel = this.applicationSnapshot.panel;
    const surfaceVersion = this.applicationSurfaceVersion;
    try {
      const state = await this.updateTargetLanguage(panel, languageCode);
      this.publishPanelStateForOrigin(state, origin, surfaceVersion);
      this.applicationShell.showToast(`已切换为${this.settingsViewModel.buildLanguageLabel(languageCode)}`);
    } catch (_error) {
      this.applicationShell.showToast('目标语言保存失败，请稍后再试。');
    }
  }

  private resetApplicationSurface(): void {
    this.applicationSurfaceVersion += 1;
    const panel = this.closePanel(this.applicationSnapshot.panel);
    this.transientSurfaceCoordinator.reset('translation_target_language');
    this.publishApplicationSnapshot(
      panel,
      this.createEmptyOrigin(),
      this.applicationSnapshot.targetLanguage
    );
  }

  private publishPanelStateForOrigin(
    state: WebpageTranslationPanelState,
    origin: WebpageTranslationPanelOriginState,
    surfaceVersion: number
  ): void {
    if (!this.isExpectedOriginCurrent(origin, surfaceVersion)) {
      return;
    }
    this.publishApplicationSnapshot(state, origin, this.applicationSnapshot.targetLanguage);
  }

  private isExpectedOriginCurrent(origin: WebpageTranslationPanelOriginState, surfaceVersion: number): boolean {
    return surfaceVersion === this.applicationSurfaceVersion &&
      this.originMatches(this.applicationSnapshot.origin, origin) &&
      this.isPageCurrent(origin.tabId, origin.url, this.applicationShell.readContext());
  }

  private isSurfaceActive(
    tabId: string,
    expectedUrl: string,
    context: WebpageTranslationApplicationContext
  ): boolean {
    return this.isPageCurrent(tabId, expectedUrl, context) &&
      !context.tabsSheetVisible &&
      context.promptSurfaceAvailable;
  }

  private isPageCurrent(
    tabId: string,
    expectedUrl: string,
    context: WebpageTranslationApplicationContext
  ): boolean {
    if (tabId.trim().length <= 0 || tabId !== context.activeTabId) {
      return false;
    }
    if (expectedUrl.trim().length <= 0) {
      return true;
    }
    return this.isSameUrl(expectedUrl, context.activeUrl);
  }

  private isSameUrl(expectedUrl: string, actualUrl: string): boolean {
    const expected = expectedUrl.trim();
    const actual = actualUrl.trim();
    return expected.length > 0 && actual.length > 0 && expected === actual;
  }

  private originMatches(
    left: WebpageTranslationPanelOriginState,
    right: WebpageTranslationPanelOriginState
  ): boolean {
    if (left.tabId.trim() !== right.tabId.trim()) {
      return false;
    }
    const expectedUrl = left.url.trim();
    return expectedUrl.length <= 0 || this.isSameUrl(expectedUrl, right.url);
  }

  private buildOrigin(tabId: string, url: string): WebpageTranslationPanelOriginState {
    return { tabId: tabId.trim(), url: url.trim() };
  }

  private createEmptyOrigin(): WebpageTranslationPanelOriginState {
    return { tabId: '', url: '' };
  }

  private publishApplicationSnapshot(
    panel: WebpageTranslationPanelState,
    origin: WebpageTranslationPanelOriginState,
    targetLanguage: WebpageTranslationTargetLanguagePresentation
  ): void {
    const snapshot: WebpageTranslationApplicationSnapshot = {
      panel: panel,
      origin: origin,
      targetLanguage: targetLanguage
    };
    this.applicationSnapshot = snapshot;
    this.applicationShell.publishSnapshot(snapshot);
  }

  private openPanel(settings: TranslationSettings): WebpageTranslationPanelState {
    return {
      visible: true,
      status: 'idle',
      displayMode: 'none',
      title: '翻译此网页',
      message: this.buildReadyMessage(settings),
      providerTemplateId: this.resolvePanelProviderTemplateId(settings),
      providerDisplayName: this.resolvePanelProviderDisplayName(settings),
      sourceLanguage: '',
      targetLanguage: settings.preferences.preferredTargetLanguage,
      translatedCount: 0,
      canTranslate: settings.preferences.enabled,
      canRestore: false,
      canCancel: false
    };
  }

  private openPanelFromToolbar(
    currentState: WebpageTranslationPanelState,
    settings: TranslationSettings
  ): WebpageTranslationPanelOpenResult {
    if (this.canReopenExistingPanelState(currentState)) {
      this.sessionCoordinator.setDisplayMode(currentState.displayMode);
      return {
        state: {
          visible: true,
          status: currentState.status,
          displayMode: currentState.displayMode,
          title: currentState.title,
          message: currentState.message,
          providerTemplateId: this.resolvePanelProviderTemplateId(settings),
          providerDisplayName: this.resolvePanelProviderDisplayName(settings),
          sourceLanguage: currentState.sourceLanguage,
          targetLanguage: currentState.targetLanguage,
          translatedCount: currentState.translatedCount,
          canTranslate: currentState.canTranslate,
          canRestore: currentState.canRestore,
          canCancel: false
        },
        shouldResumeDynamicTranslation: this.shouldResumeDynamicTranslationForState(currentState)
      };
    }
    return {
      state: this.openPanel(settings),
      shouldResumeDynamicTranslation: false
    };
  }

  private closePanel(state: WebpageTranslationPanelState): WebpageTranslationPanelState {
    if (state.canCancel) {
      this.cancelCurrentTask();
    }
    return {
      visible: false,
      status: state.status,
      displayMode: state.displayMode,
      title: state.title,
      message: state.message,
      providerTemplateId: state.providerTemplateId,
      providerDisplayName: state.providerDisplayName,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
      translatedCount: state.translatedCount,
      canTranslate: state.canTranslate,
      canRestore: state.canRestore,
      canCancel: false
    };
  }

  private cancelCurrentTask(): void {
    this.sessionCoordinator.cancelCurrentTaskGeneration();
    this.requestCoordinator.cancelActiveRequests();
    this.lifecycleCoordinator.stopDynamicTranslationPolling();
  }

  private async cancelCurrentPageTranslation(
    controller: webview.WebviewController | undefined,
    state: WebpageTranslationPanelState
  ): Promise<WebpageTranslationPanelState> {
    this.cancelCurrentTask();
    if (controller !== undefined) {
      await this.clearTransientTranslationStates(controller);
    }
    return {
      visible: true,
      status: 'idle',
      displayMode: state.displayMode,
      title: '网页翻译',
      message: '已取消当前翻译任务',
      providerTemplateId: state.providerTemplateId,
      providerDisplayName: state.providerDisplayName,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
      translatedCount: state.translatedCount,
      canTranslate: true,
      canRestore: state.canRestore,
      canCancel: false
    };
  }

  private async translateCurrentPage(
    controller: webview.WebviewController | undefined,
    settings: TranslationSettings,
    onState: (state: WebpageTranslationPanelState) => void
  ): Promise<void> {
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'translateCurrentPage start enabled=%{public}s activeProvider=%{public}s target=%{public}s',
      settings.preferences.enabled ? 'true' : 'false',
      settings.activeProviderId,
      settings.preferences.preferredTargetLanguage
    );
    this.lifecycleCoordinator.resumeDynamicTranslation();
    this.lifecycleCoordinator.stopDynamicTranslationPolling();
    this.requestCoordinator.cancelActiveRequests();
    const taskGeneration = this.nextGeneration();
    this.sessionCoordinator.setDisplayMode('translation_only');
    if (!settings.preferences.enabled) {
      onState(this.buildErrorState(settings, '请先在网页翻译设置中开启功能。'));
      return;
    }
    const provider = this.resolveActiveProvider(settings);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'provider resolved template=%{public}s status=%{public}s display=%{public}s',
      provider?.templateId ?? 'none',
      provider?.status ?? 'none',
      provider?.displayName ?? ''
    );
    if (!this.isProviderReadyForTranslation(provider)) {
      onState(this.buildProviderUnavailableState(settings, provider));
      return;
    }
    if (controller === undefined) {
      onState(this.buildErrorState(settings, '当前页面还没有可用的网页控制器。'));
      return;
    }
    const initialRuntimeCacheNamespace = this.cacheCoordinator.buildRuntimeCacheNamespace(provider, settings);
    onState({
      visible: true,
      status: 'extracting',
      displayMode: 'none',
      title: '正在准备翻译',
      message: '正在读取当前网页文字',
      providerTemplateId: this.resolveProviderTemplateId(provider),
      providerDisplayName: this.resolveProviderDisplayName(provider),
      sourceLanguage: '',
      targetLanguage: settings.preferences.preferredTargetLanguage,
      translatedCount: 0,
      canTranslate: false,
      canRestore: false,
      canCancel: true
    });
    try {
      await this.runtimeBridge.configureCache(controller, initialRuntimeCacheNamespace);
      hilog.info(WEBPAGE_TRANSLATION_LOG_DOMAIN, WEBPAGE_TRANSLATION_LOG_TAG, 'extract initial visible batch start');
      const extraction = await this.runtimeBridge.extractVisibleBatch(
        controller,
        this.requestCoordinator.resolveInitialNodeLimit(provider),
        this.requestCoordinator.resolveInitialCharLimit(provider)
      );
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'extract initial visible batch done items=%{public}d chars=%{public}d lang=%{public}s title=%{public}s',
        extraction.items.length,
        this.countItemChars(extraction.items),
        extraction.lang,
        extraction.title
      );
      if (this.isStale(taskGeneration)) {
        return;
      }
      if (extraction.items.length === 0) {
        onState(this.buildErrorState(settings, '当前可见区域没有可翻译文字。', extraction.lang));
        return;
      }
      const sourceLanguage = this.languageService.inferLanguage(extraction.lang, extraction.items);
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'source language inferred raw=%{public}s inferred=%{public}s target=%{public}s',
        extraction.lang,
        sourceLanguage,
        settings.preferences.preferredTargetLanguage
      );
      if (sourceLanguage.length === 0) {
        onState(this.buildErrorState(settings, '未能识别当前页面语言。', extraction.lang));
        return;
      }
      const sourcePolicyDecision = this.policyService.resolveSourceLanguageDecision({
        settings: settings,
        sourceLanguage: sourceLanguage,
        currentUrl: extraction.url
      });
      if (!sourcePolicyDecision.allowed) {
        onState(this.buildErrorState(settings, sourcePolicyDecision.message, sourceLanguage));
        return;
      }
      const effectiveSettings = this.buildSettingsWithTargetLanguage(settings, sourcePolicyDecision.targetLanguage);
      const runtimeCacheNamespace = this.cacheCoordinator.buildRuntimeCacheNamespace(provider, effectiveSettings, sourceLanguage);
      await this.runtimeBridge.configureCache(controller, runtimeCacheNamespace);
      onState({
        visible: true,
        status: 'translating',
        displayMode: 'none',
        title: '正在翻译',
        message: this.buildTranslatingMessage(extraction.items.length, this.countItemChars(extraction.items), provider),
        providerTemplateId: this.resolveProviderTemplateId(provider),
        providerDisplayName: this.resolveProviderDisplayName(provider),
        sourceLanguage: sourceLanguage,
        targetLanguage: effectiveSettings.preferences.preferredTargetLanguage,
        translatedCount: 0,
        canTranslate: false,
        canRestore: false,
        canCancel: true
      });
      const cacheContext = this.cacheCoordinator.buildPersistentCacheContext(provider, sourceLanguage, effectiveSettings);
      this.sessionCoordinator.beginSession({
        generation: taskGeneration,
        provider: provider,
        settings: effectiveSettings,
        sourceLanguage: sourceLanguage,
        targetLanguage: effectiveSettings.preferences.preferredTargetLanguage,
        documentUrl: extraction.url,
        runtimeCacheNamespace: runtimeCacheNamespace,
        cacheContext: cacheContext
      });
      const hydratedExtraction = await this.cacheCoordinator.hydrateExtraction(extraction, cacheContext);
      const progress = await this.translateAndApplyPageQueues(
        controller,
        provider,
        hydratedExtraction,
        sourceLanguage,
        effectiveSettings,
        cacheContext,
        onState,
        taskGeneration
      );
      if (this.isStale(taskGeneration)) {
        return;
      }
      const finalHasMore = progress.hasMore || this.extractionPageIsScrollable(hydratedExtraction);
      this.sessionCoordinator.updateSessionProgress(
        progress.extractedCount,
        progress.appliedCount,
        progress.cacheHitCount,
        progress.requestedCount,
        progress.requestedChars
      );
      this.sessionCoordinator.updateSessionStatus(finalHasMore ? 'partially_translated' : 'translated');
      onState(this.buildTranslatedState(
        effectiveSettings,
        progress.lastExtraction,
        progress.appliedCount,
        progress.appliedChars,
        sourceLanguage,
        finalHasMore,
        progress.extractedCount > 0 ? progress.extractedCount : hydratedExtraction.items.length
      ));
      await this.startDynamicTranslationPolling(controller, effectiveSettings, onState, taskGeneration);
    } catch (error) {
      if (!this.isStale(taskGeneration)) {
        hilog.error(
          WEBPAGE_TRANSLATION_LOG_DOMAIN,
          WEBPAGE_TRANSLATION_LOG_TAG,
          'translateCurrentPage failed error=%{public}s',
          this.stringifyError(error)
        );
        onState(this.buildErrorState(settings, this.buildErrorMessage(error)));
      }
    }
  }

  private async restoreOriginals(
    controller: webview.WebviewController | undefined,
    state: WebpageTranslationPanelState
  ): Promise<WebpageTranslationPanelState> {
    this.cancelCurrentTask();
    if (controller === undefined) {
      return {
        visible: true,
        status: 'error',
        displayMode: state.displayMode,
        title: '恢复失败',
        message: '当前页面还没有可用的网页控制器。',
        providerTemplateId: state.providerTemplateId,
        providerDisplayName: state.providerDisplayName,
        sourceLanguage: state.sourceLanguage,
        targetLanguage: state.targetLanguage,
        translatedCount: state.translatedCount,
        canTranslate: true,
        canRestore: state.canRestore,
        canCancel: false
      };
    }
    const restoredCount = await this.runtimeBridge.restoreOriginals(controller);
    if (restoredCount > 0) {
      this.sessionCoordinator.setDisplayMode('original');
    }
    return {
      visible: true,
      status: 'restored',
      displayMode: restoredCount > 0 ? 'original' : state.displayMode,
      title: '已显示原文',
      message: restoredCount > 0 ? `已恢复 ${restoredCount} 段原文` : '没有可恢复的翻译内容',
      providerTemplateId: state.providerTemplateId,
      providerDisplayName: state.providerDisplayName,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
      translatedCount: 0,
      canTranslate: true,
      canRestore: restoredCount > 0,
      canCancel: false
    };
  }

  private async showBilingualTranslations(
    controller: webview.WebviewController | undefined,
    state: WebpageTranslationPanelState
  ): Promise<WebpageTranslationPanelState> {
    return await this.showDisplayMode(controller, state, 'bilingual');
  }

  private async showTranslationOnly(
    controller: webview.WebviewController | undefined,
    state: WebpageTranslationPanelState
  ): Promise<WebpageTranslationPanelState> {
    return await this.showDisplayMode(controller, state, 'translation_only');
  }

  private async showDisplayMode(
    controller: webview.WebviewController | undefined,
    state: WebpageTranslationPanelState,
    displayMode: 'bilingual' | 'translation_only'
  ): Promise<WebpageTranslationPanelState> {
    if (controller === undefined) {
      return {
        visible: true,
        status: 'error',
        displayMode: state.displayMode,
        title: '切换显示失败',
        message: '当前页面还没有可用的网页控制器。',
        providerTemplateId: state.providerTemplateId,
        providerDisplayName: state.providerDisplayName,
        sourceLanguage: state.sourceLanguage,
        targetLanguage: state.targetLanguage,
        translatedCount: state.translatedCount,
        canTranslate: true,
        canRestore: state.canRestore,
        canCancel: false
      };
    }
    this.sessionCoordinator.setDisplayMode(displayMode);
    const shownCount = displayMode === 'bilingual'
      ? await this.runtimeBridge.showBilingualTranslations(controller)
      : await this.runtimeBridge.showTranslationOnly(controller);
    return {
      visible: true,
      status: shownCount > 0 ? 'translated' : state.status,
      displayMode: shownCount > 0 ? displayMode : state.displayMode,
      title: shownCount > 0 ? this.buildDisplayModeTitle(displayMode) : '没有可切换的译文',
      message: shownCount > 0
        ? this.buildDisplayModeMessage(displayMode, shownCount)
        : '当前页面没有可恢复的缓存译文',
      providerTemplateId: state.providerTemplateId,
      providerDisplayName: state.providerDisplayName,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
      translatedCount: shownCount > 0 ? shownCount : state.translatedCount,
      canTranslate: true,
      canRestore: shownCount > 0 || state.canRestore,
      canCancel: false
    };
  }

  private async updateTargetLanguage(
    state: WebpageTranslationPanelState,
    languageCode: string
  ): Promise<WebpageTranslationPanelState> {
    const nextLanguage = languageCode.trim();
    if (nextLanguage.length === 0) {
      return state;
    }
    const currentSettings = this.settingsRepository.getSettings();
    const nextPreferences: TranslationSettingsPreferences = {
      enabled: currentSettings.preferences.enabled,
      offerToTranslate: currentSettings.preferences.offerToTranslate,
      allowInPrivateTabs: currentSettings.preferences.allowInPrivateTabs,
      preferredTargetLanguage: nextLanguage,
      firstCloudDisclosureAcceptedAt: currentSettings.preferences.firstCloudDisclosureAcceptedAt
    };
    const result: TranslationSettingsMutationResult = await this.translationSettingsCoordinator.updatePreferences(
      nextPreferences,
      this.buildTranslationSettingsBoundary()
    );
    if (!result.allowed) {
      return state;
    }
    const nextSettings = result.settings;
    return {
      visible: state.visible,
      status: state.status,
      displayMode: state.displayMode,
      title: state.title,
      message: this.buildTargetLanguageUpdatedMessage(state, nextLanguage),
      providerTemplateId: this.resolvePanelProviderTemplateId(nextSettings),
      providerDisplayName: this.resolvePanelProviderDisplayName(nextSettings),
      sourceLanguage: state.sourceLanguage,
      targetLanguage: nextSettings.preferences.preferredTargetLanguage,
      translatedCount: state.translatedCount,
      canTranslate: nextSettings.preferences.enabled,
      canRestore: state.canRestore,
      canCancel: state.canCancel
    };
  }

  private async clearPageRuntime(
    controller: webview.WebviewController | undefined,
    shouldCancelTask: boolean = true
  ): Promise<void> {
    if (shouldCancelTask) {
      this.cancelCurrentTask();
    }
    if (controller === undefined) {
      return;
    }
    try {
      await this.runtimeBridge.stopDynamicTracking(controller);
      await this.runtimeBridge.clear(controller);
    } catch (_error) {
    }
  }

  private buildTranslationSettingsBoundary(): TranslationSettingsBoundary {
    const context = this.applicationShell.readContext();
    return new TranslationSettingsBoundary(
      context.privateMode ? 'session_ephemeral' : 'profile_persistent',
      context.privateMode ? 'private' : 'regular'
    );
  }

  private pauseDynamicTranslation(): void {
    this.lifecycleCoordinator.pauseDynamicTranslation();
  }

  handlePageBeginForRuntimeTab(
    tabId: string,
    activeTabId: string,
    url: string
  ): void {
    this.handlePageBeginForTab({
      tabId: tabId,
      activeTabId: activeTabId,
      url: url,
      controller: this.runtimeLifecyclePort.resolveController(tabId)
    });
  }

  handlePageEndForRuntimeTab(tabId: string, activeTabId: string, url: string): void {
    this.handlePageEndForTab({
      tabId: tabId,
      activeTabId: activeTabId,
      url: url
    });
  }

  handleRefreshOrBackForwardForRuntimeTab(
    tabId: string,
    activeTabId: string,
    url: string
  ): void {
    this.handleRefreshOrBackForwardForTab({
      tabId: tabId,
      activeTabId: activeTabId,
      url: url,
      controller: this.runtimeLifecyclePort.resolveController(tabId)
    });
  }

  handleSpaRouteChangedForRuntimeTab(
    tabId: string,
    activeTabId: string,
    url: string
  ): void {
    this.handleSpaRouteChangedForTab({
      tabId: tabId,
      activeTabId: activeTabId,
      url: url,
      controller: this.runtimeLifecyclePort.resolveController(tabId)
    });
  }

  handleActiveTabChangedFromShell(
    previousTabId: string,
    activeTabId: string,
    activeUrl: string
  ): void {
    this.handleActiveTabChanged({
      previousTabId: previousTabId,
      activeTabId: activeTabId,
      activeUrl: activeUrl
    });
  }

  handleRuntimeDetachedForRuntimeTab(tabId: string, activeTabId: string): void {
    this.handleRuntimeDetachedForTab({
      tabId: tabId,
      activeTabId: activeTabId,
      url: ''
    });
  }

  handleTabDestroyedForRuntimeTab(
    tabId: string,
    activeTabId: string,
    wasActive: boolean
  ): void {
    this.handleTabDestroyedForTab({
      tabId: tabId,
      activeTabId: activeTabId,
      url: '',
      wasActive: wasActive
    });
  }

  private handlePageBeginForTab(input: WebpageTranslationTabLifecycleInput): void {
    if (!this.shouldHandleTabLifecycle(input)) {
      return;
    }
    this.resetApplicationSurface();
    this.handlePageBegin(input.url);
    void this.clearPageRuntime(input.controller, false);
  }

  private handlePageEndForTab(input: WebpageTranslationTabLifecycleInput): void {
    if (!this.shouldHandleTabLifecycle(input)) {
      return;
    }
    this.handlePageEnd(input.url);
  }

  private handleRefreshOrBackForwardForTab(input: WebpageTranslationTabLifecycleInput): void {
    if (!this.shouldHandleTabLifecycle(input)) {
      return;
    }
    this.resetApplicationSurface();
    this.handleRefreshOrBackForward(input.url);
    void this.clearPageRuntime(input.controller, false);
  }

  private handleSpaRouteChangedForTab(input: WebpageTranslationTabLifecycleInput): void {
    if (!this.shouldHandleTabLifecycle(input)) {
      return;
    }
    this.resetApplicationSurface();
    this.handleSpaRouteChanged(input.url);
    void this.clearPageRuntime(input.controller, false);
  }

  private handleActiveTabChanged(input: WebpageTranslationActiveTabChangedInput): void {
    const previousTabId = input.previousTabId.trim();
    const activeTabId = input.activeTabId.trim();
    if (previousTabId === activeTabId) {
      return;
    }
    if (previousTabId.length > 0) {
      this.lifecycleCoordinator.handleTabDeactivated();
      this.sessionCoordinator.logSessionEvent(
        'lifecycle_event',
        0,
        0,
        0,
        0,
        `tab_deactivated:${previousTabId}`
      );
    }
    if (activeTabId.length > 0) {
      this.lifecycleCoordinator.handleTabActivated(input.activeUrl);
      this.sessionCoordinator.logSessionEvent(
        'lifecycle_event',
        0,
        0,
        0,
        0,
        `tab_activated:${activeTabId}:${input.activeUrl}`
      );
    }
    this.resetApplicationSurface();
    this.cancelCurrentTask();
  }

  private handleRuntimeDetachedForTab(input: WebpageTranslationTabLifecycleInput): void {
    if (!this.shouldHandleTabLifecycle(input)) {
      return;
    }
    this.resetApplicationSurface();
    this.handleRuntimeDetached();
  }

  handleActiveRuntimeDetached(): void {
    this.resetApplicationSurface();
    this.handleRuntimeDetached();
  }

  private handleTabDestroyedForTab(input: WebpageTranslationTabLifecycleInput): void {
    if (!this.shouldHandleTabLifecycle(input)) {
      return;
    }
    this.resetApplicationSurface();
    this.handleTabDestroyed();
  }

  private handlePageBegin(url: string): void {
    this.lifecycleCoordinator.handlePageBegin(url);
    this.sessionCoordinator.logSessionEvent('lifecycle_event', 0, 0, 0, 0, `page_begin:${url}`);
    this.cancelCurrentTask();
  }

  private handlePageEnd(url: string): void {
    this.lifecycleCoordinator.handlePageEnd(url);
    this.sessionCoordinator.logSessionEvent('lifecycle_event', 0, 0, 0, 0, `page_end:${url}`);
  }

  private handleRefreshOrBackForward(url: string): void {
    this.lifecycleCoordinator.handleRefreshOrBackForward(url);
    this.sessionCoordinator.logSessionEvent('lifecycle_event', 0, 0, 0, 0, `refresh_or_history:${url}`);
    this.cancelCurrentTask();
  }

  private handleSpaRouteChanged(url: string): void {
    this.lifecycleCoordinator.handleSpaRouteChanged(url);
    this.sessionCoordinator.logSessionEvent('lifecycle_event', 0, 0, 0, 0, `spa_route_changed:${url}`);
    this.cancelCurrentTask();
  }

  private handleRuntimeDetached(): void {
    this.lifecycleCoordinator.handleRuntimeDetached();
    this.sessionCoordinator.logSessionEvent('lifecycle_event', 0, 0, 0, 0, 'runtime_detached');
    this.cancelCurrentTask();
  }

  private handleTabDestroyed(): void {
    this.lifecycleCoordinator.handleTabDestroyed();
    this.sessionCoordinator.logSessionEvent('lifecycle_event', 0, 0, 0, 0, 'tab_destroyed');
    this.cancelCurrentTask();
  }

  private async resumeDynamicTranslationForCurrentPage(
    controller: webview.WebviewController | undefined,
    settings: TranslationSettings,
    state: WebpageTranslationPanelState,
    onState: (state: WebpageTranslationPanelState) => void
  ): Promise<void> {
    if (controller === undefined || !this.shouldResumeDynamicTranslationForState(state)) {
      return;
    }
    this.sessionCoordinator.setDisplayMode(state.displayMode);
    const activeSession = this.sessionCoordinator.getActiveSession();
    if (activeSession === undefined) {
      return;
    }
    const taskGeneration = activeSession.generation;
    await this.startDynamicTranslationPolling(controller, settings, onState, taskGeneration);
  }

  private nextGeneration(): number {
    return this.sessionCoordinator.nextTaskGeneration();
  }

  private shouldHandleTabLifecycle(input: WebpageTranslationTabLifecycleInput): boolean {
    return input.tabId.trim().length > 0 && (input.tabId === input.activeTabId || input.wasActive === true);
  }

  private nextLoadingRunId(): number {
    return this.sessionCoordinator.nextLoadingRunId();
  }

  private async markItemsLoading(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    loadingRunId: number
  ): Promise<void> {
    try {
      await this.runtimeBridge.markLoading(controller, items, loadingRunId);
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'mark translation loading failed items=%{public}d error=%{public}s',
        items.length,
        this.stringifyError(error)
      );
    }
  }

  private async clearItemsLoading(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    loadingRunId?: number
  ): Promise<void> {
    try {
      await this.runtimeBridge.clearLoading(controller, items, loadingRunId);
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'clear translation loading failed items=%{public}d error=%{public}s',
        items.length,
        this.stringifyError(error)
      );
    }
  }

  private async markItemsFailed(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    message: string,
    loadingRunId?: number
  ): Promise<void> {
    try {
      await this.runtimeBridge.markFailed(controller, items, message, loadingRunId);
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'mark translation failed failed items=%{public}d error=%{public}s',
        items.length,
        this.stringifyError(error)
      );
    }
  }

  private async clearTransientTranslationStates(controller: webview.WebviewController): Promise<void> {
    try {
      await this.runtimeBridge.clearTransientStates(controller);
    } catch (error) {
      hilog.warn(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'clear transient translation states failed error=%{public}s',
        this.stringifyError(error)
      );
    }
  }

  private buildTargetLanguageUpdatedMessage(state: WebpageTranslationPanelState, languageCode: string): string {
    if (state.status === 'idle' || state.status === 'restored' || state.status === 'error') {
      return '目标语言已更新';
    }
    return state.message;
  }

  private buildSettingsWithTargetLanguage(settings: TranslationSettings, targetLanguage: string): TranslationSettings {
    const normalizedTargetLanguage = targetLanguage.trim();
    if (normalizedTargetLanguage.length === 0 ||
      normalizedTargetLanguage === settings.preferences.preferredTargetLanguage) {
      return settings;
    }
    const nextPreferences: TranslationSettingsPreferences = {
      enabled: settings.preferences.enabled,
      offerToTranslate: settings.preferences.offerToTranslate,
      allowInPrivateTabs: settings.preferences.allowInPrivateTabs,
      preferredTargetLanguage: normalizedTargetLanguage,
      firstCloudDisclosureAcceptedAt: settings.preferences.firstCloudDisclosureAcceptedAt
    };
    return {
      preferences: nextPreferences,
      activeProviderId: settings.activeProviderId,
      providers: settings.providers,
      rules: settings.rules,
      updatedAt: settings.updatedAt
    };
  }

  private isStale(taskGeneration: number): boolean {
    return this.sessionCoordinator.isStale(taskGeneration);
  }

  private buildReadyMessage(settings: TranslationSettings): string {
    if (!settings.preferences.enabled) {
      return '网页翻译未开启，请先在设置中启用。';
    }
    const provider = this.resolveActiveProvider(settings);
    if (provider === undefined || provider.status !== 'configured') {
      return this.buildProviderUnavailableMessage(provider);
    }
    return `页面文字将发送到 ${provider.displayName} 翻译。`;
  }

  private buildTranslatingMessage(
    itemCount: number,
    charCount: number,
    provider: TranslationProviderConfig | undefined
  ): string {
    if (provider === undefined || provider.status !== 'configured') {
      return `已读取 ${itemCount} 段、约 ${charCount} 字，正在检查翻译服务`;
    }
    return `已读取 ${itemCount} 段、约 ${charCount} 字，正在请求 ${provider.displayName}`;
  }

  private isProviderReadyForTranslation(provider: TranslationProviderConfig | undefined): boolean {
    return provider !== undefined &&
      provider.status === 'configured';
  }

  private buildProviderUnavailableState(
    settings: TranslationSettings,
    provider: TranslationProviderConfig | undefined
  ): WebpageTranslationPanelState {
    return this.buildErrorState(settings, this.buildProviderUnavailableMessage(provider), '', '未配置翻译 API');
  }

  private buildProviderUnavailableMessage(provider: TranslationProviderConfig | undefined): string {
    if (provider === undefined) {
      return '请先到网页翻译设置中添加并启用翻译 API。';
    }
    if (provider.status !== 'configured') {
      return '当前翻译 API 未配置完成，请到网页翻译设置中补全配置。';
    }
    return '请先到网页翻译设置中添加并启用翻译 API。';
  }

  private buildTranslatedState(
    settings: TranslationSettings,
    extraction: WebpageTranslationExtractionResult,
    appliedCount: number,
    appliedChars?: number,
    sourceLanguage?: string,
    hasMore: boolean = false,
    extractedCountOverride?: number
  ): WebpageTranslationPanelState {
    const appliedCharsText = appliedChars !== undefined && appliedChars > 0 ? `、约 ${appliedChars} 个原文字符` : '';
    const extractedCount = extractedCountOverride !== undefined && extractedCountOverride > 0
      ? extractedCountOverride
      : extraction.items.length;
    return {
      visible: true,
      status: hasMore ? 'partially_translated' : 'translated',
      displayMode: this.resolvePanelDisplayModeForAppliedCount(appliedCount),
      title: hasMore ? '已翻译部分内容' : '已翻译当前网页',
      message: appliedCount > 0
        ? this.buildTranslatedMessage(extractedCount, appliedCount, appliedCharsText, hasMore)
        : '页面文字已变化，未能安全回写译文',
      providerTemplateId: this.resolvePanelProviderTemplateId(settings),
      providerDisplayName: this.resolvePanelProviderDisplayName(settings),
      sourceLanguage: sourceLanguage ?? extraction.lang,
      targetLanguage: settings.preferences.preferredTargetLanguage,
      translatedCount: appliedCount,
      canTranslate: true,
      canRestore: appliedCount > 0,
      canCancel: false
    };
  }

  private buildTranslatingProgressState(
    settings: TranslationSettings,
    totalCount: number,
    progress: WebpageTranslationProgress,
    totalChars: number,
    sourceLanguage: string
  ): WebpageTranslationPanelState {
    return {
      visible: true,
      status: 'translating',
      displayMode: this.resolvePanelDisplayModeForAppliedCount(progress.appliedCount),
      title: '正在翻译',
      message: `已尝试约 ${progress.attemptedChars}/${totalChars} 个原文字符，已应用约 ${progress.appliedChars} 个原文字符、${progress.appliedCount}/${totalCount} 段`,
      providerTemplateId: this.resolvePanelProviderTemplateId(settings),
      providerDisplayName: this.resolvePanelProviderDisplayName(settings),
      sourceLanguage: sourceLanguage,
      targetLanguage: settings.preferences.preferredTargetLanguage,
      translatedCount: progress.appliedCount,
      canTranslate: false,
      canRestore: progress.appliedCount > 0,
      canCancel: true
    };
  }

  private buildTranslatedMessage(
    extractedCount: number,
    appliedCount: number,
    appliedCharsText: string,
    hasMore: boolean
  ): string {
    if (hasMore) {
      return `已应用 ${appliedCount}/${extractedCount} 段${appliedCharsText}译文，可继续翻译更多内容`;
    }
    return `已处理 ${extractedCount} 段，已应用 ${appliedCount} 段${appliedCharsText}译文`;
  }

  private buildDisplayModeTitle(displayMode: 'bilingual' | 'translation_only'): string {
    return displayMode === 'bilingual' ? '已显示双语对照' : '已仅显示译文';
  }

  private buildDisplayModeMessage(displayMode: 'bilingual' | 'translation_only', shownCount: number): string {
    return displayMode === 'bilingual'
      ? `已显示 ${shownCount} 段双语对照`
      : `已仅显示 ${shownCount} 段译文`;
  }

  private resolvePanelDisplayModeForAppliedCount(appliedCount: number): WebpageTranslationDisplayMode {
    if (appliedCount <= 0) {
      return 'none';
    }
    const displayMode = this.sessionCoordinator.getAppliedDisplayMode();
    return displayMode === 'translation_only' ? 'translation_only' : 'bilingual';
  }

  private canReopenExistingPanelState(state: WebpageTranslationPanelState): boolean {
    if (state.canCancel) {
      return false;
    }
    if (state.status === 'translated' ||
      state.status === 'partially_translated' ||
      state.status === 'restored') {
      return state.translatedCount > 0 ||
        state.canRestore;
    }
    return state.status === 'error' &&
      (state.canRestore || state.translatedCount > 0);
  }

  private shouldResumeDynamicTranslationForState(state: WebpageTranslationPanelState): boolean {
    return (state.status === 'translated' || state.status === 'partially_translated') &&
      state.translatedCount > 0;
  }

  private async startDynamicTranslationPolling(
    controller: webview.WebviewController,
    settings: TranslationSettings,
    onState: (state: WebpageTranslationPanelState) => void,
    taskGeneration: number
  ): Promise<void> {
    await this.lifecycleCoordinator.startDynamicTranslationPolling(
      controller,
      this.runtimeBridge,
      () => {
        return this.pollDynamicTranslation(controller, settings, onState, taskGeneration);
      }
    );
  }

  private stopDynamicTranslationPolling(): void {
    this.lifecycleCoordinator.stopDynamicTranslationPolling();
  }

  private async pollDynamicTranslation(
    controller: webview.WebviewController,
    settings: TranslationSettings,
    onState: (state: WebpageTranslationPanelState) => void,
    taskGeneration: number
  ): Promise<void> {
    if (this.isStale(taskGeneration)) {
      this.stopDynamicTranslationPolling();
      return;
    }
    if (this.lifecycleCoordinator.isDynamicTrackingPaused()) {
      this.lifecycleCoordinator.stopDynamicTranslationPolling();
      return;
    }
    const session = this.sessionCoordinator.getActiveSession(taskGeneration);
    if (session === undefined) {
      this.lifecycleCoordinator.stopDynamicTranslationPolling();
      return;
    }
    try {
      const signalChange = await this.lifecycleCoordinator.readSignalChange(controller, this.runtimeBridge);
      if (signalChange.routeChanged) {
        await this.translateCurrentPage(controller, settings, onState);
        return;
      }
      if (!signalChange.pageChanged) {
        return;
      }
      const extraction = await this.runtimeBridge.extractPendingBatch(
        controller,
        CLOUD_TRANSLATION_DYNAMIC_PENDING_NODE_LIMIT,
        CLOUD_TRANSLATION_DYNAMIC_PENDING_CHAR_LIMIT
      );
      if (this.isStale(taskGeneration) || extraction.items.length === 0) {
        return;
      }
      const sourceLanguage = session.sourceLanguage;
      const sourcePolicyDecision = this.policyService.resolveSourceLanguageDecision({
        settings: session.settings,
        sourceLanguage: sourceLanguage,
        currentUrl: extraction.url
      });
      if (!sourcePolicyDecision.allowed) {
        return;
      }
      const provider = session.provider;
      const effectiveSettings = session.settings;
      await this.runtimeBridge.configureCache(controller, session.runtimeCacheNamespace);
      const cacheContext = session.cacheContext;
      const hydratedItems = await this.cacheCoordinator.hydrateItems(
        this.prioritizeItemsForTranslation(extraction.items).slice(0, CLOUD_TRANSLATION_DYNAMIC_PENDING_NODE_LIMIT),
        cacheContext
      );
      this.sessionCoordinator.addSessionProgress(hydratedItems.length, 0, 0, 0, 0);
      const cachePipeline = this.cacheCoordinator.buildCachePipeline(hydratedItems);
      this.sessionCoordinator.logSessionEvent(
        'cache_split',
        cachePipeline.stats.sourceCount,
        cachePipeline.stats.sourceChars,
        cachePipeline.stats.cacheHitCount,
        cachePipeline.stats.missedCount,
        'dynamic_poll'
      );
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'dynamic poll cache pipeline items=%{public}d cacheHit=%{public}d missed=%{public}d cacheHitChars=%{public}d missedChars=%{public}d source=%{public}s target=%{public}s displayMode=%{public}s',
        cachePipeline.stats.sourceCount,
        cachePipeline.stats.cacheHitCount,
        cachePipeline.stats.missedCount,
        cachePipeline.stats.cacheHitChars,
        cachePipeline.stats.missedChars,
        sourceLanguage,
        session.targetLanguage,
        session.displayMode
      );
      if (cachePipeline.cachedApplyItems.length > 0) {
        const cachedApplyResult = await this.runtimeBridge.applyTranslations(controller, cachePipeline.cachedApplyItems);
        if (!this.isStale(taskGeneration) && cachedApplyResult.appliedCount > 0) {
          this.sessionCoordinator.addSessionProgress(
            0,
            cachedApplyResult.appliedCount,
            cachePipeline.stats.cacheHitCount,
            0,
            0
          );
          this.sessionCoordinator.logSessionEvent(
            'apply_done',
            cachedApplyResult.appliedCount,
            cachePipeline.stats.cacheHitChars,
            cachePipeline.stats.cacheHitCount,
            0,
            'dynamic_cache'
          );
          const updatedSession = this.sessionCoordinator.getActiveSession(taskGeneration);
          onState(this.buildTranslatedState(
            effectiveSettings,
            extraction,
            updatedSession?.appliedCount ?? cachedApplyResult.appliedCount,
            undefined,
            sourceLanguage
          ));
        }
      }
      const uncachedItems = cachePipeline.missedSourceItems;
      if (uncachedItems.length === 0) {
        this.sessionCoordinator.updateSessionStatus('translated');
        return;
      }
      const loadingRunId = this.nextLoadingRunId();
      await this.markItemsLoading(controller, uncachedItems, loadingRunId);
      let translations: WebpageTranslationApplyItem[] = [];
      this.sessionCoordinator.addSessionProgress(
        0,
        0,
        0,
        uncachedItems.length,
        this.countItemChars(uncachedItems)
      );
      try {
        translations = await this.requestCoordinator.translateBatch(
          provider,
          uncachedItems,
          sourceLanguage,
          effectiveSettings.preferences.preferredTargetLanguage
        );
      } catch (error) {
        this.sessionCoordinator.logSessionEvent(
          'provider_request_failed',
          uncachedItems.length,
          this.countItemChars(uncachedItems),
          0,
          uncachedItems.length,
          this.stringifyError(error)
        );
        await this.markItemsFailed(controller, uncachedItems, this.buildErrorMessage(error as Error), loadingRunId);
        return;
      }
      if (this.isStale(taskGeneration)) {
        await this.clearItemsLoading(controller, uncachedItems, loadingRunId);
        return;
      }
      await this.cacheCoordinator.storeTranslations(uncachedItems, translations, cacheContext);
      let applyResult: WebpageTranslationApplyResult;
      try {
        applyResult = await this.runtimeBridge.applyTranslations(controller, translations);
      } finally {
        await this.clearItemsLoading(controller, uncachedItems, loadingRunId);
      }
      if (this.isStale(taskGeneration) || (applyResult.appliedCount <= 0 && applyResult.unchangedTextCount <= 0)) {
        return;
      }
      this.sessionCoordinator.addSessionProgress(0, applyResult.appliedCount, 0, 0, 0);
      this.sessionCoordinator.logSessionEvent(
        'apply_done',
        applyResult.appliedCount,
        this.countAppliedChars(uncachedItems, applyResult.appliedIds, applyResult.appliedCount),
        0,
        uncachedItems.length,
        'dynamic_provider'
      );
      this.sessionCoordinator.updateSessionStatus('translated');
      const updatedSession = this.sessionCoordinator.getActiveSession(taskGeneration);
      onState(this.buildTranslatedState(
        effectiveSettings,
        extraction,
        updatedSession?.appliedCount ?? applyResult.appliedCount,
        undefined,
        sourceLanguage
      ));
    } catch (_error) {
    }
  }

  private async translateAndApplyVisibleBatches(
    controller: webview.WebviewController,
    provider: TranslationProviderConfig | undefined,
    extraction: WebpageTranslationExtractionResult,
    sourceLanguage: string,
    settings: TranslationSettings,
    cacheContext: WebpageTranslationCacheContext,
    onState: (state: WebpageTranslationPanelState) => void,
    taskGeneration: number
  ): Promise<WebpageTranslationProgress> {
    const charBudget = this.requestCoordinator.resolveBatchCharBudget(provider);
    const itemGuard = this.requestCoordinator.resolveBatchItemGuard(provider);
    const prioritizedItems = this.prioritizeItemsForTranslation(extraction.items);
    const cachePipeline = this.cacheCoordinator.buildCachePipeline(prioritizedItems);
    this.sessionCoordinator.logSessionEvent(
      'cache_split',
      cachePipeline.stats.sourceCount,
      cachePipeline.stats.sourceChars,
      cachePipeline.stats.cacheHitCount,
      cachePipeline.stats.missedCount,
      'visible_batch'
    );
    const cachedSummary = await this.applyCachedTranslations(
      controller,
      cachePipeline,
      settings,
      sourceLanguage,
      onState,
      taskGeneration
    );
    const uncachedPrioritizedItems = cachePipeline.missedSourceItems;
    const batches = this.requestCoordinator.buildBudgetBatches(uncachedPrioritizedItems, charBudget, itemGuard);
    const totalChars = this.countItemChars(extraction.items);
    let appliedTotal = cachedSummary.appliedCount;
    let appliedChars = cachedSummary.appliedChars;
    let attemptedCount = prioritizedItems.length;
    let attemptedChars = this.countItemChars(prioritizedItems);
    let requestedCount = 0;
    let requestedChars = 0;
    let cacheHitCount = cachedSummary.cacheHitCount;
    if (this.isStale(taskGeneration) || batches.length === 0) {
      return {
        appliedCount: appliedTotal,
        appliedChars: appliedChars,
        attemptedCount: attemptedCount,
        attemptedChars: attemptedChars,
        requestedCount: requestedCount,
        requestedChars: requestedChars,
        cacheHitCount: cacheHitCount,
        stoppedAfterProviderFailure: false,
        hasMore: !this.isStale(taskGeneration) && this.extractionHasMoreCandidates(extraction)
      };
    }
    for (let index = 0; index < batches.length; index += 1) {
      if (this.isStale(taskGeneration)) {
        return {
          appliedCount: appliedTotal,
          appliedChars: appliedChars,
          attemptedCount: attemptedCount,
          attemptedChars: attemptedChars,
          requestedCount: requestedCount,
          requestedChars: requestedChars,
          cacheHitCount: cacheHitCount,
          stoppedAfterProviderFailure: false,
          hasMore: index < batches.length - 1
        };
      }
      if (index > 0) {
        await this.requestCoordinator.delayBetweenTranslationBatches(provider);
      }
      if (this.isStale(taskGeneration)) {
        return {
          appliedCount: appliedTotal,
          appliedChars: appliedChars,
          attemptedCount: attemptedCount,
          attemptedChars: attemptedChars,
          requestedCount: requestedCount,
          requestedChars: requestedChars,
          cacheHitCount: cacheHitCount,
          stoppedAfterProviderFailure: false,
          hasMore: index < batches.length - 1
        };
      }
      const batch = batches[index];
      requestedCount += batch.items.length;
      requestedChars += batch.charCount;
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'progressive translation batch start index=%{public}d batches=%{public}d items=%{public}d chars=%{public}d cached=%{public}d requestItems=%{public}d nearViewport=%{public}d budget=%{public}d provider=%{public}s source=%{public}s',
        index + 1,
        batches.length,
        batch.items.length,
        batch.charCount,
        0,
        batch.items.length,
        this.countNearViewportItems(batch.items),
        charBudget,
        provider?.templateId ?? 'none',
        this.buildSourceBatchSample(batch.items)
      );
      let translations: WebpageTranslationApplyItem[] = [];
      const loadingRunId = this.nextLoadingRunId();
      await this.markItemsLoading(controller, batch.items, loadingRunId);
      try {
        translations = await this.requestCoordinator.translateBatch(
          provider,
          batch.items,
          sourceLanguage,
          settings.preferences.preferredTargetLanguage
        );
      } catch (error) {
        this.sessionCoordinator.logSessionEvent(
          'provider_request_failed',
          batch.items.length,
          batch.charCount,
          cacheHitCount,
          batch.items.length,
          this.stringifyError(error)
        );
        if (appliedTotal > 0 || cacheHitCount > 0) {
          hilog.warn(
            WEBPAGE_TRANSLATION_LOG_DOMAIN,
            WEBPAGE_TRANSLATION_LOG_TAG,
            'progressive translation provider failed after cache applied index=%{public}d cached=%{public}d applied=%{public}d error=%{public}s',
            index + 1,
            cacheHitCount,
            appliedTotal,
            this.stringifyError(error)
          );
          await this.markItemsFailed(controller, batch.items, this.buildErrorMessage(error as Error), loadingRunId);
          return {
            appliedCount: appliedTotal,
            appliedChars: appliedChars,
            attemptedCount: attemptedCount,
            attemptedChars: attemptedChars,
            requestedCount: requestedCount,
            requestedChars: requestedChars,
            cacheHitCount: cacheHitCount,
            stoppedAfterProviderFailure: true,
            hasMore: true
          };
        }
        await this.markItemsFailed(controller, batch.items, this.buildErrorMessage(error as Error), loadingRunId);
        throw this.normalizeThrowable(error);
      }
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'progressive translation batch translated index=%{public}d applyItems=%{public}d translation=%{public}s',
        index + 1,
        translations.length,
        this.buildTranslationBatchSample(translations)
      );
      await this.cacheCoordinator.storeTranslations(batch.items, translations, cacheContext);
      if (this.isStale(taskGeneration)) {
        await this.clearItemsLoading(controller, batch.items, loadingRunId);
        return {
          appliedCount: appliedTotal,
          appliedChars: appliedChars,
          attemptedCount: attemptedCount,
          attemptedChars: attemptedChars,
          requestedCount: requestedCount,
          requestedChars: requestedChars,
          cacheHitCount: cacheHitCount,
          stoppedAfterProviderFailure: false,
          hasMore: index < batches.length - 1
        };
      }
      let applyResult: WebpageTranslationApplyResult;
      try {
        applyResult = await this.runtimeBridge.applyTranslations(controller, translations);
      } finally {
        await this.clearItemsLoading(controller, batch.items, loadingRunId);
      }
      appliedTotal += applyResult.appliedCount;
      appliedChars += this.countAppliedChars(batch.items, applyResult.appliedIds, applyResult.appliedCount);
      this.sessionCoordinator.logSessionEvent(
        'apply_done',
        applyResult.appliedCount,
        this.countAppliedChars(batch.items, applyResult.appliedIds, applyResult.appliedCount),
        0,
        batch.items.length,
        'visible_provider'
      );
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'progressive translation batch applied index=%{public}d sourceItems=%{public}d cached=%{public}d requestItems=%{public}d applyItems=%{public}d requestedApply=%{public}d applied=%{public}d appliedChars=%{public}d totalApplied=%{public}d attempted=%{public}d/%{public}d attemptedChars=%{public}d missingNode=%{public}d invalidText=%{public}d changedText=%{public}d unchangedText=%{public}d',
        index + 1,
        batch.items.length,
        0,
        batch.items.length,
        translations.length,
        applyResult.requestedCount,
        applyResult.appliedCount,
        appliedChars,
        appliedTotal,
        attemptedCount,
        prioritizedItems.length,
        attemptedChars,
        applyResult.missingNodeCount,
        applyResult.invalidTextCount,
        applyResult.changedTextCount,
        applyResult.unchangedTextCount
      );
      if (this.isStale(taskGeneration)) {
        await this.clearItemsLoading(controller, batch.items, loadingRunId);
        return {
          appliedCount: appliedTotal,
          appliedChars: appliedChars,
          attemptedCount: attemptedCount,
          attemptedChars: attemptedChars,
          requestedCount: requestedCount,
          requestedChars: requestedChars,
          cacheHitCount: cacheHitCount,
          stoppedAfterProviderFailure: false,
          hasMore: index < batches.length - 1
        };
      }
      onState(this.buildTranslatingProgressState(
        settings,
        prioritizedItems.length,
        {
          appliedCount: appliedTotal,
          appliedChars: appliedChars,
          attemptedCount: attemptedCount,
          attemptedChars: attemptedChars,
          requestedCount: requestedCount,
          requestedChars: requestedChars,
          cacheHitCount: cacheHitCount,
          stoppedAfterProviderFailure: false,
          hasMore: index < batches.length - 1
        },
        totalChars,
        sourceLanguage
      ));
    }
    return {
      appliedCount: appliedTotal,
      appliedChars: appliedChars,
      attemptedCount: attemptedCount,
      attemptedChars: attemptedChars,
      requestedCount: requestedCount,
      requestedChars: requestedChars,
      cacheHitCount: cacheHitCount,
      stoppedAfterProviderFailure: false,
      hasMore: appliedTotal < prioritizedItems.length ||
        uncachedPrioritizedItems.length > requestedCount ||
        this.extractionHasMoreCandidates(extraction)
    };
  }

  private async translateAndApplyPageQueues(
    controller: webview.WebviewController,
    provider: TranslationProviderConfig | undefined,
    initialExtraction: WebpageTranslationExtractionResult,
    sourceLanguage: string,
    settings: TranslationSettings,
    cacheContext: WebpageTranslationCacheContext,
    onState: (state: WebpageTranslationPanelState) => void,
    taskGeneration: number
  ): Promise<WebpageTranslationAggregateProgress> {
    let currentExtraction = initialExtraction;
    let appliedCount = 0;
    let appliedChars = 0;
    let attemptedCount = 0;
    let attemptedChars = 0;
    let requestedCount = 0;
    let requestedChars = 0;
    let cacheHitCount = 0;
    let stoppedAfterProviderFailure = false;
    let extractedCount = 0;
    let extractedChars = 0;
    let hasMore = false;
    const seenExtractionSignatures: Record<string, boolean> = {};

    for (let round = 0; round < CLOUD_TRANSLATION_MAX_QUEUE_ROUNDS; round += 1) {
      if (this.isStale(taskGeneration) || currentExtraction.items.length === 0) {
        break;
      }
      const extractionSignature = this.buildExtractionSignature(currentExtraction);
      if (seenExtractionSignatures[extractionSignature] === true) {
        hilog.warn(
          WEBPAGE_TRANSLATION_LOG_DOMAIN,
          WEBPAGE_TRANSLATION_LOG_TAG,
          'page queue stopped on repeated extraction round=%{public}d items=%{public}d signature=%{public}s',
          round + 1,
          currentExtraction.items.length,
          extractionSignature
        );
        hasMore = false;
        break;
      }
      seenExtractionSignatures[extractionSignature] = true;
      const roundChars = this.countItemChars(currentExtraction.items);
      if (attemptedChars >= CLOUD_TRANSLATION_MAX_TOTAL_CHARS) {
        hasMore = true;
        break;
      }
      extractedCount += currentExtraction.items.length;
      extractedChars += roundChars;
      const roundHasMoreCandidates = this.extractionHasMoreCandidates(currentExtraction);
      const roundPageScrollable = this.extractionPageIsScrollable(currentExtraction);
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'page queue round start round=%{public}d items=%{public}d chars=%{public}d totalAttemptedChars=%{public}d hasMoreCandidates=%{public}s pageScrollable=%{public}s sample=%{public}s',
        round + 1,
        currentExtraction.items.length,
        roundChars,
        attemptedChars,
        roundHasMoreCandidates ? 'true' : 'false',
        roundPageScrollable ? 'true' : 'false',
        this.buildSourceBatchSample(currentExtraction.items)
      );
      let progress: WebpageTranslationProgress;
      try {
        progress = await this.translateAndApplyVisibleBatches(
          controller,
          provider,
          currentExtraction,
          sourceLanguage,
          settings,
          cacheContext,
          onState,
          taskGeneration
        );
      } catch (error) {
        if (appliedCount > 0 || cacheHitCount > 0) {
          hilog.warn(
            WEBPAGE_TRANSLATION_LOG_DOMAIN,
            WEBPAGE_TRANSLATION_LOG_TAG,
            'page queue provider failed after previous cached/applied content round=%{public}d cached=%{public}d applied=%{public}d error=%{public}s',
            round + 1,
            cacheHitCount,
            appliedCount,
            this.stringifyError(error)
          );
          hasMore = true;
          stoppedAfterProviderFailure = true;
          break;
        }
        throw this.normalizeThrowable(error);
      }
      appliedCount += progress.appliedCount;
      appliedChars += progress.appliedChars;
      attemptedCount += progress.attemptedCount;
      attemptedChars += progress.attemptedChars;
      requestedCount += progress.requestedCount;
      requestedChars += progress.requestedChars;
      cacheHitCount += progress.cacheHitCount;
      stoppedAfterProviderFailure = stoppedAfterProviderFailure || progress.stoppedAfterProviderFailure;
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'page queue round done round=%{public}d extracted=%{public}d roundApplied=%{public}d totalApplied=%{public}d cacheHit=%{public}d requested=%{public}d requestedChars=%{public}d attemptedChars=%{public}d hasMore=%{public}s stoppedAfterProviderFailure=%{public}s',
        round + 1,
        currentExtraction.items.length,
        progress.appliedCount,
        appliedCount,
        cacheHitCount,
        requestedCount,
        requestedChars,
        attemptedChars,
        progress.hasMore ? 'true' : 'false',
        progress.stoppedAfterProviderFailure ? 'true' : 'false'
      );
      onState(this.buildTranslatingProgressState(
        settings,
        extractedCount,
        {
          appliedCount: appliedCount,
          appliedChars: appliedChars,
          attemptedCount: attemptedCount,
          attemptedChars: attemptedChars,
          requestedCount: requestedCount,
          requestedChars: requestedChars,
          cacheHitCount: cacheHitCount,
          stoppedAfterProviderFailure: stoppedAfterProviderFailure,
          hasMore: true
        },
        Math.max(extractedChars, attemptedChars),
        sourceLanguage
      ));
      hasMore = progress.hasMore;
      if (this.isStale(taskGeneration)) {
        break;
      }
      if (progress.stoppedAfterProviderFailure) {
        hasMore = true;
        break;
      }
      if (!this.shouldContinuePageQueue(currentExtraction)) {
        hasMore = false;
        break;
      }
      if (attemptedChars >= CLOUD_TRANSLATION_MAX_TOTAL_CHARS) {
        hasMore = true;
        break;
      }
      if (round + 1 >= CLOUD_TRANSLATION_MAX_QUEUE_ROUNDS) {
        hasMore = true;
        break;
      }
      await this.requestCoordinator.delayBetweenTranslationBatches(provider);
      const nextExtraction = await this.runtimeBridge.extractPageQueue(
        controller,
        this.requestCoordinator.resolveInitialNodeLimit(provider),
        this.requestCoordinator.resolveInitialCharLimit(provider),
        CLOUD_TRANSLATION_MAX_ITEM_CHARS
      );
      if (nextExtraction.items.length === 0) {
        hilog.info(
          WEBPAGE_TRANSLATION_LOG_DOMAIN,
          WEBPAGE_TRANSLATION_LOG_TAG,
          'page queue stopped on empty next extraction round=%{public}d pageScrollable=%{public}s',
          round + 1,
          this.extractionPageIsScrollable(nextExtraction) ? 'true' : 'false'
        );
        hasMore = false;
        break;
      }
      currentExtraction = await this.cacheCoordinator.hydrateExtraction(nextExtraction, cacheContext);
    }

    return {
      appliedCount: appliedCount,
      appliedChars: appliedChars,
      attemptedCount: attemptedCount,
      attemptedChars: attemptedChars,
      requestedCount: requestedCount,
      requestedChars: requestedChars,
      cacheHitCount: cacheHitCount,
      stoppedAfterProviderFailure: stoppedAfterProviderFailure,
      extractedCount: extractedCount,
      extractedChars: extractedChars,
      hasMore: hasMore,
      lastExtraction: currentExtraction
    };
  }

  private async applyCachedTranslations(
    controller: webview.WebviewController,
    cachePipeline: WebpageTranslationCachePipeline,
    settings: TranslationSettings,
    sourceLanguage: string,
    onState: (state: WebpageTranslationPanelState) => void,
    taskGeneration: number
  ): Promise<WebpageTranslationCachedApplySummary> {
    const items = cachePipeline.sourceItems;
    if (cachePipeline.cachedApplyItems.length === 0) {
      return {
        appliedCount: 0,
        appliedChars: 0,
        cacheHitCount: 0
      };
    }
    const applyResult = await this.runtimeBridge.applyTranslations(controller, cachePipeline.cachedApplyItems);
    const appliedChars = this.countAppliedChars(items, applyResult.appliedIds, applyResult.appliedCount);
    if (!this.isStale(taskGeneration) && applyResult.appliedCount > 0) {
      this.sessionCoordinator.logSessionEvent(
        'apply_done',
        applyResult.appliedCount,
        appliedChars,
        cachePipeline.stats.cacheHitCount,
        0,
        'visible_cache'
      );
      onState(this.buildTranslatingProgressState(
        settings,
        items.length,
        {
          appliedCount: applyResult.appliedCount,
          appliedChars: appliedChars,
          attemptedCount: items.length,
          attemptedChars: this.countItemChars(items),
          requestedCount: 0,
          requestedChars: 0,
          cacheHitCount: cachePipeline.stats.cacheHitCount,
          stoppedAfterProviderFailure: false,
          hasMore: cachePipeline.missedSourceItems.length > 0
        },
        this.countItemChars(items),
        sourceLanguage
      ));
    }
    return {
      appliedCount: applyResult.appliedCount,
      appliedChars: appliedChars,
      cacheHitCount: cachePipeline.stats.cacheHitCount
    };
  }

  private normalizeThrowable(error: Object | string | number | boolean | undefined): Error {
    if (error instanceof Error) {
      return error;
    }
    return new Error(this.stringifyError(error));
  }

  private extractionHasMoreCandidates(extraction: WebpageTranslationExtractionResult): boolean {
    const diagnostics = extraction.diagnostics;
    if (diagnostics === undefined) {
      return false;
    }
    const candidateCount = diagnostics.candidateCount ?? 0;
    const selectedCount = diagnostics.selectedCount ?? extraction.items.length;
    if (candidateCount > selectedCount) {
      return true;
    }
    const selectedChars = diagnostics.selectedChars ?? this.countItemChars(extraction.items);
    const limitChars = diagnostics.limitChars ?? 0;
    const limitNodes = diagnostics.limitNodes ?? 0;
    return (limitNodes > 0 && selectedCount >= limitNodes) ||
      (limitChars > 0 && selectedChars >= limitChars);
  }

  private extractionPageIsScrollable(extraction: WebpageTranslationExtractionResult): boolean {
    return extraction.diagnostics?.pageScrollable === true;
  }

  private shouldContinuePageQueue(extraction: WebpageTranslationExtractionResult): boolean {
    return this.extractionHasMoreCandidates(extraction) || this.extractionPageIsScrollable(extraction);
  }

  private prioritizeItemsForTranslation(items: WebpageTranslationTextItem[]): WebpageTranslationTextItem[] {
    return items.slice().sort((left: WebpageTranslationTextItem, right: WebpageTranslationTextItem): number => {
      const leftVisible = left.nearViewport === true;
      const rightVisible = right.nearViewport === true;
      if (leftVisible !== rightVisible) {
        return leftVisible ? -1 : 1;
      }
      const topDiff = this.normalizeSortNumber(left.top) - this.normalizeSortNumber(right.top);
      if (topDiff !== 0) {
        return topDiff;
      }
      return this.normalizeSortNumber(left.order) - this.normalizeSortNumber(right.order);
    });
  }

  private countNearViewportItems(items: WebpageTranslationTextItem[]): number {
    let total = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      if (item.nearViewport === true) {
        total += 1;
      }
    });
    return total;
  }

  private normalizeSortNumber(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value)) {
      return 0;
    }
    return value;
  }

  private countItemChars(items: WebpageTranslationTextItem[]): number {
    let total = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      const itemLength = item.charLength !== undefined && item.charLength > 0
        ? item.charLength
        : item.text.length;
      total += itemLength;
    });
    return total;
  }

  private countAppliedChars(
    items: WebpageTranslationTextItem[],
    appliedIds: string[],
    fallbackAppliedCount: number
  ): number {
    if (appliedIds.length > 0) {
      const appliedMap: Record<string, boolean> = {};
      appliedIds.forEach((id: string) => {
        appliedMap[id] = true;
      });
      return this.countItemChars(items.filter((item: WebpageTranslationTextItem): boolean => {
        return appliedMap[item.id] === true;
      }));
    }
    return this.countItemChars(items.slice(0, Math.max(0, fallbackAppliedCount)));
  }

  private buildSourceBatchSample(items: WebpageTranslationTextItem[]): string {
    return items.slice(0, 4).map((item: WebpageTranslationTextItem): string => {
      return `${item.id}:${item.text.length}:s${item.score ?? 0}:top${item.top ?? 0}:${this.sanitizeLogText(item.text)}`;
    }).join(' | ');
  }

  private buildExtractionSignature(extraction: WebpageTranslationExtractionResult): string {
    const mode = extraction.diagnostics?.mode ?? '';
    const selected = extraction.items.slice(0, 8).map((item: WebpageTranslationTextItem): string => {
      return `${item.id}:${item.order ?? 0}:${item.text.length}:${this.sanitizeLogText(item.text).substring(0, 16)}`;
    }).join('|');
    return `${mode}:${extraction.items.length}:${selected}`;
  }

  private buildTranslationBatchSample(items: WebpageTranslationApplyItem[]): string {
    return items.slice(0, 4).map((item: WebpageTranslationApplyItem): string => {
      return `${item.id}:${item.translatedText.length}:${this.sanitizeLogText(item.translatedText)}`;
    }).join(' | ');
  }

  private sanitizeLogText(value: string): string {
    return value
      .replace(/\s+/g, ' ')
      .replace(/%/g, '%%')
      .substring(0, 48);
  }

  private resolveActiveProvider(settings: TranslationSettings): TranslationProviderConfig | undefined {
    const activeProviderId = settings.activeProviderId.trim();
    if (activeProviderId.length === 0) {
      return undefined;
    }
    return settings.providers.find((provider: TranslationProviderConfig) => provider.id === activeProviderId);
  }

  private resolvePanelProviderTemplateId(settings: TranslationSettings): TranslationProviderTemplateId {
    return this.resolveProviderTemplateId(this.resolveActiveProvider(settings));
  }

  private resolveProviderTemplateId(provider: TranslationProviderConfig | undefined): TranslationProviderTemplateId {
    return provider?.templateId ?? 'custom_http';
  }

  private resolvePanelProviderDisplayName(settings: TranslationSettings): string {
    return this.resolveProviderDisplayName(this.resolveActiveProvider(settings));
  }

  private resolveProviderDisplayName(provider: TranslationProviderConfig | undefined): string {
    return provider?.displayName ?? '未配置翻译服务';
  }

  private buildErrorMessage(error: Error | Object): string {
    if (error instanceof TranslationProviderError) {
      return error.failure.message;
    }
    if (error instanceof Error) {
      return `网页翻译失败：${error.message}`;
    }
    try {
      return `网页翻译失败：${JSON.stringify(error)}`;
    } catch (_error) {
      return '网页翻译失败。';
    }
  }

  private stringifyError(error: Error | Object | string | number | boolean | undefined): string {
    if (error === undefined) {
      return 'unknown error';
    }
    if (error instanceof Error) {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch (_error) {
      return `${error}`;
    }
  }

  private buildErrorState(
    settings: TranslationSettings,
    message: string,
    sourceLanguage: string = '',
    title: string = '网页翻译'
  ): WebpageTranslationPanelState {
    return {
      visible: true,
      status: 'error',
      displayMode: 'none',
      title: title,
      message: message,
      providerTemplateId: this.resolvePanelProviderTemplateId(settings),
      providerDisplayName: this.resolvePanelProviderDisplayName(settings),
      sourceLanguage: sourceLanguage,
      targetLanguage: settings.preferences.preferredTargetLanguage,
      translatedCount: 0,
      canTranslate: true,
      canRestore: false,
      canCancel: false
    };
  }
}

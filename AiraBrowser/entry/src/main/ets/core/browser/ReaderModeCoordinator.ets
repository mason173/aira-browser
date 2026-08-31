import { webview } from '@kit.ArkWeb';
import {
  ReaderModeAction,
  ReaderModeArticle,
  ReaderModeControlPanel,
  ReaderModeOverlayBackState,
  ReaderModePreferences,
  ReaderModeSearchState,
  ReaderModeTheme,
  ReaderModeViewState,
  createDefaultReaderModeOverlayBackState,
  createDefaultReaderModeViewState
} from '../../features/reader/ReaderModeModels';
import { ReaderArticlePostProcessor } from '../../features/reader/ReaderArticlePostProcessor';
import { ReaderImageQualityService } from '../../features/reader/ReaderImageQualityService';
import { ReaderModeViewModel } from '../../features/reader/ReaderModeViewModel';
import {
  ReaderSpeechState,
  ReaderSpeechVoiceOption,
  createDefaultReaderSpeechState,
  isReaderSpeechActive,
  shouldResetReaderSpeechStateOnStop
} from '../../features/reader/ReaderSpeechModels';
import { ReaderSpeechPlaybackViewModel } from '../../features/reader/ReaderSpeechPlaybackViewModel';
import { ReaderSpeechPlayerViewModel } from '../../features/reader/ReaderSpeechPlayerViewModel';
import { ReaderSpeechTextBuilder } from '../../features/reader/ReaderSpeechTextBuilder';
import {
  ReaderSpeechProgress,
  ReaderSpeechService
} from '../../services/reader/ReaderSpeechService';
import { ReaderEligibilityService } from '../../services/web/ReaderEligibilityService';
import { ReaderExtractionService } from '../../services/web/ReaderExtractionService';
import { ReaderImageCacheService } from '../../services/web/ReaderImageCacheService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  BrowserResolvedThemeMode,
  ReaderModeBrightnessMode
} from '../../common/models/BrowserModels';
import {
  ReadingAppearancePreferencesRepository,
  sharedReadingAppearancePreferencesRepository
} from '../../data/reading/ReadingAppearancePreferencesRepository';
import {
  ReadingPresentationMode,
  ReadingSurfaceAppearance
} from '../../features/reading/ReadingSurfaceModels';

interface ReaderModeOpenResult {
  state: ReaderModeViewState;
  available: boolean;
  article?: ReaderModeArticle;
  diagnosticEvent: string;
  diagnosticText: string;
  shouldCacheImages: boolean;
}

interface ReaderModeCacheResult {
  state?: ReaderModeViewState;
  diagnosticEvent: string;
  diagnosticText: string;
}

interface ReaderModeSpeechSessionSnapshot {
  state: ReaderSpeechState;
  chunks: string[];
  speed: number;
  voiceLabel: string;
  voiceDialog: ReaderModeSpeechVoiceDialogPresentation;
}

export interface ReaderModeSpeechVoiceDialogPresentation {
  readerTheme: ReaderModeTheme;
  selectedVoiceId: string;
  options: ReaderSpeechVoiceOption[];
  loading: boolean;
  errorMessage: string;
}

export type ReaderModeSessionSnapshotTransition = 'none' | 'theme';
export type ReaderModeSessionOpenOutcome = 'opened' | 'unavailable' | 'stale';

export interface ReaderSpeechPlayerAction {
  type: 'dismiss' | 'toggle' | 'previous' | 'next' | 'replay' | 'locate' | 'change_speed' | 'open_voice_picker';
  speed?: number;
}

export interface ReaderModeSessionSnapshot {
  state: ReaderModeViewState;
  reading: ReaderModeReadingSessionSnapshot;
  overlayBackState: ReaderModeOverlayBackState;
  speech: ReaderModeSpeechSessionSnapshot;
}

export interface ReaderModeReadingSessionSnapshot {
  presentationMode: ReadingPresentationMode;
}

export function createDefaultReaderModeSessionSnapshot(): ReaderModeSessionSnapshot {
  return {
    state: createDefaultReaderModeViewState(),
    reading: {
      presentationMode: 'vertical'
    },
    overlayBackState: createDefaultReaderModeOverlayBackState(),
    speech: {
      state: createDefaultReaderSpeechState(),
      chunks: [],
      speed: 1,
      voiceLabel: '',
      voiceDialog: {
        readerTheme: 'system',
        selectedVoiceId: '',
        options: [],
        loading: false,
        errorMessage: ''
      }
    }
  };
}

type ReaderModeSimpleEffectType =
  'sync_status_bar_style' |
  'present_speech_player' |
  'dismiss_speech_player' |
  'reset_speech_player_presentation' |
  'open_bookmarks';

interface ReaderModeSimpleEffect {
  type: ReaderModeSimpleEffectType;
}

interface ReaderModeToastEffect {
  type: 'toast';
  message: string;
}

interface ReaderModeRestoreStatusBarEffect {
  type: 'restore_status_bar';
  source: string;
}

interface ReaderModeUrlEffect {
  type: 'copy_link' | 'open_link';
  url: string;
}

interface ReaderModeShareEffect {
  type: 'share';
  title: string;
  url: string;
}

interface ReaderModeBookmarkEffect {
  type: 'bookmark';
}

interface ReaderModeStatusBarVisibilityEffect {
  type: 'status_bar_visibility';
  visible: boolean;
  source: string;
}

interface ReaderModeDiagnosticEffect {
  type: 'record_diagnostic';
  diagnosticEvent: string;
  diagnosticText: string;
  tabId: string;
}

interface ReaderModeOpenControlPanelEffect {
  type: 'open_control_panel';
  panel: ReaderModeControlPanel;
}

interface ReaderModeWindowBrightnessEffect {
  type: 'apply_window_brightness';
  brightnessMode: ReaderModeBrightnessMode;
  brightnessPercent: number;
}

interface ReaderModeWindowBrightnessRestoreEffect {
  type: 'restore_window_brightness';
}

export type ReaderModeEffect =
  ReaderModeSimpleEffect |
  ReaderModeToastEffect |
  ReaderModeRestoreStatusBarEffect |
  ReaderModeUrlEffect |
  ReaderModeShareEffect |
  ReaderModeBookmarkEffect |
  ReaderModeStatusBarVisibilityEffect |
  ReaderModeDiagnosticEffect |
  ReaderModeOpenControlPanelEffect |
  ReaderModeWindowBrightnessEffect |
  ReaderModeWindowBrightnessRestoreEffect;

export interface ReaderModeEffectApplication {
  apply: (effect: ReaderModeEffect) => void;
}

export interface ReaderModeActionContext {
  fallbackTitle: string;
  fallbackUrl: string;
}

export interface ReaderModeSessionListener {
  onSnapshotChanged: (
    snapshot: ReaderModeSessionSnapshot,
    transition: ReaderModeSessionSnapshotTransition
  ) => void;
  onEffect?: (effect: ReaderModeEffect) => void;
}

export interface ArticleReadingSessionConnection {
  disconnect(): void;
}

export interface ArticleReadingSessionOperations {
  connectSessionListener(listener: ReaderModeSessionListener): ArticleReadingSessionConnection;
  setEffectApplication(application: ReaderModeEffectApplication | undefined): void;
  getSessionSnapshot(): ReaderModeSessionSnapshot;
  resolveEffectiveTheme(systemTheme: BrowserResolvedThemeMode): ReaderModeTheme;
  loadPreferences(): void;
  handleAction(action: ReaderModeAction, context: ReaderModeActionContext): void;
  handleSpeechPlayerAction(action: ReaderSpeechPlayerAction, openVoicePicker: () => void): void;
  openSessionFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    webPageVisible: boolean,
    pageUrl: string,
    tabId: string
  ): Promise<void>;
  openSessionFromController(
    controller: webview.WebviewController,
    pageUrl: string
  ): Promise<ReaderModeSessionOpenOutcome>;
  openSessionFromArticle(article: ReaderModeArticle, pageUrl: string): ReaderModeSessionOpenOutcome;
  requestImagePreviewDismissal(): void;
  requestPanelDismissal(): void;
  beginExitConfirmation(): boolean;
  endExitConfirmation(): void;
  closeSession(): void;
  resolveCurrentUrl(fallbackUrl?: string): string;
  toggleSpeech(): Promise<void>;
  playPreviousSpeechChunk(): Promise<void>;
  playNextSpeechChunk(): Promise<void>;
  replayCurrentSpeechChunk(): Promise<void>;
  changeSpeechSpeed(speed: number): Promise<void>;
  openSpeechVoicePicker(systemTheme: BrowserResolvedThemeMode): void;
  selectSpeechVoiceById(voiceId: string): Promise<void>;
  resetSpeechVoicePickerState(): void;
  locateSpeechChunkInReader(): void;
  dismissSpeechPlayerPresentation(): void;
  resetSpeechPlayerPresentation(): void;
  resetSpeechAfterLifecycleResume(): void;
  shutdownSpeechSession(): void;
}

class ArticleReadingSessionConnectionImplementation implements ArticleReadingSessionConnection {
  private disconnectHandler?: () => void;

  constructor(disconnectHandler: () => void) {
    this.disconnectHandler = disconnectHandler;
  }

  disconnect(): void {
    const handler = this.disconnectHandler;
    this.disconnectHandler = undefined;
    handler?.();
  }
}

interface ReaderModeCoordinatorOptions {
  viewModel?: ReaderModeViewModel;
  eligibilityService?: ReaderEligibilityService;
  extractionService?: ReaderExtractionService;
  articlePostProcessor?: ReaderArticlePostProcessor;
  imageQualityService?: ReaderImageQualityService;
  imageCacheService?: ReaderImageCacheService;
  speechTextBuilder?: ReaderSpeechTextBuilder;
  speechPlaybackViewModel?: ReaderSpeechPlaybackViewModel;
  speechPlayerViewModel?: ReaderSpeechPlayerViewModel;
  speechService?: ReaderSpeechService;
  preferencesRepository?: PreferencesRepository;
  appearancePreferencesRepository?: ReadingAppearancePreferencesRepository;
}

export class ReaderModeCoordinator implements ArticleReadingSessionOperations {
  private viewModel: ReaderModeViewModel;
  private eligibilityService: ReaderEligibilityService;
  private extractionService: ReaderExtractionService;
  private articlePostProcessor: ReaderArticlePostProcessor;
  private imageQualityService: ReaderImageQualityService;
  private imageCacheService: ReaderImageCacheService;
  private speechTextBuilder: ReaderSpeechTextBuilder;
  private speechPlaybackViewModel: ReaderSpeechPlaybackViewModel;
  private speechPlayerViewModel: ReaderSpeechPlayerViewModel;
  private speechService: ReaderSpeechService;
  private preferencesRepository: PreferencesRepository;
  private appearancePreferencesRepository: ReadingAppearancePreferencesRepository;
  private sessionListener?: ReaderModeSessionListener;
  private effectApplication?: ReaderModeEffectApplication;
  private readerState: ReaderModeViewState = createDefaultReaderModeViewState();
  private presentationModeOverride: '' | ReadingPresentationMode = '';
  private overlayBackState: ReaderModeOverlayBackState = createDefaultReaderModeOverlayBackState();
  private exitConfirmVisible: boolean = false;
  private readerOpenGeneration: number = 0;
  private preferenceGeneration: number = 0;
  private speechState: ReaderSpeechState = createDefaultReaderSpeechState();
  private speechChunks: string[] = [];
  private speechSpeed: number = 1;
  private speechVoiceOptions: ReaderSpeechVoiceOption[] = [];
  private selectedSpeechVoice?: ReaderSpeechVoiceOption;
  private speechVoiceDialogTheme: ReaderModeTheme = 'system';
  private speechVoiceDialogLoading: boolean = false;
  private speechVoiceDialogErrorMessage: string = '';
  private speechVoiceDialogGeneration: number = 0;
  private speechCommandGeneration: number = 0;

  constructor(options: ReaderModeCoordinatorOptions = {}) {
    this.viewModel = options.viewModel ?? new ReaderModeViewModel();
    this.eligibilityService = options.eligibilityService ?? new ReaderEligibilityService();
    this.extractionService = options.extractionService ?? new ReaderExtractionService();
    this.articlePostProcessor = options.articlePostProcessor ?? new ReaderArticlePostProcessor();
    this.imageQualityService = options.imageQualityService ?? new ReaderImageQualityService();
    this.imageCacheService = options.imageCacheService ?? new ReaderImageCacheService();
    this.speechTextBuilder = options.speechTextBuilder ?? new ReaderSpeechTextBuilder();
    this.speechPlaybackViewModel = options.speechPlaybackViewModel ?? new ReaderSpeechPlaybackViewModel();
    this.speechPlayerViewModel = options.speechPlayerViewModel ?? new ReaderSpeechPlayerViewModel();
    this.speechService = options.speechService ?? new ReaderSpeechService();
    this.preferencesRepository = options.preferencesRepository ?? new PreferencesRepository();
    this.appearancePreferencesRepository = options.appearancePreferencesRepository ??
      sharedReadingAppearancePreferencesRepository;
    this.bindSpeechService();
  }

  setSessionListener(listener: ReaderModeSessionListener): void {
    this.sessionListener = listener;
    this.emitSessionSnapshot();
  }

  connectSessionListener(listener: ReaderModeSessionListener): ArticleReadingSessionConnection {
    this.sessionListener = listener;
    this.emitSessionSnapshot();
    return new ArticleReadingSessionConnectionImplementation((): void => {
      if (this.sessionListener === listener) {
        this.sessionListener = undefined;
      }
    });
  }

  setEffectApplication(application: ReaderModeEffectApplication | undefined): void {
    this.effectApplication = application;
  }

  getSessionSnapshot(): ReaderModeSessionSnapshot {
    return {
      state: this.cloneReaderState(this.readerState),
      reading: {
        presentationMode: this.resolveReadingPresentationMode()
      },
      overlayBackState: this.cloneOverlayBackState(this.overlayBackState),
      speech: this.getSpeechSessionSnapshot()
    };
  }

  resolveEffectiveTheme(systemTheme: BrowserResolvedThemeMode): ReaderModeTheme {
    return this.viewModel.resolveEffectiveTheme(this.readerState.preferences.theme, systemTheme);
  }

  loadPreferences(): void {
    const preferences: ReaderModePreferences = this.preferencesRepository.getPreferences().readerMode;
    this.applyReaderPreferences(this.mergeReadingAppearance(
      preferences,
      this.appearancePreferencesRepository.resolveCached(this.buildReadingAppearance(preferences))
    ), 'none');
    const loadGeneration: number = this.preferenceGeneration;
    void this.appearancePreferencesRepository.load(this.buildReadingAppearance(preferences))
      .then((appearance: ReadingSurfaceAppearance): void => {
        if (this.preferenceGeneration !== loadGeneration) {
          return;
        }
        const currentPreferences: ReaderModePreferences = this.readerState.preferences;
        this.applyReaderPreferences(this.mergeReadingAppearance(currentPreferences, appearance), 'none');
      })
      .catch((_error: Error): void => {
      });
  }

  handleAction(action: ReaderModeAction, context: ReaderModeActionContext): void {
    switch (action.type) {
      case 'close':
        this.closeSession();
        return;
      case 'copy_link':
        this.emitEffect({
          type: 'copy_link',
          url: this.resolveCurrentUrl(context.fallbackUrl)
        });
        return;
      case 'share':
        this.shareCurrentArticle(context);
        return;
      case 'bookmark':
        this.emitEffect({ type: 'bookmark' });
        return;
      case 'update_preferences':
        if (action.resetPresentationModeOverride === true) {
          this.presentationModeOverride = '';
        }
        this.applyAndPersistReaderPreferences(action.preferences, 'none');
        return;
      case 'open_bookmarks':
        this.emitEffect({ type: 'open_bookmarks' });
        return;
      case 'open_link':
        this.emitEffect({
          type: 'open_link',
          url: action.url
        });
        return;
      case 'open_speech_player':
        this.openSpeechPlayerFromSession();
        return;
      case 'open_control_panel':
        this.emitEffect({ type: 'open_control_panel', panel: action.panel });
        return;
      case 'reading_appearance_change': {
        const preferences: ReaderModePreferences = this.cloneReaderPreferences(this.readerState.preferences);
        preferences.fontSize = action.appearance.fontSize;
        preferences.theme = action.appearance.theme;
        preferences.lineHeight = action.appearance.lineHeight;
        preferences.pageWidth = action.appearance.pageWidth;
        preferences.brightnessMode = action.appearance.brightnessMode;
        preferences.brightnessPercent = action.appearance.brightnessPercent;
        this.applyAndPersistReaderPreferences(preferences, 'none');
        return;
      }
      case 'reading_presentation_mode_change': {
        const preferences: ReaderModePreferences = this.cloneReaderPreferences(this.readerState.preferences);
        preferences.pageMode = action.mode;
        this.presentationModeOverride = '';
        this.applyAndPersistReaderPreferences(preferences, 'none');
        return;
      }
      case 'search_change':
        this.applyReaderSearch(this.viewModel.buildSearchState(action.query, this.readerState.article));
        return;
      case 'search_previous':
        this.applyReaderSearch(this.viewModel.moveSearchIndex(
          this.readerState.search,
          -1,
          this.readerState.article
        ));
        return;
      case 'search_next':
        this.applyReaderSearch(this.viewModel.moveSearchIndex(
          this.readerState.search,
          1,
          this.readerState.article
        ));
        return;
      case 'reading_layout_failure':
        this.fallbackCurrentSessionToVertical();
        return;
      case 'status_bar_visibility_change':
        this.emitEffect({
          type: 'status_bar_visibility',
          visible: action.visible,
          source: action.source
        });
        return;
      case 'image_preview_visibility_change':
        this.overlayBackState = this.viewModel.buildImagePreviewVisibilityState(
          this.overlayBackState,
          action.visible
        );
        this.emitSessionSnapshot();
        return;
      case 'panel_visibility_change':
        this.overlayBackState = this.viewModel.buildPanelVisibilityState(
          this.overlayBackState,
          action.visible
        );
        this.emitSessionSnapshot();
        return;
    }
  }

  handleSpeechPlayerAction(action: ReaderSpeechPlayerAction, openVoicePicker: () => void): void {
    if (action.type === 'dismiss') {
      this.dismissSpeechPlayerPresentation();
      return;
    }
    if (action.type === 'toggle') {
      void this.toggleSpeech();
      return;
    }
    if (action.type === 'previous') {
      void this.playPreviousSpeechChunk();
      return;
    }
    if (action.type === 'next') {
      void this.playNextSpeechChunk();
      return;
    }
    if (action.type === 'replay') {
      void this.replayCurrentSpeechChunk();
      return;
    }
    if (action.type === 'locate') {
      this.locateSpeechChunkInReader();
      return;
    }
    if (action.type === 'change_speed') {
      if (action.speed !== undefined) {
        void this.changeSpeechSpeed(action.speed);
      }
      return;
    }
    openVoicePicker();
  }

  async openSessionFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    webPageVisible: boolean,
    pageUrl: string,
    tabId: string
  ): Promise<void> {
    const controller = this.resolveVisibleActiveController(runtimeLifecyclePort, webPageVisible);
    if (controller === undefined) {
      this.emitToast('网页内容还在准备，请稍后再试。');
      return;
    }
    const generation = this.beginSessionOpen();
    const result = await this.open(controller, this.readerState);
    this.applySessionOpenResult(result, generation, pageUrl, tabId, true, false);
  }

  async openSessionFromController(
    controller: webview.WebviewController,
    pageUrl: string
  ): Promise<ReaderModeSessionOpenOutcome> {
    const generation = this.beginSessionOpen();
    const result = await this.open(controller, this.readerState);
    return this.applySessionOpenResult(result, generation, pageUrl, '', false, true);
  }

  openSessionFromArticle(article: ReaderModeArticle, pageUrl: string): ReaderModeSessionOpenOutcome {
    const generation = this.beginSessionOpen();
    if (this.readerOpenGeneration !== generation) {
      return 'stale';
    }
    const sessionArticle = this.resolveSessionArticle(article, pageUrl);
    if (sessionArticle.blocks.length <= 0) {
      this.readerState = this.viewModel.buildErrorState(
        this.readerState,
        '没有整理出可阅读的正文。'
      );
      this.emitSessionSnapshot();
      this.emitEffect({ type: 'sync_status_bar_style' });
      return 'unavailable';
    }
    this.readerState = this.viewModel.buildArticleState(this.readerState, sessionArticle);
    this.emitSessionSnapshot();
    this.emitEffect({ type: 'sync_status_bar_style' });
    return 'opened';
  }

  requestImagePreviewDismissal(): void {
    this.overlayBackState = this.viewModel.buildImagePreviewDismissRequest(this.overlayBackState);
    this.emitSessionSnapshot();
  }

  requestPanelDismissal(): void {
    this.overlayBackState = this.viewModel.buildPanelDismissRequest(this.overlayBackState);
    this.emitSessionSnapshot();
  }

  beginExitConfirmation(): boolean {
    if (this.exitConfirmVisible) {
      return false;
    }
    this.exitConfirmVisible = true;
    return true;
  }

  endExitConfirmation(): void {
    this.exitConfirmVisible = false;
  }

  closeSession(): void {
    this.readerOpenGeneration += 1;
    this.presentationModeOverride = '';
    this.closeSpeechSession();
    this.exitConfirmVisible = false;
    this.overlayBackState = createDefaultReaderModeOverlayBackState();
    this.readerState = this.viewModel.buildClosedState(this.readerState);
    this.emitSessionSnapshot();
    this.emitEffect({ type: 'reset_speech_player_presentation' });
    this.emitEffect({
      type: 'restore_status_bar',
      source: 'reader-close'
    });
    this.emitEffect({ type: 'sync_status_bar_style' });
  }

  resolveCurrentUrl(fallbackUrl: string = ''): string {
    const articleUrl = this.readerState.article.url.trim();
    return articleUrl.length > 0 ? articleUrl : fallbackUrl.trim();
  }

  private getSpeechSessionSnapshot(): ReaderModeSpeechSessionSnapshot {
    return {
      state: {
        status: this.speechState.status,
        currentChunkIndex: this.speechState.currentChunkIndex,
        totalChunks: this.speechState.totalChunks,
        message: this.speechState.message
      },
      chunks: this.speechChunks.slice(),
      speed: this.speechSpeed,
      voiceLabel: this.speechPlaybackViewModel.resolveVoiceLabel(this.selectedSpeechVoice),
      voiceDialog: {
        readerTheme: this.speechVoiceDialogTheme,
        selectedVoiceId: this.speechPlaybackViewModel.resolveSelectedVoiceId(this.selectedSpeechVoice),
        options: this.speechVoiceOptions.slice(),
        loading: this.speechVoiceDialogLoading,
        errorMessage: this.speechVoiceDialogErrorMessage
      }
    };
  }

  private openSpeechPlayer(): boolean {
    if (!this.prepareSpeechChunks()) {
      return false;
    }
    if (this.speechPlaybackViewModel.shouldAutoStartPlayer(this.speechState)) {
      void this.toggleSpeech();
    }
    return true;
  }

  async toggleSpeech(): Promise<void> {
    if (isReaderSpeechActive(this.speechState)) {
      const commandGeneration = this.speechCommandGeneration + 1;
      this.speechCommandGeneration = commandGeneration;
      const pausedState = this.speechPlaybackViewModel.buildPausedState(
        this.speechState,
        this.speechChunks.length
      );
      this.speechState = this.speechPlaybackViewModel.buildStoppingState(this.speechState);
      this.emitSessionSnapshot();
      await this.speechService.stop();
      if (this.speechCommandGeneration !== commandGeneration) {
        return;
      }
      this.speechState = pausedState;
      this.emitSessionSnapshot();
      return;
    }
    if (!this.prepareSpeechChunks()) {
      return;
    }
    const startChunkIndex = this.speechPlaybackViewModel.resolvePlaybackStartChunkIndex(
      this.speechState,
      this.speechChunks.length
    );
    await this.speakFromChunk(startChunkIndex);
  }

  async playPreviousSpeechChunk(): Promise<void> {
    await this.playSpeechChunk(
      this.speechPlayerViewModel.resolvePreviousChunkIndex(this.speechState, this.speechChunks.length)
    );
  }

  async playNextSpeechChunk(): Promise<void> {
    await this.playSpeechChunk(
      this.speechPlayerViewModel.resolveNextChunkIndex(this.speechState, this.speechChunks.length)
    );
  }

  async replayCurrentSpeechChunk(): Promise<void> {
    await this.playSpeechChunk(
      this.speechPlayerViewModel.resolveCurrentChunkStartIndex(this.speechState, this.speechChunks.length)
    );
  }

  async changeSpeechSpeed(speed: number): Promise<void> {
    this.speechSpeed = this.speechPlaybackViewModel.clampSpeechSpeed(speed);
    this.emitSessionSnapshot();
    if (isReaderSpeechActive(this.speechState)) {
      await this.replayCurrentSpeechChunk();
    }
  }

  openSpeechVoicePicker(systemTheme: BrowserResolvedThemeMode): void {
    const generation = this.speechVoiceDialogGeneration + 1;
    this.speechVoiceDialogGeneration = generation;
    this.speechVoiceDialogErrorMessage = '';
    this.speechVoiceDialogLoading = this.speechVoiceOptions.length <= 0;
    this.speechVoiceDialogTheme = this.resolveEffectiveTheme(systemTheme);
    this.emitSessionSnapshot();
    if (this.speechVoiceOptions.length > 0) {
      return;
    }
    void this.loadSpeechVoiceOptions(generation);
  }

  async selectSpeechVoiceById(voiceId: string): Promise<void> {
    const voice = this.speechVoiceOptions.find((option: ReaderSpeechVoiceOption) => option.id === voiceId);
    if (voice === undefined || !voice.isAvailable) {
      return;
    }
    this.selectedSpeechVoice = voice;
    this.emitSessionSnapshot();
    if (this.speechPlaybackViewModel.shouldRestartForRuntimeChange(this.speechState)) {
      await this.replayCurrentSpeechChunk();
    }
  }

  resetSpeechVoicePickerState(): void {
    this.resetSpeechVoiceDialogState();
    this.emitSessionSnapshot();
  }

  locateSpeechChunkInReader(): void {
    this.emitEffect({ type: 'dismiss_speech_player' });
  }

  dismissSpeechPlayerPresentation(): void {
    this.emitEffect({ type: 'dismiss_speech_player' });
  }

  resetSpeechPlayerPresentation(): void {
    this.emitEffect({ type: 'reset_speech_player_presentation' });
  }

  private closeSpeechSession(): void {
    this.invalidateSpeechCommands();
    void this.speechService.stop();
    this.speechState = createDefaultReaderSpeechState();
    this.resetSpeechVoiceDialogState();
    this.emitSessionSnapshot();
  }

  resetSpeechAfterLifecycleResume(): void {
    if (!this.readerState.visible) {
      return;
    }
    this.invalidateSpeechCommands();
    this.speechService.resetAfterLifecycleResume();
    this.speechState = createDefaultReaderSpeechState();
    this.resetSpeechVoiceDialogState();
    this.emitSessionSnapshot();
    this.emitEffect({ type: 'reset_speech_player_presentation' });
  }

  shutdownSpeechSession(): void {
    this.invalidateSpeechCommands();
    this.speechService.shutdown();
  }

  private async open(
    controller: webview.WebviewController,
    currentState: ReaderModeViewState
  ): Promise<ReaderModeOpenResult> {
    try {
      const probe = await this.extractionService.probe(controller);
      const eligibility = this.eligibilityService.evaluate(probe);
      const extractedArticle = await this.extractionService.extractChunked(controller, eligibility.bestSelector);
      const postProcessedArticle = this.articlePostProcessor.process(extractedArticle);
      const article = this.imageQualityService.filterArticleImages(postProcessedArticle);
      if (article.blocks.length <= 0) {
        return {
          state: this.viewModel.buildErrorState(currentState, this.buildExtractionFailureMessage(article)),
          available: false,
          article: article,
          diagnosticEvent: 'reader_mode_open_empty',
          diagnosticText: this.buildOpenDiagnosticText(article, eligibility.readable, eligibility.reason),
          shouldCacheImages: false
        };
      }
      return {
        state: this.viewModel.buildArticleState(currentState, article),
        available: true,
        article: article,
        diagnosticEvent: 'reader_mode_opened',
        diagnosticText: this.buildOpenDiagnosticText(article, eligibility.readable, eligibility.reason),
        shouldCacheImages: true
      };
    } catch (_error) {
      return {
        state: this.viewModel.buildErrorState(currentState, '阅读模式打开失败，请稍后重试。'),
        available: false,
        diagnosticEvent: 'reader_mode_open_failed',
        diagnosticText: '',
        shouldCacheImages: false
      };
    }
  }

  private async cacheImages(
    currentState: ReaderModeViewState,
    article: ReaderModeArticle
  ): Promise<ReaderModeCacheResult> {
    try {
      const cachedArticle = await this.imageCacheService.cacheArticleImages(article);
      if (!currentState.visible || currentState.article.url !== article.url) {
        return {
          diagnosticEvent: 'reader_mode_images_cache_stale',
          diagnosticText: article.url
        };
      }
      return {
        state: this.viewModel.buildArticleState(currentState, cachedArticle),
        diagnosticEvent: 'reader_mode_images_cached',
        diagnosticText: `blocks=${cachedArticle.blocks.length}`
      };
    } catch (_error) {
      return {
        diagnosticEvent: 'reader_mode_images_cache_failed',
        diagnosticText: article.url
      };
    }
  }

  private openSpeechPlayerFromSession(): void {
    if (!this.openSpeechPlayer()) {
      return;
    }
    this.emitEffect({ type: 'present_speech_player' });
  }

  private beginSessionOpen(): number {
    const currentPreferences: ReaderModePreferences = this.readerState.preferences;
    const cachedAppearance: ReadingSurfaceAppearance = this.appearancePreferencesRepository.resolveCached(
      this.buildReadingAppearance(currentPreferences)
    );
    this.readerState = this.buildStateWithPreferences(
      this.readerState,
      this.mergeReadingAppearance(currentPreferences, cachedAppearance)
    );
    const generation = this.readerOpenGeneration + 1;
    this.readerOpenGeneration = generation;
    this.presentationModeOverride = '';
    this.readerState = this.viewModel.buildLoadingState(this.readerState);
    this.emitSessionSnapshot();
    this.emitEffect({ type: 'sync_status_bar_style' });
    return generation;
  }

  private applySessionOpenResult(
    result: ReaderModeOpenResult,
    generation: number,
    pageUrl: string,
    tabId: string,
    publishDiagnostics: boolean,
    canonicalizeArticleUrl: boolean
  ): ReaderModeSessionOpenOutcome {
    if (this.readerOpenGeneration !== generation) {
      return 'stale';
    }
    const sessionArticle = !result.available || result.article === undefined ? undefined :
      (canonicalizeArticleUrl ? this.resolveSessionArticle(result.article, pageUrl) : result.article);
    this.readerState = sessionArticle === undefined ? result.state :
      this.viewModel.buildArticleState(result.state, sessionArticle);
    this.emitSessionSnapshot();
    this.emitEffect({ type: 'sync_status_bar_style' });
    if (publishDiagnostics) {
      this.emitDiagnostic(
        result.diagnosticEvent,
        result.diagnosticText.length > 0 ? result.diagnosticText : pageUrl,
        tabId
      );
    }
    if (result.shouldCacheImages && sessionArticle !== undefined) {
      void this.cacheSessionImages(sessionArticle, generation, tabId, publishDiagnostics);
    }
    return result.available ? 'opened' : 'unavailable';
  }

  private async cacheSessionImages(
    article: ReaderModeArticle,
    generation: number,
    tabId: string,
    publishDiagnostics: boolean = true
  ): Promise<void> {
    const result = await this.cacheImages(this.readerState, article);
    if (this.readerOpenGeneration !== generation) {
      return;
    }
    if (result.state !== undefined) {
      this.readerState = this.viewModel.buildArticleState(
        this.readerState,
        result.state.article
      );
      this.emitSessionSnapshot();
    }
    if (publishDiagnostics) {
      this.emitDiagnostic(result.diagnosticEvent, result.diagnosticText, tabId);
    }
  }

  private resolveSessionArticle(article: ReaderModeArticle, pageUrl: string): ReaderModeArticle {
    const normalizedPageUrl = pageUrl.trim();
    if (normalizedPageUrl.length <= 0 || article.url === normalizedPageUrl) {
      return article;
    }
    return {
      title: article.title,
      byline: article.byline,
      siteName: article.siteName,
      publishedAt: article.publishedAt,
      url: normalizedPageUrl,
      excerpt: article.excerpt,
      diagnostics: article.diagnostics,
      blocks: article.blocks
    };
  }

  private applyReaderPreferences(
    preferences: ReaderModePreferences,
    transition: ReaderModeSessionSnapshotTransition
  ): void {
    this.readerState = this.buildStateWithPreferences(this.readerState, preferences);
    this.emitSessionSnapshot(transition);
    this.emitEffect({ type: 'sync_status_bar_style' });
  }

  private buildStateWithPreferences(
    state: ReaderModeViewState,
    preferences: ReaderModePreferences
  ): ReaderModeViewState {
    return {
      visible: state.visible,
      loading: state.loading,
      errorMessage: state.errorMessage,
      article: state.article,
      preferences: this.cloneReaderPreferences(preferences),
      search: state.search
    };
  }

  private applyAndPersistReaderPreferences(
    preferences: ReaderModePreferences,
    transition: ReaderModeSessionSnapshotTransition
  ): void {
    this.applyReaderPreferences(preferences, transition);
    const generation = this.preferenceGeneration + 1;
    this.preferenceGeneration = generation;
    void this.preferencesRepository.updateReaderModePreferences(preferences)
      .then((snapshot) => {
        if (this.preferenceGeneration !== generation) {
          return;
        }
        this.applyReaderPreferences(snapshot.readerMode, 'none');
      })
      .catch((_error: Error) => {
        if (this.preferenceGeneration === generation) {
          this.emitToast('阅读偏好保存失败。');
        }
      });
  }

  private applyReaderSearch(search: ReaderModeSearchState): void {
    this.readerState = {
      visible: this.readerState.visible,
      loading: this.readerState.loading,
      errorMessage: this.readerState.errorMessage,
      article: this.readerState.article,
      preferences: this.readerState.preferences,
      search: {
        query: search.query,
        matches: search.matches,
        activeIndex: search.activeIndex,
        activeBlockId: search.activeBlockId,
        blockMatchCounts: search.blockMatchCounts
      }
    };
    this.emitSessionSnapshot();
  }

  private fallbackCurrentSessionToVertical(): void {
    if (!this.readerState.visible || this.resolveReadingPresentationMode() === 'vertical') {
      return;
    }
    this.presentationModeOverride = 'vertical';
    this.emitSessionSnapshot();
    this.emitToast('当前内容无法安全分页，已临时切换为上下滚动。');
  }

  private resolveReadingPresentationMode(): ReadingPresentationMode {
    return this.presentationModeOverride.length > 0
      ? this.presentationModeOverride as ReadingPresentationMode
      : this.readerState.preferences.pageMode;
  }

  private shareCurrentArticle(context: ReaderModeActionContext): void {
    const url = this.resolveCurrentUrl(context.fallbackUrl);
    if (url.length <= 0) {
      this.emitToast('当前没有可分享的网址。');
      return;
    }
    const articleTitle = this.readerState.article.title.trim();
    const fallbackTitle = context.fallbackTitle.trim();
    this.emitEffect({
      type: 'share',
      title: articleTitle.length > 0 ? articleTitle : (fallbackTitle.length > 0 ? fallbackTitle : url),
      url: url
    });
  }

  private emitDiagnostic(event: string, text: string, tabId: string): void {
    this.emitEffect({
      type: 'record_diagnostic',
      diagnosticEvent: event,
      diagnosticText: text,
      tabId: tabId
    });
  }

  private cloneReaderState(state: ReaderModeViewState): ReaderModeViewState {
    return {
      visible: state.visible,
      loading: state.loading,
      errorMessage: state.errorMessage,
      // Articles are session-owned value objects that are replaced, never mutated in place.
      // Reuse that read-only payload to avoid cloning the full document on scroll and TTS snapshots.
      article: state.article,
      preferences: this.cloneReaderPreferences(state.preferences),
      search: {
        query: state.search.query,
        matches: state.search.matches,
        activeIndex: state.search.activeIndex,
        activeBlockId: state.search.activeBlockId,
        blockMatchCounts: this.cloneReaderBlockMatchCounts(state.search.blockMatchCounts)
      }
    };
  }

  private cloneReaderPreferences(preferences: ReaderModePreferences): ReaderModePreferences {
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent,
      pageMode: preferences.pageMode
    };
  }

  private buildReadingAppearance(preferences: ReaderModePreferences): ReadingSurfaceAppearance {
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent
    };
  }

  private mergeReadingAppearance(
    preferences: ReaderModePreferences,
    appearance: ReadingSurfaceAppearance
  ): ReaderModePreferences {
    return {
      fontSize: appearance.fontSize,
      theme: appearance.theme,
      lineHeight: appearance.lineHeight,
      pageWidth: appearance.pageWidth,
      brightnessMode: appearance.brightnessMode,
      brightnessPercent: appearance.brightnessPercent,
      pageMode: preferences.pageMode
    };
  }

  private cloneReaderBlockMatchCounts(counts: Record<string, number>): Record<string, number> {
    const clonedCounts: Record<string, number> = {};
    Object.keys(counts).forEach((blockId: string): void => {
      clonedCounts[blockId] = counts[blockId];
    });
    return clonedCounts;
  }

  private cloneOverlayBackState(state: ReaderModeOverlayBackState): ReaderModeOverlayBackState {
    return {
      imagePreviewVisible: state.imagePreviewVisible,
      dismissImagePreviewRequestVersion: state.dismissImagePreviewRequestVersion,
      panelVisible: state.panelVisible,
      dismissPanelRequestVersion: state.dismissPanelRequestVersion
    };
  }

  private bindSpeechService(): void {
    this.speechService.setListener({
      onStart: (progress: ReaderSpeechProgress): void => {
        this.applySpeechProgress(progress);
      },
      onChunkStart: (progress: ReaderSpeechProgress): void => {
        this.applySpeechProgress(progress);
      },
      onComplete: (): void => {
        this.speechState = createDefaultReaderSpeechState();
        this.emitSessionSnapshot();
        this.emitToast('朗读完成。');
      },
      onStop: (): void => {
        if (shouldResetReaderSpeechStateOnStop(this.speechState)) {
          this.speechState = createDefaultReaderSpeechState();
          this.emitSessionSnapshot();
        }
      },
      onError: (message: string): void => {
        this.speechState = this.speechPlaybackViewModel.buildErrorState(message);
        this.emitSessionSnapshot();
        this.emitToast(message);
      }
    });
  }

  private async playSpeechChunk(startChunkIndex: number): Promise<void> {
    if (!this.prepareSpeechChunks()) {
      return;
    }
    const safeIndex = this.speechPlaybackViewModel.clampChunkIndex(startChunkIndex, this.speechChunks.length);
    await this.speakFromChunk(safeIndex);
  }

  private async speakFromChunk(startChunkIndex: number): Promise<void> {
    const commandGeneration = this.speechCommandGeneration + 1;
    this.speechCommandGeneration = commandGeneration;
    this.speechState = this.speechPlaybackViewModel.buildPreparingState(
      startChunkIndex,
      this.speechChunks.length
    );
    this.emitSessionSnapshot();
    try {
      await this.speechService.speak(this.speechChunks, {
        startChunkIndex: startChunkIndex,
        speed: this.speechSpeed,
        voice: this.selectedSpeechVoice
      });
    } catch (_error) {
      if (this.speechCommandGeneration !== commandGeneration) {
        return;
      }
      this.speechState = this.speechPlaybackViewModel.buildErrorState('朗读启动失败，请稍后再试。');
      this.emitSessionSnapshot();
    }
  }

  private prepareSpeechChunks(): boolean {
    if (this.readerState.loading) {
      this.emitToast('正文还在整理中，请稍后再试。');
      return false;
    }
    if (this.readerState.errorMessage.length > 0) {
      this.emitToast(this.readerState.errorMessage);
      return false;
    }
    const chunks = this.speechTextBuilder.buildChunks(this.readerState.article);
    if (chunks.length <= 0) {
      this.emitToast('没有可朗读的正文。');
      return false;
    }
    this.speechState = this.speechPlaybackViewModel.reconcileChunksState(
      this.speechState,
      this.speechChunks,
      chunks
    );
    this.speechChunks = chunks;
    this.emitSessionSnapshot();
    return true;
  }

  private applySpeechProgress(progress: ReaderSpeechProgress): void {
    this.speechState = this.speechPlaybackViewModel.buildProgressState(
      'speaking',
      progress.currentChunkIndex,
      progress.totalChunks,
      ''
    );
    this.emitSessionSnapshot();
  }

  private async loadSpeechVoiceOptions(generation: number): Promise<void> {
    const options = await this.speechService.listVoiceOptions();
    if (this.speechVoiceDialogGeneration !== generation) {
      return;
    }
    this.speechVoiceOptions = options;
    this.speechVoiceDialogLoading = false;
    if (options.length <= 0) {
      this.speechVoiceDialogErrorMessage = '当前设备暂未返回中文音色。';
      this.emitSessionSnapshot();
      return;
    }
    if (this.selectedSpeechVoice === undefined) {
      this.selectedSpeechVoice = options[0];
    }
    this.emitSessionSnapshot();
  }

  private resetSpeechVoiceDialogState(): void {
    this.speechVoiceDialogGeneration += 1;
    this.speechVoiceDialogLoading = false;
    this.speechVoiceDialogErrorMessage = '';
  }

  private invalidateSpeechCommands(): void {
    this.speechCommandGeneration += 1;
  }

  private emitSessionSnapshot(transition: ReaderModeSessionSnapshotTransition = 'none'): void {
    this.sessionListener?.onSnapshotChanged(this.getSessionSnapshot(), transition);
    if (this.readerState.visible) {
      this.emitEffect({
        type: 'apply_window_brightness',
        brightnessMode: this.readerState.preferences.brightnessMode,
        brightnessPercent: this.readerState.preferences.brightnessPercent
      });
      return;
    }
    this.emitEffect({ type: 'restore_window_brightness' });
  }

  private emitToast(message: string): void {
    this.emitEffect({
      type: 'toast',
      message: message
    });
  }

  private emitEffect(effect: ReaderModeEffect): void {
    if (this.effectApplication !== undefined) {
      this.effectApplication.apply(effect);
      return;
    }
    this.sessionListener?.onEffect?.(effect);
  }

  private buildExtractionFailureMessage(article: ReaderModeArticle): string {
    const diagnostics = article.diagnostics;
    if (diagnostics === undefined) {
      return '没有整理出可阅读的正文。';
    }
    return `没有整理出可阅读的正文。诊断：${diagnostics.extractionStrategy}，文本 ${diagnostics.sourceTextLength}，候选 ${diagnostics.candidateCount}`;
  }

  private buildOpenDiagnosticText(article: ReaderModeArticle, readable: boolean, reason: string): string {
    const diagnostics = article.diagnostics;
    const summary = diagnostics?.postProcessSummary ?? '';
    return `blocks=${article.blocks.length} readable=${readable} reason=${reason} ${summary}`;
  }

  private resolveVisibleActiveController(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    webPageVisible: boolean
  ): webview.WebviewController | undefined {
    if (!webPageVisible) {
      return undefined;
    }
    return runtimeLifecyclePort.resolveActiveController();
  }
}

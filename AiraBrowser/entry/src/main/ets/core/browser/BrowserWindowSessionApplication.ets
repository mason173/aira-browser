import {
  BrowserRuntimeSessionPort,
  BrowserSessionCoordinator
} from './BrowserSessionCoordinator';
import { BrowserRuntimeLifecycleCoordinator } from './BrowserRuntimeLifecycleCoordinator';
import {
  BrowserTabBackgroundManagerCoordinator,
  BrowserTabBackgroundSessionSyncRequest,
  BrowserTabBackgroundSessionSyncResult
} from './BrowserTabBackgroundManagerCoordinator';
import {
  BrowserTabBackgroundWindowStateCoordinator,
  BrowserTabBackgroundWindowTransitionResult
} from './BrowserTabBackgroundWindowStateCoordinator';
import { BrowserTabWindowState } from './BrowserTabBackgroundTypes';
import {
  BrowserWindowSuspendedContext
} from './BrowserWindowContextState';
import {
  BrowserShellFamilyAvailability,
  BrowserWindowPresentationProfile,
  BrowserWindowPresentationProfileCoordinator,
  BrowserWindowPresentationProfileInput
} from './BrowserWindowPresentationProfile';
import { BrowserShellAdapterCatalogSnapshot } from './BrowserShellAdapterCatalog';
import { BrowserLargeScreenPresentationFacts } from './BrowserLargeScreenPresentationViewModel';
import {
  BrowserLargeScreenWindowFactsInput,
  BrowserLargeScreenWindowFactsPolicy,
  BrowserLargeScreenWindowFactsSnapshot,
  BrowserLargeScreenWindowFactsViewModel
} from './BrowserLargeScreenWindowFactsViewModel';
import {
  BrowserShellPresentationCoordinator,
  BrowserShellPresentationReconcileResult,
  BrowserShellPresentationSnapshot,
  BrowserShellPresentationSurface
} from './BrowserShellPresentationCoordinator';
import {
  BrowserWindowSessionContextBinding,
  BrowserWindowSessionContextComposition,
  BrowserWindowSessionContextOperations,
  BrowserWindowSessionContextOperationsImplementation,
  registerBrowserWindowSessionContextOperations,
  unregisterBrowserWindowSessionContextOperations
} from './BrowserWindowSessionContextApplication';
import {
  BrowserWindowSessionContextStateBinding,
  BrowserWindowSessionContextStateStore,
  registerBrowserWindowSessionContextStateStore,
  unregisterBrowserWindowSessionContextStateStore
} from './BrowserWindowSessionContextState';
import {
  BrowserCreateTabOptions,
  BrowserTabManagerPort,
  BrowserTabMutationResult,
  BrowserTabRestoreResult,
  BrowserTabRuntimePatch,
  BrowserTabState,
  BrowserTerminalBackPlan,
  TabManager
} from '../tabs/TabManager';
import {
  BrowserResolvedThemeMode,
  ReaderModeTheme,
  TabRecord,
  TabRuntimeState
} from '../../common/models/BrowserModels';
import { webview } from '@kit.ArkWeb';
import {
  NovelReaderBookshelfCacheOpenRequest,
  NovelReaderOpenRequest,
  NovelReaderController,
  NovelReaderControllerOptions,
  NovelReaderSessionConnection,
  NovelReaderSessionOperations,
  NovelReaderTakeoverPreviewCapturePort
} from '../../features/novel/NovelReaderController';
import {
  createDefaultNovelReaderSnapshot,
  NovelReaderAction,
  NovelReaderPageReadyFacts,
  NovelReaderSessionListener,
  NovelReaderSnapshot
} from '../../features/novel/NovelReaderModels';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { sharedBrowserWindowSessionLifetimeSignal } from './BrowserWindowSessionLifetimeSignal';
import { NovelReaderPreferencesRepository } from '../../data/novel/NovelReaderPreferencesRepository';
import {
  sharedNovelReadingCheckpointRepository
} from '../../data/novel/NovelReadingCheckpointRepository';
import { NovelReaderSessionCoordinator } from './NovelReaderSessionCoordinator';
import {
  NovelReadingRecoveryMarkerRepository
} from '../../data/novel/NovelReadingRecoveryMarkerRepository';
import { sharedNovelLibraryRepository } from '../../data/novel/NovelLibraryRepository';
import { sharedNovelCatalogCacheRepository } from '../../data/novel/NovelCatalogCacheRepository';
import {
  sharedNovelChapterArtifactCacheRepository
} from '../../data/novel/NovelChapterArtifactCacheRepository';
import {
  ArticleReadingSessionConnection,
  ArticleReadingSessionOperations,
  createDefaultReaderModeSessionSnapshot,
  ReaderModeActionContext,
  ReaderModeCoordinator,
  ReaderModeEffectApplication,
  ReaderModeSessionListener,
  ReaderModeSessionOpenOutcome,
  ReaderModeSessionSnapshot,
  ReaderSpeechPlayerAction
} from './ReaderModeCoordinator';
import {
  ReaderModeAction,
  ReaderModeArticle
} from '../../features/reader/ReaderModeModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

export interface BrowserWindowPresentationReconcileResult {
  profile: BrowserWindowPresentationProfile;
  presentationChanged: boolean;
}

export class BrowserWindowSessionRuntimeBinding {
}

export class BrowserWindowSessionTabManagerBinding {
}

export class BrowserWindowSessionBackgroundBinding {
}

export class BrowserWindowSessionShellPresentationBinding {
}

export class BrowserWindowSessionNovelReaderBinding {
}

export class BrowserWindowSessionArticleReadingBinding {
}

function createNovelReaderController(): NovelReaderController {
  const options: NovelReaderControllerOptions = new NovelReaderControllerOptions();
  options.preferencesRepository = new NovelReaderPreferencesRepository();
  options.checkpointRepository = sharedNovelReadingCheckpointRepository;
  options.libraryRepository = sharedNovelLibraryRepository;
  options.catalogCacheRepository = sharedNovelCatalogCacheRepository;
  options.chapterArtifactCacheRepository = sharedNovelChapterArtifactCacheRepository;
  return new NovelReaderController(options);
}

function createNovelReaderSessionCoordinator(
  windowId: string,
  preferencesRepository?: PreferencesRepository
): NovelReaderSessionCoordinator {
  return new NovelReaderSessionCoordinator(
    createNovelReaderController(),
    createNovelReaderController(),
    (): NovelReaderController => createNovelReaderController(),
    new NovelReadingRecoveryMarkerRepository(windowId),
    preferencesRepository
  );
}

function createArticleReadingCoordinator(
  preferencesRepository?: PreferencesRepository
): ReaderModeCoordinator {
  return new ReaderModeCoordinator({ preferencesRepository: preferencesRepository });
}

class BrowserWindowSessionContextStateStoreImplementation implements BrowserWindowSessionContextStateStore {
  private readonly contextsByWindowId: Record<string, BrowserWindowSuspendedContext | undefined> = {};
  private readonly isSessionAvailable: () => boolean;

  constructor(isSessionAvailable: () => boolean) {
    this.isSessionAvailable = isSessionAvailable;
  }

  isAvailable(): boolean {
    return this.isSessionAvailable();
  }

  getSuspendedContexts(): Record<string, BrowserWindowSuspendedContext | undefined> {
    const result: Record<string, BrowserWindowSuspendedContext | undefined> = {};
    if (!this.isAvailable()) {
      return result;
    }
    Object.keys(this.contextsByWindowId).forEach((windowId: string) => {
      const context = this.contextsByWindowId[windowId];
      result[windowId] = context === undefined ? undefined : this.copyContext(context);
    });
    return result;
  }

  setSuspendedContext(windowId: string, context: BrowserWindowSuspendedContext): void {
    if (!this.isAvailable()) {
      return;
    }
    this.contextsByWindowId[windowId] = this.copyContext(context);
  }

  takeSuspendedContext(windowId: string): BrowserWindowSuspendedContext | undefined {
    if (!this.isAvailable()) {
      return undefined;
    }
    const context = this.contextsByWindowId[windowId];
    this.contextsByWindowId[windowId] = undefined;
    return context === undefined ? undefined : this.copyContext(context);
  }

  private copyContext(context: BrowserWindowSuspendedContext): BrowserWindowSuspendedContext {
    return {
      tabs: context.tabs.slice(),
      activeTabId: context.activeTabId,
      tabSequence: context.tabSequence,
      showHomePage: context.showHomePage
    };
  }
}

const runtimeBindings: Map<BrowserWindowSessionRuntimeBinding, BrowserRuntimeSessionPort> = new Map();
const runtimeLifecycleBindings: Map<BrowserWindowSessionRuntimeBinding,
  BrowserRuntimeLifecycleCoordinator> = new Map();
const tabManagerBindings: Map<BrowserWindowSessionTabManagerBinding, BrowserTabManagerPort> = new Map();
const backgroundBindings: Map<BrowserWindowSessionBackgroundBinding,
  BrowserWindowSessionBackgroundOperations> = new Map();
const shellPresentationBindings: Map<BrowserWindowSessionShellPresentationBinding,
  BrowserWindowSessionShellPresentationOperations> = new Map();
const novelReaderBindings: Map<BrowserWindowSessionNovelReaderBinding,
  NovelReaderSessionOperations> = new Map();
const articleReadingBindings: Map<BrowserWindowSessionArticleReadingBinding,
  ArticleReadingSessionOperations> = new Map();

export function resolveBrowserWindowSessionRuntimeBinding(
  binding: BrowserWindowSessionRuntimeBinding | undefined
): BrowserRuntimeSessionPort | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return runtimeBindings.get(binding);
}

export function resolveBrowserWindowSessionRuntimeLifecycleBinding(
  binding: BrowserWindowSessionRuntimeBinding | undefined
): BrowserRuntimeLifecycleCoordinator | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return runtimeLifecycleBindings.get(binding);
}

export function resolveBrowserWindowSessionNovelReaderBinding(
  binding: BrowserWindowSessionNovelReaderBinding | undefined
): NovelReaderSessionOperations | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return novelReaderBindings.get(binding);
}

export function resolveBrowserWindowSessionArticleReadingBinding(
  binding: BrowserWindowSessionArticleReadingBinding | undefined
): ArticleReadingSessionOperations | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return articleReadingBindings.get(binding);
}

/** Shell-facing capability adapter; Novel policy and lifetime remain in the Window Session owner. */
export class BrowserWindowSessionNovelReaderPort implements NovelReaderSessionOperations {
  private binding?: BrowserWindowSessionNovelReaderBinding;
  private listenerConnection?: NovelReaderSessionConnection;
  private takeoverPreviewConnection?: NovelReaderSessionConnection;

  connect(binding: BrowserWindowSessionNovelReaderBinding | undefined): void {
    this.disconnect();
    this.binding = binding;
  }

  disconnect(): void {
    this.listenerConnection?.disconnect();
    this.listenerConnection = undefined;
    this.takeoverPreviewConnection?.disconnect();
    this.takeoverPreviewConnection = undefined;
    this.binding = undefined;
  }

  connectSessionListener(listener: NovelReaderSessionListener): NovelReaderSessionConnection {
    this.listenerConnection?.disconnect();
    const connection = this.resolveOperations()?.connectSessionListener(listener) ??
      new BrowserWindowSessionNovelReaderDisconnectedConnection();
    this.listenerConnection = connection;
    return connection;
  }

  getSnapshot(): NovelReaderSnapshot {
    return this.resolveOperations()?.getSnapshot() ?? createDefaultNovelReaderSnapshot();
  }

  shouldHandleSpaRouteReprobe(): boolean {
    return this.resolveOperations()?.shouldHandleSpaRouteReprobe() ?? false;
  }

  reconcileReentryForPageReady(facts: NovelReaderPageReadyFacts): void {
    this.resolveOperations()?.reconcileReentryForPageReady(facts);
  }

  handlePageReadyForAutoDetection(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void {
    this.resolveOperations()?.handlePageReadyForAutoDetection(runtimeLifecyclePort, facts);
  }

  async openFromLifecyclePort(request: NovelReaderOpenRequest): Promise<void> {
    await this.resolveOperations()?.openFromLifecyclePort(request);
  }

  async openBookshelfFromPersistentCache(
    request: NovelReaderBookshelfCacheOpenRequest
  ): Promise<boolean> {
    return await this.resolveOperations()?.openBookshelfFromPersistentCache(request) ?? false;
  }

  connectTakeoverPreviewCapture(
    port?: NovelReaderTakeoverPreviewCapturePort
  ): NovelReaderSessionConnection {
    this.takeoverPreviewConnection?.disconnect();
    const connection = this.resolveOperations()?.connectTakeoverPreviewCapture(port) ??
      new BrowserWindowSessionNovelReaderDisconnectedConnection();
    this.takeoverPreviewConnection = connection;
    return connection;
  }

  handleAction(action: NovelReaderAction): void {
    this.resolveOperations()?.handleAction(action);
  }

  close(): void {
    this.resolveOperations()?.close();
  }

  private resolveOperations(): NovelReaderSessionOperations | undefined {
    return resolveBrowserWindowSessionNovelReaderBinding(this.binding);
  }
}

class BrowserWindowSessionNovelReaderDisconnectedConnection implements NovelReaderSessionConnection {
  disconnect(): void {
  }
}

/** Shell-facing adapter; Article acquisition and reading state remain owned by the Window Session. */
export class BrowserWindowSessionArticleReadingPort implements ArticleReadingSessionOperations {
  private binding?: BrowserWindowSessionArticleReadingBinding;
  private listenerConnection?: ArticleReadingSessionConnection;

  connect(binding: BrowserWindowSessionArticleReadingBinding | undefined): void {
    this.disconnect();
    this.binding = binding;
  }

  disconnect(): void {
    this.listenerConnection?.disconnect();
    this.listenerConnection = undefined;
    this.resolveOperations()?.setEffectApplication(undefined);
    this.binding = undefined;
  }

  connectSessionListener(listener: ReaderModeSessionListener): ArticleReadingSessionConnection {
    this.listenerConnection?.disconnect();
    const connection: ArticleReadingSessionConnection = this.resolveOperations()?.connectSessionListener(listener) ??
      new BrowserWindowSessionArticleReadingDisconnectedConnection();
    this.listenerConnection = connection;
    return connection;
  }

  setEffectApplication(application: ReaderModeEffectApplication | undefined): void {
    this.resolveOperations()?.setEffectApplication(application);
  }

  getSessionSnapshot(): ReaderModeSessionSnapshot {
    return this.resolveOperations()?.getSessionSnapshot() ?? createDefaultReaderModeSessionSnapshot();
  }

  resolveEffectiveTheme(systemTheme: BrowserResolvedThemeMode): ReaderModeTheme {
    return this.resolveOperations()?.resolveEffectiveTheme(systemTheme) ?? systemTheme;
  }

  loadPreferences(): void {
    this.resolveOperations()?.loadPreferences();
  }

  handleAction(action: ReaderModeAction, context: ReaderModeActionContext): void {
    this.resolveOperations()?.handleAction(action, context);
  }

  handleSpeechPlayerAction(action: ReaderSpeechPlayerAction, openVoicePicker: () => void): void {
    this.resolveOperations()?.handleSpeechPlayerAction(action, openVoicePicker);
  }

  async openSessionFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    webPageVisible: boolean,
    pageUrl: string,
    tabId: string
  ): Promise<void> {
    await this.resolveOperations()?.openSessionFromLifecyclePort(
      runtimeLifecyclePort,
      webPageVisible,
      pageUrl,
      tabId
    );
  }

  async openSessionFromController(
    controller: webview.WebviewController,
    pageUrl: string
  ): Promise<ReaderModeSessionOpenOutcome> {
    return await this.resolveOperations()?.openSessionFromController(controller, pageUrl) ?? 'stale';
  }

  openSessionFromArticle(article: ReaderModeArticle, pageUrl: string): ReaderModeSessionOpenOutcome {
    return this.resolveOperations()?.openSessionFromArticle(article, pageUrl) ?? 'stale';
  }

  requestImagePreviewDismissal(): void {
    this.resolveOperations()?.requestImagePreviewDismissal();
  }

  requestPanelDismissal(): void {
    this.resolveOperations()?.requestPanelDismissal();
  }

  beginExitConfirmation(): boolean {
    return this.resolveOperations()?.beginExitConfirmation() ?? false;
  }

  endExitConfirmation(): void {
    this.resolveOperations()?.endExitConfirmation();
  }

  closeSession(): void {
    this.resolveOperations()?.closeSession();
  }

  resolveCurrentUrl(fallbackUrl: string = ''): string {
    return this.resolveOperations()?.resolveCurrentUrl(fallbackUrl) ?? fallbackUrl.trim();
  }

  async toggleSpeech(): Promise<void> {
    await this.resolveOperations()?.toggleSpeech();
  }

  async playPreviousSpeechChunk(): Promise<void> {
    await this.resolveOperations()?.playPreviousSpeechChunk();
  }

  async playNextSpeechChunk(): Promise<void> {
    await this.resolveOperations()?.playNextSpeechChunk();
  }

  async replayCurrentSpeechChunk(): Promise<void> {
    await this.resolveOperations()?.replayCurrentSpeechChunk();
  }

  async changeSpeechSpeed(speed: number): Promise<void> {
    await this.resolveOperations()?.changeSpeechSpeed(speed);
  }

  openSpeechVoicePicker(systemTheme: BrowserResolvedThemeMode): void {
    this.resolveOperations()?.openSpeechVoicePicker(systemTheme);
  }

  async selectSpeechVoiceById(voiceId: string): Promise<void> {
    await this.resolveOperations()?.selectSpeechVoiceById(voiceId);
  }

  resetSpeechVoicePickerState(): void {
    this.resolveOperations()?.resetSpeechVoicePickerState();
  }

  locateSpeechChunkInReader(): void {
    this.resolveOperations()?.locateSpeechChunkInReader();
  }

  dismissSpeechPlayerPresentation(): void {
    this.resolveOperations()?.dismissSpeechPlayerPresentation();
  }

  resetSpeechPlayerPresentation(): void {
    this.resolveOperations()?.resetSpeechPlayerPresentation();
  }

  resetSpeechAfterLifecycleResume(): void {
    this.resolveOperations()?.resetSpeechAfterLifecycleResume();
  }

  shutdownSpeechSession(): void {
    this.resolveOperations()?.shutdownSpeechSession();
  }

  private resolveOperations(): ArticleReadingSessionOperations | undefined {
    return resolveBrowserWindowSessionArticleReadingBinding(this.binding);
  }
}

class BrowserWindowSessionArticleReadingDisconnectedConnection implements ArticleReadingSessionConnection {
  disconnect(): void {
  }
}

export function resolveBrowserWindowSessionTabManagerBinding(
  binding: BrowserWindowSessionTabManagerBinding | undefined
): BrowserTabManagerPort | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return tabManagerBindings.get(binding);
}

/**
 * Page-facing adapter for the Window Session tab owner. The concrete
 * TabManager is created and retained by BrowserWindowSessionApplication; this
 * object forwards only the shaped tab capability surface captured at connect
 * time and becomes inert after Session release.
 */
export class BrowserWindowSessionTabManagerPort extends TabManager implements BrowserTabManagerPort {
  private operations?: BrowserTabManagerPort;

  constructor() {
    super();
  }

  connect(binding: BrowserWindowSessionTabManagerBinding | undefined): void {
    this.operations = resolveBrowserWindowSessionTabManagerBinding(binding);
  }

  disconnect(): void {
    this.operations = undefined;
  }

  isConnected(): boolean {
    return this.operations !== undefined;
  }

  private resolveOperations(): BrowserTabManagerPort | undefined {
    return this.operations;
  }

  setWindowId(windowId: string): void {
    this.resolveOperations()?.setWindowId(windowId);
  }

  createBootstrapTab(options: BrowserCreateTabOptions = {}): TabRecord {
    return this.resolveOperations()?.createBootstrapTab(options) ?? {
      id: '',
      windowId: '',
      title: '',
      url: 'aira://home',
      isActive: false,
      isPinned: false,
      lastActiveAt: 0
    };
  }

  createWindowHomeTab(timestamp: number = Date.now(), options: BrowserCreateTabOptions = {}): BrowserTabState {
    return this.resolveOperations()?.createWindowHomeTab(timestamp, options) ??
      this.buildDisconnectedTabState('', timestamp, options);
  }

  createHomeTab(
    id: string,
    timestamp: number = Date.now(),
    options: BrowserCreateTabOptions = {}
  ): BrowserTabState {
    return this.resolveOperations()?.createHomeTab(id, timestamp, options) ??
      this.buildDisconnectedTabState(id, timestamp, options);
  }

  createTab(
    tabs: BrowserTabState[],
    tabSequence: number,
    initialUrl: string = 'aira://home',
    initialTitle: string = '新标签页',
    options: BrowserCreateTabOptions = {}
  ): BrowserTabMutationResult {
    return this.resolveOperations()?.createTab(tabs, tabSequence, initialUrl, initialTitle, options) ?? {
      tabs: tabs,
      activeTabId: '',
      tabSequence: tabSequence
    };
  }

  createBackgroundTab(
    tabs: BrowserTabState[],
    activeTabId: string,
    tabSequence: number,
    initialUrl: string = 'aira://home',
    initialTitle: string = '新标签页',
    options: BrowserCreateTabOptions = {}
  ): BrowserTabMutationResult {
    return this.resolveOperations()?.createBackgroundTab(
      tabs,
      activeTabId,
      tabSequence,
      initialUrl,
      initialTitle,
      options
    ) ?? {
      tabs: tabs,
      activeTabId: activeTabId,
      tabSequence: tabSequence
    };
  }

  switchToTab(tabs: BrowserTabState[], activeTabId: string, targetTabId: string): BrowserTabMutationResult {
    return this.resolveOperations()?.switchToTab(tabs, activeTabId, targetTabId) ?? {
      tabs: tabs,
      activeTabId: activeTabId,
      tabSequence: 0
    };
  }

  closeTab(tabs: BrowserTabState[], activeTabId: string, targetTabId: string): BrowserTabMutationResult {
    return this.resolveOperations()?.closeTab(tabs, activeTabId, targetTabId) ?? {
      tabs: tabs,
      activeTabId: activeTabId,
      tabSequence: 0
    };
  }

  buildTerminalBackPlan(tabs: BrowserTabState[], activeTabId: string): BrowserTerminalBackPlan {
    return this.resolveOperations()?.buildTerminalBackPlan(tabs, activeTabId) ?? {
      kind: 'missing_active',
      remainingTabCount: tabs.length
    };
  }

  closeActiveTabToHome(tabs: BrowserTabState[], activeTabId: string): BrowserTabMutationResult {
    return this.resolveOperations()?.closeActiveTabToHome(tabs, activeTabId) ?? {
      tabs: tabs,
      activeTabId: activeTabId,
      tabSequence: 0
    };
  }

  closeTabsToHome(
    tabs: BrowserTabState[],
    activeTabId: string,
    targetTabIds: string[]
  ): BrowserTabMutationResult {
    return this.resolveOperations()?.closeTabsToHome(tabs, activeTabId, targetTabIds) ?? {
      tabs: tabs,
      activeTabId: activeTabId,
      tabSequence: 0
    };
  }

  markActiveTabAsHome(tabs: BrowserTabState[], activeTabId: string): BrowserTabState[] {
    return this.resolveOperations()?.markActiveTabAsHome(tabs, activeTabId) ?? tabs;
  }

  updateActiveTab(tabs: BrowserTabState[], activeTabId: string, patch: BrowserTabRuntimePatch): BrowserTabState[] {
    return this.resolveOperations()?.updateActiveTab(tabs, activeTabId, patch) ?? tabs;
  }

  updateTab(tabs: BrowserTabState[], targetTabId: string, patch: BrowserTabRuntimePatch): BrowserTabState[] {
    return this.resolveOperations()?.updateTab(tabs, targetTabId, patch) ?? tabs;
  }

  recordActiveNavigation(tabs: BrowserTabState[], activeTabId: string, url: string, title?: string): BrowserTabState[] {
    return this.resolveOperations()?.recordActiveNavigation(tabs, activeTabId, url, title) ?? tabs;
  }

  recordNavigationForTab(tabs: BrowserTabState[], targetTabId: string, url: string, title?: string): BrowserTabState[] {
    return this.resolveOperations()?.recordNavigationForTab(tabs, targetTabId, url, title) ?? tabs;
  }

  restoreTabs(records: TabRecord[], emptyStateOptions: BrowserCreateTabOptions = {}): BrowserTabRestoreResult {
    return this.resolveOperations()?.restoreTabs(records, emptyStateOptions) ?? {
      tabs: [],
      activeTabId: '',
      tabSequence: 1
    };
  }

  serializeTabs(tabs: BrowserTabState[], activeTabId: string): TabRecord[] {
    return this.resolveOperations()?.serializeTabs(tabs, activeTabId) ?? [];
  }

  getActiveTab(tabs: BrowserTabState[], activeTabId: string): BrowserTabState | undefined {
    return this.resolveOperations()?.getActiveTab(tabs, activeTabId);
  }

  getTab(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return this.resolveOperations()?.getTab(tabs, tabId);
  }

  applyRuntimeStates(tabs: BrowserTabState[], states: Record<string, TabRuntimeState>): BrowserTabState[] {
    return this.resolveOperations()?.applyRuntimeStates(tabs, states) ?? tabs;
  }

  setTabPinned(tabs: BrowserTabState[], targetTabId: string, pinned: boolean): BrowserTabState[] {
    return this.resolveOperations()?.setTabPinned(tabs, targetTabId, pinned) ?? tabs;
  }

  private buildDisconnectedTabState(
    id: string,
    timestamp: number,
    options: BrowserCreateTabOptions
  ): BrowserTabState {
    const isPrivate = options.privacyMode === 'private';
    return {
      id: id,
      profileId: 'profile-main',
      title: '新标签页',
      url: 'aira://home',
      isHome: true,
      lastActiveAt: timestamp,
      pendingUrl: '',
      navigationHistory: [],
      navigationIndex: -1,
      runtimeState: 'active',
      lastError: '',
      lastRestoreReason: '',
      lastDiscardReason: '',
      lastCrashReason: '',
      lastLoadedAt: timestamp,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: '',
      lastGoodTitle: '',
      lastRestorableUrl: '',
      lastRestorableTitle: '',
      lastRestoreType: 'none',
      privacyMode: isPrivate ? 'private' : 'regular',
      dataScope: isPrivate ? 'session_ephemeral' : 'profile_persistent',
      launchContext: {
        sourceType: '',
        sourceId: '',
        sourceUrl: '',
        key: ''
      },
      openerTabId: options.openerTabId ?? '',
      openSource: options.openSource ?? '',
      openedByNewWindow: options.openedByNewWindow === true,
      pinned: false,
      muted: false,
      audible: false
    };
  }
}

export interface BrowserWindowSessionShellPresentationOperations {
  isAvailable(): boolean;
  surface(): BrowserShellPresentationSurface | undefined;
  snapshot(): BrowserShellPresentationSnapshot | undefined;
  reconcileTabs(tabs: BrowserTabState[], activeTabId: string): BrowserShellPresentationSnapshot | undefined;
}

class BrowserWindowSessionShellPresentationOperationsImplementation
  implements BrowserWindowSessionShellPresentationOperations {
  private readonly isSessionAvailable: () => boolean;
  private readonly resolveSnapshot: () => BrowserShellPresentationSnapshot | undefined;
  private readonly reconcileTabPresentation:
    (tabs: BrowserTabState[], activeTabId: string) => BrowserShellPresentationSnapshot | undefined;

  constructor(
    isSessionAvailable: () => boolean,
    resolveSnapshot: () => BrowserShellPresentationSnapshot | undefined,
    reconcileTabPresentation:
      (tabs: BrowserTabState[], activeTabId: string) => BrowserShellPresentationSnapshot | undefined
  ) {
    this.isSessionAvailable = isSessionAvailable;
    this.resolveSnapshot = resolveSnapshot;
    this.reconcileTabPresentation = reconcileTabPresentation;
  }

  isAvailable(): boolean {
    return this.isSessionAvailable();
  }

  surface(): BrowserShellPresentationSurface | undefined {
    return this.snapshot()?.surface;
  }

  snapshot(): BrowserShellPresentationSnapshot | undefined {
    if (!this.isAvailable()) {
      return undefined;
    }
    return this.resolveSnapshot();
  }

  reconcileTabs(tabs: BrowserTabState[], activeTabId: string): BrowserShellPresentationSnapshot | undefined {
    if (!this.isAvailable()) {
      return undefined;
    }
    return this.reconcileTabPresentation(tabs, activeTabId);
  }
}

export function resolveBrowserWindowSessionShellPresentationBinding(
  binding: BrowserWindowSessionShellPresentationBinding | undefined
): BrowserWindowSessionShellPresentationOperations | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return shellPresentationBindings.get(binding);
}

export interface BrowserWindowSessionBackgroundOperations {
  runSessionSync(request: BrowserTabBackgroundSessionSyncRequest): BrowserTabBackgroundSessionSyncResult | undefined;
  markAppForeground(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined;
  markAppBackground(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined;
  markWindowActive(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined;
  markWindowHidden(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined;
  buildWindowState(windowId: string): BrowserTabWindowState | undefined;
}

class BrowserWindowSessionBackgroundOperationsImplementation implements BrowserWindowSessionBackgroundOperations {
  private readonly backgroundManager: BrowserTabBackgroundManagerCoordinator =
    new BrowserTabBackgroundManagerCoordinator();
  private readonly windowStateCoordinator: BrowserTabBackgroundWindowStateCoordinator =
    new BrowserTabBackgroundWindowStateCoordinator();
  private readonly isSessionAvailable: () => boolean;

  constructor(isSessionAvailable: () => boolean) {
    this.isSessionAvailable = isSessionAvailable;
  }

  runSessionSync(request: BrowserTabBackgroundSessionSyncRequest): BrowserTabBackgroundSessionSyncResult | undefined {
    if (!this.isSessionAvailable()) {
      return undefined;
    }
    return this.backgroundManager.runSessionSync(request);
  }

  markAppForeground(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined {
    return this.isSessionAvailable() ? this.windowStateCoordinator.markAppForeground(windowId) : undefined;
  }

  markAppBackground(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined {
    return this.isSessionAvailable() ? this.windowStateCoordinator.markAppBackground(windowId) : undefined;
  }

  markWindowActive(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined {
    return this.isSessionAvailable() ? this.windowStateCoordinator.markWindowActive(windowId) : undefined;
  }

  markWindowHidden(windowId: string): BrowserTabBackgroundWindowTransitionResult | undefined {
    return this.isSessionAvailable() ? this.windowStateCoordinator.markWindowHidden(windowId) : undefined;
  }

  buildWindowState(windowId: string): BrowserTabWindowState | undefined {
    return this.isSessionAvailable() ? this.windowStateCoordinator.buildWindowState(windowId) : undefined;
  }
}

export function resolveBrowserWindowSessionBackgroundBinding(
  binding: BrowserWindowSessionBackgroundBinding | undefined
): BrowserWindowSessionBackgroundOperations | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return backgroundBindings.get(binding);
}

export interface BrowserWindowSessionSeed {
  windowId: string;
  articleReadingPreferencesRepository?: PreferencesRepository;
}

export interface BrowserWindowSessionLifetimeFacts {
  windowId: string;
  revision: number;
  foreground: boolean;
}

/**
 * Owns composition and lifetime for one browser window.
 *
 * Narrative browser owners remain subordinate modules. The Shell presentation
 * connection selects registered adapters without absorbing their UI trees or
 * the browser business owners behind them.
 */
export class BrowserWindowSessionApplication {
  private readonly windowId: string;
  private readonly tabManager: TabManager;
  private lifetimeRevision: number = 0;
  private foreground: boolean = false;
  private released: boolean = false;
  private readonly browserSessionCoordinator: BrowserSessionCoordinator = new BrowserSessionCoordinator();
  private readonly browserRuntimeLifecycleCoordinator: BrowserRuntimeLifecycleCoordinator =
    new BrowserRuntimeLifecycleCoordinator();
  private readonly runtimeSessionBinding: BrowserWindowSessionRuntimeBinding =
    new BrowserWindowSessionRuntimeBinding();
  private readonly tabManagerBinding: BrowserWindowSessionTabManagerBinding =
    new BrowserWindowSessionTabManagerBinding();
  private readonly contextStateBinding: BrowserWindowSessionContextStateBinding =
    new BrowserWindowSessionContextStateBinding();
  private contextBinding?: BrowserWindowSessionContextBinding;
  private readonly backgroundBinding: BrowserWindowSessionBackgroundBinding =
    new BrowserWindowSessionBackgroundBinding();
  private readonly shellPresentationBinding: BrowserWindowSessionShellPresentationBinding =
    new BrowserWindowSessionShellPresentationBinding();
  private readonly novelReaderBinding: BrowserWindowSessionNovelReaderBinding =
    new BrowserWindowSessionNovelReaderBinding();
  private readonly novelReaderSessionCoordinator: NovelReaderSessionCoordinator;
  private readonly articleReadingBinding: BrowserWindowSessionArticleReadingBinding =
    new BrowserWindowSessionArticleReadingBinding();
  private readonly articleReadingCoordinator: ReaderModeCoordinator;
  private readonly presentationProfileCoordinator: BrowserWindowPresentationProfileCoordinator =
    new BrowserWindowPresentationProfileCoordinator();
  private readonly shellPresentationCoordinator: BrowserShellPresentationCoordinator =
    new BrowserShellPresentationCoordinator();
  private readonly largeScreenWindowFactsViewModel: BrowserLargeScreenWindowFactsViewModel =
    new BrowserLargeScreenWindowFactsViewModel();
  private readonly contextStateStore: BrowserWindowSessionContextStateStore =
    new BrowserWindowSessionContextStateStoreImplementation((): boolean => !this.released);
  private contextOperations?: BrowserWindowSessionContextOperations;
  private readonly backgroundOperations: BrowserWindowSessionBackgroundOperations =
    new BrowserWindowSessionBackgroundOperationsImplementation((): boolean => !this.released);
  private readonly shellPresentationOperations: BrowserWindowSessionShellPresentationOperations =
    new BrowserWindowSessionShellPresentationOperationsImplementation(
      (): boolean => !this.released,
      (): BrowserShellPresentationSnapshot | undefined => this.shellPresentationCoordinator.snapshot(),
      (tabs: BrowserTabState[], activeTabId: string): BrowserShellPresentationSnapshot | undefined => {
        const activeTab = tabs.find((tab: BrowserTabState): boolean => tab.id === activeTabId);
        this.novelReaderSessionCoordinator.reconcileWindowState(
          activeTab?.privacyMode === 'private' ? 'private' : 'regular',
          activeTabId,
          tabs.map((tab: BrowserTabState): string => tab.id),
          this.browserSessionCoordinator.getRuntime(activeTabId)?.controller
        );
        return this.shellPresentationCoordinator.reconcileLargeScreenTabs(tabs, activeTabId);
      }
    );
  private readonly runtimeSessionPort: BrowserRuntimeSessionPort = new BrowserRuntimeSessionPort(
    this.browserSessionCoordinator,
    (): boolean => !this.released
  );

  constructor(seed: BrowserWindowSessionSeed) {
    const normalizedWindowId = seed.windowId.trim();
    if (normalizedWindowId.length === 0) {
      throw new Error('Browser Window Session requires a windowId.');
    }
    this.windowId = normalizedWindowId;
    this.novelReaderSessionCoordinator = createNovelReaderSessionCoordinator(
      normalizedWindowId,
      seed.articleReadingPreferencesRepository
    );
    this.tabManager = new TabManager('aira://home', normalizedWindowId);
    this.articleReadingCoordinator = createArticleReadingCoordinator(seed.articleReadingPreferencesRepository);
    runtimeBindings.set(this.runtimeSessionBinding, this.runtimeSessionPort);
    runtimeLifecycleBindings.set(this.runtimeSessionBinding, this.browserRuntimeLifecycleCoordinator);
    tabManagerBindings.set(this.tabManagerBinding, this.tabManager);
    registerBrowserWindowSessionContextStateStore(this.contextStateBinding, this.contextStateStore);
    backgroundBindings.set(this.backgroundBinding, this.backgroundOperations);
    shellPresentationBindings.set(this.shellPresentationBinding, this.shellPresentationOperations);
    novelReaderBindings.set(this.novelReaderBinding, this.novelReaderSessionCoordinator);
    articleReadingBindings.set(this.articleReadingBinding, this.articleReadingCoordinator);
  }

  reconcileLifetime(facts: BrowserWindowSessionLifetimeFacts): void {
    if (this.released || facts.windowId !== this.windowId || facts.revision <= this.lifetimeRevision) {
      return;
    }
    this.lifetimeRevision = facts.revision;
    if (this.foreground === facts.foreground) {
      return;
    }
    this.foreground = facts.foreground;
    sharedBrowserWindowSessionLifetimeSignal.reconcile(this.windowId, facts.foreground);
  }

  createRuntimeSessionBinding(): BrowserWindowSessionRuntimeBinding {
    return this.runtimeSessionBinding;
  }

  createTabManagerBinding(): BrowserWindowSessionTabManagerBinding {
    return this.tabManagerBinding;
  }

  createContextStateBinding(): BrowserWindowSessionContextStateBinding {
    return this.contextStateBinding;
  }

  createWindowContextBinding(): BrowserWindowSessionContextBinding | undefined {
    return this.contextBinding;
  }

  consumePendingLaunch(source: string): boolean {
    if (this.released) {
      return false;
    }
    return this.contextOperations?.consumePendingLaunch(source) ?? false;
  }

  connectWindowContext(composition: BrowserWindowSessionContextComposition): BrowserWindowSessionContextBinding | undefined {
    if (this.released) {
      return undefined;
    }
    this.disconnectWindowContext();
    const binding = new BrowserWindowSessionContextBinding();
    const operations = new BrowserWindowSessionContextOperationsImplementation((): boolean => !this.released);
    operations.connect(composition);
    this.contextBinding = binding;
    this.contextOperations = operations;
    registerBrowserWindowSessionContextOperations(binding, operations);
    return binding;
  }

  disconnectWindowContext(): void {
    const binding = this.contextBinding;
    this.contextOperations?.disconnect();
    if (binding !== undefined) {
      unregisterBrowserWindowSessionContextOperations(binding);
    }
    this.contextBinding = undefined;
    this.contextOperations = undefined;
  }

  createBackgroundBinding(): BrowserWindowSessionBackgroundBinding {
    return this.backgroundBinding;
  }

  createShellPresentationBinding(): BrowserWindowSessionShellPresentationBinding {
    return this.shellPresentationBinding;
  }

  createNovelReaderBinding(): BrowserWindowSessionNovelReaderBinding {
    return this.novelReaderBinding;
  }

  async openNovelBookshelfFromPersistentCache(
    request: NovelReaderBookshelfCacheOpenRequest
  ): Promise<boolean> {
    if (this.released) {
      return false;
    }
    return this.novelReaderSessionCoordinator.openBookshelfFromPersistentCache(request);
  }

  createArticleReadingBinding(): BrowserWindowSessionArticleReadingBinding {
    return this.articleReadingBinding;
  }

  resolveShellPresentationSurface(): BrowserShellPresentationSurface | undefined {
    if (this.released) {
      return undefined;
    }
    return this.shellPresentationCoordinator.snapshot()?.surface;
  }

  reconcileWebAppPresentation(active: boolean): BrowserShellPresentationSnapshot | undefined {
    if (this.released) {
      return undefined;
    }
    return this.shellPresentationCoordinator.reconcileWebAppPresentation(active).snapshot;
  }

  connectShellPresentation(catalog: BrowserShellAdapterCatalogSnapshot): void {
    if (this.released) {
      return;
    }
    this.shellPresentationCoordinator.connect(catalog);
  }

  reconcilePresentationProfile(
    input: BrowserWindowPresentationProfileInput,
    availability: BrowserShellFamilyAvailability,
    revision: number
  ): BrowserWindowPresentationReconcileResult | undefined {
    if (this.released) {
      return undefined;
    }
    const profile = this.presentationProfileCoordinator.reconcile(input, availability, revision);
    const presentationResult = this.shellPresentationCoordinator.reconcile(profile);
    return {
      profile: profile,
      presentationChanged: presentationResult.changed
    };
  }

  reconcileLargeScreenPresentation(
    facts: BrowserLargeScreenPresentationFacts
  ): BrowserShellPresentationSnapshot | undefined {
    if (this.released) {
      return undefined;
    }
    return this.shellPresentationCoordinator.reconcileLargeScreenPresentation(facts);
  }

  reconcileLargeScreenWindowFacts(
    input: BrowserLargeScreenWindowFactsInput,
    policy: BrowserLargeScreenWindowFactsPolicy
  ): BrowserShellPresentationReconcileResult {
    if (this.released) {
      return { snapshot: undefined, changed: false };
    }
    const facts: BrowserLargeScreenWindowFactsSnapshot =
      this.largeScreenWindowFactsViewModel.resolve(input, policy);
    return this.shellPresentationCoordinator.reconcileLargeScreenWindowFacts(facts);
  }

  release(windowId: string, revision: number): void {
    if (this.released || windowId !== this.windowId) {
      return;
    }
    if (revision > this.lifetimeRevision) {
      this.lifetimeRevision = revision;
    }
    sharedBrowserWindowSessionLifetimeSignal.reconcile(this.windowId, false);
    sharedBrowserWindowSessionLifetimeSignal.clear(this.windowId);
    this.foreground = false;
    this.released = true;
    runtimeBindings.delete(this.runtimeSessionBinding);
    runtimeLifecycleBindings.delete(this.runtimeSessionBinding);
    tabManagerBindings.delete(this.tabManagerBinding);
    unregisterBrowserWindowSessionContextStateStore(this.contextStateBinding);
    backgroundBindings.delete(this.backgroundBinding);
    shellPresentationBindings.delete(this.shellPresentationBinding);
    this.novelReaderSessionCoordinator.close();
    novelReaderBindings.delete(this.novelReaderBinding);
    this.articleReadingCoordinator.closeSession();
    this.articleReadingCoordinator.shutdownSpeechSession();
    articleReadingBindings.delete(this.articleReadingBinding);
    this.presentationProfileCoordinator.clear();
    this.disconnectWindowContext();
    this.shellPresentationCoordinator.disconnect();
  }
}

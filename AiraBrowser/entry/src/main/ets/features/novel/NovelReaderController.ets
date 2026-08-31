import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { NovelExtractionService } from '../../services/novel/NovelExtractionService';
import {
  COMIC_CHAPTER_AUTHENTICATION_REQUIRED_ERROR,
  ComicChapterAcquisitionEngine,
  sharedComicChapterAcquisitionEngine
} from '../../services/novel/ComicChapterAcquisitionEngine';
import { NovelBookCoverPaletteService } from '../../services/novel/NovelBookCoverPaletteService';
import {
  NovelBookCoverImageService,
  sharedNovelBookCoverImageService
} from '../../services/novel/NovelBookCoverImageService';
import {
  NovelLibraryRepository,
  sharedNovelLibraryRepository
} from '../../data/novel/NovelLibraryRepository';
import {
  sharedNovelCatalogCacheRepository
} from '../../data/novel/NovelCatalogCacheRepository';
import {
  sharedNovelChapterArtifactCacheRepository
} from '../../data/novel/NovelChapterArtifactCacheRepository';
import { NovelCatalogCachePolicyService } from '../../services/novel/NovelCatalogCachePolicyService';
import {
  NovelDetectionPolicy,
  NovelDetectionPolicyCatalog,
  sharedNovelDetectionPolicyCatalog
} from '../../services/novel/NovelDetectionPolicyCatalog';
import {
  NovelSourceIdentityService,
  sharedNovelSourceIdentityService
} from '../../services/novel/NovelSourceIdentityService';
import {
  buildNovelBookPaletteCacheKey,
  cloneNovelBookCoverPalette,
  NovelBookCoverPalette,
  NovelBookPaletteThemeMode,
  NovelBookshelfBook,
  NovelBookshelfBookInput
} from './NovelLibraryModels';
import { consumeNovelBookshelfTakeover } from './NovelBookshelfOpenRequestCenter';
import {
  ReaderModeLineHeight,
  ReaderModePageWidth,
  ReaderModeTheme
} from '../../common/models/BrowserModels';
import {
  createDefaultNovelReaderPreferences,
  createDefaultNovelReaderSnapshot,
  NovelBookOverview,
  NovelCatalogCachePort,
  NovelCatalogCacheRecord,
  NovelCatalogEntry,
  NOVEL_CATALOG_RANGE_SIZE,
  NovelCatalogPageCursor,
  NovelCatalogPageResult,
  NovelCatalogResult,
  NovelChapterArtifactCachePort,
  NovelChapterArtifactCacheReadResult,
  NovelChapterArtifactCacheRecord,
  NovelChapterExtract,
  NovelContentKind,
  NovelDetectedPageType,
  NovelReaderAction,
  NovelReaderCatalogEntry,
  NovelReaderEffect,
  NovelReaderPageReadyFacts,
  NovelReaderPageMode,
  NovelReaderPreferences,
  NovelReadingCheckpointPort,
  NovelReadingCheckpointRecord,
  NovelReaderPreferencesPort,
  NovelReaderSessionScope,
  NovelReaderSessionListener,
  NovelReaderSnapshot,
  NovelTopPromptState
} from './NovelReaderModels';
import {
  NovelReadingSessionState,
  NovelSessionCatalogChapter,
  NovelSessionCatalogCommit,
  NovelSessionCatalogRequest,
  NovelSessionChapterCommit,
  NovelSessionChapterIntent,
  NovelSessionChapterRequest,
  NovelSessionChapterRetryTarget,
  NovelSessionCommittedChapter,
  NovelSessionFailureCode,
  NovelReadingSessionSnapshot,
  NovelSessionOperationSnapshot
} from './NovelReadingSessionState';

const NOVEL_LOG_DOMAIN = 0x0000;
const NOVEL_LOG_TAG = 'AiraNovel';
const NOVEL_CHAPTER_PREFETCH_DELAY_MS: number = 280;
const NOVEL_RENDERED_CHAPTER_TIMEOUT_MS: number = 12 * 1000;

export type NovelReaderEntryReason = 'automatic' | 'manual';

export interface NovelReaderOpenRequest {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  webPageVisible: boolean;
  pageUrl: string;
  acceptedNavigationCommitUrl?: string;
  detectedPageType?: NovelDetectedPageType;
  requireDetectedPage?: boolean;
  entryReason: NovelReaderEntryReason;
  scope: NovelReaderSessionScope;
}

export interface NovelReaderBookshelfCacheOpenRequest {
  book: NovelBookshelfBook;
  tabId: string;
}

export interface NovelReaderTakeoverPreviewCapturePort {
  captureSourceTabPreview(tabId: string): Promise<boolean>;
  isSourceTabCurrent(scope: NovelReaderSessionScope, pageUrl: string): boolean;
}

export interface NovelReaderSessionConnection {
  disconnect(): void;
}

class NovelReaderSessionConnectionImplementation implements NovelReaderSessionConnection {
  private disconnectListener?: () => void;

  constructor(disconnectListener: () => void) {
    this.disconnectListener = disconnectListener;
  }

  disconnect(): void {
    const disconnectListener = this.disconnectListener;
    this.disconnectListener = undefined;
    disconnectListener?.();
  }
}

/**
 * Controller 的公开快照只能由语义事件推进。
 * 这里禁止 all-optional patch: 目录、章节、书籍和装饰状态必须通过各自的边界更新。
 */
interface NovelReentryClearedEvent {
  type: 'reentry_cleared';
}

interface NovelOpeningStartedEvent {
  type: 'opening_started';
  scope: NovelReaderSessionScope;
  pageUrl: string;
  requestId: string;
}

interface NovelOpeningFailedEvent {
  type: 'opening_failed';
  requestId: string;
  failureCode: NovelSessionFailureCode;
}

interface NovelCatalogLoadingEvent {
  type: 'catalog_loading';
  catalogUrl: string;
  session: NovelReadingSessionSnapshot;
  rangeStartOrdinal: number;
  rangeEndOrdinal: number;
}

interface NovelCatalogReadyEvent {
  type: 'catalog_ready';
  catalogUrl: string;
  bookTitle: string;
  bookAuthor: string;
  bookCoverUrl: string;
  session: NovelReadingSessionSnapshot;
  hasMore: boolean;
  totalHint: number;
  supportsRandomAccess: boolean;
}

interface NovelCatalogFailedEvent {
  type: 'catalog_failed';
  session: NovelReadingSessionSnapshot;
}

interface NovelBookOverviewReadyEvent {
  type: 'book_overview_ready';
  overview: NovelBookOverview;
  detailUrl: string;
  catalogUrl: string;
  bookshelfAvailable: boolean;
  session: NovelReadingSessionSnapshot;
}

interface NovelReaderStateEvent {
  type: 'reader_state';
  session: NovelReadingSessionSnapshot;
  bookTitle: string;
}

interface NovelPreferencesChangedEvent {
  type: 'preferences_changed';
  preferences: NovelReaderPreferences;
}

interface NovelBookshelfStateEvent {
  type: 'bookshelf_state';
  inBookshelf?: boolean;
  actionBusy?: boolean;
}

interface NovelBookshelfContextReadyEvent {
  type: 'bookshelf_context_ready';
  detailUrl: string;
  available: boolean;
}

interface NovelTopPromptChangedEvent {
  type: 'top_prompt_changed';
  prompt: NovelTopPromptState;
}

interface NovelPaletteLoadingEvent {
  type: 'palette_loading';
}

interface NovelPaletteReadyEvent {
  type: 'palette_ready';
  key?: string;
  palette?: NovelBookCoverPalette;
  loading: boolean;
}

interface NovelResumeHintChangedEvent {
  type: 'resume_hint_changed';
  resumeHint: string;
}

interface NovelCatalogWindowLoadResult {
  bookTitle: string;
  author: string;
  coverUrl: string;
  entries: NovelCatalogEntry[];
  complete: boolean;
  totalHint: number;
  pageCursor?: NovelCatalogPageCursor;
}

type NovelReaderSnapshotEvent = NovelReentryClearedEvent | NovelOpeningStartedEvent |
  NovelOpeningFailedEvent | NovelCatalogLoadingEvent | NovelCatalogReadyEvent |
  NovelCatalogFailedEvent | NovelBookOverviewReadyEvent | NovelReaderStateEvent |
  NovelPreferencesChangedEvent | NovelBookshelfStateEvent | NovelBookshelfContextReadyEvent |
  NovelPaletteLoadingEvent | NovelPaletteReadyEvent | NovelResumeHintChangedEvent |
  NovelTopPromptChangedEvent;

export interface NovelExtractionPort {
  detectNovelPage(controller: webview.WebviewController, pageUrl: string): Promise<string>;
  extractBookOverview(controller: webview.WebviewController, pageUrl: string): Promise<NovelBookOverview>;
  extractCurrent(controller: webview.WebviewController, pageUrl: string): Promise<NovelChapterExtract>;
  fetchCatalog(
    controller: webview.WebviewController,
    catalogUrl: string,
    maximumEntries?: number
  ): Promise<NovelCatalogResult>;
  fetchCatalogPage(
    controller: webview.WebviewController,
    catalogUrl: string,
    cursor: NovelCatalogPageCursor
  ): Promise<NovelCatalogPageResult | undefined>;
  fetchChapter(
    controller: webview.WebviewController,
    chapterUrl: string,
    contentKind?: NovelContentKind
  ): Promise<NovelChapterExtract>;
}

export class NovelReaderControllerOptions {
  extractionService?: NovelExtractionPort;
  preferencesRepository?: NovelReaderPreferencesPort;
  checkpointRepository?: NovelReadingCheckpointPort;
  catalogCacheRepository?: NovelCatalogCachePort;
  chapterArtifactCacheRepository?: NovelChapterArtifactCachePort;
  catalogCachePolicyService?: NovelCatalogCachePolicyService;
  libraryRepository?: NovelLibraryRepository;
  bookCoverPaletteService?: NovelBookCoverPaletteService;
  bookCoverImageService?: NovelBookCoverImageService;
  detectionPolicyCatalog?: NovelDetectionPolicyCatalog;
}

export interface NovelReaderSessionOperations {
  connectSessionListener(listener: NovelReaderSessionListener): NovelReaderSessionConnection;
  getSnapshot(): NovelReaderSnapshot;
  shouldHandleSpaRouteReprobe(): boolean;
  reconcileReentryForPageReady(facts: NovelReaderPageReadyFacts): void;
  handlePageReadyForAutoDetection(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void;
  openFromLifecyclePort(request: NovelReaderOpenRequest): Promise<void>;
  openBookshelfFromPersistentCache(request: NovelReaderBookshelfCacheOpenRequest): Promise<boolean>;
  connectTakeoverPreviewCapture(port?: NovelReaderTakeoverPreviewCapturePort): NovelReaderSessionConnection;
  handleAction(action: NovelReaderAction): void;
  close(): void;
}

/**
 * 小说模式控制器。
 *
 * 核心架构(实测踩坑后确定):
 * - 章节页的上一章/下一章链接优先,完整目录只补齐站点未提供的相邻链接。
 * - 目录标题按 100 章范围显式加载；未展开范围不发请求，随机分页源可直接跳到远端范围。
 * - 单章被站点拆成多页时(第1/3页),抽取服务会沿"下一页"合并成完整一章。
 */
export class NovelReaderController implements NovelReaderSessionOperations {
  private extractionService: NovelExtractionPort;
  private preferencesRepository?: NovelReaderPreferencesPort;
  private checkpointRepository?: NovelReadingCheckpointPort;
  private catalogCacheRepository: NovelCatalogCachePort;
  private chapterArtifactCacheRepository: NovelChapterArtifactCachePort;
  private catalogCachePolicyService: NovelCatalogCachePolicyService;
  private libraryRepository: NovelLibraryRepository;
  private bookCoverPaletteService: NovelBookCoverPaletteService;
  private bookCoverImageService: NovelBookCoverImageService;
  private readonly detectionPolicyCatalog: NovelDetectionPolicyCatalog;
  private snapshot: NovelReaderSnapshot = createDefaultNovelReaderSnapshot();
  private readonly readingSessionState: NovelReadingSessionState = new NovelReadingSessionState();
  private sessionListener?: NovelReaderSessionListener;
  private sessionListenerRevision: number = 0;
  private openGeneration: number = 0;
  private activeController?: webview.WebviewController;
  private activeSourcePageUrl: string = '';
  private runtimeAvailable: boolean = true;
  private autoSuppressed: boolean = false;
  private lastAutoIdentity: string = '';
  private autoDetectionGeneration: number = 0;
  private autoDetectionRetryTimer: number = -1;
  private autoDetectionProbeRuns: number = 0;
  private autoDetectionNextRetryIndex: number = 0;
  private autoDetectionInFlightGeneration: number = -1;
  private autoDetectionInFlightIdentity: string = '';
  private preferencesMutationRevision: number = 0;
  private preferencesWriteTask: Promise<void> = Promise.resolve();
  private checkpointWriteTask: Promise<void> = Promise.resolve();
  private checkpointLoadTask?: Promise<NovelReadingCheckpointRecord | undefined>;
  private checkpointLoadBookId: string = '';
  private checkpointLoadBookDetailUrl: string = '';
  private checkpointFallbackBookId: string = '';
  private pendingPersistedCheckpoint?: NovelReadingCheckpointRecord;
  private latestPersistedCheckpointUpdatedAt: number = 0;
  private exitConfirmationPending: boolean = false;
  private bookshelfRequestGeneration: number = 0;
  private bookPaletteRequestGeneration: number = 0;
  private sessionGeneration: number = 0;
  private chapterRequestSequence: number = 0;
  private catalogRequestSequence: number = 0;
  private contentRevisionSequence: number = 0;
  private takeoverPreviewCapturePort?: NovelReaderTakeoverPreviewCapturePort;
  private takeoverPreviewCaptureRevision: number = 0;
  private readonly sourceIdentityService: NovelSourceIdentityService = sharedNovelSourceIdentityService;
  private readonly comicChapterAcquisitionEngine: ComicChapterAcquisitionEngine =
    sharedComicChapterAcquisitionEngine;
  private pendingChapterArtifactRefresh?: NovelChapterArtifactCacheRecord;
  private pendingChapterArtifactRefreshSessionGeneration: number = 0;
  private pendingRenderedChapterRequest?: NovelSessionChapterRequest;
  private pendingRenderedChapterGeneration: number = -1;
  private pendingRenderedChapterInFlight: boolean = false;
  private pendingRenderedChapterAttemptSequence: number = 0;
  private pendingRenderedChapterActiveAttempt: number = 0;
  private pendingRenderedChapterTimeoutTimer: number = -1;
  private catalogPageCursor?: NovelCatalogPageCursor;
  private catalogTotalHint: number = 0;
  private catalogRangeExtentHint: number = 0;
  private catalogRefreshRecommended: boolean = false;
  private catalogDefaultRangeHydrationPending: boolean = false;
  private chapterPrefetchTimer: number = -1;
  private chapterPrefetchTargetUrl: string = '';
  private chapterPrefetchTask?: Promise<void>;
  private chapterPrefetchRevision: number = 0;

  constructor(options: NovelReaderControllerOptions = new NovelReaderControllerOptions()) {
    this.extractionService = options.extractionService ?? new NovelExtractionService();
    this.preferencesRepository = options.preferencesRepository;
    this.checkpointRepository = options.checkpointRepository;
    this.catalogCacheRepository = options.catalogCacheRepository ?? sharedNovelCatalogCacheRepository;
    this.chapterArtifactCacheRepository = options.chapterArtifactCacheRepository ??
      sharedNovelChapterArtifactCacheRepository;
    this.catalogCachePolicyService = options.catalogCachePolicyService ?? new NovelCatalogCachePolicyService();
    this.libraryRepository = options.libraryRepository ?? sharedNovelLibraryRepository;
    this.bookCoverPaletteService = options.bookCoverPaletteService ?? new NovelBookCoverPaletteService();
    this.bookCoverImageService = options.bookCoverImageService ?? sharedNovelBookCoverImageService;
    this.detectionPolicyCatalog = options.detectionPolicyCatalog ?? sharedNovelDetectionPolicyCatalog;
    void this.loadPreferences();
  }

  connectSessionListener(listener: NovelReaderSessionListener): NovelReaderSessionConnection {
    const listenerRevision: number = this.sessionListenerRevision + 1;
    this.sessionListenerRevision = listenerRevision;
    this.sessionListener = listener;
    this.notify();
    return new NovelReaderSessionConnectionImplementation((): void => {
      if (this.sessionListenerRevision === listenerRevision) {
        this.sessionListener = undefined;
      }
    });
  }

  getSnapshot(): NovelReaderSnapshot {
    return this.cloneSnapshot(this.snapshot);
  }

  connectTakeoverPreviewCapture(
    port?: NovelReaderTakeoverPreviewCapturePort
  ): NovelReaderSessionConnection {
    const revision = this.takeoverPreviewCaptureRevision + 1;
    this.takeoverPreviewCaptureRevision = revision;
    this.takeoverPreviewCapturePort = port;
    return new NovelReaderSessionConnectionImplementation((): void => {
      if (this.takeoverPreviewCaptureRevision === revision) {
        this.takeoverPreviewCapturePort = undefined;
      }
    });
  }

  reconcileWindowState(
    activeTabId: string,
    tabIds: string[],
    activeController?: webview.WebviewController
  ): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (session.phase === 'inactive') {
      return;
    }
    if (tabIds.indexOf(session.tabId) < 0) {
      this.persistSessionCheckpoint();
      this.closeSession(false);
      return;
    }
    if (activeTabId === session.tabId) {
      this.runtimeAvailable = activeController !== undefined;
      if (activeController !== undefined) {
        this.activeController = activeController;
      }
      if (this.readingSessionState.resume(activeTabId)) {
        this.publishReadingSessionState();
        this.emitEffect({
          type: 'status_bar_visibility_override',
          visible: this.snapshot.preferences.systemStatusBarVisible
        });
      }
      return;
    }
    if (session.phase === 'opening') {
      this.closeSession(false);
      return;
    }
    this.runtimeAvailable = false;
    if (this.readingSessionState.suspend(activeTabId)) {
      this.publishReadingSessionState();
      this.emitEffect({ type: 'status_bar_visibility_release' });
    }
  }

  isVisible(): boolean {
    return this.snapshot.visible;
  }

  shouldHandleSpaRouteReprobe(): boolean {
    const policy: NovelDetectionPolicy = this.detectionPolicyCatalog.currentPolicy();
    return policy.spaRouteReprobeEnabled && policy.strategyIds.indexOf('dom_evidence_v1') >= 0;
  }

  shouldAttemptAutoDetection(identity: string): boolean {
    if (this.readingSessionState.snapshot().phase === 'suspended') {
      return false;
    }
    if (identity !== this.lastAutoIdentity) {
      this.cancelAutoDetectionRetry();
      this.lastAutoIdentity = identity;
      this.autoSuppressed = false;
      this.autoDetectionGeneration = this.autoDetectionGeneration + 1;
      this.autoDetectionProbeRuns = 0;
      this.autoDetectionNextRetryIndex = 0;
      if (this.snapshot.reentryAvailable) {
        this.emit({ type: 'reentry_cleared' });
      }
    }
    const policy: NovelDetectionPolicy = this.detectionPolicyCatalog.currentPolicy();
    return !this.snapshot.visible && !this.autoSuppressed &&
      policy.strategyIds.indexOf('dom_evidence_v1') >= 0 &&
      this.autoDetectionProbeRuns < policy.maxProbeRunsPerNavigation;
  }

  handlePageReadyForAutoDetection(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void {
    this.handlePageReadyForDetection(runtimeLifecyclePort, facts, 'automatic');
  }

  handlePageReadyForCandidateDetection(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void {
    this.handlePageReadyForDetection(runtimeLifecyclePort, facts, 'manual');
  }

  reconcileReentryForPageReady(facts: NovelReaderPageReadyFacts): void {
    const snapshot: NovelReaderSnapshot = this.snapshot;
    const committedPageUrl: string = facts.acceptedNavigationCommitUrl ?? '';
    const acceptedPageUrl: string = committedPageUrl.trim().length > 0
      ? committedPageUrl
      : facts.pageUrl;
    if (!snapshot.reentryAvailable || snapshot.visible || snapshot.scope.tabId !== facts.tabId ||
      facts.scope.tabId !== facts.tabId || !acceptedPageUrl.startsWith('http') ||
      this.normalizeUrl(snapshot.reentryPageUrl) === this.normalizeUrl(acceptedPageUrl)) {
      return;
    }
    this.emit({ type: 'reentry_cleared' });
  }

  private handlePageReadyForDetection(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts,
    entryReason: NovelReaderEntryReason
  ): void {
    const activeTabMatches: boolean = facts.tabId === facts.activeTabId;
    const scopeTabMatches: boolean = facts.tabId === facts.scope.tabId;
    const validScope: boolean = this.isValidScope(facts.scope);
    if (!activeTabMatches || !scopeTabMatches || !facts.webPageVisible ||
      !facts.pageUrl.startsWith('http') || !validScope) {
      return;
    }
    const bookshelfBook: NovelBookshelfBook | undefined = consumeNovelBookshelfTakeover(facts.pageUrl);
    const reconciledOwnerRuntime: boolean = this.reconcileOwnerRuntimeFromPageReady(runtimeLifecyclePort, facts);
    if (reconciledOwnerRuntime) {
      return;
    }
    const autoIdentity: string = this.buildAutoIdentity(facts.pageUrl, facts.scope);
    if (bookshelfBook !== undefined) {
      this.autoSuppressed = false;
    }
    const shouldAttempt: boolean = this.shouldAttemptAutoDetection(autoIdentity);
    if (!shouldAttempt) {
      return;
    }
    this.cancelAutoDetectionRetry();
    this.runtimeAvailable = true;
    void this.autoDetectAndOpen({
      runtimeLifecyclePort: runtimeLifecyclePort,
      webPageVisible: facts.webPageVisible,
      pageUrl: facts.pageUrl,
      acceptedNavigationCommitUrl: facts.acceptedNavigationCommitUrl,
      entryReason: entryReason,
      scope: facts.scope
    }, autoIdentity, bookshelfBook);
  }

  private reconcileOwnerRuntimeFromPageReady(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): boolean {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (session.phase === 'inactive' || session.tabId !== facts.tabId ||
      session.privacyMode !== facts.scope.privacyMode) {
      return false;
    }
    const controller: webview.WebviewController | undefined = runtimeLifecyclePort.resolveActiveController();
    this.runtimeAvailable = controller !== undefined;
    if (controller !== undefined) {
      this.activeController = controller;
      this.refreshPendingCachedChapterIfReady(controller, facts.pageUrl);
      this.resumePendingRenderedChapter(controller, facts.pageUrl);
    }
    if (this.readingSessionState.resume(facts.activeTabId)) {
      this.publishReadingSessionState();
      this.emitEffect({
        type: 'status_bar_visibility_override',
        visible: this.snapshot.preferences.systemStatusBarVisible
      });
    }
    if (controller !== undefined && this.catalogDefaultRangeHydrationPending) {
      this.requestDefaultCatalogRangeHydration();
    }
    this.scheduleNextChapterPrefetch();
    return true;
  }

  closeByUser(): void {
    const reentryAvailable: boolean = this.snapshot.visible && this.snapshot.phase !== 'inactive';
    this.cancelAutoDetectionRetry();
    this.autoDetectionGeneration = this.autoDetectionGeneration + 1;
    this.autoSuppressed = true;
    this.closeSession(reentryAvailable);
  }

  /**
   * 页面加载完的自动接管不依赖 host 白名单。抽取 adapter 必须用多项 DOM 结构证据
   * 保守确认章节页或书籍详情页,普通网页探测失败时静默留在原网页。
   */
  private async autoDetectAndOpen(
    request: NovelReaderOpenRequest,
    autoIdentity: string,
    bookshelfBook?: NovelBookshelfBook
  ): Promise<void> {
    if (this.snapshot.visible) {
      return;
    }
    const controller: webview.WebviewController | undefined =
      request.webPageVisible ? request.runtimeLifecyclePort.resolveActiveController() : undefined;
    if (controller === undefined) {
      return;
    }
    const detectionGeneration: number = this.autoDetectionGeneration;
    const policy: NovelDetectionPolicy = this.detectionPolicyCatalog.currentPolicy();
    if (policy.strategyIds.indexOf('dom_evidence_v1') < 0 ||
      this.autoDetectionProbeRuns >= policy.maxProbeRunsPerNavigation ||
      !this.beginAutoDetectionRun(autoIdentity, detectionGeneration)) {
      return;
    }
    this.autoDetectionProbeRuns += 1;
    try {
      const openedCachedChapter: boolean = await this.tryOpenCachedChapter(
        controller,
        request,
        autoIdentity,
        detectionGeneration,
        bookshelfBook
      );
      if (openedCachedChapter) {
        return;
      }
      const currentBeforeDetection: boolean =
        this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration);
      if (!currentBeforeDetection) {
        return;
      }
      const type: NovelDetectedPageType = this.normalizeDetectedPageType(
        await this.extractionService.detectNovelPage(controller, request.pageUrl)
      );
      const currentAfterDetection: boolean =
        this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration);
      if (!currentAfterDetection) {
        return;
      }
      if (type === 'chapter' || type === 'book') {
        this.cancelAutoDetectionRetry();
        const previewReady: boolean = await this.prepareSourceTabPreview(request);
        if (!previewReady) {
          return;
        }
        const currentAfterPreview: boolean =
          this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration);
        if (!currentAfterPreview) {
          return;
        }
        await this.openWithController(controller, {
          runtimeLifecyclePort: request.runtimeLifecyclePort,
          webPageVisible: request.webPageVisible,
          pageUrl: request.pageUrl,
          acceptedNavigationCommitUrl: request.acceptedNavigationCommitUrl,
          detectedPageType: type,
          entryReason: request.entryReason,
          scope: request.scope
        });
        return;
      }
      this.scheduleAutoDetectionRetry(
        request,
        autoIdentity,
        detectionGeneration,
        bookshelfBook
      );
    } catch (_error) {
      if (this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration)) {
        this.scheduleAutoDetectionRetry(
          request,
          autoIdentity,
          detectionGeneration,
          bookshelfBook
        );
      }
    } finally {
      this.finishAutoDetectionRun(autoIdentity, detectionGeneration);
    }
  }

  private scheduleAutoDetectionRetry(
    request: NovelReaderOpenRequest,
    autoIdentity: string,
    detectionGeneration: number,
    bookshelfBook?: NovelBookshelfBook
  ): void {
    const policy: NovelDetectionPolicy = this.detectionPolicyCatalog.currentPolicy();
    if (policy.strategyIds.indexOf('dom_evidence_v1') < 0 ||
      this.autoDetectionProbeRuns >= policy.maxProbeRunsPerNavigation ||
      this.autoDetectionNextRetryIndex >= policy.retryDelaysMs.length) {
      return;
    }
    this.cancelAutoDetectionRetry();
    const delayMs: number = policy.retryDelaysMs[this.autoDetectionNextRetryIndex];
    this.autoDetectionNextRetryIndex += 1;
    this.autoDetectionRetryTimer = setTimeout((): void => {
      this.autoDetectionRetryTimer = -1;
      if (this.snapshot.visible || this.autoSuppressed ||
        detectionGeneration !== this.autoDetectionGeneration || autoIdentity !== this.lastAutoIdentity) {
        return;
      }
      void this.autoDetectAndOpen(request, autoIdentity, bookshelfBook);
    }, delayMs);
  }

  private beginAutoDetectionRun(autoIdentity: string, detectionGeneration: number): boolean {
    if (this.autoDetectionInFlightGeneration === detectionGeneration &&
      this.autoDetectionInFlightIdentity === autoIdentity) {
      return false;
    }
    this.autoDetectionInFlightGeneration = detectionGeneration;
    this.autoDetectionInFlightIdentity = autoIdentity;
    return true;
  }

  private finishAutoDetectionRun(autoIdentity: string, detectionGeneration: number): void {
    if (this.autoDetectionInFlightGeneration !== detectionGeneration ||
      this.autoDetectionInFlightIdentity !== autoIdentity) {
      return;
    }
    this.autoDetectionInFlightGeneration = -1;
    this.autoDetectionInFlightIdentity = '';
  }

  private cancelAutoDetectionRetry(): void {
    if (this.autoDetectionRetryTimer < 0) {
      return;
    }
    clearTimeout(this.autoDetectionRetryTimer);
    this.autoDetectionRetryTimer = -1;
  }

  private isAutoDetectionRequestCurrent(
    controller: webview.WebviewController,
    request: NovelReaderOpenRequest,
    autoIdentity: string,
    detectionGeneration: number
  ): boolean {
    return !this.snapshot.visible && !this.autoSuppressed &&
      detectionGeneration === this.autoDetectionGeneration && autoIdentity === this.lastAutoIdentity &&
      this.isLiveRequestIdentity(controller, request);
  }

  private async tryOpenCachedChapter(
    controller: webview.WebviewController,
    request: NovelReaderOpenRequest,
    autoIdentity: string,
    detectionGeneration: number,
    bookshelfBook?: NovelBookshelfBook
  ): Promise<boolean> {
    if (!this.canUsePersistentChapterCache(request.scope)) {
      return false;
    }
    const cacheStartedAt: number = Date.now();
    let cached: NovelChapterArtifactCacheReadResult | undefined = undefined;
    let cacheEntry: string = bookshelfBook === undefined ? 'chapter' : 'bookshelf';
    try {
      if (bookshelfBook !== undefined) {
        cached = await this.chapterArtifactCacheRepository.readLatestForBook(bookshelfBook.detailUrl);
      } else {
        cached = await this.chapterArtifactCacheRepository.readChapter(request.pageUrl);
        if (cached === undefined) {
          cached = await this.chapterArtifactCacheRepository.readLatestForBook(request.pageUrl);
          cacheEntry = 'book-detail';
        }
      }
    } catch (_error) {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache read failed during automatic open');
      return false;
    }
    if (cached === undefined ||
      !this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration)) {
      return false;
    }
    if (!this.isCachedArtifactValidForOpen(cached.artifact, request.pageUrl, bookshelfBook)) {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache identity rejected during automatic open');
      return false;
    }
    if (!await this.prepareSourceTabPreview(request) ||
      !this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration)) {
      return false;
    }
    await this.loadPreferences();
    if (!this.isAutoDetectionRequestCurrent(controller, request, autoIdentity, detectionGeneration)) {
      return false;
    }
    const opened: boolean = this.openCachedChapter(
      controller,
      request.scope,
      request.pageUrl,
      request.entryReason,
      cached,
      bookshelfBook
    );
    if (opened) {
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'open ready source=chapter-cache entry=%{public}s stale=%{public}s totalMs=%{public}d',
        cacheEntry,
        cached.refreshRecommended ? 'true' : 'false', Date.now() - cacheStartedAt);
    }
    return opened;
  }

  private openCachedChapter(
    controller: webview.WebviewController | undefined,
    scope: NovelReaderSessionScope,
    sourcePageUrl: string,
    entryReason: NovelReaderEntryReason,
    cached: NovelChapterArtifactCacheReadResult,
    bookshelfBook?: NovelBookshelfBook
  ): boolean {
    const artifact: NovelChapterArtifactCacheRecord = cached.artifact;
    this.cancelAutoDetectionRetry();
    this.activeController = controller;
    this.runtimeAvailable = controller !== undefined;
    this.activeSourcePageUrl = sourcePageUrl;
    this.beginOpen();
    this.resetSnapshot(scope);
    this.sessionGeneration = this.sessionGeneration + 1;
    this.readingSessionState.begin(
      scope.tabId,
      scope.privacyMode,
      artifact.bookId,
      this.sessionGeneration
    );
    this.emit({
      type: 'opening_started',
      scope: scope,
      pageUrl: sourcePageUrl,
      requestId: `${this.sessionGeneration}:open`
    });
    const detailUrl: string = this.resolveCachedArtifactDetailUrl(artifact, bookshelfBook);
    const cachedBookTitle: string = (bookshelfBook?.title ?? artifact.bookTitle).trim();
    const overview: NovelBookOverview = {
      contentKind: artifact.contentKind,
      title: cachedBookTitle.length > 0 ? cachedBookTitle : artifact.title,
      author: bookshelfBook?.author ?? '',
      category: bookshelfBook?.category ?? '',
      latest: bookshelfBook?.latestChapter ?? '',
      cover: bookshelfBook?.coverUrl ?? '',
      synopsis: bookshelfBook?.synopsis ?? '',
      host: bookshelfBook?.sourceHost ?? this.sourceIdentityService.normalizedAuthority(detailUrl),
      catalogUrl: artifact.catalogUrl,
      startChapterUrl: artifact.canonicalUrl,
      catalogSourceComplete: false,
      catalogTotal: 1,
      initialEntries: [{
        ordinal: Math.max(0, this.resolveChapterOrdinal(artifact.title) - 1),
        title: artifact.title,
        url: artifact.canonicalUrl
      }]
    };
    this.applyBookOverview(overview, detailUrl);
    const chapterRequest: NovelSessionChapterRequest = this.createChapterRequest(artifact.canonicalUrl, 'select');
    if (!this.readingSessionState.beginChapterTransition(chapterRequest) ||
      !this.commitAcquiredChapter(
        chapterRequest,
        this.createChapterExtractFromArtifact(artifact),
        artifact.finalUrl,
        false
      )) {
      this.rejectTakeover('identity_mismatch');
      return false;
    }
    this.markChapterArtifactAsLatest(artifact);
    this.publishAutomaticTakeoverPrompt(entryReason);
    void this.hydrateCatalogAndRefresh(
      artifact.catalogUrl,
      artifact.canonicalUrl,
      bookshelfBook?.latestChapter ?? '',
      false,
      0
    );
    if (cached.refreshRecommended) {
      if (controller !== undefined) {
        void this.refreshCachedChapter(controller, artifact, 'select', this.sessionGeneration);
      } else {
        this.pendingChapterArtifactRefresh = artifact;
        this.pendingChapterArtifactRefreshSessionGeneration = this.sessionGeneration;
      }
    }
    return true;
  }

  private isCachedArtifactValidForOpen(
    artifact: NovelChapterArtifactCacheRecord,
    pageUrl: string,
    bookshelfBook?: NovelBookshelfBook
  ): boolean {
    const detailUrl: string = this.resolveCachedArtifactDetailUrl(artifact, bookshelfBook);
    const identityCatalogUrl: string = artifact.catalogUrl.length > 0 ? artifact.catalogUrl : detailUrl;
    if (detailUrl.length === 0 || artifact.title.trim().length === 0 ||
      artifact.bookId !== this.sourceIdentityService.buildBookIdentity(identityCatalogUrl, detailUrl) ||
      artifact.chapterId !== this.sourceIdentityService.buildChapterIdentity(
        artifact.bookId,
        artifact.canonicalUrl
      )) {
      return false;
    }
    if (bookshelfBook !== undefined) {
      return this.sourceIdentityService.normalizeUrl(bookshelfBook.detailUrl) ===
        this.sourceIdentityService.normalizeUrl(artifact.bookDetailUrl);
    }
    const pageIdentity: string = this.sourceIdentityService.normalizeUrl(pageUrl);
    return pageIdentity === this.sourceIdentityService.normalizeUrl(artifact.canonicalUrl) ||
      pageIdentity === this.sourceIdentityService.normalizeUrl(artifact.bookDetailUrl);
  }

  private resolveCachedArtifactDetailUrl(
    artifact: NovelChapterArtifactCacheRecord,
    bookshelfBook?: NovelBookshelfBook
  ): string {
    if (bookshelfBook !== undefined && bookshelfBook.detailUrl.trim().length > 0) {
      return bookshelfBook.detailUrl;
    }
    if (artifact.bookDetailUrl.trim().length > 0) {
      return artifact.bookDetailUrl;
    }
    if (artifact.catalogUrl.trim().length > 0) {
      return artifact.catalogUrl;
    }
    return this.sourceIdentityService.parentDirectory(artifact.canonicalUrl);
  }

  private createChapterExtractFromArtifact(
    artifact: NovelChapterArtifactCacheRecord
  ): NovelChapterExtract {
    return {
      pageUrl: artifact.finalUrl,
      title: artifact.title,
      paragraphs: artifact.paragraphs.slice(),
      images: artifact.images.slice(),
      prevUrl: artifact.prevUrl,
      nextUrl: artifact.nextUrl,
      catalogUrl: artifact.catalogUrl,
      bookTitle: artifact.bookTitle,
      pageTotal: 1,
      nextPageUrl: ''
    };
  }

  private refreshPendingCachedChapterIfReady(
    controller: webview.WebviewController,
    pageUrl: string
  ): void {
    const artifact: NovelChapterArtifactCacheRecord | undefined = this.pendingChapterArtifactRefresh;
    const expectedSessionGeneration: number = this.pendingChapterArtifactRefreshSessionGeneration;
    if (artifact === undefined) {
      return;
    }
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (expectedSessionGeneration <= 0 ||
      session.sessionGeneration !== expectedSessionGeneration || session.bookId !== artifact.bookId ||
      session.activeChapterId !== artifact.chapterId) {
      this.clearPendingChapterArtifactRefresh();
      return;
    }
    if (this.normalizeUrl(pageUrl) !== this.normalizeUrl(this.activeSourcePageUrl)) {
      return;
    }
    this.clearPendingChapterArtifactRefresh();
    void this.refreshCachedChapter(controller, artifact, 'select', expectedSessionGeneration);
  }

  async openBookshelfFromPersistentCache(
    request: NovelReaderBookshelfCacheOpenRequest
  ): Promise<boolean> {
    const tabId: string = request.tabId.trim();
    const detailUrl: string = request.book.detailUrl.trim();
    const lowerDetailUrl: string = detailUrl.toLowerCase();
    if (tabId.length === 0 ||
      (!lowerDetailUrl.startsWith('https://') && !lowerDetailUrl.startsWith('http://'))) {
      return false;
    }
    const expectedOpenGeneration: number = this.openGeneration;
    let cached: NovelChapterArtifactCacheReadResult | undefined = undefined;
    try {
      cached = await this.chapterArtifactCacheRepository.readLatestForBook(detailUrl);
    } catch (_error) {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache read failed before Bookshelf navigation');
      return false;
    }
    if (cached === undefined || expectedOpenGeneration !== this.openGeneration ||
      !this.isCachedArtifactValidForOpen(cached.artifact, detailUrl, request.book)) {
      return false;
    }
    await this.loadPreferences();
    if (expectedOpenGeneration !== this.openGeneration) {
      return false;
    }
    const scope: NovelReaderSessionScope = {
      tabId: tabId,
      privacyMode: 'regular',
      dataScope: 'profile_persistent'
    };
    const opened: boolean = this.openCachedChapter(
      undefined,
      scope,
      detailUrl,
      'automatic',
      cached,
      request.book
    );
    if (opened) {
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'open ready source=bookshelf-pre-navigation-cache stale=%{public}s',
        cached.refreshRecommended ? 'true' : 'false');
    }
    return opened;
  }

  async openFromLifecyclePort(request: NovelReaderOpenRequest): Promise<void> {
    if (!request.webPageVisible || !request.pageUrl.startsWith('http') || !this.isValidScope(request.scope)) {
      return;
    }
    const controller: webview.WebviewController | undefined =
      request.runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return;
    }
    if (!await this.prepareSourceTabPreview(request)) {
      return;
    }
    await this.openWithController(controller, request);
  }

  private async prepareSourceTabPreview(request: NovelReaderOpenRequest): Promise<boolean> {
    const port = this.takeoverPreviewCapturePort;
    if (port === undefined) {
      return true;
    }
    const hasTabId: boolean = request.scope.tabId.trim().length > 0;
    const currentBeforeCapture: boolean = hasTabId && port.isSourceTabCurrent(request.scope, request.pageUrl);
    if (!currentBeforeCapture) {
      return false;
    }
    await port.captureSourceTabPreview(request.scope.tabId);
    const samePort: boolean = this.takeoverPreviewCapturePort === port;
    const currentAfterCapture: boolean = samePort && port.isSourceTabCurrent(request.scope, request.pageUrl);
    return currentAfterCapture;
  }

  private async openWithController(
    controller: webview.WebviewController,
    request: NovelReaderOpenRequest
  ): Promise<void> {
    const liveAtEntry: boolean = this.isLiveRequestIdentity(controller, request);
    if (!liveAtEntry) {
      return;
    }
    await this.loadPreferences();
    const liveAfterPreferences: boolean = this.isLiveRequestIdentity(controller, request);
    if (!liveAfterPreferences) {
      return;
    }
    this.cancelAutoDetectionRetry();
    this.activeController = controller;
    this.runtimeAvailable = true;
    this.activeSourcePageUrl = request.pageUrl;
    const generation: number = this.beginOpen();
    this.resetSnapshot(request.scope);
    this.sessionGeneration = this.sessionGeneration + 1;
    this.readingSessionState.begin(
      request.scope.tabId,
      request.scope.privacyMode,
      this.buildBookIdentity('', request.pageUrl),
      this.sessionGeneration
    );
    this.emit({
      type: 'opening_started',
      scope: request.scope,
      pageUrl: request.pageUrl,
      requestId: `${this.sessionGeneration}:open`
    });
    const openStartedAt: number = Date.now();
    try {
      let pageType: NovelDetectedPageType = request.detectedPageType ?? '';
      if (pageType.length === 0) {
        pageType = this.normalizeDetectedPageType(
          await this.extractionService.detectNovelPage(controller, request.pageUrl)
        );
        if (!this.isOpenRequestCurrent(generation, controller, request)) {
          return;
        }
      }
      if (request.requireDetectedPage === true && pageType.length === 0) {
        this.rejectTakeover('content_rejected');
        return;
      }
      const detectionFinishedAt: number = Date.now();
      if (pageType === 'book') {
        const overview: NovelBookOverview =
          await this.extractionService.extractBookOverview(controller, request.pageUrl);
        const currentAfterOverview: boolean = this.isOpenRequestCurrent(generation, controller, request);
        if (!currentAfterOverview) {
          return;
        }
        const usableOverview: boolean = this.applyUsableBookOverview(overview, request.pageUrl);
        if (!usableOverview) {
          this.rejectTakeover('content_rejected');
          return;
        }
        this.publishAutomaticTakeoverPrompt(request.entryReason);
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'open ready type=book detectMs=%{public}d overviewMs=%{public}d totalMs=%{public}d initial=%{public}d',
          detectionFinishedAt - openStartedAt, Date.now() - detectionFinishedAt,
          Date.now() - openStartedAt, overview.initialEntries.length);
        return;
      }
      const chapter: NovelChapterExtract = await this.extractionService.extractCurrent(controller, request.pageUrl);
      if (!this.isOpenRequestCurrent(generation, controller, request)) {
        return;
      }
      if (chapter.paragraphs.length >= 3 || this.comicChapterAcquisitionEngine.isComicArtifact(chapter.images)) {
        const currentChapterUrl: string = chapter.pageUrl.length > 0 ? chapter.pageUrl : request.pageUrl;
        this.activeSourcePageUrl = currentChapterUrl;
        this.applyChapter(chapter, currentChapterUrl);
        this.publishAutomaticTakeoverPrompt(request.entryReason);
        // 该章被站点拆成多页 → 从当前已确认章节地址继续合并全文。
        if (chapter.pageTotal > 1 && chapter.images.length === 0) {
          void this.reloadAssembled(currentChapterUrl, generation);
        }
        void this.hydrateCatalogAndRefresh(chapter.catalogUrl, currentChapterUrl, '', false, 0);
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'open ready type=chapter detectMs=%{public}d chapterMs=%{public}d totalMs=%{public}d',
          detectionFinishedAt - openStartedAt, Date.now() - detectionFinishedAt, Date.now() - openStartedAt);
        return;
      }
      const overview: NovelBookOverview =
        await this.extractionService.extractBookOverview(controller, request.pageUrl);
      if (!this.isOpenRequestCurrent(generation, controller, request)) {
        return;
      }
      if (this.applyUsableBookOverview(overview, request.pageUrl)) {
        this.publishAutomaticTakeoverPrompt(request.entryReason);
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'open ready type=book-fallback totalMs=%{public}d initial=%{public}d',
          Date.now() - openStartedAt, overview.initialEntries.length);
        return;
      }
      if (chapter.paragraphs.length > 0) {
        const currentChapterUrl: string = chapter.pageUrl.length > 0 ? chapter.pageUrl : request.pageUrl;
        this.activeSourcePageUrl = currentChapterUrl;
        this.applyChapter(chapter, currentChapterUrl);
        this.publishAutomaticTakeoverPrompt(request.entryReason);
        void this.hydrateCatalogAndRefresh(chapter.catalogUrl, currentChapterUrl, '', false, 0);
        return;
      }
      this.rejectTakeover('content_rejected');
    } catch (error) {
      if (!this.isOpenRequestCurrent(generation, controller, request)) {
        return;
      }
      this.rejectTakeover(this.resolveChapterAcquisitionFailureCode(error));
    }
  }

  private publishAutomaticTakeoverPrompt(entryReason: NovelReaderEntryReason): void {
    const promptKey: string = `auto-takeover:${this.sessionGeneration}`;
    if (entryReason !== 'automatic' || !this.snapshot.visible ||
      (this.snapshot.phase !== 'book' && this.snapshot.phase !== 'reader')) {
      return;
    }
    this.emit({
      type: 'top_prompt_changed',
      prompt: {
        visible: true,
        key: promptKey,
        kind: 'auto_takeover',
        bookTitle: this.snapshot.bookTitle,
        contentKind: this.snapshot.contentKind
      }
    });
  }

  handleAction(action: NovelReaderAction): void {
    if (action.type === 'close') {
      this.requestCloseByUser();
      return;
    }
    if (action.type === 'cancel_close') {
      this.exitConfirmationPending = false;
      return;
    }
    if (action.type === 'confirm_close') {
      if (this.exitConfirmationPending) {
        this.exitConfirmationPending = false;
        this.closeByUser();
      }
      return;
    }
    if (action.type === 'suspend_to_home') {
      this.suspendToHome();
      return;
    }
    if (action.type === 'continue_reading') {
      this.continueReading();
      return;
    }
    if (action.type === 'previous_chapter') {
      this.loadPrevChapter();
      return;
    }
    if (action.type === 'next_chapter') {
      this.loadNextChapter('next');
      return;
    }
    if (action.type === 'continue_vertical') {
      this.loadNextChapter('continue_vertical');
      return;
    }
    if (action.type === 'open_catalog') {
      this.openCatalog();
      this.emitEffect({ type: 'open_catalog' });
      return;
    }
    if (action.type === 'load_catalog_range') {
      this.loadCatalogRange(action.startOrdinal, action.endOrdinal);
      return;
    }
    if (action.type === 'open_control_panel') {
      this.emitEffect({ type: 'open_control_panel', panel: action.panel });
      return;
    }
    if (action.type === 'reading_appearance_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.fontSize = action.appearance.fontSize;
      preferences.theme = action.appearance.theme;
      preferences.lineHeight = action.appearance.lineHeight;
      preferences.pageWidth = action.appearance.pageWidth;
      preferences.brightnessMode = action.appearance.brightnessMode;
      preferences.brightnessPercent = action.appearance.brightnessPercent;
      this.updatePreferences(preferences);
      return;
    }
    if (action.type === 'reading_page_mode_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.pageMode = action.mode;
      if (action.mode !== 'vertical') {
        preferences.autoReadingEnabled = false;
      }
      this.updatePreferences(preferences);
      return;
    }
    if (action.type === 'auto_reading_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.autoReadingEnabled = action.enabled;
      if (action.enabled) {
        preferences.pageMode = 'vertical';
      }
      this.updatePreferences(preferences);
      if (action.enabled) {
        this.emitEffect({ type: 'close_system_sheet' });
      }
      return;
    }
    if (action.type === 'volume_key_paging_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.volumeKeyPagingEnabled = action.enabled;
      this.updatePreferences(preferences);
      return;
    }
    if (action.type === 'chapter_name_visibility_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.chapterNameVisible = action.visible;
      this.updatePreferences(preferences);
      return;
    }
    if (action.type === 'page_number_visibility_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.pageNumberVisible = action.visible;
      this.updatePreferences(preferences);
      return;
    }
    if (action.type === 'retry_catalog') {
      this.loadCatalogRange(0, NOVEL_CATALOG_RANGE_SIZE - 1);
      return;
    }
    if (action.type === 'retry_chapter') {
      this.retryChapterTransition();
      return;
    }
    if (action.type === 'return_to_source') {
      this.closeByUser();
      return;
    }
    if (action.type === 'copy_source_link') {
      this.emitEffect({ type: 'copy_source_url', url: this.snapshot.pageUrl });
      return;
    }
    if (action.type === 'share_source_link') {
      this.emitEffect({
        type: 'share_source_url',
        title: this.snapshot.bookTitle,
        url: this.snapshot.pageUrl
      });
      return;
    }
    if (action.type === 'select_chapter') {
      this.emitEffect({ type: 'close_system_sheet' });
      this.selectChapter(action.chapterId ?? action.url ?? '');
      return;
    }
    if (action.type === 'start_reading') {
      void this.startReading();
      return;
    }
    if (action.type === 'toggle_bookshelf') {
      void this.toggleBookshelf();
      return;
    }
    if (action.type === 'dismiss_panel') {
      this.requestPanelDismissal();
      return;
    }
    if (action.type === 'panel_visibility_change') {
      this.recordPanelVisibility(action.visible);
      return;
    }
    if (action.type === 'dismiss_top_prompt') {
      this.emit({ type: 'top_prompt_changed', prompt: this.createHiddenTopPrompt() });
      return;
    }
    if (action.type === 'resolve_book_palette') {
      void this.resolveBookPalette(action.themeMode);
      return;
    }
    if (action.type === 'update_preferences') {
      this.updatePreferences(action.preferences);
      return;
    }
    if (action.type === 'progress_change') {
      this.recordProgress(action.chapterId, action.characterOffset);
      return;
    }
    if (action.type === 'status_bar_visibility_change') {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.systemStatusBarVisible = action.visible;
      this.updatePreferences(preferences);
      this.emitEffect({ type: 'status_bar_visibility_override', visible: action.visible });
      return;
    }
    if (action.type === 'status_bar_visibility_apply') {
      this.emitEffect({ type: 'status_bar_visibility_override', visible: action.visible });
    }
  }

  private loadNextChapter(intent: NovelSessionChapterIntent): void {
    const nextUrl: string = this.resolveSessionNextChapterUrl();
    if (nextUrl.length > 0) {
      void this.loadChapterByUrl(nextUrl, intent);
      return;
    }
    this.emitEffect({ type: 'toast', message: '没有下一页了' });
  }

  private loadPrevChapter(): void {
    const previousUrl: string = this.resolveSessionPreviousChapterUrl();
    if (previousUrl.length > 0) {
      void this.loadChapterByUrl(previousUrl, 'previous');
      return;
    }
    this.emitEffect({ type: 'toast', message: '没有上一页了' });
  }

  private selectChapter(chapterId: string): void {
    const chapter: NovelSessionCatalogChapter | undefined = this.findCatalogChapterById(chapterId);
    if (chapter !== undefined) {
      void this.loadChapterByUrl(chapter.canonicalUrl, 'select');
    }
  }

  /** 接管页点"开始阅读":从目录中有顺序证据的起始章进入阅读器。 */
  private async startReading(): Promise<void> {
    const sessionBeforeLoad: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    await this.ensurePersistedCheckpointLoaded();
    const currentSession: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (currentSession.sessionGeneration !== sessionBeforeLoad.sessionGeneration ||
      currentSession.bookId !== sessionBeforeLoad.bookId || currentSession.phase !== 'book') {
      return;
    }
    const persistedUrl: string = this.resolvePersistedStartReadingUrl();
    const startUrl: string = persistedUrl.length > 0 ? persistedUrl : this.resolveStartReadingUrl();
    if (startUrl.length > 0) {
      void this.loadChapterByUrl(startUrl, 'start');
    }
  }

  private retryChapterTransition(): void {
    const target: NovelSessionChapterRetryTarget | undefined =
      this.readingSessionState.failedChapterRetryTarget();
    if (target !== undefined) {
      void this.loadChapterByUrl(target.requestedUrl, target.intent);
    }
  }

  openCatalog(): void {
    // Opening the Catalog is presentation-only. Network demand starts when a range is expanded.
  }

  close(): void {
    this.closeSession(false);
  }

  private requestCloseByUser(): void {
    if (!this.snapshot.visible || this.exitConfirmationPending) {
      return;
    }
    this.exitConfirmationPending = true;
    this.emitEffect({ type: 'show_exit_confirmation', contentKind: this.snapshot.contentKind });
  }

  private suspendToHome(): void {
    if (!this.snapshot.visible || this.snapshot.phase !== 'reader' ||
      !this.readingSessionState.suspendToHome()) {
      return;
    }
    if (this.snapshot.preferences.autoReadingEnabled) {
      const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
      preferences.autoReadingEnabled = false;
      this.updatePreferences(preferences);
    }
    this.persistSessionCheckpoint();
    this.emitEffect({ type: 'close_system_sheet' });
    this.emit({ type: 'top_prompt_changed', prompt: this.createHiddenTopPrompt() });
    this.publishReadingSessionState();
    this.emitEffect({ type: 'status_bar_visibility_release' });
    this.emitEffect({ type: 'reveal_browser_home' });
  }

  private continueReading(): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (session.phase !== 'suspended' || session.tabId.length === 0 ||
      !this.readingSessionState.requestContinuation()) {
      return;
    }
    this.emitEffect({ type: 'activate_source_tab', tabId: session.tabId });
  }

  private rejectTakeover(failureCode: NovelSessionFailureCode): void {
    this.readingSessionState.end();
    this.emit({
      type: 'opening_failed',
      requestId: `${this.sessionGeneration}:open`,
      failureCode: failureCode
    });
  }

  private closeSession(reentryAvailable: boolean): void {
    const hadSessionPresentation: boolean = this.snapshot.phase !== 'inactive';
    const scope: NovelReaderSessionScope = this.copyScope(this.snapshot.scope);
    const reentryPageUrl: string = reentryAvailable ? this.activeSourcePageUrl : '';
    this.cancelAutoDetectionRetry();
    this.autoDetectionGeneration = this.autoDetectionGeneration + 1;
    this.exitConfirmationPending = false;
    this.cancelChapterPrefetch();
    this.beginOpen();
    this.activeController = undefined;
    this.runtimeAvailable = false;
    this.activeSourcePageUrl = '';
    this.pendingPersistedCheckpoint = undefined;
    this.checkpointLoadBookId = '';
    this.checkpointLoadBookDetailUrl = '';
    this.checkpointLoadTask = undefined;
    this.latestPersistedCheckpointUpdatedAt = 0;
    this.readingSessionState.end();
    this.resetSnapshot(scope);
    this.snapshot.reentryAvailable = reentryAvailable;
    this.snapshot.reentryPageUrl = reentryPageUrl;
    this.notify();
    if (hadSessionPresentation) {
      this.emitEffect({ type: 'status_bar_visibility_release' });
    }
  }

  private async loadChapterByUrl(url: string, intent: NovelSessionChapterIntent): Promise<void> {
    await this.awaitMatchingChapterPrefetch(url);
    const beforeRequest: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (beforeRequest.phase === 'inactive' || beforeRequest.phase === 'suspended') {
      return;
    }
    const chapterRequest: NovelSessionChapterRequest = this.createChapterRequest(url, intent);
    if (!this.readingSessionState.beginChapterTransition(chapterRequest)) {
      return;
    }
    this.clearPendingChapterArtifactRefresh();
    const generation: number = this.beginOpen();
    this.publishReadingSessionState();
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (this.canUsePersistentChapterCache(this.snapshot.scope)) {
      try {
        const cached: NovelChapterArtifactCacheReadResult | undefined =
          await this.chapterArtifactCacheRepository.readChapter(
            this.resolveCanonicalChapterUrl(url)
          );
        if (generation !== this.openGeneration) {
          return;
        }
        if (cached !== undefined && cached.artifact.bookId === session.bookId &&
          cached.artifact.chapterId === chapterRequest.chapterId) {
          if (!this.commitAcquiredChapter(
            chapterRequest,
            this.createChapterExtractFromArtifact(cached.artifact),
            cached.artifact.finalUrl,
            false
          )) {
            return;
          }
          this.markChapterArtifactAsLatest(cached.artifact);
          hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
            'chapter ready source=cache intent=%{public}s stale=%{public}s',
            intent, cached.refreshRecommended ? 'true' : 'false');
          const cachedController: webview.WebviewController | undefined = this.activeController;
          if (cached.refreshRecommended && intent !== 'continue_vertical' &&
            cachedController !== undefined && this.runtimeAvailable) {
            void this.refreshCachedChapter(
              cachedController,
              cached.artifact,
              intent,
              session.sessionGeneration
            );
          }
          return;
        }
      } catch (_error) {
        hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache read failed during transition');
      }
    }
    const controller: webview.WebviewController | undefined = this.activeController;
    if (controller === undefined || !this.runtimeAvailable) {
      this.readingSessionState.failChapter(chapterRequest, 'retryable');
      this.publishReadingSessionState();
      return;
    }
    try {
      const chapter: NovelChapterExtract = await this.extractionService.fetchChapter(
        controller,
        url,
        this.snapshot.contentKind
      );
      if (generation !== this.openGeneration) {
        return;
      }
      if (chapter.paragraphs.length === 0 && chapter.images.length === 0) {
        if (this.requestRenderedSourceChapter(chapterRequest, generation, url)) {
          return;
        }
        this.readingSessionState.failChapter(chapterRequest, 'content_rejected');
        this.publishReadingSessionState();
        return;
      }
      const finalPageUrl: string = chapter.pageUrl.length > 0 ? chapter.pageUrl : url;
      if (!this.commitAcquiredChapter(chapterRequest, chapter, finalPageUrl)) {
        return;
      }
    } catch (error) {
      if (generation === this.openGeneration) {
        this.readingSessionState.failChapter(
          chapterRequest,
          this.resolveChapterAcquisitionFailureCode(error)
        );
        this.publishReadingSessionState();
      }
    }
  }

  private requestRenderedSourceChapter(
    request: NovelSessionChapterRequest,
    generation: number,
    url: string
  ): boolean {
    const tabId: string = this.snapshot.scope.tabId;
    if (tabId.length === 0 || !url.startsWith('http')) {
      return false;
    }
    this.clearPendingRenderedChapter();
    this.pendingRenderedChapterRequest = request;
    this.pendingRenderedChapterGeneration = generation;
    this.pendingRenderedChapterInFlight = false;
    this.pendingRenderedChapterActiveAttempt = 0;
    const accepted: boolean = this.emitEffect({
      type: 'navigate_source_chapter',
      tabId: tabId,
      url: url
    });
    if (!accepted) {
      this.clearPendingRenderedChapter();
      return false;
    }
    this.armPendingRenderedChapterTimeout(request, generation);
    hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
      'chapter source navigation pending intent=%{public}s', request.intent);
    return true;
  }

  private resumePendingRenderedChapter(
    controller: webview.WebviewController,
    pageUrl: string
  ): void {
    const request: NovelSessionChapterRequest | undefined = this.pendingRenderedChapterRequest;
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (request === undefined || this.pendingRenderedChapterInFlight ||
      this.pendingRenderedChapterGeneration !== this.openGeneration ||
      session.chapterTransition.requestId !== request.requestId ||
      this.buildChapterIdentity(session.bookId, pageUrl) !== request.chapterId) {
      return;
    }
    const attempt: number = this.pendingRenderedChapterAttemptSequence + 1;
    this.pendingRenderedChapterAttemptSequence = attempt;
    this.pendingRenderedChapterActiveAttempt = attempt;
    this.pendingRenderedChapterInFlight = true;
    void this.completePendingRenderedChapter(controller, request, pageUrl, attempt);
  }

  private async completePendingRenderedChapter(
    controller: webview.WebviewController,
    request: NovelSessionChapterRequest,
    pageUrl: string,
    attempt: number
  ): Promise<void> {
    const generation: number = this.pendingRenderedChapterGeneration;
    try {
      const chapter: NovelChapterExtract = await this.extractionService.extractCurrent(controller, pageUrl);
      if (!this.isPendingRenderedChapterCurrent(controller, request, generation, attempt, pageUrl)) {
        this.releasePendingRenderedChapterAttempt(request, generation, attempt);
        return;
      }
      this.clearPendingRenderedChapter();
      if (chapter.paragraphs.length === 0 && chapter.images.length === 0) {
        this.readingSessionState.failChapter(request, 'content_rejected');
        this.publishReadingSessionState();
        return;
      }
      const finalPageUrl: string = chapter.pageUrl.length > 0 ? chapter.pageUrl : pageUrl;
      if (this.commitAcquiredChapter(request, chapter, finalPageUrl)) {
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'chapter ready source=rendered intent=%{public}s paragraphs=%{public}d',
          request.intent, chapter.paragraphs.length);
      }
    } catch (_error) {
      if (!this.isPendingRenderedChapterCurrent(controller, request, generation, attempt, pageUrl)) {
        this.releasePendingRenderedChapterAttempt(request, generation, attempt);
        return;
      }
      this.clearPendingRenderedChapter();
      this.readingSessionState.failChapter(request, 'retryable');
      this.publishReadingSessionState();
    }
  }

  private isPendingRenderedChapterCurrent(
    controller: webview.WebviewController,
    request: NovelSessionChapterRequest,
    generation: number,
    attempt: number,
    pageUrl: string
  ): boolean {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const requestCurrent: boolean = this.pendingRenderedChapterRequest?.requestId === request.requestId &&
      this.pendingRenderedChapterGeneration === generation && generation === this.openGeneration &&
      this.pendingRenderedChapterActiveAttempt === attempt &&
      this.activeController === controller && this.runtimeAvailable &&
      session.chapterTransition.requestId === request.requestId;
    if (!requestCurrent ||
      this.buildChapterIdentity(session.bookId, this.resolveCanonicalChapterUrl(pageUrl)) !== request.chapterId) {
      return false;
    }
    try {
      const liveUrl: string = this.resolveCanonicalChapterUrl(controller.getUrl());
      return this.buildChapterIdentity(session.bookId, liveUrl) === request.chapterId;
    } catch (_error) {
      return false;
    }
  }

  private releasePendingRenderedChapterAttempt(
    request: NovelSessionChapterRequest,
    generation: number,
    attempt: number
  ): void {
    if (this.pendingRenderedChapterRequest?.requestId !== request.requestId ||
      this.pendingRenderedChapterGeneration !== generation ||
      this.pendingRenderedChapterActiveAttempt !== attempt) {
      return;
    }
    this.pendingRenderedChapterInFlight = false;
    this.pendingRenderedChapterActiveAttempt = 0;
  }

  private armPendingRenderedChapterTimeout(
    request: NovelSessionChapterRequest,
    generation: number
  ): void {
    this.cancelPendingRenderedChapterTimeout();
    this.pendingRenderedChapterTimeoutTimer = setTimeout((): void => {
      this.pendingRenderedChapterTimeoutTimer = -1;
      const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
      if (this.pendingRenderedChapterRequest?.requestId !== request.requestId ||
        this.pendingRenderedChapterGeneration !== generation || generation !== this.openGeneration ||
        session.chapterTransition.requestId !== request.requestId) {
        return;
      }
      this.clearPendingRenderedChapter();
      if (this.readingSessionState.failChapter(request, 'retryable')) {
        this.publishReadingSessionState();
      }
    }, NOVEL_RENDERED_CHAPTER_TIMEOUT_MS);
  }

  private cancelPendingRenderedChapterTimeout(): void {
    if (this.pendingRenderedChapterTimeoutTimer < 0) {
      return;
    }
    clearTimeout(this.pendingRenderedChapterTimeoutTimer);
    this.pendingRenderedChapterTimeoutTimer = -1;
  }

  private clearPendingRenderedChapter(): void {
    this.cancelPendingRenderedChapterTimeout();
    this.pendingRenderedChapterRequest = undefined;
    this.pendingRenderedChapterGeneration = -1;
    this.pendingRenderedChapterInFlight = false;
    this.pendingRenderedChapterActiveAttempt = 0;
  }

  /** 多页章节:按第一页地址重抓一次,拿到合并后的完整正文替换当前内容。 */
  private async reloadAssembled(firstPageUrl: string, generation: number): Promise<void> {
    const controller: webview.WebviewController | undefined = this.activeController;
    if (controller === undefined) {
      return;
    }
    try {
      const full: NovelChapterExtract = await this.extractionService.fetchChapter(
        controller,
        firstPageUrl,
        this.snapshot.contentKind
      );
      if (generation !== this.openGeneration) {
        return;
      }
      const activeChapter: NovelSessionCommittedChapter | undefined = this.resolveActiveSessionChapter();
      if (activeChapter !== undefined && full.paragraphs.length > activeChapter.paragraphs.length) {
        const finalPageUrl: string = full.pageUrl.length > 0 ? full.pageUrl : firstPageUrl;
        this.applyChapter(full, finalPageUrl);
      }
    } catch (_error) {
      // 合并失败就保留第一页内容,不打扰用户。
    }
  }

  private async hydrateCatalogAndRefresh(
    catalogUrl: string,
    chapterUrl: string,
    sourceLatest: string,
    inlineSourceComplete: boolean,
    inlineTotal: number
  ): Promise<void> {
    const target: string = catalogUrl.length > 0 ? catalogUrl : this.parentDirOf(chapterUrl);
    const initialSession: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (target.length === 0 || initialSession.bookId.length === 0) {
      return;
    }
    const hydrationStartedAt: number = Date.now();
    const sessionGeneration: number = initialSession.sessionGeneration;
    const bookId: string = initialSession.bookId;
    const inlineComplete: boolean = inlineSourceComplete && inlineTotal > 0 &&
      inlineTotal === initialSession.catalog.length;
    if (inlineComplete) {
      this.catalogTotalHint = Math.max(this.catalogTotalHint, inlineTotal);
    }
    if (inlineComplete) {
      this.persistCatalogCache(target, sourceLatest, true, initialSession.catalog.map(
        (chapter: NovelSessionCatalogChapter): NovelCatalogEntry => ({
          ordinal: chapter.ordinal,
          title: chapter.title,
          url: chapter.canonicalUrl
        })
      ));
      this.catalogRefreshRecommended = false;
      this.catalogDefaultRangeHydrationPending = false;
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'catalog hydrate inline-complete entries=%{public}d durationMs=%{public}d',
        initialSession.catalog.length, Date.now() - hydrationStartedAt);
      return;
    }

    let cached: NovelCatalogCacheRecord | undefined = undefined;
    if (this.canPersistCatalogCache()) {
      try {
        cached = await this.catalogCacheRepository.read(bookId);
      } catch (_error) {
        cached = undefined;
      }
      if (!this.isCatalogHydrationCurrent(sessionGeneration, bookId)) {
        return;
      }
      const current: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
      const cacheMatches: boolean = cached !== undefined &&
        this.normalizeUrl(cached.catalogUrl) === this.normalizeUrl(target);
      if (cacheMatches && cached !== undefined &&
        current.catalogTransition.status !== 'loading' &&
        this.commitInlineCatalog(target, cached.entries, cached.complete)) {
        const cachedCursor: NovelCatalogPageCursor | undefined =
          this.cloneCatalogPageCursor(cached.pageCursor);
        if (cachedCursor !== undefined) {
          this.catalogPageCursor = cachedCursor;
        }
        const cachedTotalHint: number = cached.complete || cached.totalHint > cached.entries.length
          ? cached.totalHint
          : cached.pageCursor?.totalHint ?? 0;
        this.catalogTotalHint = Math.max(this.catalogTotalHint, cachedTotalHint);
        this.catalogRangeExtentHint = Math.max(this.catalogRangeExtentHint, this.catalogTotalHint);
        this.emit({
          type: 'catalog_ready',
          catalogUrl: target,
          bookTitle: this.snapshot.bookTitle,
          bookAuthor: this.snapshot.bookAuthor,
          bookCoverUrl: this.snapshot.bookCoverUrl,
          session: this.readingSessionState.snapshot(),
          hasMore: this.resolveCatalogHasMore(this.readingSessionState.snapshot()),
          totalHint: this.catalogTotalHint,
          supportsRandomAccess: this.catalogPageCursor !== undefined
        });
      }
      if (!cacheMatches) {
        cached = undefined;
      }
    }

    const refreshLatest: string = sourceLatest.trim().length > 0
      ? sourceLatest
      : cached?.sourceLatest ?? '';
    const shouldRefresh: boolean = this.catalogCachePolicyService.shouldRefresh(cached, refreshLatest);
    this.catalogRefreshRecommended = shouldRefresh;
    if (cached !== undefined && shouldRefresh &&
      this.readingSessionState.snapshot().catalogTransition.status !== 'loading') {
      this.emit({
        type: 'catalog_ready',
        catalogUrl: target,
        bookTitle: this.snapshot.bookTitle,
        bookAuthor: this.snapshot.bookAuthor,
        bookCoverUrl: this.snapshot.bookCoverUrl,
        session: this.readingSessionState.snapshot(),
        hasMore: true,
        totalHint: this.catalogTotalHint,
        supportsRandomAccess: this.catalogPageCursor !== undefined
      });
    }
    hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
      'catalog hydrate cacheHit=%{public}s refresh=%{public}s durationMs=%{public}d',
      cached === undefined ? 'false' : 'true', shouldRefresh ? 'true' : 'false',
      Date.now() - hydrationStartedAt);
    if (!this.isCatalogHydrationCurrent(sessionGeneration, bookId)) {
      return;
    }
    const hydrated: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (cached === undefined && hydrated.catalog.length > 0) {
      this.persistCatalogCache(target, refreshLatest, hydrated.catalogComplete, this.sessionCatalogEntries(hydrated));
    }
    this.requestDefaultCatalogRangeHydration();
  }

  /** 第一组默认展开：先交付现有标题，再在运行时可用时补齐该组。 */
  private requestDefaultCatalogRangeHydration(): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (session.phase === 'inactive' || session.bookId.length === 0) {
      this.catalogDefaultRangeHydrationPending = false;
      return;
    }
    const entries: NovelCatalogEntry[] = this.sessionCatalogEntries(session);
    const rangeComplete: boolean = this.isCatalogRangeComplete(
      entries,
      0,
      NOVEL_CATALOG_RANGE_SIZE - 1,
      this.catalogTotalHint,
      session.catalogComplete
    );
    if (!this.catalogRefreshRecommended && rangeComplete) {
      this.catalogDefaultRangeHydrationPending = false;
      return;
    }
    if (session.phase === 'suspended' || this.activeController === undefined || !this.runtimeAvailable ||
      session.catalogTransition.status === 'loading') {
      this.catalogDefaultRangeHydrationPending = true;
      return;
    }
    this.catalogDefaultRangeHydrationPending = false;
    this.loadCatalogRange(0, NOVEL_CATALOG_RANGE_SIZE - 1);
  }

  /** 只加载已展开的 100 章范围；第一组由默认展开策略触发，后续组由用户触发。 */
  private loadCatalogRange(requestedStartOrdinal: number, requestedEndOrdinal: number): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (session.catalogTransition.status === 'loading') {
      return;
    }
    const startOrdinal: number = Math.floor(Math.max(0, requestedStartOrdinal) /
      NOVEL_CATALOG_RANGE_SIZE) * NOVEL_CATALOG_RANGE_SIZE;
    const endOrdinal: number = Math.min(
      startOrdinal + NOVEL_CATALOG_RANGE_SIZE - 1,
      Math.max(startOrdinal, Math.floor(requestedEndOrdinal))
    );
    if (this.catalogTotalHint > 0 && startOrdinal >= this.catalogTotalHint) {
      return;
    }
    const currentEntries: NovelCatalogEntry[] = this.sessionCatalogEntries(session);
    if (!this.catalogRefreshRecommended && this.isCatalogRangeComplete(
      currentEntries,
      startOrdinal,
      endOrdinal,
      this.catalogTotalHint,
      session.catalogComplete
    )) {
      return;
    }
    if (this.catalogPageCursor === undefined &&
      !this.canLoadSequentialCatalogRange(currentEntries, startOrdinal)) {
      return;
    }
    const target: string = this.snapshot.catalogUrl.length > 0
      ? this.snapshot.catalogUrl
      : this.parentDirOf(this.snapshot.pageUrl);
    if (target.length === 0) {
      return;
    }
    const catalogRequest: NovelSessionCatalogRequest = this.createCatalogRequest(target);
    if (!this.readingSessionState.beginCatalogTransition(catalogRequest)) {
      return;
    }
    hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
      'loadCatalogRange target=%{public}s start=%{public}d end=%{public}d random=%{public}s',
      target, startOrdinal, endOrdinal, this.catalogPageCursor === undefined ? 'false' : 'true');
    this.emit({
      type: 'catalog_loading',
      catalogUrl: target,
      session: this.readingSessionState.snapshot(),
      rangeStartOrdinal: startOrdinal,
      rangeEndOrdinal: endOrdinal
    });
    const controller: webview.WebviewController | undefined = this.activeController;
    if (controller === undefined || !this.runtimeAvailable) {
      this.readingSessionState.failCatalog(catalogRequest, 'retryable');
      this.emit({ type: 'catalog_failed', session: this.readingSessionState.snapshot() });
      return;
    }
    void this.acquireAndCommitCatalogRange(
      controller,
      target,
      catalogRequest,
      this.snapshot.bookLatest,
      startOrdinal,
      endOrdinal
    );
  }

  private async acquireAndCommitCatalogRange(
    controller: webview.WebviewController,
    catalogUrl: string,
    catalogRequest: NovelSessionCatalogRequest,
    sourceLatest: string,
    startOrdinal: number,
    endOrdinal: number
  ): Promise<void> {
    const startedAt: number = Date.now();
    try {
      const result: NovelCatalogWindowLoadResult = await this.acquireCatalogRange(
        controller,
        catalogUrl,
        startOrdinal,
        endOrdinal
      );
      if (result.entries.length === 0) {
        throw new Error('novel-catalog-empty');
      }
      const catalogChapters: NovelSessionCatalogChapter[] = result.entries.map(
        (entry: NovelCatalogEntry): NovelSessionCatalogChapter => ({
          id: this.buildChapterIdentity(this.readingSessionState.snapshot().bookId, entry.url),
          title: entry.title,
          canonicalUrl: entry.url,
          ordinal: entry.ordinal
        })
      );
      const catalogCommit: NovelSessionCatalogCommit = {
        catalogUrl: catalogUrl,
        chapters: catalogChapters,
        complete: result.complete
      };
      if (!this.readingSessionState.commitCatalog(catalogRequest, catalogCommit)) {
        return;
      }
      this.catalogPageCursor = this.cloneCatalogPageCursor(result.pageCursor);
      this.catalogTotalHint = Math.max(this.catalogTotalHint, result.totalHint);
      this.catalogRangeExtentHint = Math.max(this.catalogRangeExtentHint, this.catalogTotalHint);
      this.catalogRefreshRecommended = false;
      const committedSession: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
      const hasMore: boolean = this.resolveCatalogHasMore(committedSession);
      this.emit({
        type: 'catalog_ready',
        catalogUrl: catalogUrl,
        bookTitle: this.snapshot.bookTitle.trim().length > 0 ? this.snapshot.bookTitle : result.bookTitle,
        bookAuthor: result.author.length > 0 ? result.author : this.snapshot.bookAuthor,
        bookCoverUrl: this.snapshot.bookCoverUrl.trim().length > 0
          ? this.snapshot.bookCoverUrl
          : result.coverUrl,
        session: committedSession,
        hasMore: hasMore,
        totalHint: this.catalogTotalHint,
        supportsRandomAccess: this.catalogPageCursor !== undefined
      });
      this.refreshPersistedBookMetadata();
      this.persistCatalogCache(catalogUrl, sourceLatest, result.complete, result.entries);
      this.scheduleNextChapterPrefetch();
      if (this.catalogDefaultRangeHydrationPending) {
        this.requestDefaultCatalogRangeHydration();
      }
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'catalog loaded entries=%{public}d complete=%{public}s durationMs=%{public}d',
        result.entries.length, result.complete ? 'true' : 'false', Date.now() - startedAt);
    } catch (_error) {
      if (!this.readingSessionState.failCatalog(catalogRequest, 'retryable')) {
        return;
      }
      hilog.error(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'catalog load failed durationMs=%{public}d retainedEntries=%{public}d',
        Date.now() - startedAt, this.snapshot.catalog.length);
      this.emit({ type: 'catalog_failed', session: this.readingSessionState.snapshot() });
    }
  }

  private async acquireCatalogRange(
    controller: webview.WebviewController,
    catalogUrl: string,
    startOrdinal: number,
    endOrdinal: number
  ): Promise<NovelCatalogWindowLoadResult> {
    const current: NovelCatalogEntry[] = this.snapshot.catalog.map(
      (entry: NovelReaderCatalogEntry): NovelCatalogEntry => ({
        ordinal: entry.ordinal,
        title: entry.title,
        url: entry.url
      })
    );
    const cursor: NovelCatalogPageCursor | undefined = this.cloneCatalogPageCursor(this.catalogPageCursor);
    if (cursor !== undefined) {
      let entries: NovelCatalogEntry[] = current;
      let sourceCursor: NovelCatalogPageCursor = cursor;
      let loadedPages: number = 0;
      const firstPageNumber: number = cursor.initialPage + Math.floor(startOrdinal / cursor.pageSize);
      const finalPageNumber: number = cursor.initialPage + Math.floor(endOrdinal / cursor.pageSize);
      for (let pageNumber = firstPageNumber; pageNumber <= finalPageNumber; pageNumber += 1) {
        const pageStartOrdinal: number = (pageNumber - cursor.initialPage) * cursor.pageSize;
        const pageEndOrdinal: number = pageStartOrdinal + cursor.pageSize - 1;
        const knownTotalHint: number = Math.max(this.catalogTotalHint, sourceCursor.totalHint);
        if (knownTotalHint > 0 && pageStartOrdinal >= knownTotalHint) {
          break;
        }
        if (!this.catalogRefreshRecommended && this.isCatalogRangeComplete(
          entries,
          pageStartOrdinal,
          pageEndOrdinal,
          knownTotalHint,
          false
        )) {
          continue;
        }
        const requestCursor: NovelCatalogPageCursor = this.cloneCatalogPageCursor(sourceCursor) as
          NovelCatalogPageCursor;
        requestCursor.nextPage = pageNumber;
        const page: NovelCatalogPageResult | undefined = await this.extractionService.fetchCatalogPage(
          controller,
          catalogUrl,
          requestCursor
        );
        if (page === undefined) {
          throw new Error('novel-catalog-page-failed');
        }
        entries = this.catalogCachePolicyService.mergeMonotonic(entries, page.entries);
        sourceCursor.totalHint = Math.max(sourceCursor.totalHint, page.cursor.totalHint);
        sourceCursor.totalPages = Math.max(sourceCursor.totalPages, page.cursor.totalPages);
        sourceCursor.nextPage = page.cursor.nextPage;
        loadedPages += 1;
      }
      if (loadedPages === 0) {
        throw new Error('novel-catalog-page-empty');
      }
      const totalHint: number = Math.max(this.catalogTotalHint, sourceCursor.totalHint);
      const complete: boolean = totalHint > 0 && this.hasEveryCatalogOrdinal(entries, totalHint);
      return {
        bookTitle: '',
        author: '',
        coverUrl: '',
        entries: entries,
        complete: complete,
        totalHint: totalHint,
        pageCursor: sourceCursor
      };
    }
    const fetched: NovelCatalogResult = await this.extractionService.fetchCatalog(
      controller,
      catalogUrl,
      endOrdinal + 1
    );
    const entries: NovelCatalogEntry[] = this.catalogCachePolicyService.mergeMonotonic(current, fetched.entries);
    return {
      bookTitle: fetched.bookTitle,
      author: fetched.author,
      coverUrl: fetched.coverUrl,
      entries: entries,
      complete: fetched.complete,
      totalHint: fetched.complete ? Math.max(this.catalogTotalHint, this.highestCatalogOrdinal(entries) + 1) :
        this.catalogTotalHint
    };
  }

  private canLoadSequentialCatalogRange(entries: NovelCatalogEntry[], startOrdinal: number): boolean {
    const nextRangeStart: number = Math.floor((this.highestCatalogOrdinal(entries) + 1) /
      NOVEL_CATALOG_RANGE_SIZE) * NOVEL_CATALOG_RANGE_SIZE;
    return startOrdinal <= Math.max(0, nextRangeStart);
  }

  private isCatalogRangeComplete(
    entries: NovelCatalogEntry[],
    startOrdinal: number,
    requestedEndOrdinal: number,
    totalHint: number,
    complete: boolean
  ): boolean {
    if (totalHint > 0 && startOrdinal >= totalHint) {
      return true;
    }
    const endOrdinal: number = totalHint > 0
      ? Math.min(requestedEndOrdinal, totalHint - 1)
      : requestedEndOrdinal;
    if (endOrdinal < startOrdinal) {
      return true;
    }
    if (complete && endOrdinal > this.highestCatalogOrdinal(entries)) {
      return true;
    }
    for (let ordinal: number = startOrdinal; ordinal <= endOrdinal; ordinal += 1) {
      if (!this.hasCatalogOrdinal(entries, ordinal)) {
        return false;
      }
    }
    return true;
  }

  private hasEveryCatalogOrdinal(entries: NovelCatalogEntry[], totalHint: number): boolean {
    if (totalHint <= 0 || entries.length < totalHint) {
      return false;
    }
    return this.isCatalogRangeComplete(entries, 0, totalHint - 1, totalHint, false);
  }

  private hasCatalogOrdinal(entries: NovelCatalogEntry[], ordinal: number): boolean {
    for (let index: number = 0; index < entries.length; index += 1) {
      if (entries[index].ordinal === ordinal) {
        return true;
      }
    }
    return false;
  }

  private highestCatalogOrdinal(entries: NovelCatalogEntry[]): number {
    let highest: number = -1;
    for (let index: number = 0; index < entries.length; index += 1) {
      highest = Math.max(highest, entries[index].ordinal);
    }
    return highest;
  }

  private persistCatalogCache(
    catalogUrl: string,
    sourceLatest: string,
    complete: boolean,
    entries: NovelCatalogEntry[]
  ): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (!this.canPersistCatalogCache() || session.bookId.length === 0 || entries.length === 0) {
      return;
    }
    const record: NovelCatalogCacheRecord = {
      bookId: session.bookId,
      catalogUrl: catalogUrl,
      sourceLatest: sourceLatest,
      complete: complete,
      cachedAt: Date.now(),
      entries: entries.map((entry: NovelCatalogEntry): NovelCatalogEntry => ({
        ordinal: entry.ordinal,
        title: entry.title,
        url: entry.url
      })),
      totalHint: this.catalogTotalHint,
      pageCursor: this.cloneCatalogPageCursor(this.catalogPageCursor)
    };
    void this.catalogCacheRepository.write(record).catch((_error: Error): void => {});
  }

  private canPersistCatalogCache(): boolean {
    return this.snapshot.scope.privacyMode === 'regular' &&
      this.snapshot.scope.dataScope === 'profile_persistent';
  }

  private sessionCatalogEntries(session: NovelReadingSessionSnapshot): NovelCatalogEntry[] {
    return session.catalog.map((chapter: NovelSessionCatalogChapter): NovelCatalogEntry => ({
      ordinal: chapter.ordinal,
      title: chapter.title,
      url: chapter.canonicalUrl
    }));
  }

  private resolveCatalogHasMore(session: NovelReadingSessionSnapshot): boolean {
    if (this.catalogRefreshRecommended) {
      return true;
    }
    if (session.catalogComplete) {
      return false;
    }
    if (this.catalogPageCursor !== undefined) {
      return true;
    }
    return this.catalogTotalHint > session.catalog.length || !session.catalogComplete;
  }

  private isCatalogHydrationCurrent(sessionGeneration: number, bookId: string): boolean {
    const current: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    return current.sessionGeneration === sessionGeneration && current.bookId === bookId &&
      current.phase !== 'inactive' && current.phase !== 'suspended';
  }

  private createCatalogRequest(catalogUrl: string): NovelSessionCatalogRequest {
    this.catalogRequestSequence = this.catalogRequestSequence + 1;
    return {
      requestId: `${this.sessionGeneration}:catalog:${this.catalogRequestSequence}`,
      sessionGeneration: this.sessionGeneration,
      tabId: this.snapshot.scope.tabId,
      privacyMode: this.snapshot.scope.privacyMode,
      catalogUrl: catalogUrl
    };
  }

  private resolveActiveSessionChapter(): NovelSessionCommittedChapter | undefined {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    for (let index: number = 0; index < session.chapterTrail.length; index++) {
      if (session.chapterTrail[index].id === session.activeChapterId) {
        return session.chapterTrail[index];
      }
    }
    return undefined;
  }

  /** 目录顺序优先;只有当前章不在目录中时,才使用页面提供的相邻章节链接。 */
  private resolveSessionPreviousChapterUrl(): string {
    const chapter: NovelSessionCommittedChapter | undefined = this.resolveActiveSessionChapter();
    if (chapter === undefined) {
      return '';
    }
    const index: number = this.findCatalogIndex(chapter.canonicalUrl);
    const catalog: NovelSessionCatalogChapter[] = this.readingSessionState.snapshot().catalog;
    if (index >= 0) {
      const previous: NovelSessionCatalogChapter | undefined =
        this.findCatalogChapterByOrdinal(catalog[index].ordinal - 1);
      if (previous !== undefined) {
        return previous.canonicalUrl;
      }
      if (catalog[index].ordinal === 0) {
        return '';
      }
    }
    if (this.resolveChapterOrdinal(chapter.title) === 1) {
      return '';
    }
    return this.resolvePageProvidedChapterUrl(chapter.prevUrl, chapter);
  }

  private resolveSessionNextChapterUrl(): string {
    const chapter: NovelSessionCommittedChapter | undefined = this.resolveActiveSessionChapter();
    if (chapter === undefined) {
      return '';
    }
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const index: number = this.findCatalogIndex(chapter.canonicalUrl);
    if (index >= 0) {
      const next: NovelSessionCatalogChapter | undefined =
        this.findCatalogChapterByOrdinal(session.catalog[index].ordinal + 1);
      if (next !== undefined) {
        return next.canonicalUrl;
      }
    }
    if (index >= 0 && session.catalogComplete) {
      return '';
    }
    return this.resolvePageProvidedChapterUrl(chapter.nextUrl, chapter);
  }

  private resolvePageProvidedChapterUrl(
    candidate: string,
    chapter: NovelSessionCommittedChapter
  ): string {
    const target: string = this.normalizeUrl(candidate);
    if (target.length === 0 || target === this.normalizeUrl(chapter.canonicalUrl) ||
      target === this.normalizeUrl(chapter.requestedUrl) || target === this.normalizeUrl(chapter.finalUrl) ||
      target === this.normalizeUrl(chapter.catalogUrl)) {
      return '';
    }
    return candidate;
  }

  private findCatalogIndex(chapterUrl: string): number {
    const target: string = this.normalizeUrl(chapterUrl);
    if (target.length === 0) {
      return -1;
    }
    const catalog: NovelSessionCatalogChapter[] = this.readingSessionState.snapshot().catalog;
    for (let i = 0; i < catalog.length; i++) {
      if (this.normalizeUrl(catalog[i].canonicalUrl) === target) {
        return i;
      }
    }
    return -1;
  }

  private findCatalogChapterByOrdinal(ordinal: number): NovelSessionCatalogChapter | undefined {
    const catalog: NovelSessionCatalogChapter[] = this.readingSessionState.snapshot().catalog;
    for (let index: number = 0; index < catalog.length; index += 1) {
      if (catalog[index].ordinal === ordinal) {
        return catalog[index];
      }
    }
    return undefined;
  }

  private parentDirOf(url: string): string {
    return this.sourceIdentityService.parentDirectory(url);
  }

  private buildBookIdentity(catalogUrl: string, pageUrl: string): string {
    return this.sourceIdentityService.buildBookIdentity(catalogUrl, pageUrl);
  }

  private buildChapterIdentity(bookId: string, canonicalUrl: string): string {
    return this.sourceIdentityService.buildChapterIdentity(bookId, canonicalUrl);
  }

  private resolveCanonicalChapterUrl(requestedUrl: string): string {
    const target: string = this.normalizeUrl(requestedUrl);
    const catalog: NovelSessionCatalogChapter[] = this.readingSessionState.snapshot().catalog;
    for (let index: number = 0; index < catalog.length; index++) {
      const entry: NovelSessionCatalogChapter = catalog[index];
      if (this.normalizeUrl(entry.canonicalUrl) === target) {
        return entry.canonicalUrl;
      }
    }
    return requestedUrl;
  }

  private normalizeUrl(url: string): string {
    return this.sourceIdentityService.normalizeUrl(url);
  }

  private isDigits(value: string): boolean {
    if (value.length === 0) {
      return false;
    }
    for (let index = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private resolveStartReadingUrl(): string {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (this.isValidSourceChapterUrl(session.startChapterUrl)) {
      return session.startChapterUrl;
    }
    const catalog: NovelSessionCatalogChapter[] = session.catalog;
    if (catalog.length === 0) {
      return '';
    }
    let firstOrdinal: number = -1;
    let lastOrdinal: number = -1;
    let minimumOrdinal: number = -1;
    let minimumOrdinalIndex: number = -1;
    let ordinalCount: number = 0;
    for (let index = 0; index < catalog.length; index++) {
      const ordinal: number = this.resolveChapterOrdinal(catalog[index].title);
      if (ordinal >= 0) {
        if (firstOrdinal < 0) {
          firstOrdinal = ordinal;
        }
        lastOrdinal = ordinal;
        ordinalCount = ordinalCount + 1;
        if (minimumOrdinal < 0 || ordinal < minimumOrdinal) {
          minimumOrdinal = ordinal;
          minimumOrdinalIndex = index;
        }
      }
    }
    if (ordinalCount < 2 || minimumOrdinalIndex < 0) {
      return catalog[0].canonicalUrl;
    }
    if (firstOrdinal > lastOrdinal) {
      const finalIndex: number = catalog.length - 1;
      return this.isStartChapterMarker(catalog[finalIndex].title)
        ? catalog[finalIndex].canonicalUrl
        : catalog[minimumOrdinalIndex].canonicalUrl;
    }
    return this.isStartChapterMarker(catalog[0].title)
      ? catalog[0].canonicalUrl
      : catalog[minimumOrdinalIndex].canonicalUrl;
  }

  private findCatalogChapterById(chapterId: string): NovelSessionCatalogChapter | undefined {
    const catalog: NovelSessionCatalogChapter[] = this.readingSessionState.snapshot().catalog;
    for (let index: number = 0; index < catalog.length; index++) {
      if (catalog[index].id === chapterId) {
        return catalog[index];
      }
    }
    return undefined;
  }

  private resolvePersistedStartReadingUrl(): string {
    const pending: NovelReadingCheckpointRecord | undefined = this.pendingPersistedCheckpoint;
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (pending === undefined || session.privacyMode !== 'regular' || pending.bookId !== session.bookId) {
      return '';
    }
    const chapter: NovelSessionCatalogChapter | undefined = this.findCatalogChapterById(pending.chapterId);
    if (chapter !== undefined &&
      this.normalizeUrl(chapter.canonicalUrl) === this.normalizeUrl(pending.canonicalUrl)) {
      return chapter.canonicalUrl;
    }
    if (pending.chapterId !== this.buildChapterIdentity(session.bookId, pending.canonicalUrl) ||
      !this.isValidSourceChapterUrl(pending.canonicalUrl)) {
      return '';
    }
    return pending.canonicalUrl;
  }

  private isStartChapterMarker(title: string): boolean {
    return title.indexOf('楔子') >= 0 || title.indexOf('序章') >= 0 || title.indexOf('序言') >= 0 ||
      title.indexOf('前言') >= 0 || title.indexOf('引子') >= 0 || title.indexOf('开篇') >= 0;
  }

  private resolveChapterOrdinal(title: string): number {
    const value: string = title.trim();
    if (value.length === 0) {
      return -1;
    }
    if (this.isDigits(value)) {
      return parseInt(value, 10);
    }
    const start: number = value.indexOf('第');
    if (start >= 0) {
      const end: number = this.findChapterOrdinalSuffix(value, start + 1);
      if (end > start + 1) {
        return this.parseChapterOrdinalToken(value.substring(start + 1, end).trim());
      }
    }
    const prefixEnd: number = this.findChapterOrdinalSuffix(value, 0);
    if (prefixEnd > 0) {
      return this.parseChapterOrdinalToken(value.substring(0, prefixEnd).trim());
    }
    return -1;
  }

  private findChapterOrdinalSuffix(value: string, start: number): number {
    const suffixes: string[] = ['章', '话', '回', '節', '节'];
    let result: number = -1;
    for (let index = 0; index < suffixes.length; index++) {
      const found: number = value.indexOf(suffixes[index], start);
      if (found >= start && (result < 0 || found < result)) {
        result = found;
      }
    }
    return result;
  }

  private parseChapterOrdinalToken(token: string): number {
    if (this.isDigits(token)) {
      return parseInt(token, 10);
    }
    let digitSequence: number = 0;
    let hasOnlyChineseDigits: boolean = token.length > 0;
    for (let index: number = 0; index < token.length; index += 1) {
      const digit: number = this.resolveChineseDigit(token.charAt(index));
      if (digit < 0) {
        hasOnlyChineseDigits = false;
        break;
      }
      digitSequence = digitSequence * 10 + digit;
    }
    if (hasOnlyChineseDigits) {
      return digitSequence;
    }
    let total: number = 0;
    let section: number = 0;
    let digit: number = -1;
    let recognized: boolean = false;
    for (let index = 0; index < token.length; index++) {
      const character: string = token.charAt(index);
      const chineseDigit: number = this.resolveChineseDigit(character);
      if (chineseDigit >= 0) {
        digit = chineseDigit;
        recognized = true;
        continue;
      }
      const unit: number = this.resolveChineseUnit(character);
      if (unit < 0) {
        return -1;
      }
      recognized = true;
      if (unit === 10000) {
        section = section + (digit >= 0 ? digit : 0);
        total = total + Math.max(1, section) * unit;
        section = 0;
      } else {
        section = section + (digit >= 0 ? digit : 1) * unit;
      }
      digit = -1;
    }
    if (!recognized) {
      return -1;
    }
    return total + section + (digit >= 0 ? digit : 0);
  }

  private resolveChineseDigit(character: string): number {
    if (character === '零' || character === '〇') { return 0; }
    if (character === '一') { return 1; }
    if (character === '二' || character === '两') { return 2; }
    if (character === '三') { return 3; }
    if (character === '四') { return 4; }
    if (character === '五') { return 5; }
    if (character === '六') { return 6; }
    if (character === '七') { return 7; }
    if (character === '八') { return 8; }
    if (character === '九') { return 9; }
    return -1;
  }

  private resolveChineseUnit(character: string): number {
    if (character === '十') { return 10; }
    if (character === '百') { return 100; }
    if (character === '千') { return 1000; }
    if (character === '万') { return 10000; }
    return -1;
  }

  private applyBookOverview(overview: NovelBookOverview, detailUrl: string): void {
    const catalogUrl: string = overview.catalogUrl.length > 0 ? overview.catalogUrl : detailUrl;
    const bookId: string = this.buildBookIdentity(catalogUrl, detailUrl);
    const detailBookId: string = this.buildBookIdentity(detailUrl, detailUrl);
    this.checkpointFallbackBookId = detailBookId !== bookId ? detailBookId : '';
    this.catalogPageCursor = this.cloneCatalogPageCursor(overview.catalogPageCursor);
    const overviewComplete: boolean = overview.catalogSourceComplete && overview.catalogTotal > 0 &&
      overview.catalogTotal === overview.initialEntries.length;
    this.catalogTotalHint = Math.max(
      overviewComplete ? overview.catalogTotal : 0,
      overview.catalogPageCursor?.totalHint ?? 0
    );
    const latestChapterOrdinal: number = this.catalogPageCursor === undefined
      ? -1
      : this.resolveChapterOrdinal(overview.latest);
    this.catalogRangeExtentHint = Math.max(
      this.catalogTotalHint,
      overview.initialEntries.length,
      latestChapterOrdinal > 0 ? latestChapterOrdinal : 0
    );
    this.catalogRefreshRecommended = false;
    this.readingSessionState.setBookIdentity(bookId);
    this.commitInlineCatalog(
      catalogUrl,
      overview.initialEntries,
      overviewComplete
    );
    this.readingSessionState.markBookReady(overview.startChapterUrl);
    void this.ensurePersistedCheckpointLoaded(detailUrl);
    const bookshelfAvailable: boolean = this.snapshot.scope.privacyMode === 'regular' &&
      this.snapshot.scope.dataScope === 'profile_persistent';
    this.emit({
      type: 'book_overview_ready',
      overview: overview,
      detailUrl: detailUrl,
      catalogUrl: catalogUrl,
      bookshelfAvailable: bookshelfAvailable,
      session: this.readingSessionState.snapshot()
    });
    void this.refreshBookshelfMembership(this.openGeneration, detailUrl);
  }

  private applyUsableBookOverview(overview: NovelBookOverview, pageUrl: string): boolean {
    const hasSeparateCatalog: boolean = overview.catalogUrl.length > 0 &&
      this.normalizeUrl(overview.catalogUrl) !== this.normalizeUrl(pageUrl);
    if (overview.initialEntries.length < 5 && overview.startChapterUrl.length === 0 && !hasSeparateCatalog) {
      return false;
    }
    this.applyBookOverview(overview, pageUrl);
    void this.hydrateCatalogAndRefresh(
      hasSeparateCatalog ? overview.catalogUrl : pageUrl,
      pageUrl,
      overview.latest,
      !hasSeparateCatalog && overview.catalogSourceComplete,
      overview.catalogTotal
    );
    return true;
  }

  private applyChapter(chapter: NovelChapterExtract, pageUrl: string): void {
    const bookIdentity: string = this.buildBookIdentity(chapter.catalogUrl, pageUrl);
    this.readingSessionState.setBookIdentity(bookIdentity);
    void this.ensurePersistedCheckpointLoaded();
    const request: NovelSessionChapterRequest = this.createChapterRequest(pageUrl, 'select');
    if (!this.readingSessionState.beginChapterTransition(request)) {
      return;
    }
    this.commitAcquiredChapter(request, chapter, pageUrl);
  }

  private commitInlineCatalog(
    catalogUrl: string,
    entries: NovelCatalogEntry[],
    complete: boolean = false
  ): boolean {
    if (catalogUrl.length === 0 || entries.length === 0) {
      return false;
    }
    const currentSession: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const mergedEntries: NovelCatalogEntry[] = this.catalogCachePolicyService.mergeMonotonic(
      this.sessionCatalogEntries(currentSession),
      entries
    );
    const request: NovelSessionCatalogRequest = this.createCatalogRequest(catalogUrl);
    if (!this.readingSessionState.beginCatalogTransition(request)) {
      return false;
    }
    const bookId: string = this.readingSessionState.snapshot().bookId;
    const chapters: NovelSessionCatalogChapter[] = mergedEntries.map(
      (entry: NovelCatalogEntry): NovelSessionCatalogChapter => ({
        id: this.buildChapterIdentity(bookId, entry.url),
        title: entry.title,
        canonicalUrl: entry.url,
        ordinal: entry.ordinal
      })
    );
    return this.readingSessionState.commitCatalog(request, {
      catalogUrl: catalogUrl,
      chapters: chapters,
      complete: currentSession.catalogComplete || complete
    });
  }

  private commitAcquiredChapter(
    request: NovelSessionChapterRequest,
    chapter: NovelChapterExtract,
    finalPageUrl: string,
    persistArtifact: boolean = true
  ): boolean {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const canonicalUrl: string = this.resolveCanonicalChapterUrl(request.requestedUrl);
    const finalCanonicalUrl: string = this.resolveCanonicalChapterUrl(finalPageUrl);
    if (this.buildChapterIdentity(session.bookId, finalCanonicalUrl) !== request.chapterId) {
      this.readingSessionState.failChapter(request, 'identity_mismatch');
      this.publishReadingSessionState();
      return false;
    }
    this.contentRevisionSequence = this.contentRevisionSequence + 1;
    const resolvedChapterTitle: string = this.resolveCommittedChapterTitle(
      session,
      request.chapterId,
      chapter.title
    );
    const committedChapter: NovelSessionCommittedChapter = {
      id: request.chapterId,
      bookId: session.bookId,
      canonicalUrl: canonicalUrl,
      requestedUrl: request.requestedUrl,
      finalUrl: finalPageUrl,
      title: resolvedChapterTitle,
      contentKind: this.comicChapterAcquisitionEngine.resolveContentKind(chapter.images),
      paragraphs: chapter.paragraphs.slice(),
      images: chapter.images.slice(),
      prevUrl: chapter.prevUrl,
      nextUrl: chapter.nextUrl,
      catalogUrl: chapter.catalogUrl.length > 0 ? chapter.catalogUrl : this.snapshot.catalogUrl,
      revision: this.contentRevisionSequence
    };
    const commit: NovelSessionChapterCommit = { chapter: committedChapter };
    if (!this.readingSessionState.commitChapter(request, commit)) {
      if (this.readingSessionState.failChapter(request, 'content_rejected')) {
        this.publishReadingSessionState();
      }
      return false;
    }
    const resolvedBookTitle: string = this.snapshot.bookTitle.trim().length > 0
      ? this.snapshot.bookTitle
      : chapter.bookTitle;
    this.publishReadingSessionState(resolvedBookTitle);
    this.initializeReaderBookshelfContext(committedChapter.catalogUrl, committedChapter.canonicalUrl);
    this.applyLoadedCheckpointIfMatching();
    if (persistArtifact) {
      this.persistChapterArtifact(committedChapter, resolvedBookTitle);
    }
    this.scheduleNextChapterPrefetch();
    return true;
  }

  private resolveCommittedChapterTitle(
    session: NovelReadingSessionSnapshot,
    chapterId: string,
    extractedTitle: string
  ): string {
    for (let index: number = 0; index < session.catalog.length; index++) {
      const candidate: NovelSessionCatalogChapter = session.catalog[index];
      if (candidate.id === chapterId && candidate.title.trim().length > 0) {
        return candidate.title.trim();
      }
    }
    return extractedTitle.trim();
  }

  private persistChapterArtifact(
    chapter: NovelSessionCommittedChapter,
    bookTitle: string
  ): void {
    if (!this.canUsePersistentChapterCache(this.snapshot.scope)) {
      return;
    }
    const detailUrl: string = this.snapshot.bookshelfDetailUrl.trim().length > 0
      ? this.snapshot.bookshelfDetailUrl
      : (chapter.catalogUrl.trim().length > 0
        ? chapter.catalogUrl
        : this.sourceIdentityService.parentDirectory(chapter.canonicalUrl));
    const cacheCatalogUrl: string = this.resolveChapterArtifactCatalogUrl(
      chapter.bookId,
      chapter.catalogUrl,
      detailUrl,
      chapter.canonicalUrl
    );
    const record: NovelChapterArtifactCacheRecord = {
      bookId: chapter.bookId,
      chapterId: chapter.id,
      bookDetailUrl: detailUrl,
      bookTitle: bookTitle,
      canonicalUrl: chapter.canonicalUrl,
      requestedUrl: chapter.requestedUrl,
      finalUrl: chapter.finalUrl,
      title: chapter.title,
      contentKind: chapter.contentKind,
      paragraphs: chapter.paragraphs.slice(),
      images: chapter.images.slice(),
      prevUrl: chapter.prevUrl,
      nextUrl: chapter.nextUrl,
      catalogUrl: cacheCatalogUrl,
      cachedAt: Date.now()
    };
    this.writeChapterArtifact(record);
  }

  private writeChapterArtifact(record: NovelChapterArtifactCacheRecord): void {
    void this.chapterArtifactCacheRepository.write(record).catch((_error: Error): void => {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache write failed');
    });
  }

  private markChapterArtifactAsLatest(record: NovelChapterArtifactCacheRecord): void {
    void this.chapterArtifactCacheRepository.markLatestForBook(record).catch((_error: Error): void => {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache recent reference update failed');
    });
  }

  private scheduleNextChapterPrefetch(): void {
    this.cancelChapterPrefetch();
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const controller: webview.WebviewController | undefined = this.activeController;
    const targetUrl: string = this.resolveSessionNextChapterUrl();
    if (!this.canUsePersistentChapterCache(this.snapshot.scope) || controller === undefined ||
      !this.runtimeAvailable || session.phase !== 'reader' || session.activeChapterId.length === 0 ||
      session.chapterTransition.status !== 'idle' || targetUrl.length === 0) {
      return;
    }
    this.chapterPrefetchTargetUrl = targetUrl;
    const revision: number = this.chapterPrefetchRevision;
    this.chapterPrefetchTimer = setTimeout((): void => {
      this.chapterPrefetchTimer = -1;
      if (revision === this.chapterPrefetchRevision) {
        void this.startChapterPrefetch();
      }
    }, NOVEL_CHAPTER_PREFETCH_DELAY_MS);
  }

  private async awaitMatchingChapterPrefetch(url: string): Promise<void> {
    const target: string = this.normalizeUrl(url);
    if (target.length === 0 || target !== this.normalizeUrl(this.chapterPrefetchTargetUrl)) {
      this.cancelChapterPrefetch();
      return;
    }
    if (this.chapterPrefetchTimer >= 0) {
      clearTimeout(this.chapterPrefetchTimer);
      this.chapterPrefetchTimer = -1;
    }
    await this.startChapterPrefetch();
  }

  private startChapterPrefetch(): Promise<void> {
    if (this.chapterPrefetchTask !== undefined) {
      return this.chapterPrefetchTask;
    }
    const targetUrl: string = this.chapterPrefetchTargetUrl;
    const controller: webview.WebviewController | undefined = this.activeController;
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const revision: number = this.chapterPrefetchRevision;
    if (targetUrl.length === 0 || controller === undefined ||
      !this.isChapterPrefetchContextCurrent(
        revision,
        controller,
        session.sessionGeneration,
        session.bookId,
        session.activeChapterId,
        targetUrl
      )) {
      return Promise.resolve();
    }
    const task: Promise<void> = this.runChapterPrefetch(
      revision,
      controller,
      session.sessionGeneration,
      session.bookId,
      session.activeChapterId,
      targetUrl
    ).finally((): void => {
      if (revision === this.chapterPrefetchRevision) {
        this.chapterPrefetchTask = undefined;
        this.chapterPrefetchTargetUrl = '';
      }
    });
    this.chapterPrefetchTask = task;
    return task;
  }

  private async runChapterPrefetch(
    revision: number,
    controller: webview.WebviewController,
    sessionGeneration: number,
    bookId: string,
    activeChapterId: string,
    targetUrl: string
  ): Promise<void> {
    try {
      const cached: NovelChapterArtifactCacheReadResult | undefined =
        await this.chapterArtifactCacheRepository.readChapter(targetUrl);
      if (cached !== undefined) {
        return;
      }
      if (!this.isChapterPrefetchContextCurrent(
        revision,
        controller,
        sessionGeneration,
        bookId,
        activeChapterId,
        targetUrl
      )) {
        return;
      }
      const chapter: NovelChapterExtract = await this.extractionService.fetchChapter(
        controller,
        targetUrl,
        this.snapshot.contentKind
      );
      if ((chapter.paragraphs.length === 0 && chapter.images.length === 0) ||
        !this.isChapterPrefetchContextCurrent(
          revision,
          controller,
          sessionGeneration,
          bookId,
          activeChapterId,
          targetUrl
        )) {
        return;
      }
      const canonicalUrl: string = this.resolveCanonicalChapterUrl(targetUrl);
      const finalUrl: string = chapter.pageUrl.length > 0 ? chapter.pageUrl : canonicalUrl;
      const chapterId: string = this.buildChapterIdentity(bookId, canonicalUrl);
      if (chapterId.length === 0 || this.buildChapterIdentity(bookId, finalUrl) !== chapterId) {
        return;
      }
      const detailUrl: string = this.snapshot.bookshelfDetailUrl.trim().length > 0
        ? this.snapshot.bookshelfDetailUrl
        : (chapter.catalogUrl.trim().length > 0
          ? chapter.catalogUrl
          : this.sourceIdentityService.parentDirectory(canonicalUrl));
      const artifact: NovelChapterArtifactCacheRecord = {
        bookId: bookId,
        chapterId: chapterId,
        bookDetailUrl: detailUrl,
        bookTitle: this.snapshot.bookTitle.trim().length > 0 ? this.snapshot.bookTitle : chapter.bookTitle,
        canonicalUrl: canonicalUrl,
        requestedUrl: canonicalUrl,
        finalUrl: finalUrl,
        title: this.resolveCommittedChapterTitle(
          this.readingSessionState.snapshot(),
          chapterId,
          chapter.title
        ),
        contentKind: this.comicChapterAcquisitionEngine.resolveContentKind(chapter.images),
        paragraphs: chapter.paragraphs.slice(),
        images: chapter.images.slice(),
        prevUrl: chapter.prevUrl,
        nextUrl: chapter.nextUrl,
        catalogUrl: this.resolveChapterArtifactCatalogUrl(
          bookId,
          chapter.catalogUrl.length > 0 ? chapter.catalogUrl : this.snapshot.catalogUrl,
          detailUrl,
          canonicalUrl
        ),
        cachedAt: Date.now()
      };
      if (!this.isChapterPrefetchContextCurrent(
        revision,
        controller,
        sessionGeneration,
        bookId,
        activeChapterId,
        targetUrl
      )) {
        return;
      }
      await this.chapterArtifactCacheRepository.write(artifact);
      hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
        'chapter prefetch ready target=%{public}s', canonicalUrl);
    } catch (_error) {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter prefetch failed');
    }
  }

  private isChapterPrefetchContextCurrent(
    revision: number,
    controller: webview.WebviewController,
    sessionGeneration: number,
    bookId: string,
    activeChapterId: string,
    targetUrl: string
  ): boolean {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    return revision === this.chapterPrefetchRevision && this.activeController === controller &&
      this.runtimeAvailable && this.canUsePersistentChapterCache(this.snapshot.scope) &&
      session.phase === 'reader' && session.sessionGeneration === sessionGeneration &&
      session.bookId === bookId && session.activeChapterId === activeChapterId &&
      session.chapterTransition.status === 'idle' &&
      this.normalizeUrl(this.chapterPrefetchTargetUrl) === this.normalizeUrl(targetUrl) &&
      this.normalizeUrl(this.resolveSessionNextChapterUrl()) === this.normalizeUrl(targetUrl);
  }

  private cancelChapterPrefetch(): void {
    this.chapterPrefetchRevision += 1;
    if (this.chapterPrefetchTimer >= 0) {
      clearTimeout(this.chapterPrefetchTimer);
      this.chapterPrefetchTimer = -1;
    }
    this.chapterPrefetchTargetUrl = '';
    this.chapterPrefetchTask = undefined;
  }

  private async refreshCachedChapter(
    controller: webview.WebviewController,
    artifact: NovelChapterArtifactCacheRecord,
    intent: NovelSessionChapterIntent,
    expectedSessionGeneration: number
  ): Promise<void> {
    try {
      const chapter: NovelChapterExtract = await this.extractionService.fetchChapter(
        controller,
        artifact.canonicalUrl,
        artifact.contentKind
      );
      const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
      if (this.activeController !== controller || !this.runtimeAvailable ||
        session.sessionGeneration !== expectedSessionGeneration || session.bookId !== artifact.bookId ||
        session.activeChapterId !== artifact.chapterId || session.chapterTransition.status !== 'idle' ||
        (chapter.paragraphs.length === 0 && chapter.images.length === 0)) {
        return;
      }
      const finalPageUrl: string = chapter.pageUrl.length > 0 ? chapter.pageUrl : artifact.canonicalUrl;
      const finalCanonicalUrl: string = this.resolveCanonicalChapterUrl(finalPageUrl);
      if (this.buildChapterIdentity(artifact.bookId, finalCanonicalUrl) !== artifact.chapterId) {
        hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache refresh identity rejected');
        return;
      }
      const refreshed: NovelChapterArtifactCacheRecord = {
        bookId: artifact.bookId,
        chapterId: artifact.chapterId,
        bookDetailUrl: artifact.bookDetailUrl,
        bookTitle: this.snapshot.bookTitle.trim().length > 0
          ? this.snapshot.bookTitle
          : (artifact.bookTitle.trim().length > 0 ? artifact.bookTitle : chapter.bookTitle),
        canonicalUrl: artifact.canonicalUrl,
        requestedUrl: artifact.canonicalUrl,
        finalUrl: finalPageUrl,
        title: chapter.title,
        contentKind: this.comicChapterAcquisitionEngine.resolveContentKind(chapter.images),
        paragraphs: chapter.paragraphs.slice(),
        images: chapter.images.slice(),
        prevUrl: chapter.prevUrl,
        nextUrl: chapter.nextUrl,
        catalogUrl: this.resolveChapterArtifactCatalogUrl(
          artifact.bookId,
          chapter.catalogUrl.length > 0 ? chapter.catalogUrl : artifact.catalogUrl,
          artifact.bookDetailUrl,
          artifact.canonicalUrl
        ),
        cachedAt: Date.now()
      };
      if (this.areChapterArtifactsEquivalent(artifact, refreshed)) {
        const freshnessOnly: NovelChapterArtifactCacheRecord = {
          bookId: artifact.bookId,
          chapterId: artifact.chapterId,
          bookDetailUrl: artifact.bookDetailUrl,
          bookTitle: artifact.bookTitle,
          canonicalUrl: artifact.canonicalUrl,
          requestedUrl: artifact.requestedUrl,
          finalUrl: artifact.finalUrl,
          title: artifact.title,
          contentKind: artifact.contentKind,
          paragraphs: artifact.paragraphs.slice(),
          images: artifact.images.slice(),
          prevUrl: artifact.prevUrl,
          nextUrl: artifact.nextUrl,
          catalogUrl: artifact.catalogUrl,
          cachedAt: Date.now()
        };
        this.writeChapterArtifact(freshnessOnly);
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'chapter cache refresh unchanged intent=%{public}s', intent);
        return;
      }
      const refreshRequest: NovelSessionChapterRequest =
        this.createChapterRequest(artifact.canonicalUrl, 'select');
      if (!this.readingSessionState.beginChapterTransition(refreshRequest)) {
        return;
      }
      if (this.commitAcquiredChapter(refreshRequest, chapter, finalPageUrl)) {
        hilog.info(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG,
          'chapter cache refresh committed intent=%{public}s', intent);
      }
    } catch (_error) {
      hilog.warn(NOVEL_LOG_DOMAIN, NOVEL_LOG_TAG, 'chapter cache background refresh failed');
    }
  }

  private areChapterArtifactsEquivalent(
    left: NovelChapterArtifactCacheRecord,
    right: NovelChapterArtifactCacheRecord
  ): boolean {
    if (left.title !== right.title || left.contentKind !== right.contentKind ||
      this.normalizeUrl(left.finalUrl) !== this.normalizeUrl(right.finalUrl) ||
      this.normalizeUrl(left.prevUrl) !== this.normalizeUrl(right.prevUrl) ||
      this.normalizeUrl(left.nextUrl) !== this.normalizeUrl(right.nextUrl) ||
      this.normalizeUrl(left.catalogUrl) !== this.normalizeUrl(right.catalogUrl) ||
      left.paragraphs.length !== right.paragraphs.length || left.images.length !== right.images.length) {
      return false;
    }
    for (let index: number = 0; index < left.paragraphs.length; index += 1) {
      if (left.paragraphs[index] !== right.paragraphs[index]) {
        return false;
      }
    }
    for (let index: number = 0; index < left.images.length; index += 1) {
      if (left.images[index] !== right.images[index]) {
        return false;
      }
    }
    return true;
  }

  private canUsePersistentChapterCache(scope: NovelReaderSessionScope): boolean {
    return scope.privacyMode === 'regular' && scope.dataScope === 'profile_persistent';
  }

  private resolveChapterArtifactCatalogUrl(
    bookId: string,
    catalogUrl: string,
    detailUrl: string,
    chapterUrl: string
  ): string {
    if (catalogUrl.trim().length > 0 &&
      this.buildBookIdentity(catalogUrl, detailUrl) === bookId) {
      return catalogUrl;
    }
    if (detailUrl.trim().length > 0 &&
      this.buildBookIdentity(detailUrl, detailUrl) === bookId) {
      return '';
    }
    if (this.buildBookIdentity('', chapterUrl) === bookId) {
      return '';
    }
    return catalogUrl;
  }

  private createChapterRequest(url: string, intent: NovelSessionChapterIntent): NovelSessionChapterRequest {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const canonicalUrl: string = this.resolveCanonicalChapterUrl(url);
    const tailId: string = session.chapterTrail.length > 0 ?
      session.chapterTrail[session.chapterTrail.length - 1].id : '';
    this.chapterRequestSequence = this.chapterRequestSequence + 1;
    return {
      requestId: `${this.sessionGeneration}:chapter:${this.chapterRequestSequence}`,
      sessionGeneration: this.sessionGeneration,
      tabId: this.snapshot.scope.tabId,
      privacyMode: this.snapshot.scope.privacyMode,
      chapterId: this.buildChapterIdentity(session.bookId, canonicalUrl),
      requestedUrl: url,
      intent: intent,
      startingTrailTailId: tailId
    };
  }

  private publishReadingSessionState(bookTitle: string = this.snapshot.bookTitle): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    this.emit({
      type: 'reader_state',
      session: session,
      bookTitle: bookTitle
    });
  }

  private resolveChapterFailureMessage(failureCode: string): string {
    if (failureCode === 'retryable') {
      return '这一章加载失败，请重试。';
    }
    if (failureCode === 'content_rejected') {
      return '这一章正文不完整，请重试。';
    }
    if (failureCode === 'identity_mismatch') {
      return '章节身份校验失败，请返回原网页后重试。';
    }
    if (failureCode === 'unsupported_source') {
      return '当前来源暂不支持继续读取。';
    }
    if (failureCode === 'authentication_required') {
      return '请先在来源网站登录，登录后再开始阅读。';
    }
    return '';
  }

  private resolveChapterAcquisitionFailureCode(error: Object): NovelSessionFailureCode {
    if (error instanceof Error && error.message === COMIC_CHAPTER_AUTHENTICATION_REQUIRED_ERROR) {
      return 'authentication_required';
    }
    return 'retryable';
  }

  private beginOpen(): number {
    this.clearPendingRenderedChapter();
    this.openGeneration = this.openGeneration + 1;
    return this.openGeneration;
  }

  private emit(event: NovelReaderSnapshotEvent): void {
    const base: NovelReaderSnapshot = this.snapshot;
    const next: NovelReaderSnapshot = this.cloneSnapshot(base);
    if (event.type === 'reentry_cleared') {
      next.reentryAvailable = false;
      next.reentryPageUrl = '';
    } else if (event.type === 'opening_started') {
      next.visible = true;
      next.phase = 'detecting';
      next.openingTransition = { status: 'loading', requestId: event.requestId, failureCode: '' };
      next.openingFailure = '';
      next.pageUrl = event.pageUrl;
      next.scope = this.copyScope(event.scope);
    } else if (event.type === 'opening_failed') {
      next.visible = false;
      next.phase = 'inactive';
      next.openingTransition = { status: 'failed', requestId: event.requestId, failureCode: event.failureCode };
      next.openingFailure = event.failureCode;
    } else if (event.type === 'catalog_loading') {
      next.catalogUrl = event.catalogUrl;
      next.catalogLoadingMore = true;
      next.catalogLoadingRangeStart = event.rangeStartOrdinal;
      next.catalogLoadingRangeEnd = event.rangeEndOrdinal;
      next.catalogTransition = this.copyOperation(event.session.catalogTransition);
    } else if (event.type === 'catalog_ready') {
      next.catalogUrl = event.catalogUrl;
      next.catalog = event.session.catalog.map((entry: NovelSessionCatalogChapter): NovelReaderCatalogEntry => ({
        id: entry.id,
        ordinal: entry.ordinal,
        title: entry.title,
        url: entry.canonicalUrl
      }));
      next.catalogLoadingMore = false;
      next.catalogLoadingRangeStart = -1;
      next.catalogLoadingRangeEnd = -1;
      next.catalogHasMore = event.hasMore;
      next.catalogTotalHint = event.totalHint;
      next.catalogRangeExtentHint = Math.max(this.catalogRangeExtentHint, event.totalHint);
      next.catalogSupportsRandomAccess = event.supportsRandomAccess;
      next.catalogTransition = this.copyOperation(event.session.catalogTransition);
      next.bookTitle = event.bookTitle;
      next.bookAuthor = event.bookAuthor;
      next.bookCoverUrl = event.bookCoverUrl;
      next.resumeHint = this.resolveResumeHint(event.session);
    } else if (event.type === 'catalog_failed') {
      next.catalogLoadingMore = false;
      next.catalogLoadingRangeStart = -1;
      next.catalogLoadingRangeEnd = -1;
      next.catalogTransition = this.copyOperation(event.session.catalogTransition);
    } else if (event.type === 'book_overview_ready') {
      next.visible = true;
      next.phase = 'book';
      next.bookIdentity = event.session.bookId;
      next.openingTransition = { status: 'idle', requestId: '', failureCode: '' };
      next.openingFailure = '';
      next.bookTitle = event.overview.title;
      next.contentKind = event.overview.contentKind;
      next.bookAuthor = event.overview.author;
      next.bookCoverUrl = event.overview.cover;
      next.bookCategory = event.overview.category;
      next.bookLatest = event.overview.latest;
      next.bookSynopsis = event.overview.synopsis;
      next.sourceHost = event.overview.host;
      next.bookshelfDetailUrl = event.detailUrl;
      next.catalog = event.session.catalog.map((entry: NovelSessionCatalogChapter): NovelReaderCatalogEntry => ({
          id: entry.id,
          ordinal: entry.ordinal,
          title: entry.title,
          url: entry.canonicalUrl
      }));
      next.catalogUrl = event.catalogUrl;
      next.catalogLoadingMore = false;
      next.catalogLoadingRangeStart = -1;
      next.catalogLoadingRangeEnd = -1;
      next.catalogHasMore = this.resolveCatalogHasMore(event.session);
      next.catalogTotalHint = this.catalogTotalHint;
      next.catalogRangeExtentHint = this.catalogRangeExtentHint;
      next.catalogSupportsRandomAccess = this.catalogPageCursor !== undefined;
      next.bookshelfAvailable = event.bookshelfAvailable;
      next.bookshelfActionBusy = event.bookshelfAvailable;
      next.resumeHint = this.resolveResumeHint(event.session);
    } else if (event.type === 'reader_state') {
      const activeChapter: NovelSessionCommittedChapter | undefined =
        event.session.chapterTrail.find((chapter: NovelSessionCommittedChapter): boolean =>
          chapter.id === event.session.activeChapterId);
      next.visible = event.session.phase !== 'inactive' && event.session.phase !== 'suspended';
      next.bookIdentity = event.session.bookId;
      if (event.session.phase === 'suspended') {
        next.phase = 'suspended';
      } else if (event.session.phase === 'reader' && activeChapter !== undefined) {
        next.phase = 'reader';
      } else if (event.session.phase === 'book') {
        next.phase = 'book';
      } else if (event.session.phase === 'opening') {
        next.phase = 'detecting';
      } else {
        next.phase = 'inactive';
      }
      next.chapterTransition = this.copyOperation(event.session.chapterTransition);
      next.catalogTransition = this.copyOperation(event.session.catalogTransition);
      if (event.session.catalogTransition.status !== 'loading') {
        next.catalogLoadingMore = false;
        next.catalogLoadingRangeStart = -1;
        next.catalogLoadingRangeEnd = -1;
      }
      next.bookTitle = event.bookTitle;
      if (activeChapter !== undefined) {
        next.pageUrl = activeChapter.canonicalUrl;
        next.catalogUrl = activeChapter.catalogUrl.length > 0 ? activeChapter.catalogUrl : base.catalogUrl;
        next.contentKind = activeChapter.contentKind;
      } else {
        next.contentKind = base.contentKind;
      }
      next.position = {
        chapterId: event.session.checkpoint.chapterId,
        characterOffset: event.session.checkpoint.characterOffset
      };
      next.activeChapterId = event.session.activeChapterId;
      next.chapterTrail = this.copyChapterTrail(event.session.chapterTrail);
      next.resumeHint = next.phase === 'book' ? this.resolveResumeHint(event.session) : '';
    } else if (event.type === 'preferences_changed') {
      next.preferences = this.copyPreferences(event.preferences);
    } else if (event.type === 'bookshelf_state') {
      next.bookInBookshelf = event.inBookshelf !== undefined ? event.inBookshelf : base.bookInBookshelf;
      next.bookshelfActionBusy = event.actionBusy !== undefined ? event.actionBusy : base.bookshelfActionBusy;
    } else if (event.type === 'bookshelf_context_ready') {
      next.bookshelfDetailUrl = event.detailUrl;
      next.bookshelfAvailable = event.available;
      next.bookshelfActionBusy = event.available;
    } else if (event.type === 'top_prompt_changed') {
      next.topPrompt = this.copyTopPrompt(event.prompt);
    } else if (event.type === 'palette_loading') {
      next.bookPaletteKey = '';
      next.bookPaletteLoading = true;
    } else if (event.type === 'palette_ready') {
      if (event.palette !== undefined) {
        next.bookPalette = cloneNovelBookCoverPalette(event.palette);
      }
      next.bookPaletteKey = event.key === undefined ? base.bookPaletteKey : event.key;
      next.bookPaletteLoading = event.loading;
    } else if (event.type === 'resume_hint_changed') {
      next.resumeHint = event.resumeHint;
    }
    next.canNavigatePrevious = next.phase === 'reader' &&
      this.resolveSessionPreviousChapterUrl().length > 0;
    next.canNavigateNext = next.phase === 'reader' &&
      this.resolveSessionNextChapterUrl().length > 0;
    if (!next.visible || next.phase !== 'reader') {
      next.overlayBackState.panelVisible = false;
    }
    this.snapshot = next;
    this.notify();
  }

  private notify(): void {
    if (this.sessionListener !== undefined) {
      this.sessionListener.onSnapshotChanged(this.cloneSnapshot(this.snapshot));
    }
    if (this.snapshot.visible && this.snapshot.phase === 'reader') {
      this.emitEffect({
        type: 'apply_window_brightness',
        brightnessMode: this.snapshot.preferences.brightnessMode,
        brightnessPercent: this.snapshot.preferences.brightnessPercent
      });
      return;
    }
    this.emitEffect({ type: 'restore_window_brightness' });
  }

  private emitEffect(effect: NovelReaderEffect): boolean {
    const listener: NovelReaderSessionListener | undefined = this.sessionListener;
    if (listener === undefined || listener.onEffect === undefined) {
      return false;
    }
    return listener.onEffect(effect);
  }

  private recordProgress(chapterId: string, characterOffset: number): void {
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    for (let index: number = 0; index < session.chapterTrail.length; index++) {
      const chapter: NovelSessionCommittedChapter = session.chapterTrail[index];
      if (chapter.id === chapterId) {
        const updatedAt: number = Math.max(
          Date.now(),
          this.latestPersistedCheckpointUpdatedAt + 1,
          session.checkpoint.updatedAt + 1
        );
        if (this.readingSessionState.recordCheckpoint(chapter.id, characterOffset, updatedAt)) {
          this.latestPersistedCheckpointUpdatedAt = updatedAt;
          this.publishReadingSessionState();
          this.persistSessionCheckpoint();
        }
        return;
      }
    }
  }

  private recordPanelVisibility(visible: boolean): void {
    const panelVisible: boolean = visible && this.snapshot.visible && this.snapshot.phase === 'reader';
    if (this.snapshot.overlayBackState.panelVisible === panelVisible) {
      return;
    }
    const next: NovelReaderSnapshot = this.cloneSnapshot(this.snapshot);
    next.overlayBackState.panelVisible = panelVisible;
    this.snapshot = next;
    this.notify();
  }

  private requestPanelDismissal(): void {
    if (!this.snapshot.overlayBackState.panelVisible) {
      return;
    }
    const next: NovelReaderSnapshot = this.cloneSnapshot(this.snapshot);
    next.overlayBackState.dismissPanelRequestVersion =
      next.overlayBackState.dismissPanelRequestVersion + 1;
    this.snapshot = next;
    this.notify();
  }

  private resetSnapshot(scope: NovelReaderSessionScope): void {
    const preferences: NovelReaderPreferences = this.copyPreferences(this.snapshot.preferences);
    this.snapshot = createDefaultNovelReaderSnapshot();
    this.snapshot.preferences = preferences;
    this.snapshot.scope = this.copyScope(scope);
    this.pendingPersistedCheckpoint = undefined;
    this.checkpointLoadBookId = '';
    this.checkpointLoadBookDetailUrl = '';
    this.checkpointFallbackBookId = '';
    this.checkpointLoadTask = undefined;
    this.latestPersistedCheckpointUpdatedAt = 0;
    this.catalogPageCursor = undefined;
    this.catalogTotalHint = 0;
    this.catalogRangeExtentHint = 0;
    this.catalogRefreshRecommended = false;
    this.catalogDefaultRangeHydrationPending = false;
    this.cancelChapterPrefetch();
    this.clearPendingChapterArtifactRefresh();
  }

  private clearPendingChapterArtifactRefresh(): void {
    this.pendingChapterArtifactRefresh = undefined;
    this.pendingChapterArtifactRefreshSessionGeneration = 0;
  }

  private ensurePersistedCheckpointLoaded(
    bookDetailUrl: string = this.snapshot.bookshelfDetailUrl
  ): Promise<NovelReadingCheckpointRecord | undefined> {
    const repository = this.checkpointRepository;
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    if (repository === undefined || session.privacyMode !== 'regular' || session.bookId.length === 0) {
      return Promise.resolve(undefined);
    }
    const normalizedBookDetailUrl: string = bookDetailUrl.trim();
    if (this.checkpointLoadBookId === session.bookId &&
      this.checkpointLoadBookDetailUrl === normalizedBookDetailUrl && this.checkpointLoadTask !== undefined) {
      return this.checkpointLoadTask;
    }
    const bookId: string = session.bookId;
    const generation: number = session.sessionGeneration;
    this.checkpointLoadBookId = bookId;
    this.checkpointLoadBookDetailUrl = normalizedBookDetailUrl;
    this.checkpointLoadTask = this.loadCheckpointWithProvenDetailAlias(
      repository,
      bookId,
      this.checkpointFallbackBookId,
      normalizedBookDetailUrl
    )
      .then((checkpoint: NovelReadingCheckpointRecord | undefined): NovelReadingCheckpointRecord | undefined => {
        const current: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
        if (current.sessionGeneration === generation && current.bookId === bookId &&
          current.privacyMode === 'regular') {
          this.pendingPersistedCheckpoint = checkpoint;
          this.latestPersistedCheckpointUpdatedAt = Math.max(
            this.latestPersistedCheckpointUpdatedAt,
            checkpoint?.updatedAt ?? 0
          );
          this.applyLoadedCheckpointIfMatching();
          this.emit({
            type: 'resume_hint_changed',
            resumeHint: this.resolveResumeHint(current)
          });
        }
        return checkpoint;
      })
      .catch((_error: Error): NovelReadingCheckpointRecord | undefined => {
        return undefined;
      });
    return this.checkpointLoadTask;
  }

  private async loadCheckpointWithProvenDetailAlias(
    repository: NovelReadingCheckpointPort,
    bookId: string,
    fallbackBookId: string,
    bookDetailUrl: string
  ): Promise<NovelReadingCheckpointRecord | undefined> {
    const exact: NovelReadingCheckpointRecord | undefined = await repository.load(bookId);
    let selected: NovelReadingCheckpointRecord | undefined = exact;
    if (fallbackBookId.length > 0 && fallbackBookId !== bookId) {
      const legacy: NovelReadingCheckpointRecord | undefined = await repository.load(fallbackBookId);
      if (legacy !== undefined && legacy.bookId === fallbackBookId &&
        legacy.chapterId === this.buildChapterIdentity(fallbackBookId, legacy.canonicalUrl) &&
        this.normalizedAuthority(legacy.canonicalUrl) === this.normalizedAuthority(this.snapshot.pageUrl) &&
        (selected === undefined || this.comparePersistedCheckpoints(legacy, selected) > 0)) {
        selected = legacy;
      }
    }
    if (bookDetailUrl.length > 0) {
      const portable: NovelReadingCheckpointRecord | undefined =
        await repository.loadByBookDetailUrl(bookDetailUrl);
      if (portable !== undefined &&
        this.normalizedAuthority(portable.canonicalUrl) === this.normalizedAuthority(this.snapshot.pageUrl) &&
        (selected === undefined || this.comparePersistedCheckpoints(portable, selected) > 0)) {
        selected = portable;
      }
    }
    if (selected === undefined) {
      return undefined;
    }
    const resolvedDetailUrl: string = bookDetailUrl.length > 0 ? bookDetailUrl : selected.bookDetailUrl;
    const expectedChapterId: string = this.buildChapterIdentity(bookId, selected.canonicalUrl);
    if (selected.bookId === bookId && selected.chapterId === expectedChapterId &&
      selected.bookDetailUrl === resolvedDetailUrl) {
      return selected;
    }
    const migrated: NovelReadingCheckpointRecord = {
      bookId: bookId,
      bookDetailUrl: resolvedDetailUrl,
      chapterId: expectedChapterId,
      canonicalUrl: selected.canonicalUrl,
      chapterTitle: selected.chapterTitle,
      characterOffset: selected.characterOffset,
      updatedAt: selected.updatedAt
    };
    await repository.save(migrated).catch((_error: Error): void => {});
    return migrated;
  }

  private comparePersistedCheckpoints(
    left: NovelReadingCheckpointRecord,
    right: NovelReadingCheckpointRecord
  ): number {
    if (left.updatedAt !== right.updatedAt) {
      return left.updatedAt - right.updatedAt;
    }
    return JSON.stringify(left).localeCompare(JSON.stringify(right));
  }

  private applyLoadedCheckpointIfMatching(): void {
    const pending: NovelReadingCheckpointRecord | undefined = this.pendingPersistedCheckpoint;
    if (pending === undefined) {
      return;
    }
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const chapter: NovelSessionCommittedChapter | undefined = session.chapterTrail.find(
      (candidate: NovelSessionCommittedChapter): boolean => candidate.id === session.activeChapterId
    );
    if (session.privacyMode !== 'regular' || chapter === undefined || session.bookId !== pending.bookId ||
      chapter.id !== pending.chapterId ||
      this.normalizeUrl(chapter.canonicalUrl) !== this.normalizeUrl(pending.canonicalUrl)) {
      return;
    }
    if (this.readingSessionState.recordCheckpoint(chapter.id, pending.characterOffset, pending.updatedAt)) {
      this.pendingPersistedCheckpoint = undefined;
      this.publishReadingSessionState();
    }
  }

  private persistSessionCheckpoint(): void {
    const repository = this.checkpointRepository;
    const session: NovelReadingSessionSnapshot = this.readingSessionState.snapshot();
    const checkpoint = this.readingSessionState.checkpointForPersistence();
    if (repository === undefined || checkpoint === undefined || session.bookId.length === 0) {
      return;
    }
    const record: NovelReadingCheckpointRecord = {
      bookId: session.bookId,
      bookDetailUrl: this.snapshot.bookshelfDetailUrl,
      chapterId: checkpoint.chapterId,
      canonicalUrl: checkpoint.canonicalUrl,
      chapterTitle: session.chapterTrail.find(
        (chapter: NovelSessionCommittedChapter): boolean => chapter.id === checkpoint.chapterId
      )?.title ?? '',
      characterOffset: checkpoint.characterOffset,
      updatedAt: checkpoint.updatedAt
    };
    this.checkpointWriteTask = this.checkpointWriteTask
      .catch((_error: Error): void => {
      })
      .then((): Promise<void> => repository.save(record))
      .catch((_error: Error): void => {
      });
  }

  private normalizeDetectedPageType(value: string): NovelDetectedPageType {
    if (value === 'book' || value === 'chapter') {
      return value;
    }
    return '';
  }

  private normalizePreferences(preferences: NovelReaderPreferences): NovelReaderPreferences {
    const defaults: NovelReaderPreferences = createDefaultNovelReaderPreferences();
    const fontSizeValue: number = Number.isFinite(preferences.fontSize) ? preferences.fontSize : defaults.fontSize;
    const brightnessValue: number = Number.isFinite(preferences.brightnessPercent)
      ? preferences.brightnessPercent
      : defaults.brightnessPercent;
    const speedValue: number = Number.isFinite(preferences.autoReadingSpeed)
      ? preferences.autoReadingSpeed
      : defaults.autoReadingSpeed;
    const fontSize: number = Math.max(15, Math.min(26, Math.round(fontSizeValue)));
    const brightnessPercent: number = Math.max(20, Math.min(100, Math.round(brightnessValue)));
    const autoReadingSpeed: number = Math.max(1, Math.min(5, Math.round(speedValue)));
    return {
      fontSize: fontSize,
      theme: this.normalizeTheme(preferences.theme, defaults.theme),
      lineHeight: this.normalizeLineHeight(preferences.lineHeight, defaults.lineHeight),
      pageWidth: this.normalizePageWidth(preferences.pageWidth, defaults.pageWidth),
      brightnessMode: preferences.brightnessMode === 'manual' ? 'manual' : 'system',
      brightnessPercent: brightnessPercent,
      pageMode: this.normalizePageMode(preferences.pageMode, defaults.pageMode),
      autoReadingEnabled: typeof preferences.autoReadingEnabled === 'boolean'
        ? preferences.autoReadingEnabled
        : defaults.autoReadingEnabled,
      autoReadingSpeed: autoReadingSpeed,
      volumeKeyPagingEnabled: typeof preferences.volumeKeyPagingEnabled === 'boolean'
        ? preferences.volumeKeyPagingEnabled
        : defaults.volumeKeyPagingEnabled,
      systemStatusBarVisible: typeof preferences.systemStatusBarVisible === 'boolean'
        ? preferences.systemStatusBarVisible
        : defaults.systemStatusBarVisible,
      chapterNameVisible: typeof preferences.chapterNameVisible === 'boolean'
        ? preferences.chapterNameVisible
        : defaults.chapterNameVisible,
      pageNumberVisible: typeof preferences.pageNumberVisible === 'boolean'
        ? preferences.pageNumberVisible
        : defaults.pageNumberVisible
    };
  }

  private updatePreferences(preferences: NovelReaderPreferences): void {
    const normalized: NovelReaderPreferences = this.normalizePreferences(preferences);
    this.preferencesMutationRevision += 1;
    this.emit({ type: 'preferences_changed', preferences: normalized });
    this.persistPreferences(normalized);
  }

  private loadPreferences(): Promise<void> {
    const repository = this.preferencesRepository;
    if (repository === undefined) {
      return Promise.resolve();
    }
    const loadRevision: number = this.preferencesMutationRevision;
    return repository.load(createDefaultNovelReaderPreferences())
      .then((preferences: NovelReaderPreferences): void => {
        if (loadRevision !== this.preferencesMutationRevision) {
          return;
        }
        this.emit({ type: 'preferences_changed', preferences: this.normalizePreferences(preferences) });
      })
      .catch((_error: Error): void => {
      });
  }

  private persistPreferences(preferences: NovelReaderPreferences): void {
    const repository = this.preferencesRepository;
    if (repository === undefined) {
      return;
    }
    const value: NovelReaderPreferences = this.copyPreferences(preferences);
    this.preferencesWriteTask = this.preferencesWriteTask
      .catch((_error: Error): void => {
      })
      .then((): Promise<void> => repository.save(value))
      .catch((_error: Error): void => {
      });
  }

  private normalizeTheme(
    value: ReaderModeTheme,
    fallback: ReaderModeTheme
  ): ReaderModeTheme {
    if (value === 'light' || value === 'paper' || value === 'sepia' || value === 'sage' ||
      value === 'charcoal' || value === 'dark' || value === 'system') {
      return value;
    }
    return fallback;
  }

  private normalizeLineHeight(
    value: ReaderModeLineHeight,
    fallback: ReaderModeLineHeight
  ): ReaderModeLineHeight {
    if (value === 'compact' || value === 'comfortable' || value === 'loose') {
      return value;
    }
    return fallback;
  }

  private normalizePageWidth(
    value: ReaderModePageWidth,
    fallback: ReaderModePageWidth
  ): ReaderModePageWidth {
    if (value === 'narrow' || value === 'standard' || value === 'wide') {
      return value;
    }
    return fallback;
  }

  private normalizePageMode(
    value: NovelReaderPageMode,
    fallback: NovelReaderPageMode
  ): NovelReaderPageMode {
    if (value === 'horizontal' || value === 'horizontalFast' || value === 'vertical') {
      return value;
    }
    return fallback;
  }

  private copyPreferences(preferences: NovelReaderPreferences): NovelReaderPreferences {
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent,
      pageMode: preferences.pageMode,
      autoReadingEnabled: preferences.autoReadingEnabled,
      autoReadingSpeed: preferences.autoReadingSpeed,
      volumeKeyPagingEnabled: preferences.volumeKeyPagingEnabled,
      systemStatusBarVisible: preferences.systemStatusBarVisible,
      chapterNameVisible: preferences.chapterNameVisible,
      pageNumberVisible: preferences.pageNumberVisible
    };
  }

  private copyScope(scope: NovelReaderSessionScope): NovelReaderSessionScope {
    return {
      tabId: scope.tabId,
      privacyMode: scope.privacyMode,
      dataScope: scope.dataScope
    };
  }

  private cloneCatalogPageCursor(
    cursor: NovelCatalogPageCursor | undefined
  ): NovelCatalogPageCursor | undefined {
    if (cursor === undefined) {
      return undefined;
    }
    return {
      ruleId: cursor.ruleId,
      bookToken: cursor.bookToken,
      initialPage: cursor.initialPage,
      nextPage: cursor.nextPage,
      pageSize: cursor.pageSize,
      totalHint: cursor.totalHint,
      totalPages: cursor.totalPages
    };
  }

  private createHiddenTopPrompt(): NovelTopPromptState {
    return {
      visible: false,
      key: '',
      kind: '',
      bookTitle: '',
      contentKind: 'novel'
    };
  }

  private copyTopPrompt(prompt: NovelTopPromptState): NovelTopPromptState {
    return {
      visible: prompt.visible,
      key: prompt.key,
      kind: prompt.kind,
      bookTitle: prompt.bookTitle,
      contentKind: prompt.contentKind
    };
  }

  private copyChapterTrail(chapterTrail: NovelSessionCommittedChapter[]): NovelSessionCommittedChapter[] {
    return chapterTrail.map((chapter: NovelSessionCommittedChapter): NovelSessionCommittedChapter => ({
      id: chapter.id,
      bookId: chapter.bookId,
      canonicalUrl: chapter.canonicalUrl,
      requestedUrl: chapter.requestedUrl,
      finalUrl: chapter.finalUrl,
      title: chapter.title,
      contentKind: chapter.contentKind,
      paragraphs: chapter.paragraphs.slice(),
      images: chapter.images.slice(),
      prevUrl: chapter.prevUrl,
      nextUrl: chapter.nextUrl,
      catalogUrl: chapter.catalogUrl,
      revision: chapter.revision
    }));
  }

  private async refreshBookshelfMembership(generation: number, detailUrl: string): Promise<void> {
    const requestGeneration: number = this.bookshelfRequestGeneration + 1;
    this.bookshelfRequestGeneration = requestGeneration;
    if (!this.snapshot.bookshelfAvailable) {
      this.emit({ type: 'bookshelf_state', inBookshelf: false, actionBusy: false });
      return;
    }
    try {
      const isInBookshelf: boolean = await this.libraryRepository.isInBookshelf(detailUrl);
      if (!this.isCurrentBookshelfRequest(generation, detailUrl) ||
        requestGeneration !== this.bookshelfRequestGeneration) {
        return;
      }
      this.emit({ type: 'bookshelf_state', inBookshelf: isInBookshelf, actionBusy: false });
      if (isInBookshelf) {
        this.refreshPersistedBookMetadata();
      }
    } catch (_error) {
      if (this.isCurrentBookshelfRequest(generation, detailUrl) &&
        requestGeneration === this.bookshelfRequestGeneration) {
        this.emit({ type: 'bookshelf_state', inBookshelf: false, actionBusy: false });
      }
    }
  }

  private initializeReaderBookshelfContext(catalogUrl: string, chapterUrl: string): void {
    if (this.snapshot.phase !== 'reader' || this.snapshot.bookshelfDetailUrl.trim().length > 0) {
      return;
    }
    const available: boolean = this.snapshot.scope.privacyMode === 'regular' &&
      this.snapshot.scope.dataScope === 'profile_persistent';
    const detailUrl: string = (catalogUrl.trim().length > 0 ? catalogUrl : this.parentDirOf(chapterUrl)).trim();
    const normalized: string = detailUrl.toLowerCase();
    if (!available || (!normalized.startsWith('https://') && !normalized.startsWith('http://'))) {
      return;
    }
    this.emit({ type: 'bookshelf_context_ready', detailUrl: detailUrl, available: true });
    void this.refreshBookshelfMembership(this.openGeneration, detailUrl);
  }

  private async toggleBookshelf(): Promise<void> {
    if ((this.snapshot.phase !== 'book' && this.snapshot.phase !== 'reader') ||
      !this.snapshot.bookshelfAvailable || this.snapshot.bookshelfActionBusy ||
      this.snapshot.bookshelfDetailUrl.trim().length === 0) {
      return;
    }
    const generation: number = this.openGeneration;
    const detailUrl: string = this.snapshot.bookshelfDetailUrl;
    const wasInBookshelf: boolean = this.snapshot.bookInBookshelf;
    const input: NovelBookshelfBookInput = this.buildCurrentBookshelfInput();
    this.emit({ type: 'bookshelf_state', actionBusy: true });
    try {
      if (wasInBookshelf) {
        await this.libraryRepository.removeFromBookshelf(detailUrl);
      } else {
        await this.libraryRepository.addToBookshelf(input);
        void this.bookCoverImageService.warm(input.coverUrl, input.detailUrl);
      }
      if (!this.isCurrentBookshelfRequest(generation, detailUrl)) {
        return;
      }
      this.emit({
        type: 'bookshelf_state',
        inBookshelf: !wasInBookshelf,
        actionBusy: false
      });
      this.emit({ type: 'top_prompt_changed', prompt: this.createHiddenTopPrompt() });
      this.emitEffect({ type: 'toast', message: wasInBookshelf ? '已移出书架。' : '已加入书架。' });
      if (!wasInBookshelf) {
        this.refreshPersistedBookMetadata();
      }
    } catch (_error) {
      if (this.isCurrentBookshelfRequest(generation, detailUrl)) {
        this.emit({ type: 'bookshelf_state', actionBusy: false });
        this.emitEffect({
          type: 'toast',
          message: wasInBookshelf ? '移出书架失败，请稍后重试。' : '加入书架失败，请稍后重试。'
        });
      }
    }
  }

  private async resolveBookPalette(themeMode: NovelBookPaletteThemeMode): Promise<void> {
    if (this.snapshot.phase !== 'book') {
      return;
    }
    const coverUrl: string = this.snapshot.bookCoverUrl.trim();
    const detailUrl: string = this.snapshot.pageUrl;
    if (coverUrl.length === 0 || detailUrl.trim().length === 0) {
      return;
    }
    const generation: number = this.openGeneration;
    const requestGeneration: number = this.bookPaletteRequestGeneration + 1;
    const paletteKey: string = buildNovelBookPaletteCacheKey(coverUrl, themeMode);
    this.bookPaletteRequestGeneration = requestGeneration;
    if (this.snapshot.bookPaletteKey === paletteKey && this.snapshot.bookPalette !== undefined) {
      return;
    }
    this.emit({ type: 'palette_loading' });
    try {
      const cached: NovelBookCoverPalette | undefined = this.snapshot.bookshelfAvailable
        ? await this.libraryRepository.readPalette(coverUrl, themeMode)
        : undefined;
      if (!this.isCurrentPaletteRequest(generation, requestGeneration, detailUrl, coverUrl)) {
        return;
      }
      if (cached !== undefined) {
        this.emit({ type: 'palette_ready', palette: cached, key: paletteKey, loading: false });
        return;
      }
      const resolved: NovelBookCoverPalette | undefined = await this.bookCoverPaletteService.resolve(
        coverUrl,
        detailUrl,
        themeMode
      );
      if (!this.isCurrentPaletteRequest(generation, requestGeneration, detailUrl, coverUrl)) {
        return;
      }
      if (resolved === undefined) {
        this.emit({ type: 'palette_ready', loading: false });
        return;
      }
      if (this.snapshot.bookshelfAvailable) {
        await this.libraryRepository.savePalette(coverUrl, themeMode, resolved).catch((_error: Error): void => {});
      }
      if (!this.isCurrentPaletteRequest(generation, requestGeneration, detailUrl, coverUrl)) {
        return;
      }
      this.emit({ type: 'palette_ready', palette: resolved, key: paletteKey, loading: false });
    } catch (_error) {
      if (this.isCurrentPaletteRequest(generation, requestGeneration, detailUrl, coverUrl)) {
        this.emit({ type: 'palette_ready', loading: false });
      }
    }
  }

  private buildCurrentBookshelfInput(): NovelBookshelfBookInput {
    return {
      detailUrl: this.snapshot.bookshelfDetailUrl,
      title: this.snapshot.bookTitle,
      author: this.snapshot.bookAuthor,
      coverUrl: this.snapshot.bookCoverUrl,
      sourceHost: this.snapshot.sourceHost,
      category: this.snapshot.bookCategory,
      latestChapter: this.snapshot.bookLatest,
      synopsis: this.snapshot.bookSynopsis
    };
  }

  private refreshPersistedBookMetadata(): void {
    if ((this.snapshot.phase !== 'book' && this.snapshot.phase !== 'reader') ||
      !this.snapshot.bookInBookshelf ||
      !this.snapshot.bookshelfAvailable || this.snapshot.bookshelfActionBusy) {
      return;
    }
    const input: NovelBookshelfBookInput = this.buildCurrentBookshelfInput();
    void this.libraryRepository.addToBookshelf(input)
      .then((): void => {
        void this.bookCoverImageService.warm(input.coverUrl, input.detailUrl);
      })
      .catch((_error: Error): void => {});
  }

  private isCurrentBookRequest(generation: number, detailUrl: string): boolean {
    return generation === this.openGeneration && this.snapshot.visible && this.snapshot.phase === 'book' &&
      this.normalizeUrl(detailUrl) === this.normalizeUrl(this.snapshot.pageUrl);
  }

  private isCurrentBookshelfRequest(generation: number, detailUrl: string): boolean {
    return generation === this.openGeneration && this.snapshot.visible &&
      (this.snapshot.phase === 'book' || this.snapshot.phase === 'reader') &&
      this.normalizeUrl(detailUrl) === this.normalizeUrl(this.snapshot.bookshelfDetailUrl);
  }

  private isCurrentPaletteRequest(
    generation: number,
    requestGeneration: number,
    detailUrl: string,
    coverUrl: string
  ): boolean {
    return requestGeneration === this.bookPaletteRequestGeneration &&
      this.isCurrentBookRequest(generation, detailUrl) && coverUrl === this.snapshot.bookCoverUrl.trim();
  }

  private buildAutoIdentity(pageUrl: string, scope: NovelReaderSessionScope): string {
    return `${scope.tabId}|${scope.privacyMode}|${scope.dataScope}|${pageUrl}`;
  }

  private isValidScope(scope: NovelReaderSessionScope): boolean {
    if (scope.tabId.trim().length === 0) {
      return false;
    }
    if (scope.privacyMode === 'private') {
      return scope.dataScope === 'session_ephemeral';
    }
    return scope.privacyMode === 'regular' && scope.dataScope === 'profile_persistent';
  }

  private isScopeEqual(left: NovelReaderSessionScope, right: NovelReaderSessionScope): boolean {
    return left.tabId === right.tabId && left.privacyMode === right.privacyMode &&
      left.dataScope === right.dataScope;
  }

  private isOpenRequestCurrent(
    generation: number,
    controller: webview.WebviewController,
    request: NovelReaderOpenRequest
  ): boolean {
    return generation === this.openGeneration && this.activeController === controller &&
      this.isLiveRequestIdentity(controller, request) &&
      this.isScopeEqual(this.snapshot.scope, request.scope);
  }

  private isLiveRequestIdentity(
    controller: webview.WebviewController,
    request: NovelReaderOpenRequest
  ): boolean {
    const validScope: boolean = this.isValidScope(request.scope);
    const activeWebTab: boolean = request.runtimeLifecyclePort.isActiveWebTab(request.scope.tabId);
    const sameController: boolean = controller === request.runtimeLifecyclePort.resolveActiveController();
    if (!validScope || !activeWebTab || !sameController) {
      return false;
    }
    const liveScope = request.runtimeLifecyclePort.resolveActiveTabDataScope();
    if (liveScope === undefined || liveScope.tabId !== request.scope.tabId ||
      liveScope.privacyMode !== request.scope.privacyMode || liveScope.dataScope !== request.scope.dataScope) {
      return false;
    }
    const requestedUrl: string = this.normalizeUrl(request.pageUrl);
    const projectedRuntimeUrl: string = this.normalizeUrl(
      request.runtimeLifecyclePort.resolvePageUrl(request.scope.tabId)
    );
    const acceptedNavigationCommitUrl: string = this.normalizeUrl(
      request.acceptedNavigationCommitUrl ?? ''
    );
    if (requestedUrl.length === 0 ||
      (requestedUrl !== projectedRuntimeUrl && requestedUrl !== acceptedNavigationCommitUrl)) {
      return false;
    }
    try {
      const controllerUrl: string = this.normalizeUrl(controller.getUrl());
      return requestedUrl === controllerUrl;
    } catch (_error) {
      return false;
    }
  }

  private isValidSourceChapterUrl(chapterUrl: string): boolean {
    const raw: string = chapterUrl.trim();
    const lower: string = raw.toLowerCase();
    if (!lower.startsWith('https://') && !lower.startsWith('http://')) {
      return false;
    }
    const target: string = this.normalizeUrl(chapterUrl);
    if (target.length === 0) {
      return false;
    }
    for (let i = 0; i < this.snapshot.catalog.length; i++) {
      if (target === this.normalizeUrl(this.snapshot.catalog[i].url)) {
        return true;
      }
    }
    const targetAuthority: string = this.normalizedAuthority(raw);
    return targetAuthority.length > 0 &&
      (targetAuthority === this.normalizedAuthority(this.snapshot.pageUrl) ||
        targetAuthority === this.normalizedAuthority(this.snapshot.catalogUrl));
  }

  private normalizedAuthority(url: string): string {
    return this.sourceIdentityService.normalizedAuthority(url);
  }

  private cloneSnapshot(snapshot: NovelReaderSnapshot): NovelReaderSnapshot {
    return {
      visible: snapshot.visible,
      reentryAvailable: snapshot.reentryAvailable,
      reentryPageUrl: snapshot.reentryPageUrl,
      phase: snapshot.phase,
      bookIdentity: snapshot.bookIdentity,
      pageEntryAvailable: snapshot.pageEntryAvailable,
      pageEntryKind: snapshot.pageEntryKind,
      pageEntryTabId: snapshot.pageEntryTabId,
      pageEntryPageUrl: snapshot.pageEntryPageUrl,
      bookTitle: snapshot.bookTitle,
      bookAuthor: snapshot.bookAuthor,
      bookCoverUrl: snapshot.bookCoverUrl,
      bookCategory: snapshot.bookCategory,
      bookLatest: snapshot.bookLatest,
      bookSynopsis: snapshot.bookSynopsis,
      sourceHost: snapshot.sourceHost,
      pageUrl: snapshot.pageUrl,
      bookshelfDetailUrl: snapshot.bookshelfDetailUrl,
      catalogUrl: snapshot.catalogUrl,
      catalog: snapshot.catalog.map((entry: NovelReaderCatalogEntry): NovelReaderCatalogEntry => ({
        id: entry.id,
        ordinal: entry.ordinal,
        title: entry.title,
        url: entry.url
      })),
      catalogLoadingMore: snapshot.catalogLoadingMore,
      catalogLoadingRangeStart: snapshot.catalogLoadingRangeStart,
      catalogLoadingRangeEnd: snapshot.catalogLoadingRangeEnd,
      catalogHasMore: snapshot.catalogHasMore,
      catalogTotalHint: snapshot.catalogTotalHint,
      catalogRangeExtentHint: snapshot.catalogRangeExtentHint,
      catalogSupportsRandomAccess: snapshot.catalogSupportsRandomAccess,
      canNavigatePrevious: snapshot.canNavigatePrevious,
      canNavigateNext: snapshot.canNavigateNext,
      bookInBookshelf: snapshot.bookInBookshelf,
      bookshelfActionBusy: snapshot.bookshelfActionBusy,
      bookshelfAvailable: snapshot.bookshelfAvailable,
      topPrompt: this.copyTopPrompt(snapshot.topPrompt),
      overlayBackState: {
        panelVisible: snapshot.overlayBackState.panelVisible,
        dismissPanelRequestVersion: snapshot.overlayBackState.dismissPanelRequestVersion
      },
      bookPalette: snapshot.bookPalette === undefined
        ? undefined
        : cloneNovelBookCoverPalette(snapshot.bookPalette),
      bookPaletteKey: snapshot.bookPaletteKey,
      bookPaletteLoading: snapshot.bookPaletteLoading,
      preferences: this.copyPreferences(snapshot.preferences),
      position: {
        chapterId: snapshot.position.chapterId,
        characterOffset: snapshot.position.characterOffset
      },
      resumeHint: snapshot.resumeHint,
      activeChapterId: snapshot.activeChapterId,
      contentKind: snapshot.contentKind,
      chapterTrail: this.copyChapterTrail(snapshot.chapterTrail),
      openingTransition: this.copyOperation(snapshot.openingTransition),
      chapterTransition: this.copyOperation(snapshot.chapterTransition),
      catalogTransition: this.copyOperation(snapshot.catalogTransition),
      openingFailure: snapshot.openingFailure,
      scope: this.copyScope(snapshot.scope)
    };
  }

  private resolveResumeHint(session: NovelReadingSessionSnapshot): string {
    const pending: NovelReadingCheckpointRecord | undefined = this.pendingPersistedCheckpoint;
    if (pending === undefined || session.privacyMode !== 'regular' || session.bookId.length === 0 ||
      pending.bookId !== session.bookId) {
      return '从第一章开始阅读';
    }
    const chapter: NovelSessionCatalogChapter | undefined = session.catalog.find(
      (candidate: NovelSessionCatalogChapter): boolean => candidate.id === pending.chapterId &&
        this.normalizeUrl(candidate.canonicalUrl) === this.normalizeUrl(pending.canonicalUrl)
    );
    const title: string = chapter !== undefined ? chapter.title.trim() : pending.chapterTitle.trim();
    if (title.length > 0 && !this.isDigits(title)) {
      return `继续阅读到${title}`;
    }
    const ordinal: number = title.length > 0
      ? this.resolveChapterOrdinal(title)
      : (chapter !== undefined ? chapter.ordinal + 1 : -1);
    return ordinal > 0 ? `继续阅读到第${ordinal}章` : '继续阅读';
  }

  private copyOperation(operation: NovelSessionOperationSnapshot): NovelSessionOperationSnapshot {
    return {
      status: operation.status,
      requestId: operation.requestId,
      failureCode: operation.failureCode
    };
  }
}

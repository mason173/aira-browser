import { webview } from '@kit.ArkWeb';
import { BrowserSessionPrivacyMode } from '../../common/models/BrowserModels';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  NovelReaderBookshelfCacheOpenRequest,
  NovelReaderController,
  NovelReaderOpenRequest,
  NovelReaderSessionConnection,
  NovelReaderSessionOperations,
  NovelReaderTakeoverPreviewCapturePort
} from '../../features/novel/NovelReaderController';
import {
  NovelReaderAction,
  NovelReaderEffect,
  NovelReaderPageEntryKind,
  NovelReaderPageReadyFacts,
  NovelReaderPhase,
  NovelReadingRecoveryMarkerPort,
  NovelReadingRecoveryMarkerRecord,
  NovelReaderSessionListener,
  NovelReaderSessionScope,
  NovelReaderSnapshot
} from '../../features/novel/NovelReaderModels';

const NOVEL_RECOVERY_TIMEOUT_MS: number = 30000;

type NovelReaderCandidateProbePurpose = 'page_entry' | 'recovery';

interface NovelReaderCandidateProbe {
  key: string;
  purpose: NovelReaderCandidateProbePurpose;
  controller: NovelReaderController;
  connection?: NovelReaderSessionConnection;
  scope: NovelReaderSessionScope;
  pageUrl: string;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  sourceController?: webview.WebviewController;
}

interface NovelReaderPageEntryPresentation {
  available: boolean;
  kind: NovelReaderPageEntryKind;
  tabId: string;
  pageUrl: string;
}

function createHiddenPageEntry(): NovelReaderPageEntryPresentation {
  return {
    available: false,
    kind: '',
    tabId: '',
    pageUrl: ''
  };
}

class NovelReaderSessionCoordinatorConnection implements NovelReaderSessionConnection {
  private disconnectAction?: () => void;

  constructor(disconnectAction: () => void) {
    this.disconnectAction = disconnectAction;
  }

  disconnect(): void {
    const action = this.disconnectAction;
    this.disconnectAction = undefined;
    action?.();
  }
}

/**
 * Window-level Novel reading owner. It coordinates privacy boundaries, staged replacement and cold recovery;
 * each subordinate controller owns one boundary's live reading session.
 */
export class NovelReaderSessionCoordinator implements NovelReaderSessionOperations {
  private regularController: NovelReaderController;
  private privateController: NovelReaderController;
  private readonly createController: () => NovelReaderController;
  private readonly recoveryMarkerRepository: NovelReadingRecoveryMarkerPort;
  private readonly preferencesRepository?: PreferencesRepository;
  private preferencesListenerKey: string = '';
  private regularControllerConnection?: NovelReaderSessionConnection;
  private privateControllerConnection?: NovelReaderSessionConnection;
  private regularCandidateProbe?: NovelReaderCandidateProbe;
  private privateCandidateProbe?: NovelReaderCandidateProbe;
  private regularPageEntry: NovelReaderPageEntryPresentation = createHiddenPageEntry();
  private privatePageEntry: NovelReaderPageEntryPresentation = createHiddenPageEntry();
  private recoveryMarker?: NovelReadingRecoveryMarkerRecord;
  private recoveryLoading: boolean = false;
  private recoveryMarkerClearedForCurrentSession: boolean = false;
  private lastRegularControllerPhase: NovelReaderPhase = 'inactive';
  private recoveryMarkerWriteTask: Promise<void> = Promise.resolve();
  private recoveryTimeoutId: number = -1;
  private activePrivacyMode: BrowserSessionPrivacyMode = 'regular';
  private listener?: NovelReaderSessionListener;
  private listenerRevision: number = 0;
  private takeoverPreviewCapturePort?: NovelReaderTakeoverPreviewCapturePort;
  private takeoverPreviewCaptureRevision: number = 0;
  private regularTakeoverPreviewConnection?: NovelReaderSessionConnection;
  private privateTakeoverPreviewConnection?: NovelReaderSessionConnection;
  private bookshelfCacheOpenRevision: number = 0;

  constructor(
    regularController: NovelReaderController,
    privateController: NovelReaderController,
    createController: () => NovelReaderController,
    recoveryMarkerRepository: NovelReadingRecoveryMarkerPort,
    preferencesRepository?: PreferencesRepository
  ) {
    this.regularController = regularController;
    this.privateController = privateController;
    this.createController = createController;
    this.recoveryMarkerRepository = recoveryMarkerRepository;
    this.preferencesRepository = preferencesRepository;
    this.regularControllerConnection = this.bindController('regular', regularController);
    this.privateControllerConnection = this.bindController('private', privateController);
    if (this.preferencesRepository !== undefined) {
      this.preferencesListenerKey = this.preferencesRepository.subscribe((_preferences, scope): void => {
        if (scope === 'experiments') {
          this.handleExperimentPreferencesChanged();
        }
      });
    }
    void this.loadRecoveryMarker();
  }

  connectSessionListener(listener: NovelReaderSessionListener): NovelReaderSessionConnection {
    const revision = this.listenerRevision + 1;
    this.listenerRevision = revision;
    this.listener = listener;
    listener.onSnapshotChanged(this.getSnapshot());
    return new NovelReaderSessionCoordinatorConnection((): void => {
      if (this.listenerRevision === revision) {
        this.listener = undefined;
      }
    });
  }

  getSnapshot(): NovelReaderSnapshot {
    const snapshot = this.resolveController(this.activePrivacyMode).getSnapshot();
    if (this.activePrivacyMode === 'regular' && snapshot.phase === 'inactive' &&
      this.recoveryMarker !== undefined) {
      snapshot.phase = 'suspended';
      snapshot.visible = false;
      snapshot.bookIdentity = this.recoveryMarker.bookIdentity;
      snapshot.bookTitle = this.recoveryMarker.bookTitle;
      snapshot.pageUrl = this.recoveryMarker.sourcePageUrl;
      snapshot.scope = {
        tabId: this.recoveryMarker.sourceTabId,
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      snapshot.openingTransition = this.recoveryLoading
        ? { status: 'loading', requestId: 'cold-recovery', failureCode: '' }
        : { status: 'idle', requestId: '', failureCode: '' };
    }
    if (!this.isNovelModeEnabled()) {
      snapshot.reentryAvailable = false;
      snapshot.pageEntryAvailable = false;
      return snapshot;
    }
    const pageEntry = this.resolvePageEntry(this.activePrivacyMode);
    if (!snapshot.visible && pageEntry.available) {
      snapshot.pageEntryAvailable = true;
      snapshot.pageEntryKind = pageEntry.kind;
      snapshot.pageEntryTabId = pageEntry.tabId;
      snapshot.pageEntryPageUrl = pageEntry.pageUrl;
    }
    return snapshot;
  }

  shouldHandleSpaRouteReprobe(): boolean {
    return this.resolveController(this.activePrivacyMode).shouldHandleSpaRouteReprobe();
  }

  reconcileReentryForPageReady(facts: NovelReaderPageReadyFacts): void {
    this.activateBoundary(facts.scope.privacyMode);
    this.resolveController(facts.scope.privacyMode).reconcileReentryForPageReady(facts);
    const committedPageUrl: string = facts.acceptedNavigationCommitUrl ?? '';
    const acceptedPageUrl: string = committedPageUrl.trim().length > 0
      ? committedPageUrl
      : facts.pageUrl;
    if (!acceptedPageUrl.startsWith('http') || facts.scope.tabId !== facts.tabId) {
      return;
    }
    const mode: BrowserSessionPrivacyMode = facts.scope.privacyMode;
    const probe: NovelReaderCandidateProbe | undefined = this.resolveCandidateProbe(mode);
    const pageEntry: NovelReaderPageEntryPresentation = this.resolvePageEntry(mode);
    const acceptedIdentity: string = this.normalizePageEntryUrl(acceptedPageUrl);
    const staleProbe: boolean = probe !== undefined && probe.scope.tabId === facts.tabId &&
      this.normalizePageEntryUrl(probe.pageUrl) !== acceptedIdentity;
    const stalePageEntry: boolean = pageEntry.available && pageEntry.tabId === facts.tabId &&
      this.normalizePageEntryUrl(pageEntry.pageUrl) !== acceptedIdentity;
    if (staleProbe || stalePageEntry) {
      this.clearCandidateProbe(mode);
      this.setPageEntry(mode, createHiddenPageEntry());
    }
  }

  handlePageReadyForAutoDetection(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void {
    if (facts.scope.privacyMode === 'regular') {
      this.bookshelfCacheOpenRevision = this.bookshelfCacheOpenRevision + 1;
    }
    this.reconcileReentryForPageReady(facts);
    const controller = this.resolveController(facts.scope.privacyMode);
    if (!this.isNovelModeEnabled()) {
      this.clearCandidateProbe(facts.scope.privacyMode);
      this.setPageEntry(facts.scope.privacyMode, createHiddenPageEntry());
      if (controller.getSnapshot().visible) {
        controller.handlePageReadyForAutoDetection(runtimeLifecyclePort, facts);
      }
      return;
    }
    if (facts.scope.privacyMode === 'regular' && this.recoveryLoading) {
      const marker = this.recoveryMarker;
      if (marker !== undefined && (facts.tabId === marker.sourceTabId ||
        this.normalizeRecoveryUrl(facts.pageUrl) === this.normalizeRecoveryUrl(marker.sourcePageUrl) ||
        this.normalizeRecoveryAuthority(facts.pageUrl) ===
          this.normalizeRecoveryAuthority(marker.sourcePageUrl))) {
        this.startCandidateProbe('regular', 'recovery', runtimeLifecyclePort, facts);
      }
      return;
    }
    if (controller.getSnapshot().phase === 'suspended') {
      this.handleSuspendedPageReady(controller, runtimeLifecyclePort, facts);
      return;
    }
    if (controller.getSnapshot().phase === 'inactive' && !this.isAutomaticTakeoverEnabled()) {
      if (facts.tabId !== facts.activeTabId || facts.tabId !== facts.scope.tabId ||
        !facts.webPageVisible || !facts.pageUrl.startsWith('http')) {
        return;
      }
      this.startCandidateProbe(facts.scope.privacyMode, 'page_entry', runtimeLifecyclePort, facts);
      return;
    }
    this.clearCandidateProbe(facts.scope.privacyMode);
    this.setPageEntry(facts.scope.privacyMode, createHiddenPageEntry());
    controller.handlePageReadyForAutoDetection(runtimeLifecyclePort, facts);
  }

  async openFromLifecyclePort(request: NovelReaderOpenRequest): Promise<void> {
    if (request.scope.privacyMode === 'regular') {
      this.bookshelfCacheOpenRevision = this.bookshelfCacheOpenRevision + 1;
    }
    this.activateBoundary(request.scope.privacyMode);
    await this.resolveController(request.scope.privacyMode).openFromLifecyclePort(request);
  }

  async openBookshelfFromPersistentCache(
    request: NovelReaderBookshelfCacheOpenRequest
  ): Promise<boolean> {
    this.activateBoundary('regular');
    const revision: number = this.bookshelfCacheOpenRevision + 1;
    this.bookshelfCacheOpenRevision = revision;
    const candidate: NovelReaderController = this.createController();
    const opened: boolean = await candidate.openBookshelfFromPersistentCache(request);
    if (!opened || revision !== this.bookshelfCacheOpenRevision) {
      candidate.close();
      return false;
    }
    this.clearCandidateProbe('regular');
    this.replaceController('regular', candidate);
    return true;
  }

  connectTakeoverPreviewCapture(
    port?: NovelReaderTakeoverPreviewCapturePort
  ): NovelReaderSessionConnection {
    const revision = this.takeoverPreviewCaptureRevision + 1;
    this.takeoverPreviewCaptureRevision = revision;
    this.regularTakeoverPreviewConnection?.disconnect();
    this.privateTakeoverPreviewConnection?.disconnect();
    this.takeoverPreviewCapturePort = port;
    this.regularTakeoverPreviewConnection = this.regularController.connectTakeoverPreviewCapture(port);
    this.privateTakeoverPreviewConnection = this.privateController.connectTakeoverPreviewCapture(port);
    return new NovelReaderSessionCoordinatorConnection((): void => {
      if (this.takeoverPreviewCaptureRevision === revision) {
        this.regularTakeoverPreviewConnection?.disconnect();
        this.privateTakeoverPreviewConnection?.disconnect();
        this.regularTakeoverPreviewConnection = undefined;
        this.privateTakeoverPreviewConnection = undefined;
        this.takeoverPreviewCapturePort = undefined;
      }
    });
  }

  handleAction(action: NovelReaderAction): void {
    if (action.type === 'activate_page_entry') {
      void this.activatePageEntry();
      return;
    }
    if (action.type === 'continue_reading' && this.activePrivacyMode === 'regular' &&
      this.regularController.getSnapshot().phase === 'inactive' && this.recoveryMarker !== undefined) {
      this.recoveryLoading = true;
      this.startRecoveryTimeout();
      this.publishCurrentSnapshot();
      this.listener?.onEffect?.({
        type: 'recover_suspended_reading',
        tabId: this.recoveryMarker.sourceTabId,
        url: this.recoveryMarker.sourcePageUrl,
        title: this.recoveryMarker.bookTitle
      });
      return;
    }
    this.resolveController(this.activePrivacyMode).handleAction(action);
  }

  close(): void {
    if (this.preferencesRepository !== undefined && this.preferencesListenerKey.length > 0) {
      this.preferencesRepository.unsubscribe(this.preferencesListenerKey);
      this.preferencesListenerKey = '';
    }
    this.stopRecoveryTimeout();
    this.clearCandidateProbe('regular');
    this.clearCandidateProbe('private');
    this.regularControllerConnection?.disconnect();
    this.privateControllerConnection?.disconnect();
    this.regularTakeoverPreviewConnection?.disconnect();
    this.privateTakeoverPreviewConnection?.disconnect();
    this.regularController.close();
    this.privateController.close();
    this.regularTakeoverPreviewConnection = undefined;
    this.privateTakeoverPreviewConnection = undefined;
    this.takeoverPreviewCapturePort = undefined;
  }

  reconcileWindowState(
    activePrivacyMode: BrowserSessionPrivacyMode,
    activeTabId: string,
    tabIds: string[],
    activeController?: webview.WebviewController
  ): void {
    this.activateBoundary(activePrivacyMode);
    this.regularController.reconcileWindowState(activeTabId, tabIds, activeController);
    this.privateController.reconcileWindowState(activeTabId, tabIds, activeController);
    this.publishCurrentSnapshot();
  }

  private bindController(
    mode: BrowserSessionPrivacyMode,
    controller: NovelReaderController
  ): NovelReaderSessionConnection {
    return controller.connectSessionListener({
      onSnapshotChanged: (_snapshot: NovelReaderSnapshot): void => {
        if (mode === 'regular') {
          this.synchronizeRecoveryMarker(_snapshot);
        }
        if (mode === this.activePrivacyMode) {
          this.publishCurrentSnapshot();
        }
      },
      onEffect: (effect: NovelReaderEffect): boolean => this.forwardEffect(mode, effect)
    });
  }

  private async loadRecoveryMarker(): Promise<void> {
    const marker = await this.recoveryMarkerRepository.load();
    if (marker === undefined || this.regularController.getSnapshot().phase !== 'inactive') {
      return;
    }
    this.recoveryMarker = marker;
    this.recoveryMarkerClearedForCurrentSession = false;
    if (this.activePrivacyMode === 'regular') {
      this.publishCurrentSnapshot();
    }
  }

  private synchronizeRecoveryMarker(snapshot: NovelReaderSnapshot): void {
    const previousPhase = this.lastRegularControllerPhase;
    this.lastRegularControllerPhase = snapshot.phase;
    if (snapshot.phase === 'suspended' && snapshot.bookIdentity.length > 0 &&
      snapshot.bookTitle.length > 0 && snapshot.pageUrl.startsWith('http')) {
      const marker: NovelReadingRecoveryMarkerRecord = {
        bookIdentity: snapshot.bookIdentity,
        bookTitle: snapshot.bookTitle,
        sourceTabId: snapshot.scope.tabId,
        sourcePageUrl: snapshot.pageUrl,
        updatedAt: Date.now()
      };
      this.recoveryMarker = marker;
      this.recoveryMarkerClearedForCurrentSession = false;
      this.enqueueRecoveryMarkerWrite((): Promise<void> => this.recoveryMarkerRepository.save(marker));
      return;
    }
    if (snapshot.visible && (snapshot.phase === 'book' || snapshot.phase === 'reader')) {
      this.clearRecoveryMarker();
      return;
    }
    if (snapshot.phase === 'inactive' &&
      (previousPhase === 'book' || previousPhase === 'reader' || previousPhase === 'suspended' ||
        this.recoveryLoading)) {
      this.clearRecoveryMarker();
    }
  }

  private clearRecoveryMarker(): void {
    if (this.recoveryMarkerClearedForCurrentSession && this.recoveryMarker === undefined &&
      !this.recoveryLoading) {
      return;
    }
    const hadMarker = this.recoveryMarker !== undefined || this.recoveryLoading;
    this.stopRecoveryTimeout();
    this.recoveryMarker = undefined;
    this.recoveryLoading = false;
    this.recoveryMarkerClearedForCurrentSession = true;
    this.enqueueRecoveryMarkerWrite((): Promise<void> => this.recoveryMarkerRepository.clear());
    if (hadMarker && this.activePrivacyMode === 'regular') {
      this.publishCurrentSnapshot();
    }
  }

  private enqueueRecoveryMarkerWrite(operation: () => Promise<void>): void {
    this.recoveryMarkerWriteTask = this.recoveryMarkerWriteTask
      .catch((_error: Error): void => {
      })
      .then(operation)
      .catch((_error: Error): void => {
      });
  }

  private normalizeRecoveryUrl(value: string): string {
    const trimmed = value.trim();
    const fragmentIndex = trimmed.indexOf('#');
    const withoutFragment = fragmentIndex >= 0 ? trimmed.substring(0, fragmentIndex) : trimmed;
    return withoutFragment.endsWith('/') ? withoutFragment.substring(0, withoutFragment.length - 1) : withoutFragment;
  }

  private normalizePageEntryUrl(value: string): string {
    const trimmed: string = value.trim();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  private normalizeRecoveryAuthority(value: string): string {
    const normalized = this.normalizeRecoveryUrl(value).toLowerCase();
    const schemeIndex = normalized.indexOf('://');
    const authorityStart = schemeIndex >= 0 ? schemeIndex + 3 : 0;
    const suffixIndex = normalized.indexOf('/', authorityStart);
    return suffixIndex >= 0 ? normalized.substring(authorityStart, suffixIndex) :
      normalized.substring(authorityStart);
  }

  private startRecoveryTimeout(): void {
    this.stopRecoveryTimeout();
    this.recoveryTimeoutId = setTimeout((): void => {
      this.recoveryTimeoutId = -1;
      if (this.recoveryLoading) {
        this.clearCandidateProbe('regular');
        this.clearRecoveryMarker();
      }
    }, NOVEL_RECOVERY_TIMEOUT_MS);
  }

  private stopRecoveryTimeout(): void {
    if (this.recoveryTimeoutId < 0) {
      return;
    }
    clearTimeout(this.recoveryTimeoutId);
    this.recoveryTimeoutId = -1;
  }

  private handleSuspendedPageReady(
    controller: NovelReaderController,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void {
    const snapshot = controller.getSnapshot();
    if (facts.tabId === snapshot.scope.tabId &&
      this.normalizeRecoveryUrl(facts.pageUrl) === this.normalizeRecoveryUrl(snapshot.pageUrl)) {
      this.clearCandidateProbe(facts.scope.privacyMode);
      this.setPageEntry(facts.scope.privacyMode, {
        available: true,
        kind: 'resume',
        tabId: facts.tabId,
        pageUrl: facts.pageUrl
      });
      controller.handlePageReadyForAutoDetection(runtimeLifecyclePort, facts);
      return;
    }
    this.startCandidateProbe(facts.scope.privacyMode, 'page_entry', runtimeLifecyclePort, facts);
  }

  private startCandidateProbe(
    mode: BrowserSessionPrivacyMode,
    purpose: NovelReaderCandidateProbePurpose,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    facts: NovelReaderPageReadyFacts
  ): void {
    const probeKey = `${purpose}|${facts.scope.privacyMode}|${facts.tabId}|${facts.pageUrl}`;
    const existingProbe: NovelReaderCandidateProbe | undefined = this.resolveCandidateProbe(facts.scope.privacyMode);
    if (existingProbe?.key === probeKey) {
      return;
    }
    this.clearCandidateProbe(mode);
    if (purpose === 'page_entry') {
      this.setPageEntry(mode, createHiddenPageEntry());
    }
    const candidate = this.createController();
    const probe: NovelReaderCandidateProbe = {
      key: probeKey,
      purpose: purpose,
      controller: candidate,
      scope: {
        tabId: facts.scope.tabId,
        privacyMode: facts.scope.privacyMode,
        dataScope: facts.scope.dataScope
      },
      pageUrl: facts.pageUrl,
      runtimeLifecyclePort: runtimeLifecyclePort,
      sourceController: runtimeLifecyclePort.resolveActiveController()
    };
    this.setCandidateProbe(mode, probe);
    probe.connection = candidate.connectSessionListener({
      onSnapshotChanged: (candidateSnapshot: NovelReaderSnapshot): void => {
        this.handleCandidateSnapshot(mode, probe, candidateSnapshot);
      },
      onEffect: (_effect: NovelReaderEffect): boolean => false
    });
    if (purpose === 'page_entry') {
      candidate.handlePageReadyForCandidateDetection(runtimeLifecyclePort, facts);
    } else {
      void candidate.openFromLifecyclePort({
        runtimeLifecyclePort: runtimeLifecyclePort,
        webPageVisible: facts.webPageVisible,
        pageUrl: facts.pageUrl,
        requireDetectedPage: false,
        entryReason: 'manual',
        scope: probe.scope
      });
    }
  }

  private handleCandidateSnapshot(
    mode: BrowserSessionPrivacyMode,
    probe: NovelReaderCandidateProbe,
    candidateSnapshot: NovelReaderSnapshot
  ): void {
    if (this.resolveCandidateProbe(mode) !== probe) {
      return;
    }
    if (probe.purpose === 'recovery') {
      this.handleRecoveryCandidateSnapshot(probe, candidateSnapshot);
      return;
    }
    if (!candidateSnapshot.visible ||
      (candidateSnapshot.phase !== 'book' && candidateSnapshot.phase !== 'reader') ||
      candidateSnapshot.bookIdentity.length === 0) {
      if (candidateSnapshot.openingFailure.length > 0) {
        this.clearCandidateProbe(mode);
        this.setPageEntry(mode, createHiddenPageEntry());
      }
      return;
    }
    const currentIdentity = this.resolveController(mode).getSnapshot().bookIdentity;
    this.setPageEntry(mode, {
      available: true,
      kind: currentIdentity.length > 0 && candidateSnapshot.bookIdentity === currentIdentity ? 'resume' : 'replace',
      tabId: probe.scope.tabId,
      pageUrl: probe.pageUrl
    });
  }

  private isNovelModeEnabled(): boolean {
    return this.preferencesRepository?.getPreferences().experiments.novelModeEnabled ?? true;
  }

  private isAutomaticTakeoverEnabled(): boolean {
    const experiments = this.preferencesRepository?.getPreferences().experiments;
    return experiments !== undefined && experiments.novelModeEnabled && experiments.novelAutoTakeoverEnabled;
  }

  private handleExperimentPreferencesChanged(): void {
    if (!this.isNovelModeEnabled()) {
      this.clearCandidateProbe('regular');
      this.clearCandidateProbe('private');
      this.regularPageEntry = createHiddenPageEntry();
      this.privatePageEntry = createHiddenPageEntry();
    }
    this.publishCurrentSnapshot();
  }

  private handleRecoveryCandidateSnapshot(
    probe: NovelReaderCandidateProbe,
    candidateSnapshot: NovelReaderSnapshot
  ): void {
    const marker = this.recoveryMarker;
    if (candidateSnapshot.openingFailure.length > 0) {
      this.clearCandidateProbe('regular');
      this.clearRecoveryMarker();
      return;
    }
    if (!candidateSnapshot.visible ||
      (candidateSnapshot.phase !== 'book' && candidateSnapshot.phase !== 'reader') ||
      candidateSnapshot.bookIdentity.length === 0) {
      return;
    }
    if (marker === undefined || candidateSnapshot.bookIdentity !== marker.bookIdentity) {
      this.clearCandidateProbe('regular');
      this.clearRecoveryMarker();
      return;
    }
    this.promoteCandidateController('regular', probe);
  }

  private async activatePageEntry(): Promise<void> {
    const mode = this.activePrivacyMode;
    if (!this.isNovelModeEnabled()) {
      this.clearCandidateProbe(mode);
      this.setPageEntry(mode, createHiddenPageEntry());
      return;
    }
    const entry = this.resolvePageEntry(mode);
    if (!entry.available) {
      return;
    }
    if (entry.kind === 'resume') {
      this.clearCandidateProbe(mode);
      this.setPageEntry(mode, createHiddenPageEntry());
      this.resolveController(mode).handleAction({ type: 'continue_reading' });
      return;
    }
    const probe = this.resolveCandidateProbe(mode);
    if (entry.kind !== 'replace' || probe === undefined ||
      !probe.controller.getSnapshot().visible) {
      return;
    }
    if (!this.isCandidateSourceRuntimeCurrent(probe)) {
      return;
    }
    if (!await this.prepareSourceTabPreview(probe.scope, probe.pageUrl)) {
      return;
    }
    if (this.resolveCandidateProbe(mode) !== probe ||
      this.resolvePageEntry(mode).kind !== 'replace' ||
      !probe.controller.getSnapshot().visible ||
      !this.isCandidateSourceRuntimeCurrent(probe)) {
      return;
    }
    this.promoteCandidateController(mode, probe);
  }

  private async prepareSourceTabPreview(
    scope: NovelReaderSessionScope,
    pageUrl: string
  ): Promise<boolean> {
    const port = this.takeoverPreviewCapturePort;
    if (port === undefined) {
      return true;
    }
    if (scope.tabId.trim().length === 0 || !port.isSourceTabCurrent(scope, pageUrl)) {
      return false;
    }
    const captured: boolean = await port.captureSourceTabPreview(scope.tabId);
    const samePort: boolean = this.takeoverPreviewCapturePort === port;
    const currentAfterCapture: boolean = samePort && port.isSourceTabCurrent(scope, pageUrl);
    return currentAfterCapture;
  }

  private isCandidateSourceRuntimeCurrent(probe: NovelReaderCandidateProbe): boolean {
    return probe.sourceController !== undefined &&
      probe.runtimeLifecyclePort.resolveActiveController() === probe.sourceController;
  }

  private promoteCandidateController(
    mode: BrowserSessionPrivacyMode,
    probe: NovelReaderCandidateProbe
  ): void {
    probe.connection?.disconnect();
    this.replaceController(mode, probe.controller);
  }

  private replaceController(
    mode: BrowserSessionPrivacyMode,
    controller: NovelReaderController
  ): void {
    const previousController: NovelReaderController = this.resolveController(mode);
    const takeoverPreviewConnection: NovelReaderSessionConnection = controller.connectTakeoverPreviewCapture(
      this.takeoverPreviewCapturePort
    );
    if (mode === 'private') {
      this.privateTakeoverPreviewConnection?.disconnect();
      this.privateControllerConnection?.disconnect();
      this.privateController = controller;
      this.privateCandidateProbe = undefined;
      this.privatePageEntry = createHiddenPageEntry();
      this.privateTakeoverPreviewConnection = takeoverPreviewConnection;
      this.privateControllerConnection = this.bindController(mode, controller);
    } else {
      this.regularTakeoverPreviewConnection?.disconnect();
      this.regularControllerConnection?.disconnect();
      this.regularController = controller;
      this.regularCandidateProbe = undefined;
      this.regularPageEntry = createHiddenPageEntry();
      this.regularTakeoverPreviewConnection = takeoverPreviewConnection;
      this.regularControllerConnection = this.bindController(mode, controller);
    }
    previousController.close();
    this.publishCurrentSnapshot();
  }

  private clearCandidateProbe(mode: BrowserSessionPrivacyMode): void {
    const probe = this.resolveCandidateProbe(mode);
    if (probe !== undefined) {
      probe.connection?.disconnect();
      probe.controller.close();
    }
    this.setCandidateProbe(mode, undefined);
  }

  private resolveCandidateProbe(mode: BrowserSessionPrivacyMode): NovelReaderCandidateProbe | undefined {
    return mode === 'private' ? this.privateCandidateProbe : this.regularCandidateProbe;
  }

  private setCandidateProbe(
    mode: BrowserSessionPrivacyMode,
    probe: NovelReaderCandidateProbe | undefined
  ): void {
    if (mode === 'private') {
      this.privateCandidateProbe = probe;
      return;
    }
    this.regularCandidateProbe = probe;
  }

  private resolvePageEntry(mode: BrowserSessionPrivacyMode): NovelReaderPageEntryPresentation {
    return mode === 'private' ? this.privatePageEntry : this.regularPageEntry;
  }

  private setPageEntry(mode: BrowserSessionPrivacyMode, entry: NovelReaderPageEntryPresentation): void {
    if (mode === 'private') {
      this.privatePageEntry = entry;
    } else {
      this.regularPageEntry = entry;
    }
    if (mode === this.activePrivacyMode) {
      this.publishCurrentSnapshot();
    }
  }

  private forwardEffect(mode: BrowserSessionPrivacyMode, effect: NovelReaderEffect): boolean {
    if (mode !== this.activePrivacyMode && effect.type !== 'restore_window_brightness' &&
      effect.type !== 'status_bar_visibility_release' && effect.type !== 'close_system_sheet') {
      return false;
    }
    const listener = this.listener;
    return listener !== undefined && listener.onEffect !== undefined ? listener.onEffect(effect) : false;
  }

  private activateBoundary(mode: BrowserSessionPrivacyMode): void {
    if (this.activePrivacyMode === mode) {
      return;
    }
    this.activePrivacyMode = mode;
    this.publishCurrentSnapshot();
  }

  private publishCurrentSnapshot(): void {
    this.listener?.onSnapshotChanged(this.getSnapshot());
  }

  private resolveController(mode: BrowserSessionPrivacyMode): NovelReaderController {
    return mode === 'private' ? this.privateController : this.regularController;
  }
}

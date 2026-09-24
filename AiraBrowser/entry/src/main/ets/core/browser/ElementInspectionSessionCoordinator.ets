import { BrowserClipboardCopyResult, BrowserClipboardService } from '../../services/share/BrowserClipboardService';
import {
  ElementInspectionBoxModel,
  ElementInspectionComputedProperty,
  ElementInspectionConsoleEntry,
  ElementInspectionListenerEntry,
  ElementInspectionNavigationRelation,
  ElementInspectionNetworkEntry,
  ElementInspectionOutlineNode,
  ElementInspectionPageInfo,
  ElementInspectionRuntimeAttribute,
  ElementInspectionRuntimeNodeSnapshot,
  ElementInspectionContextActionResult,
  ElementInspectionRuntimeScriptService,
  ElementInspectionRuntimeSnapshot,
  ElementInspectionSecuritySummary,
  ElementInspectionSourceEntry,
  ElementInspectionSourcePreview,
  ElementInspectionStorageEntry,
  ElementInspectionStorageSnapshot
} from '../../services/web/ElementInspectionRuntimeScriptService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserTransientSurfaceCoordinator } from './BrowserTransientSurfaceCoordinator';

export type ElementInspectionSessionPhase =
  'inactive' |
  'starting' |
  'selecting' |
  'inspected' |
  'closing';

export type ElementInspectionAction =
  'cancel' |
  'reselect' |
  'navigate_parent' |
  'navigate_first_child' |
  'navigate_previous_sibling' |
  'navigate_next_sibling' |
  'copy_selector' |
  'copy_html';

export interface ElementInspectionOutlineCommand {
  kind: string;
  path: string;
  name: string;
  value: string;
  requestId: number;
  previousName?: string;
}

export interface ElementInspectionOutlineDraft {
  requestId: number;
  path: string;
  kind: string;
  text: string;
  ready: boolean;
  reason: string;
}

interface ElementInspectionAttributePayload {
  name: string;
  value: string;
  previousName?: string;
}

export interface ElementInspectionSessionFacts {
  activeTabId: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
  webPageVisible: boolean;
  highlightColor: string;
}

export interface ElementInspectionPresentation {
  active: boolean;
  phase: ElementInspectionSessionPhase;
  busy: boolean;
  helperText: string;
  pickerArmed: boolean;
  outline: ElementInspectionOutlineNode[];
  computed: ElementInspectionComputedProperty[];
  logs: ElementInspectionConsoleEntry[];
  network: ElementInspectionNetworkEntry[];
  sources: ElementInspectionSourceEntry[];
  listeners: ElementInspectionListenerEntry[];
  pageInfo?: ElementInspectionPageInfo;
  storage?: ElementInspectionStorageSnapshot;
  security?: ElementInspectionSecuritySummary;
  sourcePreview?: ElementInspectionSourcePreview;
  node?: ElementInspectionRuntimeNodeSnapshot;
  box?: ElementInspectionBoxModel;
  outlineDraft?: ElementInspectionOutlineDraft;
}

export interface ElementInspectionSessionShell {
  resolveFacts: () => ElementInspectionSessionFacts;
  publishPresentation: (presentation: ElementInspectionPresentation) => void;
  showToast: (message: string) => void;
}

const ELEMENT_INSPECTION_POLL_INTERVAL_MS: number = 120;
const ELEMENT_INSPECTION_REVEAL_DELAY_MS: number = 0;
const ELEMENT_INSPECTION_DISMISS_DURATION_MS: number = 220;
const ELEMENT_INSPECTION_SHELL_RESUME_RETRY_DELAY_MS: number = 120;
const ELEMENT_INSPECTION_SHELL_RESUME_MAX_RETRIES: number = 20;
const ELEMENT_INSPECTION_REATTACH_RETRY_DELAY_MS: number = 200;

export class ElementInspectionSessionCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly clipboardService: BrowserClipboardService;
  private readonly runtimeScriptService: ElementInspectionRuntimeScriptService;
  private readonly shell: ElementInspectionSessionShell;
  private presentation: ElementInspectionPresentation = this.buildInactivePresentation();
  private sessionGeneration: number = 0;
  private operationSequence: number = 0;
  private runtimeRevision: number = 0;
  private originTabId: string = '';
  private documentToken: string = '';
  private certificateErrorTabId: string = '';
  private certificateErrorUrl: string = '';
  private pollTimer: number = -1;
  private pollInFlight: boolean = false;
  private selectionInFlight: boolean = false;
  private hoverInFlight: boolean = false;
  private hoverSelectInFlight: boolean = false;
  private pendingHoverX: number = -1;
  private pendingHoverY: number = -1;
  private lastHoverX: number = -1;
  private lastHoverY: number = -1;
  private hoverSelectTimer: number = -1;
  private hoverEpoch: number = 0;
  private outlinePreviewEpoch: number = 0;
  private pendingOutlinePath: string = '';
  private outlinePreviewInFlight: boolean = false;
  private outlineCommandInFlight: boolean = false;
  private outlineCommandQueued: boolean = false;
  private queuedOutlineCommand: ElementInspectionOutlineCommand = {
    kind: '',
    path: '',
    name: '',
    value: '',
    requestId: 0
  };
  private outlineReadRequestId: number = 0;
  private pollEpoch: number = 0;
  private closeTimer: number = -1;
  private shellPaused: boolean = false;
  private shellResumeInFlight: boolean = false;
  private shellResumeRequested: boolean = false;
  private shellResumeRetryTimer: number = -1;
  private shellResumeRetryCount: number = 0;
  private shellLifecycleEpoch: number = 0;
  private reattachRequested: boolean = false;
  private reattachTimer: number = -1;
  private reattachInFlightGeneration: number = 0;

  constructor(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    clipboardService: BrowserClipboardService,
    shell: ElementInspectionSessionShell,
    runtimeScriptService: ElementInspectionRuntimeScriptService = new ElementInspectionRuntimeScriptService()
  ) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.clipboardService = clipboardService;
    this.shell = shell;
    this.runtimeScriptService = runtimeScriptService;
  }

  snapshot(): ElementInspectionPresentation {
    return this.clonePresentation(this.presentation);
  }

  canStart(): boolean {
    if (this.presentation.active) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    return facts.activeTabId.trim().length > 0 &&
      !facts.showHomePage &&
      !facts.showTabsSheet &&
      facts.webPageVisible &&
      this.runtimeLifecyclePort.hasLiveRuntimeController(facts.activeTabId);
  }

  startFromToolbar(): void {
    void this.runStartFromToolbar();
  }

  setPickerArmed(armed: boolean): void {
    if (!this.presentation.active || this.presentation.phase === 'closing' ||
      this.presentation.pickerArmed === armed) {
      return;
    }
    const next = this.clonePresentation(this.presentation);
    next.pickerArmed = armed;
    this.publish(next);
    this.cancelHoverTracking();
    void this.runSetPickerArmed(armed);
  }

  previewAtNormalizedPoint(normalizedX: number, normalizedY: number): void {
    if (!this.canHoverPreview(normalizedX, normalizedY)) {
      return;
    }
    this.pendingHoverX = Math.min(1, Math.max(0, normalizedX));
    this.pendingHoverY = Math.min(1, Math.max(0, normalizedY));
    this.lastHoverX = this.pendingHoverX;
    this.lastHoverY = this.pendingHoverY;
    this.scheduleHoverSelect();
    if (!this.hoverInFlight) {
      void this.drainHoverPreview();
    }
  }

  previewOutline(path: string): void {
    if (!this.runtimeScriptService.isOutlinePath(path) || !this.canPreviewOutline()) {
      return;
    }
    this.outlinePreviewEpoch += 1;
    this.pendingOutlinePath = path;
    this.pendingHoverX = -1;
    this.pendingHoverY = -1;
    if (!this.outlinePreviewInFlight) {
      void this.drainOutlinePreview();
    }
  }

  clearOutlinePreview(): void {
    const epoch = this.outlinePreviewEpoch + 1;
    this.outlinePreviewEpoch = epoch;
    this.pendingOutlinePath = '';
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    if (tabId.length === 0 || documentToken.length === 0) {
      return;
    }
    setTimeout((): void => {
      if (epoch !== this.outlinePreviewEpoch || !this.isCurrentGeneration(generation)) {
        return;
      }
      void this.runClearPreview(generation, tabId, documentToken);
    }, 50);
  }

  clearHoverPreview(): void {
    this.hoverEpoch += 1;
    this.pendingHoverX = -1;
    this.pendingHoverY = -1;
    this.lastHoverX = -1;
    this.lastHoverY = -1;
    if (this.hoverSelectTimer >= 0) {
      clearTimeout(this.hoverSelectTimer);
      this.hoverSelectTimer = -1;
    }
    if (!this.presentation.active || this.originTabId.length === 0 || this.documentToken.length === 0) {
      return;
    }
    void this.runClearPreview(this.sessionGeneration, this.originTabId, this.documentToken);
  }

  evaluateConsole(expression: string): void {
    const normalized = expression.trim();
    if (normalized.length === 0 || normalized.length > 2000 || !this.canRunDebugCommand()) {
      return;
    }
    void this.runEvaluateConsole(normalized);
  }

  clearConsole(): void {
    if (!this.canRunDebugCommand()) {
      return;
    }
    void this.runClearConsole();
  }

  readSource(sourceId: string): void {
    if (!this.runtimeScriptService.isSourceId(sourceId) || !this.canRunDebugCommand()) {
      return;
    }
    void this.runReadSource(sourceId);
  }

  selectOutline(path: string): void {
    if (!this.runtimeScriptService.isOutlinePath(path) ||
      !this.presentation.active || this.presentation.busy || this.selectionInFlight ||
      (this.presentation.phase !== 'selecting' && this.presentation.phase !== 'inspected') ||
      this.isSelectedOutlinePath(path)) {
      return;
    }
    void this.runSelectOutline(path);
  }

  runOutlineCommand(command: ElementInspectionOutlineCommand): void {
    if (!this.runtimeScriptService.isOutlinePath(command.path) ||
      !this.runtimeScriptService.isOutlineCommandKind(command.kind) ||
      !this.canRunOutlineCommand()) {
      return;
    }
    if (this.selectionInFlight || this.outlineCommandInFlight) {
      this.queueOutlineCommand(command);
      return;
    }
    void this.executeOutlineCommand(command);
  }

  selectAtNormalizedPoint(normalizedX: number, normalizedY: number): void {
    if (!Number.isFinite(normalizedX) || !Number.isFinite(normalizedY) ||
      !this.presentation.active || this.presentation.busy || this.selectionInFlight ||
      (this.presentation.phase !== 'selecting' && this.presentation.phase !== 'inspected')) {
      return;
    }
    void this.runSelectAtNormalizedPoint(
      Math.min(1, Math.max(0, normalizedX)),
      Math.min(1, Math.max(0, normalizedY))
    );
  }

  handleAction(action: ElementInspectionAction): void {
    switch (action) {
      case 'cancel':
        this.close('user_cancel');
        return;
      case 'reselect':
        void this.runReselect();
        return;
      case 'navigate_parent':
        void this.runNavigation('parent');
        return;
      case 'navigate_first_child':
        void this.runNavigation('first_child');
        return;
      case 'navigate_previous_sibling':
        void this.runNavigation('previous_sibling');
        return;
      case 'navigate_next_sibling':
        void this.runNavigation('next_sibling');
        return;
      case 'copy_selector':
        void this.copySelector();
        return;
      case 'copy_html':
        void this.copyHtml();
        return;
      default:
        return;
    }
  }

  handleBack(): void {
    this.close('system_back');
  }

  handlePageBegin(tabId: string, url: string = ''): void {
    if (url.length > 0 && tabId === this.certificateErrorTabId &&
      !this.sameOrigin(this.certificateErrorUrl, url)) {
      this.certificateErrorTabId = '';
      this.certificateErrorUrl = '';
    }
    if (this.presentation.active && tabId === this.originTabId && this.presentation.phase !== 'closing') {
      this.beginDocumentReattach();
    }
  }

  handlePageEnd(tabId: string): void {
    if (!this.reattachRequested || tabId !== this.originTabId || this.presentation.phase === 'closing') {
      return;
    }
    this.clearReattachTimer();
    this.scheduleDocumentReattach();
  }

  noteCertificateError(tabId: string, url: string): void {
    const normalized = url.trim();
    if (tabId.length === 0 || normalized.length === 0) {
      return;
    }
    this.certificateErrorTabId = tabId;
    this.certificateErrorUrl = normalized.length > 180 ? normalized.substring(0, 180) : normalized;
    if (this.presentation.active && this.originTabId === tabId) {
      this.publish(this.presentation);
    }
  }

  handleActiveTabChanged(previousTabId: string, activeTabId: string): void {
    if (!this.presentation.active || previousTabId !== this.originTabId || activeTabId === this.originTabId) {
      return;
    }
    this.close('active_tab_changed');
  }

  handleOriginRuntimeRemoved(tabId: string): void {
    if (this.presentation.active && tabId === this.originTabId) {
      this.close('origin_runtime_removed', true);
    }
  }

  handleShellDisappear(): void {
    if (!this.presentation.active || this.presentation.phase === 'closing') {
      return;
    }
    this.shellLifecycleEpoch += 1;
    this.shellPaused = true;
    this.shellResumeRequested = false;
    this.clearShellResumeRetry();
    this.shellResumeRetryCount = 0;
    this.stopSelectionPolling();
  }

  shouldPreserveSurfaceForShellLifecycle(): boolean {
    return this.presentation.active && this.presentation.phase !== 'closing';
  }

  handleShellAppear(): void {
    if (!this.presentation.active || this.presentation.phase === 'closing') {
      return;
    }
    if (!this.shellPaused && this.transientSurfaceCoordinator.isMounted('element_inspection')) {
      return;
    }
    if (!this.shellPaused) {
      this.shellLifecycleEpoch += 1;
      this.shellPaused = true;
      this.stopSelectionPolling();
    }
    this.shellResumeRequested = true;
    this.scheduleShellResume();
  }

  private async runStartFromToolbar(): Promise<void> {
    if (!this.canStart()) {
      this.shell.showToast('当前页面暂不可审查元素。');
      return;
    }
    this.clearCloseTimer();
    const facts = this.shell.resolveFacts();
    this.sessionGeneration += 1;
    this.operationSequence += 1;
    this.runtimeRevision = 0;
    this.selectionInFlight = false;
    this.shellPaused = false;
    const generation = this.sessionGeneration;
    this.originTabId = facts.activeTabId;
    this.documentToken = `${generation}:${Date.now()}`;
    this.presentSurface(generation);
    this.publish({
      active: true,
      phase: 'starting',
      busy: true,
      helperText: '正在准备元素审查…',
      pickerArmed: true,
      outline: [],
      computed: [],
      logs: [],
      network: [],
      sources: [],
      listeners: []
    });
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        this.originTabId,
        this.runtimeScriptService.buildInstallScript(generation, this.documentToken, facts.highlightColor),
        'element_inspection_runtime_not_live'
      );
      if (this.shellPaused || !this.isCurrentGeneration(generation)) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      if (!this.applyRuntimeSnapshot(snapshot, generation)) {
        this.close('install_snapshot_invalid');
        this.shell.showToast('当前页面无法启动元素审查。');
        return;
      }
      if (!this.shellPaused && (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected')) {
        this.startSelectionPolling();
      }
    } catch (_error) {
      if (this.shellPaused || !this.isCurrentGeneration(generation)) {
        return;
      }
      this.close('install_failed');
      this.shell.showToast('当前页面无法启动元素审查。');
    }
  }

  private async runShellResume(shellEpoch: number): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    const facts = this.shell.resolveFacts();
    if (!this.canResumeShell(facts, tabId)) {
      this.finishShellResume('shell_resume_unavailable', '当前页面已变化，元素审查已结束。');
      return;
    }
    if (this.reattachRequested) {
      await this.runDocumentReattach();
      return;
    }
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildReadSnapshotScript(generation, documentToken, this.runtimeRevision),
        'element_inspection_runtime_not_live'
      );
      if (!this.presentation.active || this.sessionGeneration !== generation ||
        !this.shellPaused || this.shellLifecycleEpoch !== shellEpoch ||
        this.originTabId !== tabId || this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      const hydratedSnapshot = await this.hydrateRuntimeSnapshotHtml(snapshot, tabId, generation, documentToken);
      if (hydratedSnapshot === undefined) {
        this.shellResumeRequested = true;
        this.scheduleShellResumeRetry();
        return;
      }
      if (!this.applyRuntimeSnapshot(hydratedSnapshot, generation)) {
        this.finishShellResume('shell_resume_snapshot_invalid', '页面已变化，元素审查已结束。');
        return;
      }
      this.shellPaused = false;
      this.presentSurface(generation);
      if (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected') {
        this.startSelectionPolling();
      }
    } catch (_error) {
      if (this.presentation.active && this.sessionGeneration === generation && this.shellPaused &&
        this.shellLifecycleEpoch === shellEpoch) {
        this.shellResumeRequested = true;
        this.scheduleShellResumeRetry();
      }
    }
  }

  private scheduleShellResume(): void {
    if (!this.presentation.active || !this.shellPaused || !this.shellResumeRequested ||
      this.shellResumeInFlight || this.shellResumeRetryTimer >= 0) {
      return;
    }
    const facts = this.shell.resolveFacts();
    if (facts.activeTabId.trim().length > 0 && facts.activeTabId !== this.originTabId) {
      this.finishShellResume('shell_resume_unavailable', '当前页面已变化，元素审查已结束。');
      return;
    }
    if (facts.activeTabId.trim().length === 0 || facts.showHomePage || facts.showTabsSheet ||
      !facts.webPageVisible || !this.runtimeLifecyclePort.hasLiveRuntimeController(this.originTabId)) {
      this.scheduleShellResumeRetry();
      return;
    }
    this.shellResumeRequested = false;
    this.clearShellResumeRetry();
    this.shellResumeRetryCount = 0;
    this.shellResumeInFlight = true;
    const shellEpoch = this.shellLifecycleEpoch;
    void this.runShellResume(shellEpoch).finally(() => {
      this.shellResumeInFlight = false;
      if (this.presentation.active && this.shellPaused && this.shellResumeRequested) {
        this.scheduleShellResume();
      }
    });
  }

  private scheduleShellResumeRetry(): void {
    if (!this.presentation.active || !this.shellPaused || !this.shellResumeRequested ||
      this.shellResumeRetryTimer >= 0) {
      return;
    }
    if (this.shellResumeRetryCount >= ELEMENT_INSPECTION_SHELL_RESUME_MAX_RETRIES) {
      this.finishShellResume('shell_resume_timeout', '页面已变化，元素审查已结束。');
      return;
    }
    this.shellResumeRetryCount += 1;
    this.shellResumeRetryTimer = setTimeout(() => {
      this.shellResumeRetryTimer = -1;
      this.scheduleShellResume();
    }, ELEMENT_INSPECTION_SHELL_RESUME_RETRY_DELAY_MS);
  }

  private clearShellResumeRetry(): void {
    if (this.shellResumeRetryTimer >= 0) {
      clearTimeout(this.shellResumeRetryTimer);
      this.shellResumeRetryTimer = -1;
    }
  }

  private canResumeShell(facts: ElementInspectionSessionFacts, tabId: string): boolean {
    return facts.activeTabId === tabId &&
      !facts.showHomePage &&
      !facts.showTabsSheet &&
      facts.webPageVisible &&
      this.runtimeLifecyclePort.hasLiveRuntimeController(tabId);
  }

  private finishShellResume(reason: string, message: string): void {
    this.shellPaused = false;
    this.shellResumeRequested = false;
    this.clearShellResumeRetry();
    this.shellResumeRetryCount = 0;
    this.close(reason, true);
    this.shell.showToast(message);
  }

  private async runReselect(): Promise<void> {
    if (!this.canRunNodeCommand()) {
      return;
    }
    const operation = this.beginOperation('正在等待重新选择…');
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        operation.tabId,
        this.runtimeScriptService.buildReselectScript(operation.generation, operation.documentToken),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentOperation(operation)) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      if (snapshot.revision <= operation.runtimeRevision ||
        !this.applyRuntimeSnapshot(snapshot, operation.generation)) {
        this.restoreInspectedAfterOperation();
        this.shell.showToast('无法重新选择元素。');
        return;
      }
      this.startSelectionPolling();
    } catch (_error) {
      if (this.isCurrentOperation(operation)) {
        this.restoreInspectedAfterOperation();
        this.shell.showToast('无法重新选择元素。');
      }
    }
  }

  private async runSelectAtNormalizedPoint(normalizedX: number, normalizedY: number): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    this.selectionInFlight = true;
    this.stopSelectionPolling();
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildSelectAtNormalizedPointScript(
          generation,
          documentToken,
          normalizedX,
          normalizedY
        ),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
        this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      const hydratedSnapshot = await this.hydrateRuntimeSnapshotHtml(
        snapshot,
        tabId,
        generation,
        documentToken
      );
      if (hydratedSnapshot === undefined || !this.applyRuntimeSnapshot(hydratedSnapshot, generation)) {
        this.shell.showToast('无法选择当前元素。');
      }
    } catch (_error) {
      if (this.isCurrentGeneration(generation)) {
        this.shell.showToast('无法选择当前元素。');
      }
    } finally {
      this.selectionInFlight = false;
      if (!this.shellPaused && this.isCurrentGeneration(generation) &&
        (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected')) {
        this.startSelectionPolling();
      }
    }
  }

  private async runSelectOutline(path: string): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    const previousRevision = this.runtimeRevision;
    this.selectionInFlight = true;
    this.stopSelectionPolling();
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildSelectOutlineScript(generation, documentToken, path),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
        this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      const hydratedSnapshot = await this.hydrateRuntimeSnapshotHtml(
        snapshot,
        tabId,
        generation,
        documentToken
      );
      if (hydratedSnapshot === undefined || hydratedSnapshot.revision <= previousRevision ||
        !this.applyRuntimeSnapshot(hydratedSnapshot, generation)) {
        this.shell.showToast('无法选择当前元素。');
      }
    } catch (_error) {
      if (this.isCurrentGeneration(generation)) {
        this.shell.showToast('无法选择当前元素。');
      }
    } finally {
      this.selectionInFlight = false;
      if (!this.shellPaused && this.isCurrentGeneration(generation) &&
        (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected')) {
        this.startSelectionPolling();
      }
      this.flushQueuedOutlineCommand();
    }
  }

  private async runNavigation(relation: ElementInspectionNavigationRelation): Promise<void> {
    if (!this.canRunNodeCommand()) {
      return;
    }
    const operation = this.beginOperation('正在切换元素…');
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        operation.tabId,
        this.runtimeScriptService.buildNavigateScript(
          operation.generation,
          operation.documentToken,
          relation
        ),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentOperation(operation)) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      const hydratedSnapshot = await this.hydrateRuntimeSnapshotHtml(
        snapshot,
        operation.tabId,
        operation.generation,
        operation.documentToken
      );
      if (hydratedSnapshot === undefined) {
        this.restoreInspectedAfterOperation();
        this.startSelectionPolling();
        return;
      }
      if (hydratedSnapshot.revision <= operation.runtimeRevision ||
        !this.applyRuntimeSnapshot(hydratedSnapshot, operation.generation)) {
        this.restoreInspectedAfterOperation();
        this.shell.showToast('无法切换到该元素。');
        return;
      }
      if (snapshot.mode === 'selecting') {
        this.startSelectionPolling();
      }
    } catch (_error) {
      if (this.isCurrentOperation(operation)) {
        this.restoreInspectedAfterOperation();
        this.shell.showToast('无法切换到该元素。');
      }
    }
  }

  private async copySelector(): Promise<void> {
    if (!this.canRunNodeCommand()) {
      return;
    }
    const selector = this.presentation.node?.selector ?? '';
    const operation = this.beginOperation('正在复制选择器…');
    try {
      const result: BrowserClipboardCopyResult = await this.clipboardService.copyText({
        value: selector,
        emptyMessage: '当前元素没有可复制的选择器。',
        successMessage: '选择器已复制。'
      });
      if (!this.isCurrentOperation(operation)) {
        return;
      }
      this.restoreInspectedAfterOperation();
      this.shell.showToast(result.message);
    } catch (_error) {
      if (this.isCurrentOperation(operation)) {
        this.restoreInspectedAfterOperation();
        this.shell.showToast('复制选择器失败，请稍后重试。');
      }
    }
  }

  private async copyHtml(): Promise<void> {
    if (!this.canRunNodeCommand()) {
      return;
    }
    const html = this.presentation.node?.htmlPreview ?? '';
    const operation = this.beginOperation('正在准备 HTML…');
    try {
      const clipboardResult: BrowserClipboardCopyResult = await this.clipboardService.copyText({
        value: html,
        emptyMessage: '当前元素没有可复制的 HTML。',
        successMessage: 'HTML 已复制。'
      });
      if (!this.isCurrentOperation(operation)) {
        return;
      }
      this.restoreInspectedAfterOperation();
      this.shell.showToast(clipboardResult.message);
    } catch (_error) {
      if (this.isCurrentOperation(operation)) {
        this.restoreInspectedAfterOperation();
        this.shell.showToast('复制 HTML 失败，请稍后重试。');
      }
    }
  }

  private beginOperation(helperText: string): ElementInspectionOperationContext {
    this.operationSequence += 1;
    const context: ElementInspectionOperationContext = {
      generation: this.sessionGeneration,
      sequence: this.operationSequence,
      tabId: this.originTabId,
      documentToken: this.documentToken,
      runtimeRevision: this.runtimeRevision
    };
    this.publish({
      active: true,
      phase: this.presentation.phase,
      busy: true,
      helperText: helperText,
      pickerArmed: this.presentation.pickerArmed,
      outline: this.presentation.outline,
      computed: this.presentation.computed,
      logs: this.presentation.logs,
      network: this.presentation.network,
      sources: this.presentation.sources,
      listeners: this.presentation.listeners,
      pageInfo: this.presentation.pageInfo,
      sourcePreview: this.presentation.sourcePreview,
      node: this.presentation.node,
      box: this.presentation.box
    });
    return context;
  }

  private startSelectionPolling(): void {
    if (this.shellPaused) {
      return;
    }
    this.stopSelectionPolling();
    this.pollInFlight = false;
    void this.pollSelection();
    this.pollTimer = setInterval(() => {
      void this.pollSelection();
    }, ELEMENT_INSPECTION_POLL_INTERVAL_MS);
  }

  private async pollSelection(): Promise<void> {
    if (this.pollInFlight || this.shellPaused || !this.presentation.active || this.presentation.busy ||
      (this.presentation.phase !== 'selecting' && this.presentation.phase !== 'inspected')) {
      return;
    }
    const pollEpoch = this.pollEpoch;
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    this.pollInFlight = true;
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildReadSnapshotScript(generation, documentToken, this.runtimeRevision),
        'element_inspection_runtime_not_live'
      );
      if (pollEpoch !== this.pollEpoch || this.shellPaused ||
        !this.isCurrentGeneration(generation) || this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      if (this.presentation.busy || snapshot.revision < this.runtimeRevision) {
        return;
      }
      const hydratedSnapshot = await this.hydrateRuntimeSnapshotHtml(snapshot, tabId, generation, documentToken);
      if (hydratedSnapshot === undefined || this.presentation.busy) {
        return;
      }
      if (!this.applyRuntimeSnapshot(hydratedSnapshot, generation)) {
        this.close('poll_snapshot_invalid');
        this.shell.showToast('页面已变化，元素审查已结束。');
      }
    } catch (_error) {
      if (pollEpoch === this.pollEpoch && !this.shellPaused && this.isCurrentGeneration(generation)) {
        this.close('poll_failed');
        this.shell.showToast('页面已变化，元素审查已结束。');
      }
    } finally {
      if (pollEpoch === this.pollEpoch && this.sessionGeneration === generation) {
        this.pollInFlight = false;
      }
    }
  }

  private async hydrateRuntimeSnapshotHtml(
    snapshot: ElementInspectionRuntimeSnapshot,
    tabId: string,
    generation: number,
    documentToken: string
  ): Promise<ElementInspectionRuntimeSnapshot | undefined> {
    const node = snapshot.node;
    if (!snapshot.ok || node === undefined) {
      return snapshot;
    }
    if (node.htmlPreview.length > node.htmlLength) {
      throw new Error('element_inspection_html_length_invalid');
    }
    let html = node.htmlPreview;
    while (html.length < node.htmlLength) {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildReadHtmlChunkScript(
          generation,
          documentToken,
          snapshot.revision,
          html.length
        ),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
        this.documentToken !== documentToken) {
        return undefined;
      }
      const chunk = this.runtimeScriptService.parseHtmlChunkResult(raw);
      if (!chunk.ok && chunk.reason === 'stale_revision') {
        return undefined;
      }
      if (!chunk.ok || chunk.sessionGeneration !== generation || chunk.documentToken !== documentToken ||
        chunk.revision !== snapshot.revision || chunk.offset !== html.length ||
        chunk.totalLength !== node.htmlLength || chunk.value.length === 0 ||
        html.length + chunk.value.length > node.htmlLength) {
        throw new Error('element_inspection_html_chunk_invalid');
      }
      html += chunk.value;
    }
    node.htmlPreview = html;
    return snapshot;
  }

  private applyRuntimeSnapshot(snapshot: ElementInspectionRuntimeSnapshot, expectedGeneration: number): boolean {
    if (!snapshot.ok || snapshot.sessionGeneration !== expectedGeneration ||
      snapshot.documentToken !== this.documentToken || snapshot.revision < this.runtimeRevision ||
      !this.isCurrentGeneration(expectedGeneration)) {
      return false;
    }
    if (snapshot.mode === 'inspected' && snapshot.node !== undefined) {
      if (snapshot.node.htmlPreview.length !== snapshot.node.htmlLength) {
        return false;
      }
      this.runtimeRevision = snapshot.revision;
      this.publish({
        active: true,
        phase: 'inspected',
        busy: false,
        helperText: '已选中当前元素',
        pickerArmed: this.presentation.pickerArmed,
        outline: snapshot.outline !== undefined ? snapshot.outline : this.presentation.outline,
        computed: snapshot.computed !== undefined ? snapshot.computed : this.presentation.computed,
        logs: snapshot.logs !== undefined ? snapshot.logs : this.presentation.logs,
        network: snapshot.network !== undefined ? snapshot.network : this.presentation.network,
        sources: snapshot.sources !== undefined ? snapshot.sources : this.presentation.sources,
        listeners: snapshot.listeners !== undefined ? snapshot.listeners : this.presentation.listeners,
        pageInfo: snapshot.pageInfo !== undefined ? snapshot.pageInfo : this.presentation.pageInfo,
        storage: snapshot.storage !== undefined ? snapshot.storage : this.presentation.storage,
        security: snapshot.security !== undefined ? snapshot.security : this.presentation.security,
        sourcePreview: this.presentation.sourcePreview,
        node: snapshot.node,
        box: snapshot.box !== undefined ? snapshot.box : this.presentation.box
      });
      return true;
    }
    if (snapshot.mode === 'inspected' && snapshot.revision === this.runtimeRevision &&
      this.presentation.phase === 'inspected' && this.presentation.node !== undefined) {
      if (this.debugChanged(snapshot)) {
        const next = this.clonePresentation(this.presentation);
        this.applyDebugSnapshot(next, snapshot);
        this.publish(next);
      }
      return true;
    }
    this.runtimeRevision = snapshot.revision;
    this.publish({
      active: true,
      phase: 'selecting',
      busy: false,
      helperText: '点击网页上的元素查看代码',
      pickerArmed: this.presentation.pickerArmed,
      outline: snapshot.outline !== undefined ? snapshot.outline : this.presentation.outline,
      computed: [],
      logs: snapshot.logs !== undefined ? snapshot.logs : this.presentation.logs,
      network: snapshot.network !== undefined ? snapshot.network : this.presentation.network,
      sources: snapshot.sources !== undefined ? snapshot.sources : this.presentation.sources,
      listeners: snapshot.listeners !== undefined ? snapshot.listeners : [],
      pageInfo: snapshot.pageInfo !== undefined ? snapshot.pageInfo : this.presentation.pageInfo,
      storage: snapshot.storage !== undefined ? snapshot.storage : this.presentation.storage,
      security: snapshot.security !== undefined ? snapshot.security : this.presentation.security,
      sourcePreview: this.presentation.sourcePreview
    });
    return true;
  }

  private restoreInspectedAfterOperation(): void {
    if (!this.presentation.active) {
      return;
    }
    this.publish({
      active: true,
      phase: this.presentation.node === undefined ? 'selecting' : 'inspected',
      busy: false,
      helperText: this.presentation.node === undefined ? '点击网页上的元素查看代码' : '已选中当前元素',
      pickerArmed: this.presentation.pickerArmed,
      outline: this.presentation.outline,
      computed: this.presentation.computed,
      logs: this.presentation.logs,
      network: this.presentation.network,
      sources: this.presentation.sources,
      listeners: this.presentation.listeners,
      pageInfo: this.presentation.pageInfo,
      sourcePreview: this.presentation.sourcePreview,
      node: this.presentation.node,
      box: this.presentation.box
    });
  }

  private presentSurface(generation: number): void {
    this.transientSurfaceCoordinator.present({
      id: 'element_inspection',
      revealDelayMs: ELEMENT_INSPECTION_REVEAL_DELAY_MS,
      dismissDurationMs: ELEMENT_INSPECTION_DISMISS_DURATION_MS,
      shouldReveal: (): boolean => this.isCurrentGeneration(generation)
    });
  }

  private close(_reason: string, immediate: boolean = false): void {
    if (!this.presentation.active) {
      return;
    }
    this.shellPaused = false;
    this.shellResumeRequested = false;
    this.clearShellResumeRetry();
    this.shellResumeRetryCount = 0;
    this.reattachRequested = false;
    this.clearReattachTimer();
    if (this.presentation.phase === 'closing') {
      if (immediate) {
        this.clearCloseTimer();
        this.transientSurfaceCoordinator.reset('element_inspection');
        this.finishClose(this.sessionGeneration);
      }
      return;
    }
    const cleanupGeneration = this.sessionGeneration;
    const cleanupTabId = this.originTabId;
    const cleanupDocumentToken = this.documentToken;
    this.sessionGeneration += 1;
    this.operationSequence += 1;
    const closingGeneration = this.sessionGeneration;
    this.cancelHoverTracking();
    this.stopSelectionPolling();
    this.clearCloseTimer();
    this.publish({
      active: true,
      phase: 'closing',
      busy: true,
      helperText: '正在结束元素审查…',
      pickerArmed: this.presentation.pickerArmed,
      outline: this.presentation.outline,
      computed: this.presentation.computed,
      logs: this.presentation.logs,
      network: this.presentation.network,
      sources: this.presentation.sources,
      listeners: this.presentation.listeners,
      pageInfo: this.presentation.pageInfo,
      sourcePreview: this.presentation.sourcePreview,
      node: this.presentation.node,
      box: this.presentation.box
    });
    if (cleanupTabId.length > 0 && cleanupDocumentToken.length > 0) {
      void this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        cleanupTabId,
        this.runtimeScriptService.buildStopScript(cleanupGeneration, cleanupDocumentToken),
        'element_inspection_runtime_not_live'
      ).catch((_error: Error): void => {});
    }
    if (immediate) {
      this.transientSurfaceCoordinator.reset('element_inspection');
      this.finishClose(closingGeneration);
      return;
    }
    this.transientSurfaceCoordinator.dismiss('element_inspection');
    this.closeTimer = setTimeout(() => {
      this.closeTimer = -1;
      this.finishClose(closingGeneration);
    }, ELEMENT_INSPECTION_DISMISS_DURATION_MS);
  }

  private finishClose(expectedGeneration: number): void {
    if (this.sessionGeneration !== expectedGeneration) {
      return;
    }
    this.originTabId = '';
    this.documentToken = '';
    this.runtimeRevision = 0;
    this.selectionInFlight = false;
    this.shellPaused = false;
    this.shellResumeRequested = false;
    this.clearShellResumeRetry();
    this.shellResumeRetryCount = 0;
    this.reattachRequested = false;
    this.clearReattachTimer();
    this.publish(this.buildInactivePresentation());
  }

  private beginDocumentReattach(): void {
    this.cancelHoverTracking();
    this.stopSelectionPolling();
    this.clearReattachTimer();
    this.sessionGeneration += 1;
    this.operationSequence += 1;
    this.runtimeRevision = 0;
    this.documentToken = `${this.sessionGeneration}:${Date.now()}`;
    this.selectionInFlight = false;
    this.reattachRequested = true;
    this.reattachInFlightGeneration = 0;
    this.presentation.outlineDraft = undefined;
    this.publish({
      active: true,
      phase: 'starting',
      busy: true,
      helperText: '网页正在刷新，审查会继续。',
      pickerArmed: this.presentation.pickerArmed,
      outline: [],
      computed: [],
      logs: [],
      network: [],
      sources: [],
      listeners: [],
      pageInfo: undefined,
      storage: { local: [], session: [], cookies: [], databases: [] },
      security: {
        secure: false,
        protocol: '',
        origin: '',
        url: '',
        mixedUrls: [],
        certificateError: false
      },
      sourcePreview: undefined,
      node: undefined,
      box: undefined
    });
    this.scheduleDocumentReattach();
  }

  private scheduleDocumentReattach(): void {
    if (!this.presentation.active || !this.reattachRequested || this.presentation.phase === 'closing' ||
      this.reattachTimer >= 0 || this.reattachInFlightGeneration === this.sessionGeneration) {
      return;
    }
    const facts = this.shell.resolveFacts();
    if (facts.activeTabId.trim().length > 0 && facts.activeTabId !== this.originTabId) {
      this.reattachRequested = false;
      this.close('reattach_tab_changed', true);
      return;
    }
    if (!this.canResumeShell(facts, this.originTabId)) {
      this.reattachTimer = setTimeout(() => {
        this.reattachTimer = -1;
        this.scheduleDocumentReattach();
      }, ELEMENT_INSPECTION_REATTACH_RETRY_DELAY_MS);
      return;
    }
    void this.runDocumentReattach();
  }

  private async runDocumentReattach(): Promise<void> {
    const generation = this.sessionGeneration;
    if (this.reattachInFlightGeneration === generation) {
      return;
    }
    this.reattachInFlightGeneration = generation;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    const facts = this.shell.resolveFacts();
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildInstallScript(generation, documentToken, facts.highlightColor),
        'element_inspection_runtime_not_live'
      );
      if (!this.reattachRequested || !this.isCurrentGeneration(generation) ||
        this.originTabId !== tabId || this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      if (!this.applyRuntimeSnapshot(snapshot, generation)) {
        this.scheduleReattachRetry(generation);
        return;
      }
      this.reattachRequested = false;
      if (this.shellPaused) {
        this.shellResumeRequested = true;
        return;
      }
      if (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected') {
        this.startSelectionPolling();
      }
    } catch (_error) {
      this.scheduleReattachRetry(generation);
    } finally {
      if (this.reattachInFlightGeneration === generation) {
        this.reattachInFlightGeneration = 0;
      }
    }
  }

  private scheduleReattachRetry(generation: number): void {
    if (!this.reattachRequested || !this.isCurrentGeneration(generation) || this.reattachTimer >= 0) {
      return;
    }
    this.reattachTimer = setTimeout(() => {
      this.reattachTimer = -1;
      this.scheduleDocumentReattach();
    }, ELEMENT_INSPECTION_REATTACH_RETRY_DELAY_MS);
  }

  private clearReattachTimer(): void {
    if (this.reattachTimer >= 0) {
      clearTimeout(this.reattachTimer);
      this.reattachTimer = -1;
    }
  }

  private stopSelectionPolling(): void {
    this.pollEpoch += 1;
    this.pollInFlight = false;
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private clearCloseTimer(): void {
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }

  private canRunNodeCommand(): boolean {
    return this.presentation.active &&
      this.presentation.phase === 'inspected' &&
      !this.presentation.busy &&
      this.presentation.node !== undefined;
  }

  private isCurrentGeneration(generation: number): boolean {
    return this.presentation.active && this.sessionGeneration === generation;
  }

  private isCurrentOperation(operation: ElementInspectionOperationContext): boolean {
    return this.isCurrentGeneration(operation.generation) &&
      this.operationSequence === operation.sequence &&
      this.originTabId === operation.tabId &&
      this.documentToken === operation.documentToken &&
      this.runtimeRevision === operation.runtimeRevision;
  }

  private publish(presentation: ElementInspectionPresentation): void {
    const next = this.clonePresentation(presentation);
    if (next.outlineDraft === undefined && next.active && this.presentation.outlineDraft !== undefined) {
      next.outlineDraft = this.cloneOutlineDraft(this.presentation.outlineDraft);
    }
    if (next.storage === undefined && next.active && this.presentation.storage !== undefined) {
      next.storage = this.cloneStorage(this.presentation.storage);
    }
    if (next.security === undefined && next.active && this.presentation.security !== undefined) {
      next.security = this.cloneSecurity(this.presentation.security);
    }
    if (next.security !== undefined) {
      next.security = this.overlayCertificate(next.security);
    }
    this.presentation = next;
    this.shell.publishPresentation(this.clonePresentation(next));
  }

  private clonePresentation(presentation: ElementInspectionPresentation): ElementInspectionPresentation {
    const result: ElementInspectionPresentation = {
      active: presentation.active,
      phase: presentation.phase,
      busy: presentation.busy,
      helperText: presentation.helperText,
      pickerArmed: presentation.pickerArmed === true,
      outline: this.cloneOutline(presentation.outline),
      computed: this.cloneComputed(presentation.computed),
      logs: this.cloneLogs(presentation.logs),
      network: this.cloneNetwork(presentation.network),
      sources: this.cloneSources(presentation.sources),
      listeners: this.cloneListeners(presentation.listeners),
      pageInfo: presentation.pageInfo,
      sourcePreview: presentation.sourcePreview
    };
    if (presentation.storage !== undefined) {
      result.storage = this.cloneStorage(presentation.storage);
    }
    if (presentation.security !== undefined) {
      result.security = this.cloneSecurity(presentation.security);
    }
    if (presentation.outlineDraft !== undefined) {
      result.outlineDraft = this.cloneOutlineDraft(presentation.outlineDraft);
    }
    if (presentation.node !== undefined) {
      result.node = this.cloneNode(presentation.node);
    }
    if (presentation.box !== undefined) {
      result.box = this.cloneBox(presentation.box);
    }
    return result;
  }

  private cloneOutline(nodes: ElementInspectionOutlineNode[] | undefined): ElementInspectionOutlineNode[] {
    const result: ElementInspectionOutlineNode[] = [];
    (nodes ?? []).forEach((node: ElementInspectionOutlineNode): void => {
      result.push({
        path: node.path,
        depth: node.depth,
        tagName: node.tagName,
        elementId: node.elementId,
        classTokens: node.classTokens.slice(0),
        textPreview: node.textPreview,
        childCount: node.childCount,
        selected: node.selected,
        hidden: node.hidden === true,
        expanded: node.expanded === true,
        closing: node.closing === true,
        rowKind: node.rowKind === 'close' || node.rowKind === 'more' ? node.rowKind : 'element',
        moreCount: node.moreCount !== undefined ? node.moreCount : 0,
        moreDirection: node.moreDirection === 'before' ? 'before' : 'after',
        moreStart: node.moreStart !== undefined ? node.moreStart : 0
      });
    });
    return result;
  }

  private cloneOutlineDraft(draft: ElementInspectionOutlineDraft): ElementInspectionOutlineDraft {
    return {
      requestId: draft.requestId,
      path: draft.path,
      kind: draft.kind,
      text: draft.text,
      ready: draft.ready,
      reason: draft.reason
    };
  }

  private cloneComputed(
    properties: ElementInspectionComputedProperty[] | undefined
  ): ElementInspectionComputedProperty[] {
    const result: ElementInspectionComputedProperty[] = [];
    (properties ?? []).forEach((property: ElementInspectionComputedProperty): void => {
      result.push({ name: property.name, value: property.value });
    });
    return result;
  }

  private cloneBox(box: ElementInspectionBoxModel): ElementInspectionBoxModel {
    return {
      marginTop: box.marginTop,
      marginRight: box.marginRight,
      marginBottom: box.marginBottom,
      marginLeft: box.marginLeft,
      borderTop: box.borderTop,
      borderRight: box.borderRight,
      borderBottom: box.borderBottom,
      borderLeft: box.borderLeft,
      paddingTop: box.paddingTop,
      paddingRight: box.paddingRight,
      paddingBottom: box.paddingBottom,
      paddingLeft: box.paddingLeft,
      contentWidth: box.contentWidth,
      contentHeight: box.contentHeight
    };
  }

  private isSelectedOutlinePath(path: string): boolean {
    for (let index = 0; index < this.presentation.outline.length; index += 1) {
      const node = this.presentation.outline[index];
      if (node.selected && node.path === path) {
        return true;
      }
    }
    return false;
  }

  private cloneNode(node: ElementInspectionRuntimeNodeSnapshot): ElementInspectionRuntimeNodeSnapshot {
    return {
      tagName: node.tagName,
      elementId: node.elementId,
      classTokens: node.classTokens.slice(0),
      selector: node.selector,
      breadcrumb: node.breadcrumb.slice(0),
      attributes: node.attributes.map((attribute: ElementInspectionRuntimeAttribute): ElementInspectionRuntimeAttribute => {
        const clonedAttribute: ElementInspectionRuntimeAttribute = {
          name: attribute.name,
          value: attribute.value,
          redacted: attribute.redacted
        };
        return clonedAttribute;
      }),
      textPreview: node.textPreview,
      htmlPreview: node.htmlPreview,
      htmlLength: node.htmlLength,
      rect: {
        left: node.rect.left,
        top: node.rect.top,
        width: node.rect.width,
        height: node.rect.height
      },
      hasParent: node.hasParent,
      hasFirstChild: node.hasFirstChild,
      hasPreviousSibling: node.hasPreviousSibling,
      hasNextSibling: node.hasNextSibling
    };
  }

  private buildInactivePresentation(): ElementInspectionPresentation {
    return {
      active: false,
      phase: 'inactive',
      busy: false,
      helperText: '',
      pickerArmed: false,
      outline: [],
      computed: [],
      logs: [],
      network: [],
      sources: [],
      listeners: []
    };
  }

  private async runSetPickerArmed(armed: boolean): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    if (tabId.length === 0 || documentToken.length === 0) {
      return;
    }
    try {
      await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildSetPickerArmedScript(generation, documentToken, armed),
        'element_inspection_runtime_not_live'
      );
    } catch (_error) {
    }
  }

  private canPreviewOutline(): boolean {
    return this.presentation.active &&
      !this.presentation.busy &&
      (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected') &&
      this.originTabId.length > 0 &&
      this.documentToken.length > 0;
  }

  private async drainOutlinePreview(): Promise<void> {
    if (this.outlinePreviewInFlight) {
      return;
    }
    this.outlinePreviewInFlight = true;
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    try {
      while (this.pendingOutlinePath.length > 0 && this.isCurrentGeneration(generation)) {
        const path = this.pendingOutlinePath;
        this.pendingOutlinePath = '';
        await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
          tabId,
          this.runtimeScriptService.buildPreviewOutlineScript(generation, documentToken, path),
          'element_inspection_runtime_not_live'
        );
      }
    } catch (_error) {
    } finally {
      this.outlinePreviewInFlight = false;
      if (this.pendingOutlinePath.length > 0 && this.isCurrentGeneration(generation)) {
        void this.drainOutlinePreview();
      }
    }
  }

  private canHoverPreview(normalizedX: number, normalizedY: number): boolean {
    return Number.isFinite(normalizedX) && Number.isFinite(normalizedY) &&
      this.presentation.active && this.presentation.pickerArmed &&
      !this.presentation.busy && !this.selectionInFlight &&
      (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected') &&
      this.originTabId.length > 0 && this.documentToken.length > 0;
  }

  private cancelHoverTracking(): void {
    this.hoverEpoch += 1;
    this.pendingHoverX = -1;
    this.pendingHoverY = -1;
    this.lastHoverX = -1;
    this.lastHoverY = -1;
    if (this.hoverSelectTimer >= 0) {
      clearTimeout(this.hoverSelectTimer);
      this.hoverSelectTimer = -1;
    }
  }

  private scheduleHoverSelect(): void {
    if (this.hoverSelectTimer >= 0) {
      clearTimeout(this.hoverSelectTimer);
    }
    this.hoverSelectTimer = setTimeout((): void => {
      this.hoverSelectTimer = -1;
      void this.runHoverSelect();
    }, 80);
  }

  private async drainHoverPreview(): Promise<void> {
    if (this.hoverInFlight) {
      return;
    }
    this.hoverInFlight = true;
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    try {
      while (this.pendingHoverX >= 0 && this.pendingHoverY >= 0 &&
        this.isCurrentGeneration(generation) && this.presentation.pickerArmed) {
        const normalizedX = this.pendingHoverX;
        const normalizedY = this.pendingHoverY;
        this.pendingHoverX = -1;
        this.pendingHoverY = -1;
        await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
          tabId,
          this.runtimeScriptService.buildPreviewAtNormalizedPointScript(
            generation,
            documentToken,
            normalizedX,
            normalizedY
          ),
          'element_inspection_runtime_not_live'
        );
      }
    } catch (_error) {
    } finally {
      this.hoverInFlight = false;
      if (this.pendingHoverX >= 0 && this.isCurrentGeneration(generation) && this.presentation.pickerArmed) {
        void this.drainHoverPreview();
      }
    }
  }

  private async runHoverSelect(): Promise<void> {
    if (this.hoverSelectInFlight || this.selectionInFlight || this.lastHoverX < 0 || this.lastHoverY < 0 ||
      !this.canHoverPreview(this.lastHoverX, this.lastHoverY)) {
      return;
    }
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    const normalizedX = this.lastHoverX;
    const normalizedY = this.lastHoverY;
    const epoch = this.hoverEpoch;
    this.hoverSelectInFlight = true;
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildHoverSelectAtNormalizedPointScript(
          generation,
          documentToken,
          normalizedX,
          normalizedY
        ),
        'element_inspection_runtime_not_live'
      );
      if (epoch !== this.hoverEpoch || !this.isCurrentGeneration(generation) ||
        this.originTabId !== tabId || this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      this.applyRuntimeSnapshot(snapshot, generation);
    } catch (_error) {
    } finally {
      this.hoverSelectInFlight = false;
    }
  }

  private async runClearPreview(generation: number, tabId: string, documentToken: string): Promise<void> {
    try {
      await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildClearPreviewScript(generation, documentToken),
        'element_inspection_runtime_not_live'
      );
    } catch (_error) {
    }
  }

  private canRunOutlineCommand(): boolean {
    return this.canRunDebugCommand();
  }

  private queueOutlineCommand(command: ElementInspectionOutlineCommand): void {
    this.queuedOutlineCommand = {
      kind: command.kind,
      path: command.path,
      name: command.name,
      value: command.value,
      requestId: command.requestId,
      previousName: command.previousName !== undefined ? command.previousName : ''
    };
    this.outlineCommandQueued = true;
  }

  private flushQueuedOutlineCommand(): void {
    if (!this.outlineCommandQueued || this.outlineCommandInFlight || this.selectionInFlight) {
      return;
    }
    const command = this.queuedOutlineCommand;
    this.outlineCommandQueued = false;
    this.queuedOutlineCommand = {
      kind: '',
      path: '',
      name: '',
      value: '',
      requestId: 0
    };
    this.runOutlineCommand(command);
  }

  private outlineCommandChangesDom(kind: string): boolean {
    return kind === 'duplicate' || kind === 'delete' || kind === 'cut' || kind === 'paste' ||
      kind === 'hide' || kind === 'set_attribute' || kind === 'replace_html';
  }

  private async executeOutlineCommand(command: ElementInspectionOutlineCommand): Promise<void> {
    const mutates = this.outlineCommandChangesDom(command.kind);
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    this.outlineCommandInFlight = true;
    if (mutates) {
      this.selectionInFlight = true;
      this.stopSelectionPolling();
    }
    try {
      if (command.kind === 'cut') {
        await this.cutOutlineNode(command.path, generation, tabId, documentToken);
      } else if (command.kind === 'paste') {
        await this.pasteOutlineNode(command.path, generation, tabId, documentToken);
      } else if (command.kind === 'set_attribute') {
        await this.setOutlineAttribute(command, generation, tabId, documentToken);
      } else if (command.kind === 'read_html') {
        await this.readOutlineHtml(command, generation, tabId, documentToken);
      } else if (command.kind === 'read_attributes') {
        await this.readOutlineAttributes(command, generation, tabId, documentToken);
      } else if (command.kind === 'replace_html') {
        await this.replaceOutlineHtml(command, generation, tabId, documentToken);
      } else if (command.kind === 'toggle_outline' || command.kind === 'outline_more') {
        await this.updateOutlineTree(command, generation, tabId, documentToken);
      } else {
        await this.runSimpleOutlineCommand(command, generation, tabId, documentToken);
      }
    } catch (_error) {
      if (this.isCurrentGeneration(generation)) {
        this.shell.showToast('元素操作失败，请稍后重试。');
      }
    } finally {
      this.outlineCommandInFlight = false;
      if (mutates) {
        this.selectionInFlight = false;
        if (!this.shellPaused && this.isCurrentGeneration(generation) &&
          (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected')) {
          this.startSelectionPolling();
        }
      }
      this.flushQueuedOutlineCommand();
    }
  }

  private async cutOutlineNode(
    path: string,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    const described = await this.runPageOutlineCommand('copy_html', path, '', generation, tabId, documentToken);
    if (described === undefined) {
      return;
    }
    if (!described.ok || described.text.length === 0) {
      this.shell.showToast(this.outlineCommandFailureMessage(described.reason));
      return;
    }
    const copied = await this.clipboardService.copyText({
      value: described.text,
      emptyMessage: '当前元素没有可剪切的 HTML。',
      successMessage: '已剪切。',
      failureMessage: '剪切失败，请稍后重试。'
    });
    if (!this.isCurrentGeneration(generation)) {
      return;
    }
    if (!copied.ok) {
      this.shell.showToast(copied.message);
      return;
    }
    const deleted = await this.runPageOutlineCommand('delete', path, '', generation, tabId, documentToken);
    if (deleted === undefined) {
      return;
    }
    if (!deleted.ok) {
      this.shell.showToast('HTML 已复制，但无法删除元素。');
      return;
    }
    await this.applyContextSnapshot(deleted, generation, tabId, documentToken);
    if (this.isCurrentGeneration(generation)) {
      this.shell.showToast(described.reason === 'html_truncated' ? '已剪切，超长部分已截断。' : '已剪切。');
    }
  }

  private async pasteOutlineNode(
    path: string,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    const clipboard = await this.clipboardService.readText({
      emptyMessage: '剪贴板是空的。',
      failureMessage: '读取剪贴板失败，请稍后重试。'
    });
    if (!this.isCurrentGeneration(generation)) {
      return;
    }
    if (!clipboard.ok) {
      this.shell.showToast(clipboard.message);
      return;
    }
    const html = clipboard.value.length > 20000 ? clipboard.value.substring(0, 20000) : clipboard.value;
    const pasted = await this.runPageOutlineCommand('paste_html', path, html, generation, tabId, documentToken);
    if (pasted === undefined) {
      return;
    }
    if (!pasted.ok) {
      this.shell.showToast(this.outlineCommandFailureMessage(pasted.reason));
      return;
    }
    await this.applyContextSnapshot(pasted, generation, tabId, documentToken);
    if (this.isCurrentGeneration(generation)) {
      this.shell.showToast('已粘贴。');
    }
  }

  private async setOutlineAttribute(
    command: ElementInspectionOutlineCommand,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    const name = command.name.trim();
    const previousName = command.previousName !== undefined ? command.previousName.trim() : '';
    const value = command.value.length > 500 ? command.value.substring(0, 500) : command.value;
    if (!this.isOutlineAttributeName(name) ||
      (previousName.length > 0 && previousName !== name && !this.isOutlineAttributeName(previousName))) {
      this.shell.showToast('属性名无效。');
      return;
    }
    const payloadObject: ElementInspectionAttributePayload = { name: name, value: value };
    if (previousName.length > 0 && previousName !== name) {
      payloadObject.previousName = previousName;
    }
    const payload = JSON.stringify(payloadObject);
    const updated = await this.runPageOutlineCommand(
      'set_attribute', command.path, payload, generation, tabId, documentToken
    );
    await this.finishOutlineMutation(updated, generation, tabId, documentToken, '属性已更新。');
  }

  private async replaceOutlineHtml(
    command: ElementInspectionOutlineCommand,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    const html = command.value.trim();
    if (html.length === 0 || html.length > 12000) {
      this.shell.showToast(html.length === 0 ? 'HTML 不能为空。' : '这段 HTML 太长，暂时不能整段编辑。');
      return;
    }
    const replaced = await this.runPageOutlineCommand(
      'replace_html', command.path, html, generation, tabId, documentToken
    );
    await this.finishOutlineMutation(replaced, generation, tabId, documentToken, 'HTML 已更新。');
  }

  private async readOutlineHtml(
    command: ElementInspectionOutlineCommand,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    this.outlineReadRequestId = command.requestId;
    const result = await this.runPageOutlineCommand('read_html', command.path, '', generation, tabId, documentToken);
    if (!this.isCurrentGeneration(generation) || command.requestId !== this.outlineReadRequestId) {
      return;
    }
    const draft: ElementInspectionOutlineDraft = {
      requestId: command.requestId,
      path: command.path,
      kind: 'html',
      text: '',
      ready: false,
      reason: 'node_missing'
    };
    if (result === undefined) {
      draft.reason = 'stale';
    } else if (!result.ok) {
      draft.reason = result.reason;
      this.shell.showToast(this.outlineCommandFailureMessage(result.reason));
    } else {
      draft.ready = true;
      draft.text = result.text;
      draft.reason = result.reason;
    }
    const next = this.clonePresentation(this.presentation);
    next.outlineDraft = draft;
    this.publish(next);
  }

  private async readOutlineAttributes(
    command: ElementInspectionOutlineCommand,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    this.outlineReadRequestId = command.requestId;
    const result = await this.runPageOutlineCommand(
      'read_attributes', command.path, '', generation, tabId, documentToken
    );
    if (!this.isCurrentGeneration(generation) || command.requestId !== this.outlineReadRequestId) {
      return;
    }
    const draft: ElementInspectionOutlineDraft = {
      requestId: command.requestId,
      path: command.path,
      kind: 'attributes',
      text: '[]',
      ready: false,
      reason: 'node_missing'
    };
    if (result === undefined) {
      draft.reason = 'stale';
    } else if (!result.ok) {
      draft.reason = result.reason;
      this.shell.showToast(this.outlineCommandFailureMessage(result.reason));
    } else {
      draft.ready = true;
      draft.text = result.text.length > 0 ? result.text : '[]';
      draft.reason = result.reason;
    }
    const next = this.clonePresentation(this.presentation);
    next.outlineDraft = draft;
    this.publish(next);
  }

  private async updateOutlineTree(
    command: ElementInspectionOutlineCommand,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
      tabId,
      this.runtimeScriptService.buildOutlineTreeScript(
        generation,
        documentToken,
        command.kind,
        command.path,
        command.value
      ),
      'element_inspection_runtime_not_live'
    );
    if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
      this.documentToken !== documentToken) {
      return;
    }
    const snapshot = this.runtimeScriptService.parseSnapshot(raw);
    if (!snapshot.ok || snapshot.sessionGeneration !== generation || snapshot.documentToken !== documentToken) {
      this.shell.showToast('找不到这个元素。');
      return;
    }
    if (snapshot.outline === undefined || snapshot.revision < this.runtimeRevision) {
      return;
    }
    const next = this.clonePresentation(this.presentation);
    next.outline = snapshot.outline;
    this.publish(next);
  }

  private async runSimpleOutlineCommand(
    command: ElementInspectionOutlineCommand,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    const result = await this.runPageOutlineCommand(
      command.kind, command.path, '', generation, tabId, documentToken
    );
    if (result === undefined) {
      return;
    }
    if (!result.ok) {
      this.shell.showToast(this.outlineCommandFailureMessage(result.reason));
      return;
    }
    if (command.kind === 'copy_selector' || command.kind === 'copy_js_path' ||
      command.kind === 'copy_xpath' || command.kind === 'copy_html' || command.kind === 'copy_styles') {
      await this.copyOutlineText(command.kind, result);
      return;
    }
    if (this.outlineCommandChangesDom(command.kind) || command.kind === 'focus') {
      await this.applyContextSnapshot(result, generation, tabId, documentToken);
    }
    if (!this.isCurrentGeneration(generation)) {
      return;
    }
    const message = this.outlineCommandSuccessMessage(command.kind, result);
    if (message.length > 0) {
      this.shell.showToast(message);
    }
  }

  private async finishOutlineMutation(
    result: ElementInspectionContextActionResult | undefined,
    generation: number,
    tabId: string,
    documentToken: string,
    successMessage: string
  ): Promise<void> {
    if (result === undefined) {
      return;
    }
    if (!result.ok) {
      this.shell.showToast(this.outlineCommandFailureMessage(result.reason));
      return;
    }
    await this.applyContextSnapshot(result, generation, tabId, documentToken);
    if (this.isCurrentGeneration(generation)) {
      this.shell.showToast(successMessage);
    }
  }

  private async runPageOutlineCommand(
    kind: string,
    path: string,
    payload: string,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<ElementInspectionContextActionResult | undefined> {
    const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
      tabId,
      this.runtimeScriptService.buildOutlineCommandScript(generation, documentToken, kind, path, payload),
      'element_inspection_runtime_not_live'
    );
    if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
      this.documentToken !== documentToken) {
      return undefined;
    }
    const result = this.runtimeScriptService.parseContextActionResult(raw);
    if (result.sessionGeneration !== generation || result.documentToken !== documentToken) {
      return undefined;
    }
    return result;
  }

  private async applyContextSnapshot(
    result: ElementInspectionContextActionResult,
    generation: number,
    tabId: string,
    documentToken: string
  ): Promise<void> {
    if (!result.snapshot.ok || !this.isCurrentGeneration(generation)) {
      return;
    }
    const hydrated = await this.hydrateRuntimeSnapshotHtml(result.snapshot, tabId, generation, documentToken);
    if (hydrated === undefined || !this.isCurrentGeneration(generation)) {
      return;
    }
    this.applyRuntimeSnapshot(hydrated, generation);
  }

  private async copyOutlineText(
    kind: string,
    result: ElementInspectionContextActionResult
  ): Promise<void> {
    let successMessage = 'HTML 已复制。';
    if (kind === 'copy_selector') {
      successMessage = '选择器已复制。';
    } else if (kind === 'copy_js_path') {
      successMessage = 'JS 路径已复制。';
    } else if (kind === 'copy_xpath') {
      successMessage = 'XPath 已复制。';
    } else if (kind === 'copy_styles') {
      successMessage = result.reason === 'style_truncated' ? '样式已复制，超长部分已截断。' : '样式已复制。';
    } else if (result.reason === 'html_truncated') {
      successMessage = 'HTML 已复制，超长部分已截断。';
    }
    const copied = await this.clipboardService.copyText({
      value: result.text,
      emptyMessage: '没有可复制的内容。',
      successMessage: successMessage,
      failureMessage: '复制失败，请稍后重试。'
    });
    this.shell.showToast(copied.message);
  }

  private outlineCommandSuccessMessage(
    kind: string,
    result: ElementInspectionContextActionResult
  ): string {
    if (kind === 'copy_selector') {
      return '';
    }
    if (kind === 'copy_js_path' || kind === 'copy_xpath' || kind === 'copy_html' || kind === 'copy_styles') {
      return '';
    }
    if (kind === 'duplicate') {
      return '已在页面上创建副本。';
    }
    if (kind === 'delete') {
      return '元素已删除。';
    }
    if (kind === 'hide') {
      return result.text === 'hidden' ? '元素已隐藏。' : '元素已显示。';
    }
    if (kind === 'scroll_into_view') {
      return '已滚动到元素。';
    }
    if (kind === 'focus') {
      return '已聚焦元素。';
    }
    if (kind === 'store_global') {
      return result.text.length > 0 ? `已存为 ${result.text}，可在控制台使用。` : '已存为全局变量。';
    }
    return '';
  }

  private outlineCommandFailureMessage(reason: string): string {
    if (reason === 'node_protected') {
      return '这个元素不能这样修改。';
    }
    if (reason === 'html_too_large') {
      return '这段 HTML 太长，暂时不能整段编辑。';
    }
    if (reason === 'html_unavailable') {
      return '当前元素没有可复制的 HTML。';
    }
    if (reason === 'html_rejected') {
      return 'HTML 无法应用。请保留一个根元素。';
    }
    if (reason === 'attribute_invalid') {
      return '属性名无效。';
    }
    if (reason === 'attribute_rejected') {
      return '无法修改这个属性。';
    }
    if (reason === 'selector_unavailable') {
      return '当前元素没有可复制的路径。';
    }
    if (reason === 'styles_unavailable') {
      return '当前元素没有可复制的样式。';
    }
    if (reason === 'not_focusable') {
      return '这个元素不能聚焦。';
    }
    if (reason === 'store_failed') {
      return '无法存为全局变量。';
    }
    if (reason === 'node_missing') {
      return '找不到这个元素。';
    }
    return '元素操作失败，请稍后重试。';
  }

  private isOutlineAttributeName(value: string): boolean {
    if (value.length === 0 || value.length > 64) {
      return false;
    }
    const first = value.charCodeAt(0);
    if (!((first >= 65 && first <= 90) || (first >= 97 && first <= 122) || first === 95 || first === 58)) {
      return false;
    }
    for (let index = 1; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      const allowed = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
        (code >= 48 && code <= 57) || code === 45 || code === 95 || code === 58;
      if (!allowed) {
        return false;
      }
    }
    return true;
  }

  private canRunDebugCommand(): boolean {
    return this.presentation.active &&
      (this.presentation.phase === 'selecting' || this.presentation.phase === 'inspected') &&
      !this.presentation.busy &&
      this.originTabId.length > 0 &&
      this.documentToken.length > 0;
  }

  private async runEvaluateConsole(expression: string): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildEvaluateScript(generation, documentToken, expression),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
        this.documentToken !== documentToken) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      if (!this.applyRuntimeSnapshot(snapshot, generation)) {
        this.shell.showToast('无法执行脚本。');
      }
    } catch (_error) {
      if (this.isCurrentGeneration(generation)) {
        this.shell.showToast('无法执行脚本。');
      }
    }
  }

  private async runClearConsole(): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildClearLogsScript(generation, documentToken),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId) {
        return;
      }
      const snapshot = this.runtimeScriptService.parseSnapshot(raw);
      if (!this.applyRuntimeSnapshot(snapshot, generation)) {
        this.shell.showToast('无法清空控制台。');
      }
    } catch (_error) {
      if (this.isCurrentGeneration(generation)) {
        this.shell.showToast('无法清空控制台。');
      }
    }
  }

  private async runReadSource(sourceId: string): Promise<void> {
    const generation = this.sessionGeneration;
    const tabId = this.originTabId;
    const documentToken = this.documentToken;
    try {
      const raw: string = await this.runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        this.runtimeScriptService.buildReadSourceScript(generation, documentToken, sourceId),
        'element_inspection_runtime_not_live'
      );
      if (!this.isCurrentGeneration(generation) || this.originTabId !== tabId ||
        this.documentToken !== documentToken) {
        return;
      }
      const result = this.runtimeScriptService.parseSourceReadResult(raw);
      if (result.sessionGeneration !== generation || result.documentToken !== documentToken ||
        result.id !== sourceId) {
        this.shell.showToast('无法读取源代码。');
        return;
      }
      const next = this.clonePresentation(this.presentation);
      next.sourcePreview = {
        id: result.id,
        name: result.name,
        text: result.text,
        reason: result.reason
      };
      this.publish(next);
    } catch (_error) {
      if (this.isCurrentGeneration(generation)) {
        this.shell.showToast('无法读取源代码。');
      }
    }
  }

  private debugChanged(snapshot: ElementInspectionRuntimeSnapshot): boolean {
    const logs = snapshot.logs !== undefined ? snapshot.logs : this.presentation.logs;
    const network = snapshot.network !== undefined ? snapshot.network : this.presentation.network;
    const sources = snapshot.sources !== undefined ? snapshot.sources : this.presentation.sources;
    const listeners = snapshot.listeners !== undefined ? snapshot.listeners : this.presentation.listeners;
    return logs.length !== this.presentation.logs.length ||
      network.length !== this.presentation.network.length ||
      sources.length !== this.presentation.sources.length ||
      listeners.length !== this.presentation.listeners.length ||
      this.lastLogKey(logs) !== this.lastLogKey(this.presentation.logs) ||
      this.networkSignature(network) !== this.networkSignature(this.presentation.network) ||
      this.storageSignature(snapshot.storage) !== this.storageSignature(this.presentation.storage) ||
      this.securitySignature(snapshot.security) !== this.securitySignature(this.presentation.security);
  }

  private applyDebugSnapshot(
    presentation: ElementInspectionPresentation,
    snapshot: ElementInspectionRuntimeSnapshot
  ): void {
    if (snapshot.logs !== undefined) {
      presentation.logs = snapshot.logs;
    }
    if (snapshot.network !== undefined) {
      presentation.network = snapshot.network;
    }
    if (snapshot.sources !== undefined) {
      presentation.sources = snapshot.sources;
    }
    if (snapshot.listeners !== undefined) {
      presentation.listeners = snapshot.listeners;
    }
    if (snapshot.pageInfo !== undefined) {
      presentation.pageInfo = snapshot.pageInfo;
    }
    if (snapshot.storage !== undefined) {
      presentation.storage = snapshot.storage;
    }
    if (snapshot.security !== undefined) {
      presentation.security = snapshot.security;
    }
  }

  private lastLogKey(entries: ElementInspectionConsoleEntry[]): string {
    if (entries.length === 0) {
      return '';
    }
    const last = entries[entries.length - 1];
    return `${last.time}:${last.level}:${last.text}`;
  }

  private networkSignature(entries: ElementInspectionNetworkEntry[]): string {
    let completed = 0;
    let size = 0;
    entries.forEach((entry: ElementInspectionNetworkEntry): void => {
      if (entry.status > 0 || entry.durationMs > 0) {
        completed += 1;
      }
      size += entry.size;
      completed += entry.durationMs;
    });
    return `${entries.length}:${completed}:${size}`;
  }

  private storageSignature(storage: ElementInspectionStorageSnapshot | undefined): string {
    if (storage === undefined) {
      return '';
    }
    return `${this.storageEntryKey(storage.local)}|${this.storageEntryKey(storage.session)}|` +
      `${this.storageEntryKey(storage.cookies)}|${storage.databases.join(',')}`;
  }

  private storageEntryKey(entries: ElementInspectionStorageEntry[]): string {
    let key = `${entries.length}:`;
    entries.forEach((entry: ElementInspectionStorageEntry): void => {
      key += `${entry.name}=${entry.redacted ? 1 : 0}:${entry.value.substring(0, 24)};`;
    });
    return key;
  }

  private securitySignature(summary: ElementInspectionSecuritySummary | undefined): string {
    if (summary === undefined) {
      return '';
    }
    const pageUrl = summary.url.length > 0 ? summary.url : summary.origin;
    const certificateError = summary.certificateError || this.certificateMatches(pageUrl);
    return `${summary.secure}:${summary.protocol}:${summary.origin}:${summary.mixedUrls.join(',')}:` +
      `${certificateError}`;
  }

  private cloneLogs(entries: ElementInspectionConsoleEntry[] | undefined): ElementInspectionConsoleEntry[] {
    const result: ElementInspectionConsoleEntry[] = [];
    (entries ?? []).forEach((entry: ElementInspectionConsoleEntry): void => {
      result.push({ level: entry.level, text: entry.text, time: entry.time });
    });
    return result;
  }

  private cloneNetwork(entries: ElementInspectionNetworkEntry[] | undefined): ElementInspectionNetworkEntry[] {
    const result: ElementInspectionNetworkEntry[] = [];
    (entries ?? []).forEach((entry: ElementInspectionNetworkEntry): void => {
      result.push({
        method: entry.method,
        url: entry.url,
        status: entry.status,
        type: entry.type,
        size: entry.size,
        durationMs: entry.durationMs,
        startedAt: entry.startedAt,
        waitMs: entry.waitMs,
        downloadMs: entry.downloadMs,
        offsetMs: entry.offsetMs,
        timed: entry.timed === true
      });
    });
    return result;
  }

  private cloneStorage(storage: ElementInspectionStorageSnapshot): ElementInspectionStorageSnapshot {
    return {
      local: this.cloneStorageEntries(storage.local),
      session: this.cloneStorageEntries(storage.session),
      cookies: this.cloneStorageEntries(storage.cookies),
      databases: storage.databases.slice()
    };
  }

  private cloneStorageEntries(entries: ElementInspectionStorageEntry[]): ElementInspectionStorageEntry[] {
    const result: ElementInspectionStorageEntry[] = [];
    entries.forEach((entry: ElementInspectionStorageEntry): void => {
      result.push({ name: entry.name, value: entry.value, redacted: entry.redacted === true });
    });
    return result;
  }

  private cloneSecurity(summary: ElementInspectionSecuritySummary): ElementInspectionSecuritySummary {
    return {
      secure: summary.secure === true,
      protocol: summary.protocol,
      origin: summary.origin,
      url: summary.url,
      mixedUrls: summary.mixedUrls.slice(),
      certificateError: summary.certificateError === true
    };
  }

  private overlayCertificate(summary: ElementInspectionSecuritySummary): ElementInspectionSecuritySummary {
    const next = this.cloneSecurity(summary);
    next.certificateError = this.certificateMatches(next.url.length > 0 ? next.url : next.origin);
    return next;
  }

  private certificateMatches(pageUrl: string): boolean {
    if (this.certificateErrorTabId.length === 0 || this.certificateErrorTabId !== this.originTabId ||
      this.certificateErrorUrl.length === 0 || pageUrl.length === 0) {
      return false;
    }
    return this.sameOrigin(this.certificateErrorUrl, pageUrl);
  }

  private sameOrigin(left: string, right: string): boolean {
    const leftOrigin = this.originOf(left);
    const rightOrigin = this.originOf(right);
    return leftOrigin.length > 0 && leftOrigin === rightOrigin;
  }

  private originOf(url: string): string {
    const match = url.trim().match(/^[a-z][a-z0-9+.-]*:\/\/[^/?#]+/i);
    return match === null ? '' : match[0].toLowerCase();
  }

  private cloneSources(entries: ElementInspectionSourceEntry[] | undefined): ElementInspectionSourceEntry[] {
    const result: ElementInspectionSourceEntry[] = [];
    (entries ?? []).forEach((entry: ElementInspectionSourceEntry): void => {
      result.push({ id: entry.id, kind: entry.kind, name: entry.name, url: entry.url });
    });
    return result;
  }

  private cloneListeners(entries: ElementInspectionListenerEntry[] | undefined): ElementInspectionListenerEntry[] {
    const result: ElementInspectionListenerEntry[] = [];
    (entries ?? []).forEach((entry: ElementInspectionListenerEntry): void => {
      result.push({ type: entry.type, capture: entry.capture, source: entry.source });
    });
    return result;
  }
}

interface ElementInspectionOperationContext {
  generation: number;
  sequence: number;
  tabId: string;
  documentToken: string;
  runtimeRevision: number;
}

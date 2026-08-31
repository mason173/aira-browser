export type BrowserSearchInvocationSource =
  'desktop_card' |
  'app_shortcut' |
  'keyboard' |
  'browser_chrome' |
  'third_party_home';

export type BrowserSearchInvocationDisposition =
  'started' |
  'reinforced' |
  'replaced_pending' |
  'rejected_authority';

export type BrowserSearchInvocationPhase =
  'idle' |
  'pending_window' |
  'pending_protected_flow' |
  'routing' |
  'presenting' |
  'committed' |
  'background_suspended' |
  'ended' |
  'failed';

export type BrowserSearchInvocationScene = 'home' | 'web';
export type BrowserSearchDraftSelection = 'all' | 'preserve' | 'caret_end';
export type BrowserSearchPresentationOutcomeKind =
  'presentation_committed' |
  'superseded' |
  'rejected_authority' |
  'ended_before_commit' |
  'context_destroyed' |
  'failed';
export type BrowserSearchPresentationFailureReason =
  '' |
  'settings_exit_failed' |
  'presentation_commit_failed' |
  'context_destroyed';
export type BrowserSearchInvocationEndReason =
  'submitted' |
  'explicit_exit' |
  'other_surface_selected' |
  'active_context_changed' |
  'context_destroyed';

export class BrowserSearchSceneSnapshot {
  readonly scene: BrowserSearchInvocationScene;
  readonly valid: boolean;
  readonly draft: string;
  readonly selection: BrowserSearchDraftSelection;

  constructor(
    scene: BrowserSearchInvocationScene,
    valid: boolean,
    draft: string,
    selection: BrowserSearchDraftSelection
  ) {
    this.scene = scene;
    this.valid = valid;
    this.draft = draft;
    this.selection = selection;
  }
}

export class BrowserSearchPresentationRequest {
  readonly sessionId: string;
  readonly authorityId: string;
  readonly presentationAttempt: number;
  readonly scene: BrowserSearchInvocationScene;
  readonly draft: string;
  readonly selection: BrowserSearchDraftSelection;
  readonly reinforced: boolean;

  constructor(
    sessionId: string,
    authorityId: string,
    presentationAttempt: number,
    scene: BrowserSearchInvocationScene,
    draft: string,
    selection: BrowserSearchDraftSelection,
    reinforced: boolean
  ) {
    this.sessionId = sessionId;
    this.authorityId = authorityId;
    this.presentationAttempt = presentationAttempt;
    this.scene = scene;
    this.draft = draft;
    this.selection = selection;
    this.reinforced = reinforced;
  }
}

export type BrowserSearchPresentationCommitKind = 'committed' | 'pending' | 'failed';

export class BrowserSearchPresentationCommitResult {
  readonly kind: BrowserSearchPresentationCommitKind;
  readonly failureReason: BrowserSearchPresentationFailureReason;

  constructor(
    kind: BrowserSearchPresentationCommitKind,
    failureReason: BrowserSearchPresentationFailureReason = ''
  ) {
    this.kind = kind;
    this.failureReason = failureReason;
  }
}

export class BrowserSearchPresentationOutcome {
  readonly kind: BrowserSearchPresentationOutcomeKind;
  readonly sessionId: string;
  readonly authorityId: string;
  readonly scene: BrowserSearchInvocationScene | undefined;
  readonly degradedReason: string;
  readonly failureReason: BrowserSearchPresentationFailureReason;

  constructor(
    kind: BrowserSearchPresentationOutcomeKind,
    sessionId: string,
    authorityId: string,
    scene: BrowserSearchInvocationScene | undefined = undefined,
    degradedReason: string = '',
    failureReason: BrowserSearchPresentationFailureReason = ''
  ) {
    this.kind = kind;
    this.sessionId = sessionId;
    this.authorityId = authorityId;
    this.scene = scene;
    this.degradedReason = degradedReason;
    this.failureReason = failureReason;
  }
}

export class BrowserSearchInvocationReceipt {
  readonly sessionId: string;
  readonly authorityId: string;
  readonly disposition: BrowserSearchInvocationDisposition;
  readonly presentation: Promise<BrowserSearchPresentationOutcome>;

  constructor(
    sessionId: string,
    authorityId: string,
    disposition: BrowserSearchInvocationDisposition,
    presentation: Promise<BrowserSearchPresentationOutcome>
  ) {
    this.sessionId = sessionId;
    this.authorityId = authorityId;
    this.disposition = disposition;
    this.presentation = presentation;
  }
}

export class BrowserSearchInvocationSnapshot {
  readonly sessionId: string;
  readonly authorityId: string;
  readonly authorityEpoch: number;
  readonly presentationAttempt: number;
  readonly phase: BrowserSearchInvocationPhase;
  readonly source: BrowserSearchInvocationSource | undefined;
  readonly scene: BrowserSearchInvocationScene | undefined;
  readonly draft: string;
  readonly backgrounded: boolean;
  readonly pendingReason: string;

  constructor(
    sessionId: string,
    authorityId: string,
    authorityEpoch: number,
    presentationAttempt: number,
    phase: BrowserSearchInvocationPhase,
    source: BrowserSearchInvocationSource | undefined,
    scene: BrowserSearchInvocationScene | undefined,
    draft: string,
    backgrounded: boolean,
    pendingReason: string
  ) {
    this.sessionId = sessionId;
    this.authorityId = authorityId;
    this.authorityEpoch = authorityEpoch;
    this.presentationAttempt = presentationAttempt;
    this.phase = phase;
    this.source = source;
    this.scene = scene;
    this.draft = draft;
    this.backgrounded = backgrounded;
    this.pendingReason = pendingReason;
  }
}

export interface BrowserSearchInvocationSettingsAdapter {
  requestExit: (authorityId: string) => Promise<boolean>;
  notifyBrowserSurfaceReady: () => void;
}

export interface BrowserSearchInvocationSurfaceAdapter {
  resolveScene: () => BrowserSearchSceneSnapshot;
  present: (request: BrowserSearchPresentationRequest) => Promise<BrowserSearchPresentationCommitResult>;
  suspend: (authorityId: string) => void;
  end: (authorityId: string, reason: BrowserSearchInvocationEndReason) => void;
}

class BrowserSearchPresentationDeferred {
  readonly promise: Promise<BrowserSearchPresentationOutcome>;
  private resolver: ((outcome: BrowserSearchPresentationOutcome) => void) | undefined = undefined;
  private resolved: boolean = false;

  constructor() {
    this.promise = new Promise<BrowserSearchPresentationOutcome>((resolve) => {
      this.resolver = resolve;
    });
  }

  resolve(outcome: BrowserSearchPresentationOutcome): void {
    if (this.resolved || this.resolver === undefined) {
      return;
    }
    this.resolved = true;
    this.resolver(outcome);
    this.resolver = undefined;
  }
}

export class BrowserSearchInvocationSessionCoordinator {
  private settingsAdapter: BrowserSearchInvocationSettingsAdapter | undefined = undefined;
  private surfaceAdapter: BrowserSearchInvocationSurfaceAdapter | undefined = undefined;
  private sessionSerial: number = 0;
  private authorityEpoch: number = 0;
  private presentationAttempt: number = 0;
  private sessionId: string = '';
  private authorityId: string = '';
  private phase: BrowserSearchInvocationPhase = 'idle';
  private source: BrowserSearchInvocationSource | undefined = undefined;
  private scene: BrowserSearchInvocationScene | undefined = undefined;
  private draft: string = '';
  private draftSelection: BrowserSearchDraftSelection = 'caret_end';
  private currentActiveContextId: string = '';
  private currentActiveContextKnown: boolean = false;
  private sessionActiveContextId: string = '';
  private sessionActiveContextKnown: boolean = false;
  private backgrounded: boolean = false;
  private pendingReason: string = '';
  private activeDeferred: BrowserSearchPresentationDeferred | undefined = undefined;

  registerSettingsAdapter(adapter: BrowserSearchInvocationSettingsAdapter): void {
    this.settingsAdapter = adapter;
    this.resumePendingPresentation();
  }

  unregisterSettingsAdapter(adapter: BrowserSearchInvocationSettingsAdapter): void {
    if (this.settingsAdapter === adapter) {
      this.settingsAdapter = undefined;
    }
  }

  registerSurfaceAdapter(adapter: BrowserSearchInvocationSurfaceAdapter): void {
    this.surfaceAdapter = adapter;
    this.settingsAdapter?.notifyBrowserSurfaceReady();
    this.resumePendingPresentation();
  }

  unregisterSurfaceAdapter(adapter: BrowserSearchInvocationSurfaceAdapter): void {
    if (this.surfaceAdapter !== adapter) {
      return;
    }
    this.clearSurfaceAdapter();
  }

  clearSurfaceAdapter(): void {
    const adapter = this.surfaceAdapter;
    if (adapter === undefined) {
      return;
    }
    this.surfaceAdapter = undefined;
    if (this.isSessionActive()) {
      this.presentationAttempt += 1;
      adapter.suspend(this.authorityId);
      this.phase = this.backgrounded ? 'background_suspended' : 'pending_window';
      this.pendingReason = 'surface_unavailable';
    }
  }

  isSurfaceAdapterRegistered(adapter: BrowserSearchInvocationSurfaceAdapter): boolean {
    return this.surfaceAdapter === adapter;
  }

  open(
    source: BrowserSearchInvocationSource,
    authorized: boolean = true
  ): BrowserSearchInvocationReceipt {
    if (!authorized) {
      const rejectedDeferred = new BrowserSearchPresentationDeferred();
      rejectedDeferred.resolve(new BrowserSearchPresentationOutcome(
        'rejected_authority',
        '',
        ''
      ));
      return new BrowserSearchInvocationReceipt('', '', 'rejected_authority', rejectedDeferred.promise);
    }

    if (this.phase === 'committed') {
      this.source = source;
      this.presentationAttempt += 1;
      this.pendingReason = '';
      this.activeDeferred = new BrowserSearchPresentationDeferred();
      const reinforcedReceipt = new BrowserSearchInvocationReceipt(
        this.sessionId,
        this.authorityId,
        'reinforced',
        this.activeDeferred.promise
      );
      this.startPresentation(true);
      return reinforcedReceipt;
    }

    const replacingPending = this.isSessionActive();
    if (this.activeDeferred !== undefined) {
      this.activeDeferred.resolve(new BrowserSearchPresentationOutcome(
        'superseded',
        this.sessionId,
        this.authorityId,
        this.scene
      ));
    }
    this.sessionSerial += 1;
    this.authorityEpoch += 1;
    this.presentationAttempt = 1;
    this.sessionId = `search-session-${this.sessionSerial}`;
    this.authorityId = `${this.sessionId}-authority-${this.authorityEpoch}`;
    this.phase = this.backgrounded ? 'background_suspended' : 'pending_window';
    this.source = source;
    this.scene = undefined;
    this.draft = '';
    this.draftSelection = 'caret_end';
    this.sessionActiveContextId = this.currentActiveContextId;
    this.sessionActiveContextKnown = this.currentActiveContextKnown;
    this.pendingReason = this.backgrounded ? 'app_backgrounded' : 'surface_unavailable';
    this.activeDeferred = new BrowserSearchPresentationDeferred();
    const receipt = new BrowserSearchInvocationReceipt(
      this.sessionId,
      this.authorityId,
      replacingPending ? 'replaced_pending' : 'started',
      this.activeDeferred.promise
    );
    this.startPresentation(false);
    return receipt;
  }

  notifyForeground(): void {
    const wasBackgrounded = this.backgrounded;
    this.backgrounded = false;
    if (wasBackgrounded) {
      this.resumePendingPresentation();
    }
  }

  notifyBackground(): void {
    if (this.backgrounded) {
      return;
    }
    this.backgrounded = true;
    if (!this.isSessionActive()) {
      return;
    }
    this.presentationAttempt += 1;
    this.phase = 'background_suspended';
    this.pendingReason = 'app_backgrounded';
    this.surfaceAdapter?.suspend(this.authorityId);
  }

  updateDraft(authorityId: string, draft: string): boolean {
    if (!this.hasAuthority(authorityId)) {
      return false;
    }
    this.draft = draft;
    this.draftSelection = 'preserve';
    return true;
  }

  reconcileActiveContext(activeContextId: string): boolean {
    const normalizedContextId = activeContextId.trim();
    this.currentActiveContextId = normalizedContextId;
    this.currentActiveContextKnown = true;
    if (!this.isSessionActive()) {
      return false;
    }
    if (!this.sessionActiveContextKnown) {
      this.sessionActiveContextId = normalizedContextId;
      this.sessionActiveContextKnown = true;
      return false;
    }
    if (normalizedContextId === this.sessionActiveContextId) {
      return false;
    }
    return this.end(this.authorityId, 'active_context_changed');
  }

  end(authorityId: string, reason: BrowserSearchInvocationEndReason): boolean {
    if (!this.hasAuthority(authorityId)) {
      return false;
    }
    const outcomeKind: BrowserSearchPresentationOutcomeKind = reason === 'context_destroyed'
      ? 'context_destroyed'
      : 'ended_before_commit';
    this.activeDeferred?.resolve(new BrowserSearchPresentationOutcome(
      outcomeKind,
      this.sessionId,
      this.authorityId,
      this.scene,
      '',
      reason === 'context_destroyed' ? 'context_destroyed' : ''
    ));
    this.surfaceAdapter?.end(this.authorityId, reason);
    this.phase = 'ended';
    this.pendingReason = '';
    this.scene = undefined;
    this.draft = '';
    this.draftSelection = 'caret_end';
    this.sessionActiveContextId = '';
    this.sessionActiveContextKnown = false;
    this.activeDeferred = undefined;
    return true;
  }

  currentAuthorityId(): string {
    return this.authorityId;
  }

  snapshot(): BrowserSearchInvocationSnapshot {
    return new BrowserSearchInvocationSnapshot(
      this.sessionId,
      this.authorityId,
      this.authorityEpoch,
      this.presentationAttempt,
      this.phase,
      this.source,
      this.scene,
      this.draft,
      this.backgrounded,
      this.pendingReason
    );
  }

  private resumePendingPresentation(): void {
    if (!this.isSessionActive() || this.backgrounded ||
      (this.phase !== 'pending_window' &&
        this.phase !== 'pending_protected_flow' &&
        this.phase !== 'background_suspended')) {
      return;
    }
    this.presentationAttempt += 1;
    this.startPresentation(false);
  }

  private startPresentation(reinforced: boolean): void {
    if (!this.isSessionActive()) {
      return;
    }
    if (this.backgrounded) {
      this.phase = 'background_suspended';
      this.pendingReason = 'app_backgrounded';
      return;
    }
    const authorityId = this.authorityId;
    const presentationAttempt = this.presentationAttempt;
    void this.runPresentation(authorityId, presentationAttempt, reinforced);
  }

  private async runPresentation(
    authorityId: string,
    presentationAttempt: number,
    reinforced: boolean
  ): Promise<void> {
    if (!this.isCurrentAttempt(authorityId, presentationAttempt)) {
      return;
    }
    const settingsAdapter = this.settingsAdapter;
    if (settingsAdapter !== undefined) {
      this.phase = 'routing';
      this.pendingReason = 'settings_navigation_commit';
      const exited = await settingsAdapter.requestExit(authorityId);
      if (!this.isCurrentAttempt(authorityId, presentationAttempt)) {
        return;
      }
      if (!exited) {
        this.failCurrentPresentation('settings_exit_failed');
        return;
      }
    }
    const surfaceAdapter = this.surfaceAdapter;
    if (surfaceAdapter === undefined) {
      this.phase = 'pending_window';
      this.pendingReason = 'surface_unavailable';
      return;
    }
    let sceneSnapshot = surfaceAdapter.resolveScene();
    let degradedReason = '';
    if (sceneSnapshot.scene === 'web' && !sceneSnapshot.valid) {
      sceneSnapshot = new BrowserSearchSceneSnapshot('home', true, '', 'caret_end');
      degradedReason = 'web_scene_invalid';
    }
    const hadResolvedScene = this.scene !== undefined;
    if (this.scene === 'web' && (sceneSnapshot.scene !== 'web' || !sceneSnapshot.valid)) {
      this.scene = 'home';
      this.draft = '';
      this.draftSelection = 'caret_end';
      degradedReason = 'web_scene_invalid';
    } else if (this.scene === undefined) {
      this.scene = sceneSnapshot.scene;
      this.draft = sceneSnapshot.draft;
      this.draftSelection = sceneSnapshot.selection;
    }
    this.phase = 'presenting';
    this.pendingReason = '';
    const result = await surfaceAdapter.present(new BrowserSearchPresentationRequest(
      this.sessionId,
      authorityId,
      presentationAttempt,
      this.scene ?? sceneSnapshot.scene,
      this.draft,
      reinforced && this.source === 'browser_chrome'
        ? sceneSnapshot.selection
        : (reinforced || hadResolvedScene ? 'preserve' : this.draftSelection),
      reinforced
    ));
    if (!this.isCurrentAttempt(authorityId, presentationAttempt)) {
      return;
    }
    if (result.kind === 'pending') {
      this.phase = 'pending_window';
      this.pendingReason = 'presentation_pending';
      return;
    }
    if (result.kind === 'failed') {
      this.failCurrentPresentation(result.failureReason.length > 0
        ? result.failureReason
        : 'presentation_commit_failed');
      return;
    }
    this.phase = 'committed';
    this.pendingReason = '';
    this.activeDeferred?.resolve(new BrowserSearchPresentationOutcome(
      'presentation_committed',
      this.sessionId,
      authorityId,
      this.scene,
      degradedReason
    ));
    this.activeDeferred = undefined;
  }

  private failCurrentPresentation(reason: BrowserSearchPresentationFailureReason): void {
    this.phase = 'failed';
    this.pendingReason = reason;
    this.activeDeferred?.resolve(new BrowserSearchPresentationOutcome(
      'failed',
      this.sessionId,
      this.authorityId,
      this.scene,
      '',
      reason
    ));
    this.activeDeferred = undefined;
  }

  private hasAuthority(authorityId: string): boolean {
    return authorityId.length > 0 && authorityId === this.authorityId && this.isSessionActive();
  }

  private isCurrentAttempt(authorityId: string, presentationAttempt: number): boolean {
    return this.hasAuthority(authorityId) && presentationAttempt === this.presentationAttempt;
  }

  private isSessionActive(): boolean {
    return this.sessionId.length > 0 &&
      this.phase !== 'idle' &&
      this.phase !== 'ended' &&
      this.phase !== 'failed';
  }
}

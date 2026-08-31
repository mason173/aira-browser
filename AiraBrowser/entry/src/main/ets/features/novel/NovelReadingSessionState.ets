export type NovelSessionPrivacyMode = 'regular' | 'private';

export type NovelSessionPhase = 'inactive' | 'opening' | 'book' | 'reader' | 'suspended';
type NovelSessionSuspensionReason = '' | 'tab_background' | 'browser_home';

export type NovelSessionOperationStatus = 'idle' | 'loading' | 'failed';

export type NovelSessionChapterIntent = 'start' | 'select' | 'previous' | 'next' | 'continue_vertical';

export type NovelSessionContentKind = 'novel' | 'comic';

export type NovelSessionFailureCode = '' | 'retryable' | 'content_rejected' | 'identity_mismatch' |
  'unsupported_source' | 'authentication_required' | 'cancelled_stale';

export interface NovelSessionChapterRequest {
  requestId: string;
  sessionGeneration: number;
  tabId: string;
  privacyMode: NovelSessionPrivacyMode;
  chapterId: string;
  requestedUrl: string;
  intent: NovelSessionChapterIntent;
  startingTrailTailId: string;
}

export interface NovelSessionChapterRetryTarget {
  chapterId: string;
  requestedUrl: string;
  intent: NovelSessionChapterIntent;
}

export interface NovelSessionCommittedChapter {
  id: string;
  bookId: string;
  canonicalUrl: string;
  requestedUrl: string;
  finalUrl: string;
  title: string;
  contentKind: NovelSessionContentKind;
  paragraphs: string[];
  images: string[];
  prevUrl: string;
  nextUrl: string;
  catalogUrl: string;
  revision: number;
}

export interface NovelSessionChapterCommit {
  chapter: NovelSessionCommittedChapter;
}

export interface NovelSessionCatalogRequest {
  requestId: string;
  sessionGeneration: number;
  tabId: string;
  privacyMode: NovelSessionPrivacyMode;
  catalogUrl: string;
}

export interface NovelSessionCatalogChapter {
  id: string;
  title: string;
  canonicalUrl: string;
  ordinal: number;
}

export interface NovelSessionCatalogCommit {
  catalogUrl: string;
  chapters: NovelSessionCatalogChapter[];
  complete: boolean;
}

export interface NovelSessionOperationSnapshot {
  status: NovelSessionOperationStatus;
  requestId: string;
  failureCode: NovelSessionFailureCode;
}

export interface NovelSessionReadingCheckpoint {
  chapterId: string;
  canonicalUrl: string;
  characterOffset: number;
  updatedAt: number;
}

export interface NovelReadingSessionSnapshot {
  phase: NovelSessionPhase;
  sessionGeneration: number;
  tabId: string;
  privacyMode: NovelSessionPrivacyMode;
  bookId: string;
  startChapterUrl: string;
  activeChapterId: string;
  chapterTrail: NovelSessionCommittedChapter[];
  catalogUrl: string;
  catalog: NovelSessionCatalogChapter[];
  catalogComplete: boolean;
  checkpoint: NovelSessionReadingCheckpoint;
  chapterTransition: NovelSessionOperationSnapshot;
  catalogTransition: NovelSessionOperationSnapshot;
}

function createIdleOperation(): NovelSessionOperationSnapshot {
  return {
    status: 'idle',
    requestId: '',
    failureCode: ''
  };
}

function cloneOperation(operation: NovelSessionOperationSnapshot): NovelSessionOperationSnapshot {
  return {
    status: operation.status,
    requestId: operation.requestId,
    failureCode: operation.failureCode
  };
}

function createEmptyCheckpoint(): NovelSessionReadingCheckpoint {
  return {
    chapterId: '',
    canonicalUrl: '',
    characterOffset: 0,
    updatedAt: 0
  };
}

function cloneCheckpoint(checkpoint: NovelSessionReadingCheckpoint): NovelSessionReadingCheckpoint {
  return {
    chapterId: checkpoint.chapterId,
    canonicalUrl: checkpoint.canonicalUrl,
    characterOffset: checkpoint.characterOffset,
    updatedAt: checkpoint.updatedAt
  };
}

function cloneChapter(chapter: NovelSessionCommittedChapter): NovelSessionCommittedChapter {
  return {
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
  };
}

export function buildNovelChapterRenderKey(chapter: NovelSessionCommittedChapter): string {
  return `${chapter.id.length}:${chapter.id}:${chapter.revision}`;
}

function cloneTrail(chapters: NovelSessionCommittedChapter[]): NovelSessionCommittedChapter[] {
  return chapters.map((chapter: NovelSessionCommittedChapter): NovelSessionCommittedChapter => cloneChapter(chapter));
}

function cloneCatalogChapter(chapter: NovelSessionCatalogChapter): NovelSessionCatalogChapter {
  return {
    id: chapter.id,
    title: chapter.title,
    canonicalUrl: chapter.canonicalUrl,
    ordinal: chapter.ordinal
  };
}

function cloneCatalog(chapters: NovelSessionCatalogChapter[]): NovelSessionCatalogChapter[] {
  return chapters.map((chapter: NovelSessionCatalogChapter): NovelSessionCatalogChapter => cloneCatalogChapter(chapter));
}

function cloneRetryTarget(target: NovelSessionChapterRetryTarget): NovelSessionChapterRetryTarget {
  return {
    chapterId: target.chapterId,
    requestedUrl: target.requestedUrl,
    intent: target.intent
  };
}

export class NovelReadingSessionState {
  private phase: NovelSessionPhase = 'inactive';
  private phaseBeforeSuspension: NovelSessionPhase = 'inactive';
  private suspensionReason: NovelSessionSuspensionReason = '';
  private continuationRequested: boolean = false;
  private sessionGeneration: number = 0;
  private tabId: string = '';
  private privacyMode: NovelSessionPrivacyMode = 'regular';
  private bookId: string = '';
  private startChapterUrl: string = '';
  private activeChapterId: string = '';
  private chapterTrail: NovelSessionCommittedChapter[] = [];
  private catalogUrl: string = '';
  private catalog: NovelSessionCatalogChapter[] = [];
  private catalogComplete: boolean = false;
  private checkpoint: NovelSessionReadingCheckpoint = createEmptyCheckpoint();
  private chapterTransition: NovelSessionOperationSnapshot = createIdleOperation();
  private catalogTransition: NovelSessionOperationSnapshot = createIdleOperation();
  private pendingChapterRequest?: NovelSessionChapterRequest;
  private pendingCatalogRequest?: NovelSessionCatalogRequest;
  private failedChapterTarget?: NovelSessionChapterRetryTarget;

  begin(
    tabId: string,
    privacyMode: NovelSessionPrivacyMode,
    bookId: string,
    sessionGeneration: number
  ): void {
    this.phase = 'opening';
    this.phaseBeforeSuspension = 'opening';
    this.suspensionReason = '';
    this.continuationRequested = false;
    this.sessionGeneration = sessionGeneration;
    this.tabId = tabId;
    this.privacyMode = privacyMode;
    this.bookId = bookId;
    this.startChapterUrl = '';
    this.activeChapterId = '';
    this.chapterTrail = [];
    this.catalogUrl = '';
    this.catalog = [];
    this.catalogComplete = false;
    this.checkpoint = createEmptyCheckpoint();
    this.chapterTransition = createIdleOperation();
    this.catalogTransition = createIdleOperation();
    this.pendingChapterRequest = undefined;
    this.pendingCatalogRequest = undefined;
    this.failedChapterTarget = undefined;
  }

  end(): void {
    this.phase = 'inactive';
    this.phaseBeforeSuspension = 'inactive';
    this.suspensionReason = '';
    this.continuationRequested = false;
    this.sessionGeneration = 0;
    this.tabId = '';
    this.privacyMode = 'regular';
    this.bookId = '';
    this.startChapterUrl = '';
    this.activeChapterId = '';
    this.chapterTrail = [];
    this.catalogUrl = '';
    this.catalog = [];
    this.catalogComplete = false;
    this.checkpoint = createEmptyCheckpoint();
    this.cancelPendingOperations();
    this.failedChapterTarget = undefined;
  }

  beginChapterTransition(request: NovelSessionChapterRequest): boolean {
    if (!this.belongsToCurrentSession(request)) {
      return false;
    }
    this.pendingChapterRequest = request;
    this.failedChapterTarget = undefined;
    this.chapterTransition = {
      status: 'loading',
      requestId: request.requestId,
      failureCode: ''
    };
    return true;
  }

  setBookIdentity(bookId: string): boolean {
    if (this.phase === 'inactive' || this.chapterTrail.length > 0 || bookId.length === 0) {
      return false;
    }
    this.bookId = bookId;
    return true;
  }

  markBookReady(startChapterUrl: string = ''): boolean {
    if (this.phase === 'inactive' || this.phase === 'suspended' || this.chapterTrail.length > 0) {
      return false;
    }
    this.startChapterUrl = startChapterUrl;
    this.phase = 'book';
    return true;
  }

  beginCatalogTransition(request: NovelSessionCatalogRequest): boolean {
    if (!this.catalogRequestBelongsToCurrentSession(request) || request.catalogUrl.length === 0) {
      return false;
    }
    this.pendingCatalogRequest = request;
    this.catalogTransition = {
      status: 'loading',
      requestId: request.requestId,
      failureCode: ''
    };
    return true;
  }

  commitCatalog(request: NovelSessionCatalogRequest, commit: NovelSessionCatalogCommit): boolean {
    if (!this.isCurrentCatalogRequest(request) || commit.catalogUrl !== request.catalogUrl) {
      return false;
    }
    this.catalogUrl = commit.catalogUrl;
    this.catalog = cloneCatalog(commit.chapters);
    this.catalogComplete = commit.complete;
    this.catalogTransition = createIdleOperation();
    this.pendingCatalogRequest = undefined;
    return true;
  }

  failCatalog(request: NovelSessionCatalogRequest, failureCode: NovelSessionFailureCode): boolean {
    if (!this.isCurrentCatalogRequest(request)) {
      return false;
    }
    this.catalogTransition = failureCode === 'cancelled_stale' || this.catalog.length > 0 ? createIdleOperation() : {
      status: 'failed',
      requestId: request.requestId,
      failureCode: failureCode
    };
    this.pendingCatalogRequest = undefined;
    return true;
  }

  commitChapter(request: NovelSessionChapterRequest, commit: NovelSessionChapterCommit): boolean {
    if (!this.isCurrentChapterRequest(request) || !this.isValidCommit(request, commit.chapter)) {
      return false;
    }
    const committedChapter: NovelSessionCommittedChapter = cloneChapter(commit.chapter);
    if (request.intent === 'continue_vertical') {
      this.chapterTrail = cloneTrail(this.chapterTrail);
      this.chapterTrail.push(committedChapter);
    } else {
      this.chapterTrail = [committedChapter];
    }
    this.activeChapterId = committedChapter.id;
    this.checkpoint = this.checkpoint.chapterId === committedChapter.id ? cloneCheckpoint(this.checkpoint) : {
      chapterId: committedChapter.id,
      canonicalUrl: committedChapter.canonicalUrl,
      characterOffset: 0,
      updatedAt: 0
    };
    this.phase = 'reader';
    this.chapterTransition = createIdleOperation();
    this.pendingChapterRequest = undefined;
    this.failedChapterTarget = undefined;
    return true;
  }

  failChapter(request: NovelSessionChapterRequest, failureCode: NovelSessionFailureCode): boolean {
    if (!this.isCurrentChapterRequest(request)) {
      return false;
    }
    this.chapterTransition = failureCode === 'cancelled_stale' ? createIdleOperation() : {
      status: 'failed',
      requestId: request.requestId,
      failureCode: failureCode
    };
    this.failedChapterTarget = failureCode === 'cancelled_stale' ? undefined : {
      chapterId: request.chapterId,
      requestedUrl: request.requestedUrl,
      intent: request.intent
    };
    this.pendingChapterRequest = undefined;
    return true;
  }

  failedChapterRetryTarget(): NovelSessionChapterRetryTarget | undefined {
    return this.failedChapterTarget === undefined ? undefined : cloneRetryTarget(this.failedChapterTarget);
  }

  recordCheckpoint(chapterId: string, characterOffset: number, updatedAt: number): boolean {
    if (this.phase !== 'reader') {
      return false;
    }
    const chapter: NovelSessionCommittedChapter | undefined = this.findChapter(chapterId);
    if (chapter === undefined) {
      return false;
    }
    this.activeChapterId = chapter.id;
    this.checkpoint = {
      chapterId: chapter.id,
      canonicalUrl: chapter.canonicalUrl,
      characterOffset: Math.max(0, Math.floor(characterOffset)),
      updatedAt: Math.max(0, Math.floor(updatedAt))
    };
    return true;
  }

  checkpointForPersistence(): NovelSessionReadingCheckpoint | undefined {
    if (this.privacyMode !== 'regular' || this.checkpoint.chapterId.length === 0) {
      return undefined;
    }
    return cloneCheckpoint(this.checkpoint);
  }

  suspend(activeTabId: string): boolean {
    if (this.phase === 'inactive' || this.phase === 'opening' || this.phase === 'suspended' ||
      activeTabId === this.tabId) {
      return false;
    }
    return this.suspendCurrent('tab_background');
  }

  suspendToHome(): boolean {
    if (this.phase !== 'reader' && this.phase !== 'book') {
      return false;
    }
    return this.suspendCurrent('browser_home');
  }

  requestContinuation(): boolean {
    if (this.phase !== 'suspended') {
      return false;
    }
    this.continuationRequested = true;
    return true;
  }

  private suspendCurrent(reason: NovelSessionSuspensionReason): boolean {
    this.phaseBeforeSuspension = this.phase;
    this.phase = 'suspended';
    this.suspensionReason = reason;
    this.continuationRequested = false;
    this.cancelPendingOperations();
    return true;
  }

  resume(activeTabId: string): boolean {
    if (this.phase !== 'suspended' || activeTabId !== this.tabId ||
      (this.suspensionReason === 'browser_home' && !this.continuationRequested)) {
      return false;
    }
    this.phase = this.phaseBeforeSuspension === 'suspended' || this.phaseBeforeSuspension === 'inactive' ?
      'opening' : this.phaseBeforeSuspension;
    this.suspensionReason = '';
    this.continuationRequested = false;
    return true;
  }

  snapshot(): NovelReadingSessionSnapshot {
    return {
      phase: this.phase,
      sessionGeneration: this.sessionGeneration,
      tabId: this.tabId,
      privacyMode: this.privacyMode,
      bookId: this.bookId,
      startChapterUrl: this.startChapterUrl,
      activeChapterId: this.activeChapterId,
      chapterTrail: cloneTrail(this.chapterTrail),
      catalogUrl: this.catalogUrl,
      catalog: cloneCatalog(this.catalog),
      catalogComplete: this.catalogComplete,
      checkpoint: cloneCheckpoint(this.checkpoint),
      chapterTransition: cloneOperation(this.chapterTransition),
      catalogTransition: cloneOperation(this.catalogTransition)
    };
  }

  private belongsToCurrentSession(request: NovelSessionChapterRequest): boolean {
    return this.phase !== 'inactive' && this.phase !== 'suspended' &&
      request.sessionGeneration === this.sessionGeneration &&
      request.tabId === this.tabId && request.privacyMode === this.privacyMode;
  }

  private catalogRequestBelongsToCurrentSession(request: NovelSessionCatalogRequest): boolean {
    return this.phase !== 'inactive' && this.phase !== 'suspended' &&
      request.sessionGeneration === this.sessionGeneration &&
      request.tabId === this.tabId && request.privacyMode === this.privacyMode;
  }

  private isCurrentChapterRequest(request: NovelSessionChapterRequest): boolean {
    const pending: NovelSessionChapterRequest | undefined = this.pendingChapterRequest;
    return pending !== undefined && this.belongsToCurrentSession(request) &&
      pending.requestId === request.requestId && pending.chapterId === request.chapterId &&
      pending.requestedUrl === request.requestedUrl && pending.intent === request.intent &&
      pending.startingTrailTailId === request.startingTrailTailId;
  }

  private isCurrentCatalogRequest(request: NovelSessionCatalogRequest): boolean {
    const pending: NovelSessionCatalogRequest | undefined = this.pendingCatalogRequest;
    return pending !== undefined && this.catalogRequestBelongsToCurrentSession(request) &&
      pending.requestId === request.requestId && pending.catalogUrl === request.catalogUrl;
  }

  private isValidCommit(
    request: NovelSessionChapterRequest,
    chapter: NovelSessionCommittedChapter
  ): boolean {
    if (chapter.id !== request.chapterId || chapter.bookId !== this.bookId || chapter.canonicalUrl.trim().length === 0 ||
      chapter.revision <= 0 || !this.hasCanonicalContent(chapter)) {
      return false;
    }
    if (request.intent !== 'continue_vertical') {
      return true;
    }
    const tailId: string = this.chapterTrail.length > 0 ?
      this.chapterTrail[this.chapterTrail.length - 1].id : '';
    return request.startingTrailTailId === tailId && tailId.length > 0;
  }

  private hasCanonicalContent(chapter: NovelSessionCommittedChapter): boolean {
    for (let index: number = 0; index < chapter.paragraphs.length; index++) {
      if (chapter.paragraphs[index].trim().length > 0) {
        return true;
      }
    }
    for (let index: number = 0; index < chapter.images.length; index++) {
      if (chapter.images[index].trim().length > 0) {
        return true;
      }
    }
    return false;
  }

  private findChapter(chapterId: string): NovelSessionCommittedChapter | undefined {
    for (let i: number = 0; i < this.chapterTrail.length; i++) {
      if (this.chapterTrail[i].id === chapterId) {
        return this.chapterTrail[i];
      }
    }
    return undefined;
  }

  private cancelPendingOperations(): void {
    this.pendingChapterRequest = undefined;
    this.pendingCatalogRequest = undefined;
    this.chapterTransition = createIdleOperation();
    this.catalogTransition = createIdleOperation();
  }
}

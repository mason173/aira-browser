import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  TranslationProviderConfig,
  TranslationSettings
} from '../../common/models/BrowserModels';
import {
  WebpageTranslationCacheContext
} from '../../services/translation/WebpageTranslationPersistentCacheService';

export type WebpageTranslationSessionDisplayMode =
  'none' |
  'bilingual' |
  'translation_only' |
  'original';

export type WebpageTranslationSessionEventName =
  'session_start' |
  'session_end' |
  'cache_split' |
  'provider_request_blocked' |
  'provider_request_failed' |
  'apply_done' |
  'session_stale' |
  'lifecycle_event';

export type WebpageTranslationSessionStatus =
  'idle' |
  'extracting' |
  'translating' |
  'partially_translated' |
  'translated' |
  'restored' |
  'canceled' |
  'error';

export interface WebpageTranslationSessionContextInput {
  generation: number;
  provider: TranslationProviderConfig | undefined;
  settings: TranslationSettings;
  sourceLanguage: string;
  targetLanguage: string;
  documentUrl: string;
  runtimeCacheNamespace: string;
  cacheContext: WebpageTranslationCacheContext;
}

export interface WebpageTranslationSessionContext {
  sessionId: string;
  generation: number;
  provider: TranslationProviderConfig | undefined;
  settings: TranslationSettings;
  sourceLanguage: string;
  targetLanguage: string;
  documentUrl: string;
  runtimeCacheNamespace: string;
  cacheContext: WebpageTranslationCacheContext;
  displayMode: WebpageTranslationSessionDisplayMode;
  status: WebpageTranslationSessionStatus;
  startedAt: number;
  lastActivityAt: number;
  extractedCount: number;
  appliedCount: number;
  cacheHitCount: number;
  requestedCount: number;
  requestedChars: number;
}

const WEBPAGE_TRANSLATION_SESSION_LOG_DOMAIN: number = 0x0000;
const WEBPAGE_TRANSLATION_SESSION_LOG_TAG: string = 'QFWebTranslateSession';

export class WebpageTranslationSessionCoordinator {
  private generation: number = 0;
  private loadingRunId: number = 0;
  private displayMode: WebpageTranslationSessionDisplayMode = 'none';
  private activeSession: WebpageTranslationSessionContext | undefined = undefined;

  cancelCurrentTaskGeneration(): number {
    this.generation += 1;
    this.endActiveSession('canceled');
    return this.generation;
  }

  nextTaskGeneration(): number {
    this.generation += 1;
    this.activeSession = undefined;
    this.displayMode = 'none';
    return this.generation;
  }

  isStale(taskGeneration: number): boolean {
    return taskGeneration !== this.generation;
  }

  nextLoadingRunId(): number {
    this.loadingRunId += 1;
    return this.loadingRunId;
  }

  setDisplayMode(displayMode: WebpageTranslationSessionDisplayMode): void {
    this.displayMode = displayMode;
    if (this.activeSession !== undefined) {
      this.activeSession.displayMode = displayMode;
      this.touchSession();
    }
  }

  getDisplayMode(): WebpageTranslationSessionDisplayMode {
    return this.displayMode;
  }

  getAppliedDisplayMode(): WebpageTranslationSessionDisplayMode {
    return this.displayMode === 'translation_only' ? 'translation_only' : 'bilingual';
  }

  beginSession(input: WebpageTranslationSessionContextInput): WebpageTranslationSessionContext {
    const now = Date.now();
    this.displayMode = 'translation_only';
    this.activeSession = {
      sessionId: this.buildSessionId(input.generation, now),
      generation: input.generation,
      provider: input.provider,
      settings: input.settings,
      sourceLanguage: input.sourceLanguage,
      targetLanguage: input.targetLanguage,
      documentUrl: input.documentUrl,
      runtimeCacheNamespace: input.runtimeCacheNamespace,
      cacheContext: input.cacheContext,
      displayMode: this.displayMode,
      status: 'translating',
      startedAt: now,
      lastActivityAt: now,
      extractedCount: 0,
      appliedCount: 0,
      cacheHitCount: 0,
      requestedCount: 0,
      requestedChars: 0
    };
    this.logSessionEvent('session_start', 0, 0, 0, 0, input.documentUrl);
    return this.activeSession;
  }

  getActiveSession(taskGeneration?: number): WebpageTranslationSessionContext | undefined {
    if (this.activeSession === undefined) {
      return undefined;
    }
    if (taskGeneration !== undefined && this.activeSession.generation !== taskGeneration) {
      return undefined;
    }
    return this.activeSession;
  }

  updateSessionStatus(status: WebpageTranslationSessionStatus): void {
    if (this.activeSession === undefined) {
      return;
    }
    this.activeSession.status = status;
    this.touchSession();
  }

  updateSessionProgress(
    extractedCount: number,
    appliedCount: number,
    cacheHitCount: number,
    requestedCount: number,
    requestedChars: number
  ): void {
    if (this.activeSession === undefined) {
      return;
    }
    this.activeSession.extractedCount = Math.max(this.activeSession.extractedCount, Math.max(0, Math.floor(extractedCount)));
    this.activeSession.appliedCount = Math.max(this.activeSession.appliedCount, Math.max(0, Math.floor(appliedCount)));
    this.activeSession.cacheHitCount = Math.max(this.activeSession.cacheHitCount, Math.max(0, Math.floor(cacheHitCount)));
    this.activeSession.requestedCount = Math.max(this.activeSession.requestedCount, Math.max(0, Math.floor(requestedCount)));
    this.activeSession.requestedChars = Math.max(this.activeSession.requestedChars, Math.max(0, Math.floor(requestedChars)));
    this.touchSession();
  }

  addSessionProgress(
    extractedCount: number,
    appliedCount: number,
    cacheHitCount: number,
    requestedCount: number,
    requestedChars: number
  ): void {
    if (this.activeSession === undefined) {
      return;
    }
    this.activeSession.extractedCount += Math.max(0, Math.floor(extractedCount));
    this.activeSession.appliedCount += Math.max(0, Math.floor(appliedCount));
    this.activeSession.cacheHitCount += Math.max(0, Math.floor(cacheHitCount));
    this.activeSession.requestedCount += Math.max(0, Math.floor(requestedCount));
    this.activeSession.requestedChars += Math.max(0, Math.floor(requestedChars));
    this.touchSession();
  }

  endActiveSession(status: WebpageTranslationSessionStatus): void {
    if (this.activeSession !== undefined) {
      this.activeSession.status = status;
      this.activeSession.lastActivityAt = Date.now();
      this.logSessionEvent('session_end', 0, 0, 0, 0, status);
    }
    this.activeSession = undefined;
  }

  logSessionEvent(
    eventName: WebpageTranslationSessionEventName,
    itemCount: number = 0,
    charCount: number = 0,
    cacheHitCount: number = 0,
    requestedCount: number = 0,
    message: string = ''
  ): void {
    const session = this.activeSession;
    if (session === undefined) {
      hilog.info(
        WEBPAGE_TRANSLATION_SESSION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_SESSION_LOG_TAG,
        'session event=%{public}s active=false items=%{public}d chars=%{public}d cacheHit=%{public}d requested=%{public}d message=%{public}s',
        eventName,
        itemCount,
        charCount,
        cacheHitCount,
        requestedCount,
        message
      );
      return;
    }
    hilog.info(
      WEBPAGE_TRANSLATION_SESSION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_SESSION_LOG_TAG,
      'session event=%{public}s sessionId=%{public}s generation=%{public}d status=%{public}s displayMode=%{public}s provider=%{public}s source=%{public}s target=%{public}s items=%{public}d chars=%{public}d cacheHit=%{public}d requested=%{public}d message=%{public}s',
      eventName,
      session.sessionId,
      session.generation,
      session.status,
      session.displayMode,
      session.provider?.templateId ?? 'none',
      session.sourceLanguage,
      session.targetLanguage,
      itemCount,
      charCount,
      cacheHitCount,
      requestedCount,
      message
    );
  }

  private touchSession(): void {
    if (this.activeSession !== undefined) {
      this.activeSession.lastActivityAt = Date.now();
    }
  }

  private buildSessionId(generation: number, startedAt: number): string {
    return `${startedAt.toString(36)}-${generation.toString(36)}`;
  }
}

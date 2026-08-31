import {
  BrowserDataBoundaryInput,
  BrowserExperimentSettings,
  DEFAULT_SEARCH_ENGINE_ID,
  SearchEngineId,
  SearchEngineRecord,
  SearchEngineSettings
} from '../../common/models/BrowserModels';
import {
  looksLikeUrl,
  normalizeAddressInputText,
  normalizeUrl,
  resolveSchemelessHttpFallbackUrl
} from '../../common/utils/UrlUtils';
import { SearchEngineTemplateService } from './SearchEngineTemplateService';
import {
  SearchEngineAvailabilityProbeService,
  SearchEngineAvailabilityProbeRequest,
  SearchEngineAvailabilitySnapshot
} from './SearchEngineAvailabilityProbeService';

export type SearchEngineRoutingIntent = 'empty' | 'navigate' | 'search';
export type SearchEngineRoutingMode = 'configured' | 'exact';
export type SmartSearchFallbackEligibilityResolver = (boundary: BrowserDataBoundaryInput) => Promise<boolean>;

export interface SearchEngineRoutingInput {
  rawInput: string;
  selectedSearchEngineId: SearchEngineId;
  settings: SearchEngineSettings;
  availableSearchEngines: SearchEngineRecord[];
  routingMode?: SearchEngineRoutingMode;
  experiments?: BrowserExperimentSettings;
  maxProbeWaitMs?: number;
  boundary: BrowserDataBoundaryInput;
}

export interface SearchEngineRoutingResult {
  rawInput: string;
  submittedText: string;
  resolvedUrl: string;
  intent: SearchEngineRoutingIntent;
  searchQuery: string;
  searchEngineId: SearchEngineId;
  primarySearchEngineId: SearchEngineId;
  fallbackApplied: boolean;
  fallbackMessage: string;
  httpFallbackUrl: string;
  availability?: SearchEngineAvailabilitySnapshot;
}

export interface SearchEngineLoadFailureFallbackInput {
  primarySearchEngineId: SearchEngineId;
  query: string;
}

export interface SearchEngineFallbackNoticeInput {
  primarySearchEngineId: SearchEngineId;
  primarySearchEngineName: string;
  fallbackSearchEngineId: SearchEngineId;
  fallbackSearchEngineName: string;
  noticeEnabled: boolean;
}

interface PendingSearchEngineLoadFailureFallback {
  count: number;
  expiresAt: number;
}

const FOREGROUND_SEARCH_ENGINE_PROBE_MIN_WAIT_MS: number = 900;
const SEARCH_ENGINE_LOAD_FAILURE_FALLBACK_TTL_MS: number = 2 * 60 * 1000;
const MAX_PENDING_SEARCH_ENGINE_LOAD_FAILURE_FALLBACKS: number = 64;
const MAX_IDENTICAL_PENDING_SEARCH_ENGINE_LOAD_FAILURE_FALLBACKS: number = 8;

export class SearchEngineRoutingService {
  private templateService: SearchEngineTemplateService = new SearchEngineTemplateService();
  private availabilityService: SearchEngineAvailabilityProbeService;
  private smartFallbackEligibilityResolver: SmartSearchFallbackEligibilityResolver;
  private lastFallbackNoticeSignature: string = '';
  private pendingLoadFailureFallbacks: Map<string, PendingSearchEngineLoadFailureFallback> =
    new Map<string, PendingSearchEngineLoadFailureFallback>();

  constructor(
    availabilityService: SearchEngineAvailabilityProbeService = new SearchEngineAvailabilityProbeService(),
    smartFallbackEligibilityResolver: SmartSearchFallbackEligibilityResolver =
      async (_boundary: BrowserDataBoundaryInput): Promise<boolean> => false
  ) {
    this.availabilityService = availabilityService;
    this.smartFallbackEligibilityResolver = smartFallbackEligibilityResolver;
  }

  setSmartFallbackEligibilityResolver(resolver: SmartSearchFallbackEligibilityResolver): void {
    this.smartFallbackEligibilityResolver = resolver;
  }

  async resolve(input: SearchEngineRoutingInput): Promise<SearchEngineRoutingResult> {
    const submittedText = normalizeAddressInputText(input.rawInput);
    if (submittedText.length === 0) {
      return this.buildResult(input.rawInput, submittedText, '', 'empty', '', input.selectedSearchEngineId,
        input.selectedSearchEngineId, false, '', '');
    }
    if (this.looksLikeNavigation(submittedText)) {
      const resolvedUrl = normalizeUrl(submittedText);
      const httpFallbackUrl = resolveSchemelessHttpFallbackUrl(submittedText);
      return this.buildResult(input.rawInput, submittedText, resolvedUrl, 'navigate', '', input.selectedSearchEngineId,
        input.selectedSearchEngineId, false, '', httpFallbackUrl);
    }

    const exactRouting = input.routingMode === 'exact';
    const primaryEngine = exactRouting ?
      this.resolveOptionalEngine(input.selectedSearchEngineId, input.availableSearchEngines) :
      this.resolveEngine(
        input.selectedSearchEngineId,
        input.settings.defaultSearchEngineId,
        input.availableSearchEngines
      );
    if (primaryEngine === undefined) {
      return this.buildResult(input.rawInput, submittedText, '', 'empty', '', input.selectedSearchEngineId,
        input.selectedSearchEngineId, false, '', '');
    }
    if (exactRouting) {
      return this.buildSearchResult(input, submittedText, primaryEngine, primaryEngine, false, '', undefined);
    }
    const fallbackEngine = this.resolveOptionalEngine(
      input.settings.fallbackSearch.fallbackSearchEngineId,
      input.availableSearchEngines
    );
    if (!this.isSmartFallbackConfigured(input.settings, primaryEngine, fallbackEngine)) {
      return this.buildSearchResult(input, submittedText, primaryEngine, primaryEngine, false, '', undefined);
    }
    if (!await this.canUseSmartFallback(input.boundary)) {
      return this.buildSearchResult(input, submittedText, primaryEngine, primaryEngine, false, '', undefined);
    }

    const probeRequest: SearchEngineAvailabilityProbeRequest = {
      engine: primaryEngine,
      experiments: input.experiments,
      maxWaitMs: Math.max(input.maxProbeWaitMs ?? 0, FOREGROUND_SEARCH_ENGINE_PROBE_MIN_WAIT_MS)
    };
    let availability = this.availabilityService.resolveCachedAvailability(probeRequest);
    if (availability === undefined) {
      try {
        availability = await this.availabilityService.resolveAvailability(probeRequest);
      } catch (_error) {
        availability = undefined;
      }
    }
    if (availability?.reachability !== 'unreachable' || fallbackEngine === undefined) {
      if (availability?.reachability === 'reachable') {
        this.lastFallbackNoticeSignature = '';
      }
      const primaryResult = this.buildSearchResult(
        input,
        submittedText,
        primaryEngine,
        primaryEngine,
        false,
        '',
        availability
      );
      if (primaryResult.resolvedUrl.length > 0) {
        this.rememberLoadFailureFallback(primaryEngine.id, submittedText);
      }
      return primaryResult;
    }

    return this.buildSearchResult(
      input,
      submittedText,
      primaryEngine,
      fallbackEngine,
      true,
      this.buildFallbackMessageIfEnabled(input.settings, primaryEngine, fallbackEngine),
      availability
    );
  }

  invalidateAvailabilityCache(): void {
    this.availabilityService.invalidate();
    this.lastFallbackNoticeSignature = '';
    this.pendingLoadFailureFallbacks.clear();
  }

  consumeLoadFailureFallback(input: SearchEngineLoadFailureFallbackInput): boolean {
    const now = Date.now();
    this.pruneExpiredLoadFailureFallbacks(now);
    const key = this.buildLoadFailureFallbackKey(input.primarySearchEngineId, input.query);
    const pending = this.pendingLoadFailureFallbacks.get(key);
    if (pending === undefined || pending.count <= 0 || pending.expiresAt <= now) {
      return false;
    }
    if (pending.count === 1) {
      this.pendingLoadFailureFallbacks.delete(key);
    } else {
      pending.count -= 1;
    }
    return true;
  }

  buildFallbackNotice(input: SearchEngineFallbackNoticeInput): string {
    if (!input.noticeEnabled) {
      this.lastFallbackNoticeSignature = '';
      return '';
    }
    const signature = `${input.primarySearchEngineId}->${input.fallbackSearchEngineId}`;
    if (signature === this.lastFallbackNoticeSignature) {
      return '';
    }
    this.lastFallbackNoticeSignature = signature;
    return `${input.primarySearchEngineName} 当前不可用，已用 ${input.fallbackSearchEngineName} 搜索。`;
  }

  private buildSearchResult(
    input: SearchEngineRoutingInput,
    submittedText: string,
    primaryEngine: SearchEngineRecord,
    effectiveEngine: SearchEngineRecord,
    fallbackApplied: boolean,
    fallbackMessage: string,
    availability: SearchEngineAvailabilitySnapshot | undefined
  ): SearchEngineRoutingResult {
    const resolvedUrl = this.templateService.buildSearchUrl(submittedText, effectiveEngine);
    return this.buildResult(
      input.rawInput,
      submittedText,
      resolvedUrl,
      resolvedUrl.length > 0 ? 'search' : 'empty',
      resolvedUrl.length > 0 ? submittedText : '',
      effectiveEngine.id,
      primaryEngine.id,
      fallbackApplied,
      fallbackMessage,
      '',
      availability
    );
  }

  private isSmartFallbackConfigured(
    settings: SearchEngineSettings,
    primaryEngine: SearchEngineRecord,
    fallbackEngine: SearchEngineRecord | undefined
  ): boolean {
    return settings.fallbackSearch.enabled &&
      fallbackEngine !== undefined &&
      fallbackEngine.id !== primaryEngine.id;
  }

  private async canUseSmartFallback(boundary: BrowserDataBoundaryInput): Promise<boolean> {
    try {
      return await this.smartFallbackEligibilityResolver(boundary);
    } catch (_error) {
      return false;
    }
  }

  private rememberLoadFailureFallback(primarySearchEngineId: SearchEngineId, query: string): void {
    const now = Date.now();
    this.pruneExpiredLoadFailureFallbacks(now);
    const key = this.buildLoadFailureFallbackKey(primarySearchEngineId, query);
    if (key.length <= 0) {
      return;
    }
    const existing = this.pendingLoadFailureFallbacks.get(key);
    if (existing !== undefined) {
      existing.count = Math.min(
        MAX_IDENTICAL_PENDING_SEARCH_ENGINE_LOAD_FAILURE_FALLBACKS,
        existing.count + 1
      );
      existing.expiresAt = now + SEARCH_ENGINE_LOAD_FAILURE_FALLBACK_TTL_MS;
      return;
    }
    this.evictOldestLoadFailureFallbackIfNeeded();
    this.pendingLoadFailureFallbacks.set(key, {
      count: 1,
      expiresAt: now + SEARCH_ENGINE_LOAD_FAILURE_FALLBACK_TTL_MS
    });
  }

  private pruneExpiredLoadFailureFallbacks(now: number): void {
    this.pendingLoadFailureFallbacks.forEach((pending: PendingSearchEngineLoadFailureFallback, key: string): void => {
      if (pending.expiresAt <= now || pending.count <= 0) {
        this.pendingLoadFailureFallbacks.delete(key);
      }
    });
  }

  private evictOldestLoadFailureFallbackIfNeeded(): void {
    if (this.pendingLoadFailureFallbacks.size < MAX_PENDING_SEARCH_ENGINE_LOAD_FAILURE_FALLBACKS) {
      return;
    }
    let oldestKey = '';
    let oldestExpiresAt = Number.MAX_SAFE_INTEGER;
    this.pendingLoadFailureFallbacks.forEach((pending: PendingSearchEngineLoadFailureFallback, key: string): void => {
      if (pending.expiresAt < oldestExpiresAt) {
        oldestKey = key;
        oldestExpiresAt = pending.expiresAt;
      }
    });
    if (oldestKey.length > 0) {
      this.pendingLoadFailureFallbacks.delete(oldestKey);
    }
  }

  private buildLoadFailureFallbackKey(primarySearchEngineId: SearchEngineId, query: string): string {
    const normalizedEngineId = primarySearchEngineId.trim();
    const normalizedQuery = query.trim();
    if (normalizedEngineId.length <= 0 || normalizedQuery.length <= 0) {
      return '';
    }
    return `${normalizedEngineId}\n${normalizedQuery}`;
  }

  private buildFallbackMessageIfEnabled(
    settings: SearchEngineSettings,
    primaryEngine: SearchEngineRecord,
    fallbackEngine: SearchEngineRecord
  ): string {
    return this.buildFallbackNotice({
      primarySearchEngineId: primaryEngine.id,
      primarySearchEngineName: primaryEngine.name,
      fallbackSearchEngineId: fallbackEngine.id,
      fallbackSearchEngineName: fallbackEngine.name,
      noticeEnabled: settings.fallbackSearch.noticeEnabled !== false
    });
  }

  private resolveEngine(
    preferredEngineId: SearchEngineId,
    fallbackEngineId: SearchEngineId,
    availableSearchEngines: SearchEngineRecord[]
  ): SearchEngineRecord {
    const preferred = availableSearchEngines.find((engine: SearchEngineRecord): boolean => {
      return engine.id === preferredEngineId;
    });
    if (preferred !== undefined) {
      return preferred;
    }
    const fallback = availableSearchEngines.find((engine: SearchEngineRecord): boolean => {
      return engine.id === fallbackEngineId;
    });
    if (fallback !== undefined) {
      return fallback;
    }
    const defaultEngine = availableSearchEngines.find((engine: SearchEngineRecord): boolean => {
      return engine.id === DEFAULT_SEARCH_ENGINE_ID;
    });
    return defaultEngine ?? availableSearchEngines[0] ?? this.buildDefaultEngineRecord();
  }

  private resolveOptionalEngine(
    preferredEngineId: SearchEngineId,
    availableSearchEngines: SearchEngineRecord[]
  ): SearchEngineRecord | undefined {
    return availableSearchEngines.find((engine: SearchEngineRecord): boolean => {
      return engine.id === preferredEngineId;
    });
  }

  private looksLikeNavigation(value: string): boolean {
    const lower = value.trim().toLowerCase();
    return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('file://') ||
      lower.startsWith('aira://') ||
      looksLikeUrl(value);
  }

  private buildDefaultEngineRecord(): SearchEngineRecord {
    return {
      id: DEFAULT_SEARCH_ENGINE_ID,
      kind: 'built_in',
      name: 'Bing',
      searchUrlTemplate: 'https://www.bing.com/search?q={searchTerms}',
      homepageUrl: 'https://www.bing.com',
      availabilityProbeUrl: 'https://www.bing.com',
      isEditable: false,
      position: 0,
      createdAt: 0,
      updatedAt: 0
    };
  }

  private buildResult(
    rawInput: string,
    submittedText: string,
    resolvedUrl: string,
    intent: SearchEngineRoutingIntent,
    searchQuery: string,
    searchEngineId: SearchEngineId,
    primarySearchEngineId: SearchEngineId,
    fallbackApplied: boolean,
    fallbackMessage: string,
    httpFallbackUrl: string,
    availability?: SearchEngineAvailabilitySnapshot
  ): SearchEngineRoutingResult {
    return {
      rawInput: rawInput,
      submittedText: submittedText,
      resolvedUrl: resolvedUrl,
      intent: intent,
      searchQuery: searchQuery,
      searchEngineId: searchEngineId,
      primarySearchEngineId: primarySearchEngineId,
      fallbackApplied: fallbackApplied,
      fallbackMessage: fallbackMessage,
      httpFallbackUrl: httpFallbackUrl,
      availability: availability
    };
  }
}

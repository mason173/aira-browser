import { connection, http } from '@kit.NetworkKit';
import {
  BrowserExperimentSettings,
  SearchEngineRecord
} from '../../common/models/BrowserModels';
import {
  NativeHttpProxyResolution,
  NativeHttpProxyResolutionService
} from '../network/NativeHttpProxyResolutionService';

export type SearchEngineReachability = 'unknown' | 'reachable' | 'unreachable';

export interface SearchEngineAvailabilityProbeRequest {
  engine: SearchEngineRecord;
  experiments?: BrowserExperimentSettings;
  maxWaitMs?: number;
  successTtlMs?: number;
  failureTtlMs?: number;
  forceRefresh?: boolean;
}

export interface SearchEngineAvailabilitySnapshot {
  engineId: string;
  reachability: SearchEngineReachability;
  checkedAt: number;
  expiresAt: number;
  probeUrl: string;
  networkSignature: string;
  proxySignature: string;
  responseCode: number;
  durationMs: number;
  reason: string;
  proxyEnabled: boolean;
  proxyApplied: boolean;
}

interface SearchEngineAvailabilityProbeError {
  code?: number;
}

interface SearchEngineAvailabilityProbeContext {
  now: number;
  probeUrl: string;
  networkSignature: string;
  proxyResolution: NativeHttpProxyResolution;
  cacheKey: string;
  operationKey: string;
  generation: number;
}

const DEFAULT_SEARCH_ENGINE_PROBE_TIMEOUT_MS: number = 1000;
const DEFAULT_SEARCH_ENGINE_SUCCESS_TTL_MS: number = 8 * 60 * 1000;
const DEFAULT_SEARCH_ENGINE_FAILURE_TTL_MS: number = 2 * 60 * 1000;
const HTTP_REQUEST_TIMEOUT_ERROR_CODE: number = 2300028;
const CONCLUSIVE_SEARCH_ENGINE_TIMEOUT_MIN_MS: number = 900;

export class SearchEngineAvailabilityProbeService {
  private cache: Map<string, SearchEngineAvailabilitySnapshot> = new Map<string, SearchEngineAvailabilitySnapshot>();
  private inFlight: Map<string, Promise<SearchEngineAvailabilitySnapshot>> =
    new Map<string, Promise<SearchEngineAvailabilitySnapshot>>();
  private cacheGeneration: number = 0;
  private proxyResolutionService: NativeHttpProxyResolutionService;

  constructor(proxyResolutionService: NativeHttpProxyResolutionService = new NativeHttpProxyResolutionService()) {
    this.proxyResolutionService = proxyResolutionService;
  }

  invalidate(): void {
    this.cacheGeneration += 1;
    this.cache.clear();
  }

  resolveCachedAvailability(
    input: SearchEngineAvailabilityProbeRequest
  ): SearchEngineAvailabilitySnapshot | undefined {
    const context = this.buildProbeContext(input);
    const cached = this.cache.get(context.cacheKey);
    if (cached === undefined || cached.expiresAt <= context.now) {
      return undefined;
    }
    return cached;
  }

  async resolveAvailability(
    input: SearchEngineAvailabilityProbeRequest
  ): Promise<SearchEngineAvailabilitySnapshot> {
    const context = this.buildProbeContext(input);
    const cached = this.cache.get(context.cacheKey);
    if (input.forceRefresh !== true && cached !== undefined && cached.expiresAt > context.now) {
      return cached;
    }

    if (context.probeUrl.length <= 0) {
      return this.buildSnapshot(input.engine.id, '', context.networkSignature, context.proxyResolution, 'unknown', 0, 0,
        'missing_probe_url', context.now, input.failureTtlMs);
    }
    if (context.networkSignature === 'offline') {
      return this.buildSnapshot(
        input.engine.id,
        context.probeUrl,
        context.networkSignature,
        context.proxyResolution,
        'unknown',
        0,
        0,
        'no_default_network',
        context.now,
        input.failureTtlMs
      );
    }

    const pending = this.inFlight.get(context.operationKey);
    if (pending !== undefined) {
      return pending;
    }
    const operation = this.probe(
      input,
      context.probeUrl,
      context.networkSignature,
      context.proxyResolution,
      context.now
    ).then((snapshot: SearchEngineAvailabilitySnapshot): SearchEngineAvailabilitySnapshot => {
      if (this.cacheGeneration === context.generation) {
        this.cache.set(context.cacheKey, snapshot);
      }
      return snapshot;
    }).finally((): void => {
      this.inFlight.delete(context.operationKey);
    });
    this.inFlight.set(context.operationKey, operation);
    return operation;
  }

  private buildProbeContext(input: SearchEngineAvailabilityProbeRequest): SearchEngineAvailabilityProbeContext {
    const probeUrl = this.resolveProbeUrl(input.engine);
    const proxyResolution = this.proxyResolutionService.resolveFromExperimentSettings(input.experiments);
    const networkSignature = this.resolveNetworkSignature();
    const cacheKey = this.buildCacheKey(input.engine.id, probeUrl, networkSignature, proxyResolution.signature);
    const generation = this.cacheGeneration;
    return {
      now: Date.now(),
      probeUrl: probeUrl,
      networkSignature: networkSignature,
      proxyResolution: proxyResolution,
      cacheKey: cacheKey,
      operationKey: `${generation}:${cacheKey}`,
      generation: generation
    };
  }

  private async probe(
    input: SearchEngineAvailabilityProbeRequest,
    probeUrl: string,
    networkSignature: string,
    proxyResolution: NativeHttpProxyResolution,
    startedAt: number
  ): Promise<SearchEngineAvailabilitySnapshot> {
    const timeoutMs = this.resolveTimeout(input.maxWaitMs);
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.HEAD,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        usingCache: false,
        header: {
          'Accept': '*/*',
          'User-Agent': 'AiraBrowser/1.0'
        }
      };
      if (proxyResolution.usingProxy !== undefined) {
        options.usingProxy = proxyResolution.usingProxy;
      }
      const response = await request.request(probeUrl, options);
      const responseCode = response.responseCode;
      const reachable = this.isReachable(responseCode, input.engine.availabilityExpectedStatus);
      return this.buildSnapshot(
        input.engine.id,
        probeUrl,
        networkSignature,
        proxyResolution,
        reachable ? 'reachable' : 'unreachable',
        responseCode,
        Date.now() - startedAt,
        reachable ? 'http_reachable' : 'unexpected_status',
        startedAt,
        reachable ? input.successTtlMs : input.failureTtlMs
      );
    } catch (error) {
      const durationMs = Date.now() - startedAt;
      const timedOut = this.isTimeoutError(error);
      const timeoutIsConclusive = timedOut && timeoutMs >= CONCLUSIVE_SEARCH_ENGINE_TIMEOUT_MIN_MS;
      const reachability: SearchEngineReachability = timedOut && !timeoutIsConclusive ? 'unknown' : 'unreachable';
      const reason = timedOut ?
        (timeoutIsConclusive ? 'request_timeout' : 'request_timeout_indeterminate') :
        'request_failed';
      return this.buildSnapshot(
        input.engine.id,
        probeUrl,
        networkSignature,
        proxyResolution,
        reachability,
        0,
        durationMs,
        reason,
        startedAt,
        input.failureTtlMs
      );
    } finally {
      request.destroy();
    }
  }

  private isReachable(responseCode: number, expectedStatus: number | undefined): boolean {
    if (expectedStatus !== undefined) {
      return responseCode === expectedStatus;
    }
    return responseCode >= 200 && responseCode < 500;
  }

  private isTimeoutError(error: Object): boolean {
    const requestError = error as SearchEngineAvailabilityProbeError;
    return requestError.code === HTTP_REQUEST_TIMEOUT_ERROR_CODE;
  }

  private resolveProbeUrl(engine: SearchEngineRecord): string {
    const probeUrl = (engine.availabilityProbeUrl ?? '').trim();
    if (this.isHttpUrl(probeUrl)) {
      return probeUrl;
    }
    const homepageUrl = engine.homepageUrl.trim();
    if (this.isHttpUrl(homepageUrl)) {
      return homepageUrl;
    }
    return '';
  }

  private resolveNetworkSignature(): string {
    try {
      if (!connection.hasDefaultNetSync()) {
        return 'offline';
      }
      const net = connection.getDefaultNetSync();
      return `net:${String(net.netId)}`;
    } catch (_error) {
      return 'net:unknown';
    }
  }

  private buildSnapshot(
    engineId: string,
    probeUrl: string,
    networkSignature: string,
    proxyResolution: NativeHttpProxyResolution,
    reachability: SearchEngineReachability,
    responseCode: number,
    durationMs: number,
    reason: string,
    checkedAt: number,
    ttlMs: number | undefined
  ): SearchEngineAvailabilitySnapshot {
    return {
      engineId: engineId,
      reachability: reachability,
      checkedAt: checkedAt,
      expiresAt: checkedAt + this.resolveTtl(reachability, ttlMs),
      probeUrl: probeUrl,
      networkSignature: networkSignature,
      proxySignature: proxyResolution.signature,
      responseCode: responseCode,
      durationMs: durationMs,
      reason: reason,
      proxyEnabled: proxyResolution.enabled,
      proxyApplied: proxyResolution.usingProxy !== undefined
    };
  }

  private resolveTimeout(value: number | undefined): number {
    if (typeof value === 'number' && value > 0) {
      return Math.floor(value);
    }
    return DEFAULT_SEARCH_ENGINE_PROBE_TIMEOUT_MS;
  }

  private resolveTtl(reachability: SearchEngineReachability, value: number | undefined): number {
    if (typeof value === 'number' && value > 0) {
      return Math.floor(value);
    }
    if (reachability === 'reachable') {
      return DEFAULT_SEARCH_ENGINE_SUCCESS_TTL_MS;
    }
    return DEFAULT_SEARCH_ENGINE_FAILURE_TTL_MS;
  }

  private buildCacheKey(
    engineId: string,
    probeUrl: string,
    networkSignature: string,
    proxySignature: string
  ): string {
    return [engineId, probeUrl, networkSignature, proxySignature].join('|');
  }

  private isHttpUrl(value: string): boolean {
    const normalized = value.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }
}

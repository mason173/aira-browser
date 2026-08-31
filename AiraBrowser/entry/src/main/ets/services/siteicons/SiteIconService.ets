import http from '@ohos.net.http';
import urlUtils from '@ohos.url';
import { image } from '@kit.ImageKit';
import {
  SiteIconCachedFile,
  SiteIconCandidate,
  SiteIconCacheMetadata,
  SiteIconCachePruneOptions,
  SiteIconCachePruneResult,
  SiteIconDomainUriCacheEntry,
  SiteIconResolveOptions,
  SiteIconResult,
  SiteIconUriCacheEntry
} from '../../common/models/SiteIconModels';
import {
  SiteIconCachedDomainFile,
  SiteIconCacheStore
} from '../../data/siteicons/SiteIconCacheStore';
import { SiteIconDiscoveryService } from './SiteIconDiscoveryService';
import { SiteIconPixelMapCacheService } from './SiteIconPixelMapCacheService';
import { SiteIconResolutionPolicyService } from './SiteIconResolutionPolicyService';
import { SiteIconUpdateCenter } from './SiteIconUpdateCenter';

const MAX_ICON_BYTES: number = 512 * 1024;
const MAX_DOCUMENT_BYTES: number = 512 * 1024;
const MAX_MANIFEST_BYTES: number = 128 * 1024;
const ARKWEB_FAVICON_PACK_BUFFER_SIZE: number = 512 * 1024;
const ARKWEB_FAVICON_BASE_QUALITY_SCORE: number = 4000000;
const REQUEST_TIMEOUT_MS: number = 6000;
const MAX_MEMORY_CACHE_ENTRIES: number = 256;
const MAX_FAILED_DOMAIN_ENTRIES: number = 256;
const SITE_ICON_CACHE_MAX_FILES: number = 1200;
const SITE_ICON_CACHE_MAX_BYTES: number = 24 * 1024 * 1024;
const SITE_ICON_CACHE_PRUNE_INTERVAL_MS: number = 30 * 60 * 1000;
const TRANSIENT_FAILURE_TTL_MS: number = 5 * 60 * 1000;
const INVALID_PAYLOAD_FAILURE_TTL_MS: number = 24 * 60 * 60 * 1000;
const MAX_CURRENT_PAGE_ICON_FETCHES: number = 4;

interface SiteIconMemoryEntry {
  domain: string;
  result: SiteIconResult;
}

interface SiteIconInFlightEntry {
  domain: string;
  promise: Promise<SiteIconResult | undefined>;
}

interface SiteIconCurrentPageCandidateInFlightEntry {
  domain: string;
  promise: Promise<SiteIconResult | undefined>;
}

type SiteIconFailureReason = 'transient' | 'invalidPayload';

interface SiteIconFailedDomainEntry {
  domain: string;
  retryAfter: number;
}

interface SiteIconUrlDomainTarget {
  url: string;
  domain: string;
}

interface SiteIconImageDimensions {
  width: number;
  height: number;
}

interface SiteIconInspectedCandidate {
  candidate: SiteIconCandidate;
  dimensions: SiteIconImageDimensions;
}

export class SiteIconService {
  private static sharedMemoryCache: SiteIconMemoryEntry[] = [];
  private static sharedFailedDomains: SiteIconFailedDomainEntry[] = [];
  private static sharedInFlightEntries: SiteIconInFlightEntry[] = [];
  private static sharedCurrentPageCandidateInFlightEntries: SiteIconCurrentPageCandidateInFlightEntry[] = [];
  private static sharedPruneInFlight: boolean = false;
  private static sharedLastPruneStartedAt: number = 0;
  private discoveryService: SiteIconDiscoveryService = new SiteIconDiscoveryService();
  private resolutionPolicyService: SiteIconResolutionPolicyService = new SiteIconResolutionPolicyService();
  private cacheStore: SiteIconCacheStore = new SiteIconCacheStore();
  private pixelMapCacheService: SiteIconPixelMapCacheService = new SiteIconPixelMapCacheService();

  async resolve(url: string, options?: SiteIconResolveOptions): Promise<SiteIconResult | undefined> {
    const domain = this.extractDomainFromUrl(url);
    if (domain.length === 0) {
      return undefined;
    }

    const networkPolicy = options?.networkPolicy ?? 'remoteAllowed';
    const memory = this.peekResult(url);
    if (memory !== undefined) {
      return memory;
    }

    const cached = await this.resolveCachedIcon(domain);
    if (cached !== undefined) {
      this.setMemoryCache(domain, cached);
      this.prewarmResultPixelMap(cached);
      return cached;
    }

    if (networkPolicy === 'cacheOnly' || options?.privateMode === true ||
      !this.shouldProbeRemoteFavicon(url, domain)) {
      return cached ?? memory;
    }

    if (this.isFailedDomainActive(domain)) {
      return cached ?? memory;
    }

    const inFlight = SiteIconService.sharedInFlightEntries.find((item: SiteIconInFlightEntry) => item.domain === domain);
    if (inFlight !== undefined) {
      return inFlight.promise;
    }

    const promise = this.resolveRemoteIcon(url, domain, options?.allowRemoteFallback === true);
    SiteIconService.sharedInFlightEntries = SiteIconService.sharedInFlightEntries.concat([{
      domain: domain,
      promise: promise
    }]);

    try {
      return await promise;
    } finally {
      SiteIconService.sharedInFlightEntries = SiteIconService.sharedInFlightEntries
        .filter((item: SiteIconInFlightEntry) => item.domain !== domain);
    }
  }

  resolveDomain(url: string): string {
    return this.extractDomainFromUrl(url);
  }

  canCollect(url: string): boolean {
    const domain = this.extractDomainFromUrl(url);
    return domain.length > 0 && this.shouldProbeRemoteFavicon(url, domain);
  }

  async resolveCachedUris(urls: string[]): Promise<SiteIconUriCacheEntry[]> {
    const entries: SiteIconUriCacheEntry[] = [];
    const targets: SiteIconUrlDomainTarget[] = [];
    const domains: string[] = [];
    for (let index = 0; index < urls.length; index += 1) {
      const url = urls[index].trim();
      const domain = this.extractDomainFromUrl(url);
      if (domain.length === 0) {
        continue;
      }
      targets.push({
        url: url,
        domain: domain
      });
      if (domains.indexOf(domain) < 0) {
        domains.push(domain);
      }
    }

    const domainEntries = await this.resolveCachedUrisByDomains(domains);
    for (let index = 0; index < targets.length; index += 1) {
      const target = targets[index];
      const domainEntry = domainEntries.find((item: SiteIconDomainUriCacheEntry) => item.domain === target.domain);
      const uri = domainEntry === undefined ? '' : domainEntry.uri;
      if (uri.length === 0) {
        continue;
      }
      entries.push({
        url: target.url,
        uri: uri
      });
    }
    return entries;
  }

  async ingestArkWebFavicon(
    url: string,
    favicon: image.PixelMap
  ): Promise<SiteIconResult | undefined> {
    const domain = this.extractDomainFromUrl(url);
    if (domain.length === 0 || !this.shouldProbeRemoteFavicon(url, domain)) {
      return undefined;
    }

    try {
      const dimensions = this.resolveArkWebFaviconDimensions(favicon);
      const arkWebCandidate: SiteIconCandidate = {
        url: `arkweb://${domain}/favicon.png`,
        source: 'arkweb',
        size: Math.min(dimensions.width, dimensions.height),
        scalable: false,
        purpose: ''
      };
      const current = this.peekResultByDomain(domain) ?? await this.resolveCachedIcon(domain);
      if (!this.resolutionPolicyService.shouldReplaceCachedIconWithCandidate(current, arkWebCandidate)) {
        return current;
      }
      const data = await this.packFaviconPixelMap(favicon);
      if (data.byteLength === 0 || data.byteLength > MAX_ICON_BYTES || !this.cacheStore.isLikelyImagePayload(data)) {
        this.rememberFailedDomain(domain, 'invalidPayload');
        return undefined;
      }
      const cached = await this.cacheStore.writeArkWebFavicon(
        domain,
        data,
        this.resolveArkWebFaviconQualityScore(dimensions),
        dimensions.width,
        dimensions.height
      );
      const result = this.createCachedResult(domain, cached);
      if (cached.cacheState === 'network') {
        this.pixelMapCacheService.invalidateIconUri(result.uri);
      }
      this.setMemoryCache(domain, result);
      this.prewarmResultPixelMap(result);
      this.publishUpdatedIcon(result);
      this.pruneCacheSoon();
      this.clearFailedDomain(domain);
      return result;
    } catch (_error) {
      return undefined;
    }
  }

  async ingestPageCandidates(
    url: string,
    candidates: SiteIconCandidate[]
  ): Promise<SiteIconResult | undefined> {
    const domain = this.extractDomainFromUrl(url);
    if (domain.length === 0 || !this.shouldProbeRemoteFavicon(url, domain)) {
      return undefined;
    }
    return await this.runSerializedCurrentPageCandidateWrite(domain, () => (
      this.ingestPageCandidatesInternal(url, domain, candidates)
    ));
  }

  private async ingestPageCandidatesInternal(
    url: string,
    domain: string,
    candidates: SiteIconCandidate[]
  ): Promise<SiteIconResult | undefined> {
    const sortedCandidates = this.resolutionPolicyService.rankCandidates(candidates);
    const current = this.peekResultByDomain(domain) ?? await this.resolveCachedIcon(domain);
    let fetchCount = 0;
    let bestInspected: SiteIconInspectedCandidate | undefined = undefined;
    let bestData: ArrayBuffer | undefined = undefined;
    for (let index = 0; index < sortedCandidates.length; index += 1) {
      const candidate = sortedCandidates[index];
      if (!this.resolutionPolicyService.shouldInspectCandidate(current, candidate)) {
        continue;
      }
      if (fetchCount >= MAX_CURRENT_PAGE_ICON_FETCHES) {
        break;
      }
      fetchCount += 1;
      const data = await this.fetchIcon(candidate.url, true, url);
      if (data.byteLength === 0) {
        continue;
      }
      const inspected = await this.inspectFetchedCandidate(candidate, data);
      if (inspected === undefined ||
        !this.resolutionPolicyService.shouldReplaceCachedIconWithCandidate(current, inspected.candidate)) {
        continue;
      }
      if (bestInspected === undefined ||
        this.resolutionPolicyService.scoreCandidate(inspected.candidate) >
          this.resolutionPolicyService.scoreCandidate(bestInspected.candidate)) {
        bestInspected = inspected;
        bestData = data;
      }
    }
    if (bestInspected === undefined || bestData === undefined) {
      return current;
    }
    const latest = this.peekResultByDomain(domain) ?? await this.resolveCachedIcon(domain);
    if (!this.resolutionPolicyService.shouldReplaceCachedIconWithCandidate(latest, bestInspected.candidate)) {
      return latest;
    }
    const resolvedCandidate = bestInspected.candidate;
    const cached = await this.cacheStore.writeIcon(
      domain,
      this.cacheStore.resolveIconExtension(resolvedCandidate.url),
      bestData,
      this.createCacheMetadata(
        resolvedCandidate,
        this.resolutionPolicyService.scoreCandidate(resolvedCandidate),
        bestInspected.dimensions
      ),
      true
    );
    const result = cached.cacheState === 'network'
      ? this.createNetworkResult(domain, resolvedCandidate, cached)
      : this.createCachedResult(domain, cached);
    if (result.cacheState === 'network') {
      this.pixelMapCacheService.invalidateIconUri(result.uri);
    }
    this.setMemoryCache(domain, result);
    this.prewarmResultPixelMap(result);
    this.publishUpdatedIcon(result);
    if (result.cacheState === 'network') {
      this.pruneCacheSoon();
    }
    this.clearFailedDomain(domain);
    return result;
  }

  async refresh(url: string, options?: SiteIconResolveOptions): Promise<SiteIconResult | undefined> {
    const domain = this.extractDomainFromUrl(url);
    if (domain.length === 0 || options?.privateMode === true || !this.shouldProbeRemoteFavicon(url, domain)) {
      return undefined;
    }

    this.clearFailedDomain(domain);

    const inFlight = SiteIconService.sharedInFlightEntries.find((item: SiteIconInFlightEntry) => item.domain === domain);
    if (inFlight !== undefined) {
      return inFlight.promise;
    }

    const promise = this.resolveRemoteIcon(url, domain, options?.allowRemoteFallback === true, false);
    SiteIconService.sharedInFlightEntries = SiteIconService.sharedInFlightEntries.concat([{
      domain: domain,
      promise: promise
    }]);

    try {
      return await promise;
    } finally {
      SiteIconService.sharedInFlightEntries = SiteIconService.sharedInFlightEntries
        .filter((item: SiteIconInFlightEntry) => item.domain !== domain);
    }
  }

  async prune(): Promise<SiteIconCachePruneResult> {
    const pruneOptions: SiteIconCachePruneOptions = {
      maxFiles: SITE_ICON_CACHE_MAX_FILES,
      maxBytes: SITE_ICON_CACHE_MAX_BYTES
    };
    return await this.cacheStore.pruneCache(pruneOptions);
  }

  peekUri(url: string): string {
    const result = this.peekResult(url);
    return result === undefined ? '' : result.uri;
  }

  async readCachedUri(url: string): Promise<string> {
    const domain = this.extractDomainFromUrl(url);
    if (domain.length === 0) {
      return '';
    }
    const result = await this.readCachedResultByDomain(domain);
    return result === undefined ? '' : result.uri;
  }

  private peekResult(url: string): SiteIconResult | undefined {
    const domain = this.extractDomainFromUrl(url);
    if (domain.length === 0) {
      return undefined;
    }
    return this.peekResultByDomain(domain);
  }

  private peekResultByDomain(domain: string): SiteIconResult | undefined {
    const normalizedDomain = this.normalizeDomain(domain);
    if (normalizedDomain.length === 0) {
      return undefined;
    }
    const index = SiteIconService.sharedMemoryCache
      .findIndex((entry: SiteIconMemoryEntry) => entry.domain === normalizedDomain);
    if (index < 0) {
      return undefined;
    }
    const item = SiteIconService.sharedMemoryCache[index];
    if (index < SiteIconService.sharedMemoryCache.length - 1) {
      SiteIconService.sharedMemoryCache = SiteIconService.sharedMemoryCache
        .filter((entry: SiteIconMemoryEntry) => entry.domain !== normalizedDomain)
        .concat([item]);
    }
    return item.result;
  }

  private async readCachedResultByDomain(domain: string): Promise<SiteIconResult | undefined> {
    const normalizedDomain = this.normalizeDomain(domain);
    if (normalizedDomain.length === 0) {
      return undefined;
    }
    const memory = this.peekResultByDomain(normalizedDomain);
    if (memory !== undefined) {
      return memory;
    }
    const cached = await this.resolveCachedIcon(normalizedDomain);
    if (cached !== undefined) {
      this.setMemoryCache(normalizedDomain, cached);
      this.prewarmResultPixelMap(cached);
      return cached;
    }
    return undefined;
  }

  private async resolveCachedUrisByDomains(domains: string[]): Promise<SiteIconDomainUriCacheEntry[]> {
    const normalizedDomains = this.normalizeDomains(domains);
    if (normalizedDomains.length === 0) {
      return [];
    }

    const entries: SiteIconDomainUriCacheEntry[] = [];
    const missingDomains: string[] = [];
    for (let index = 0; index < normalizedDomains.length; index += 1) {
      const domain = normalizedDomains[index];
      const memory = this.peekResultByDomain(domain);
      if (memory !== undefined) {
        entries.push({
          domain: domain,
          uri: memory.uri
        });
        continue;
      }
      missingDomains.push(domain);
    }

    const cachedFiles = await this.cacheStore.findCachedIconsByDomains(missingDomains);
    for (let index = 0; index < cachedFiles.length; index += 1) {
      const cachedFile = cachedFiles[index];
      const result = this.createCachedResult(cachedFile.domain, cachedFile.file);
      this.setMemoryCache(cachedFile.domain, result);
      entries.push({
        domain: cachedFile.domain,
        uri: result.uri
      });
    }
    return entries;
  }

  private async resolveCachedIcon(domain: string): Promise<SiteIconResult | undefined> {
    const cached = await this.cacheStore.findCachedIcon(domain);
    if (cached !== undefined) {
      return this.createCachedResult(domain, cached);
    }
    return undefined;
  }

  private async resolveRemoteIcon(
    inputUrl: string,
    domain: string,
    allowRemoteFallback: boolean,
    useHttpCache: boolean = true
  ): Promise<SiteIconResult | undefined> {
    const candidates = await this.buildFaviconCandidates(inputUrl, domain, allowRemoteFallback, useHttpCache);
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index];
      const qualityScore = this.resolutionPolicyService.scoreCandidate(candidate);
      const existingCached = await this.resolveCachedIcon(domain);
      const shouldTryCandidate = this.resolutionPolicyService.shouldInspectCandidate(existingCached, candidate);
      if (existingCached !== undefined && existingCached.qualityScore > qualityScore && !shouldTryCandidate) {
        this.setMemoryCache(domain, existingCached);
        this.prewarmResultPixelMap(existingCached);
        return existingCached;
      }

      const data = await this.fetchIcon(candidate.url, useHttpCache);
      if (data.byteLength === 0) {
        continue;
      }
      const inspected = await this.inspectFetchedCandidate(candidate, data);
      if (inspected === undefined) {
        continue;
      }
      const resolvedCandidate = inspected.candidate;
      const resolvedQualityScore = this.resolutionPolicyService.scoreCandidate(resolvedCandidate);
      const shouldReplaceExisting = this.resolutionPolicyService
        .shouldReplaceCachedIconWithCandidate(existingCached, resolvedCandidate);
      if (!shouldReplaceExisting) {
        continue;
      }

      const cached = await this.cacheStore.writeIcon(
        domain,
        this.cacheStore.resolveIconExtension(resolvedCandidate.url),
        data,
        this.createCacheMetadata(resolvedCandidate, resolvedQualityScore, inspected.dimensions),
        true
      );
      const result = cached.cacheState === 'network'
        ? this.createNetworkResult(domain, resolvedCandidate, cached)
        : this.createCachedResult(domain, cached);
      if (result.cacheState === 'network') {
        this.pixelMapCacheService.invalidateIconUri(result.uri);
      }
      this.setMemoryCache(domain, result);
      this.prewarmResultPixelMap(result);
      this.publishUpdatedIcon(result);
      if (result.cacheState === 'network') {
        this.pruneCacheSoon();
      }
      return result;
    }

    const retainedCached = await this.resolveCachedIcon(domain);
    if (retainedCached !== undefined) {
      this.setMemoryCache(domain, retainedCached);
      this.prewarmResultPixelMap(retainedCached);
      return retainedCached;
    }

    this.rememberFailedDomain(domain, 'transient');
    return undefined;
  }

  private async buildFaviconCandidates(
    inputUrl: string,
    domain: string,
    allowRemoteFallback: boolean,
    useHttpCache: boolean = true
  ): Promise<SiteIconCandidate[]> {
    const safeDomain = domain.trim().toLowerCase();
    const pageUrl = this.toNavigableUrl(inputUrl.trim().length > 0 ? inputUrl : `https://${safeDomain}`);
    const documentCandidates = await this.discoverDocumentCandidates(pageUrl, useHttpCache);
    const fallbackCandidates = this.discoveryService.buildFallbackCandidates(safeDomain, allowRemoteFallback);
    return this.resolutionPolicyService.rankCandidates(documentCandidates.concat(fallbackCandidates));
  }

  private async discoverDocumentCandidates(
    pageUrl: string,
    useHttpCache: boolean
  ): Promise<SiteIconCandidate[]> {
    const html = await this.fetchText(pageUrl, MAX_DOCUMENT_BYTES, useHttpCache);
    if (html.length === 0) {
      return [];
    }

    const documentDiscovery = this.discoveryService.discoverFromDocument(pageUrl, html);
    let candidates = documentDiscovery.iconCandidates;
    for (let index = 0; index < documentDiscovery.manifestUrls.length; index += 1) {
      const manifestUrl = documentDiscovery.manifestUrls[index];
      const manifestPayload = await this.fetchText(manifestUrl, MAX_MANIFEST_BYTES, useHttpCache);
      if (manifestPayload.length === 0) {
        continue;
      }
      candidates = candidates.concat(this.discoveryService.discoverFromManifest(manifestUrl, manifestPayload));
    }
    return this.resolutionPolicyService.rankCandidates(candidates);
  }

  private async fetchText(url: string, maxBytes: number, useHttpCache: boolean = true): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        usingCache: useHttpCache,
        header: {
          'Accept': 'text/html,application/xhtml+xml,application/manifest+json,application/json,*/*;q=0.8',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });

      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return '';
      }
      if (response.result.length === 0 || response.result.length > maxBytes) {
        return '';
      }
      return response.result;
    } catch (_error) {
      return '';
    } finally {
      request.destroy();
    }
  }

  private async fetchIcon(
    url: string,
    useHttpCache: boolean = true,
    referer: string = ''
  ): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Accept': 'image/png,image/webp,image/svg+xml,image/jpeg,image/x-icon,image/*;q=0.8,*/*;q=0.4',
        'User-Agent': 'AiraBrowser/1.0'
      };
      if (referer.trim().length > 0) {
        headers['Referer'] = referer.trim();
      }
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS,
        usingCache: useHttpCache,
        header: headers
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        return new ArrayBuffer(0);
      }
      if (!(response.result instanceof ArrayBuffer)) {
        return new ArrayBuffer(0);
      }
      if (response.result.byteLength === 0 || response.result.byteLength > MAX_ICON_BYTES) {
        return new ArrayBuffer(0);
      }
      if (!this.cacheStore.isLikelyImagePayload(response.result)) {
        return new ArrayBuffer(0);
      }
      return response.result;
    } catch (_error) {
      return new ArrayBuffer(0);
    } finally {
      request.destroy();
    }
  }

  private async packFaviconPixelMap(favicon: image.PixelMap): Promise<ArrayBuffer> {
    const packer = image.createImagePacker();
    try {
      return await packer.packToData(favicon, {
        format: 'image/png',
        quality: 100,
        bufferSize: ARKWEB_FAVICON_PACK_BUFFER_SIZE
      });
    } finally {
      try {
        await packer.release();
      } catch (_error) {
      }
    }
  }

  private resolveArkWebFaviconQualityScore(dimensions: SiteIconImageDimensions): number {
    const edge = Math.min(dimensions.width, dimensions.height);
    return ARKWEB_FAVICON_BASE_QUALITY_SCORE + edge * 1000;
  }

  private resolveArkWebFaviconDimensions(favicon: image.PixelMap): SiteIconImageDimensions {
    try {
      const imageInfo = favicon.getImageInfoSync();
      const width = Math.max(1, Math.floor(imageInfo.size.width));
      const height = Math.max(1, Math.floor(imageInfo.size.height));
      return {
        width: width,
        height: height
      };
    } catch (_error) {
      return {
        width: 0,
        height: 0
      };
    }
  }

  private async inspectFetchedCandidate(
    candidate: SiteIconCandidate,
    data: ArrayBuffer
  ): Promise<SiteIconInspectedCandidate | undefined> {
    if (this.cacheStore.isLikelySvgPayload(data)) {
      return {
        candidate: {
          url: candidate.url,
          source: candidate.source,
          size: 1024,
          scalable: true,
          purpose: candidate.purpose
        },
        dimensions: {
          width: 1024,
          height: 1024
        }
      };
    }

    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(data);
      const imageInfo = await imageSource.getImageInfo();
      const width = Math.max(0, Math.floor(imageInfo.size.width));
      const height = Math.max(0, Math.floor(imageInfo.size.height));
      if (width <= 0 || height <= 0) {
        return undefined;
      }
      return {
        candidate: {
          url: candidate.url,
          source: candidate.source,
          size: Math.min(width, height),
          scalable: false,
          purpose: candidate.purpose
        },
        dimensions: {
          width: width,
          height: height
        }
      };
    } catch (_error) {
      return undefined;
    } finally {
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {
        });
      }
    }
  }

  private createCachedResult(domain: string, cached: SiteIconCachedFile): SiteIconResult {
    return {
      uri: cached.uri,
      domain: domain,
      source: cached.source ?? 'rootIcon',
      iconUrl: cached.iconUrl ?? '',
      cacheState: cached.cacheState,
      qualityScore: cached.qualityScore ?? 0,
      width: cached.width ?? 0,
      height: cached.height ?? 0
    };
  }

  private createNetworkResult(domain: string, candidate: SiteIconCandidate, cached: SiteIconCachedFile): SiteIconResult {
    return {
      uri: cached.uri,
      domain: domain,
      source: candidate.source,
      iconUrl: candidate.url,
      cacheState: 'network',
      qualityScore: this.resolutionPolicyService.scoreCandidate(candidate),
      width: cached.width ?? 0,
      height: cached.height ?? 0
    };
  }

  private createCacheMetadata(
    candidate: SiteIconCandidate,
    qualityScore: number,
    dimensions: SiteIconImageDimensions
  ): SiteIconCacheMetadata {
    return {
      source: candidate.source,
      iconUrl: candidate.url,
      extension: this.cacheStore.resolveIconExtension(candidate.url),
      qualityScore: qualityScore,
      width: dimensions.width,
      height: dimensions.height,
      updatedAt: Date.now(),
      lastAccessedAt: Date.now()
    };
  }

  private prewarmResultPixelMap(result: SiteIconResult): void {
    void this.pixelMapCacheService.prewarmIconUri(result.uri);
  }

  private extractDomainFromUrl(url: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(this.toNavigableUrl(url.trim()));
      return this.normalizeDomain(parsed.hostname);
    } catch (_error) {
      return '';
    }
  }

  private toNavigableUrl(input: string): string {
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(input)) {
      return input;
    }
    return `https://${input}`;
  }

  private shouldProbeRemoteFavicon(url: string, domain: string): boolean {
    try {
      const parsed = urlUtils.URL.parseURL(this.toNavigableUrl(url.trim()));
      const protocol = parsed.protocol.toLowerCase();
      if (protocol !== 'http:' && protocol !== 'https:') {
        return false;
      }
      return !this.isLikelyLocalHost(domain);
    } catch (_error) {
      return false;
    }
  }

  private isLikelyLocalHost(hostname: string): boolean {
    const host = hostname.trim().toLowerCase();
    if (host === 'localhost' || host.endsWith('.localhost')) {
      return true;
    }
    if (host.startsWith('127.') || host.startsWith('10.') || host.startsWith('192.168.')) {
      return true;
    }
    if (/^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(host)) {
      return true;
    }
    return host === '::1' || host.length === 0;
  }

  private normalizeDomain(domain: string): string {
    let normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    return normalized;
  }

  private normalizeDomains(domains: string[]): string[] {
    const normalizedDomains: string[] = [];
    for (let index = 0; index < domains.length; index += 1) {
      const domain = this.normalizeDomain(domains[index]);
      if (domain.length === 0 || normalizedDomains.indexOf(domain) >= 0) {
        continue;
      }
      normalizedDomains.push(domain);
    }
    return normalizedDomains;
  }

  private setMemoryCache(domain: string, result: SiteIconResult): void {
    const entry: SiteIconMemoryEntry = {
      domain: domain,
      result: {
        uri: result.uri,
        domain: result.domain,
        source: result.source,
        iconUrl: result.iconUrl ?? '',
        cacheState: 'memory',
        qualityScore: result.qualityScore,
        width: result.width,
        height: result.height
      }
    };
    const nextCache = SiteIconService.sharedMemoryCache
      .filter((entry: SiteIconMemoryEntry) => entry.domain !== domain)
      .concat([entry]);
    SiteIconService.sharedMemoryCache = nextCache.slice(Math.max(0, nextCache.length - MAX_MEMORY_CACHE_ENTRIES));
  }

  private async runSerializedCurrentPageCandidateWrite(
    domain: string,
    task: () => Promise<SiteIconResult | undefined>
  ): Promise<SiteIconResult | undefined> {
    while (true) {
      const existing = SiteIconService.sharedCurrentPageCandidateInFlightEntries
        .find((entry: SiteIconCurrentPageCandidateInFlightEntry) => entry.domain === domain);
      if (existing === undefined) {
        break;
      }
      await existing.promise.catch((_error: Error) => undefined);
    }
    let serializedPromise: Promise<SiteIconResult | undefined>;
    serializedPromise = task().finally(() => {
      SiteIconService.sharedCurrentPageCandidateInFlightEntries =
        SiteIconService.sharedCurrentPageCandidateInFlightEntries
          .filter((entry: SiteIconCurrentPageCandidateInFlightEntry) => entry.promise !== serializedPromise);
    });
    SiteIconService.sharedCurrentPageCandidateInFlightEntries =
      SiteIconService.sharedCurrentPageCandidateInFlightEntries.concat([{
        domain: domain,
        promise: serializedPromise
      }]);
    return await serializedPromise;
  }

  private publishUpdatedIcon(result: SiteIconResult): void {
    if (result.cacheState !== 'network') {
      return;
    }
    SiteIconUpdateCenter.publish({
      domain: result.domain,
      uri: result.uri,
      source: result.source,
      cacheState: result.cacheState,
      updatedAt: Date.now()
    });
  }

  private isFailedDomainActive(domain: string): boolean {
    const now = Date.now();
    const entry = SiteIconService.sharedFailedDomains
      .find((item: SiteIconFailedDomainEntry) => item.domain === domain);
    if (entry === undefined) {
      return false;
    }
    if (entry.retryAfter > now) {
      return true;
    }
    this.clearFailedDomain(domain);
    return false;
  }

  private rememberFailedDomain(domain: string, reason: SiteIconFailureReason): void {
    if (domain.length === 0) {
      return;
    }
    const now = Date.now();
    const ttl = reason === 'invalidPayload' ? INVALID_PAYLOAD_FAILURE_TTL_MS : TRANSIENT_FAILURE_TTL_MS;
    const nextDomains = SiteIconService.sharedFailedDomains
      .filter((item: SiteIconFailedDomainEntry) => item.domain !== domain && item.retryAfter > now)
      .concat([{
        domain: domain,
        retryAfter: now + ttl
      }]);
    SiteIconService.sharedFailedDomains = nextDomains.slice(Math.max(0, nextDomains.length - MAX_FAILED_DOMAIN_ENTRIES));
  }

  private clearFailedDomain(domain: string): void {
    SiteIconService.sharedFailedDomains = SiteIconService.sharedFailedDomains
      .filter((item: SiteIconFailedDomainEntry) => item.domain !== domain);
  }

  private pruneCacheSoon(): void {
    const now = Date.now();
    if (SiteIconService.sharedPruneInFlight ||
      now - SiteIconService.sharedLastPruneStartedAt < SITE_ICON_CACHE_PRUNE_INTERVAL_MS) {
      return;
    }
    SiteIconService.sharedPruneInFlight = true;
    SiteIconService.sharedLastPruneStartedAt = now;
    void this.prune().finally(() => {
      SiteIconService.sharedPruneInFlight = false;
    });
  }
}

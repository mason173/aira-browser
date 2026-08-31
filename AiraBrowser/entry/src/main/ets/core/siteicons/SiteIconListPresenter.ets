import { image } from '@kit.ImageKit';
import { SiteIconListResolutionPolicy } from '../../common/models/SiteIconModels';
import { SiteIconService } from '../../services/siteicons/SiteIconService';
import { SiteIconPixelMapCacheService } from '../../services/siteicons/SiteIconPixelMapCacheService';
import {
  SiteIconDomainUpdateBinder,
  SiteIconDomainUpdateTarget
} from './SiteIconDomainUpdateBinder';
import {
  SiteIconPrewarmCoordinator,
  SiteIconPrewarmResolvedIcon,
  SiteIconPrewarmTarget
} from './SiteIconPrewarmCoordinator';

export interface SiteIconListTarget {
  id: string;
  url: string;
  domain?: string;
  initialIconUri?: string;
}

export interface SiteIconListResolvedIcon {
  id: string;
  domain: string;
  uri: string;
  pixelMap?: image.PixelMap;
  sourceRevision: number;
}

export interface SiteIconListRenderState {
  id: string;
  domain: string;
  path: string;
  pixelMap?: image.PixelMap;
  sourceRevision: number;
}

export interface SiteIconListResolveOptions {
  resolutionPolicy?: SiteIconListResolutionPolicy;
  shouldSkipTarget?: (target: SiteIconListTarget) => boolean;
}

export type SiteIconListTargetProvider = () => SiteIconListTarget[];
export type SiteIconListResolvedHandler = (result: SiteIconListResolvedIcon) => void;

interface SiteIconListSourceRevisionEntry {
  domain: string;
  uri: string;
  revision: number;
  domainUpdateSequence: number;
}

interface SiteIconListPixelMapRecoveryEntry {
  key: string;
  promise: Promise<SiteIconListPixelMapRecoveryAsset | undefined>;
}

interface SiteIconListPixelMapRecoveryAsset {
  domain: string;
  uri: string;
  pixelMap: image.PixelMap;
  sourceRevision: number;
}

const SITE_ICON_LIST_PIXEL_MAP_DECODE_SIZE: number = 72;

export class SiteIconListPresenter {
  private readonly siteIconService: SiteIconService;
  private readonly pixelMapCacheService: SiteIconPixelMapCacheService;
  private readonly prewarmCoordinator: SiteIconPrewarmCoordinator;
  private readonly domainUpdateBinder: SiteIconDomainUpdateBinder;
  private sourceRevisionEntries: SiteIconListSourceRevisionEntry[] = [];
  private pixelMapRecoveryEntries: SiteIconListPixelMapRecoveryEntry[] = [];
  private failedPixelMapRecoveryKeys: string[] = [];
  private pixelMapRecoveryGeneration: number = 0;

  constructor(
    siteIconService: SiteIconService = new SiteIconService(),
    pixelMapCacheService: SiteIconPixelMapCacheService = new SiteIconPixelMapCacheService()
  ) {
    this.siteIconService = siteIconService;
    this.pixelMapCacheService = pixelMapCacheService;
    this.prewarmCoordinator = new SiteIconPrewarmCoordinator(this.siteIconService);
    this.domainUpdateBinder = new SiteIconDomainUpdateBinder(this.siteIconService);
  }

  bindDomainUpdates(
    provideTargets: SiteIconListTargetProvider,
    onResolved: SiteIconListResolvedHandler
  ): void {
    this.domainUpdateBinder.subscribe(
      (): SiteIconDomainUpdateTarget[] => this.toDomainUpdateTargets(provideTargets()),
      (target: SiteIconDomainUpdateTarget, uri: string, updateSequence: number): void => {
        const listTarget: SiteIconListTarget = {
          id: target.id,
          url: target.url,
          domain: target.domain
        };
        onResolved(this.toResolvedIcon(listTarget, uri, true, updateSequence));
      }
    );
  }

  resolveTargets(
    targets: SiteIconListTarget[],
    onResolved: SiteIconListResolvedHandler,
    options?: SiteIconListResolveOptions
  ): void {
    const resolutionPolicy = options?.resolutionPolicy ?? 'remoteAllowed';
    const normalizedTargets = this.normalizeTargets(targets);
    const prewarmTargets: SiteIconPrewarmTarget[] = [];
    normalizedTargets.forEach((target: SiteIconListTarget) => {
      if (options?.shouldSkipTarget !== undefined && options.shouldSkipTarget(target)) {
        return;
      }
      const initialIconUri = (target.initialIconUri ?? '').trim();
      if (initialIconUri.length > 0) {
        onResolved(this.toResolvedIcon(target, initialIconUri));
        return;
      }
      const memoryUri = this.siteIconService.peekUri(target.domain ?? target.url);
      if (memoryUri.length > 0) {
        onResolved(this.toResolvedIcon(target, memoryUri));
        return;
      }
      if (resolutionPolicy === 'memoryOnly') {
        return;
      }
      prewarmTargets.push({
        id: target.id,
        url: target.url,
        domain: target.domain
      });
    });

    if (prewarmTargets.length === 0) {
      return;
    }
    this.prewarmCoordinator.resolveVisibleTargets(
      prewarmTargets,
      (result: SiteIconPrewarmResolvedIcon): void => {
        if (result.uri.length <= 0) {
          return;
        }
        const listTarget: SiteIconListTarget = {
          id: result.id,
          url: result.url,
          domain: result.domain
        };
        onResolved(this.toResolvedIcon(listTarget, result.uri));
      },
      {
        resolutionPolicy: resolutionPolicy
      }
    );
  }

  resolvePixelMapAfterUriFailure(
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number,
    onResolved: SiteIconListResolvedHandler
  ): void {
    const normalizedTarget = this.normalizeTargets([target])[0];
    if (normalizedTarget === undefined) {
      return;
    }
    const normalizedUri = currentUri.trim();
    const revision = sourceRevision > 0
      ? Math.floor(sourceRevision)
      : this.resolveSourceRevision(normalizedTarget.domain ?? '', normalizedUri, false);
    const recoveryKey = this.buildPixelMapRecoveryKey(
      normalizedTarget.domain ?? '',
      normalizedUri,
      revision
    );
    if (this.failedPixelMapRecoveryKeys.indexOf(recoveryKey) >= 0) {
      return;
    }
    const recoveryGeneration = this.pixelMapRecoveryGeneration;
    const inFlight = this.pixelMapRecoveryEntries
      .find((entry: SiteIconListPixelMapRecoveryEntry) => entry.key === recoveryKey);
    if (inFlight !== undefined) {
      this.applyRecoveryResult(inFlight.promise, normalizedTarget, recoveryGeneration, onResolved);
      return;
    }

    const promise = this.resolvePixelMapRecovery(normalizedTarget, normalizedUri)
      .then((result: SiteIconListPixelMapRecoveryAsset | undefined) => {
        if (result === undefined) {
          this.rememberFailedPixelMapRecovery(recoveryKey);
        }
        return result;
      })
      .catch((_error: Error) => {
        this.rememberFailedPixelMapRecovery(recoveryKey);
        return undefined;
      })
      .finally(() => {
        this.pixelMapRecoveryEntries = this.pixelMapRecoveryEntries
          .filter((entry: SiteIconListPixelMapRecoveryEntry) => entry.key !== recoveryKey);
      });
    this.pixelMapRecoveryEntries = this.pixelMapRecoveryEntries.concat([{
      key: recoveryKey,
      promise: promise
    }]);
    this.applyRecoveryResult(promise, normalizedTarget, recoveryGeneration, onResolved);
  }

  applyResolvedIcon(
    states: SiteIconListRenderState[],
    result: SiteIconListResolvedIcon
  ): SiteIconListRenderState[] {
    const existing = states.find((item: SiteIconListRenderState) => item.id === result.id);
    const resultDomain = this.normalizeDomain(result.domain);
    const isSameDomain = existing !== undefined && existing.domain === resultDomain;
    if (isSameDomain && existing !== undefined && existing.sourceRevision > result.sourceRevision) {
      return states;
    }
    const retainedPixelMap = result.pixelMap ?? (
      isSameDomain && existing !== undefined &&
      existing.path === result.uri &&
      existing.sourceRevision === result.sourceRevision
        ? existing.pixelMap
        : undefined
    );
    if (existing !== undefined &&
      existing.domain === resultDomain &&
      existing.path === result.uri &&
      existing.pixelMap === retainedPixelMap &&
      existing.sourceRevision === result.sourceRevision) {
      return states;
    }
    return states
      .filter((item: SiteIconListRenderState) => item.id !== result.id)
      .concat([{
        id: result.id,
        domain: resultDomain,
        path: result.uri,
        pixelMap: retainedPixelMap,
        sourceRevision: result.sourceRevision
      }]);
  }

  hasResolvedIcon(states: SiteIconListRenderState[], target: SiteIconListTarget): boolean {
    const normalizedTarget = this.normalizeTargets([target])[0];
    if (normalizedTarget === undefined) {
      return false;
    }
    return states.some((item: SiteIconListRenderState) =>
      item.id === normalizedTarget.id && item.domain === normalizedTarget.domain);
  }

  getResolvedIconPath(states: SiteIconListRenderState[], id: string): string {
    return states.find((item: SiteIconListRenderState) => item.id === id)?.path ?? '';
  }

  dispose(): void {
    this.domainUpdateBinder.dispose();
    this.prewarmCoordinator.cancel();
    this.cancelPixelMapRecovery();
  }

  private toDomainUpdateTargets(targets: SiteIconListTarget[]): SiteIconDomainUpdateTarget[] {
    return this.normalizeTargets(targets).map((target: SiteIconListTarget): SiteIconDomainUpdateTarget => {
      return {
        id: target.id,
        url: target.url,
        domain: target.domain
      };
    });
  }

  private normalizeTargets(targets: SiteIconListTarget[]): SiteIconListTarget[] {
    const normalizedTargets: SiteIconListTarget[] = [];
    targets.forEach((target: SiteIconListTarget) => {
      const url = target.url.trim();
      const domain = this.resolveTargetDomain(target.domain ?? '', url);
      if (target.id.length === 0 || url.length === 0 || domain.length === 0) {
        return;
      }
      normalizedTargets.push({
        id: target.id,
        url: url,
        domain: domain,
        initialIconUri: (target.initialIconUri ?? '').trim()
      });
    });
    return normalizedTargets;
  }

  private toResolvedIcon(
    target: SiteIconListTarget,
    uri: string,
    forceRevisionAdvance: boolean = false,
    domainUpdateSequence: number = 0
  ): SiteIconListResolvedIcon {
    const domain = this.resolveTargetDomain(target.domain ?? '', target.url);
    return {
      id: target.id,
      domain: domain,
      uri: uri,
      sourceRevision: this.resolveSourceRevision(
        domain,
        uri,
        forceRevisionAdvance,
        domainUpdateSequence
      )
    };
  }

  private async resolvePixelMapRecovery(
    target: SiteIconListTarget,
    currentUri: string
  ): Promise<SiteIconListPixelMapRecoveryAsset | undefined> {
    const centralUri = await this.resolveCentralCachedUri(target, currentUri);
    if (centralUri.length === 0) {
      return undefined;
    }
    const domain = this.resolveTargetDomain(target.domain ?? '', target.url);
    const sourceRevision = this.resolveSourceRevision(domain, centralUri, false);
    const pixelMap = await this.pixelMapCacheService.prewarmIconUri(
      centralUri,
      SITE_ICON_LIST_PIXEL_MAP_DECODE_SIZE
    );
    if (pixelMap === undefined) {
      return undefined;
    }
    if (!this.isCurrentSourceRevision(domain, centralUri, sourceRevision)) {
      return undefined;
    }
    return {
      domain: domain,
      uri: centralUri,
      pixelMap: pixelMap,
      sourceRevision: sourceRevision
    };
  }

  private async resolveCentralCachedUri(target: SiteIconListTarget, currentUri: string): Promise<string> {
    const domain = target.domain ?? target.url;
    const memoryUri = this.siteIconService.peekUri(domain);
    if (memoryUri.length > 0) {
      return memoryUri;
    }
    const cachedUri = await this.siteIconService.readCachedUri(domain);
    if (cachedUri.length > 0) {
      return cachedUri;
    }
    return currentUri.trim();
  }

  private applyRecoveryResult(
    promise: Promise<SiteIconListPixelMapRecoveryAsset | undefined>,
    target: SiteIconListTarget,
    recoveryGeneration: number,
    onResolved: SiteIconListResolvedHandler
  ): void {
    void promise.then((asset: SiteIconListPixelMapRecoveryAsset | undefined) => {
      if (recoveryGeneration === this.pixelMapRecoveryGeneration && asset !== undefined) {
        onResolved({
          id: target.id,
          domain: asset.domain,
          uri: asset.uri,
          pixelMap: asset.pixelMap,
          sourceRevision: asset.sourceRevision
        });
      }
    });
  }

  private cancelPixelMapRecovery(): void {
    this.pixelMapRecoveryGeneration += 1;
    this.pixelMapRecoveryEntries = [];
  }

  private resolveSourceRevision(
    domain: string,
    uri: string,
    forceAdvance: boolean,
    domainUpdateSequence: number = 0
  ): number {
    const normalizedDomain = this.normalizeDomain(domain);
    const normalizedUri = uri.trim();
    const existing = this.sourceRevisionEntries
      .find((entry: SiteIconListSourceRevisionEntry) => entry.domain === normalizedDomain);
    if (existing === undefined) {
      this.sourceRevisionEntries = this.sourceRevisionEntries.concat([{
        domain: normalizedDomain,
        uri: normalizedUri,
        revision: 1,
        domainUpdateSequence: domainUpdateSequence
      }]);
      return 1;
    }
    if (forceAdvance && domainUpdateSequence > 0 &&
      existing.domainUpdateSequence === domainUpdateSequence) {
      return existing.revision;
    }
    if (!forceAdvance && existing.uri === normalizedUri) {
      return existing.revision;
    }
    existing.uri = normalizedUri;
    existing.revision += 1;
    existing.domainUpdateSequence = domainUpdateSequence;
    this.clearFailedPixelMapRecoveries(normalizedDomain);
    return existing.revision;
  }

  private buildPixelMapRecoveryKey(domain: string, uri: string, revision: number): string {
    return `${this.normalizeDomain(domain)}|${uri.trim()}|${Math.max(0, revision)}`;
  }

  private isCurrentSourceRevision(domain: string, uri: string, revision: number): boolean {
    const normalizedDomain = this.normalizeDomain(domain);
    const existing = this.sourceRevisionEntries
      .find((entry: SiteIconListSourceRevisionEntry) => entry.domain === normalizedDomain);
    return existing !== undefined && existing.uri === uri.trim() && existing.revision === revision;
  }

  private rememberFailedPixelMapRecovery(key: string): void {
    if (this.failedPixelMapRecoveryKeys.indexOf(key) >= 0) {
      return;
    }
    this.failedPixelMapRecoveryKeys = this.failedPixelMapRecoveryKeys.concat([key]);
  }

  private clearFailedPixelMapRecoveries(domain: string): void {
    const prefix = `${this.normalizeDomain(domain)}|`;
    this.failedPixelMapRecoveryKeys = this.failedPixelMapRecoveryKeys
      .filter((key: string) => !key.startsWith(prefix));
  }

  private resolveTargetDomain(domain: string, url: string): string {
    const normalizedDomain = this.normalizeDomain(domain);
    if (normalizedDomain.length > 0) {
      return normalizedDomain;
    }
    return this.siteIconService.resolveDomain(url);
  }

  private normalizeDomain(domain: string): string {
    let normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    return normalized;
  }
}

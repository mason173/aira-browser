import {
  SiteIconListResolutionPolicy,
  SiteIconResult
} from '../../common/models/SiteIconModels';
import { SiteIconService } from '../../services/siteicons/SiteIconService';

const SITE_ICON_PREWARM_DELAY_MS: number = 360;
const SITE_ICON_PREWARM_MAX_CONCURRENCY: number = 2;
const SITE_ICON_PREWARM_FAILED_RETRY_DELAY_MS: number = 5 * 60 * 1000;

export interface SiteIconPrewarmTarget {
  id: string;
  url: string;
  domain?: string;
}

export interface SiteIconPrewarmResolvedIcon {
  id: string;
  url: string;
  domain: string;
  uri: string;
}

export type SiteIconPrewarmResolvedCallback = (result: SiteIconPrewarmResolvedIcon) => void;

export interface SiteIconPrewarmResolveOptions {
  resolutionPolicy?: SiteIconListResolutionPolicy;
  shouldSkipTarget?: (target: SiteIconPrewarmTarget) => boolean;
}

interface SiteIconPrewarmQueueEntry {
  domain: string;
  generation: number;
  visibleGeneration: number;
  targets: SiteIconPrewarmTarget[];
  onResolved: SiteIconPrewarmResolvedCallback;
}

interface SiteIconVisibleDomainGroup {
  domain: string;
  sourceUrl: string;
  targets: SiteIconPrewarmTarget[];
}

export class SiteIconPrewarmCoordinator {
  private readonly siteIconService: SiteIconService;
  private queuedEntries: SiteIconPrewarmQueueEntry[] = [];
  private activeEntries: SiteIconPrewarmQueueEntry[] = [];
  private failedDomainTimestamps: Record<string, number | undefined> = {};
  private prewarmTimer: number = -1;
  private generation: number = 0;
  private visibleGeneration: number = 0;

  constructor(siteIconService: SiteIconService = new SiteIconService()) {
    this.siteIconService = siteIconService;
  }

  resolveVisibleTargets(
    targets: SiteIconPrewarmTarget[],
    onResolved: SiteIconPrewarmResolvedCallback,
    options?: SiteIconPrewarmResolveOptions
  ): void {
    this.visibleGeneration += 1;
    this.dropStaleQueuedEntries();
    const generation = this.generation;
    const resolutionPolicy = options?.resolutionPolicy ?? 'remoteAllowed';
    const groups = this.collectVisibleDomainGroups(targets, options);
    groups.forEach((group: SiteIconVisibleDomainGroup) => {
      this.resolveVisibleDomainGroup(group, onResolved, generation, resolutionPolicy);
    });
  }

  enqueueTargets(
    targets: SiteIconPrewarmTarget[],
    onResolved: SiteIconPrewarmResolvedCallback,
    delayMs: number = SITE_ICON_PREWARM_DELAY_MS
  ): void {
    targets.forEach((target: SiteIconPrewarmTarget) => {
      this.enqueueTarget(target, onResolved, this.visibleGeneration);
    });
    this.scheduleDrain(delayMs);
  }

  cancel(): void {
    this.generation += 1;
    this.visibleGeneration += 1;
    this.queuedEntries = [];
    this.activeEntries = [];
    if (this.prewarmTimer >= 0) {
      clearTimeout(this.prewarmTimer);
      this.prewarmTimer = -1;
    }
  }

  private collectVisibleDomainGroups(
    targets: SiteIconPrewarmTarget[],
    options?: SiteIconPrewarmResolveOptions
  ): SiteIconVisibleDomainGroup[] {
    let groups: SiteIconVisibleDomainGroup[] = [];
    targets.forEach((target: SiteIconPrewarmTarget) => {
      if (options?.shouldSkipTarget !== undefined && options.shouldSkipTarget(target)) {
        return;
      }

      const url = target.url.trim();
      const domain = this.resolveTargetDomain(target, url);
      if (target.id.length === 0 || url.length === 0 || domain.length === 0) {
        return;
      }

      const normalizedTarget: SiteIconPrewarmTarget = {
        id: target.id,
        url: url,
        domain: domain
      };
      const existingGroup = groups.find((group: SiteIconVisibleDomainGroup) => group.domain === domain);
      if (existingGroup !== undefined) {
        this.appendVisibleTarget(existingGroup, normalizedTarget);
        return;
      }

      groups = groups.concat([{
        domain: domain,
        sourceUrl: url,
        targets: [normalizedTarget]
      }]);
    });
    return groups;
  }

  private resolveVisibleDomainGroup(
    group: SiteIconVisibleDomainGroup,
    onResolved: SiteIconPrewarmResolvedCallback,
    lifecycleGeneration: number,
    resolutionPolicy: SiteIconListResolutionPolicy
  ): void {
    if (lifecycleGeneration !== this.generation) {
      return;
    }

    const memoryUri = this.siteIconService.peekUri(group.domain);
    if (memoryUri.length > 0) {
      this.notifyResolvedTargets(group, memoryUri, onResolved, lifecycleGeneration);
      return;
    }
    if (resolutionPolicy === 'memoryOnly') {
      return;
    }

    this.siteIconService.readCachedUri(group.domain)
      .then((uri: string) => {
        if (lifecycleGeneration !== this.generation) {
          return;
        }
        if (uri.length > 0) {
          this.notifyResolvedTargets(group, uri, onResolved, lifecycleGeneration);
          return;
        }
        if (resolutionPolicy === 'cacheOnly') {
          return;
        }
        this.enqueueTargets(group.targets, onResolved);
      })
      .catch((_error: Error) => {
        if (lifecycleGeneration !== this.generation) {
          return;
        }
        if (resolutionPolicy === 'cacheOnly') {
          return;
        }
        this.enqueueTargets(group.targets, onResolved);
      });
  }

  private notifyResolvedTargets(
    group: SiteIconVisibleDomainGroup,
    uri: string,
    onResolved: SiteIconPrewarmResolvedCallback,
    lifecycleGeneration: number
  ): void {
    group.targets.forEach((target: SiteIconPrewarmTarget) => {
      if (lifecycleGeneration !== this.generation) {
        return;
      }
      onResolved({
        id: target.id,
        url: target.url,
        domain: group.domain,
        uri: uri
      });
    });
  }

  private enqueueTarget(
    target: SiteIconPrewarmTarget,
    onResolved: SiteIconPrewarmResolvedCallback,
    visibleGeneration: number
  ): void {
    const url = target.url.trim();
    if (target.id.length === 0 || url.length === 0) {
      return;
    }
    const domain = this.resolveTargetDomain(target, url);
    if (domain.length === 0) {
      return;
    }
    if (!this.siteIconService.canCollect(url)) {
      return;
    }
    if (this.shouldSkipRecentlyFailedDomain(domain)) {
      return;
    }

    const activeEntry = this.findEntryByDomain(this.activeEntries, domain);
    if (activeEntry !== undefined) {
      this.appendTarget(activeEntry, { id: target.id, url: url, domain: domain });
      return;
    }

    const queuedEntry = this.findEntryByDomain(this.queuedEntries, domain);
    if (queuedEntry !== undefined) {
      this.appendTarget(queuedEntry, { id: target.id, url: url, domain: domain });
      return;
    }

    this.queuedEntries = this.queuedEntries.concat([{
      domain: domain,
      generation: this.generation,
      visibleGeneration: visibleGeneration,
      targets: [{ id: target.id, url: url, domain: domain }],
      onResolved: onResolved
    }]);
  }

  private scheduleDrain(delayMs: number): void {
    if (this.queuedEntries.length === 0 || this.prewarmTimer >= 0) {
      return;
    }
    this.prewarmTimer = setTimeout(() => {
      this.prewarmTimer = -1;
      this.drainQueue();
    }, Math.max(0, delayMs));
  }

  private drainQueue(): void {
    while (this.activeEntries.length < SITE_ICON_PREWARM_MAX_CONCURRENCY && this.queuedEntries.length > 0) {
      const entry = this.queuedEntries[0];
      this.queuedEntries = this.queuedEntries.slice(1);
      this.activeEntries = this.activeEntries.concat([entry]);
      this.runEntry(entry);
    }
  }

  private runEntry(entry: SiteIconPrewarmQueueEntry): void {
    const sourceUrl = entry.targets.length > 0 ? entry.targets[0].url : '';
    this.siteIconService.resolve(sourceUrl, {
      networkPolicy: 'remoteAllowed'
    })
      .then((result: SiteIconResult | undefined) => {
        if (entry.generation !== this.generation) {
          return;
        }
        if (result === undefined || result.uri.length === 0) {
          this.failedDomainTimestamps[entry.domain] = Date.now();
          return;
        }
        this.failedDomainTimestamps[entry.domain] = undefined;
        entry.targets.forEach((target: SiteIconPrewarmTarget) => {
          entry.onResolved({
            id: target.id,
            url: target.url,
            domain: entry.domain,
            uri: result.uri
          });
        });
      })
      .catch((_error: Error) => {
        if (entry.generation === this.generation) {
          this.failedDomainTimestamps[entry.domain] = Date.now();
        }
      })
      .finally(() => {
        this.activeEntries = this.activeEntries.filter((item: SiteIconPrewarmQueueEntry) => item !== entry);
        if (entry.generation !== this.generation) {
          return;
        }
        if (this.queuedEntries.length > 0) {
          this.drainQueue();
        }
      });
  }

  private shouldSkipRecentlyFailedDomain(domain: string): boolean {
    const failedAt = this.failedDomainTimestamps[domain] ?? 0;
    return failedAt > 0 && Date.now() - failedAt < SITE_ICON_PREWARM_FAILED_RETRY_DELAY_MS;
  }

  private dropStaleQueuedEntries(): void {
    const retained = this.queuedEntries.filter((entry: SiteIconPrewarmQueueEntry) => {
      return entry.generation === this.generation && entry.visibleGeneration === this.visibleGeneration;
    });
    if (retained.length !== this.queuedEntries.length) {
      this.queuedEntries = retained;
      if (this.queuedEntries.length === 0 && this.prewarmTimer >= 0) {
        clearTimeout(this.prewarmTimer);
        this.prewarmTimer = -1;
      }
    }
  }

  private findEntryByDomain(
    entries: SiteIconPrewarmQueueEntry[],
    domain: string
  ): SiteIconPrewarmQueueEntry | undefined {
    return entries.find((entry: SiteIconPrewarmQueueEntry) => entry.domain === domain &&
      entry.generation === this.generation);
  }

  private resolveTargetDomain(target: SiteIconPrewarmTarget, url: string): string {
    const domain = this.normalizeTargetDomain(target.domain ?? '');
    if (domain.length > 0) {
      return domain;
    }
    return this.siteIconService.resolveDomain(url);
  }

  private normalizeTargetDomain(domain: string): string {
    let normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    return normalized;
  }

  private appendTarget(entry: SiteIconPrewarmQueueEntry, target: SiteIconPrewarmTarget): void {
    const existing = entry.targets.find((item: SiteIconPrewarmTarget) => item.id === target.id);
    if (existing !== undefined) {
      return;
    }
    entry.targets = entry.targets.concat([target]);
  }

  private appendVisibleTarget(group: SiteIconVisibleDomainGroup, target: SiteIconPrewarmTarget): void {
    const existing = group.targets.find((item: SiteIconPrewarmTarget) => item.id === target.id);
    if (existing !== undefined) {
      return;
    }
    group.targets = group.targets.concat([target]);
  }
}

import { SiteIconService } from '../../services/siteicons/SiteIconService';
import {
  SiteIconDomainUpdate,
  SiteIconUpdateCenter
} from '../../services/siteicons/SiteIconUpdateCenter';

export interface SiteIconDomainUpdateTarget {
  id: string;
  url: string;
  domain?: string;
}

export type SiteIconDomainUpdateTargetProvider = () => SiteIconDomainUpdateTarget[];
export type SiteIconDomainUpdateApplyHandler = (
  target: SiteIconDomainUpdateTarget,
  uri: string,
  updateSequence: number
) => void;

export class SiteIconDomainUpdateBinder {
  private readonly siteIconService: SiteIconService;
  private unsubscribeSiteIconUpdates: (() => void) | undefined = undefined;
  private updateSequence: number = 0;

  constructor(siteIconService: SiteIconService = new SiteIconService()) {
    this.siteIconService = siteIconService;
  }

  subscribe(
    provideTargets: SiteIconDomainUpdateTargetProvider,
    apply: SiteIconDomainUpdateApplyHandler
  ): void {
    this.dispose();
    this.unsubscribeSiteIconUpdates = SiteIconUpdateCenter.subscribe((update: SiteIconDomainUpdate): void => {
      this.applyDomainUpdate(update, provideTargets, apply);
    });
  }

  dispose(): void {
    const unsubscribe = this.unsubscribeSiteIconUpdates;
    if (unsubscribe === undefined) {
      return;
    }
    unsubscribe();
    this.unsubscribeSiteIconUpdates = undefined;
  }

  private applyDomainUpdate(
    update: SiteIconDomainUpdate,
    provideTargets: SiteIconDomainUpdateTargetProvider,
    apply: SiteIconDomainUpdateApplyHandler
  ): void {
    if (update.domain.length === 0 || update.uri.length === 0) {
      return;
    }
    this.updateSequence += 1;
    const updateSequence = this.updateSequence;
    provideTargets().forEach((target: SiteIconDomainUpdateTarget) => {
      if (this.resolveTargetDomain(target) === update.domain) {
        apply(target, update.uri, updateSequence);
      }
    });
  }

  private resolveTargetDomain(target: SiteIconDomainUpdateTarget): string {
    const domain = this.normalizeTargetDomain(target.domain ?? '');
    if (domain.length > 0) {
      return domain;
    }
    return this.siteIconService.resolveDomain(target.url);
  }

  private normalizeTargetDomain(domain: string): string {
    let normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    return normalized;
  }
}

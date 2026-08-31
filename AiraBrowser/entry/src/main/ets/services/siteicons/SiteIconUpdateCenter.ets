import {
  SiteIconCacheState,
  SiteIconCandidateSource
} from '../../common/models/SiteIconModels';

export interface SiteIconDomainUpdate {
  domain: string;
  uri: string;
  source: SiteIconCandidateSource;
  cacheState: SiteIconCacheState;
  updatedAt: number;
}

export type SiteIconDomainUpdateListener = (update: SiteIconDomainUpdate) => void;

interface SiteIconDomainUpdateListenerEntry {
  id: number;
  listener: SiteIconDomainUpdateListener;
}

export class SiteIconUpdateCenter {
  private static listenerEntries: SiteIconDomainUpdateListenerEntry[] = [];
  private static nextListenerId: number = 1;

  static subscribe(listener: SiteIconDomainUpdateListener): () => void {
    const listenerId = SiteIconUpdateCenter.nextListenerId;
    SiteIconUpdateCenter.nextListenerId += 1;
    SiteIconUpdateCenter.listenerEntries = SiteIconUpdateCenter.listenerEntries.concat([{
      id: listenerId,
      listener: listener
    }]);
    return (): void => {
      SiteIconUpdateCenter.listenerEntries = SiteIconUpdateCenter.listenerEntries
        .filter((entry: SiteIconDomainUpdateListenerEntry) => entry.id !== listenerId);
    };
  }

  static publish(update: SiteIconDomainUpdate): void {
    if (update.domain.trim().length === 0 || update.uri.trim().length === 0) {
      return;
    }
    const snapshot = SiteIconUpdateCenter.listenerEntries.slice();
    snapshot.forEach((entry: SiteIconDomainUpdateListenerEntry) => {
      try {
        entry.listener(update);
      } catch (_error) {
      }
    });
  }
}

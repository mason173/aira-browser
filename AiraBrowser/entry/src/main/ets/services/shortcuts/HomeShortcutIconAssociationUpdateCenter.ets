import { TabLaunchContext } from '../../common/models/BrowserModels';
import { SiteIconCandidateSource } from '../../common/models/SiteIconModels';

export interface HomeShortcutIconAssociationCandidate {
  documentUrl: string;
  iconUri: string;
  source: SiteIconCandidateSource;
  qualityScore: number;
  width: number;
  height: number;
}

export interface HomeShortcutIconAssociationUpdate extends HomeShortcutIconAssociationCandidate {
  shortcutId: string;
  sourceUrl: string;
  updatedAt: number;
}

export type HomeShortcutIconAssociationUpdateListener = (update: HomeShortcutIconAssociationUpdate) => void;

interface HomeShortcutIconAssociationUpdateListenerEntry {
  id: number;
  listener: HomeShortcutIconAssociationUpdateListener;
}

interface HomeShortcutIconLaunchTicket {
  key: string;
  shortcutId: string;
  sourceUrl: string;
  registeredAt: number;
  bestUpdate: HomeShortcutIconAssociationUpdate | undefined;
}

const MAX_LAUNCH_TICKETS: number = 128;
const LAUNCH_TICKET_TTL_MS: number = 2 * 60 * 1000;

export class HomeShortcutIconAssociationUpdateCenter {
  private static listenerEntries: HomeShortcutIconAssociationUpdateListenerEntry[] = [];
  private static launchTickets: HomeShortcutIconLaunchTicket[] = [];
  private static nextListenerId: number = 1;

  static registerLaunch(launchContext: TabLaunchContext): void {
    if (launchContext.sourceType !== 'home_shortcut') {
      return;
    }
    const key = launchContext.key.trim();
    const shortcutId = launchContext.sourceId.trim();
    const sourceUrl = launchContext.sourceUrl.trim();
    if (key.length === 0 || shortcutId.length === 0 || sourceUrl.length === 0) {
      return;
    }
    const now = Date.now();
    HomeShortcutIconAssociationUpdateCenter.pruneLaunchTickets(now);
    const nextTickets = HomeShortcutIconAssociationUpdateCenter.launchTickets
      .filter((ticket: HomeShortcutIconLaunchTicket) => (
        ticket.key !== key && ticket.shortcutId !== shortcutId
      ))
      .concat([{
        key: key,
        shortcutId: shortcutId,
        sourceUrl: sourceUrl,
        registeredAt: now,
        bestUpdate: undefined
      }]);
    HomeShortcutIconAssociationUpdateCenter.launchTickets =
      nextTickets.slice(Math.max(0, nextTickets.length - MAX_LAUNCH_TICKETS));
  }

  static publishForLaunch(
    launchContext: TabLaunchContext,
    candidate: HomeShortcutIconAssociationCandidate
  ): void {
    if (launchContext.sourceType !== 'home_shortcut') {
      return;
    }
    const now = Date.now();
    HomeShortcutIconAssociationUpdateCenter.pruneLaunchTickets(now);
    const key = launchContext.key.trim();
    const shortcutId = launchContext.sourceId.trim();
    const sourceUrl = launchContext.sourceUrl.trim();
    const ticket = HomeShortcutIconAssociationUpdateCenter.launchTickets.find(
      (entry: HomeShortcutIconLaunchTicket) => entry.key === key &&
        entry.shortcutId === shortcutId && entry.sourceUrl === sourceUrl
    );
    const normalizedCandidate = HomeShortcutIconAssociationUpdateCenter.normalizeCandidate(candidate);
    if (ticket === undefined || normalizedCandidate === undefined ||
      !HomeShortcutIconAssociationUpdateCenter.matchesLaunchSite(ticket.sourceUrl, normalizedCandidate.documentUrl)) {
      return;
    }
    const update: HomeShortcutIconAssociationUpdate = {
      shortcutId: ticket.shortcutId,
      sourceUrl: ticket.sourceUrl,
      documentUrl: normalizedCandidate.documentUrl,
      iconUri: normalizedCandidate.iconUri,
      source: normalizedCandidate.source,
      qualityScore: normalizedCandidate.qualityScore,
      width: normalizedCandidate.width,
      height: normalizedCandidate.height,
      updatedAt: now
    };
    if (!HomeShortcutIconAssociationUpdateCenter.shouldReplaceUpdate(ticket.bestUpdate, update)) {
      return;
    }
    ticket.bestUpdate = update;
    HomeShortcutIconAssociationUpdateCenter.notifyListeners(update);
  }

  static subscribe(listener: HomeShortcutIconAssociationUpdateListener): () => void {
    const listenerId = HomeShortcutIconAssociationUpdateCenter.nextListenerId;
    HomeShortcutIconAssociationUpdateCenter.nextListenerId += 1;
    HomeShortcutIconAssociationUpdateCenter.listenerEntries =
      HomeShortcutIconAssociationUpdateCenter.listenerEntries.concat([{
        id: listenerId,
        listener: listener
      }]);
    HomeShortcutIconAssociationUpdateCenter.pruneLaunchTickets(Date.now());
    HomeShortcutIconAssociationUpdateCenter.launchTickets.forEach((ticket: HomeShortcutIconLaunchTicket) => {
      if (ticket.bestUpdate !== undefined) {
        HomeShortcutIconAssociationUpdateCenter.notifyListener(listener, ticket.bestUpdate);
      }
    });
    return (): void => {
      HomeShortcutIconAssociationUpdateCenter.listenerEntries =
        HomeShortcutIconAssociationUpdateCenter.listenerEntries
          .filter((entry: HomeShortcutIconAssociationUpdateListenerEntry) => entry.id !== listenerId);
    };
  }

  private static normalizeCandidate(
    candidate: HomeShortcutIconAssociationCandidate
  ): HomeShortcutIconAssociationCandidate | undefined {
    const documentUrl = candidate.documentUrl.trim();
    const iconUri = candidate.iconUri.trim();
    if (documentUrl.length === 0 || iconUri.length === 0) {
      return undefined;
    }
    return {
      documentUrl: documentUrl,
      iconUri: iconUri,
      source: candidate.source,
      qualityScore: candidate.qualityScore,
      width: candidate.width,
      height: candidate.height
    };
  }

  private static shouldReplaceUpdate(
    current: HomeShortcutIconAssociationUpdate | undefined,
    candidate: HomeShortcutIconAssociationUpdate
  ): boolean {
    if (current === undefined || current.sourceUrl !== candidate.sourceUrl) {
      return true;
    }
    if (candidate.qualityScore !== current.qualityScore) {
      return candidate.qualityScore > current.qualityScore;
    }
    return HomeShortcutIconAssociationUpdateCenter.resolveUpdateEdge(candidate) >
      HomeShortcutIconAssociationUpdateCenter.resolveUpdateEdge(current);
  }

  private static resolveUpdateEdge(update: HomeShortcutIconAssociationUpdate): number {
    return Math.min(Math.max(0, Math.floor(update.width)), Math.max(0, Math.floor(update.height)));
  }

  private static matchesLaunchSite(sourceUrl: string, documentUrl: string): boolean {
    const sourceHost = HomeShortcutIconAssociationUpdateCenter.extractHost(sourceUrl);
    const documentHost = HomeShortcutIconAssociationUpdateCenter.extractHost(documentUrl);
    if (sourceHost.length === 0 || documentHost.length === 0) {
      return false;
    }
    if (sourceHost === documentHost) {
      return true;
    }
    const sourceSiteHost = sourceHost.startsWith('www.') ? sourceHost.substring(4) : sourceHost;
    return documentHost === sourceSiteHost || documentHost.endsWith(`.${sourceSiteHost}`);
  }

  private static extractHost(url: string): string {
    const match = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(url.trim());
    if (match === null) {
      return '';
    }
    const authority = match[1].trim().toLowerCase();
    const userInfoIndex = authority.lastIndexOf('@');
    const hostAndPort = userInfoIndex >= 0 ? authority.substring(userInfoIndex + 1) : authority;
    if (hostAndPort.startsWith('[')) {
      const bracketEnd = hostAndPort.indexOf(']');
      return bracketEnd > 0 ? hostAndPort.substring(1, bracketEnd) : '';
    }
    const portIndex = hostAndPort.indexOf(':');
    return portIndex >= 0 ? hostAndPort.substring(0, portIndex) : hostAndPort;
  }

  private static notifyListeners(update: HomeShortcutIconAssociationUpdate): void {
    const listenerSnapshot = HomeShortcutIconAssociationUpdateCenter.listenerEntries.slice();
    listenerSnapshot.forEach((entry: HomeShortcutIconAssociationUpdateListenerEntry) => {
      HomeShortcutIconAssociationUpdateCenter.notifyListener(entry.listener, update);
    });
  }

  private static notifyListener(
    listener: HomeShortcutIconAssociationUpdateListener,
    update: HomeShortcutIconAssociationUpdate
  ): void {
    try {
      listener(update);
    } catch (_error) {
    }
  }

  private static pruneLaunchTickets(now: number): void {
    HomeShortcutIconAssociationUpdateCenter.launchTickets =
      HomeShortcutIconAssociationUpdateCenter.launchTickets.filter((ticket: HomeShortcutIconLaunchTicket) => (
        now - ticket.registeredAt <= LAUNCH_TICKET_TTL_MS
      ));
  }
}

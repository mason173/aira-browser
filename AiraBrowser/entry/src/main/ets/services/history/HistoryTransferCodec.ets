import {
  BrowserDataScope,
  BrowserHistoryTransition,
  BrowserProfileId,
  HistoryTransferBundle,
  HistoryTransferVisit,
  HistoryVisit
} from '../../common/models/BrowserModels';

const HISTORY_TRANSFER_VERSION: number = 1;
const HISTORY_TRANSFER_APP: string = 'aira-browser';

export class HistoryTransferCodec {
  encodeVisits(visits: HistoryVisit[]): string {
    const bundle: HistoryTransferBundle = {
      version: HISTORY_TRANSFER_VERSION,
      app: HISTORY_TRANSFER_APP,
      exportedAt: Date.now(),
      visits: this.buildTransferVisits(visits)
    };
    return JSON.stringify(bundle, null, 2);
  }

  buildTransferVisits(visits: HistoryVisit[]): HistoryTransferVisit[] {
    return visits
      .slice()
      .sort((left: HistoryVisit, right: HistoryVisit) => right.visitedAt - left.visitedAt)
      .map((visit: HistoryVisit): HistoryTransferVisit => {
        return {
          title: visit.title,
          url: visit.url,
          visitedAt: visit.visitedAt,
          sessionId: visit.sessionId,
          fromVisitId: visit.fromVisitId,
          transition: visit.transition,
          visitDurationMs: visit.visitDurationMs,
          profileId: visit.profileId,
          dataScope: visit.dataScope
        };
      });
  }

  decodeVisits(payload: string): HistoryTransferVisit[] {
    const parsed = JSON.parse(payload) as HistoryTransferBundle | HistoryTransferVisit[];
    const rawVisits = Array.isArray(parsed) ? parsed : parsed.visits;
    if (!Array.isArray(rawVisits)) {
      throw new Error('历史文件格式无效。');
    }
    return rawVisits
      .map((visit: HistoryTransferVisit): HistoryTransferVisit | undefined => this.normalizeVisit(visit))
      .filter((visit: HistoryTransferVisit | undefined) => visit !== undefined)
      .map((visit: HistoryTransferVisit | undefined): HistoryTransferVisit => visit as HistoryTransferVisit);
  }

  private normalizeVisit(visit: HistoryTransferVisit): HistoryTransferVisit | undefined {
    const title = String(visit.title ?? '').trim();
    const url = String(visit.url ?? '').trim();
    const visitedAt = Number(visit.visitedAt);
    if (url.length === 0 || !Number.isFinite(visitedAt) || visitedAt <= 0) {
      return undefined;
    }
    return {
      title: title.length > 0 ? title : url,
      url: url,
      visitedAt: Math.round(visitedAt),
      sessionId: typeof visit.sessionId === 'string' ? visit.sessionId.trim() : undefined,
      fromVisitId: typeof visit.fromVisitId === 'string' ? visit.fromVisitId.trim() : undefined,
      transition: this.normalizeTransition(visit.transition),
      visitDurationMs: this.normalizeNonNegativeNumber(visit.visitDurationMs),
      profileId: this.normalizeProfileId(visit.profileId),
      dataScope: this.normalizeDataScope(visit.dataScope)
    };
  }

  private normalizeTransition(value: BrowserHistoryTransition | undefined): BrowserHistoryTransition {
    if (
      value === 'link' ||
      value === 'typed' ||
      value === 'auto_bookmark' ||
      value === 'auto_subframe' ||
      value === 'manual_subframe' ||
      value === 'generated' ||
      value === 'auto_toplevel' ||
      value === 'form_submit' ||
      value === 'reload' ||
      value === 'keyword' ||
      value === 'keyword_generated' ||
      value === 'unknown'
    ) {
      return value;
    }
    return 'link';
  }

  private normalizeProfileId(value: BrowserProfileId | undefined): BrowserProfileId {
    return value === 'profile-main' ? value : 'profile-main';
  }

  private normalizeDataScope(value: BrowserDataScope | undefined): BrowserDataScope {
    return value === 'session_ephemeral' ? 'session_ephemeral' : 'profile_persistent';
  }

  private normalizeNonNegativeNumber(value: number | undefined): number {
    const numeric = Number(value);
    if (!Number.isFinite(numeric) || numeric < 0) {
      return 0;
    }
    return Math.round(numeric);
  }
}

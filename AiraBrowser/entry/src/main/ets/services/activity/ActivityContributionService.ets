import { AiraActivityDailyAggregate } from '../../common/models/ActivityModels';
import {
  PersonalizationActivityContribution,
  PersonalizationActivityHeatmapPayload
} from '../../common/models/PersonalizationSyncModels';

const MAX_ACTIVITY_DAYS: number = 420;
const MAX_DAILY_SCORE: number = 240;
const MAX_DAILY_PAGE_VISITS: number = 120;
const LOCAL_VISIBLE_HISTORY_SOURCE_ID: string = 'aira-local-visible-history-g2';

export interface ActivityLocalMergeResult {
  totals: AiraActivityDailyAggregate[];
  localContributions: AiraActivityDailyAggregate[];
}

export class ActivityContributionService {
  buildGenerationPayload(
    sourceId: string,
    visibleHistorySeed: AiraActivityDailyAggregate[],
    localContributions: AiraActivityDailyAggregate[],
    updatedAt: number
  ): PersonalizationActivityHeatmapPayload {
    const normalizedSourceId = sourceId.trim().length > 0 ? sourceId.trim() : 'aira-personalization-device';
    const normalizedLocalContributions = this.normalizeAggregates(localContributions);
    const normalizedVisibleHistorySeed = this.normalizeAggregates(visibleHistorySeed);
    const contributions: PersonalizationActivityContribution[] = [];
    if (normalizedLocalContributions.length > 0) {
      contributions.push({
        sourceId: normalizedSourceId,
        items: normalizedLocalContributions,
        updatedAt: this.resolveContributionUpdatedAt(normalizedLocalContributions, updatedAt)
      });
    }
    if (normalizedVisibleHistorySeed.length > 0) {
      contributions.push({
        sourceId: LOCAL_VISIBLE_HISTORY_SOURCE_ID,
        items: normalizedVisibleHistorySeed,
        updatedAt: this.resolveContributionUpdatedAt(normalizedVisibleHistorySeed, updatedAt)
      });
    }
    return {
      contributions: this.mergeContributions([], contributions)
    };
  }

  mergeLocalActivity(
    totals: AiraActivityDailyAggregate[],
    localContributions: AiraActivityDailyAggregate[],
    incoming: AiraActivityDailyAggregate[]
  ): ActivityLocalMergeResult {
    const normalizedIncoming = this.normalizeAggregates(incoming);
    const nextLocalContributions = this.mergeLocalContributions(localContributions, normalizedIncoming);
    return {
      totals: this.applyContributionDelta(totals, localContributions, nextLocalContributions),
      localContributions: nextLocalContributions
    };
  }

  sanitizePayload(payload: PersonalizationActivityHeatmapPayload | undefined): PersonalizationActivityHeatmapPayload {
    return {
      contributions: this.readContributions(payload)
    };
  }

  mergePayloads(
    left: PersonalizationActivityHeatmapPayload | undefined,
    right: PersonalizationActivityHeatmapPayload | undefined
  ): PersonalizationActivityHeatmapPayload {
    return {
      contributions: this.mergeContributions(this.readContributions(left), this.readContributions(right))
    };
  }

  buildTotals(payload: PersonalizationActivityHeatmapPayload | undefined): AiraActivityDailyAggregate[] {
    const totalsByDate = new Map<string, AiraActivityDailyAggregate>();
    this.readContributions(payload).forEach((contribution: PersonalizationActivityContribution): void => {
      contribution.items.forEach((item: AiraActivityDailyAggregate): void => {
        const current = totalsByDate.get(item.date);
        totalsByDate.set(item.date, current === undefined ? this.cloneAggregate(item) : {
          date: item.date,
          score: current.score + item.score,
          pageVisits: current.pageVisits + item.pageVisits,
          searches: current.searches + item.searches,
          bookmarkActions: current.bookmarkActions + item.bookmarkActions,
          downloads: current.downloads + item.downloads,
          featureActions: current.featureActions + item.featureActions,
          activeSeconds: current.activeSeconds + item.activeSeconds,
          updatedAt: Math.max(current.updatedAt, item.updatedAt)
        });
      });
    });
    return this.sortAndTrim(Array.from(totalsByDate.values()));
  }

  mergePortableTotals(
    existing: AiraActivityDailyAggregate[],
    incoming: AiraActivityDailyAggregate[]
  ): AiraActivityDailyAggregate[] {
    const byDate = new Map<string, AiraActivityDailyAggregate>();
    this.normalizeAggregates(existing).forEach((item: AiraActivityDailyAggregate): void => {
      byDate.set(item.date, item);
    });
    this.normalizeAggregates(incoming).forEach((item: AiraActivityDailyAggregate): void => {
      const current = byDate.get(item.date);
      byDate.set(item.date, current === undefined ? item : this.maxAggregate(current, item));
    });
    return this.sortAndTrim(Array.from(byDate.values()));
  }

  reconcileSyncedTotals(
    syncedTotals: AiraActivityDailyAggregate[],
    syncedLocalContributions: AiraActivityDailyAggregate[],
    currentLocalContributions: AiraActivityDailyAggregate[]
  ): AiraActivityDailyAggregate[] {
    return this.applyContributionDelta(
      syncedTotals,
      this.normalizeAggregates(syncedLocalContributions),
      this.normalizeAggregates(currentLocalContributions)
    );
  }

  findSourceItems(
    payload: PersonalizationActivityHeatmapPayload | undefined,
    sourceId: string
  ): AiraActivityDailyAggregate[] {
    const normalizedSourceId = sourceId.trim();
    const contribution = this.readContributions(payload).find(
      (value: PersonalizationActivityContribution): boolean => value.sourceId === normalizedSourceId
    );
    return contribution === undefined ? [] : this.cloneAggregates(contribution.items);
  }

  private readContributions(
    payload: PersonalizationActivityHeatmapPayload | undefined
  ): PersonalizationActivityContribution[] {
    if (payload === undefined || !Array.isArray(payload.contributions)) {
      return [];
    }
    return this.mergeContributions([], payload.contributions);
  }

  private mergeContributions(
    left: PersonalizationActivityContribution[],
    right: PersonalizationActivityContribution[]
  ): PersonalizationActivityContribution[] {
    const itemsBySource = new Map<string, Map<string, AiraActivityDailyAggregate>>();
    const updatedAtBySource = new Map<string, number>();
    const append = (contribution: PersonalizationActivityContribution): void => {
      const sourceId = `${contribution?.sourceId ?? ''}`.trim();
      if (sourceId.length <= 0) {
        return;
      }
      let itemsByDate = itemsBySource.get(sourceId);
      if (itemsByDate === undefined) {
        itemsByDate = new Map<string, AiraActivityDailyAggregate>();
        itemsBySource.set(sourceId, itemsByDate);
      }
      let sourceUpdatedAt = Math.max(
        updatedAtBySource.get(sourceId) ?? 0,
        this.normalizeTimestamp(contribution?.updatedAt)
      );
      const items = Array.isArray(contribution?.items) ? contribution.items : [];
      items.forEach((item: AiraActivityDailyAggregate): void => {
        const normalized = this.normalizeAggregate(item);
        if (normalized === undefined) {
          return;
        }
        const current = itemsByDate?.get(normalized.date);
        itemsByDate?.set(
          normalized.date,
          current === undefined ? normalized : this.maxAggregate(current, normalized)
        );
        sourceUpdatedAt = Math.max(sourceUpdatedAt, normalized.updatedAt);
      });
      updatedAtBySource.set(sourceId, sourceUpdatedAt);
    };
    left.forEach(append);
    right.forEach(append);
    return Array.from(itemsBySource.keys())
      .sort()
      .map((sourceId: string): PersonalizationActivityContribution => {
        const items = this.sortAndTrim(Array.from(itemsBySource.get(sourceId)?.values() ?? []));
        return {
          sourceId: sourceId,
          items: items,
          updatedAt: updatedAtBySource.get(sourceId) ?? 0
        };
      })
      .filter((contribution: PersonalizationActivityContribution): boolean => contribution.items.length > 0);
  }

  private mergeLocalContributions(
    existing: AiraActivityDailyAggregate[],
    incoming: AiraActivityDailyAggregate[]
  ): AiraActivityDailyAggregate[] {
    const byDate = new Map<string, AiraActivityDailyAggregate>();
    this.normalizeAggregates(existing).forEach((item: AiraActivityDailyAggregate): void => {
      byDate.set(item.date, item);
    });
    incoming.forEach((item: AiraActivityDailyAggregate): void => {
      const current = byDate.get(item.date);
      if (current === undefined) {
        byDate.set(item.date, item);
        return;
      }
      byDate.set(item.date, {
        date: item.date,
        score: Math.min(MAX_DAILY_SCORE, current.score + item.score),
        pageVisits: Math.min(MAX_DAILY_PAGE_VISITS, current.pageVisits + item.pageVisits),
        searches: current.searches + item.searches,
        bookmarkActions: current.bookmarkActions + item.bookmarkActions,
        downloads: current.downloads + item.downloads,
        featureActions: current.featureActions + item.featureActions,
        activeSeconds: current.activeSeconds + item.activeSeconds,
        updatedAt: Math.max(current.updatedAt, item.updatedAt)
      });
    });
    return this.sortAndTrim(Array.from(byDate.values()));
  }

  private applyContributionDelta(
    totals: AiraActivityDailyAggregate[],
    previousContributions: AiraActivityDailyAggregate[],
    nextContributions: AiraActivityDailyAggregate[]
  ): AiraActivityDailyAggregate[] {
    const totalsByDate = new Map<string, AiraActivityDailyAggregate>();
    const previousByDate = new Map<string, AiraActivityDailyAggregate>();
    this.normalizeAggregates(totals).forEach((item: AiraActivityDailyAggregate): void => {
      totalsByDate.set(item.date, item);
    });
    this.normalizeAggregates(previousContributions).forEach((item: AiraActivityDailyAggregate): void => {
      previousByDate.set(item.date, item);
    });
    this.normalizeAggregates(nextContributions).forEach((item: AiraActivityDailyAggregate): void => {
      const previous = previousByDate.get(item.date);
      const current = totalsByDate.get(item.date) ?? this.createEmptyAggregate(item.date);
      totalsByDate.set(item.date, {
        date: item.date,
        score: current.score + Math.max(0, item.score - (previous?.score ?? 0)),
        pageVisits: current.pageVisits + Math.max(0, item.pageVisits - (previous?.pageVisits ?? 0)),
        searches: current.searches + Math.max(0, item.searches - (previous?.searches ?? 0)),
        bookmarkActions:
          current.bookmarkActions + Math.max(0, item.bookmarkActions - (previous?.bookmarkActions ?? 0)),
        downloads: current.downloads + Math.max(0, item.downloads - (previous?.downloads ?? 0)),
        featureActions:
          current.featureActions + Math.max(0, item.featureActions - (previous?.featureActions ?? 0)),
        activeSeconds: current.activeSeconds + Math.max(0, item.activeSeconds - (previous?.activeSeconds ?? 0)),
        updatedAt: Math.max(current.updatedAt, item.updatedAt)
      });
    });
    return this.sortAndTrim(Array.from(totalsByDate.values()));
  }

  private resolveContributionUpdatedAt(items: AiraActivityDailyAggregate[], fallback: number): number {
    return items.reduce((latest: number, item: AiraActivityDailyAggregate): number => {
      return Math.max(latest, this.normalizeTimestamp(item.updatedAt));
    }, this.normalizeTimestamp(fallback));
  }

  private normalizeAggregates(values: AiraActivityDailyAggregate[]): AiraActivityDailyAggregate[] {
    const byDate = new Map<string, AiraActivityDailyAggregate>();
    (Array.isArray(values) ? values : []).forEach((value: AiraActivityDailyAggregate): void => {
      const normalized = this.normalizeAggregate(value);
      if (normalized === undefined) {
        return;
      }
      const current = byDate.get(normalized.date);
      byDate.set(normalized.date, current === undefined ? normalized : {
        date: normalized.date,
        score: current.score + normalized.score,
        pageVisits: current.pageVisits + normalized.pageVisits,
        searches: current.searches + normalized.searches,
        bookmarkActions: current.bookmarkActions + normalized.bookmarkActions,
        downloads: current.downloads + normalized.downloads,
        featureActions: current.featureActions + normalized.featureActions,
        activeSeconds: current.activeSeconds + normalized.activeSeconds,
        updatedAt: Math.max(current.updatedAt, normalized.updatedAt)
      });
    });
    return this.sortAndTrim(Array.from(byDate.values()));
  }

  private normalizeAggregate(
    value: AiraActivityDailyAggregate | undefined
  ): AiraActivityDailyAggregate | undefined {
    const date = `${value?.date ?? ''}`.trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return undefined;
    }
    return {
      date: date,
      score: this.normalizeCount(value?.score),
      pageVisits: this.normalizeCount(value?.pageVisits),
      searches: this.normalizeCount(value?.searches),
      bookmarkActions: this.normalizeCount(value?.bookmarkActions),
      downloads: this.normalizeCount(value?.downloads),
      featureActions: this.normalizeCount(value?.featureActions),
      activeSeconds: this.normalizeCount(value?.activeSeconds),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private maxAggregate(
    left: AiraActivityDailyAggregate,
    right: AiraActivityDailyAggregate
  ): AiraActivityDailyAggregate {
    return {
      date: left.date,
      score: Math.max(left.score, right.score),
      pageVisits: Math.max(left.pageVisits, right.pageVisits),
      searches: Math.max(left.searches, right.searches),
      bookmarkActions: Math.max(left.bookmarkActions, right.bookmarkActions),
      downloads: Math.max(left.downloads, right.downloads),
      featureActions: Math.max(left.featureActions, right.featureActions),
      activeSeconds: Math.max(left.activeSeconds, right.activeSeconds),
      updatedAt: Math.max(left.updatedAt, right.updatedAt)
    };
  }

  private sortAndTrim(values: AiraActivityDailyAggregate[]): AiraActivityDailyAggregate[] {
    return values
      .slice()
      .sort((left: AiraActivityDailyAggregate, right: AiraActivityDailyAggregate): number => {
        return left.date.localeCompare(right.date);
      })
      .slice(-MAX_ACTIVITY_DAYS);
  }

  private createEmptyAggregate(date: string): AiraActivityDailyAggregate {
    return {
      date: date,
      score: 0,
      pageVisits: 0,
      searches: 0,
      bookmarkActions: 0,
      downloads: 0,
      featureActions: 0,
      activeSeconds: 0,
      updatedAt: 0
    };
  }

  private normalizeTimestamp(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    return Number.isFinite(numberValue) && numberValue > 0 ? Math.floor(numberValue) : 0;
  }

  private normalizeCount(value: number | undefined): number {
    const numberValue = Number(value ?? 0);
    return Number.isFinite(numberValue) && numberValue > 0 ? Math.floor(numberValue) : 0;
  }

  private cloneAggregates(values: AiraActivityDailyAggregate[]): AiraActivityDailyAggregate[] {
    return values.map((value: AiraActivityDailyAggregate): AiraActivityDailyAggregate => this.cloneAggregate(value));
  }

  private cloneAggregate(value: AiraActivityDailyAggregate): AiraActivityDailyAggregate {
    return {
      date: value.date,
      score: value.score,
      pageVisits: value.pageVisits,
      searches: value.searches,
      bookmarkActions: value.bookmarkActions,
      downloads: value.downloads,
      featureActions: value.featureActions,
      activeSeconds: value.activeSeconds,
      updatedAt: value.updatedAt
    };
  }
}

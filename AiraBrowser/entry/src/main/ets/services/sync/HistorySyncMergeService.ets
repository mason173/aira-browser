import {
  HISTORY_SYNC_MAX_VISITS,
  HISTORY_SYNC_RETENTION_MS,
  HistorySyncDeleteRange,
  HistorySyncExactTombstone,
  HistorySyncRetentionFrontier,
  HistorySyncVisit,
  HuaweiSpaceHistorySyncState
} from '../../common/models/HistorySyncModels';
import { AiraSyncCooperativeThrottle } from './AiraSyncWorkThrottleService';
import urlUtils from '@ohos.url';

const HISTORY_RETENTION_FRONTIER_GRANULARITY_MS: number = 24 * 60 * 60 * 1000;

export class HistorySyncMergeService {
  emptyState(): HuaweiSpaceHistorySyncState {
    return {
      visits: [],
      tombstones: [],
      deleteRanges: [],
      clearBefore: 0,
      retentionFrontier: this.emptyRetentionFrontier()
    };
  }

  merge(
    preferred: HuaweiSpaceHistorySyncState,
    incoming: HuaweiSpaceHistorySyncState,
    now: number = Date.now()
  ): HuaweiSpaceHistorySyncState {
    return this.mergeInternal(preferred, incoming, now, false);
  }

  mergeKeepingPreferredVisits(
    preferred: HuaweiSpaceHistorySyncState,
    incoming: HuaweiSpaceHistorySyncState,
    now: number = Date.now()
  ): HuaweiSpaceHistorySyncState {
    return this.mergeInternal(preferred, incoming, now, true);
  }

  async mergeCooperatively(
    preferred: HuaweiSpaceHistorySyncState,
    incoming: HuaweiSpaceHistorySyncState,
    throttle: AiraSyncCooperativeThrottle,
    now: number = Date.now()
  ): Promise<HuaweiSpaceHistorySyncState> {
    return this.mergeInternalCooperatively(preferred, incoming, now, false, throttle);
  }

  async mergeKeepingPreferredVisitsCooperatively(
    preferred: HuaweiSpaceHistorySyncState,
    incoming: HuaweiSpaceHistorySyncState,
    throttle: AiraSyncCooperativeThrottle,
    now: number = Date.now()
  ): Promise<HuaweiSpaceHistorySyncState> {
    return this.mergeInternalCooperatively(preferred, incoming, now, true, throttle);
  }

  async sameStateCooperatively(
    left: HuaweiSpaceHistorySyncState,
    right: HuaweiSpaceHistorySyncState,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<boolean> {
    const normalizedLeft = await this.normalizeCooperatively(left, throttle);
    await throttle.afterStage();
    const normalizedRight = await this.normalizeCooperatively(right, throttle);
    if (normalizedLeft.clearBefore !== normalizedRight.clearBefore ||
      JSON.stringify(normalizedLeft.retentionFrontier) !== JSON.stringify(normalizedRight.retentionFrontier) ||
      normalizedLeft.visits.length !== normalizedRight.visits.length ||
      normalizedLeft.tombstones.length !== normalizedRight.tombstones.length ||
      normalizedLeft.deleteRanges.length !== normalizedRight.deleteRanges.length) {
      return false;
    }
    for (let index = 0; index < normalizedLeft.visits.length; index += 1) {
      if (JSON.stringify(normalizedLeft.visits[index]) !== JSON.stringify(normalizedRight.visits[index])) {
        return false;
      }
      await throttle.afterBatchItem(index + 1);
    }
    for (let index = 0; index < normalizedLeft.tombstones.length; index += 1) {
      if (JSON.stringify(normalizedLeft.tombstones[index]) !== JSON.stringify(normalizedRight.tombstones[index])) {
        return false;
      }
      await throttle.afterBatchItem(index + 1);
    }
    for (let index = 0; index < normalizedLeft.deleteRanges.length; index += 1) {
      if (JSON.stringify(normalizedLeft.deleteRanges[index]) !== JSON.stringify(normalizedRight.deleteRanges[index])) {
        return false;
      }
      await throttle.afterBatchItem(index + 1);
    }
    return true;
  }

  async normalizeCooperatively(
    value: HuaweiSpaceHistorySyncState,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistorySyncState> {
    const visits = await this.mergeVisitsCooperatively(
      [],
      Array.isArray(value?.visits) ? value.visits : [],
      false,
      throttle
    );
    const tombstones = await this.mergeTombstonesCooperatively(
      [],
      Array.isArray(value?.tombstones) ? value.tombstones : [],
      throttle
    );
    const deleteRanges = await this.mergeDeleteRangesCooperatively(
      [],
      Array.isArray(value?.deleteRanges) ? value.deleteRanges : [],
      throttle
    );
    const sortedVisits = await this.sortVisitsCooperatively(visits, throttle);
    const sortedTombstones = await this.sortTombstonesCooperatively(tombstones, throttle);
    const sortedDeleteRanges = await this.sortDeleteRangesCooperatively(deleteRanges, throttle);
    return {
      visits: sortedVisits,
      tombstones: sortedTombstones,
      deleteRanges: sortedDeleteRanges,
      clearBefore: this.normalizeTimestamp(value?.clearBefore),
      retentionFrontier: this.normalizeRetentionFrontier(value?.retentionFrontier)
    };
  }

  private async mergeInternalCooperatively(
    preferred: HuaweiSpaceHistorySyncState,
    incoming: HuaweiSpaceHistorySyncState,
    now: number,
    keepPreferredVisitConflicts: boolean,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HuaweiSpaceHistorySyncState> {
    const preferredState = await this.normalizeCooperatively(preferred, throttle);
    await throttle.afterStage();
    const incomingState = await this.normalizeCooperatively(incoming, throttle);
    await throttle.afterStage();
    const tombstones = await this.mergeTombstonesCooperatively(
      preferredState.tombstones,
      incomingState.tombstones,
      throttle
    );
    const deleteRanges = await this.mergeDeleteRangesCooperatively(
      preferredState.deleteRanges,
      incomingState.deleteRanges,
      throttle
    );
    const clearBefore = Math.max(preferredState.clearBefore, incomingState.clearBefore);
    let retentionFrontier = this.mergeRetentionFrontiers(
      preferredState.retentionFrontier,
      incomingState.retentionFrontier
    );
    const retentionCutoff = this.resolveRetentionCutoff(now);
    const durableCutoff = this.resolveDurableRetentionCutoff(retentionCutoff);
    if (durableCutoff > retentionFrontier.cutoffAt) {
      retentionFrontier = {
        cutoffAt: durableCutoff,
        boundaryVisitedAt: retentionFrontier.boundaryVisitedAt,
        boundaryVisitId: retentionFrontier.boundaryVisitId,
        updatedAt: Math.max(retentionFrontier.updatedAt, Math.max(0, Math.floor(now)))
      };
    }
    const mergedVisits = await this.mergeVisitsCooperatively(
      preferredState.visits,
      incomingState.visits,
      keepPreferredVisitConflicts,
      throttle
    );
    const tombstoneIds = new Set<string>();
    for (let index = 0; index < tombstones.length; index += 1) {
      tombstoneIds.add(tombstones[index].visitId);
      await throttle.afterBatchItem(index + 1);
    }
    const rangesByUrl = new Map<string, HistorySyncDeleteRange[]>();
    for (let index = 0; index < deleteRanges.length; index += 1) {
      const range = deleteRanges[index];
      const ranges = rangesByUrl.get(range.url) ?? [];
      ranges.push(range);
      rangesByUrl.set(range.url, ranges);
      await throttle.afterBatchItem(index + 1);
    }
    const visits: HistorySyncVisit[] = [];
    for (let index = 0; index < mergedVisits.length; index += 1) {
      const visit = mergedVisits[index];
      const ranges = rangesByUrl.get(visit.url) ?? [];
      const deletedByRange = ranges.some((range: HistorySyncDeleteRange): boolean => {
        return visit.visitedAt >= range.startedAt && visit.visitedAt <= range.endedAt;
      });
      if (visit.visitedAt >= retentionCutoff && visit.visitedAt > clearBefore &&
        !this.isBehindRetentionFrontier(visit, retentionFrontier) &&
        !tombstoneIds.has(visit.visitId) && !deletedByRange) {
        visits.push(visit);
      }
      await throttle.afterBatchItem(index + 1);
    }
    const sortedVisits = await this.sortVisitsCooperatively(visits, throttle);
    if (sortedVisits.length > HISTORY_SYNC_MAX_VISITS) {
      const boundary = sortedVisits[HISTORY_SYNC_MAX_VISITS - 1];
      const boundaryAdvances = boundary.visitedAt > retentionFrontier.boundaryVisitedAt ||
        (boundary.visitedAt === retentionFrontier.boundaryVisitedAt &&
          boundary.visitId.localeCompare(retentionFrontier.boundaryVisitId) > 0);
      if (boundaryAdvances) {
        retentionFrontier = {
          cutoffAt: retentionFrontier.cutoffAt,
          boundaryVisitedAt: boundary.visitedAt,
          boundaryVisitId: boundary.visitId,
          updatedAt: Math.max(retentionFrontier.updatedAt, Math.max(0, Math.floor(now)))
        };
      }
    }
    const retainedVisits: HistorySyncVisit[] = [];
    for (let index = 0;
      index < sortedVisits.length && retainedVisits.length < HISTORY_SYNC_MAX_VISITS;
      index += 1) {
      if (!this.isBehindRetentionFrontier(sortedVisits[index], retentionFrontier)) {
        retainedVisits.push(sortedVisits[index]);
      }
      await throttle.afterBatchItem(index + 1);
    }
    const retainedTombstones: HistorySyncExactTombstone[] = [];
    for (let index = 0; index < tombstones.length; index += 1) {
      if (tombstones[index].deletedAt >= retentionCutoff) {
        retainedTombstones.push(tombstones[index]);
      }
      await throttle.afterBatchItem(index + 1);
    }
    const retainedRanges: HistorySyncDeleteRange[] = [];
    for (let index = 0; index < deleteRanges.length; index += 1) {
      if (deleteRanges[index].endedAt >= retentionCutoff) {
        retainedRanges.push(deleteRanges[index]);
      }
      await throttle.afterBatchItem(index + 1);
    }
    return {
      visits: retainedVisits,
      tombstones: retainedTombstones,
      deleteRanges: retainedRanges,
      clearBefore,
      retentionFrontier
    };
  }

  private async sortVisitsCooperatively(
    values: HistorySyncVisit[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HistorySyncVisit[]> {
    if (values.length <= 1) {
      return values.slice();
    }
    let source = values.slice();
    let target = values.slice();
    let width = 1;
    let processed = 0;
    while (width < source.length) {
      for (let start = 0; start < source.length; start += width * 2) {
        let left = start;
        const leftEnd = Math.min(start + width, source.length);
        let right = leftEnd;
        const rightEnd = Math.min(start + width * 2, source.length);
        let output = start;
        while (left < leftEnd || right < rightEnd) {
          if (right >= rightEnd ||
            (left < leftEnd && this.compareVisits(source[left], source[right]) <= 0)) {
            target[output] = source[left];
            left += 1;
          } else {
            target[output] = source[right];
            right += 1;
          }
          output += 1;
          processed += 1;
          await throttle.afterBatchItem(processed);
        }
      }
      const swap = source;
      source = target;
      target = swap;
      width *= 2;
      await throttle.afterStage();
    }
    return source;
  }

  private async sortTombstonesCooperatively(
    values: HistorySyncExactTombstone[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HistorySyncExactTombstone[]> {
    if (values.length <= 1) {
      return values.slice();
    }
    let source = values.slice();
    let target = values.slice();
    let width = 1;
    let processed = 0;
    while (width < source.length) {
      for (let start = 0; start < source.length; start += width * 2) {
        let left = start;
        const leftEnd = Math.min(start + width, source.length);
        let right = leftEnd;
        const rightEnd = Math.min(start + width * 2, source.length);
        let output = start;
        while (left < leftEnd || right < rightEnd) {
          if (right >= rightEnd ||
            (left < leftEnd && source[left].visitId.localeCompare(source[right].visitId) <= 0)) {
            target[output] = source[left];
            left += 1;
          } else {
            target[output] = source[right];
            right += 1;
          }
          output += 1;
          processed += 1;
          await throttle.afterBatchItem(processed);
        }
      }
      const swap = source;
      source = target;
      target = swap;
      width *= 2;
      await throttle.afterStage();
    }
    return source;
  }

  private async sortDeleteRangesCooperatively(
    values: HistorySyncDeleteRange[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HistorySyncDeleteRange[]> {
    if (values.length <= 1) {
      return values.slice();
    }
    let source = values.slice();
    let target = values.slice();
    let width = 1;
    let processed = 0;
    while (width < source.length) {
      for (let start = 0; start < source.length; start += width * 2) {
        let left = start;
        const leftEnd = Math.min(start + width, source.length);
        let right = leftEnd;
        const rightEnd = Math.min(start + width * 2, source.length);
        let output = start;
        while (left < leftEnd || right < rightEnd) {
          if (right >= rightEnd ||
            (left < leftEnd && source[left].rangeId.localeCompare(source[right].rangeId) <= 0)) {
            target[output] = source[left];
            left += 1;
          } else {
            target[output] = source[right];
            right += 1;
          }
          output += 1;
          processed += 1;
          await throttle.afterBatchItem(processed);
        }
      }
      const swap = source;
      source = target;
      target = swap;
      width *= 2;
      await throttle.afterStage();
    }
    return source;
  }

  private mergeInternal(
    preferred: HuaweiSpaceHistorySyncState,
    incoming: HuaweiSpaceHistorySyncState,
    now: number,
    keepPreferredVisitConflicts: boolean
  ): HuaweiSpaceHistorySyncState {
    const preferredState = this.normalize(preferred);
    const incomingState = this.normalize(incoming);
    const tombstones = this.mergeTombstones(preferredState.tombstones, incomingState.tombstones);
    const deleteRanges = this.mergeDeleteRanges(preferredState.deleteRanges, incomingState.deleteRanges);
    const clearBefore = Math.max(preferredState.clearBefore, incomingState.clearBefore);
    let retentionFrontier = this.mergeRetentionFrontiers(
      preferredState.retentionFrontier,
      incomingState.retentionFrontier
    );
    const retentionCutoff = this.resolveRetentionCutoff(now);
    const durableCutoff = this.resolveDurableRetentionCutoff(retentionCutoff);
    if (durableCutoff > retentionFrontier.cutoffAt) {
      retentionFrontier = {
        cutoffAt: durableCutoff,
        boundaryVisitedAt: retentionFrontier.boundaryVisitedAt,
        boundaryVisitId: retentionFrontier.boundaryVisitId,
        updatedAt: Math.max(retentionFrontier.updatedAt, Math.max(0, Math.floor(now)))
      };
    }
    const visits = this.mergeVisits(
      preferredState.visits,
      incomingState.visits,
      keepPreferredVisitConflicts
    )
      .filter((visit: HistorySyncVisit): boolean => {
        return visit.visitedAt >= retentionCutoff &&
          !this.isDeleted(visit, tombstones, deleteRanges, clearBefore, retentionFrontier);
      })
      .sort((left: HistorySyncVisit, right: HistorySyncVisit): number => this.compareVisits(left, right));
    if (visits.length > HISTORY_SYNC_MAX_VISITS) {
      const boundary = visits[HISTORY_SYNC_MAX_VISITS - 1];
      const boundaryAdvances = boundary.visitedAt > retentionFrontier.boundaryVisitedAt ||
        (boundary.visitedAt === retentionFrontier.boundaryVisitedAt &&
          boundary.visitId.localeCompare(retentionFrontier.boundaryVisitId) > 0);
      if (boundaryAdvances) {
        retentionFrontier = {
          cutoffAt: retentionFrontier.cutoffAt,
          boundaryVisitedAt: boundary.visitedAt,
          boundaryVisitId: boundary.visitId,
          updatedAt: Math.max(retentionFrontier.updatedAt, Math.max(0, Math.floor(now)))
        };
      }
    }
    const retainedVisits = visits
      .filter((visit: HistorySyncVisit): boolean => !this.isBehindRetentionFrontier(visit, retentionFrontier))
      .slice(0, HISTORY_SYNC_MAX_VISITS);
    const retainedTombstones = tombstones.filter((value: HistorySyncExactTombstone): boolean => {
      return value.deletedAt >= retentionCutoff;
    });
    const retainedRanges = deleteRanges.filter((value: HistorySyncDeleteRange): boolean => {
      return value.endedAt >= retentionCutoff;
    });
    return {
      visits: retainedVisits,
      tombstones: retainedTombstones,
      deleteRanges: retainedRanges,
      clearBefore,
      retentionFrontier
    };
  }

  sameState(left: HuaweiSpaceHistorySyncState, right: HuaweiSpaceHistorySyncState): boolean {
    return JSON.stringify(this.normalize(left)) === JSON.stringify(this.normalize(right));
  }

  normalize(value: HuaweiSpaceHistorySyncState): HuaweiSpaceHistorySyncState {
    const visits = this.mergeVisits([], Array.isArray(value?.visits) ? value.visits : []);
    const tombstones = this.mergeTombstones([], Array.isArray(value?.tombstones) ? value.tombstones : []);
    const deleteRanges = this.mergeDeleteRanges([], Array.isArray(value?.deleteRanges) ? value.deleteRanges : []);
    return {
      visits: visits.sort((left: HistorySyncVisit, right: HistorySyncVisit): number => {
        return this.compareVisits(left, right);
      }),
      tombstones: tombstones.sort((left: HistorySyncExactTombstone, right: HistorySyncExactTombstone): number => {
        return left.visitId.localeCompare(right.visitId);
      }),
      deleteRanges: deleteRanges.sort((left: HistorySyncDeleteRange, right: HistorySyncDeleteRange): number => {
        return left.rangeId.localeCompare(right.rangeId);
      }),
      clearBefore: this.normalizeTimestamp(value?.clearBefore),
      retentionFrontier: this.normalizeRetentionFrontier(value?.retentionFrontier)
    };
  }

  private mergeVisits(
    preferred: HistorySyncVisit[],
    incoming: HistorySyncVisit[],
    keepPreferredConflicts: boolean = false
  ): HistorySyncVisit[] {
    const visits = new Map<string, HistorySyncVisit>();
    preferred.concat(incoming).forEach((visit: HistorySyncVisit): void => {
      const normalized = this.normalizeVisit(visit);
      if (normalized === undefined) {
        return;
      }
      const existing = visits.get(normalized.visitId);
      if (existing === undefined) {
        visits.set(normalized.visitId, normalized);
        return;
      }
      if (JSON.stringify(existing) === JSON.stringify(normalized)) {
        return;
      }
      if (keepPreferredConflicts) {
        return;
      }
      throw new Error('华为云空间存在内容不一致的历史访问标识，已停止同步。');
    });
    return Array.from(visits.values());
  }

  private async mergeVisitsCooperatively(
    preferred: HistorySyncVisit[],
    incoming: HistorySyncVisit[],
    keepPreferredConflicts: boolean,
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HistorySyncVisit[]> {
    const visits = new Map<string, HistorySyncVisit>();
    const values = preferred.concat(incoming);
    for (let index = 0; index < values.length; index += 1) {
      const normalized = this.normalizeVisit(values[index]);
      if (normalized !== undefined) {
        const existing = visits.get(normalized.visitId);
        if (existing === undefined) {
          visits.set(normalized.visitId, normalized);
        } else if (JSON.stringify(existing) !== JSON.stringify(normalized) && !keepPreferredConflicts) {
          throw new Error('华为云空间存在内容不一致的历史访问标识，已停止同步。');
        }
      }
      await throttle.afterBatchItem(index + 1);
    }
    return Array.from(visits.values());
  }

  private mergeTombstones(
    left: HistorySyncExactTombstone[],
    right: HistorySyncExactTombstone[]
  ): HistorySyncExactTombstone[] {
    const values = new Map<string, HistorySyncExactTombstone>();
    left.concat(right).forEach((value: HistorySyncExactTombstone): void => {
      const visitId = (value?.visitId ?? '').trim();
      const deletedAt = this.normalizeTimestamp(value?.deletedAt);
      if (visitId.length <= 0 || deletedAt <= 0) {
        return;
      }
      const existing = values.get(visitId);
      if (existing === undefined || deletedAt > existing.deletedAt) {
        values.set(visitId, { visitId, deletedAt });
      }
    });
    return Array.from(values.values());
  }

  private async mergeTombstonesCooperatively(
    left: HistorySyncExactTombstone[],
    right: HistorySyncExactTombstone[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HistorySyncExactTombstone[]> {
    const values = new Map<string, HistorySyncExactTombstone>();
    const candidates = left.concat(right);
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index];
      const visitId = (value?.visitId ?? '').trim();
      const deletedAt = this.normalizeTimestamp(value?.deletedAt);
      const existing = values.get(visitId);
      if (visitId.length > 0 && deletedAt > 0 && (existing === undefined || deletedAt > existing.deletedAt)) {
        values.set(visitId, { visitId, deletedAt });
      }
      await throttle.afterBatchItem(index + 1);
    }
    return Array.from(values.values());
  }

  private mergeDeleteRanges(left: HistorySyncDeleteRange[], right: HistorySyncDeleteRange[]): HistorySyncDeleteRange[] {
    const values = new Map<string, HistorySyncDeleteRange>();
    left.concat(right).forEach((value: HistorySyncDeleteRange): void => {
      const rangeId = (value?.rangeId ?? '').trim();
      const url = this.normalizeUrl(value?.url ?? '');
      const startedAt = this.normalizeTimestamp(value?.startedAt);
      const endedAt = this.normalizeTimestamp(value?.endedAt);
      const seq = this.normalizeTimestamp(value?.seq);
      if (rangeId.length <= 0 || url.length <= 0 || endedAt < startedAt) {
        return;
      }
      const candidate: HistorySyncDeleteRange = { rangeId, url, startedAt, endedAt, seq };
      const existing = values.get(rangeId);
      if (existing === undefined) {
        values.set(rangeId, candidate);
        return;
      }
      if (JSON.stringify(existing) !== JSON.stringify(candidate)) {
        throw new Error('华为云空间存在内容不一致的历史删除范围，已停止同步。');
      }
    });
    return Array.from(values.values());
  }

  private async mergeDeleteRangesCooperatively(
    left: HistorySyncDeleteRange[],
    right: HistorySyncDeleteRange[],
    throttle: AiraSyncCooperativeThrottle
  ): Promise<HistorySyncDeleteRange[]> {
    const values = new Map<string, HistorySyncDeleteRange>();
    const candidates = left.concat(right);
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index];
      const rangeId = (value?.rangeId ?? '').trim();
      const url = this.normalizeUrl(value?.url ?? '');
      const startedAt = this.normalizeTimestamp(value?.startedAt);
      const endedAt = this.normalizeTimestamp(value?.endedAt);
      const seq = this.normalizeTimestamp(value?.seq);
      if (rangeId.length > 0 && url.length > 0 && endedAt >= startedAt) {
        const candidate: HistorySyncDeleteRange = { rangeId, url, startedAt, endedAt, seq };
        const existing = values.get(rangeId);
        if (existing === undefined) {
          values.set(rangeId, candidate);
        } else if (JSON.stringify(existing) !== JSON.stringify(candidate)) {
          throw new Error('华为云空间存在内容不一致的历史删除范围，已停止同步。');
        }
      }
      await throttle.afterBatchItem(index + 1);
    }
    return Array.from(values.values());
  }

  private mergeRetentionFrontiers(
    left: HistorySyncRetentionFrontier,
    right: HistorySyncRetentionFrontier
  ): HistorySyncRetentionFrontier {
    const normalizedLeft = this.normalizeRetentionFrontier(left);
    const normalizedRight = this.normalizeRetentionFrontier(right);
    const boundary = this.compareBoundary(normalizedLeft, normalizedRight) >= 0
      ? normalizedLeft
      : normalizedRight;
    return {
      cutoffAt: Math.max(normalizedLeft.cutoffAt, normalizedRight.cutoffAt),
      boundaryVisitedAt: boundary.boundaryVisitedAt,
      boundaryVisitId: boundary.boundaryVisitId,
      updatedAt: Math.max(normalizedLeft.updatedAt, normalizedRight.updatedAt)
    };
  }

  private isDeleted(
    visit: HistorySyncVisit,
    tombstones: HistorySyncExactTombstone[],
    ranges: HistorySyncDeleteRange[],
    clearBefore: number,
    retentionFrontier: HistorySyncRetentionFrontier
  ): boolean {
    if (visit.visitedAt <= clearBefore || this.isBehindRetentionFrontier(visit, retentionFrontier)) {
      return true;
    }
    if (tombstones.some((value: HistorySyncExactTombstone): boolean => value.visitId === visit.visitId)) {
      return true;
    }
    return ranges.some((range: HistorySyncDeleteRange): boolean => {
      return range.url === visit.url && visit.visitedAt >= range.startedAt && visit.visitedAt <= range.endedAt;
    });
  }

  private isBehindRetentionFrontier(
    visit: HistorySyncVisit,
    frontier: HistorySyncRetentionFrontier
  ): boolean {
    if (visit.visitedAt < frontier.cutoffAt) {
      return true;
    }
    if (frontier.boundaryVisitedAt <= 0) {
      return false;
    }
    if (visit.visitedAt !== frontier.boundaryVisitedAt) {
      return visit.visitedAt < frontier.boundaryVisitedAt;
    }
    return visit.visitId.localeCompare(frontier.boundaryVisitId) < 0;
  }

  private normalizeVisit(value: HistorySyncVisit): HistorySyncVisit | undefined {
    const visitId = (value?.visitId ?? '').trim();
    const clientId = (value?.clientId ?? '').trim();
    const nativeVisitId = (value?.nativeVisitId ?? '').trim();
    const url = this.normalizeUrl(value?.url ?? '');
    const visitedAt = this.normalizeTimestamp(value?.visitedAt);
    if (visitId.length <= 0 || clientId.length <= 0 || nativeVisitId.length <= 0 ||
      url.length <= 0 || visitedAt <= 0 || visitId !== `h1:${clientId}:${nativeVisitId}`) {
      return undefined;
    }
    return {
      visitId,
      clientId,
      nativeVisitId,
      url,
      title: value.title ?? '',
      visitedAt,
      transition: value.transition ?? 'link',
      referrer: value.referrer ?? '',
      deviceName: value.deviceName ?? '',
      source: value.source ?? ''
    };
  }

  private normalizeRetentionFrontier(value: HistorySyncRetentionFrontier): HistorySyncRetentionFrontier {
    return {
      cutoffAt: this.normalizeTimestamp(value?.cutoffAt),
      boundaryVisitedAt: this.normalizeTimestamp(value?.boundaryVisitedAt),
      boundaryVisitId: (value?.boundaryVisitId ?? '').trim(),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private emptyRetentionFrontier(): HistorySyncRetentionFrontier {
    return { cutoffAt: 0, boundaryVisitedAt: 0, boundaryVisitId: '', updatedAt: 0 };
  }

  private resolveRetentionCutoff(now: number): number {
    return Math.max(0, Math.floor(now) - HISTORY_SYNC_RETENTION_MS);
  }

  private resolveDurableRetentionCutoff(cutoff: number): number {
    return Math.floor(Math.max(0, cutoff) / HISTORY_RETENTION_FRONTIER_GRANULARITY_MS) *
      HISTORY_RETENTION_FRONTIER_GRANULARITY_MS;
  }

  private compareVisits(left: HistorySyncVisit, right: HistorySyncVisit): number {
    if (left.visitedAt !== right.visitedAt) {
      return right.visitedAt - left.visitedAt;
    }
    return right.visitId.localeCompare(left.visitId);
  }

  private compareBoundary(left: HistorySyncRetentionFrontier, right: HistorySyncRetentionFrontier): number {
    if (left.boundaryVisitedAt !== right.boundaryVisitedAt) {
      return left.boundaryVisitedAt - right.boundaryVisitedAt;
    }
    return left.boundaryVisitId.localeCompare(right.boundaryVisitId);
  }

  private normalizeTimestamp(value: number | undefined): number {
    const candidate = Number(value ?? 0);
    return Number.isFinite(candidate) && candidate > 0 ? Math.floor(candidate) : 0;
  }

  private normalizeUrl(value: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(value.trim());
      const protocol = parsed.protocol.trim().toLowerCase();
      if ((protocol !== 'http:' && protocol !== 'https:') || parsed.hostname.trim().length <= 0) {
        return '';
      }
      return parsed.href;
    } catch (_error) {
      return '';
    }
  }
}

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ActivityRepository } from '../../data/activity/ActivityRepository';
import {
  AiraActivityDailyAggregate,
  AiraActivityEventKind,
  AiraActivityRecordOptions,
  AiraActivityStoreState
} from '../../common/models/ActivityModels';
import { ActivityScoreService } from './ActivityScoreService';
import { ActivityContributionService } from './ActivityContributionService';

const DOMAIN = 0x0000;
const TAG = 'ActivityTracker';
const FLUSH_INTERVAL_MS: number = 5 * 60 * 1000;
const MIN_DEFERRED_FLUSH_MS: number = 30 * 1000;
const FLUSH_EVENT_THRESHOLD: number = 80;
const MAX_BUFFER_DAYS: number = 8;

export type ActivityLocalFlushHandler = () => void;

export class ActivityTracker {
  private repository: ActivityRepository;
  private accountUidProvider: () => string;
  private localFlushHandler?: ActivityLocalFlushHandler;
  private scoreService: ActivityScoreService;
  private contributionService: ActivityContributionService;
  private buffer: AiraActivityDailyAggregate[] = [];
  private bufferAccountUid: string = '';
  private bufferedEventCount: number = 0;
  private lastFlushAt: number = 0;
  private flushTimer: number = -1;
  private flushDueAt: number = 0;
  private flushPromise?: Promise<void>;

  constructor(
    repository: ActivityRepository,
    accountUidProvider: () => string = () => '',
    localFlushHandler?: ActivityLocalFlushHandler,
    scoreService: ActivityScoreService = new ActivityScoreService(),
    contributionService: ActivityContributionService = new ActivityContributionService()
  ) {
    this.repository = repository;
    this.accountUidProvider = accountUidProvider;
    this.localFlushHandler = localFlushHandler;
    this.scoreService = scoreService;
    this.contributionService = contributionService;
  }

  record(kind: AiraActivityEventKind, options: AiraActivityRecordOptions = {}): void {
    this.prepareBufferForCurrentAccount();
    const aggregate = this.scoreService.buildEventAggregate(kind, options);
    this.buffer = this.mergeIntoBuffer(this.buffer, aggregate);
    this.bufferedEventCount += 1;
    if (this.shouldFlushSoon(Date.now())) {
      this.ensureFlushTimer(MIN_DEFERRED_FLUSH_MS);
    } else {
      this.ensureFlushTimer(FLUSH_INTERVAL_MS);
    }
  }

  recordPageVisit(timestamp: number = Date.now()): void {
    this.record('page_visit', { timestamp });
  }

  recordSearch(timestamp: number = Date.now()): void {
    this.record('search', { timestamp });
  }

  recordBookmarkAction(timestamp: number = Date.now()): void {
    this.record('bookmark_action', { timestamp });
  }

  recordDownloadComplete(timestamp: number = Date.now()): void {
    this.record('download_complete', { timestamp });
  }

  recordFeatureAction(timestamp: number = Date.now(), score?: number): void {
    this.record('feature_action', { timestamp, score });
  }

  recordActiveSeconds(seconds: number, timestamp: number = Date.now()): void {
    const normalizedSeconds = Math.max(0, Math.round(seconds));
    if (normalizedSeconds <= 0) {
      return;
    }
    this.prepareBufferForCurrentAccount();
    this.buffer = this.mergeIntoBuffer(this.buffer, {
      date: this.scoreService.toLocalDateKey(timestamp),
      score: Math.max(1, Math.min(8, Math.ceil(normalizedSeconds / 60))),
      pageVisits: 0,
      searches: 0,
      bookmarkActions: 0,
      downloads: 0,
      featureActions: 0,
      activeSeconds: normalizedSeconds,
      updatedAt: timestamp
    });
    this.bufferedEventCount += 1;
    if (this.shouldFlushSoon(Date.now())) {
      this.ensureFlushTimer(MIN_DEFERRED_FLUSH_MS);
    } else {
      this.ensureFlushTimer(FLUSH_INTERVAL_MS);
    }
  }

  flushDeferred(delayMs: number = FLUSH_INTERVAL_MS): void {
    if (this.buffer.length === 0 || this.flushPromise !== undefined) {
      return;
    }
    this.ensureFlushTimer(Math.max(0, delayMs));
  }

  async flush(): Promise<void> {
    if (this.flushPromise !== undefined) {
      return this.flushPromise;
    }
    this.clearFlushTimer();
    if (this.buffer.length === 0) {
      return Promise.resolve();
    }
    const pending = this.buffer.map((item: AiraActivityDailyAggregate) => this.scoreService.applyDailyCaps(item));
    this.buffer = [];
    this.bufferedEventCount = 0;
    this.lastFlushAt = Date.now();
    const accountUid = this.resolveCurrentAccountUid();
    if (this.bufferAccountUid !== accountUid) {
      return Promise.resolve();
    }
    this.flushPromise = this.repository.updateActivityState(
      accountUid,
      (state: AiraActivityStoreState) => {
        return this.contributionService.mergeLocalActivity(
          state.totals,
          state.localContributions,
          pending
        );
      },
      this.lastFlushAt
    )
      .then(() => {
        this.notifyLocalFlush();
      })
      .catch((error: Error) => {
        this.buffer = this.mergeManyIntoBuffer(this.buffer, pending);
        hilog.warn(DOMAIN, TAG, 'activity flush failed: %{public}s', JSON.stringify(error));
      })
      .finally(() => {
        this.flushPromise = undefined;
      });
    return this.flushPromise;
  }

  private prepareBufferForCurrentAccount(): void {
    const accountUid = this.resolveCurrentAccountUid();
    if (this.buffer.length <= 0) {
      this.bufferAccountUid = accountUid;
      return;
    }
    if (this.bufferAccountUid === accountUid) {
      return;
    }
    this.buffer = [];
    this.bufferedEventCount = 0;
    this.bufferAccountUid = accountUid;
  }

  private resolveCurrentAccountUid(): string {
    return this.accountUidProvider().trim();
  }

  private shouldFlushSoon(now: number): boolean {
    if (this.bufferedEventCount >= FLUSH_EVENT_THRESHOLD) {
      return true;
    }
    if (this.lastFlushAt <= 0) {
      return false;
    }
    return now - this.lastFlushAt >= FLUSH_INTERVAL_MS;
  }

  private ensureFlushTimer(delayMs: number): void {
    const dueAt = Date.now() + delayMs;
    if (this.flushTimer >= 0) {
      if (this.flushDueAt > 0 && this.flushDueAt <= dueAt) {
        return;
      }
      clearTimeout(this.flushTimer);
    }
    this.flushDueAt = dueAt;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = -1;
      this.flushDueAt = 0;
      void this.flush();
    }, delayMs);
  }

  private clearFlushTimer(): void {
    if (this.flushTimer < 0) {
      return;
    }
    clearTimeout(this.flushTimer);
    this.flushTimer = -1;
    this.flushDueAt = 0;
  }

  private notifyLocalFlush(): void {
    if (this.localFlushHandler === undefined) {
      return;
    }
    try {
      this.localFlushHandler();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'activity local flush notification failed: %{public}s', JSON.stringify(error));
    }
  }

  private mergeManyIntoBuffer(
    buffer: AiraActivityDailyAggregate[],
    items: AiraActivityDailyAggregate[]
  ): AiraActivityDailyAggregate[] {
    let next = buffer;
    items.forEach((item: AiraActivityDailyAggregate) => {
      next = this.mergeIntoBuffer(next, item);
    });
    return next;
  }

  private mergeIntoBuffer(
    buffer: AiraActivityDailyAggregate[],
    item: AiraActivityDailyAggregate
  ): AiraActivityDailyAggregate[] {
    const next = buffer.slice();
    const index = next.findIndex((candidate: AiraActivityDailyAggregate) => candidate.date === item.date);
    if (index < 0) {
      next.push(item);
      return next.slice(-MAX_BUFFER_DAYS);
    }
    const current = next[index];
    next[index] = {
      date: current.date,
      score: current.score + item.score,
      pageVisits: current.pageVisits + item.pageVisits,
      searches: current.searches + item.searches,
      bookmarkActions: current.bookmarkActions + item.bookmarkActions,
      downloads: current.downloads + item.downloads,
      featureActions: current.featureActions + item.featureActions,
      activeSeconds: current.activeSeconds + item.activeSeconds,
      updatedAt: Math.max(current.updatedAt, item.updatedAt)
    };
    return next.slice(-MAX_BUFFER_DAYS);
  }
}

import {
  AiraActivityDailyAggregate,
  AiraActivityEventKind,
  AiraActivityRecordOptions
} from '../../common/models/ActivityModels';

const DAY_MS: number = 24 * 60 * 60 * 1000;
const PAGE_VISIT_DAILY_SCORE_CAP: number = 120;

export class ActivityScoreService {
  buildEventAggregate(kind: AiraActivityEventKind, options: AiraActivityRecordOptions = {}): AiraActivityDailyAggregate {
    const timestamp = options.timestamp !== undefined && options.timestamp > 0 ? options.timestamp : Date.now();
    const score = this.resolveScore(kind, options.score);
    const aggregate = this.createEmptyAggregate(this.toLocalDateKey(timestamp), timestamp);
    aggregate.score = score;
    if (kind === 'page_visit') {
      aggregate.pageVisits = 1;
    } else if (kind === 'search') {
      aggregate.searches = 1;
    } else if (kind === 'bookmark_action') {
      aggregate.bookmarkActions = 1;
    } else if (kind === 'download_complete') {
      aggregate.downloads = 1;
    } else {
      aggregate.featureActions = 1;
    }
    return aggregate;
  }

  applyDailyCaps(item: AiraActivityDailyAggregate): AiraActivityDailyAggregate {
    const pageVisits = Math.min(Math.max(0, item.pageVisits), PAGE_VISIT_DAILY_SCORE_CAP);
    const nonPageScore = Math.max(0, item.score - item.pageVisits);
    return {
      date: item.date,
      score: Math.min(pageVisits + nonPageScore, 240),
      pageVisits,
      searches: Math.max(0, item.searches),
      bookmarkActions: Math.max(0, item.bookmarkActions),
      downloads: Math.max(0, item.downloads),
      featureActions: Math.max(0, item.featureActions),
      activeSeconds: Math.max(0, item.activeSeconds),
      updatedAt: item.updatedAt
    };
  }

  toLocalDateKey(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.pad2(date.getMonth() + 1);
    const day = this.pad2(date.getDate());
    return `${year}-${month}-${day}`;
  }

  dateKeyToTimestamp(dateKey: string): number {
    const parts = dateKey.split('-');
    if (parts.length !== 3) {
      return 0;
    }
    const year = Number(parts[0]);
    const month = Number(parts[1]);
    const day = Number(parts[2]);
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
      return 0;
    }
    return new Date(year, month - 1, day).getTime();
  }

  shiftDateKey(dateKey: string, offsetDays: number): string {
    const timestamp = this.dateKeyToTimestamp(dateKey);
    return this.toLocalDateKey(timestamp + offsetDays * DAY_MS);
  }

  private resolveScore(kind: AiraActivityEventKind, override: number | undefined): number {
    if (override !== undefined && Number.isFinite(override) && override > 0) {
      return Math.round(override);
    }
    if (kind === 'search') {
      return 2;
    }
    if (kind === 'bookmark_action') {
      return 4;
    }
    if (kind === 'download_complete') {
      return 3;
    }
    if (kind === 'feature_action') {
      return 2;
    }
    return 1;
  }

  private createEmptyAggregate(date: string, updatedAt: number): AiraActivityDailyAggregate {
    return {
      date,
      score: 0,
      pageVisits: 0,
      searches: 0,
      bookmarkActions: 0,
      downloads: 0,
      featureActions: 0,
      activeSeconds: 0,
      updatedAt
    };
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}

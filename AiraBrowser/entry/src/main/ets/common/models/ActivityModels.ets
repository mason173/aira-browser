export type AiraActivityEventKind =
  'page_visit' |
  'search' |
  'bookmark_action' |
  'download_complete' |
  'feature_action';

export interface AiraActivityDailyAggregate {
  date: string;
  score: number;
  pageVisits: number;
  searches: number;
  bookmarkActions: number;
  downloads: number;
  featureActions: number;
  activeSeconds: number;
  updatedAt: number;
}

export interface AiraActivityStoreState {
  accountUid: string;
  totals: AiraActivityDailyAggregate[];
  localContributions: AiraActivityDailyAggregate[];
  localBackupTotalsFloor: AiraActivityDailyAggregate[];
  g2VisibleHistorySeed: AiraActivityDailyAggregate[];
  g2VisibleHistorySeedPrepared: boolean;
  updatedAt: number;
}

export interface AiraActivityRecordOptions {
  timestamp?: number;
  score?: number;
}

export interface AiraActivityHeatmapCellState {
  date: string;
  dayOfMonth: string;
  count: number;
  level: number;
  isToday: boolean;
  isFuture: boolean;
  tooltipText: string;
  accessibilityText: string;
}

export interface AiraActivityHeatmapViewState {
  title: string;
  summary: string;
  cells: AiraActivityHeatmapCellState[];
  weekCount: number;
  legendLevels: number[];
  maxLevel: number;
  hasActivity: boolean;
}

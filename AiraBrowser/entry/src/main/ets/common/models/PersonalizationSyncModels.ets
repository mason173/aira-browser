import { AiraActivityDailyAggregate } from './ActivityModels';
import {
  BrowserBottomToolbarScrollBehavior,
  BrowserHomeShortcutLayoutDensity,
  BrowserPrivateTabRestorePolicy,
  BrowserStartupRestorePolicy,
  BrowserTabAutoClosePolicy,
  BrowserThemeMode,
  BrowserThemePaletteId,
  BrowserTabsOverviewLayoutStyle,
  SearchEngineSettings,
  ShortcutRecord,
  ShortcutScenarioRecord
} from './BrowserModels';
import { WallpaperMode } from './WallpaperModels';

export const PERSONALIZATION_SYNC_SCHEMA_VERSION: number = 2;

export type PersonalizationSyncItemId =
  | 'home_shortcuts'
  | 'core_preferences'
  | 'activity_heatmap'
  | 'search';

export type PersonalizationSyncContentId = PersonalizationSyncItemId | 'novel_bookshelf';

export interface PersonalizationSyncItemSetting {
  id: PersonalizationSyncItemId;
  enabled: boolean;
  updatedAt: number;
}

export interface PersonalizationSyncSectionState {
  id: PersonalizationSyncItemId;
  enabled: boolean;
  updatedAt: number;
  checksum: string;
}

export interface PersonalizationSyncItemTombstone {
  id: string;
  deletedAt: number;
}

export interface PersonalizationSyncDeletionState extends PersonalizationSyncItemTombstone {
  sectionId: PersonalizationSyncItemId;
}

export type PersonalizationSyncItemDeletionRecorder = (itemId: string, deletedAt: number) => Promise<void>;

export interface PersonalizationSyncConfig {
  items: PersonalizationSyncItemSetting[];
  sections: PersonalizationSyncSectionState[];
  deletions: PersonalizationSyncDeletionState[];
  lastSyncAt: number;
  updatedAt: number;
}

export interface PersonalizationSyncSection {
  enabled: boolean;
  updatedAt: number;
  payload: Object;
}

export interface PersonalizationSyncSnapshot {
  meta: PersonalizationSyncSnapshotMeta;
  sections: Record<string, PersonalizationSyncSection>;
  checksum?: string;
}

export interface PersonalizationSyncSnapshotMeta {
  version: number;
  deviceId: string;
  generatedAt: string;
}

export interface PersonalizationActivityContribution {
  sourceId: string;
  items: AiraActivityDailyAggregate[];
  updatedAt: number;
}

export interface PersonalizationActivityHeatmapPayload {
  contributions: PersonalizationActivityContribution[];
}

export interface PersonalizationHomeShortcutsPayload {
  scenarios: ShortcutScenarioRecord[];
  shortcuts: ShortcutRecord[];
  orders: PersonalizationHomeShortcutOrder[];
}

export interface PersonalizationHomeShortcutOrder {
  scenarioId: string;
  shortcutIds: string[];
  updatedAt: number;
}

export interface PersonalizationCorePreferencesPayload {
  themeMode?: BrowserThemeMode;
  appearance?: PersonalizationCoreAppearancePreferences;
  general?: PersonalizationCoreGeneralPreferences;
  toolbarLayout?: PersonalizationCoreToolbarLayoutPreferences;
}

export interface PersonalizationCoreAppearancePreferences {
  bottomToolbarScrollBehavior?: BrowserBottomToolbarScrollBehavior;
  globalImmersionEnabled?: boolean;
  alwaysTopImmersionEnabled?: boolean;
  forceDarkWebContentEnabled?: boolean;
  blurPrivateTabPreviews?: boolean;
  showHomeRecentlyClosed?: boolean;
  showHomeShortcuts?: boolean;
  showHomeFavoritesTitle?: boolean;
  showHomeShortcutNames?: boolean;
  showHomeRecentlyClosedTitle?: boolean;
  showHomeSettingsButton?: boolean;
  showHomeSystemSearch?: boolean;
  hideHomeSystemSearchOnScroll?: boolean;
  homeWallpaperMode?: WallpaperMode;
  homeRecentlyClosedLimit?: number;
  homeShortcutLayoutDensity?: BrowserHomeShortcutLayoutDensity;
  homeShortcutIconSizeRatio?: number;
  siteIconCornerRadiusRatio?: number;
  themePaletteId?: BrowserThemePaletteId;
  tabsOverviewLayoutStyle?: BrowserTabsOverviewLayoutStyle;
  tabsOverviewCloseButtonAlwaysVisible?: boolean;
}

export type PersonalizationSettingsChangeOrigin = 'local' | 'sync' | 'system';
export type PersonalizationSettingsLocalChangeHandler = () => void;

export interface PersonalizationCoreGeneralPreferences {
  startupRestorePolicy?: BrowserStartupRestorePolicy;
  tabAutoClosePolicy?: BrowserTabAutoClosePolicy;
  privateTabRestorePolicy?: BrowserPrivateTabRestorePolicy;
  privateModeThemeEnabled?: boolean;
}

export interface PersonalizationCoreToolbarLayoutPreferences {
  primaryActionIds?: string[];
  secondaryActionIds?: string[];
  updatedAt?: number;
}

export interface PersonalizationSearchPayload {
  settings: SearchEngineSettings;
  tombstones: PersonalizationSyncItemTombstone[];
}

export interface PersonalizationCollectionPayload {
  tombstones?: PersonalizationSyncItemTombstone[];
}

export interface PersonalizationSyncRemoteState {
  snapshot: PersonalizationSyncSnapshot | null;
  revision: string;
  headSnapshots?: PersonalizationSyncSnapshot[];
}

export interface PersonalizationSyncWriteResult {
  revision: string;
}

export interface PersonalizationSyncRemoteStore {
  readState(): Promise<PersonalizationSyncRemoteState>;
  writeSnapshot(
    deviceId: string,
    snapshot: PersonalizationSyncSnapshot,
    expectedRevision: string
  ): Promise<PersonalizationSyncWriteResult>;
}

export interface PersonalizationSyncRunResult {
  ok: boolean;
  message: string;
  appliedRemoteCount: number;
  uploaded: boolean;
  syncedAt: number;
}

export const PERSONALIZATION_SYNC_ITEM_IDS: PersonalizationSyncItemId[] = [
  'home_shortcuts',
  'core_preferences',
  'activity_heatmap',
  'search'
];

export function createDefaultPersonalizationSyncConfig(now: number = Date.now()): PersonalizationSyncConfig {
  return {
    items: PERSONALIZATION_SYNC_ITEM_IDS.map((id: PersonalizationSyncItemId): PersonalizationSyncItemSetting => {
      return {
        id: id,
        enabled: true,
        updatedAt: 0
      };
    }),
    sections: [],
    deletions: [],
    lastSyncAt: 0,
    updatedAt: now
  };
}

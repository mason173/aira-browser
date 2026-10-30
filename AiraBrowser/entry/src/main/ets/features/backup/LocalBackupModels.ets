import { AiraActivityDailyAggregate } from '../../common/models/ActivityModels';
import {
  HistoryTransferVisit,
  SearchEngineSettings,
  ShortcutKind
} from '../../common/models/BrowserModels';
import {
  UserScriptGrant,
  UserScriptInstallSource,
  UserScriptResourceRecord,
  UserScriptRunAt
} from '../userscripts/UserScriptMetadataModels';
import { UserScriptValueRecord } from '../userscripts/UserScriptValueModels';

export const LOCAL_BACKUP_FORMAT: string = 'aira-local-backup';
export const LOCAL_BACKUP_FORMAT_VERSION: number = 1;
export const LOCAL_BACKUP_BOOKMARKS_SCHEMA_VERSION: number = 1;
export const LOCAL_BACKUP_HISTORY_SCHEMA_VERSION: number = 1;
export const LOCAL_BACKUP_PERSONALIZATION_SCHEMA_VERSION: number = 1;
export const LOCAL_BACKUP_USER_SCRIPTS_SCHEMA_VERSION: number = 1;
export const LOCAL_BACKUP_USER_SCRIPT_VALUES_SCHEMA_VERSION: number = 1;

export type LocalBackupSectionId =
  'bookmarks' |
  'history' |
  'personalization' |
  'userScripts' |
  'userScriptValues';

export interface LocalBackupSection<T> {
  schemaVersion: number;
  data: T;
}

export interface LocalBackupAppIdentity {
  versionName: string;
  versionCode: number;
}

export interface LocalBackupBookmarkFolderRecord {
  id: string;
  parentId: string | null;
  title: string;
  createdAt: string;
  updatedAt: string;
}

export interface LocalBackupBookmarkItemRecord {
  id: string;
  parentId: string | null;
  title: string;
  url: string;
  createdAt: string;
  updatedAt: string;
}

export interface LocalBackupBookmarkOrderRecord {
  parentId: string | null;
  ids: string[];
  updatedAt: string;
}

export interface LocalBackupBookmarkDataSet {
  folders: LocalBackupBookmarkFolderRecord[];
  items: LocalBackupBookmarkItemRecord[];
  orders: LocalBackupBookmarkOrderRecord[];
}

export interface LocalBackupBookmarksPayload {
  regular: LocalBackupBookmarkDataSet;
  private?: LocalBackupBookmarkDataSet;
}

export type LocalBackupPersonalizationSectionId =
  'home_shortcuts' |
  'core_preferences' |
  'activity_heatmap' |
  'search';

export interface LocalBackupPersonalizationSectionRecord {
  id: LocalBackupPersonalizationSectionId;
  updatedAt: number;
  payload: Object;
}

export interface LocalBackupPersonalizationPayload {
  sections: LocalBackupPersonalizationSectionRecord[];
}

export interface LocalBackupShortcutScenarioRecord {
  id: string;
  name: string;
  color: string;
  icon: string;
  position: number;
  archived: boolean;
  createdAt: number;
  updatedAt: number;
}

export interface LocalBackupShortcutRecord {
  id: string;
  scenarioId?: string;
  kind?: ShortcutKind;
  title: string;
  url: string;
  folderName: string;
  position: number;
  icon?: string;
  description?: string;
  useOfficialIcon?: boolean;
  autoUseOfficialIcon?: boolean;
  officialIconAvailableAtSave?: boolean;
  officialIconColorOverride?: boolean;
  iconRendering?: string;
  iconColor?: string;
  createdAt?: number;
  updatedAt?: number;
}

export interface LocalBackupHomeShortcutOrderRecord {
  scenarioId: string;
  shortcutIds: string[];
  updatedAt: number;
}

export interface LocalBackupHomeShortcutsPayload {
  scenarios: LocalBackupShortcutScenarioRecord[];
  shortcuts: LocalBackupShortcutRecord[];
  orders: LocalBackupHomeShortcutOrderRecord[];
}

export interface LocalBackupActivityHeatmapPayload {
  items: AiraActivityDailyAggregate[];
}

export interface LocalBackupSearchPayload {
  settings: SearchEngineSettings;
}

export interface LocalBackupUserScriptsPayload {
  scripts: LocalBackupUserScriptRecord[];
}

export interface LocalBackupUserScriptMaterializedRequireRecord {
  executionOrder: number;
  source: string;
}

export interface LocalBackupUserScriptRecord {
  id: string;
  name: string;
  namespace: string;
  version: string;
  description: string;
  iconUrl: string;
  source: string;
  sourceUrl: string;
  updateUrl: string;
  downloadUrl: string;
  enabled: boolean;
  matches: string[];
  includes: string[];
  excludeMatches: string[];
  excludes: string[];
  grants: UserScriptGrant[];
  materializedRequires: LocalBackupUserScriptMaterializedRequireRecord[];
  resources: UserScriptResourceRecord[];
  connectRules: string[];
  noframes: boolean;
  runAt: UserScriptRunAt;
  installSource: UserScriptInstallSource;
  createdAt: number;
  updatedAt: number;
}

export interface LocalBackupUserScriptValuesPayload {
  values: UserScriptValueRecord[];
}

export interface LocalBackupSections {
  bookmarks?: LocalBackupSection<LocalBackupBookmarksPayload>;
  history?: LocalBackupSection<HistoryTransferVisit[]>;
  personalization?: LocalBackupSection<LocalBackupPersonalizationPayload>;
  userScripts?: LocalBackupSection<LocalBackupUserScriptsPayload>;
  userScriptValues?: LocalBackupSection<LocalBackupUserScriptValuesPayload>;
}

export interface LocalBackupDocument {
  format: string;
  formatVersion: number;
  exportedAt: number;
  exportedBy: LocalBackupAppIdentity;
  sections: LocalBackupSections;
}

export interface LocalBackupSelection {
  bookmarks: boolean;
  history: boolean;
  personalization: boolean;
  userScripts: boolean;
  userScriptValues: boolean;
}

export interface LocalBackupSectionPreview {
  id: LocalBackupSectionId;
  count: number;
  available: boolean;
}

export interface LocalBackupPreview {
  exportedAt: number;
  exportedBy: LocalBackupAppIdentity;
  sections: LocalBackupSectionPreview[];
}

export interface LocalBackupInspection {
  document: LocalBackupDocument;
  preview: LocalBackupPreview;
}

export interface LocalBackupImportResult {
  bookmarkCount: number;
  historyCount: number;
  personalizationCount: number;
  userScriptCount: number;
  userScriptValueCount: number;
  skippedUserScriptCount: number;
}

export function createDefaultLocalBackupSelection(): LocalBackupSelection {
  return {
    bookmarks: true,
    history: true,
    personalization: true,
    userScripts: true,
    userScriptValues: false
  };
}

export function cloneLocalBackupSelection(selection: LocalBackupSelection): LocalBackupSelection {
  return {
    bookmarks: selection.bookmarks,
    history: selection.history,
    personalization: selection.personalization,
    userScripts: selection.userScripts,
    userScriptValues: selection.userScriptValues
  };
}

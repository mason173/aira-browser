import {
  AIRA_SYNC_SCHEMA_VERSION,
  AiraBookmarkSyncApplyResult,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot
} from '../../common/models/AiraSyncModels';
import { AiraActivityDailyAggregate } from '../../common/models/ActivityModels';
import {
  HistoryImportResult,
  HistoryTransferVisit,
  ShortcutRecord,
  ShortcutScenarioRecord,
  SyncMetadata
} from '../../common/models/BrowserModels';
import {
  PERSONALIZATION_SYNC_ITEM_IDS,
  PERSONALIZATION_SYNC_SCHEMA_VERSION,
  PersonalizationActivityContribution,
  PersonalizationActivityHeatmapPayload,
  PersonalizationHomeShortcutOrder,
  PersonalizationHomeShortcutsPayload,
  PersonalizationSearchPayload,
  PersonalizationSyncItemId,
  PersonalizationSyncSection,
  PersonalizationSyncSnapshot
} from '../../common/models/PersonalizationSyncModels';
import { UserScriptRepository } from '../../data/userscripts/UserScriptRepository';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import {
  HistoryRepository
} from '../../data/repositories/BrowserRepositories';
import {
  LOCAL_BACKUP_FORMAT,
  LOCAL_BACKUP_FORMAT_VERSION,
  LOCAL_BACKUP_BOOKMARKS_SCHEMA_VERSION,
  LOCAL_BACKUP_HISTORY_SCHEMA_VERSION,
  LOCAL_BACKUP_PERSONALIZATION_SCHEMA_VERSION,
  LOCAL_BACKUP_USER_SCRIPTS_SCHEMA_VERSION,
  LOCAL_BACKUP_USER_SCRIPT_VALUES_SCHEMA_VERSION,
  LocalBackupDocument,
  LocalBackupAppIdentity,
  LocalBackupActivityHeatmapPayload,
  LocalBackupBookmarkDataSet,
  LocalBackupBookmarkFolderRecord,
  LocalBackupBookmarkItemRecord,
  LocalBackupBookmarkOrderRecord,
  LocalBackupBookmarksPayload,
  LocalBackupImportResult,
  LocalBackupInspection,
  LocalBackupHomeShortcutOrderRecord,
  LocalBackupHomeShortcutsPayload,
  LocalBackupPersonalizationPayload,
  LocalBackupPersonalizationSectionId,
  LocalBackupPersonalizationSectionRecord,
  LocalBackupPreview,
  LocalBackupSearchPayload,
  LocalBackupSection,
  LocalBackupSectionId,
  LocalBackupSectionPreview,
  LocalBackupSections,
  LocalBackupSelection,
  LocalBackupShortcutRecord,
  LocalBackupShortcutScenarioRecord,
  LocalBackupUserScriptMaterializedRequireRecord,
  LocalBackupUserScriptRecord,
  LocalBackupUserScriptsPayload,
  LocalBackupUserScriptValuesPayload
} from '../../features/backup/LocalBackupModels';
import {
  InstalledUserScriptState,
  UserScriptSettings,
  UserScriptResourceRecord
} from '../../features/userscripts/UserScriptMetadataModels';
import {
  UserScriptValueCommitResult,
  UserScriptValueMutation,
  UserScriptValueReadinessSnapshot,
  UserScriptValueRecord,
  UserScriptValueScriptManagementProjection
} from '../../features/userscripts/UserScriptValueModels';
import {
  UserScriptBackupRestoreState,
  UserScriptPackageCommitResult,
  UserScriptPackageLifecycleCoordinator,
  UserScriptPackagePreviewResult,
  UserScriptPackageSourceInput
} from '../../core/userscripts/UserScriptPackageLifecycleCoordinator';
import { HistoryFeature } from '../../features/history/HistoryFeature';
import { HistoryTransferCodec } from '../history/HistoryTransferCodec';
import { ActivityContributionService } from '../activity/ActivityContributionService';
import { ChangelogContentService } from '../settings/ChangelogContentService';
import { PersonalizationSyncService } from '../sync/PersonalizationSyncService';
import { SyncService } from '../sync/SyncService';

interface LocalBackupScriptRestoreSummary {
  restoredCount: number;
  skippedCount: number;
  scriptIdMap: Map<string, string>;
}

const AIRA_LOCAL_BACKUP_IMPORT_ACTOR: string = 'local-backup-import';

export interface LocalBackupBookmarkDomain {
  buildLocalBackupBookmarkSnapshot(): Promise<AiraSyncSnapshot>;
  importLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult>;
  validateLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): AiraSyncSnapshot;
}

export interface LocalBackupPersonalizationDomain {
  buildLocalBackupSnapshot(): Promise<PersonalizationSyncSnapshot>;
  importLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): Promise<number>;
  validateLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): PersonalizationSyncSnapshot;
}

export interface LocalBackupHistoryDomain {
  importVisits(payload: string): Promise<HistoryImportResult>;
}

export interface LocalBackupUserScriptRepository {
  initialize(): Promise<UserScriptSettings>;
}

export interface LocalBackupUserScriptPackageDomain {
  previewSource(input: UserScriptPackageSourceInput): UserScriptPackagePreviewResult;
  restoreBackupState(state: UserScriptBackupRestoreState): Promise<UserScriptPackageCommitResult>;
}

export interface LocalBackupUserScriptValueDomain {
  initialize(): Promise<UserScriptValueReadinessSnapshot>;
  synchronizeCommands(scriptId: string): Promise<void>;
  readScriptManagementProjection(scriptId: string): UserScriptValueScriptManagementProjection;
  commitMutations(scriptId: string, mutations: UserScriptValueMutation[]): Promise<UserScriptValueCommitResult>;
}

export class LocalBackupService {
  private readonly syncService: SyncService | LocalBackupBookmarkDomain;
  private readonly personalizationSyncService: PersonalizationSyncService | LocalBackupPersonalizationDomain;
  private readonly historyRepository: HistoryRepository;
  private readonly historyFeature: HistoryFeature | LocalBackupHistoryDomain;
  private readonly historyTransferCodec: HistoryTransferCodec = new HistoryTransferCodec();
  private readonly activityContributionService: ActivityContributionService = new ActivityContributionService();
  private readonly userScriptRepository: UserScriptRepository | LocalBackupUserScriptRepository;
  private readonly userScriptPackageLifecycle:
    UserScriptPackageLifecycleCoordinator | LocalBackupUserScriptPackageDomain;
  private readonly userScriptValueStore: UserScriptValueStateStore | LocalBackupUserScriptValueDomain;
  private readonly changelogContentService: ChangelogContentService = new ChangelogContentService();
  private localBackupImportSequence: number = 0;

  constructor(
    syncService: SyncService | LocalBackupBookmarkDomain,
    personalizationSyncService: PersonalizationSyncService | LocalBackupPersonalizationDomain,
    historyRepository: HistoryRepository,
    historyFeature: HistoryFeature | LocalBackupHistoryDomain,
    userScriptRepository: UserScriptRepository | LocalBackupUserScriptRepository,
    userScriptPackageLifecycle: UserScriptPackageLifecycleCoordinator | LocalBackupUserScriptPackageDomain,
    userScriptValueStore: UserScriptValueStateStore | LocalBackupUserScriptValueDomain
  ) {
    this.syncService = syncService;
    this.personalizationSyncService = personalizationSyncService;
    this.historyRepository = historyRepository;
    this.historyFeature = historyFeature;
    this.userScriptRepository = userScriptRepository;
    this.userScriptPackageLifecycle = userScriptPackageLifecycle;
    this.userScriptValueStore = userScriptValueStore;
  }

  async buildExportPayload(selection: LocalBackupSelection): Promise<string> {
    this.requireValidSelection(selection);
    const currentVersion = this.changelogContentService.resolveCurrentVersion();
    const exportedBy: LocalBackupAppIdentity = {
      versionName: currentVersion.versionName,
      versionCode: currentVersion.versionCode
    };
    const sections: LocalBackupSections = {};
    const document: LocalBackupDocument = {
      format: LOCAL_BACKUP_FORMAT,
      formatVersion: LOCAL_BACKUP_FORMAT_VERSION,
      exportedAt: Date.now(),
      exportedBy: exportedBy,
      sections: sections
    };
    if (selection.bookmarks) {
      document.sections.bookmarks = {
        schemaVersion: LOCAL_BACKUP_BOOKMARKS_SCHEMA_VERSION,
        data: this.buildBookmarksPayload(await this.syncService.buildLocalBackupBookmarkSnapshot())
      };
    }
    if (selection.history) {
      await this.historyRepository.initialize();
      const visits = (await this.historyRepository.refresh())
        .filter((visit): boolean => visit.dataScope !== 'session_ephemeral');
      document.sections.history = {
        schemaVersion: LOCAL_BACKUP_HISTORY_SCHEMA_VERSION,
        data: this.historyTransferCodec.buildTransferVisits(visits)
      };
    }
    if (selection.personalization) {
      document.sections.personalization = {
        schemaVersion: LOCAL_BACKUP_PERSONALIZATION_SCHEMA_VERSION,
        data: this.buildPersonalizationPayload(await this.personalizationSyncService.buildLocalBackupSnapshot())
      };
    }
    if (selection.userScripts) {
      const settings = await this.userScriptRepository.initialize();
      document.sections.userScripts = {
        schemaVersion: LOCAL_BACKUP_USER_SCRIPTS_SCHEMA_VERSION,
        data: {
          scripts: settings.scripts.map((script: InstalledUserScriptState): LocalBackupUserScriptRecord => {
            return this.buildUserScriptRecord(script);
          })
        }
      };
      if (selection.userScriptValues) {
        document.sections.userScriptValues = {
          schemaVersion: LOCAL_BACKUP_USER_SCRIPT_VALUES_SCHEMA_VERSION,
          data: await this.buildUserScriptValuesPayload(settings.scripts)
        };
      }
    }
    return JSON.stringify(document);
  }

  inspectPayload(payload: string): LocalBackupInspection {
    let document: LocalBackupDocument;
    try {
      document = JSON.parse(payload) as LocalBackupDocument;
    } catch (_error) {
      throw new Error('备份文件不是有效的 Aira 备份。');
    }
    this.validateDocument(document);
    return {
      document: document,
      preview: this.buildPreview(document)
    };
  }

  async importDocument(
    document: LocalBackupDocument,
    selection: LocalBackupSelection
  ): Promise<LocalBackupImportResult> {
    this.validateDocument(document);
    this.requireValidSelection(selection);
    const result: LocalBackupImportResult = {
      bookmarkCount: 0,
      historyCount: 0,
      personalizationCount: 0,
      userScriptCount: 0,
      userScriptValueCount: 0,
      skippedUserScriptCount: 0
    };
    if (selection.bookmarks && document.sections.bookmarks !== undefined) {
      const bookmarkResult = await this.syncService.importLocalBackupBookmarkSnapshot(
        this.buildBookmarkSnapshot(document.sections.bookmarks.data)
      );
      result.bookmarkCount = bookmarkResult.upsertedFolderCount + bookmarkResult.upsertedBookmarkCount;
    }
    if (selection.history && document.sections.history !== undefined) {
      await this.historyRepository.initialize();
      await this.historyRepository.refresh();
      const historyResult = await this.historyFeature.importVisits(
        JSON.stringify(document.sections.history.data)
      );
      result.historyCount = historyResult.importedCount;
    }
    if (selection.personalization && document.sections.personalization !== undefined) {
      result.personalizationCount = await this.personalizationSyncService.importLocalBackupSnapshot(
        this.buildPersonalizationSnapshot(document.sections.personalization.data)
      );
    }
    let scriptSummary: LocalBackupScriptRestoreSummary = {
      restoredCount: 0,
      skippedCount: 0,
      scriptIdMap: new Map<string, string>()
    };
    if (selection.userScripts && document.sections.userScripts !== undefined) {
      scriptSummary = await this.restoreUserScripts(document.sections.userScripts.data);
      result.userScriptCount = scriptSummary.restoredCount;
      result.skippedUserScriptCount = scriptSummary.skippedCount;
    }
    if (selection.userScriptValues && document.sections.userScriptValues !== undefined) {
      result.userScriptValueCount = await this.restoreUserScriptValues(
        document.sections.userScriptValues.data,
        scriptSummary.scriptIdMap
      );
    }
    return result;
  }

  private async buildUserScriptValuesPayload(
    scripts: InstalledUserScriptState[]
  ): Promise<LocalBackupUserScriptValuesPayload> {
    await this.userScriptValueStore.initialize();
    const values: UserScriptValueRecord[] = [];
    for (let index = 0; index < scripts.length; index += 1) {
      const script = scripts[index];
      await this.userScriptValueStore.synchronizeCommands(script.id);
      const projection = this.userScriptValueStore.readScriptManagementProjection(script.id);
      projection.records.forEach((record: UserScriptValueRecord): void => {
        values.push(record);
      });
    }
    return { values: values };
  }

  private async restoreUserScripts(
    payload: LocalBackupUserScriptsPayload
  ): Promise<LocalBackupScriptRestoreSummary> {
    await this.userScriptRepository.initialize();
    const scriptIdMap = new Map<string, string>();
    let restoredCount = 0;
    let skippedCount = 0;
    for (let index = 0; index < payload.scripts.length; index += 1) {
      const script = payload.scripts[index];
      const restoreResult = await this.userScriptPackageLifecycle.restoreBackupState(
        this.buildUserScriptBackupRestoreState(script)
      );
      if (restoreResult.status === 'installed' || restoreResult.status === 'updated') {
        scriptIdMap.set(script.id, restoreResult.scriptId);
        restoredCount += 1;
      } else {
        skippedCount += 1;
      }
    }
    return {
      restoredCount: restoredCount,
      skippedCount: skippedCount,
      scriptIdMap: scriptIdMap
    };
  }

  private async restoreUserScriptValues(
    payload: LocalBackupUserScriptValuesPayload,
    scriptIdMap: Map<string, string>
  ): Promise<number> {
    await this.userScriptValueStore.initialize();
    const mutationsByScriptId = new Map<string, UserScriptValueMutation[]>();
    payload.values.forEach((record: UserScriptValueRecord): void => {
      const targetScriptId = scriptIdMap.get(record.scriptId) ?? '';
      if (targetScriptId.length <= 0) {
        return;
      }
      const mutations = mutationsByScriptId.get(targetScriptId) ?? [];
      mutations.push({
        operation: 'set',
        key: record.key,
        valueJson: record.valueJson
      });
      mutationsByScriptId.set(targetScriptId, mutations);
    });
    let restoredCount = 0;
    const scriptIds = Array.from(mutationsByScriptId.keys());
    for (let index = 0; index < scriptIds.length; index += 1) {
      const scriptId = scriptIds[index];
      const mutations = mutationsByScriptId.get(scriptId) ?? [];
      const commitResult = await this.userScriptValueStore.commitMutations(scriptId, mutations);
      restoredCount += commitResult.transitions.length;
    }
    return restoredCount;
  }

  private buildBookmarksPayload(snapshot: AiraSyncSnapshot): LocalBackupBookmarksPayload {
    const payload: LocalBackupBookmarksPayload = {
      regular: this.buildBackupBookmarkDataSet(snapshot)
    };
    if (snapshot.appPrivateBookmarks !== undefined) {
      payload.private = this.buildBackupBookmarkDataSet(snapshot.appPrivateBookmarks);
    }
    return payload;
  }

  private buildBackupBookmarkDataSet(
    dataSet: AiraSyncBookmarkDataSet | AiraSyncSnapshot
  ): LocalBackupBookmarkDataSet {
    return {
      folders: dataSet.bookmarkFolders.map(
        (folder: AiraSyncBookmarkFolderEntity): LocalBackupBookmarkFolderRecord => {
          return {
            id: folder.id,
            parentId: folder.parentId,
            title: folder.title,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt
          };
        }
      ),
      items: dataSet.bookmarkItems.map(
        (item: AiraSyncBookmarkItemEntity): LocalBackupBookmarkItemRecord => {
          return {
            id: item.id,
            parentId: item.parentId,
            title: item.title,
            url: item.url,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
          };
        }
      ),
      orders: dataSet.bookmarkOrders.map(
        (order: AiraSyncBookmarkOrder): LocalBackupBookmarkOrderRecord => {
          return {
            parentId: order.parentId,
            ids: order.ids.slice(),
            updatedAt: order.updatedAt
          };
        }
      )
    };
  }

  private buildBookmarkSnapshot(payload: LocalBackupBookmarksPayload): AiraSyncSnapshot {
    const generatedAt = new Date().toISOString();
    const sourceId = this.createLocalBackupImportActor();
    const regular = this.buildSyncBookmarkDataSet(payload.regular, sourceId);
    const snapshot: AiraSyncSnapshot = {
      meta: {
        version: AIRA_SYNC_SCHEMA_VERSION,
        deviceId: 'local-backup-import',
        generatedAt: generatedAt
      },
      bookmarkFolders: regular.bookmarkFolders,
      bookmarkItems: regular.bookmarkItems,
      bookmarkOrders: regular.bookmarkOrders,
      tombstones: []
    };
    if (payload.private !== undefined) {
      snapshot.appPrivateBookmarks = this.buildSyncBookmarkDataSet(payload.private, sourceId);
    }
    return snapshot;
  }

  private buildSyncBookmarkDataSet(payload: LocalBackupBookmarkDataSet, sourceId: string): AiraSyncBookmarkDataSet {
    return {
      bookmarkFolders: payload.folders.map(
        (folder: LocalBackupBookmarkFolderRecord): AiraSyncBookmarkFolderEntity => {
          return {
            id: folder.id,
            type: 'bookmark-folder',
            parentId: folder.parentId,
            title: folder.title,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt,
            updatedBy: sourceId,
            revision: 0
          };
        }
      ),
      bookmarkItems: payload.items.map(
        (item: LocalBackupBookmarkItemRecord): AiraSyncBookmarkItemEntity => {
          return {
            id: item.id,
            type: 'bookmark-item',
            parentId: item.parentId,
            title: item.title,
            url: item.url,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            updatedBy: sourceId,
            revision: 0
          };
        }
      ),
      bookmarkOrders: payload.orders.map(
        (order: LocalBackupBookmarkOrderRecord): AiraSyncBookmarkOrder => {
          return {
            type: 'bookmark-order',
            parentId: order.parentId,
            ids: order.ids.slice(),
            updatedAt: order.updatedAt,
            updatedBy: sourceId,
            revision: 0
          };
        }
      ),
      tombstones: []
    };
  }

  private createLocalBackupImportActor(): string {
    this.localBackupImportSequence = (this.localBackupImportSequence + 1) % 1000000;
    return `${AIRA_LOCAL_BACKUP_IMPORT_ACTOR}-${Date.now()}-${this.localBackupImportSequence}`;
  }

  private validateBookmarksPayload(payload: LocalBackupBookmarksPayload): void {
    if (!this.isRecord(payload) || !this.isValidBackupBookmarkDataSetShape(payload.regular) ||
      (payload.private !== undefined && !this.isValidBackupBookmarkDataSetShape(payload.private))) {
      throw new Error('备份中的书签格式无效。');
    }
    this.syncService.validateLocalBackupBookmarkSnapshot(this.buildBookmarkSnapshot(payload));
  }

  private isValidBackupBookmarkDataSetShape(payload: LocalBackupBookmarkDataSet | undefined): boolean {
    if (payload === undefined || !this.isRecord(payload) || !Array.isArray(payload.folders) ||
      !Array.isArray(payload.items) || !Array.isArray(payload.orders)) {
      return false;
    }
    return payload.folders.every((folder: LocalBackupBookmarkFolderRecord): boolean => {
        return this.isRecord(folder);
      }) && payload.items.every((item: LocalBackupBookmarkItemRecord): boolean => {
        return this.isRecord(item);
      }) && payload.orders.every((order: LocalBackupBookmarkOrderRecord): boolean => {
        return this.isRecord(order) && Array.isArray(order.ids);
      });
  }

  private buildPersonalizationPayload(snapshot: PersonalizationSyncSnapshot): LocalBackupPersonalizationPayload {
    const sections: LocalBackupPersonalizationSectionRecord[] = PERSONALIZATION_SYNC_ITEM_IDS.map(
      (id: PersonalizationSyncItemId): LocalBackupPersonalizationSectionRecord => {
        const section = snapshot.sections[id];
        return {
          id: id as LocalBackupPersonalizationSectionId,
          updatedAt: section.updatedAt,
          payload: this.buildPortablePersonalizationSectionPayload(id, section.payload)
        };
      }
    );
    return { sections: sections };
  }

  private buildPersonalizationSnapshot(payload: LocalBackupPersonalizationPayload): PersonalizationSyncSnapshot {
    const sections: Record<string, PersonalizationSyncSection> = {};
    payload.sections.forEach((section: LocalBackupPersonalizationSectionRecord): void => {
      sections[section.id] = {
        enabled: true,
        updatedAt: section.updatedAt,
        payload: this.buildImportedPersonalizationSectionPayload(
          section.id as PersonalizationSyncItemId,
          section.payload,
          section.updatedAt
        )
      };
    });
    return {
      meta: {
        version: PERSONALIZATION_SYNC_SCHEMA_VERSION,
        deviceId: 'local-backup-import',
        generatedAt: new Date().toISOString()
      },
      sections: sections
    };
  }

  private buildPortablePersonalizationSectionPayload(
    id: PersonalizationSyncItemId,
    payload: Object
  ): Object {
    if (id === 'home_shortcuts') {
      return this.buildPortableHomeShortcutsPayload(payload as PersonalizationHomeShortcutsPayload);
    }
    if (id === 'activity_heatmap') {
      const activityPayload: LocalBackupActivityHeatmapPayload = {
        items: this.activityContributionService.buildTotals(payload as PersonalizationActivityHeatmapPayload)
      };
      return activityPayload;
    }
    if (id === 'search') {
      const searchPayload = payload as PersonalizationSearchPayload;
      const backupSearchPayload: LocalBackupSearchPayload = {
        settings: searchPayload.settings
      };
      return backupSearchPayload;
    }
    return payload;
  }

  private buildPortableHomeShortcutsPayload(
    payload: PersonalizationHomeShortcutsPayload
  ): LocalBackupHomeShortcutsPayload {
    const scenarios = payload.scenarios
      .filter((scenario: ShortcutScenarioRecord): boolean => scenario.sync.deletedAt === undefined)
      .map((scenario: ShortcutScenarioRecord): LocalBackupShortcutScenarioRecord => {
        return {
          id: scenario.id,
          name: scenario.name,
          color: scenario.color,
          icon: scenario.icon,
          position: scenario.position,
          archived: scenario.archived,
          createdAt: scenario.createdAt,
          updatedAt: scenario.updatedAt
        };
      });
    const scenarioIds = new Set<string>(
      scenarios.map((scenario: LocalBackupShortcutScenarioRecord): string => scenario.id)
    );
    const shortcuts = payload.shortcuts
      .filter((shortcut: ShortcutRecord): boolean => {
        return shortcut.sync?.deletedAt === undefined &&
          (shortcut.scenarioId === undefined || scenarioIds.has(shortcut.scenarioId));
      })
      .map((shortcut: ShortcutRecord): LocalBackupShortcutRecord => {
        return {
          id: shortcut.id,
          scenarioId: shortcut.scenarioId,
          kind: shortcut.kind,
          title: shortcut.title,
          url: shortcut.url,
          folderName: shortcut.folderName,
          position: shortcut.position,
          icon: shortcut.icon,
          description: shortcut.description,
          useOfficialIcon: shortcut.useOfficialIcon,
          autoUseOfficialIcon: shortcut.autoUseOfficialIcon,
          officialIconAvailableAtSave: shortcut.officialIconAvailableAtSave,
          officialIconColorOverride: shortcut.officialIconColorOverride,
          iconRendering: shortcut.iconRendering,
          iconColor: shortcut.iconColor,
          createdAt: shortcut.createdAt,
          updatedAt: shortcut.updatedAt
        };
      });
    const shortcutIds = new Set<string>(
      shortcuts.map((shortcut: LocalBackupShortcutRecord): string => shortcut.id)
    );
    const orders = payload.orders
      .filter((order: PersonalizationHomeShortcutOrder): boolean => scenarioIds.has(order.scenarioId))
      .map((order: PersonalizationHomeShortcutOrder): LocalBackupHomeShortcutOrderRecord => {
        return {
          scenarioId: order.scenarioId,
          shortcutIds: order.shortcutIds.filter((id: string): boolean => shortcutIds.has(id)),
          updatedAt: order.updatedAt
        };
      });
    return {
      scenarios: scenarios,
      shortcuts: shortcuts,
      orders: orders
    };
  }

  private buildImportedPersonalizationSectionPayload(
    id: PersonalizationSyncItemId,
    payload: Object,
    updatedAt: number
  ): Object {
    if (id === 'home_shortcuts') {
      return this.buildImportedHomeShortcutsPayload(payload as LocalBackupHomeShortcutsPayload);
    }
    if (id === 'activity_heatmap') {
      const backupActivity = payload as LocalBackupActivityHeatmapPayload;
      const contributions: PersonalizationActivityContribution[] = [];
      if (backupActivity.items.length > 0) {
        contributions.push({
          sourceId: 'local-backup-import',
          items: backupActivity.items,
          updatedAt: backupActivity.items.reduce((latest: number, item: AiraActivityDailyAggregate): number => {
            return Math.max(latest, item.updatedAt);
          }, updatedAt)
        });
      }
      const activityPayload: PersonalizationActivityHeatmapPayload = { contributions: contributions };
      return activityPayload;
    }
    if (id === 'search') {
      const backupSearch = payload as LocalBackupSearchPayload;
      const searchPayload: PersonalizationSearchPayload = {
        settings: backupSearch.settings,
        tombstones: []
      };
      return searchPayload;
    }
    return payload;
  }

  private buildImportedHomeShortcutsPayload(
    payload: LocalBackupHomeShortcutsPayload
  ): PersonalizationHomeShortcutsPayload {
    return {
      scenarios: payload.scenarios.map(
        (scenario: LocalBackupShortcutScenarioRecord): ShortcutScenarioRecord => {
          return {
            id: scenario.id,
            name: scenario.name,
            color: scenario.color,
            icon: scenario.icon,
            position: scenario.position,
            archived: scenario.archived,
            createdAt: scenario.createdAt,
            updatedAt: scenario.updatedAt,
            sync: this.buildImportedSyncMetadata(Math.max(scenario.createdAt, scenario.updatedAt))
          };
        }
      ),
      shortcuts: payload.shortcuts.map((shortcut: LocalBackupShortcutRecord): ShortcutRecord => {
        return {
          id: shortcut.id,
          scenarioId: shortcut.scenarioId,
          kind: shortcut.kind,
          title: shortcut.title,
          url: shortcut.url,
          folderName: shortcut.folderName,
          position: shortcut.position,
          icon: shortcut.icon,
          description: shortcut.description,
          useOfficialIcon: shortcut.useOfficialIcon,
          autoUseOfficialIcon: shortcut.autoUseOfficialIcon,
          officialIconAvailableAtSave: shortcut.officialIconAvailableAtSave,
          officialIconColorOverride: shortcut.officialIconColorOverride,
          iconRendering: shortcut.iconRendering,
          iconColor: shortcut.iconColor,
          createdAt: shortcut.createdAt,
          updatedAt: shortcut.updatedAt,
          sync: this.buildImportedSyncMetadata(Math.max(shortcut.createdAt ?? 0, shortcut.updatedAt ?? 0))
        };
      }),
      orders: payload.orders.map(
        (order: LocalBackupHomeShortcutOrderRecord): PersonalizationHomeShortcutOrder => {
          return {
            scenarioId: order.scenarioId,
            shortcutIds: order.shortcutIds.slice(),
            updatedAt: order.updatedAt
          };
        }
      )
    };
  }

  private buildImportedSyncMetadata(updatedAt: number): SyncMetadata {
    return {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: updatedAt,
      lastModifiedBy: 'local-backup-import',
      deviceId: 'local-backup-import'
    };
  }

  private validatePersonalizationPayload(payload: LocalBackupPersonalizationPayload): void {
    if (!this.isRecord(payload) || !Array.isArray(payload.sections) ||
      payload.sections.length !== PERSONALIZATION_SYNC_ITEM_IDS.length) {
      throw new Error('备份中的常用设置格式无效。');
    }
    const ids = new Set<string>();
    for (let index = 0; index < payload.sections.length; index += 1) {
      const section = payload.sections[index];
      if (!this.isRecord(section) || !PERSONALIZATION_SYNC_ITEM_IDS.includes(
        section.id as PersonalizationSyncItemId
      ) || ids.has(section.id) || !this.isNonNegativeInteger(section.updatedAt) ||
        !this.isRecord(section.payload) || !this.isValidPortablePersonalizationSectionShape(
          section.id as PersonalizationSyncItemId,
          section.payload
        )) {
        throw new Error('备份中的常用设置分区无效。');
      }
      ids.add(section.id);
    }
    this.personalizationSyncService.validateLocalBackupSnapshot(this.buildPersonalizationSnapshot(payload));
  }

  private isValidPortablePersonalizationSectionShape(
    id: PersonalizationSyncItemId,
    payload: Object
  ): boolean {
    if (id === 'home_shortcuts') {
      const home = payload as LocalBackupHomeShortcutsPayload;
      return Array.isArray(home.scenarios) && Array.isArray(home.shortcuts) && Array.isArray(home.orders) &&
        home.scenarios.every((scenario: LocalBackupShortcutScenarioRecord): boolean => {
          return this.isRecord(scenario);
        }) && home.shortcuts.every((shortcut: LocalBackupShortcutRecord): boolean => {
          return this.isRecord(shortcut);
        }) && home.orders.every((order: LocalBackupHomeShortcutOrderRecord): boolean => {
          return this.isRecord(order) && Array.isArray(order.shortcutIds);
        });
    }
    if (id === 'activity_heatmap') {
      const activity = payload as LocalBackupActivityHeatmapPayload;
      return Array.isArray(activity.items) && activity.items.every(
        (item: AiraActivityDailyAggregate): boolean => this.isRecord(item)
      );
    }
    if (id === 'search') {
      return this.isRecord((payload as LocalBackupSearchPayload).settings);
    }
    return true;
  }

  private validateDocument(document: LocalBackupDocument): void {
    if (!this.isRecord(document) || document.format !== LOCAL_BACKUP_FORMAT) {
      throw new Error('备份文件不是有效的 Aira 本地备份。');
    }
    if (document.formatVersion > LOCAL_BACKUP_FORMAT_VERSION) {
      throw new Error('这份备份由更高版本的 Aira 创建，请先升级应用。');
    }
    if (document.formatVersion !== LOCAL_BACKUP_FORMAT_VERSION ||
      !this.isNonNegativeInteger(document.exportedAt) || !this.isRecord(document.exportedBy) ||
      typeof document.exportedBy.versionName !== 'string' ||
      !this.isNonNegativeInteger(document.exportedBy.versionCode) || !this.isRecord(document.sections)) {
      throw new Error('Aira 备份文件格式或版本不受支持。');
    }
    const sectionKeys = Object.keys(document.sections);
    const allowedSectionIds: string[] = [
      'bookmarks', 'history', 'personalization', 'userScripts', 'userScriptValues'
    ];
    if (sectionKeys.length <= 0 || sectionKeys.some((key: string): boolean => !allowedSectionIds.includes(key))) {
      throw new Error('Aira 备份文件包含不受支持的数据分区。');
    }
    if (document.sections.bookmarks !== undefined) {
      this.requireSectionVersion(
        document.sections.bookmarks,
        LOCAL_BACKUP_BOOKMARKS_SCHEMA_VERSION,
        '书签'
      );
      this.validateBookmarksPayload(document.sections.bookmarks.data);
    }
    if (document.sections.history !== undefined) {
      this.requireSectionVersion(
        document.sections.history,
        LOCAL_BACKUP_HISTORY_SCHEMA_VERSION,
        '历史记录'
      );
      const historyVisits = this.historyTransferCodec.decodeVisits(
        JSON.stringify(document.sections.history.data)
      );
      if (historyVisits.some((visit: HistoryTransferVisit): boolean => visit.dataScope === 'session_ephemeral')) {
        throw new Error('备份中的历史记录包含临时隐私会话数据，无法导入。');
      }
      document.sections.history.data = historyVisits;
    }
    if (document.sections.personalization !== undefined) {
      this.requireSectionVersion(
        document.sections.personalization,
        LOCAL_BACKUP_PERSONALIZATION_SCHEMA_VERSION,
        '常用设置'
      );
      this.validatePersonalizationPayload(document.sections.personalization.data);
    }
    if (document.sections.userScripts !== undefined) {
      this.requireSectionVersion(
        document.sections.userScripts,
        LOCAL_BACKUP_USER_SCRIPTS_SCHEMA_VERSION,
        '用户脚本'
      );
      this.validateUserScriptsPayload(document.sections.userScripts.data);
    }
    if (document.sections.userScriptValues !== undefined) {
      this.requireSectionVersion(
        document.sections.userScriptValues,
        LOCAL_BACKUP_USER_SCRIPT_VALUES_SCHEMA_VERSION,
        '脚本数据'
      );
      this.validateUserScriptValuesPayload(
        document.sections.userScriptValues.data,
        document.sections.userScripts?.data
      );
    }
  }

  private validateUserScriptsPayload(payload: LocalBackupUserScriptsPayload): void {
    if (!this.isRecord(payload) || !Array.isArray(payload.scripts)) {
      throw new Error('备份中的用户脚本格式无效。');
    }
    const ids = new Set<string>();
    for (let index = 0; index < payload.scripts.length; index += 1) {
      const script = payload.scripts[index];
      if (!this.isRecord(script) || typeof script.id !== 'string' || script.id.trim().length <= 0 ||
        ids.has(script.id) || typeof script.source !== 'string' || script.source.trim().length <= 0 ||
        typeof script.name !== 'string' || typeof script.namespace !== 'string' ||
        typeof script.version !== 'string' || typeof script.description !== 'string' ||
        typeof script.iconUrl !== 'string' || typeof script.sourceUrl !== 'string' ||
        typeof script.updateUrl !== 'string' || typeof script.downloadUrl !== 'string' ||
        typeof script.enabled !== 'boolean' || !this.isStringArray(script.matches) ||
        !this.isStringArray(script.includes) || !this.isStringArray(script.excludeMatches) ||
        !this.isStringArray(script.excludes) || !Array.isArray(script.grants) ||
        !this.isMaterializedRequireArray(script.materializedRequires) ||
        !this.isResourceArray(script.resources) || !this.isStringArray(script.connectRules) ||
        typeof script.noframes !== 'boolean' || typeof script.runAt !== 'string' ||
        typeof script.installSource !== 'string' || !this.isNonNegativeInteger(script.createdAt) ||
        !this.isNonNegativeInteger(script.updatedAt)) {
        throw new Error('备份中的用户脚本记录无效。');
      }
      const preview = this.userScriptPackageLifecycle.previewSource({
        source: script.source,
        installSource: 'paste',
        sourceUrl: typeof script.sourceUrl === 'string' ? script.sourceUrl : '',
        existingScriptId: ''
      });
      if (preview.status === 'failed') {
        const scriptLabel = script.name.trim().length > 0 ? script.name : script.id;
        throw new Error(`备份中的脚本“${scriptLabel}”格式无效。`);
      }
      ids.add(script.id);
    }
  }

  private validateUserScriptValuesPayload(
    payload: LocalBackupUserScriptValuesPayload,
    scriptsPayload?: LocalBackupUserScriptsPayload
  ): void {
    if (!this.isRecord(payload) || !Array.isArray(payload.values) || scriptsPayload === undefined) {
      throw new Error('备份中的脚本数据格式无效。');
    }
    const scriptIds = new Set<string>(
      scriptsPayload.scripts.map((script: LocalBackupUserScriptRecord): string => script.id)
    );
    const keys = new Set<string>();
    for (let index = 0; index < payload.values.length; index += 1) {
      const record = payload.values[index];
      const identity = `${record?.scriptId ?? ''}|${record?.key ?? ''}`;
      if (!this.isRecord(record) || typeof record.scriptId !== 'string' || !scriptIds.has(record.scriptId) ||
        typeof record.key !== 'string' || record.key.trim().length <= 0 ||
        typeof record.valueJson !== 'string' || keys.has(identity) ||
        !this.isNonNegativeInteger(record.updatedAt)) {
        throw new Error('备份中的脚本数据记录无效。');
      }
      try {
        JSON.parse(record.valueJson);
      } catch (_error) {
        throw new Error('备份中的脚本数据包含无效值。');
      }
      keys.add(identity);
    }
  }

  private buildPreview(document: LocalBackupDocument): LocalBackupPreview {
    const previews: LocalBackupSectionPreview[] = [];
    this.appendPreview(previews, 'bookmarks', document.sections.bookmarks !== undefined,
      this.countBookmarks(document.sections.bookmarks?.data));
    this.appendPreview(previews, 'history', document.sections.history !== undefined,
      document.sections.history?.data.length ?? 0);
    this.appendPreview(previews, 'personalization', document.sections.personalization !== undefined,
      document.sections.personalization?.data.sections.length ?? 0);
    this.appendPreview(previews, 'userScripts', document.sections.userScripts !== undefined,
      document.sections.userScripts?.data.scripts.length ?? 0);
    this.appendPreview(previews, 'userScriptValues', document.sections.userScriptValues !== undefined,
      document.sections.userScriptValues?.data.values.length ?? 0);
    return {
      exportedAt: document.exportedAt,
      exportedBy: document.exportedBy,
      sections: previews
    };
  }

  private appendPreview(
    previews: LocalBackupSectionPreview[],
    id: LocalBackupSectionId,
    available: boolean,
    count: number
  ): void {
    previews.push({ id: id, available: available, count: count });
  }

  private countBookmarks(payload?: LocalBackupBookmarksPayload): number {
    if (payload === undefined) {
      return 0;
    }
    const regularCount = payload.regular.folders.length + payload.regular.items.length;
    const privateData = payload.private;
    return regularCount + (privateData === undefined
      ? 0
      : privateData.folders.length + privateData.items.length);
  }

  private buildUserScriptRecord(script: InstalledUserScriptState): LocalBackupUserScriptRecord {
    return {
      id: script.id,
      name: script.name,
      namespace: script.namespace,
      version: script.version,
      description: script.description,
      iconUrl: script.iconUrl,
      source: script.source,
      sourceUrl: script.sourceUrl,
      updateUrl: script.updateUrl,
      downloadUrl: script.downloadUrl,
      enabled: script.enabled,
      matches: script.matches.slice(),
      includes: script.includes.slice(),
      excludeMatches: script.excludeMatches.slice(),
      excludes: script.excludes.slice(),
      grants: script.grants.slice(),
      materializedRequires: script.requireSources.map(
        (source: string, executionOrder: number): LocalBackupUserScriptMaterializedRequireRecord => {
          return {
            executionOrder: executionOrder,
            source: source
          };
        }
      ),
      resources: this.cloneUserScriptResources(script.resources),
      connectRules: script.connectRules.slice(),
      noframes: script.noframes,
      runAt: script.runAt,
      installSource: script.installSource,
      createdAt: script.createdAt,
      updatedAt: script.updatedAt
    };
  }

  private buildUserScriptBackupRestoreState(script: LocalBackupUserScriptRecord): UserScriptBackupRestoreState {
    return {
      source: script.source,
      sourceUrl: script.sourceUrl,
      enabled: script.enabled,
      installSource: script.installSource,
      dependencies: {
        requireSources: script.materializedRequires.map(
          (value: LocalBackupUserScriptMaterializedRequireRecord): string => value.source
        ),
        resources: this.cloneUserScriptResources(script.resources)
      }
    };
  }

  private cloneUserScriptResources(resources: UserScriptResourceRecord[]): UserScriptResourceRecord[] {
    return resources.map((resource: UserScriptResourceRecord): UserScriptResourceRecord => {
      return {
        name: resource.name,
        url: resource.url,
        text: resource.text,
        mimeType: resource.mimeType,
        contentBase64: resource.contentBase64
      };
    });
  }

  private isStringArray(value: Object): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    return value.every((item: Object): boolean => typeof item === 'string');
  }

  private isMaterializedRequireArray(value: Object): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    return value.every(
      (item: LocalBackupUserScriptMaterializedRequireRecord, index: number): boolean => {
        return this.isRecord(item) && item.executionOrder === index &&
          typeof item.source === 'string' && item.source.trim().length > 0;
      }
    );
  }

  private isResourceArray(value: Object): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    return value.every((item: UserScriptResourceRecord): boolean => {
      return this.isRecord(item) && typeof item.name === 'string' && typeof item.url === 'string' &&
        typeof item.text === 'string' && typeof item.mimeType === 'string' &&
        (item.contentBase64 === undefined || typeof item.contentBase64 === 'string');
    });
  }

  private requireSectionVersion<T>(section: LocalBackupSection<T>, expected: number, label: string): void {
    if (!this.isRecord(section) || section.schemaVersion !== expected || section.data === undefined) {
      throw new Error(`${label}备份版本不受支持。`);
    }
  }

  private requireValidSelection(selection: LocalBackupSelection): void {
    if (selection.userScriptValues && !selection.userScripts) {
      throw new Error('导出或恢复脚本数据时必须同时选择用户脚本。');
    }
    if (!selection.bookmarks && !selection.history && !selection.personalization &&
      !selection.userScripts && !selection.userScriptValues) {
      throw new Error('请至少选择一项备份内容。');
    }
  }

  private isRecord(value: Object | undefined): boolean {
    return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  private isNonNegativeInteger(value: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 && Math.floor(value) === value;
  }
}

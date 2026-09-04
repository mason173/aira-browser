import { describe, expect, it } from '@ohos/hypium';
import {
  AIRA_SYNC_SCHEMA_VERSION,
  AiraBookmarkSyncApplyResult,
  AiraSyncSnapshot
} from '../main/ets/common/models/AiraSyncModels';
import { AiraFeatureKey } from '../main/ets/common/constants/MembershipFeatureKeys';
import { EntitlementDecision } from '../main/ets/common/models/MembershipModels';
import { AiraActivityDailyAggregate } from '../main/ets/common/models/ActivityModels';
import {
  CreateHistoryVisitCommand,
  HistoryImportResult,
  HistorySiteAggregate,
  HistoryTransferVisit,
  HistoryVisit
} from '../main/ets/common/models/BrowserModels';
import { HistorySyncMutationOrigin } from '../main/ets/common/models/HistorySyncModels';
import {
  PersonalizationActivityHeatmapPayload,
  PersonalizationSyncSnapshot
} from '../main/ets/common/models/PersonalizationSyncModels';
import {
  LocalBackupDocument,
  LocalBackupSelection
} from '../main/ets/features/backup/LocalBackupModels';
import {
  LocalBackupBookmarkDomain,
  LocalBackupHistoryDomain,
  LocalBackupPersonalizationDomain,
  LocalBackupService,
  LocalBackupUserScriptPackageDomain,
  LocalBackupUserScriptRepository,
  LocalBackupUserScriptValueDomain
} from '../main/ets/services/backup/LocalBackupService';
import {
  UserScriptBackupRestoreState,
  UserScriptPackageCommitResult,
  UserScriptPackageLifecycleCoordinator,
  UserScriptPackagePreviewResult,
  UserScriptPackageSourceInput
} from '../main/ets/core/userscripts/UserScriptPackageLifecycleCoordinator';
import {
  cloneInstalledUserScriptState,
  InstalledUserScriptState,
  UserScriptSettings
} from '../main/ets/features/userscripts/UserScriptMetadataModels';
import {
  UserScriptValueCommitResult,
  UserScriptValueCommitTransition,
  UserScriptValueMutation,
  UserScriptValueReadinessSnapshot,
  UserScriptValueScriptManagementProjection
} from '../main/ets/features/userscripts/UserScriptValueModels';
import { HistoryRepository } from '../main/ets/data/repositories/BrowserRepositories';
import {
  InMemoryBookmarkRepository
} from '../main/ets/data/repositories/BrowserRepositories';
import { PreferencesRepository } from '../main/ets/data/preferences/PreferencesRepository';
import { HistoryFeature } from '../main/ets/features/history/HistoryFeature';
import { SyncService } from '../main/ets/services/sync/SyncService';
import {
  BOOKMARK_TOOLBAR_ROOT_ID
} from '../main/ets/data/repositories/BookmarkRepositoryCore';
import { UserScriptRepository } from '../main/ets/data/userscripts/UserScriptRepository';
import {
  UserScriptValueCommittedBytesAdapter,
  UserScriptValueStateStore
} from '../main/ets/data/userscripts/UserScriptValueStateStore';
import { MembershipRepository } from '../main/ets/data/membership/MembershipRepository';
import { MembershipFeature } from '../main/ets/features/membership/MembershipFeature';
import { EntitlementContext } from '../main/ets/services/membership/EntitlementService';
import {
  LocalBackupCoordinator,
  LocalBackupSyncExperienceDomain
} from '../main/ets/core/backup/LocalBackupCoordinator';
import { BrowserBoundaryRouteState } from '../main/ets/common/utils/RouteParamUtils';
import { ActivityContributionService } from '../main/ets/services/activity/ActivityContributionService';
import { AiraBookmarkMergeService } from '../main/ets/services/sync/AiraBookmarkMergeService';
import { AiraSyncWorkThrottleService } from '../main/ets/services/sync/AiraSyncWorkThrottleService';

class InMemoryBookmarkBackupDomain implements LocalBackupBookmarkDomain {
  buildLocalBackupBookmarkSnapshot(): Promise<AiraSyncSnapshot> {
    return Promise.reject(new Error('unexpected-bookmark-export'));
  }

  importLocalBackupBookmarkSnapshot(_snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    return Promise.reject(new Error('unexpected-bookmark-import'));
  }

  replaceLocalBookmarksFromRecoverySnapshot(_snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    return Promise.reject(new Error('unexpected-bookmark-recovery'));
  }

  validateLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): AiraSyncSnapshot {
    return snapshot;
  }
}

class StatefulBookmarkBackupDomain implements LocalBackupBookmarkDomain {
  lastImportedActor: string = '';
  private snapshot: AiraSyncSnapshot = {
    meta: {
      version: AIRA_SYNC_SCHEMA_VERSION,
      deviceId: 'test-local-device',
      generatedAt: '2026-08-01T00:00:00.000Z'
    },
    bookmarkFolders: [],
    bookmarkItems: [{
      id: 'local-bookmark',
      type: 'bookmark-item',
      parentId: null,
      title: 'Local',
      url: 'https://local.example/',
      createdAt: '2026-08-01T00:00:00.000Z',
      updatedAt: '2026-08-01T00:00:00.000Z',
      updatedBy: 'test-local-device',
      revision: 1
    }],
    bookmarkOrders: [{
      type: 'bookmark-order',
      parentId: null,
      ids: ['local-bookmark'],
      updatedAt: '2026-08-01T00:00:00.000Z',
      updatedBy: 'test-local-device',
      revision: 1
    }],
    tombstones: []
  };
  private mergeService: AiraBookmarkMergeService = new AiraBookmarkMergeService();
  private throttle: AiraSyncWorkThrottleService = new AiraSyncWorkThrottleService();

  buildLocalBackupBookmarkSnapshot(): Promise<AiraSyncSnapshot> {
    return Promise.reject(new Error('unexpected-bookmark-export'));
  }

  async importLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    this.lastImportedActor = snapshot.bookmarkItems.find(
      (item): boolean => item.id === 'backup-item'
    )?.updatedBy ?? '';
    const existingFolderIds = new Set<string>(this.snapshot.bookmarkFolders.map((folder): string => folder.id));
    const existingBookmarkIds = new Set<string>(this.snapshot.bookmarkItems.map((item): string => item.id));
    const mergeResult = await this.mergeService.mergeCooperatively(
      null,
      this.snapshot,
      snapshot,
      this.throttle,
      this.snapshot.meta.deviceId
    );
    this.snapshot = mergeResult.snapshot;
    const upsertedFolderCount = this.snapshot.bookmarkFolders.filter(
      (folder): boolean => !existingFolderIds.has(folder.id)
    ).length;
    const upsertedBookmarkCount = this.snapshot.bookmarkItems.filter(
      (item): boolean => !existingBookmarkIds.has(item.id)
    ).length;
    const result: AiraBookmarkSyncApplyResult = {
      upsertedFolderCount: upsertedFolderCount,
      upsertedBookmarkCount: upsertedBookmarkCount,
      deletedNodeCount: 0,
      skippedNodeCount: 0,
      blocked: false,
      summary: ''
    };
    return result;
  }

  replaceLocalBookmarksFromRecoverySnapshot(_snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    return Promise.reject(new Error('unexpected-bookmark-recovery'));
  }

  validateLocalBackupBookmarkSnapshot(snapshot: AiraSyncSnapshot): AiraSyncSnapshot {
    return snapshot;
  }

  hasNode(id: string): boolean {
    return this.snapshot.bookmarkFolders.some((folder): boolean => folder.id === id) ||
      this.snapshot.bookmarkItems.some((item): boolean => item.id === id);
  }
}

class InMemoryPersonalizationBackupDomain implements LocalBackupPersonalizationDomain {
  buildLocalBackupSnapshot(): Promise<PersonalizationSyncSnapshot> {
    return Promise.reject(new Error('unexpected-personalization-export'));
  }

  importLocalBackupSnapshot(_snapshot: PersonalizationSyncSnapshot): Promise<number> {
    return Promise.reject(new Error('unexpected-personalization-import'));
  }

  validateLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): PersonalizationSyncSnapshot {
    return snapshot;
  }
}

class FailingPersonalizationBackupDomain implements LocalBackupPersonalizationDomain {
  buildLocalBackupSnapshot(): Promise<PersonalizationSyncSnapshot> {
    return Promise.reject(new Error('unexpected-personalization-export'));
  }

  importLocalBackupSnapshot(_snapshot: PersonalizationSyncSnapshot): Promise<number> {
    return Promise.reject(new Error('injected-personalization-failure'));
  }

  validateLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): PersonalizationSyncSnapshot {
    return snapshot;
  }
}

class RecordingPersonalizationBackupDomain implements LocalBackupPersonalizationDomain {
  importedSnapshot?: PersonalizationSyncSnapshot;

  buildLocalBackupSnapshot(): Promise<PersonalizationSyncSnapshot> {
    return Promise.reject(new Error('unexpected-personalization-export'));
  }

  importLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): Promise<number> {
    this.importedSnapshot = snapshot;
    return Promise.resolve(4);
  }

  validateLocalBackupSnapshot(snapshot: PersonalizationSyncSnapshot): PersonalizationSyncSnapshot {
    return snapshot;
  }
}

class InMemoryHistoryRepository implements HistoryRepository {
  private visits: HistoryVisit[] = [];
  private nextId: number = 1;

  listVisits(limit?: number): HistoryVisit[] {
    return limit === undefined ? this.visits.slice() : this.visits.slice(0, limit);
  }

  initialize(): Promise<void> {
    return Promise.resolve();
  }

  refreshPreview(limit: number): Promise<HistoryVisit[]> {
    return Promise.resolve(this.listVisits(limit));
  }

  refreshPage(offset: number, limit: number): Promise<HistoryVisit[]> {
    return Promise.resolve(this.visits.slice(offset, offset + limit));
  }

  refreshSearchPage(_query: string, offset: number, limit: number): Promise<HistoryVisit[]> {
    return this.refreshPage(offset, limit);
  }

  refreshSitePage(_query: string, _offset: number, _limit: number): Promise<HistorySiteAggregate[]> {
    const values: HistorySiteAggregate[] = [];
    return Promise.resolve(values);
  }

  refresh(): Promise<HistoryVisit[]> {
    return Promise.resolve(this.visits.slice());
  }

  addVisit(_command: CreateHistoryVisitCommand): Promise<HistoryVisit> {
    return Promise.reject(new Error('unexpected-history-add'));
  }

  deleteVisit(_id: string, _origin?: HistorySyncMutationOrigin): Promise<boolean> {
    return Promise.resolve(false);
  }

  deleteVisitsByIds(_ids: string[], _origin?: HistorySyncMutationOrigin): Promise<number> {
    return Promise.resolve(0);
  }

  deleteVisitsInRange(
    _startAt: number,
    _endAt: number,
    _origin?: HistorySyncMutationOrigin
  ): Promise<number> {
    return Promise.resolve(0);
  }

  deleteVisitsByHost(_host: string, _origin?: HistorySyncMutationOrigin): Promise<number> {
    return Promise.resolve(0);
  }

  clearVisits(_origin?: HistorySyncMutationOrigin): Promise<number> {
    const count = this.visits.length;
    this.visits = [];
    return Promise.resolve(count);
  }

  importVisits(visits: HistoryTransferVisit[]): Promise<number> {
    visits.forEach((visit: HistoryTransferVisit): void => {
      const record: HistoryVisit = {
        id: `history-${this.nextId}`,
        title: visit.title,
        url: visit.url,
        visitedAt: visit.visitedAt,
        dayBucketLabel: '2026-08-28',
        source: 'local',
        deviceId: 'test-device',
        sessionId: visit.sessionId ?? '',
        fromVisitId: visit.fromVisitId,
        transition: visit.transition,
        visitDurationMs: visit.visitDurationMs,
        profileId: visit.profileId,
        dataScope: visit.dataScope
      };
      this.nextId += 1;
      this.visits.push(record);
    });
    return Promise.resolve(visits.length);
  }

  listSuggestions(limit?: number): HistoryVisit[] {
    return this.listVisits(limit);
  }

  listSuggestionCandidates(limit?: number): HistoryVisit[] {
    return this.listVisits(limit);
  }
}

class InMemoryHistoryBackupDomain implements LocalBackupHistoryDomain {
  importVisits(_payload: string): Promise<HistoryImportResult> {
    const result: HistoryImportResult = { importedCount: 0, skippedCount: 0 };
    return Promise.resolve(result);
  }
}

class InMemoryUserScriptRepository implements LocalBackupUserScriptRepository {
  initialize(): Promise<UserScriptSettings> {
    const settings: UserScriptSettings = { scripts: [], autoUpdateEnabled: false, updatedAt: 0 };
    return Promise.resolve(settings);
  }
}

class StatefulUserScriptRepository extends UserScriptRepository {
  private scripts: InstalledUserScriptState[] = [];

  initialize(): Promise<UserScriptSettings> {
    return Promise.resolve(this.getSettings());
  }

  getSettings(): UserScriptSettings {
    return {
      scripts: this.scripts.map(
        (script: InstalledUserScriptState): InstalledUserScriptState => cloneInstalledUserScriptState(script)
      ),
      autoUpdateEnabled: false,
      updatedAt: 0
    };
  }

  listScripts(): InstalledUserScriptState[] {
    return this.getSettings().scripts;
  }

  findScript(scriptId: string): InstalledUserScriptState | undefined {
    const script = this.scripts.find((value: InstalledUserScriptState): boolean => value.id === scriptId);
    return script === undefined ? undefined : cloneInstalledUserScriptState(script);
  }

  saveInstalledState(state: InstalledUserScriptState): Promise<UserScriptSettings> {
    this.scripts = this.scripts
      .filter((value: InstalledUserScriptState): boolean => value.id !== state.id)
      .concat(cloneInstalledUserScriptState(state));
    return Promise.resolve(this.getSettings());
  }
}

class AlwaysAllowedMembershipFeature extends MembershipFeature {
  constructor() {
    super(new MembershipRepository());
  }

  canUse(featureKey: AiraFeatureKey, _context: EntitlementContext): Promise<EntitlementDecision> {
    const decision: EntitlementDecision = {
      featureKey: featureKey,
      allowed: true,
      reason: 'allowed',
      title: '',
      message: '',
      primaryAction: 'none'
    };
    return Promise.resolve(decision);
  }

  recordUsage(_featureKey: AiraFeatureKey, _amount: number = 1): Promise<void> {
    return Promise.resolve();
  }
}

class InMemoryValueBytesAdapter implements UserScriptValueCommittedBytesAdapter {
  committed?: Uint8Array;

  readCommitted(): Promise<Uint8Array | undefined> {
    return Promise.resolve(this.committed);
  }

  replaceCommitted(bytes: Uint8Array): Promise<void> {
    this.committed = new Uint8Array(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    return Promise.resolve();
  }
}

class ScriptFixture {
  readonly repository: StatefulUserScriptRepository = new StatefulUserScriptRepository();
  readonly valueStore: UserScriptValueStateStore = new UserScriptValueStateStore(
    new InMemoryValueBytesAdapter(),
    0,
    (): number => 1000
  );
  readonly lifecycle: UserScriptPackageLifecycleCoordinator = new UserScriptPackageLifecycleCoordinator(
    this.repository,
    this.valueStore,
    undefined,
    new AlwaysAllowedMembershipFeature()
  );
}

class InMemoryUserScriptPackageDomain implements LocalBackupUserScriptPackageDomain {
  previewSource(_input: UserScriptPackageSourceInput): UserScriptPackagePreviewResult {
    const result: UserScriptPackagePreviewResult = {
      status: 'failed',
      warnings: [],
      errorMessage: 'unexpected-script-preview'
    };
    return result;
  }

  restoreBackupState(_state: UserScriptBackupRestoreState): Promise<UserScriptPackageCommitResult> {
    const result: UserScriptPackageCommitResult = {
      status: 'failed',
      warnings: [],
      errorMessage: 'unexpected-script-restore'
    };
    return Promise.resolve(result);
  }
}

class InMemoryUserScriptValueDomain implements LocalBackupUserScriptValueDomain {
  initialize(): Promise<UserScriptValueReadinessSnapshot> {
    const readiness: UserScriptValueReadinessSnapshot = {
      status: 'ready',
      revision: 0,
      failureStage: '',
      failureCode: ''
    };
    return Promise.resolve(readiness);
  }

  synchronizeCommands(_scriptId: string): Promise<void> {
    return Promise.resolve();
  }

  readScriptManagementProjection(scriptId: string): UserScriptValueScriptManagementProjection {
    const readiness: UserScriptValueReadinessSnapshot = {
      status: 'ready',
      revision: 0,
      failureStage: '',
      failureCode: ''
    };
    const projection: UserScriptValueScriptManagementProjection = {
      scriptId: scriptId,
      records: [],
      readiness: readiness
    };
    return projection;
  }

  commitMutations(_scriptId: string, _mutations: UserScriptValueMutation[]): Promise<UserScriptValueCommitResult> {
    const transitions: UserScriptValueCommitTransition[] = [];
    const result: UserScriptValueCommitResult = {
      revision: 0,
      changed: false,
      transitions: transitions,
      incidentRecovered: false
    };
    return Promise.resolve(result);
  }
}

class ImmediateBackupSyncExperienceDomain implements LocalBackupSyncExperienceDomain {
  runLocalBackupImport<T>(operation: () => Promise<T>): Promise<T> {
    return operation();
  }

  recordBookmarkMutation(_changedAt: number): Promise<void> {
    return Promise.resolve();
  }

  notifyPersonalizationLocalSettingsChanged(): void {}
}

function createService(
  bookmarkDomain: LocalBackupBookmarkDomain = new InMemoryBookmarkBackupDomain(),
  personalizationDomain: LocalBackupPersonalizationDomain = new InMemoryPersonalizationBackupDomain(),
  historyRepository: HistoryRepository = new InMemoryHistoryRepository(),
  historyDomain: LocalBackupHistoryDomain = new InMemoryHistoryBackupDomain(),
  scriptRepository: LocalBackupUserScriptRepository = new InMemoryUserScriptRepository(),
  scriptPackageDomain: LocalBackupUserScriptPackageDomain = new InMemoryUserScriptPackageDomain(),
  scriptValueDomain: LocalBackupUserScriptValueDomain = new InMemoryUserScriptValueDomain()
): LocalBackupService {
  return new LocalBackupService(
    bookmarkDomain,
    personalizationDomain,
    historyRepository,
    historyDomain,
    scriptRepository,
    scriptPackageDomain,
    scriptValueDomain
  );
}

function createSelection(
  bookmarks: boolean,
  history: boolean,
  personalization: boolean,
  userScripts: boolean,
  userScriptValues: boolean
): LocalBackupSelection {
  return {
    bookmarks: bookmarks,
    history: history,
    personalization: personalization,
    userScripts: userScripts,
    userScriptValues: userScriptValues
  };
}

function createDocumentPayload(sectionsJson: string, extraTopLevel: string = ''): string {
  return '{"format":"aira-local-backup","formatVersion":1,"exportedAt":1000,' +
    '"exportedBy":{"versionName":"1.0.0","versionCode":1},"sections":' + sectionsJson +
    extraTopLevel + '}';
}

function createHistoryOnlyPayload(): string {
  return createDocumentPayload('{"history":{' +
    '"schemaVersion":1,"data":[{"title":"Example","url":"https://example.com/",' +
    '"visitedAt":900,"profileId":"profile-main","dataScope":"profile_persistent"}]}}');
}

function createBookmarkOnlyPayload(): string {
  return createDocumentPayload('{"bookmarks":{"schemaVersion":1,"data":{"regular":{' +
    '"folders":[{"id":"backup-folder","parentId":null,"title":"Imported",' +
    '"createdAt":"2026-08-01T00:00:00.000Z","updatedAt":"2026-08-02T00:00:00.000Z"}],' +
    '"items":[{"id":"backup-item","parentId":"backup-folder","title":"Example",' +
    '"url":"https://example.com/","createdAt":"2026-08-01T00:00:00.000Z",' +
    '"updatedAt":"2026-08-02T00:00:00.000Z"}],' +
    '"orders":[{"parentId":null,"ids":["backup-folder"],' +
    '"updatedAt":"2026-08-02T00:00:00.000Z"},{"parentId":"backup-folder",' +
    '"ids":["backup-item"],"updatedAt":"2026-08-02T00:00:00.000Z"}]}}}}');
}

function createHistoryAndPersonalizationPayload(): string {
  return createDocumentPayload('{"history":{"schemaVersion":1,"data":[' +
    '{"title":"Example","url":"https://example.com/","visitedAt":900,' +
    '"profileId":"profile-main","dataScope":"profile_persistent"}]},' +
    '"personalization":{"schemaVersion":1,"data":{"sections":[' +
    '{"id":"home_shortcuts","updatedAt":10,"payload":{"scenarios":[],"shortcuts":[],"orders":[]}},' +
    '{"id":"core_preferences","updatedAt":10,"payload":{}},' +
    '{"id":"activity_heatmap","updatedAt":10,"payload":{"items":[]}},' +
    '{"id":"search","updatedAt":10,"payload":{"settings":{}}}' +
    ']}}}');
}

function createActivityPersonalizationPayload(): string {
  return createDocumentPayload('{"personalization":{"schemaVersion":1,"data":{"sections":[' +
    '{"id":"home_shortcuts","updatedAt":10,"payload":{"scenarios":[],"shortcuts":[],"orders":[]}},' +
    '{"id":"core_preferences","updatedAt":10,"payload":{}},' +
    '{"id":"activity_heatmap","updatedAt":20,"payload":{"items":[' +
    '{"date":"2026-08-28","score":12,"pageVisits":5,"searches":2,"bookmarkActions":1,' +
    '"downloads":1,"featureActions":3,"activeSeconds":120,"updatedAt":20}]}},' +
    '{"id":"search","updatedAt":10,"payload":{"settings":{}}}' +
    ']}}}');
}

function createActivityAggregate(
  score: number,
  pageVisits: number,
  searches: number,
  updatedAt: number
): AiraActivityDailyAggregate {
  return {
    date: '2026-08-28',
    score: score,
    pageVisits: pageVisits,
    searches: searches,
    bookmarkActions: 1,
    downloads: 1,
    featureActions: 1,
    activeSeconds: 60,
    updatedAt: updatedAt
  };
}

function createBoundary(dataScope: string, privacyMode: string): BrowserBoundaryRouteState {
  return {
    dataScope: dataScope,
    privacyMode: privacyMode,
    boundarySource: 'test'
  };
}

function createUserScriptSource(requireUrl: string = '', resourceDeclaration: string = ''): string {
  const requireLine = requireUrl.length > 0 ? `// @require ${requireUrl}\n` : '';
  const resourceLine = resourceDeclaration.length > 0 ? `// @resource icon ${resourceDeclaration}\n` : '';
  return '// ==UserScript==\n// @name Backup Script\n// @namespace aira.test\n// @version 1.0.0\n' +
    '// @match https://example.com/*\n// @grant GM_getValue\n// @grant GM_setValue\n' +
    requireLine + resourceLine + '// ==/UserScript==\nconsole.log("backup");';
}

function createUserScriptSourceWithRequires(requireUrls: string[]): string {
  let requireLines = '';
  requireUrls.forEach((url: string): void => {
    requireLines += `// @require ${url}\n`;
  });
  return '// ==UserScript==\n// @name Backup Script\n// @namespace aira.test\n// @version 1.0.0\n' +
    '// @match https://example.com/*\n// @grant GM_getValue\n// @grant GM_setValue\n' +
    requireLines + '// ==/UserScript==\nconsole.log("backup");';
}

function createUserScriptRecordJson(
  id: string,
  enabled: boolean,
  source: string,
  materializedRequiresJson: string = '[]',
  resourcesJson: string = '[]'
): string {
  return '{"id":' + JSON.stringify(id) + ',"name":"Backup Script","namespace":"aira.test",' +
    '"version":"1.0.0","description":"","iconUrl":"","source":' + JSON.stringify(source) + ',' +
    '"sourceUrl":"","updateUrl":"","downloadUrl":"","enabled":' + String(enabled) + ',' +
    '"matches":["https://example.com/*"],"includes":[],"excludeMatches":[],"excludes":[],' +
    '"grants":["GM_getValue","GM_setValue"],"materializedRequires":' + materializedRequiresJson + ',' +
    '"resources":' + resourcesJson + ',"connectRules":[],"noframes":false,' +
    '"runAt":"document-end","installSource":"paste","createdAt":100,"updatedAt":200}';
}

function createUserScriptPayload(
  recordJson: string,
  valuesJson: string = '',
  additionalRecordJson: string = ''
): string {
  const scripts = additionalRecordJson.length > 0 ? `${recordJson},${additionalRecordJson}` : recordJson;
  const valuesSection = valuesJson.length > 0
    ? ',"userScriptValues":{"schemaVersion":1,"data":{"values":' + valuesJson + '}}'
    : '';
  return createDocumentPayload('{"userScripts":{"schemaVersion":1,"data":{"scripts":[' + scripts + ']}}' +
    valuesSection + '}');
}

function createHistoryService(repository: InMemoryHistoryRepository): LocalBackupService {
  return new LocalBackupService(
    new InMemoryBookmarkBackupDomain(),
    new InMemoryPersonalizationBackupDomain(),
    repository,
    new HistoryFeature(repository),
    new InMemoryUserScriptRepository(),
    new InMemoryUserScriptPackageDomain(),
    new InMemoryUserScriptValueDomain()
  );
}

function createScriptService(fixture: ScriptFixture): LocalBackupService {
  return new LocalBackupService(
    new InMemoryBookmarkBackupDomain(),
    new InMemoryPersonalizationBackupDomain(),
    new InMemoryHistoryRepository(),
    new InMemoryHistoryBackupDomain(),
    fixture.repository,
    fixture.lifecycle,
    fixture.valueStore
  );
}

function captureInspectionError(payload: string): string {
  try {
    createService().inspectPayload(payload);
  } catch (error) {
    return error instanceof Error ? error.message : 'unknown-error';
  }
  return '';
}

async function captureImportError(
  service: LocalBackupService,
  document: LocalBackupDocument,
  selection: LocalBackupSelection
): Promise<string> {
  try {
    await service.importDocument(document, selection);
  } catch (error) {
    return error instanceof Error ? error.message : 'unknown-error';
  }
  return '';
}

export default function localBackupImportScenariosTest(): void {
  describe('LocalBackup import scenarios', () => {
    it('previews a valid history-only backup without requiring another section', 0, () => {
      const inspection = createService().inspectPayload(createHistoryOnlyPayload());
      const historyPreview = inspection.preview.sections.find(
        (section): boolean => section.id === 'history'
      );

      expect(historyPreview?.available ?? false).assertTrue();
      expect(historyPreview?.count ?? 0).assertEqual(1);
      expect(inspection.document.sections.bookmarks === undefined).assertTrue();
    });

    it('rejects empty and malformed JSON payloads', 0, () => {
      expect(captureInspectionError('').length).assertLarger(0);
      expect(captureInspectionError('{"format":').length).assertLarger(0);
    });

    it('rejects a future container version with an upgrade message', 0, () => {
      const payload = createHistoryOnlyPayload().replace('"formatVersion":1', '"formatVersion":2');
      expect(captureInspectionError(payload).includes('升级应用')).assertTrue();
    });

    it('rejects a future section version independently from the container version', 0, () => {
      const payload = createHistoryOnlyPayload().replace('"schemaVersion":1', '"schemaVersion":2');
      expect(captureInspectionError(payload).includes('历史记录备份版本不受支持')).assertTrue();
    });

    it('accepts unknown top-level metadata but rejects an unknown data section', 0, () => {
      const metadataPayload = createDocumentPayload(
        '{"history":{"schemaVersion":1,"data":[]}}',
        ',"futureMetadata":{"producer":"test"}'
      );
      const unknownSectionPayload = createDocumentPayload(
        '{"history":{"schemaVersion":1,"data":[]},"passwords":{"schemaVersion":1,"data":[]}}'
      );

      expect(createService().inspectPayload(metadataPayload).document.exportedAt).assertEqual(1000);
      expect(captureInspectionError(unknownSectionPayload).includes('不受支持的数据分区')).assertTrue();
    });

    it('accepts an empty history section and reports zero preview items', 0, () => {
      const inspection = createService().inspectPayload(
        createDocumentPayload('{"history":{"schemaVersion":1,"data":[]}}')
      );
      const historyPreview = inspection.preview.sections.find(
        (section): boolean => section.id === 'history'
      );

      expect(historyPreview?.available ?? false).assertTrue();
      expect(historyPreview?.count ?? -1).assertEqual(0);
    });

    it('rejects temporary private-session history before import', 0, () => {
      const payload = createDocumentPayload('{"history":{"schemaVersion":1,"data":[' +
        '{"title":"Private","url":"https://private.example/","visitedAt":900,' +
        '"profileId":"profile-main","dataScope":"session_ephemeral"}]}}');

      expect(captureInspectionError(payload).includes('临时隐私会话数据')).assertTrue();
    });

    it('requires scripts when script values are selected', 0, async () => {
      const inspection = createService().inspectPayload(createHistoryOnlyPayload());
      const error = await captureImportError(
        createService(),
        inspection.document,
        createSelection(false, false, false, false, true)
      );

      expect(error.includes('必须同时选择用户脚本')).assertTrue();
    });

    it('imports history once and skips the same URL and timestamp on repeated import', 0, async () => {
      const repository = new InMemoryHistoryRepository();
      const service = createHistoryService(repository);
      const document = service.inspectPayload(createHistoryOnlyPayload()).document;
      const selection = createSelection(false, true, false, false, false);

      const first = await service.importDocument(document, selection);
      const second = await service.importDocument(document, selection);

      expect(first.historyCount).assertEqual(1);
      expect(second.historyCount).assertEqual(0);
      expect(repository.listVisits().length).assertEqual(1);
    });

    it('preserves an existing bookmark and reports no newly merged nodes on repeated import', 0, async () => {
      const bookmarkDomain = new StatefulBookmarkBackupDomain();
      const service = createService(bookmarkDomain);
      const document = service.inspectPayload(createBookmarkOnlyPayload()).document;
      const selection = createSelection(true, false, false, false, false);

      const first = await service.importDocument(document, selection);
      const firstImportedActor = bookmarkDomain.lastImportedActor;
      const second = await service.importDocument(document, selection);

      expect(first.bookmarkCount).assertEqual(2);
      expect(second.bookmarkCount).assertEqual(0);
      expect(bookmarkDomain.hasNode('local-bookmark')).assertTrue();
      expect(bookmarkDomain.hasNode('backup-folder')).assertTrue();
      expect(bookmarkDomain.hasNode('backup-item')).assertTrue();
      expect(firstImportedActor.length > 0).assertTrue();
      expect(bookmarkDomain.lastImportedActor !== firstImportedActor).assertTrue();
    });

    it('converts portable activity totals into a dedicated backup contribution', 0, async () => {
      const personalizationDomain = new RecordingPersonalizationBackupDomain();
      const service = createService(new InMemoryBookmarkBackupDomain(), personalizationDomain);
      const document = service.inspectPayload(createActivityPersonalizationPayload()).document;

      const result = await service.importDocument(
        document,
        createSelection(false, false, true, false, false)
      );
      const payload = personalizationDomain.importedSnapshot?.sections.activity_heatmap?.payload as
        PersonalizationActivityHeatmapPayload | undefined;
      const contribution = payload?.contributions[0];

      expect(result.personalizationCount).assertEqual(4);
      expect(payload?.contributions.length ?? 0).assertEqual(1);
      expect(contribution?.sourceId ?? '').assertEqual('local-backup-import');
      expect(contribution?.items[0].score ?? 0).assertEqual(12);
    });

    it('merges repeated activity backup totals by per-field maximum without doubling', 0, () => {
      const service = new ActivityContributionService();
      const existing: AiraActivityDailyAggregate[] = [createActivityAggregate(10, 8, 1, 10)];
      const incoming: AiraActivityDailyAggregate[] = [createActivityAggregate(12, 5, 3, 20)];

      const first = service.mergePortableTotals(existing, incoming);
      const second = service.mergePortableTotals(first, incoming);

      expect(first.length).assertEqual(1);
      expect(first[0].score).assertEqual(12);
      expect(first[0].pageVisits).assertEqual(8);
      expect(first[0].searches).assertEqual(3);
      expect(second[0].score).assertEqual(12);
      expect(second[0].pageVisits).assertEqual(8);
      expect(second[0].searches).assertEqual(3);
    });

    it('rejects duplicate script ids and invalid userscript source during inspection', 0, () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const validRecord = createUserScriptRecordJson('backup-script', true, createUserScriptSource());
      const duplicatePayload = createUserScriptPayload(validRecord, '', validRecord);
      const invalidRecord = createUserScriptRecordJson('invalid-script', true, 'console.log("missing metadata");');

      expect(captureImportInspectionError(service, duplicatePayload).includes('用户脚本记录无效')).assertTrue();
      expect(captureImportInspectionError(service, createUserScriptPayload(invalidRecord)).includes('格式无效'))
        .assertTrue();
    });

    it('rejects missing or duplicate script-value ownership records', 0, () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const record = createUserScriptRecordJson('backup-script', true, createUserScriptSource());
      const missingScriptPayload = createDocumentPayload(
        '{"userScriptValues":{"schemaVersion":1,"data":{"values":[]}}}'
      );
      const duplicateValues = '[{"scriptId":"backup-script","key":"rules","valueJson":"1","updatedAt":10},' +
        '{"scriptId":"backup-script","key":"rules","valueJson":"2","updatedAt":20}]';

      expect(captureImportInspectionError(service, missingScriptPayload).includes('脚本数据格式无效')).assertTrue();
      expect(captureImportInspectionError(service, createUserScriptPayload(record, duplicateValues))
        .includes('脚本数据记录无效')).assertTrue();
    });

    it('rejects invalid JSON in a script value', 0, () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const record = createUserScriptRecordJson('backup-script', true, createUserScriptSource());
      const values = '[{"scriptId":"backup-script","key":"rules","valueJson":"{",' +
        '"updatedAt":10}]';

      expect(captureImportInspectionError(service, createUserScriptPayload(record, values))
        .includes('无效值')).assertTrue();
    });

    it('skips a script when a declared require source is missing from the backup', 0, async () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const source = createUserScriptSource('https://cdn.example/required.js');
      const record = createUserScriptRecordJson('backup-script', true, source);
      const inspection = service.inspectPayload(createUserScriptPayload(record));

      const result = await service.importDocument(
        inspection.document,
        createSelection(false, false, false, true, false)
      );

      expect(result.userScriptCount).assertEqual(0);
      expect(result.skippedUserScriptCount).assertEqual(1);
      expect(fixture.repository.listScripts().length).assertEqual(0);
    });

    it('restores every declared require source in declaration order', 0, async () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const source = createUserScriptSourceWithRequires([
        'https://cdn.example/first.js',
        'https://cdn.example/second.js'
      ]);
      const requires = '[{"executionOrder":0,"source":"console.log(1);"},' +
        '{"executionOrder":1,"source":"console.log(2);"}]';
      const record = createUserScriptRecordJson('backup-script', true, source, requires);
      const document = service.inspectPayload(createUserScriptPayload(record)).document;

      const result = await service.importDocument(
        document,
        createSelection(false, false, false, true, false)
      );
      const installed = fixture.repository.listScripts();

      expect(result.userScriptCount).assertEqual(1);
      expect(result.skippedUserScriptCount).assertEqual(0);
      expect(installed.length).assertEqual(1);
      expect(installed[0].requireSources.length).assertEqual(2);
      expect(installed[0].requireSources[0]).assertEqual('console.log(1);');
      expect(installed[0].requireSources[1]).assertEqual('console.log(2);');
    });

    it('rejects a materialized require with a non-contiguous execution order', 0, () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const source = createUserScriptSource('https://cdn.example/required.js');
      const requires = '[{"executionOrder":1,"source":"console.log(1);"}]';
      const record = createUserScriptRecordJson('backup-script', true, source, requires);

      expect(captureImportInspectionError(service, createUserScriptPayload(record))
        .includes('用户脚本记录无效')).assertTrue();
    });

    it('skips a script when a declared resource is missing or mismatched', 0, async () => {
      const missingFixture = new ScriptFixture();
      const missingService = createScriptService(missingFixture);
      const source = createUserScriptSource('', 'https://cdn.example/icon.svg');
      const missingRecord = createUserScriptRecordJson('missing-resource', true, source);
      const missingDocument = missingService.inspectPayload(createUserScriptPayload(missingRecord)).document;
      const missingResult = await missingService.importDocument(
        missingDocument,
        createSelection(false, false, false, true, false)
      );

      const mismatchedFixture = new ScriptFixture();
      const mismatchedService = createScriptService(mismatchedFixture);
      const resources = '[{"name":"icon","url":"https://cdn.example/other.svg",' +
        '"text":"<svg></svg>","mimeType":"image/svg+xml","contentBase64":""}]';
      const mismatchedRecord = createUserScriptRecordJson('mismatched-resource', true, source, '[]', resources);
      const mismatchedDocument = mismatchedService.inspectPayload(
        createUserScriptPayload(mismatchedRecord)
      ).document;
      const mismatchedResult = await mismatchedService.importDocument(
        mismatchedDocument,
        createSelection(false, false, false, true, false)
      );

      expect(missingResult.skippedUserScriptCount).assertEqual(1);
      expect(mismatchedResult.skippedUserScriptCount).assertEqual(1);
      expect(missingFixture.repository.listScripts().length).assertEqual(0);
      expect(mismatchedFixture.repository.listScripts().length).assertEqual(0);
    });

    it('restores the backed-up enabled state for new and existing scripts', 0, async () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const enabledRecord = createUserScriptRecordJson('backup-script', true, createUserScriptSource());
      const enabledDocument = service.inspectPayload(createUserScriptPayload(enabledRecord)).document;
      const selection = createSelection(false, false, false, true, false);

      const first = await service.importDocument(enabledDocument, selection);
      const installedAfterFirst = fixture.repository.listScripts();
      const disabledRecord = createUserScriptRecordJson('backup-script', false, createUserScriptSource());
      const disabledDocument = service.inspectPayload(createUserScriptPayload(disabledRecord)).document;
      const second = await service.importDocument(disabledDocument, selection);
      const installedAfterSecond = fixture.repository.listScripts();

      expect(first.userScriptCount).assertEqual(1);
      expect(installedAfterFirst.length).assertEqual(1);
      expect(installedAfterFirst[0].enabled).assertTrue();
      expect(second.userScriptCount).assertEqual(1);
      expect(installedAfterSecond.length).assertEqual(1);
      expect(installedAfterSecond[0].enabled).assertFalse();
    });

    it('restores script values and makes a repeated import a value no-op', 0, async () => {
      const fixture = new ScriptFixture();
      const service = createScriptService(fixture);
      const record = createUserScriptRecordJson('backup-script', true, createUserScriptSource());
      const values = '[{"scriptId":"backup-script","key":"rules",' +
        '"valueJson":"{\\"count\\":3}","updatedAt":10}]';
      const document = service.inspectPayload(createUserScriptPayload(record, values)).document;
      const selection = createSelection(false, false, false, true, true);

      const first = await service.importDocument(document, selection);
      const installedScriptId = fixture.repository.listScripts()[0].id;
      const second = await service.importDocument(document, selection);

      expect(first.userScriptValueCount).assertEqual(1);
      expect(second.userScriptValueCount).assertEqual(0);
      expect(fixture.valueStore.readCommittedValueJson(installedScriptId, 'rules')).assertEqual('{"count":3}');
    });

    it('rejects private-session import before touching regular-profile data', 0, async () => {
      const repository = new InMemoryHistoryRepository();
      const service = createHistoryService(repository);
      const inspection = service.inspectPayload(createHistoryOnlyPayload());
      const coordinator = new LocalBackupCoordinator(service, new ImmediateBackupSyncExperienceDomain());

      const outcome = await coordinator.importPrepared(
        inspection,
        createSelection(false, true, false, false, false),
        createBoundary('session_ephemeral', 'private')
      );

      expect(outcome.status).assertEqual('failed');
      expect(outcome.message.includes('隐私会话')).assertTrue();
      expect(repository.listVisits().length).assertEqual(0);
    });

    it('keeps completed history when a later personalization import fails and explains no rollback', 0, async () => {
      const repository = new InMemoryHistoryRepository();
      const service = new LocalBackupService(
        new InMemoryBookmarkBackupDomain(),
        new FailingPersonalizationBackupDomain(),
        repository,
        new HistoryFeature(repository),
        new InMemoryUserScriptRepository(),
        new InMemoryUserScriptPackageDomain(),
        new InMemoryUserScriptValueDomain()
      );
      const inspection = service.inspectPayload(createHistoryAndPersonalizationPayload());
      const coordinator = new LocalBackupCoordinator(service, new ImmediateBackupSyncExperienceDomain());

      const outcome = await coordinator.importPrepared(
        inspection,
        createSelection(false, true, true, false, false),
        createBoundary('profile_persistent', 'regular')
      );

      expect(outcome.status).assertEqual('failed');
      expect(outcome.message.includes('injected-personalization-failure')).assertTrue();
      expect(outcome.message.includes('不会自动回滚')).assertTrue();
      expect(repository.listVisits().length).assertEqual(1);
    });
  });
}

function captureImportInspectionError(service: LocalBackupService, payload: string): string {
  try {
    service.inspectPayload(payload);
  } catch (error) {
    return error instanceof Error ? error.message : 'unknown-error';
  }
  return '';
}

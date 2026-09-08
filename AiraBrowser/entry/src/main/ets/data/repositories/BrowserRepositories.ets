import {
  BookmarkNode,
  BookmarkCreateNodeCommand,
  BookmarkMoveSubtreesCommand,
  BookmarkMoveSubtreeCommand,
  BookmarkReorderChildrenCommand,
  BookmarkRepositorySnapshot,
  BookmarkRootRecord,
  BookmarkStorageScope,
  CreateShortcutCommand,
  CreateHistoryVisitCommand,
  HistoryVisit,
  HistorySiteAggregate,
  HistoryTransferVisit,
  isBrowserDataBoundarySessionEphemeralTabLike,
  RecentlyClosedTabRecord,
  ReplaceScenarioShortcutsCommand,
  ShortcutScenarioRecord,
  ShortcutRecord,
  shouldPersistBrowserDataBoundaryTabLike,
  TabRecord,
  UpdateShortcutCommand,
  UpdateBookmarkCommand
} from '../../common/models/BrowserModels';
import { BrowserDatabase } from '../database/BrowserDatabase';
import {
  HistorySyncMutationOrigin,
  HistorySyncOutboxContext
} from '../../common/models/HistorySyncModels';
import { ActivityTracker } from '../../services/activity/ActivityTracker';
import {
  BrowserRecentlyClosedTabRecord,
  DEFAULT_RECENTLY_CLOSED_PERSISTED_LIMIT
} from '../../core/browser/BrowserRecentlyClosedTabsService';
import { BookmarkStatsVersionSignal } from '../../core/bookmarks/BookmarkStatsVersionSignal';
import { BrowserTabState, TabManager } from '../../core/tabs/TabManager';
import {
  buildBookmarkRootRecords,
  buildMissingSeedBookmarkNodes,
  buildBookmarkUrlIdentityKey,
  buildSeedBookmarkNodes,
  buildLocalBookmarkNode,
  BOOKMARK_OTHER_ROOT_ID,
  collectBookmarkSubtreeIds,
  collectBookmarkSubtreeIdsForRoots,
  createLocalBookmarkId,
  DEFAULT_ACTOR,
  DEFAULT_DEVICE_ID,
  InMemoryBookmarkRepository,
  isBookmarkRootNodeId,
  applyLocalBookmarkUpdate,
  filterBookmarkSearchCandidates,
  isUserSearchableBookmark,
  markBookmarkDeleted,
  markBookmarkMoved,
  markBookmarkPositionCompacted,
  markBookmarkRepositioned,
  resolveBookmarkScope,
  sanitizeBookmarkTitle,
  sanitizeBookmarkUrl
} from './BookmarkRepositoryCore';
import {
  BrowserDefaultSeedSite,
  DEFAULT_BROWSER_SEED_SITES
} from './BrowserDefaultSeedSites';
import { RecentlyClosedTabSnapshotStore } from './RecentlyClosedTabSnapshotStore';
import { HomeShortcutLogicService } from '../../services/shortcuts/HomeShortcutLogicService';

export { InMemoryBookmarkRepository } from './BookmarkRepositoryCore';

interface RepositoryErrorLike {
  code?: number;
  message?: string;
  name?: string;
}

interface BookmarkTreeIndexCaches {
  syncNodeByIdCache: Map<string, BookmarkNode>;
  activeNodeByIdCache: Map<string, BookmarkNode>;
  childrenByParentCache: Map<string, BookmarkNode[]>;
  activeNodesCache: BookmarkNode[];
}

const BOOKMARK_INDEX_REBUILD_BATCH_SIZE: number = 200;
const BOOKMARK_CACHE_BULK_PATCH_THRESHOLD: number = 128;
const BOOKMARK_TREE_PATCH_PARENT_REBUILD_THRESHOLD: number = 32;
const LEGACY_MOBILE_BOOKMARK_ROOT_ID: string = 'bookmark-root-mobile';

function pauseBookmarkIndexWork(): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => resolve(), 0);
  });
}

function describeRepositoryError(error: Error | Object): string {
  const errorLike = error as RepositoryErrorLike;
  const parts: string[] = [];
  if (typeof errorLike.name === 'string' && errorLike.name.length > 0) {
    parts.push(`name=${errorLike.name}`);
  }
  if (typeof errorLike.message === 'string' && errorLike.message.length > 0) {
    parts.push(`message=${errorLike.message}`);
  }
  if (typeof errorLike.code === 'number') {
    parts.push(`code=${errorLike.code}`);
  }
  if (parts.length > 0) {
    return parts.join(', ');
  }
  const json = JSON.stringify(error);
  if (json.length > 0 && json !== '{}') {
    return json;
  }
  return 'unknown error';
}

export interface ShortcutRepository {
  listAll(): ShortcutRecord[];
  listSyncShortcuts(): ShortcutRecord[];
  listScenarios(): ShortcutScenarioRecord[];
  listSyncScenarios(): ShortcutScenarioRecord[];
  setLocalChangeHandler(handler: ShortcutLocalChangeHandler): void;
  runExclusiveMutation<T>(operation: () => Promise<T>): Promise<T>;
  initialize(): Promise<void>;
  refresh(): Promise<ShortcutRecord[]>;
  seedIfEmpty(): Promise<void>;
  createShortcut(command: CreateShortcutCommand): Promise<ShortcutRecord>;
  updateShortcut(command: UpdateShortcutCommand): Promise<ShortcutRecord | undefined>;
  replaceScenarioShortcuts(command: ReplaceScenarioShortcutsCommand): Promise<ShortcutRecord[]>;
  upsertSyncShortcut(shortcut: ShortcutRecord): Promise<ShortcutRecord>;
  applySyncSnapshot(scenarios: ShortcutScenarioRecord[], shortcuts: ShortcutRecord[]): Promise<void>;
  purgeDeletedSyncRecords(): Promise<number>;
  updateShortcutIcon(id: string, expectedUrl: string, icon: string): Promise<ShortcutRecord | undefined>;
  deleteShortcut(id: string): Promise<boolean>;
}

export type ShortcutLocalChangeHandler = () => void;

export interface BookmarkRepository {
  listRoots(): BookmarkRootRecord[];
  listNodes(scope?: BookmarkStorageScope): BookmarkNode[];
  getChangeGeneration(): number;
  listPreviewChildren?(parentId?: string, limit?: number, scope?: BookmarkStorageScope): Promise<BookmarkNode[]>;
  listSuggestionCandidates(limit?: number, scope?: BookmarkStorageScope): BookmarkNode[];
  listSearchCandidates(query: string, limit: number, scope?: BookmarkStorageScope): BookmarkNode[];
  listSyncNodes(scope?: BookmarkStorageScope): BookmarkNode[];
  listChildren(parentId?: string, scope?: BookmarkStorageScope): BookmarkNode[];
  findBookmarkByUrl(url: string, scope?: BookmarkStorageScope): BookmarkNode | undefined;
  findNodeById(id: string, includeDeleted?: boolean): BookmarkNode | undefined;
  listSubtree(rootId: string, includeDeleted?: boolean, scope?: BookmarkStorageScope): BookmarkNode[];
  getSnapshot(includeDeleted?: boolean, scope?: BookmarkStorageScope): BookmarkRepositorySnapshot;
  getDatabase?(): BrowserDatabase | undefined;
  isInitialized(): boolean;
  initialize(): Promise<void>;
  refresh(): Promise<BookmarkNode[]>;
  seedIfEmpty(): Promise<void>;
  createNode(command: BookmarkCreateNodeCommand): Promise<BookmarkNode>;
  updateNode(command: UpdateBookmarkCommand): Promise<BookmarkNode | undefined>;
  upsertNode(node: BookmarkNode): Promise<BookmarkNode>;
  upsertSyncNodes(nodes: BookmarkNode[], options?: BookmarkRepositoryUpsertOptions): Promise<BookmarkNode[]>;
  upsertImportedSyncNodes(nodes: BookmarkNode[]): Promise<BookmarkNode[]>;
  reorderChildren(command: BookmarkReorderChildrenCommand): Promise<BookmarkNode[]>;
  moveSubtree(command: BookmarkMoveSubtreeCommand): Promise<BookmarkNode | undefined>;
  moveSubtrees(command: BookmarkMoveSubtreesCommand): Promise<BookmarkNode[]>;
  replaceSnapshot(snapshot: BookmarkRepositorySnapshot): Promise<BookmarkRepositorySnapshot>;
  replaceAllScopes(
    regularSnapshot: BookmarkRepositorySnapshot,
    privateSnapshot: BookmarkRepositorySnapshot
  ): Promise<void>;
  purgeDeletedSyncNodes(scope?: BookmarkStorageScope, deletedBefore?: number): Promise<number>;
  deleteNode(id: string): Promise<boolean>;
  deleteNodes(ids: string[]): Promise<number>;
}

export interface BookmarkRepositoryUpsertOptions {
  databaseBatchSize?: number;
  afterDatabaseBatch?: (stats: BookmarkRepositoryDatabaseBatchStats) => Promise<void>;
  afterCachePatch?: (stats: BookmarkRepositoryCachePatchStats) => Promise<void>;
}

export interface BookmarkRepositoryDatabaseBatchStats {
  index: number;
  start: number;
  count: number;
  elapsedMs: number;
  hasMore: boolean;
}

export interface BookmarkRepositoryCachePatchStats {
  count: number;
  elapsedMs: number;
}

export interface HistoryRepository {
  listVisits(limit?: number): HistoryVisit[];
  initialize(): Promise<void>;
  refreshPreview(limit: number): Promise<HistoryVisit[]>;
  refreshPage(offset: number, limit: number): Promise<HistoryVisit[]>;
  refreshSearchPage(query: string, offset: number, limit: number): Promise<HistoryVisit[]>;
  refreshSitePage(query: string, offset: number, limit: number): Promise<HistorySiteAggregate[]>;
  refresh(): Promise<HistoryVisit[]>;
  addVisit(command: CreateHistoryVisitCommand): Promise<HistoryVisit>;
  deleteVisit(id: string, origin?: HistorySyncMutationOrigin): Promise<boolean>;
  deleteVisitsByIds(ids: string[], origin?: HistorySyncMutationOrigin): Promise<number>;
  deleteVisitsInRange(startAt: number, endAt: number, origin?: HistorySyncMutationOrigin): Promise<number>;
  deleteVisitsByHost(host: string, origin?: HistorySyncMutationOrigin): Promise<number>;
  clearVisits(origin?: HistorySyncMutationOrigin): Promise<number>;
  importVisits(visits: HistoryTransferVisit[]): Promise<number>;
  listSuggestions(limit?: number): HistoryVisit[];
  listSuggestionCandidates(limit?: number): HistoryVisit[];
}

export interface HistorySyncRepositoryContext {
  enabled: boolean;
  accountUid: string;
  clientId: string;
  deviceName: string;
}

export type HistorySyncRepositoryContextProvider = () => HistorySyncRepositoryContext;
export type HistorySyncRepositoryChangeHandler = () => void;

export interface TabSessionRepository {
  listTabs(windowId?: string, profileId?: string): TabRecord[];
  initialize(): Promise<void>;
  refresh(windowId?: string, profileId?: string): Promise<TabRecord[]>;
  replaceTabs(
    tabs: TabRecord[],
    windowId?: string,
    profileId?: string,
    options?: TabSessionReplaceOptions
  ): Promise<TabRecord[]>;
}

export interface TabSessionReplaceOptions {
  allowPrivateTabs?: boolean;
}

export interface RecentlyClosedTabRepository {
  listRecords(windowId?: string, profileId?: string): BrowserRecentlyClosedTabRecord[];
  primeFromSnapshot(windowId?: string, profileId?: string): Promise<BrowserRecentlyClosedTabRecord[]>;
  replaceCachedRecords(records: BrowserRecentlyClosedTabRecord[], windowId?: string, profileId?: string): BrowserRecentlyClosedTabRecord[];
  initialize(): Promise<void>;
  refresh(windowId?: string, profileId?: string): Promise<BrowserRecentlyClosedTabRecord[]>;
  replaceRecords(
    records: BrowserRecentlyClosedTabRecord[],
    windowId?: string,
    profileId?: string
  ): Promise<BrowserRecentlyClosedTabRecord[]>;
  clearRecords(windowId?: string, profileId?: string): Promise<number>;
  clearAllRecords(): Promise<number>;
  deleteRecordsInRange(startAt: number, endAt: number, windowId?: string, profileId?: string): Promise<number>;
}

export class InMemoryShortcutRepository implements ShortcutRepository {
  private scenarios: ShortcutScenarioRecord[] = buildSeedShortcutScenarios();
  private shortcuts: ShortcutRecord[] = buildSeedShortcuts();
  private localChangeHandler?: ShortcutLocalChangeHandler;
  private shortcutLogicService: HomeShortcutLogicService = new HomeShortcutLogicService();
  private mutationTail: Promise<void> = Promise.resolve();

  listAll(): ShortcutRecord[] {
    const activeShortcuts = this.shortcuts
      .filter((shortcut: ShortcutRecord) => {
        return shortcut.sync?.deletedAt === undefined && isAiraOwnedShortcut(shortcut);
      })
      .slice()
      .sort((left: ShortcutRecord, right: ShortcutRecord) => left.position - right.position);
    return this.shortcutLogicService.projectUniqueActiveDestinations(activeShortcuts);
  }

  listSyncShortcuts(): ShortcutRecord[] {
    return this.shortcuts
      .slice()
      .sort((left: ShortcutRecord, right: ShortcutRecord) => left.position - right.position);
  }

  setLocalChangeHandler(handler: ShortcutLocalChangeHandler): void {
    this.localChangeHandler = handler;
  }

  runExclusiveMutation<T>(operation: () => Promise<T>): Promise<T> {
    const run = this.mutationTail.then(
      (): Promise<T> => operation(),
      (): Promise<T> => operation()
    );
    this.mutationTail = run.then(
      (): void => undefined,
      (): void => undefined
    );
    return run;
  }

  listScenarios(): ShortcutScenarioRecord[] {
    return this.scenarios
      .filter((scenario: ShortcutScenarioRecord) => {
        return scenario.sync.deletedAt === undefined && isAiraOwnedShortcutScenario(scenario);
      })
      .slice()
      .sort((left: ShortcutScenarioRecord, right: ShortcutScenarioRecord) => left.position - right.position);
  }

  listSyncScenarios(): ShortcutScenarioRecord[] {
    return this.scenarios
      .slice()
      .sort((left: ShortcutScenarioRecord, right: ShortcutScenarioRecord) => left.position - right.position);
  }

  async initialize(): Promise<void> {
    return Promise.resolve();
  }

  async refresh(): Promise<ShortcutRecord[]> {
    return Promise.resolve(this.listAll());
  }

  async seedIfEmpty(): Promise<void> {
    return Promise.resolve();
  }

  async createShortcut(command: CreateShortcutCommand): Promise<ShortcutRecord> {
    const shortcut = buildLocalShortcutRecord(command, this.resolveNextShortcutPosition(command.scenarioId));
    this.shortcuts.push(shortcut);
    this.touchScenarioOrder(shortcut.scenarioId ?? 'aira_default_scenario', resolveShortcutRecordModifiedAt(shortcut));
    this.notifyLocalChange();
    return Promise.resolve(shortcut);
  }

  async updateShortcut(command: UpdateShortcutCommand): Promise<ShortcutRecord | undefined> {
    const index = this.shortcuts.findIndex((shortcut: ShortcutRecord) => shortcut.id === command.id);
    if (index < 0) {
      return Promise.resolve(undefined);
    }
    const updated = applyLocalShortcutUpdate(this.shortcuts[index], command);
    this.shortcuts[index] = updated;
    this.notifyLocalChange();
    return Promise.resolve(updated);
  }

  async replaceScenarioShortcuts(command: ReplaceScenarioShortcutsCommand): Promise<ShortcutRecord[]> {
    const normalized = normalizeShortcutTreeForLocalReplace(command.scenarioId, command.shortcuts);
    const nextRootIds = new Set<string>(normalized.map((shortcut: ShortcutRecord) => shortcut.id));
    const staleRoots = this.shortcuts.filter((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        isAiraOwnedShortcut(shortcut) &&
        (shortcut.scenarioId ?? 'aira_default_scenario') === command.scenarioId &&
        !nextRootIds.has(shortcut.id);
    });

    this.shortcuts = this.shortcuts.map((shortcut: ShortcutRecord) => {
      const replacement = normalized.find((item: ShortcutRecord) => item.id === shortcut.id);
      return replacement ?? shortcut;
    });
    normalized.forEach((shortcut: ShortcutRecord) => {
      if (!this.shortcuts.some((item: ShortcutRecord) => item.id === shortcut.id)) {
        this.shortcuts.push(shortcut);
      }
    });
    const deletedRoots = staleRoots.map((shortcut: ShortcutRecord): ShortcutRecord => markShortcutDeleted(shortcut));
    deletedRoots.forEach((shortcut: ShortcutRecord) => {
      const index = this.shortcuts.findIndex((item: ShortcutRecord) => item.id === shortcut.id);
      if (index >= 0) {
        this.shortcuts[index] = shortcut;
      } else {
        this.shortcuts.push(shortcut);
      }
    });
    this.touchScenarioOrder(
      command.scenarioId,
      resolveShortcutBatchModifiedAt(normalized.concat(deletedRoots), Date.now())
    );
    this.notifyLocalChange();
    return Promise.resolve(this.listAll());
  }

  async upsertSyncShortcut(shortcut: ShortcutRecord): Promise<ShortcutRecord> {
    const index = this.shortcuts.findIndex((item: ShortcutRecord) => item.id === shortcut.id);
    if (index >= 0) {
      this.shortcuts[index] = shortcut;
    } else {
      this.shortcuts.push(shortcut);
    }
    return Promise.resolve(shortcut);
  }

  async applySyncSnapshot(scenarios: ShortcutScenarioRecord[], shortcuts: ShortcutRecord[]): Promise<void> {
    scenarios.forEach((scenario: ShortcutScenarioRecord): void => {
      const index = this.scenarios.findIndex((item: ShortcutScenarioRecord) => item.id === scenario.id);
      if (index >= 0) {
        this.scenarios[index] = scenario;
      } else {
        this.scenarios.push(scenario);
      }
    });
    shortcuts.forEach((shortcut: ShortcutRecord): void => {
      const index = this.shortcuts.findIndex((item: ShortcutRecord) => item.id === shortcut.id);
      if (index >= 0) {
        this.shortcuts[index] = shortcut;
      } else {
        this.shortcuts.push(shortcut);
      }
    });
    return Promise.resolve();
  }

  async purgeDeletedSyncRecords(): Promise<number> {
    const scenarioCount = this.scenarios.length;
    const shortcutCount = this.shortcuts.length;
    this.scenarios = this.scenarios.filter((scenario: ShortcutScenarioRecord): boolean => {
      return scenario.sync.deletedAt === undefined;
    });
    this.shortcuts = this.shortcuts.filter((shortcut: ShortcutRecord): boolean => {
      return shortcut.sync?.deletedAt === undefined;
    });
    return Promise.resolve((scenarioCount - this.scenarios.length) + (shortcutCount - this.shortcuts.length));
  }

  async updateShortcutIcon(
    id: string,
    expectedUrl: string,
    icon: string
  ): Promise<ShortcutRecord | undefined> {
    const index = this.shortcuts.findIndex((item: ShortcutRecord) => item.id === id);
    if (index < 0 || this.shortcuts[index].url !== expectedUrl) {
      return Promise.resolve(undefined);
    }
    const updated = cloneShortcutWithIcon(this.shortcuts[index], icon.trim());
    this.shortcuts[index] = updated;
    return Promise.resolve(updated);
  }

  async deleteShortcut(id: string): Promise<boolean> {
    const index = this.shortcuts.findIndex((shortcut: ShortcutRecord) => shortcut.id === id);
    if (index < 0) {
      return Promise.resolve(false);
    }
    const deleted = markShortcutDeleted(this.shortcuts[index]);
    this.shortcuts[index] = deleted;
    this.touchScenarioOrder(
      deleted.scenarioId ?? 'aira_default_scenario',
      resolveShortcutRecordModifiedAt(deleted)
    );
    this.notifyLocalChange();
    return Promise.resolve(true);
  }

  private touchScenarioOrder(scenarioId: string, updatedAt: number): void {
    const index = this.scenarios.findIndex((scenario: ShortcutScenarioRecord) => scenario.id === scenarioId);
    if (index < 0) {
      return;
    }
    this.scenarios[index] = markShortcutScenarioOrderChanged(this.scenarios[index], updatedAt);
  }

  private notifyLocalChange(): void {
    try {
      this.localChangeHandler?.();
    } catch (_error) {
    }
  }

  private resolveNextShortcutPosition(scenarioId?: string): number {
    const targetScenarioId = scenarioId ?? 'aira_default_scenario';
    const matching = this.shortcuts.filter((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        isAiraOwnedShortcut(shortcut) &&
        (shortcut.scenarioId ?? 'aira_default_scenario') === targetScenarioId;
    });
    if (matching.length === 0) {
      return 0;
    }
    return Math.max(...matching.map((shortcut: ShortcutRecord) => shortcut.position)) + 1;
  }
}

export class RdbShortcutRepository implements ShortcutRepository {
  private database: BrowserDatabase;
  private scenariosCache: ShortcutScenarioRecord[] = buildSeedShortcutScenarios();
  private shortcutsCache: ShortcutRecord[] = buildSeedShortcuts();
  private initializationPromise?: Promise<void>;
  private localChangeHandler?: ShortcutLocalChangeHandler;
  private shortcutLogicService: HomeShortcutLogicService = new HomeShortcutLogicService();
  private mutationTail: Promise<void> = Promise.resolve();

  constructor(database: BrowserDatabase) {
    this.database = database;
  }

  listAll(): ShortcutRecord[] {
    const activeShortcuts = this.shortcutsCache
      .filter((shortcut: ShortcutRecord) => {
        return shortcut.sync?.deletedAt === undefined && isAiraOwnedShortcut(shortcut);
      })
      .slice()
      .sort((left: ShortcutRecord, right: ShortcutRecord) => {
        if ((left.scenarioId ?? '') === (right.scenarioId ?? '')) {
          return left.position - right.position;
        }
        return (left.scenarioId ?? '').localeCompare(right.scenarioId ?? '');
      });
    return this.shortcutLogicService.projectUniqueActiveDestinations(activeShortcuts);
  }

  listSyncShortcuts(): ShortcutRecord[] {
    return this.shortcutsCache
      .slice()
      .sort((left: ShortcutRecord, right: ShortcutRecord) => {
        if ((left.scenarioId ?? '') === (right.scenarioId ?? '')) {
          return left.position - right.position;
        }
        return (left.scenarioId ?? '').localeCompare(right.scenarioId ?? '');
      });
  }

  listScenarios(): ShortcutScenarioRecord[] {
    return this.scenariosCache
      .filter((scenario: ShortcutScenarioRecord) => {
        return scenario.sync.deletedAt === undefined && isAiraOwnedShortcutScenario(scenario);
      })
      .slice()
      .sort((left: ShortcutScenarioRecord, right: ShortcutScenarioRecord) => left.position - right.position);
  }

  listSyncScenarios(): ShortcutScenarioRecord[] {
    return this.scenariosCache
      .slice()
      .sort((left: ShortcutScenarioRecord, right: ShortcutScenarioRecord) => left.position - right.position);
  }

  setLocalChangeHandler(handler: ShortcutLocalChangeHandler): void {
    this.localChangeHandler = handler;
  }

  runExclusiveMutation<T>(operation: () => Promise<T>): Promise<T> {
    const run = this.mutationTail.then(
      (): Promise<T> => operation(),
      (): Promise<T> => operation()
    );
    this.mutationTail = run.then(
      (): void => undefined,
      (): void => undefined
    );
    return run;
  }

  async initialize(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.database.initialize()
        .then(() => this.seedIfEmpty())
        .then(() => this.refresh())
        .then(() => undefined)
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw new Error(`Shortcut repository initialization failed: ${describeRepositoryError(error)}`);
        });
    }
    return this.initializationPromise;
  }

  async refresh(): Promise<ShortcutRecord[]> {
    this.scenariosCache = await this.database.listShortcutScenarios();
    this.shortcutsCache = await this.database.listShortcuts();
    return this.listAll();
  }

  async seedIfEmpty(): Promise<void> {
    await this.database.seedShortcutsIfEmpty(buildSeedShortcutScenarios(), buildSeedShortcuts());
    await this.appendMissingSeedShortcuts();
  }

  async createShortcut(command: CreateShortcutCommand): Promise<ShortcutRecord> {
    await this.initialize();
    const shortcut = buildLocalShortcutRecord(command, this.resolveNextShortcutPosition(command.scenarioId));
    const scenario = this.buildOrderChangedScenario(
      shortcut.scenarioId ?? 'aira_default_scenario',
      resolveShortcutRecordModifiedAt(shortcut)
    );
    await this.database.upsertShortcutSnapshot(scenario === undefined ? [] : [scenario], [shortcut]);
    await this.refresh();
    this.notifyLocalChange();
    return shortcut;
  }

  async updateShortcut(command: UpdateShortcutCommand): Promise<ShortcutRecord | undefined> {
    await this.initialize();
    const existing = this.shortcutsCache.find((shortcut: ShortcutRecord) => shortcut.id === command.id);
    if (existing === undefined) {
      return undefined;
    }
    const shortcut = applyLocalShortcutUpdate(existing, command);
    await this.database.upsertShortcut(shortcut);
    await this.refresh();
    this.notifyLocalChange();
    return shortcut;
  }

  async replaceScenarioShortcuts(command: ReplaceScenarioShortcutsCommand): Promise<ShortcutRecord[]> {
    await this.initialize();
    const normalized = normalizeShortcutTreeForLocalReplace(command.scenarioId, command.shortcuts);
    const nextRootIds = new Set<string>(normalized.map((shortcut: ShortcutRecord) => shortcut.id));
    const staleRoots = this.shortcutsCache.filter((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        isAiraOwnedShortcut(shortcut) &&
        (shortcut.scenarioId ?? 'aira_default_scenario') === command.scenarioId &&
        !nextRootIds.has(shortcut.id);
    });

    const deletedRoots = staleRoots.map((shortcut: ShortcutRecord): ShortcutRecord => markShortcutDeleted(shortcut));
    const scenario = this.buildOrderChangedScenario(
      command.scenarioId,
      resolveShortcutBatchModifiedAt(normalized.concat(deletedRoots), Date.now())
    );
    await this.database.upsertShortcutSnapshot(
      scenario === undefined ? [] : [scenario],
      normalized.concat(deletedRoots)
    );

    await this.refresh();
    this.notifyLocalChange();
    return this.listAll();
  }

  async upsertSyncShortcut(shortcut: ShortcutRecord): Promise<ShortcutRecord> {
    await this.initialize();
    await this.database.upsertShortcut(shortcut);
    await this.refresh();
    return shortcut;
  }

  async applySyncSnapshot(scenarios: ShortcutScenarioRecord[], shortcuts: ShortcutRecord[]): Promise<void> {
    await this.initialize();
    await this.database.upsertShortcutSnapshot(scenarios, shortcuts);
    await this.refresh();
  }

  async purgeDeletedSyncRecords(): Promise<number> {
    await this.initialize();
    const deletedCount = await this.database.purgeDeletedShortcutSyncRecords();
    if (deletedCount > 0) {
      await this.refresh();
    }
    return deletedCount;
  }

  async updateShortcutIcon(
    id: string,
    expectedUrl: string,
    icon: string
  ): Promise<ShortcutRecord | undefined> {
    await this.initialize();
    const existing = this.shortcutsCache.find((shortcut: ShortcutRecord) => shortcut.id === id);
    if (existing === undefined || existing.url !== expectedUrl) {
      return undefined;
    }
    const normalizedIcon = icon.trim();
    if ((existing.icon ?? '').trim() === normalizedIcon) {
      return existing;
    }
    const updated = cloneShortcutWithIcon(existing, normalizedIcon);
    const persisted = await this.database.updateShortcutIcon(id, expectedUrl, normalizedIcon);
    if (!persisted) {
      await this.refresh();
      return undefined;
    }
    const current = this.shortcutsCache.find((shortcut: ShortcutRecord) => shortcut.id === id);
    if (current === undefined || current.url !== expectedUrl) {
      await this.refresh();
      return undefined;
    }
    this.shortcutsCache = this.shortcutsCache.map((shortcut: ShortcutRecord) => {
      return shortcut.id === id ? updated : shortcut;
    });
    return updated;
  }

  async deleteShortcut(id: string): Promise<boolean> {
    await this.initialize();
    const existing = this.shortcutsCache.find((shortcut: ShortcutRecord) => shortcut.id === id);
    if (existing === undefined) {
      return false;
    }
    const deleted = markShortcutDeleted(existing);
    const scenario = this.buildOrderChangedScenario(
      deleted.scenarioId ?? 'aira_default_scenario',
      resolveShortcutRecordModifiedAt(deleted)
    );
    await this.database.upsertShortcutSnapshot(scenario === undefined ? [] : [scenario], [deleted]);
    await this.refresh();
    this.notifyLocalChange();
    return true;
  }

  private notifyLocalChange(): void {
    try {
      this.localChangeHandler?.();
    } catch (_error) {
    }
  }

  private resolveNextShortcutPosition(scenarioId?: string): number {
    const targetScenarioId = scenarioId ?? 'aira_default_scenario';
    const matching = this.shortcutsCache.filter((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        isAiraOwnedShortcut(shortcut) &&
        (shortcut.scenarioId ?? 'aira_default_scenario') === targetScenarioId;
    });
    if (matching.length === 0) {
      return 0;
    }
    return Math.max(...matching.map((shortcut: ShortcutRecord) => shortcut.position)) + 1;
  }

  private buildOrderChangedScenario(
    scenarioId: string,
    updatedAt: number
  ): ShortcutScenarioRecord | undefined {
    const scenario = this.scenariosCache.find((item: ShortcutScenarioRecord) => item.id === scenarioId);
    return scenario === undefined ? undefined : markShortcutScenarioOrderChanged(scenario, updatedAt);
  }

  private async appendMissingSeedShortcuts(): Promise<void> {
    const existing = await this.database.listShortcuts();
    const missingSeedShortcuts = buildMissingSeedShortcuts(existing);
    for (const shortcut of missingSeedShortcuts) {
      await this.database.upsertShortcut(shortcut);
    }
  }
}

export class RdbBookmarkRepository implements BookmarkRepository {
  private database: BrowserDatabase;
  private rootsCache: BookmarkRootRecord[] = buildBookmarkRootRecords();
  private nodesCache: BookmarkNode[] = buildSeedBookmarkNodes();
  private activeNodesCache: BookmarkNode[] = [];
  private syncNodeByIdCache: Map<string, BookmarkNode> = new Map();
  private activeNodeByIdCache: Map<string, BookmarkNode> = new Map();
  private childrenByParentCache: Map<string, BookmarkNode[]> = new Map();
  private bookmarkByScopedNormalizedUrlCache: Map<string, BookmarkNode> = new Map();
  private suggestionCandidatesCache: BookmarkNode[] = [];
  private initializationPromise?: Promise<void>;
  private fullIndexRefreshPromise?: Promise<void>;
  private fullIndexRefreshVersion: number = 0;
  private bookmarkChangeGeneration: number = 0;
  private fullBookmarkIndexesReady: boolean = true;
  private initialized: boolean = false;
  private activityTracker?: ActivityTracker;

  constructor(database: BrowserDatabase, activityTracker?: ActivityTracker) {
    this.database = database;
    this.activityTracker = activityTracker;
    this.rebuildBookmarkIndexes();
  }

  getDatabase(): BrowserDatabase {
    return this.database;
  }

  listRoots(): BookmarkRootRecord[] {
    return this.rootsCache.slice().sort((left: BookmarkRootRecord, right: BookmarkRootRecord) => left.position - right.position);
  }

  listNodes(scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return this.activeNodesCache.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
  }

  getChangeGeneration(): number {
    return this.bookmarkChangeGeneration;
  }

  listSuggestionCandidates(limit?: number, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    if (!this.fullBookmarkIndexesReady) {
      const activeBookmarks = this.collectActiveBookmarkNodes(scope);
      return limit !== undefined ? activeBookmarks.slice(0, limit) : activeBookmarks;
    }
    this.ensureFullBookmarkIndexesInBackground();
    const candidates = this.suggestionCandidatesCache.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
    if (limit !== undefined) {
      return candidates.slice(0, limit);
    }
    return candidates;
  }

  listSearchCandidates(query: string, limit: number, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    if (!this.fullBookmarkIndexesReady) {
      return filterBookmarkSearchCandidates(this.collectActiveBookmarkNodes(scope), query, limit);
    }
    this.ensureFullBookmarkIndexesInBackground();
    return filterBookmarkSearchCandidates(
      this.suggestionCandidatesCache.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope)),
      query,
      limit
    );
  }

  listSyncNodes(scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return this.nodesCache.filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
  }

  listChildren(parentId?: string, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    return (this.childrenByParentCache.get(this.toParentKey(parentId)) ?? [])
      .filter((node: BookmarkNode) => this.matchesBookmarkScope(node, scope));
  }

  findBookmarkByUrl(url: string, scope: BookmarkStorageScope = 'regular'): BookmarkNode | undefined {
    if (!this.fullBookmarkIndexesReady) {
      const normalizedUrl = sanitizeBookmarkUrl(url);
      return this.activeNodesCache.find((node: BookmarkNode) => {
        return isUserSearchableBookmark(node) &&
          this.matchesBookmarkScope(node, scope) &&
          sanitizeBookmarkUrl(node.url ?? '') === normalizedUrl;
      });
    }
    this.ensureFullBookmarkIndexesInBackground();
    return this.bookmarkByScopedNormalizedUrlCache.get(buildBookmarkUrlIdentityKey(url, scope));
  }

  findNodeById(id: string, includeDeleted: boolean = false): BookmarkNode | undefined {
    return includeDeleted ? this.syncNodeByIdCache.get(id) : this.activeNodeByIdCache.get(id);
  }

  listSubtree(rootId: string, includeDeleted: boolean = false, scope: BookmarkStorageScope = 'regular'): BookmarkNode[] {
    const source = includeDeleted ? this.listSyncNodes(scope) : this.listNodes(scope);
    const subtreeIds = collectBookmarkSubtreeIds(source, rootId);
    return source.filter((node: BookmarkNode) => subtreeIds.indexOf(node.id) >= 0);
  }

  getSnapshot(includeDeleted: boolean = false, scope: BookmarkStorageScope = 'regular'): BookmarkRepositorySnapshot {
    return {
      roots: this.listRoots(),
      nodes: includeDeleted ? this.listSyncNodes(scope) : this.listNodes(scope)
    };
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  async initialize(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.database.initialize()
        .then(() => this.seedIfEmpty())
        .then(() => this.refresh())
        .then(() => {
          this.initialized = true;
          // The first refresh replaces the seed cache with persisted rows; notify mounted projections once.
          this.bumpBookmarkStatsVersion();
        })
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          const detail = describeRepositoryError(error);
          throw new Error(`Bookmark repository initialization failed: ${detail}`);
        });
    }

    return this.initializationPromise;
  }

  async refresh(): Promise<BookmarkNode[]> {
    this.rootsCache = buildBookmarkRootRecords();
    this.nodesCache = await this.database.listBookmarkNodes();
    await this.rebuildBookmarkTreeIndexesAsync();
    this.bumpBookmarkChangeGeneration();
    this.scheduleFullBookmarkIndexRefresh();
    this.initialized = true;
    return this.listNodes();
  }

  async listPreviewChildren(
    parentId?: string,
    limit: number = 50,
    scope: BookmarkStorageScope = 'regular'
  ): Promise<BookmarkNode[]> {
    return this.database.listBookmarkPreviewChildren(parentId, limit, scope);
  }

  async seedIfEmpty(): Promise<void> {
    await this.database.seedBookmarksIfEmpty(buildSeedBookmarkNodes());
    const existing = await this.database.listBookmarkNodes();
    const missing = buildMissingSeedBookmarkNodes(existing);
    if (missing.length > 0) {
      for (const node of missing) {
        await this.database.upsertBookmarkNode(node);
      }
    }
    await this.database.deleteBookmarkRootPermanently(LEGACY_MOBILE_BOOKMARK_ROOT_ID, BOOKMARK_OTHER_ROOT_ID);
  }

  async createNode(command: BookmarkCreateNodeCommand): Promise<BookmarkNode> {
    await this.initialize();
    const now = Date.now();
    const parentId = this.normalizeParentId(command.parentId);
    const scope = this.resolveCreateNodeScope(command.scope, parentId);
    const node = buildLocalBookmarkNode(
      createLocalBookmarkId(command.type, scope),
      command.type,
      sanitizeBookmarkTitle(command.title, command.type === 'folder' ? '新文件夹' : '新书签'),
      parentId,
      this.resolveNextPosition(parentId),
      now,
      command.type === 'bookmark' ? sanitizeBookmarkUrl(command.url ?? '') : undefined,
      scope
    );
    await this.database.upsertBookmarkNode(node);
    await this.refresh();
    this.recordBookmarkActivity();
    this.bumpBookmarkStatsVersion();
    return node;
  }

  async updateNode(command: UpdateBookmarkCommand): Promise<BookmarkNode | undefined> {
    await this.initialize();
    const existing = this.findNodeById(command.id);
    if (existing === undefined) {
      return undefined;
    }

    const updated = applyLocalBookmarkUpdate(existing, command);
    await this.database.updateBookmarkNode(updated);
    await this.patchBookmarkNodeCacheAsync([updated]);
    this.recordBookmarkActivity();
    this.bumpBookmarkStatsVersion();
    return updated;
  }

  async upsertNode(node: BookmarkNode): Promise<BookmarkNode> {
    await this.initialize();
    await this.database.upsertBookmarkNode(node);
    await this.refresh();
    this.bumpBookmarkStatsVersion();
    return node;
  }

  async upsertSyncNodes(nodes: BookmarkNode[], options?: BookmarkRepositoryUpsertOptions): Promise<BookmarkNode[]> {
    await this.initialize();
    if (nodes.length <= 0) {
      return nodes;
    }
    if (options?.databaseBatchSize !== undefined && options.databaseBatchSize > 0) {
      await this.upsertBookmarkNodesInDatabaseBatches(nodes, options.databaseBatchSize, options.afterDatabaseBatch);
    } else {
      await this.database.upsertBookmarkNodes(nodes);
    }
    const cachePatchStartedAt = Date.now();
    await this.patchBookmarkNodeCacheAsync(nodes);
    if (options?.afterCachePatch !== undefined) {
      await options.afterCachePatch({
        count: nodes.length,
        elapsedMs: Date.now() - cachePatchStartedAt
      });
    }
    this.bumpBookmarkStatsVersion();
    return nodes;
  }

  async upsertImportedSyncNodes(nodes: BookmarkNode[]): Promise<BookmarkNode[]> {
    await this.initialize();
    if (nodes.length <= 0) {
      return nodes;
    }
    await this.database.upsertImportedBookmarkNodes(nodes);
    await this.patchBookmarkNodeCacheAsync(nodes);
    this.bumpBookmarkStatsVersion();
    return nodes;
  }

  async reorderChildren(command: BookmarkReorderChildrenCommand): Promise<BookmarkNode[]> {
    await this.initialize();
    const scope = this.resolveParentScope(command.parentId);
    const siblings = this.listChildren(command.parentId, scope);
    const siblingMap = new Map<string, BookmarkNode>();
    siblings.forEach((node: BookmarkNode) => siblingMap.set(node.id, node));

    const reordered: BookmarkNode[] = [];
    const seen = new Set<string>();
    command.childIds.forEach((id: string) => {
      const node = siblingMap.get(id);
      if (node !== undefined) {
        reordered.push(node);
        seen.add(id);
      }
    });
    siblings.forEach((node: BookmarkNode) => {
      if (!seen.has(node.id)) {
        reordered.push(node);
      }
    });

    const now = Date.now();
    const updates = reordered.map((node: BookmarkNode, index: number) => markBookmarkRepositioned(node, index, now));
    await this.database.updateBookmarkPositions(updates);
    await this.refresh();
    this.recordBookmarkActivity();
    this.bumpBookmarkStatsVersion();
    return this.listChildren(command.parentId, scope);
  }

  async moveSubtree(command: BookmarkMoveSubtreeCommand): Promise<BookmarkNode | undefined> {
    await this.initialize();
    const node = this.findNodeById(command.nodeId);
    if (node === undefined) {
      return undefined;
    }
    const scope = this.resolveNodeScope(node);
    const nextParentId = this.normalizeParentId(command.parentId);
    const siblings = this.listChildren(nextParentId, scope).filter((item: BookmarkNode) => item.id !== node.id);
    const boundedIndex = Math.max(0, Math.min(command.targetIndex, siblings.length));
    const now = Date.now();
    const movedNode = markBookmarkMoved(node, nextParentId, boundedIndex, now);
    const reordered = siblings.slice(0, boundedIndex).concat([movedNode], siblings.slice(boundedIndex));
    const updates = reordered.map((item: BookmarkNode, index: number) => {
      const target = item.id === movedNode.id ? movedNode : item;
      return markBookmarkRepositioned(target, index, now);
    });
    await this.database.upsertBookmarkNode(movedNode);
    await this.database.updateBookmarkPositions(updates);
    if (node.parentId !== nextParentId) {
      await this.refresh();
      await this.renumberActiveChildren(node.parentId);
    } else {
      await this.refresh();
    }
    this.recordBookmarkActivity();
    this.bumpBookmarkStatsVersion();
    return this.findNodeById(command.nodeId);
  }

  async moveSubtrees(command: BookmarkMoveSubtreesCommand): Promise<BookmarkNode[]> {
    await this.initialize();
    const movingNodes = this.resolveMovableNodes(command.nodeIds);
    if (movingNodes.length === 0) {
      return [];
    }
    const nextParentId = this.normalizeParentId(command.parentId);
    const movingLookup = this.buildBookmarkIdLookup(movingNodes.map((node: BookmarkNode) => node.id));
    const scope = movingNodes.length > 0 ? this.resolveNodeScope(movingNodes[0]) : this.resolveParentScope(nextParentId);
    const targetSiblings = this.listChildren(nextParentId, scope).filter((item: BookmarkNode) => !movingLookup.has(item.id));
    const boundedIndex = Math.max(0, Math.min(command.targetIndex, targetSiblings.length));
    const now = Date.now();
    const movedNodes = movingNodes.map((node: BookmarkNode, index: number) => {
      return markBookmarkMoved(node, nextParentId, boundedIndex + index, now);
    });
    const targetOrdered = targetSiblings.slice(0, boundedIndex)
      .concat(movedNodes, targetSiblings.slice(boundedIndex))
      .map((node: BookmarkNode, index: number) => markBookmarkRepositioned(node, index, now));
    const sourceParentKeys = this.collectSourceParentKeys(movingNodes, nextParentId);
    const movedById = new Map<string, BookmarkNode>();
    movedNodes.forEach((node: BookmarkNode) => {
      movedById.set(node.id, node);
    });
    const cacheAfterMove = this.nodesCache.map((node: BookmarkNode) => {
      return movedById.get(node.id) ?? node;
    });
    const sourceRepositioned = this.buildRepositionedChildren(cacheAfterMove, sourceParentKeys, now);
    const updateById = new Map<string, BookmarkNode>();
    targetOrdered.concat(sourceRepositioned).forEach((node: BookmarkNode) => {
      updateById.set(node.id, node);
    });
    const updates: BookmarkNode[] = [];
    updateById.forEach((node: BookmarkNode) => {
      updates.push(node);
    });
    await this.database.upsertBookmarkNodes(updates);
    await this.refresh();
    this.recordBookmarkActivity();
    this.bumpBookmarkStatsVersion();
    const resolvedNodes: BookmarkNode[] = [];
    movedNodes.forEach((node: BookmarkNode) => {
      const resolvedNode = this.findNodeById(node.id);
      if (resolvedNode !== undefined) {
        resolvedNodes.push(resolvedNode);
      }
    });
    return resolvedNodes;
  }

  async replaceSnapshot(snapshot: BookmarkRepositorySnapshot): Promise<BookmarkRepositorySnapshot> {
    await this.initialize();
    await this.database.replaceBookmarkTree(snapshot.nodes, 'regular');
    await this.refresh();
    this.bumpBookmarkStatsVersion();
    return this.getSnapshot(true);
  }

  async replaceAllScopes(
    regularSnapshot: BookmarkRepositorySnapshot,
    privateSnapshot: BookmarkRepositorySnapshot
  ): Promise<void> {
    await this.initialize();
    await this.database.replaceAllBookmarkTrees(regularSnapshot.nodes, privateSnapshot.nodes);
    await this.refresh();
    this.bumpBookmarkStatsVersion();
  }

  async purgeDeletedSyncNodes(
    scope: BookmarkStorageScope = 'regular',
    deletedBefore?: number
  ): Promise<number> {
    await this.initialize();
    const deletedCount = await this.database.purgeDeletedBookmarkNodes(
      resolveBookmarkScope(scope),
      deletedBefore
    );
    if (deletedCount > 0) {
      await this.refresh();
      this.bumpBookmarkStatsVersion();
    }
    return deletedCount;
  }

  async deleteNode(id: string): Promise<boolean> {
    return (await this.deleteNodes([id])) > 0;
  }

  async deleteNodes(ids: string[]): Promise<number> {
    await this.initialize();
    const deletingIds = collectBookmarkSubtreeIdsForRoots(this.nodesCache, ids);
    if (deletingIds.length === 0) {
      return 0;
    }

    const deletingLookup = this.buildBookmarkIdLookup(deletingIds);
    const affectedParentIds = this.collectAffectedParentIds(ids, deletingLookup);
    const now = Date.now();
    const tombstones = this.nodesCache
      .filter((node: BookmarkNode) => deletingLookup.has(node.id))
      .map((node: BookmarkNode) => markBookmarkDeleted(node, now));
    await this.database.upsertBookmarkNodes(tombstones);
    const activeAfterDelete = this.nodesCache.map((node: BookmarkNode) => {
      return deletingLookup.has(node.id) ? markBookmarkDeleted(node, now) : node;
    });
    const repositioned = this.buildCompactedChildren(activeAfterDelete, affectedParentIds);
    if (repositioned.length > 0) {
      await this.database.updateBookmarkPositions(repositioned);
    }
    await this.patchBookmarkNodeCacheAsync(tombstones.concat(repositioned));
    this.recordBookmarkActivity();
    this.bumpBookmarkStatsVersion();
    return this.countDeletedRootIds(ids, deletingLookup);
  }

  private recordBookmarkActivity(): void {
    this.activityTracker?.recordBookmarkAction(Date.now());
  }

  private bumpBookmarkStatsVersion(): void {
    BookmarkStatsVersionSignal.bumpVersion();
  }

  private normalizeParentId(parentId?: string): string | undefined {
    if (parentId === undefined) {
      return undefined;
    }

    const parent = this.findNodeById(parentId);
    if (parent !== undefined && parent.type === 'folder' && !isBookmarkRootNodeId(parent.id)) {
      return parent.id;
    }
    if (parent !== undefined && parent.type === 'folder') {
      return parent.id;
    }
    return undefined;
  }

  private resolveNextPosition(parentId?: string): number {
    const siblings = this.listChildren(parentId, this.resolveParentScope(parentId));
    if (siblings.length === 0) {
      return 0;
    }

    return siblings[siblings.length - 1].position + 1;
  }

  private findNodeParentId(id: string): string | undefined {
    const node = this.findNodeById(id, true);
    return node ? node.parentId : undefined;
  }

  private resolveMovableNodes(nodeIds: string[]): BookmarkNode[] {
    const movingNodes: BookmarkNode[] = [];
    const movingLookup = new Set<string>();
    nodeIds.forEach((id: string) => {
      const node = this.findNodeById(id);
      if (node !== undefined && !movingLookup.has(node.id)) {
        movingLookup.add(node.id);
        movingNodes.push(node);
      }
    });
    return movingNodes;
  }

  private collectSourceParentKeys(movingNodes: BookmarkNode[], targetParentId?: string): string[] {
    const parentKeys: string[] = [];
    movingNodes.forEach((node: BookmarkNode) => {
      if (node.parentId === targetParentId) {
        return;
      }
      const parentKey = this.toParentKey(node.parentId);
      if (parentKeys.indexOf(parentKey) < 0) {
        parentKeys.push(parentKey);
      }
    });
    return parentKeys;
  }

  private collectAffectedParentIds(rootIds: string[], deletingLookup: Set<string>): string[] {
    const parentIds: string[] = [];
    rootIds.forEach((id: string) => {
      if (!deletingLookup.has(id)) {
        return;
      }
      const parentId = this.findNodeParentId(id);
      if (parentId !== undefined && deletingLookup.has(parentId)) {
        return;
      }
      const parentKey = this.toParentKey(parentId);
      if (parentIds.indexOf(parentKey) < 0) {
        parentIds.push(parentKey);
      }
    });
    return parentIds;
  }

  private buildRepositionedChildren(nodes: BookmarkNode[], parentKeys: string[], now: number): BookmarkNode[] {
    const repositioned: BookmarkNode[] = [];
    parentKeys.forEach((parentKey: string) => {
      const parentId = this.fromParentKey(parentKey);
      const siblings = nodes
        .filter((node: BookmarkNode) => node.sync.deletedAt === undefined && node.parentId === parentId)
        .sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
      siblings.forEach((node: BookmarkNode, index: number) => {
        if (node.position !== index) {
          repositioned.push(markBookmarkRepositioned(node, index, now));
        }
      });
    });
    return repositioned;
  }

  private buildCompactedChildren(nodes: BookmarkNode[], parentKeys: string[]): BookmarkNode[] {
    const uniqueParentKeys = new Set<string>();
    parentKeys.forEach((parentKey: string) => uniqueParentKeys.add(parentKey));
    const repositioned: BookmarkNode[] = [];
    uniqueParentKeys.forEach((parentKey: string) => {
      const siblings = nodes
        .filter((node: BookmarkNode) => node.sync.deletedAt === undefined && this.toParentKey(node.parentId) === parentKey)
        .sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
      siblings.forEach((node: BookmarkNode, index: number) => {
        if (node.position !== index) {
          repositioned.push(markBookmarkPositionCompacted(node, index));
        }
      });
    });
    return repositioned;
  }

  private countDeletedRootIds(rootIds: string[], deletingLookup: Set<string>): number {
    const countedIds: string[] = [];
    rootIds.forEach((id: string) => {
      if (deletingLookup.has(id) && countedIds.indexOf(id) < 0) {
        countedIds.push(id);
      }
    });
    return countedIds.length;
  }

  private buildBookmarkIdLookup(ids: string[]): Set<string> {
    const lookup = new Set<string>();
    ids.forEach((id: string) => {
      lookup.add(id);
    });
    return lookup;
  }

  private async renumberActiveChildren(parentId?: string): Promise<void> {
    const now = Date.now();
    const repositioned = this.listChildren(parentId, this.resolveParentScope(parentId)).map((node: BookmarkNode, index: number) => {
      return markBookmarkRepositioned(node, index, now);
    });
    await this.database.updateBookmarkPositions(repositioned);
    await this.refresh();
  }

  private fromParentKey(parentKey: string): string | undefined {
    return parentKey.length > 0 ? parentKey : undefined;
  }

  private async patchBookmarkNodeCacheAsync(nodes: BookmarkNode[]): Promise<void> {
    if (nodes.length === 0) {
      return;
    }
    this.fullIndexRefreshVersion += 1;
    this.fullIndexRefreshPromise = undefined;
    this.fullBookmarkIndexesReady = false;

    if (nodes.length >= BOOKMARK_CACHE_BULK_PATCH_THRESHOLD) {
      await this.patchBookmarkNodeCacheBatchAsync(nodes);
      this.bumpBookmarkChangeGeneration();
      this.scheduleFullBookmarkIndexRefresh();
      return;
    }

    const affectedParentKeys = new Set<string>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const previous = this.findNodeById(node.id, true);
      this.patchNodeCacheEntry(node);
      if (previous !== undefined) {
        affectedParentKeys.add(this.toParentKey(previous.parentId));
      }
      if (node.sync.deletedAt === undefined) {
        affectedParentKeys.add(this.toParentKey(node.parentId));
      }
      if ((index + 1) % BOOKMARK_INDEX_REBUILD_BATCH_SIZE === 0) {
        await pauseBookmarkIndexWork();
      }
    }
    if (affectedParentKeys.size > BOOKMARK_TREE_PATCH_PARENT_REBUILD_THRESHOLD) {
      await this.rebuildBookmarkTreeIndexesAsync();
    } else {
      this.rebuildBookmarkTreeIndexesFromPatch(affectedParentKeys);
    }
    this.bumpBookmarkChangeGeneration();
    this.scheduleFullBookmarkIndexRefresh();
  }

  private bumpBookmarkChangeGeneration(): void {
    this.bookmarkChangeGeneration += 1;
  }

  private async patchBookmarkNodeCacheBatchAsync(nodes: BookmarkNode[]): Promise<void> {
    const nextNodesCache = this.nodesCache.slice();
    const nodeIndexById = new Map<string, number>();
    for (let index = 0; index < nextNodesCache.length; index += 1) {
      nodeIndexById.set(nextNodesCache[index].id, index);
      if ((index + 1) % BOOKMARK_INDEX_REBUILD_BATCH_SIZE === 0) {
        await pauseBookmarkIndexWork();
      }
    }

    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const existingIndex = nodeIndexById.get(node.id);
      if (existingIndex === undefined) {
        nodeIndexById.set(node.id, nextNodesCache.length);
        nextNodesCache.push(node);
      } else {
        nextNodesCache[existingIndex] = node;
      }
      if ((index + 1) % BOOKMARK_INDEX_REBUILD_BATCH_SIZE === 0) {
        await pauseBookmarkIndexWork();
      }
    }

    const treeIndexes = await this.buildBookmarkTreeIndexCachesAsync(nextNodesCache);
    this.nodesCache = nextNodesCache;
    this.syncNodeByIdCache = treeIndexes.syncNodeByIdCache;
    this.activeNodeByIdCache = treeIndexes.activeNodeByIdCache;
    this.childrenByParentCache = treeIndexes.childrenByParentCache;
    this.activeNodesCache = treeIndexes.activeNodesCache;
  }

  private async upsertBookmarkNodesInDatabaseBatches(
    nodes: BookmarkNode[],
    batchSize: number,
    afterBatch?: (stats: BookmarkRepositoryDatabaseBatchStats) => Promise<void>
  ): Promise<void> {
    const resolvedBatchSize = Math.max(1, batchSize);
    let batchIndex = 0;
    for (let start = 0; start < nodes.length; start += resolvedBatchSize) {
      const batchStartedAt = Date.now();
      const batchNodes = nodes.slice(start, start + resolvedBatchSize);
      await this.database.upsertBookmarkNodes(batchNodes);
      const hasMore = start + resolvedBatchSize < nodes.length;
      if (afterBatch !== undefined) {
        await afterBatch({
          index: batchIndex,
          start: start,
          count: batchNodes.length,
          elapsedMs: Date.now() - batchStartedAt,
          hasMore: hasMore
        });
      }
      batchIndex += 1;
    }
  }

  private rebuildBookmarkIndexes(): void {
    this.rebuildBookmarkTreeIndexes();
    this.rebuildFullBookmarkIndexes();
  }

  private patchNodeCacheEntry(node: BookmarkNode): void {
    const existingIndex = this.nodesCache.findIndex((item: BookmarkNode) => item.id === node.id);
    if (existingIndex >= 0) {
      this.nodesCache[existingIndex] = node;
    } else {
      this.nodesCache.push(node);
    }

    const activeIndex = this.activeNodesCache.findIndex((item: BookmarkNode) => item.id === node.id);
    if (node.sync.deletedAt === undefined) {
      if (activeIndex >= 0) {
        this.activeNodesCache[activeIndex] = node;
      } else {
        this.activeNodesCache.push(node);
      }
      this.activeNodeByIdCache.set(node.id, node);
    } else {
      if (activeIndex >= 0) {
        this.activeNodesCache.splice(activeIndex, 1);
      }
      this.activeNodeByIdCache.delete(node.id);
    }
    this.syncNodeByIdCache.set(node.id, node);
  }

  private rebuildBookmarkTreeIndexesFromPatch(affectedParentKeys: Set<string>): void {
    affectedParentKeys.forEach((parentKey: string) => {
      const siblings = this.activeNodesCache
        .filter((node: BookmarkNode) => this.toParentKey(node.parentId) === parentKey)
        .slice()
        .sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
      this.childrenByParentCache.set(parentKey, siblings);
    });
  }

  private async rebuildBookmarkTreeIndexesAsync(): Promise<void> {
    this.fullIndexRefreshVersion += 1;
    this.fullIndexRefreshPromise = undefined;
    this.fullBookmarkIndexesReady = false;

    const treeIndexes = await this.buildBookmarkTreeIndexCachesAsync(this.nodesCache);
    this.syncNodeByIdCache = treeIndexes.syncNodeByIdCache;
    this.activeNodeByIdCache = treeIndexes.activeNodeByIdCache;
    this.childrenByParentCache = treeIndexes.childrenByParentCache;
    this.activeNodesCache = treeIndexes.activeNodesCache;
  }

  private async buildBookmarkTreeIndexCachesAsync(nodes: BookmarkNode[]): Promise<BookmarkTreeIndexCaches> {
    const syncNodeByIdCache = new Map<string, BookmarkNode>();
    const activeNodeByIdCache = new Map<string, BookmarkNode>();
    const childrenByParentCache = new Map<string, BookmarkNode[]>();
    const activeNodesCache: BookmarkNode[] = [];

    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      syncNodeByIdCache.set(node.id, node);
      if (node.sync.deletedAt !== undefined) {
        if ((index + 1) % BOOKMARK_INDEX_REBUILD_BATCH_SIZE === 0) {
          await pauseBookmarkIndexWork();
        }
        continue;
      }
      activeNodesCache.push(node);
      activeNodeByIdCache.set(node.id, node);
      const parentKey = this.toParentKey(node.parentId);
      const siblings = childrenByParentCache.get(parentKey) ?? [];
      siblings.push(node);
      childrenByParentCache.set(parentKey, siblings);
      if ((index + 1) % BOOKMARK_INDEX_REBUILD_BATCH_SIZE === 0) {
        await pauseBookmarkIndexWork();
      }
    }

    childrenByParentCache.forEach((siblings: BookmarkNode[]) => {
      siblings.sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
    });

    return {
      syncNodeByIdCache,
      activeNodeByIdCache,
      childrenByParentCache,
      activeNodesCache
    };
  }

  private rebuildBookmarkTreeIndexes(): void {
    this.fullIndexRefreshVersion += 1;
    this.fullIndexRefreshPromise = undefined;
    this.fullBookmarkIndexesReady = false;
    this.syncNodeByIdCache = new Map();
    this.activeNodeByIdCache = new Map();
    this.childrenByParentCache = new Map();
    this.activeNodesCache = [];
    this.nodesCache.forEach((node: BookmarkNode) => {
      this.syncNodeByIdCache.set(node.id, node);
      if (node.sync.deletedAt !== undefined) {
        return;
      }
      this.activeNodesCache.push(node);
      this.activeNodeByIdCache.set(node.id, node);
      const parentKey = this.toParentKey(node.parentId);
      const siblings = this.childrenByParentCache.get(parentKey) ?? [];
      siblings.push(node);
      this.childrenByParentCache.set(parentKey, siblings);
    });
    this.childrenByParentCache.forEach((siblings: BookmarkNode[]) => {
      siblings.sort((left: BookmarkNode, right: BookmarkNode) => left.position - right.position);
    });
  }

  private rebuildFullBookmarkIndexes(): void {
    this.bookmarkByScopedNormalizedUrlCache = new Map();
    this.suggestionCandidatesCache = [];
    this.collectActiveBookmarkNodes().forEach((node: BookmarkNode) => {
      if (isUserSearchableBookmark(node)) {
        this.suggestionCandidatesCache.push(node);
      }
      const identityKey = buildBookmarkUrlIdentityKey(node.url ?? '', resolveBookmarkScope(node.scope));
      if (!this.bookmarkByScopedNormalizedUrlCache.has(identityKey)) {
        this.bookmarkByScopedNormalizedUrlCache.set(identityKey, node);
      }
    });
    this.fullBookmarkIndexesReady = true;
  }

  private async rebuildFullBookmarkIndexesAsync(version: number): Promise<void> {
    const bookmarkByScopedNormalizedUrl = new Map<string, BookmarkNode>();
    const suggestionCandidates: BookmarkNode[] = [];
    for (let index = 0; index < this.activeNodesCache.length; index += 1) {
      const node = this.activeNodesCache[index];
      if (isUserSearchableBookmark(node)) {
        suggestionCandidates.push(node);
        const identityKey = buildBookmarkUrlIdentityKey(node.url ?? '', resolveBookmarkScope(node.scope));
        if (!bookmarkByScopedNormalizedUrl.has(identityKey)) {
          bookmarkByScopedNormalizedUrl.set(identityKey, node);
        }
      }
      if ((index + 1) % BOOKMARK_INDEX_REBUILD_BATCH_SIZE === 0) {
        await pauseBookmarkIndexWork();
      }
    }
    if (version !== this.fullIndexRefreshVersion) {
      return;
    }
    this.bookmarkByScopedNormalizedUrlCache = bookmarkByScopedNormalizedUrl;
    this.suggestionCandidatesCache = suggestionCandidates;
    this.fullBookmarkIndexesReady = true;
  }

  private async refreshFullBookmarkIndexesNow(): Promise<void> {
    const version = this.fullIndexRefreshVersion + 1;
    this.fullIndexRefreshVersion = version;
    this.fullIndexRefreshPromise = this.rebuildFullBookmarkIndexesAsync(version)
      .catch(() => undefined)
      .then(() => {
        if (version === this.fullIndexRefreshVersion) {
          this.fullIndexRefreshPromise = undefined;
        }
      });
    await this.fullIndexRefreshPromise;
  }

  private scheduleFullBookmarkIndexRefresh(): void {
    if (this.fullIndexRefreshPromise !== undefined) {
      return;
    }
    const version = this.fullIndexRefreshVersion + 1;
    this.fullIndexRefreshVersion = version;
    this.fullIndexRefreshPromise = this.rebuildFullBookmarkIndexesAsync(version)
      .catch(() => undefined)
      .then(() => {
        if (version === this.fullIndexRefreshVersion) {
          this.fullIndexRefreshPromise = undefined;
        }
      });
  }

  private ensureFullBookmarkIndexesInBackground(): void {
    if (!this.fullBookmarkIndexesReady && this.activeNodesCache.length > 0) {
      this.scheduleFullBookmarkIndexRefresh();
    }
  }

  private collectActiveBookmarkNodes(scope?: BookmarkStorageScope): BookmarkNode[] {
    return this.activeNodesCache.filter((node: BookmarkNode) => {
      return isUserSearchableBookmark(node) && (scope === undefined || this.matchesBookmarkScope(node, scope));
    });
  }

  private matchesBookmarkScope(node: BookmarkNode, scope: BookmarkStorageScope): boolean {
    return resolveBookmarkScope(node.scope) === resolveBookmarkScope(scope);
  }

  private resolveNodeScope(node: BookmarkNode | undefined): BookmarkStorageScope {
    return resolveBookmarkScope(node?.scope);
  }

  private resolveParentScope(parentId?: string): BookmarkStorageScope {
    if (parentId === undefined || parentId.length === 0) {
      return 'regular';
    }
    return this.resolveNodeScope(this.findNodeById(parentId, true));
  }

  private resolveCreateNodeScope(commandScope: BookmarkStorageScope | undefined, parentId?: string): BookmarkStorageScope {
    const parent = this.findNodeById(parentId ?? '', true);
    if (parent !== undefined && parent.type === 'folder') {
      return this.resolveNodeScope(parent);
    }
    return resolveBookmarkScope(commandScope);
  }

  private toParentKey(parentId?: string): string {
    return parentId ?? '';
  }
}

function buildSeedShortcutScenarios(): ShortcutScenarioRecord[] {
  const now = 1710000000000;
  return [
    {
      id: 'aira_default_scenario',
      name: '清风浏览器',
      color: '#3f7d5f',
      icon: 'sparkles',
      position: 0,
      archived: false,
      createdAt: now,
      updatedAt: now,
      sync: {
        state: 'local_only',
        source: 'seed',
        lastModifiedAt: now,
        lastModifiedBy: DEFAULT_ACTOR,
        deviceId: DEFAULT_DEVICE_ID,
        originId: 'aira_default_scenario'
      }
    }
  ];
}

function buildSeedShortcuts(): ShortcutRecord[] {
  const now = 1710000000000;
  return DEFAULT_BROWSER_SEED_SITES.map((site: BrowserDefaultSeedSite, index: number) => {
    return createSeedShortcut(
      `shortcut-seed-${site.idSuffix}`,
      site.title,
      site.url,
      '首页',
      index,
      now
    );
  });
}

function buildMissingSeedShortcuts(existingShortcuts: ShortcutRecord[]): ShortcutRecord[] {
  const seedShortcuts = buildSeedShortcuts();
  const existingIds = new Set<string>(existingShortcuts.map((shortcut: ShortcutRecord) => shortcut.id));
  let nextPosition = resolveNextSeedShortcutPosition(existingShortcuts);
  return seedShortcuts
    .filter((shortcut: ShortcutRecord) => !existingIds.has(shortcut.id))
    .map((shortcut: ShortcutRecord) => {
      const positioned = createSeedShortcut(
        shortcut.id,
        shortcut.title,
        shortcut.url,
        shortcut.folderName,
        nextPosition,
        shortcut.createdAt ?? 1710000000000
      );
      nextPosition += 1;
      return positioned;
    });
}

function resolveNextSeedShortcutPosition(existingShortcuts: ShortcutRecord[]): number {
  const activeDefaultShortcuts = existingShortcuts.filter((shortcut: ShortcutRecord) => {
    return shortcut.sync?.deletedAt === undefined &&
      isAiraOwnedShortcut(shortcut) &&
      (shortcut.scenarioId ?? 'aira_default_scenario') === 'aira_default_scenario';
  });
  if (activeDefaultShortcuts.length === 0) {
    return 0;
  }
  return Math.max(...activeDefaultShortcuts.map((shortcut: ShortcutRecord) => shortcut.position)) + 1;
}

function createSeedShortcut(
  id: string,
  title: string,
  url: string,
  folderName: string,
  position: number,
  now: number
): ShortcutRecord {
  return {
    id: id,
    scenarioId: 'aira_default_scenario',
    title: title,
    url: url,
    folderName: folderName,
    position: position,
    icon: '',
    description: folderName,
    useOfficialIcon: true,
    autoUseOfficialIcon: true,
    officialIconAvailableAtSave: false,
    officialIconColorOverride: false,
    iconRendering: 'official',
    iconColor: '',
    createdAt: now + position,
    updatedAt: now + position,
    sync: {
      state: 'local_only',
      source: 'seed',
      lastModifiedAt: now + position,
      lastModifiedBy: DEFAULT_ACTOR,
      deviceId: DEFAULT_DEVICE_ID,
      originId: id
    }
  };
}

function buildLocalShortcutRecord(command: CreateShortcutCommand, position: number): ShortcutRecord {
  const now = Date.now();
  const id = createLocalShortcutId();
  return {
    id: id,
    scenarioId: command.scenarioId ?? 'aira_default_scenario',
    kind: command.kind,
    title: sanitizeShortcutTitle(command.title, command.url),
    url: sanitizeBookmarkUrl(command.url),
    folderName: sanitizeShortcutFolderName(command.folderName),
    position: position,
    icon: (command.icon ?? '').trim(),
    description: sanitizeShortcutFolderName(command.folderName),
    useOfficialIcon: true,
    autoUseOfficialIcon: true,
    officialIconAvailableAtSave: false,
    officialIconColorOverride: false,
    iconRendering: 'official',
    iconColor: '',
    createdAt: now,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: now,
      lastModifiedBy: 'aira-shortcut-manager',
      deviceId: DEFAULT_DEVICE_ID,
      originId: id
    }
  };
}

function applyLocalShortcutUpdate(shortcut: ShortcutRecord, command: UpdateShortcutCommand): ShortcutRecord {
  const now = Date.now();
  const folderName = sanitizeShortcutFolderName(command.folderName);
  return {
    id: shortcut.id,
    scenarioId: shortcut.scenarioId,
    kind: shortcut.kind,
    title: sanitizeShortcutTitle(command.title, command.url),
    url: sanitizeBookmarkUrl(command.url),
    folderName: folderName,
    position: shortcut.position,
    icon: shortcut.icon,
    description: folderName,
    useOfficialIcon: shortcut.useOfficialIcon,
    autoUseOfficialIcon: shortcut.autoUseOfficialIcon,
    officialIconAvailableAtSave: shortcut.officialIconAvailableAtSave,
    officialIconColorOverride: shortcut.officialIconColorOverride,
    iconRendering: shortcut.iconRendering,
    iconColor: shortcut.iconColor,
    createdAt: shortcut.createdAt,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: now,
      lastModifiedBy: 'aira-shortcut-manager',
      deviceId: shortcut.sync?.deviceId ?? DEFAULT_DEVICE_ID,
      originId: shortcut.sync?.originId ?? shortcut.id
    }
  };
}

function normalizeShortcutTreeForLocalReplace(scenarioId: string, shortcuts: ShortcutRecord[]): ShortcutRecord[] {
  const now = Date.now();
  return flattenShortcutList(shortcuts).map((shortcut: ShortcutRecord, index: number) => {
    return normalizeShortcutForLocalReplace(shortcut, scenarioId, index, now);
  });
}

function normalizeShortcutForLocalReplace(
  shortcut: ShortcutRecord,
  scenarioId: string,
  position: number,
  now: number
): ShortcutRecord {
  return {
    id: shortcut.id,
    scenarioId: scenarioId,
    kind: shortcut.kind,
    title: shortcut.title,
    url: shortcut.url,
    folderName: '首页',
    position: position,
    icon: shortcut.icon,
    description: shortcut.description ?? '首页',
    useOfficialIcon: shortcut.useOfficialIcon,
    autoUseOfficialIcon: shortcut.autoUseOfficialIcon,
    officialIconAvailableAtSave: shortcut.officialIconAvailableAtSave,
    officialIconColorOverride: shortcut.officialIconColorOverride,
    iconRendering: shortcut.iconRendering,
    iconColor: shortcut.iconColor,
    createdAt: shortcut.createdAt ?? now,
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: now,
      lastModifiedBy: 'aira-shortcut-manager',
      deviceId: shortcut.sync?.deviceId ?? DEFAULT_DEVICE_ID,
      originId: shortcut.sync?.originId ?? shortcut.id
    }
  };
}

function cloneShortcutWithIcon(shortcut: ShortcutRecord, icon: string): ShortcutRecord {
  return {
    id: shortcut.id,
    scenarioId: shortcut.scenarioId,
    kind: shortcut.kind,
    title: shortcut.title,
    url: shortcut.url,
    folderName: shortcut.folderName,
    position: shortcut.position,
    icon: icon,
    description: shortcut.description,
    useOfficialIcon: shortcut.useOfficialIcon,
    autoUseOfficialIcon: shortcut.autoUseOfficialIcon,
    officialIconAvailableAtSave: shortcut.officialIconAvailableAtSave,
    officialIconColorOverride: shortcut.officialIconColorOverride,
    iconRendering: shortcut.iconRendering,
    iconColor: shortcut.iconColor,
    createdAt: shortcut.createdAt,
    updatedAt: shortcut.updatedAt,
    sync: shortcut.sync
  };
}

function flattenShortcutList(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
  return shortcuts.slice();
}

function isAiraOwnedShortcut(shortcut: ShortcutRecord): boolean {
  const source = shortcut.sync?.source;
  return source === undefined || source === 'seed' || source === 'local';
}

function isAiraOwnedShortcutScenario(scenario: ShortcutScenarioRecord): boolean {
  const source = scenario.sync.source;
  return source === 'seed' || source === 'local';
}

function markShortcutDeleted(shortcut: ShortcutRecord): ShortcutRecord {
  const now = Date.now();
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
    updatedAt: now,
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: now,
      lastModifiedBy: 'aira-shortcut-manager',
      deviceId: shortcut.sync?.deviceId ?? DEFAULT_DEVICE_ID,
      originId: shortcut.sync?.originId ?? shortcut.id,
      deletedAt: now
    }
  };
}

function resolveShortcutRecordModifiedAt(shortcut: ShortcutRecord): number {
  return Math.max(
    shortcut.sync?.deletedAt ?? 0,
    shortcut.sync?.lastModifiedAt ?? 0,
    shortcut.updatedAt ?? 0,
    shortcut.createdAt ?? 0
  );
}

function resolveShortcutBatchModifiedAt(shortcuts: ShortcutRecord[], fallback: number): number {
  if (shortcuts.length === 0) {
    return fallback;
  }
  return shortcuts.reduce((latest: number, shortcut: ShortcutRecord): number => {
    return Math.max(latest, resolveShortcutRecordModifiedAt(shortcut));
  }, fallback);
}

function markShortcutScenarioOrderChanged(
  scenario: ShortcutScenarioRecord,
  updatedAt: number
): ShortcutScenarioRecord {
  const nextUpdatedAt = Math.max(
    Math.floor(updatedAt),
    scenario.updatedAt + 1,
    scenario.sync.lastModifiedAt + 1
  );
  return {
    id: scenario.id,
    name: scenario.name,
    color: scenario.color,
    icon: scenario.icon,
    position: scenario.position,
    archived: scenario.archived,
    createdAt: scenario.createdAt,
    updatedAt: nextUpdatedAt,
    sync: {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: nextUpdatedAt,
      lastModifiedBy: 'aira-shortcut-manager',
      deviceId: scenario.sync.deviceId ?? DEFAULT_DEVICE_ID,
      originId: scenario.sync.originId ?? scenario.id
    }
  };
}

function createLocalShortcutId(): string {
  return `local-shortcut-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
}

function sanitizeShortcutTitle(title: string, url: string): string {
  const trimmed = title.trim();
  if (trimmed.length > 0) {
    return trimmed;
  }
  return sanitizeBookmarkUrl(url);
}

function sanitizeShortcutFolderName(folderName?: string): string {
  const trimmed = (folderName ?? '').trim();
  return trimmed.length > 0 ? trimmed : '首页';
}

export class RdbHistoryRepository implements HistoryRepository {
  private database: BrowserDatabase;
  private visitsCache: HistoryVisit[] = [];
  private initializationPromise?: Promise<void>;
  private readonly initialCacheLimit: number = 100;
  private syncContextProvider?: HistorySyncRepositoryContextProvider;
  private syncChangeHandler?: HistorySyncRepositoryChangeHandler;

  constructor(database: BrowserDatabase) {
    this.database = database;
  }

  setSyncContextProvider(provider: HistorySyncRepositoryContextProvider): void {
    this.syncContextProvider = provider;
  }

  setSyncChangeHandler(handler: HistorySyncRepositoryChangeHandler): void {
    this.syncChangeHandler = handler;
  }

  listVisits(limit?: number): HistoryVisit[] {
    if (limit !== undefined && limit > 0 && this.isVisitsCacheNewestFirst()) {
      return this.visitsCache.slice(0, Math.min(limit, this.visitsCache.length));
    }
    const visits = this.visitsCache
      .slice()
      .sort((left: HistoryVisit, right: HistoryVisit) => right.visitedAt - left.visitedAt);
    if (limit === undefined || limit >= visits.length) {
      return visits;
    }
    return visits.slice(0, limit);
  }

  private isVisitsCacheNewestFirst(): boolean {
    for (let index = 1; index < this.visitsCache.length; index += 1) {
      if (this.visitsCache[index - 1].visitedAt < this.visitsCache[index].visitedAt) {
        return false;
      }
    }
    return true;
  }

  async initialize(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.database.initialize()
        .then(() => this.refreshPreview(this.initialCacheLimit))
        .then(() => undefined)
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw new Error(`History repository initialization failed: ${JSON.stringify(error)}`);
        });
    }
    return this.initializationPromise;
  }

  async refreshPreview(limit: number): Promise<HistoryVisit[]> {
    const normalizedLimit = Math.max(1, Math.floor(limit));
    this.visitsCache = await this.database.listHistoryVisits(normalizedLimit);
    return this.listVisits();
  }

  async refreshPage(offset: number, limit: number): Promise<HistoryVisit[]> {
    const normalizedOffset = Math.max(0, Math.floor(offset));
    const normalizedLimit = Math.max(1, Math.floor(limit));
    const page = await this.database.listHistoryVisits(normalizedLimit, normalizedOffset);
    if (normalizedOffset === 0) {
      this.visitsCache = page;
    } else {
      this.visitsCache = this.mergeCachedVisits(page);
    }
    return page;
  }

  async refreshSearchPage(query: string, offset: number, limit: number): Promise<HistoryVisit[]> {
    const normalizedOffset = Math.max(0, Math.floor(offset));
    const normalizedLimit = Math.max(1, Math.floor(limit));
    return this.database.searchHistoryVisits(query, normalizedOffset, normalizedLimit);
  }

  async refreshSitePage(query: string, offset: number, limit: number): Promise<HistorySiteAggregate[]> {
    const normalizedOffset = Math.max(0, Math.floor(offset));
    const normalizedLimit = Math.max(1, Math.floor(limit));
    return this.database.listHistorySiteAggregates(query, normalizedOffset, normalizedLimit);
  }

  async refresh(): Promise<HistoryVisit[]> {
    this.visitsCache = await this.database.listHistoryVisits();
    return this.listVisits();
  }

  private mergeCachedVisits(page: HistoryVisit[]): HistoryVisit[] {
    const visitsById = new Map<string, HistoryVisit>();
    this.visitsCache.forEach((visit: HistoryVisit) => {
      visitsById.set(visit.id, visit);
    });
    page.forEach((visit: HistoryVisit) => {
      visitsById.set(visit.id, visit);
    });
    return Array.from(visitsById.values())
      .sort((left: HistoryVisit, right: HistoryVisit) => right.visitedAt - left.visitedAt);
  }

  async addVisit(command: CreateHistoryVisitCommand): Promise<HistoryVisit> {
    await this.initialize();
    const now = command.visitedAt ?? Date.now();
    const id = createLocalHistoryVisitId();
    const syncContext = this.resolveSyncContext('local_capture');
    const visit: HistoryVisit = {
      id: id,
      title: sanitizeHistoryTitle(command.title, command.url),
      url: sanitizeBookmarkUrl(command.url),
      visitedAt: now,
      dayBucketLabel: resolveHistoryDayBucketLabel(now),
      source: 'local',
      deviceId: syncContext?.clientId ?? DEFAULT_DEVICE_ID,
      sessionId: command.sessionId ?? 'local-browser-session',
      fromVisitId: command.fromVisitId,
      transition: command.transition ?? 'link',
      visitDurationMs: command.visitDurationMs ?? 0,
      profileId: command.profileId ?? 'profile-main',
      dataScope: command.dataScope ?? 'profile_persistent',
      syncId: syncContext === undefined ? undefined : `h1:${syncContext.clientId}:${id}`,
      syncAccountUid: syncContext?.accountUid,
      syncOrigin: syncContext === undefined ? undefined : 'local'
    };
    await this.database.upsertHistoryVisit(visit, syncContext);
    const refreshed = await this.database.listHistoryVisits(1);
    this.visitsCache = refreshed.concat(this.visitsCache.filter((item: HistoryVisit) => item.id !== visit.id));
    this.notifySyncChange(syncContext);
    return refreshed[0] ?? visit;
  }

  async deleteVisit(id: string, origin: HistorySyncMutationOrigin = 'user_deletion'): Promise<boolean> {
    await this.initialize();
    const syncContext = this.resolveSyncContext(origin);
    const deleted = await this.database.deleteHistoryVisit(id, syncContext);
    this.visitsCache = this.visitsCache.filter((visit: HistoryVisit) => visit.id !== id);
    if (deleted) {
      this.notifySyncChange(syncContext);
    }
    return deleted;
  }

  async deleteVisitsByIds(
    ids: string[],
    origin: HistorySyncMutationOrigin = 'user_deletion'
  ): Promise<number> {
    await this.initialize();
    const syncContext = this.resolveSyncContext(origin);
    const removed = await this.database.deleteHistoryVisitsByIds(ids, syncContext);
    if (removed > 0) {
      await this.refresh();
    }
    if (removed > 0) {
      this.notifySyncChange(syncContext);
    }
    return removed;
  }

  async deleteVisitsInRange(
    startAt: number,
    endAt: number,
    origin: HistorySyncMutationOrigin = 'user_deletion'
  ): Promise<number> {
    await this.initialize();
    const syncContext = this.resolveSyncContext(origin);
    const removed = await this.database.deleteHistoryVisitsInRange(startAt, endAt, syncContext);
    if (removed > 0) {
      await this.refresh();
    }
    if (removed > 0) {
      this.notifySyncChange(syncContext);
    }
    return removed;
  }

  async deleteVisitsByHost(
    host: string,
    origin: HistorySyncMutationOrigin = 'user_deletion'
  ): Promise<number> {
    await this.initialize();
    const syncContext = this.resolveSyncContext(origin);
    const removed = await this.database.deleteHistoryVisitsByHost(host, syncContext);
    if (removed > 0) {
      await this.refresh();
    }
    if (removed > 0) {
      this.notifySyncChange(syncContext);
    }
    return removed;
  }

  async clearVisits(origin: HistorySyncMutationOrigin = 'user_deletion'): Promise<number> {
    await this.initialize();
    const syncContext = this.resolveSyncContext(origin);
    const removed = await this.database.clearHistoryVisits(syncContext);
    this.visitsCache = [];
    this.notifySyncChange(syncContext);
    return removed;
  }

  async importVisits(visits: HistoryTransferVisit[]): Promise<number> {
    await this.initialize();
    let imported = 0;
    for (const visit of visits) {
      await this.addVisit({
        title: visit.title,
        url: visit.url,
        visitedAt: visit.visitedAt,
        sessionId: visit.sessionId,
        fromVisitId: visit.fromVisitId,
        transition: visit.transition,
        visitDurationMs: visit.visitDurationMs,
        profileId: visit.profileId,
        dataScope: visit.dataScope
      });
      imported += 1;
    }
    await this.refresh();
    return imported;
  }

  listSuggestions(limit?: number): HistoryVisit[] {
    const visits = this.visitsCache
      .slice()
      .sort((left: HistoryVisit, right: HistoryVisit) => {
        const leftScore = (left.visitCount ?? 1) * 12 + (left.typedCount ?? 0) * 24 +
          Math.floor((left.lastVisitAt ?? left.visitedAt) / 3600000);
        const rightScore = (right.visitCount ?? 1) * 12 + (right.typedCount ?? 0) * 24 +
          Math.floor((right.lastVisitAt ?? right.visitedAt) / 3600000);
        return rightScore - leftScore;
      });
    if (limit === undefined || limit >= visits.length) {
      return visits;
    }
    return visits.slice(0, limit);
  }

  listSuggestionCandidates(limit?: number): HistoryVisit[] {
    return this.listSuggestions(limit);
  }

  private resolveSyncContext(origin: HistorySyncMutationOrigin): HistorySyncOutboxContext | undefined {
    if (origin === 'retention' || this.syncContextProvider === undefined) {
      return undefined;
    }
    const context = this.syncContextProvider();
    if (!context.enabled || context.accountUid.trim().length <= 0 || context.clientId.trim().length <= 0) {
      return undefined;
    }
    return {
      accountUid: context.accountUid,
      clientId: context.clientId,
      deviceName: context.deviceName,
      origin: origin
    };
  }

  private notifySyncChange(context: HistorySyncOutboxContext | undefined): void {
    if (context === undefined || this.syncChangeHandler === undefined) {
      return;
    }
    this.syncChangeHandler();
  }
}

export class RdbTabSessionRepository implements TabSessionRepository {
  private database: BrowserDatabase;
  private tabsCache: TabRecord[] = [];
  private initializationPromise?: Promise<void>;

  constructor(database: BrowserDatabase) {
    this.database = database;
  }

  listTabs(windowId: string = 'window-main', profileId?: string): TabRecord[] {
    return this.tabsCache
      .filter((tab: TabRecord) => {
        if (tab.windowId !== windowId) {
          return false;
        }
        if (typeof profileId === 'string' && profileId.trim().length > 0) {
          return (tab.profileId ?? '').trim() === profileId.trim();
        }
        return true;
      })
      .slice()
      .sort((left: TabRecord, right: TabRecord) => compareTabSessionOrder(left, right));
  }

  async initialize(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.database.initialize()
        .then(() => this.refresh())
        .then(() => undefined)
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw new Error(`Tab session repository initialization failed: ${JSON.stringify(error)}`);
        });
    }
    return this.initializationPromise;
  }

  async refresh(windowId: string = 'window-main', profileId?: string): Promise<TabRecord[]> {
    const records = await this.database.listTabRecords(windowId, profileId);
    this.tabsCache = this.tabsCache.filter((tab: TabRecord) => {
      if (tab.windowId !== windowId) {
        return true;
      }
      if (typeof profileId === 'string' && profileId.trim().length > 0) {
        return (tab.profileId ?? '').trim() !== profileId.trim();
      }
      return false;
    }).concat(records);
    return this.listTabs(windowId, profileId);
  }

  async replaceTabs(
    tabs: TabRecord[],
    windowId: string = 'window-main',
    profileId?: string,
    options: TabSessionReplaceOptions = {}
  ): Promise<TabRecord[]> {
    await this.initialize();
    await this.database.replaceTabRecords(
      windowId,
      normalizeTabSessionOrder(filterPersistentTabSessionRecords(tabs, options)),
      profileId
    );
    await this.refresh(windowId, profileId);
    return this.listTabs(windowId, profileId);
  }
}

export class RdbRecentlyClosedTabRepository implements RecentlyClosedTabRepository {
  private database: BrowserDatabase;
  private tabManager: TabManager;
  private snapshotStore: RecentlyClosedTabSnapshotStore;
  private recordsCache: BrowserRecentlyClosedTabRecord[] = [];
  private initializationPromise?: Promise<void>;
  private replaceRecordsQueue: Promise<void> = Promise.resolve();

  constructor(
    database: BrowserDatabase,
    tabManager: TabManager = new TabManager(),
    snapshotStore: RecentlyClosedTabSnapshotStore = new RecentlyClosedTabSnapshotStore()
  ) {
    this.database = database;
    this.tabManager = tabManager;
    this.snapshotStore = snapshotStore;
  }

  listRecords(windowId: string = 'window-main', profileId?: string): BrowserRecentlyClosedTabRecord[] {
    return this.recordsCache
      .filter((record: BrowserRecentlyClosedTabRecord) => {
        if (record.windowId !== windowId) {
          return false;
        }
        if (typeof profileId === 'string' && profileId.trim().length > 0) {
          return record.tab.profileId === profileId.trim();
        }
        return true;
      })
      .slice()
      .sort((left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord) =>
        right.closedAt - left.closedAt);
  }

  async primeFromSnapshot(
    windowId: string = 'window-main',
    profileId?: string
  ): Promise<BrowserRecentlyClosedTabRecord[]> {
    const snapshotRecords = await this.snapshotStore.readRecords(windowId, profileId);
    const mappedRecords = this.fromPersistentRecords(snapshotRecords);
    this.replaceCacheBoundary(mappedRecords, windowId, profileId);
    return this.listRecords(windowId, profileId);
  }

  replaceCachedRecords(
    records: BrowserRecentlyClosedTabRecord[],
    windowId: string = 'window-main',
    profileId?: string
  ): BrowserRecentlyClosedTabRecord[] {
    this.replaceCacheBoundary(records, windowId, profileId);
    return this.listRecords(windowId, profileId);
  }

  async initialize(): Promise<void> {
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.database.initialize()
        .then(() => this.refreshFromDatabase())
        .then(() => undefined)
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw new Error(`Recently closed repository initialization failed: ${JSON.stringify(error)}`);
        });
    }
    return this.initializationPromise;
  }

  async refresh(windowId: string = 'window-main', profileId?: string): Promise<BrowserRecentlyClosedTabRecord[]> {
    await this.initialize();
    return this.refreshFromDatabase(windowId, profileId);
  }

  private async refreshFromDatabase(
    windowId: string = 'window-main',
    profileId?: string
  ): Promise<BrowserRecentlyClosedTabRecord[]> {
    const records = await this.database.listRecentlyClosedTabRecords(windowId, profileId);
    const mappedRecords = this.fromPersistentRecords(records);
    this.replaceCacheBoundary(mappedRecords, windowId, profileId);
    const latestRecords = this.listRecords(windowId, profileId);
    this.writeSnapshotSafely(latestRecords, windowId, profileId);
    return latestRecords;
  }

  async replaceRecords(
    records: BrowserRecentlyClosedTabRecord[],
    windowId: string = 'window-main',
    profileId?: string
  ): Promise<BrowserRecentlyClosedTabRecord[]> {
    await this.initialize();
    const persistentRecords = this.buildPersistentReplacementRecords(records, windowId, profileId);
    const operation = this.replaceRecordsQueue
      .catch((_error: Error) => undefined)
      .then(async (): Promise<BrowserRecentlyClosedTabRecord[]> => {
        await this.database.replaceRecentlyClosedTabRecords(windowId, persistentRecords, profileId);
        const latestRecords = await this.refresh(windowId, profileId);
        this.writeSnapshotSafely(latestRecords, windowId, profileId);
        return latestRecords;
      });
    this.replaceRecordsQueue = operation.then((): void => undefined, (): void => undefined);
    return operation;
  }

  async clearRecords(windowId: string = 'window-main', profileId?: string): Promise<number> {
    await this.initialize();
    const removed = await this.database.clearRecentlyClosedTabRecords(windowId, profileId);
    this.recordsCache = this.recordsCache.filter((record: BrowserRecentlyClosedTabRecord) => {
      if (record.windowId !== windowId) {
        return true;
      }
      if (typeof profileId === 'string' && profileId.trim().length > 0) {
        return record.tab.profileId !== profileId.trim();
      }
      return false;
    });
    this.clearSnapshotSafely(windowId, profileId);
    return removed;
  }

  async clearAllRecords(): Promise<number> {
    await this.initialize();
    const operation = this.replaceRecordsQueue
      .catch((_error: Error) => undefined)
      .then(async (): Promise<number> => {
        const removed = await this.database.clearAllRecentlyClosedTabRecords();
        this.recordsCache = [];
        await this.snapshotStore.clearAllRecords();
        return removed;
      });
    this.replaceRecordsQueue = operation.then((): void => undefined, (): void => undefined);
    return operation;
  }

  async deleteRecordsInRange(
    startAt: number,
    endAt: number,
    windowId: string = 'window-main',
    profileId?: string
  ): Promise<number> {
    await this.initialize();
    const normalizedStartAt = Math.max(0, Math.min(startAt, endAt));
    const normalizedEndAt = Math.max(normalizedStartAt, Math.max(startAt, endAt));
    const removed = await this.database.deleteRecentlyClosedTabRecordsInRange(
      normalizedStartAt,
      normalizedEndAt,
      windowId,
      profileId
    );
    if (removed > 0) {
      this.recordsCache = this.recordsCache.filter((record: BrowserRecentlyClosedTabRecord) => {
        if (record.windowId !== windowId) {
          return true;
        }
        if (typeof profileId === 'string' && profileId.trim().length > 0 && record.tab.profileId !== profileId.trim()) {
          return true;
        }
        return record.closedAt < normalizedStartAt || record.closedAt > normalizedEndAt;
      });
      this.writeSnapshotSafely(this.listRecords(windowId, profileId), windowId, profileId);
    }
    return removed;
  }

  private replaceCacheBoundary(
    records: BrowserRecentlyClosedTabRecord[],
    windowId: string,
    profileId?: string
  ): void {
    this.recordsCache = this.recordsCache.filter((record: BrowserRecentlyClosedTabRecord) => {
      if (record.windowId !== windowId) {
        return true;
      }
      if (typeof profileId === 'string' && profileId.trim().length > 0) {
        return record.tab.profileId !== profileId.trim();
      }
      return false;
    }).concat(records);
  }

  private buildPersistentReplacementRecords(
    records: BrowserRecentlyClosedTabRecord[],
    windowId: string,
    profileId?: string
  ): RecentlyClosedTabRecord[] {
    const normalizedProfileId = typeof profileId === 'string' ? profileId.trim() : '';
    const seenIds: string[] = [];
    return records
      .filter((record: BrowserRecentlyClosedTabRecord): boolean => record.windowId === windowId)
      .filter((record: BrowserRecentlyClosedTabRecord): boolean => {
        if (normalizedProfileId.length > 0) {
          return record.tab.profileId === normalizedProfileId;
        }
        return true;
      })
      .sort((left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord): number =>
        right.closedAt - left.closedAt)
      .filter((record: BrowserRecentlyClosedTabRecord): boolean => {
        const id = record.id.trim();
        if (id.length <= 0 || seenIds.indexOf(id) >= 0) {
          return false;
        }
        seenIds.push(id);
        return true;
      })
      .slice(0, DEFAULT_RECENTLY_CLOSED_PERSISTED_LIMIT)
      .map((record: BrowserRecentlyClosedTabRecord): RecentlyClosedTabRecord => this.toPersistentRecord(record));
  }

  private writeSnapshotSafely(
    records: BrowserRecentlyClosedTabRecord[],
    windowId: string,
    profileId?: string
  ): void {
    const persistentRecords = records.map((record: BrowserRecentlyClosedTabRecord): RecentlyClosedTabRecord =>
      this.toPersistentRecord(record));
    this.snapshotStore.writeRecords(persistentRecords, windowId, profileId)
      .catch((_error: Error) => {
      });
  }

  private clearSnapshotSafely(windowId: string, profileId?: string): void {
    this.snapshotStore.clearRecords(windowId, profileId)
      .catch((_error: Error) => {
      });
  }

  private toPersistentRecord(record: BrowserRecentlyClosedTabRecord): RecentlyClosedTabRecord {
    const tabRecord = this.tabManager.serializeTabs([record.tab], record.tab.id)[0];
    tabRecord.isActive = false;
    tabRecord.windowId = record.windowId;
    return {
      id: record.id,
      originalTabId: record.originalTabId,
      closedAt: record.closedAt,
      windowId: record.windowId,
      profileId: record.tab.profileId,
      siteIconUri: record.siteIconUri,
      tab: tabRecord
    };
  }

  private fromPersistentRecord(record: RecentlyClosedTabRecord): BrowserRecentlyClosedTabRecord | undefined {
    const restored = this.tabManager.restoreTabs([record.tab]);
    const tab = restored.activeTab;
    if (tab === undefined) {
      return undefined;
    }
    return {
      id: record.id,
      originalTabId: record.originalTabId,
      closedAt: record.closedAt,
      windowId: record.windowId,
      siteIconUri: record.siteIconUri,
      tab: tab
    };
  }

  private fromPersistentRecords(records: RecentlyClosedTabRecord[]): BrowserRecentlyClosedTabRecord[] {
    return records
      .map((record: RecentlyClosedTabRecord): BrowserRecentlyClosedTabRecord | undefined =>
        this.fromPersistentRecord(record))
      .filter((record: BrowserRecentlyClosedTabRecord | undefined): boolean => record !== undefined)
      .map((record: BrowserRecentlyClosedTabRecord | undefined): BrowserRecentlyClosedTabRecord =>
        record as BrowserRecentlyClosedTabRecord);
  }
}

function filterPersistentTabSessionRecords(
  tabs: TabRecord[],
  options: TabSessionReplaceOptions = {}
): TabRecord[] {
  return tabs.filter((tab: TabRecord) => {
    const shouldPersist = shouldPersistBrowserDataBoundaryTabLike({
      id: tab.id,
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    });
    const isSessionEphemeral = isBrowserDataBoundarySessionEphemeralTabLike({
      id: tab.id,
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    });
    return shouldPersist || options.allowPrivateTabs === true && isSessionEphemeral;
  });
}

function normalizeTabSessionOrder(tabs: TabRecord[]): TabRecord[] {
  const seenIds = new Set<string>();
  const uniqueTabs: TabRecord[] = [];
  tabs.forEach((tab: TabRecord) => {
    if (tab.id.length <= 0 || seenIds.has(tab.id)) {
      return;
    }
    seenIds.add(tab.id);
    uniqueTabs.push(tab);
  });
  return uniqueTabs.map((tab: TabRecord, index: number): TabRecord => {
    tab.tabOrder = index;
    return tab;
  });
}

function compareTabSessionOrder(left: TabRecord, right: TabRecord): number {
  const leftOrder = typeof left.tabOrder === 'number' ? left.tabOrder : Number.MAX_SAFE_INTEGER;
  const rightOrder = typeof right.tabOrder === 'number' ? right.tabOrder : Number.MAX_SAFE_INTEGER;
  if (leftOrder !== rightOrder) {
    return leftOrder - rightOrder;
  }
  return left.id.localeCompare(right.id);
}

function createLocalHistoryVisitId(): string {
  return `local-history-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
}

function sanitizeHistoryTitle(title: string, url: string): string {
  const trimmed = title.trim();
  if (trimmed.length > 0 && trimmed !== '页面加载中') {
    return trimmed;
  }
  return url.trim();
}

function resolveHistoryDayBucketLabel(visitedAt: number): string {
  const visitedDate = new Date(visitedAt);
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const visitedStart = new Date(visitedDate.getFullYear(), visitedDate.getMonth(), visitedDate.getDate()).getTime();
  const dayDiff = Math.floor((todayStart - visitedStart) / 86400000);
  if (dayDiff === 0) {
    return '今天';
  }
  if (dayDiff === 1) {
    return '昨天';
  }
  const month = `${visitedDate.getMonth() + 1}`.padStart(2, '0');
  const day = `${visitedDate.getDate()}`.padStart(2, '0');
  return `${visitedDate.getFullYear()}-${month}-${day}`;
}

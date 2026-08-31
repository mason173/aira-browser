import { BookmarkNode } from '../../common/models/BrowserModels';
import {
  AIRA_SYNC_DEFAULT_ROOT,
  AIRA_SYNC_ROOT_ORDER_KEY,
  AIRA_SYNC_SCHEMA_VERSION,
  AiraBookmarkSyncApplyResult,
  AiraBookmarkOverview,
  AiraSyncBookmarkDataSet,
  AiraSyncBookmarkFolderEntity,
  AiraSyncBookmarkItemEntity,
  AiraSyncBookmarkOrder,
  AiraSyncSnapshot,
  AiraSyncTombstone
} from '../../common/models/AiraSyncModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  BookmarkRepository,
  BookmarkRepositoryDatabaseBatchStats
} from '../../data/repositories/BrowserRepositories';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID,
  isBookmarkRootNodeId,
  resolveBookmarkScope
} from '../../data/repositories/BookmarkRepositoryCore';
import { AiraBookmarkSnapshotValidationService } from './AiraBookmarkSnapshotValidationService';
import { AiraSyncWorkThrottleService } from './AiraSyncWorkThrottleService';

const DEFAULT_DEVICE_ID = 'aira-browser-local';
const AIRA_TOOLBAR_ROOT_ID = 'browser_root_toolbar';
const AIRA_OTHER_ROOT_ID = 'browser_root_other';
const AIRA_PRIVATE_TOOLBAR_ROOT_ID = 'aira_private_root_toolbar';
const AIRA_PRIVATE_OTHER_ROOT_ID = 'aira_private_root_other';
const AIRA_CHROME_SYNC_ROOT_IDS: string[] = [
  AIRA_TOOLBAR_ROOT_ID,
  AIRA_OTHER_ROOT_ID
];
const LOCAL_CHROME_SYNC_ROOT_IDS: string[] = [
  BOOKMARK_TOOLBAR_ROOT_ID,
  BOOKMARK_OTHER_ROOT_ID
];
const AIRA_BOOKMARK_SYNC_SCOPE = 'regular';
const AIRA_PRIVATE_BOOKMARK_SYNC_SCOPE = 'private';
const AIRA_SYNC_LOCAL_DB_UPSERT_BATCH_SIZE: number = 1000;

interface AiraOrderIdsByParent {
  orderKey: string;
  ids: string[];
}

interface AiraEntityMetadata {
  createdAt: string;
  updatedAt: string;
  updatedBy: string;
  revision: number;
}

interface AiraBookmarkEntityIdPlan {
  idsByNodeId: Map<string, string>;
  parentEntityIdsByNodeId: Map<string, string | null>;
  occurrenceByNodeId: Map<string, number>;
  suppressedTombstoneNodeIds: Set<string>;
}

type AiraOrderPositionIndex = Map<string, Map<string, number>>;

export class AiraBookmarkSnapshotService {
  private bookmarkRepository: BookmarkRepository;
  private preferencesRepository: PreferencesRepository;
  private rootPath: string = AIRA_SYNC_DEFAULT_ROOT;
  private workThrottle: AiraSyncWorkThrottleService;
  private snapshotValidationService: AiraBookmarkSnapshotValidationService =
    new AiraBookmarkSnapshotValidationService();

  constructor(
    bookmarkRepository: BookmarkRepository,
    preferencesRepository: PreferencesRepository,
    workThrottle?: AiraSyncWorkThrottleService
  ) {
    this.bookmarkRepository = bookmarkRepository;
    this.preferencesRepository = preferencesRepository;
    this.workThrottle = workThrottle ?? new AiraSyncWorkThrottleService();
  }

  async buildFreshBookmarkSnapshot(
    deviceId: string = DEFAULT_DEVICE_ID,
    preferCurrentCache: boolean = false
  ): Promise<AiraSyncSnapshot> {
    await this.bookmarkRepository.initialize();
    if (!preferCurrentCache) {
      await this.bookmarkRepository.refresh();
    }
    const snapshot = await this.buildBookmarkSnapshotProgressively(deviceId);
    return this.snapshotValidationService.validate(snapshot, '本机');
  }

  validateBookmarkSnapshot(snapshot: AiraSyncSnapshot, sourceLabel: string): AiraSyncSnapshot {
    return this.snapshotValidationService.validate(snapshot, sourceLabel);
  }

  getLocalBookmarkSyncNodeCount(): number {
    return this.bookmarkRepository.listSyncNodes(AIRA_BOOKMARK_SYNC_SCOPE).length;
  }

  async purgeBookmarkTombstonesBefore(retainedFrom: string): Promise<number> {
    const retainedFromMs = Date.parse(retainedFrom);
    if (!Number.isFinite(retainedFromMs)) {
      throw new Error('书签墓碑保留边界无效。');
    }
    const regularCount = await this.bookmarkRepository.purgeDeletedSyncNodes('regular', retainedFromMs);
    const privateCount = await this.bookmarkRepository.purgeDeletedSyncNodes('private', retainedFromMs);
    return regularCount + privateCount;
  }

  buildBookmarkOverview(): AiraBookmarkOverview {
    const nodes = this.bookmarkRepository.listSyncNodes(AIRA_BOOKMARK_SYNC_SCOPE);
    const chromeSyncNodeIds = this.buildChromeSyncNodeIdSet(nodes);
    const activeNodes = this.filterReachableActiveNodes(nodes)
      .filter((node: BookmarkNode) => chromeSyncNodeIds.has(node.id));
    let folderCount = 0;
    let itemCount = 0;
    activeNodes.forEach((node: BookmarkNode) => {
      if (node.type === 'folder') {
        folderCount += 1;
      } else {
        itemCount += 1;
      }
    });

    return {
      bookmarkFolderCount: folderCount,
      bookmarkItemCount: itemCount
    };
  }

  async refreshBookmarkRepository(): Promise<void> {
    await this.bookmarkRepository.initialize();
    await this.bookmarkRepository.refresh();
  }

  async buildFreshBookmarkOverview(): Promise<AiraBookmarkOverview> {
    await this.refreshBookmarkRepository();
    return this.buildBookmarkOverview();
  }

  async applyBookmarkSnapshotToLocalDb(snapshot: AiraSyncSnapshot): Promise<AiraBookmarkSyncApplyResult> {
    this.snapshotValidationService.validate(snapshot, '合并结果');
    await this.bookmarkRepository.initialize();
    const regularResult = await this.applyBookmarkDataSetToLocalDb(
      {
        bookmarkFolders: snapshot.bookmarkFolders,
        bookmarkItems: snapshot.bookmarkItems,
        bookmarkOrders: snapshot.bookmarkOrders,
        tombstones: snapshot.tombstones
      },
      AIRA_BOOKMARK_SYNC_SCOPE,
      snapshot.meta.deviceId
    );
    const privateDataSet = this.normalizeBookmarkDataSet(snapshot.appPrivateBookmarks);
    const privateResult = await this.applyBookmarkDataSetToLocalDb(
      privateDataSet,
      AIRA_PRIVATE_BOOKMARK_SYNC_SCOPE,
      snapshot.meta.deviceId
    );
    const upsertedFolderCount = regularResult.upsertedFolderCount + privateResult.upsertedFolderCount;
    const upsertedBookmarkCount = regularResult.upsertedBookmarkCount + privateResult.upsertedBookmarkCount;
    const deletedNodeCount = regularResult.deletedNodeCount + privateResult.deletedNodeCount;
    const skippedNodeCount = regularResult.skippedNodeCount + privateResult.skippedNodeCount;
    return {
      upsertedFolderCount: upsertedFolderCount,
      upsertedBookmarkCount: upsertedBookmarkCount,
      deletedNodeCount: deletedNodeCount,
      skippedNodeCount: skippedNodeCount,
      blocked: regularResult.blocked || privateResult.blocked,
      summary: `已同步写入 ${upsertedFolderCount} 个文件夹、${upsertedBookmarkCount} 个书签，删除 ${deletedNodeCount} 个本地书签节点。`
    };
  }

  private async applyBookmarkDataSetToLocalDb(
    dataSet: AiraSyncBookmarkDataSet,
    scope: string,
    deviceId: string
  ): Promise<AiraBookmarkSyncApplyResult> {
    const activeLocalNodes = this.bookmarkRepository.listNodes(resolveBookmarkScope(scope));
    const activeLocalNodesById = this.buildBookmarkNodesById(activeLocalNodes);
    const existingLocalIdsByEntityId = await this.buildExistingLocalIdsByEntityIdAsync(activeLocalNodes);
    const deletedEntityIds = await this.buildDeletedBookmarkEntityIdSetAsync(dataSet.tombstones);
    const deletedLocalIds: string[] = [];
    const deletedLocalIdSet = new Set<string>();
    const deletedIds = Array.from(deletedEntityIds.values());
    for (let deletedIndex = 0; deletedIndex < deletedIds.length; deletedIndex += 1) {
      const id = deletedIds[deletedIndex];
      const localId = this.resolveLocalNodeIdForEntityId(id, existingLocalIdsByEntityId);
      if (!isBookmarkRootNodeId(localId) && activeLocalNodesById.has(localId) && !deletedLocalIdSet.has(localId)) {
        deletedLocalIdSet.add(localId);
        deletedLocalIds.push(localId);
      }
      await this.workThrottle.afterBatchItem(deletedIndex + 1);
    }

    const nodes = await this.buildSyncNodesFromDataSetAsync(dataSet, deletedEntityIds, existingLocalIdsByEntityId, scope, deviceId);
    this.assertCompleteDataSetProjection(dataSet, nodes, scope);
    const effectiveDeletedLocalIds = this.excludeProjectedLiveNodeIdsFromDeletion(deletedLocalIds, nodes);
    const liveNodes: BookmarkNode[] = [];
    let upsertedFolderCount = 0;
    let upsertedBookmarkCount = 0;
    let skippedNodeCount = 0;
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.sync.deletedAt !== undefined) {
        continue;
      }
      const existing = activeLocalNodesById.get(node.id);
      if (existing === undefined || !this.sameBookmarkNodeForSyncApply(existing, node)) {
        liveNodes.push(node);
        if (node.type === 'folder') {
          upsertedFolderCount += 1;
        } else {
          upsertedBookmarkCount += 1;
        }
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    if (liveNodes.length > 0) {
      await this.upsertSyncNodesWithCooperativeBatches(liveNodes);
    }

    let deletedNodeCount = 0;
    if (effectiveDeletedLocalIds.length > 0) {
      await this.workThrottle.beforeMainThreadWrite();
      try {
        deletedNodeCount = await this.bookmarkRepository.deleteNodes(effectiveDeletedLocalIds);
      } catch (error) {
        throw new Error(`本地书签删除未完成：${error instanceof Error ? error.message : JSON.stringify(error)}`);
      }
      if (deletedNodeCount !== effectiveDeletedLocalIds.length) {
        throw new Error(`本地书签删除未完成：计划删除 ${effectiveDeletedLocalIds.length} 项，实际删除 ${deletedNodeCount} 项。`);
      }
    }
    return {
      upsertedFolderCount: upsertedFolderCount,
      upsertedBookmarkCount: upsertedBookmarkCount,
      deletedNodeCount: deletedNodeCount,
      skippedNodeCount: skippedNodeCount,
      blocked: false,
      summary: `已同步写入 ${upsertedFolderCount} 个文件夹、${upsertedBookmarkCount} 个书签，删除 ${deletedNodeCount} 个本地书签节点。`
    };
  }

  private assertCompleteDataSetProjection(
    dataSet: AiraSyncBookmarkDataSet,
    nodes: BookmarkNode[],
    scope: string
  ): void {
    const expectedLiveNodeCount = dataSet.bookmarkFolders.length + dataSet.bookmarkItems.length;
    if (nodes.length !== expectedLiveNodeCount) {
      throw new Error(
        `本地书签投影不完整：${scope} 预期 ${expectedLiveNodeCount} 个存活节点，实际生成 ${nodes.length} 个。`
      );
    }
  }

  private excludeProjectedLiveNodeIdsFromDeletion(
    deletedLocalIds: string[],
    projectedLiveNodes: BookmarkNode[]
  ): string[] {
    const liveNodeIds = new Set<string>();
    for (let nodeIndex = 0; nodeIndex < projectedLiveNodes.length; nodeIndex += 1) {
      const node = projectedLiveNodes[nodeIndex];
      if (node.sync.deletedAt === undefined) {
        liveNodeIds.add(node.id);
      }
    }
    const effectiveDeletedLocalIds: string[] = [];
    for (let deleteIndex = 0; deleteIndex < deletedLocalIds.length; deleteIndex += 1) {
      const localId = deletedLocalIds[deleteIndex];
      if (!liveNodeIds.has(localId)) {
        effectiveDeletedLocalIds.push(localId);
      }
    }
    return effectiveDeletedLocalIds;
  }

  private async buildBookmarkSnapshotProgressively(
    deviceId: string = DEFAULT_DEVICE_ID
  ): Promise<AiraSyncSnapshot> {
    const generatedAt = new Date().toISOString();
    const regularDataSet = await this.buildBookmarkDataSetProgressively(
      AIRA_BOOKMARK_SYNC_SCOPE,
      LOCAL_CHROME_SYNC_ROOT_IDS,
      generatedAt,
      deviceId
    );
    const privateDataSet = await this.buildBookmarkDataSetProgressively(
      AIRA_PRIVATE_BOOKMARK_SYNC_SCOPE,
      [PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID, PRIVATE_BOOKMARK_OTHER_ROOT_ID],
      generatedAt,
      deviceId
    );

    return {
      meta: {
        version: AIRA_SYNC_SCHEMA_VERSION,
        deviceId: deviceId,
        generatedAt: generatedAt
      },
      bookmarkFolders: regularDataSet.bookmarkFolders,
      bookmarkItems: regularDataSet.bookmarkItems,
      bookmarkOrders: regularDataSet.bookmarkOrders,
      tombstones: regularDataSet.tombstones,
      appPrivateBookmarks: privateDataSet
    };
  }

  private async buildBookmarkDataSetProgressively(
    scope: string,
    rootIds: string[],
    generatedAt: string,
    deviceId: string
  ): Promise<AiraSyncBookmarkDataSet> {
    const nodes = this.bookmarkRepository.listSyncNodes(resolveBookmarkScope(scope));
    const syncNodeIds = await this.buildScopedSyncNodeIdSetAsync(nodes, rootIds);
    const reachableActiveNodes = await this.filterReachableActiveNodesAsync(nodes);
    const activeNodes = await this.filterNodesByIdSetAsync(reachableActiveNodes, syncNodeIds);
    const bookmarkFolders: AiraSyncBookmarkFolderEntity[] = [];
    const bookmarkItems: AiraSyncBookmarkItemEntity[] = [];
    const tombstones: AiraSyncTombstone[] = [];
    const sourceNodes = nodes;
    const entityIdPlan = await this.buildBookmarkEntityIdPlanAsync(sourceNodes, true);
    const orderIdsByParent = await this.buildOrderIdsByParentAsync(activeNodes, entityIdPlan);
    const nodesByEntityId = await this.buildNodesByPlannedEntityIdAsync(activeNodes, entityIdPlan);

    for (let index = 0; index < sourceNodes.length; index += 1) {
      const node = sourceNodes[index];
      if (syncNodeIds.has(node.id)) {
        this.appendBookmarkNodeEntity(
          node,
          entityIdPlan,
          bookmarkFolders,
          bookmarkItems,
          tombstones
        );
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }

    await this.workThrottle.afterStage();
    const bookmarkOrders: AiraSyncBookmarkOrder[] = [];
    for (let index = 0; index < orderIdsByParent.length; index += 1) {
      const entry = orderIdsByParent[index];
      bookmarkOrders.push(this.buildBookmarkOrderFromOrderEntry(
        entry,
        activeNodes,
        nodesByEntityId,
        generatedAt,
        deviceId
      ));
      await this.workThrottle.afterBatchItem(index + 1);
    }

    return {
      bookmarkFolders: bookmarkFolders,
      bookmarkItems: bookmarkItems,
      bookmarkOrders: bookmarkOrders,
      tombstones: this.canonicalizeTombstones(tombstones)
    };
  }

  private canonicalizeTombstones(tombstones: AiraSyncTombstone[]): AiraSyncTombstone[] {
    const latestByKey = new Map<string, AiraSyncTombstone>();
    tombstones.forEach((tombstone: AiraSyncTombstone): void => {
      const key = `${tombstone.type}|${tombstone.id}`;
      const current = latestByKey.get(key);
      if (current === undefined || this.isNewerTombstone(tombstone, current)) {
        latestByKey.set(key, tombstone);
      }
    });
    return Array.from(latestByKey.values());
  }

  private isNewerTombstone(candidate: AiraSyncTombstone, current: AiraSyncTombstone): boolean {
    const candidateDeletedAt = Date.parse(candidate.deletedAt);
    const currentDeletedAt = Date.parse(current.deletedAt);
    if (Number.isFinite(candidateDeletedAt) && Number.isFinite(currentDeletedAt) &&
      candidateDeletedAt !== currentDeletedAt) {
      return candidateDeletedAt > currentDeletedAt;
    }
    if (candidate.lastKnownRevision !== current.lastKnownRevision) {
      return candidate.lastKnownRevision > current.lastKnownRevision;
    }
    return candidate.deletedBy.localeCompare(current.deletedBy) > 0;
  }

  private normalizeBookmarkDataSet(value: AiraSyncBookmarkDataSet | undefined): AiraSyncBookmarkDataSet {
    if (value === undefined) {
      return {
        bookmarkFolders: [],
        bookmarkItems: [],
        bookmarkOrders: [],
        tombstones: []
      };
    }
    return {
      bookmarkFolders: value.bookmarkFolders ?? [],
      bookmarkItems: value.bookmarkItems ?? [],
      bookmarkOrders: value.bookmarkOrders ?? [],
      tombstones: value.tombstones ?? []
    };
  }

  private appendBookmarkNodeEntity(
    node: BookmarkNode,
    entityIdPlan: AiraBookmarkEntityIdPlan,
    bookmarkFolders: AiraSyncBookmarkFolderEntity[],
    bookmarkItems: AiraSyncBookmarkItemEntity[],
    tombstones: AiraSyncTombstone[]
  ): void {
    const entityMetadata = this.createEntityMetadata(node);
    const entityId = this.resolvePlannedEntityId(node, entityIdPlan);
    const parentId = this.resolvePlannedParentEntityId(node, entityIdPlan);
    if (node.sync.deletedAt !== undefined) {
      if (entityIdPlan.suppressedTombstoneNodeIds.has(node.id)) {
        return;
      }
      tombstones.push({
        id: entityId,
        type: node.type === 'folder' ? 'bookmark-folder' : 'bookmark-item',
        deletedAt: this.toIsoString(node.sync.deletedAt ?? node.updatedAt),
        deletedBy: node.sync.lastModifiedBy,
        lastKnownRevision: entityMetadata.revision
      });
      return;
    }
    if (node.type === 'folder') {
      bookmarkFolders.push({
        id: entityId,
        type: 'bookmark-folder',
        parentId: parentId,
        title: node.title,
        createdAt: entityMetadata.createdAt,
        updatedAt: entityMetadata.updatedAt,
        updatedBy: entityMetadata.updatedBy,
        revision: entityMetadata.revision
      });
      return;
    }
    bookmarkItems.push({
      id: entityId,
      type: 'bookmark-item',
      parentId: parentId,
      title: node.title,
      url: node.url || '',
      createdAt: entityMetadata.createdAt,
      updatedAt: entityMetadata.updatedAt,
      updatedBy: entityMetadata.updatedBy,
      revision: entityMetadata.revision
    });
  }

  private buildBookmarkOrderFromOrderEntry(
    entry: AiraOrderIdsByParent,
    activeNodes: BookmarkNode[],
    nodesByEntityId: Map<string, BookmarkNode>,
    generatedAt: string,
    deviceId: string
  ): AiraSyncBookmarkOrder {
    const revisionSeedNode = this.findOrderRevisionSeed(activeNodes, nodesByEntityId, entry.orderKey, entry.ids);
    return {
      type: 'bookmark-order',
      parentId: entry.orderKey === AIRA_SYNC_ROOT_ORDER_KEY ? null : entry.orderKey,
      ids: entry.ids,
      updatedAt: revisionSeedNode ? this.toIsoString(revisionSeedNode.updatedAt) : generatedAt,
      updatedBy: revisionSeedNode ? revisionSeedNode.sync.lastModifiedBy : deviceId,
      revision: revisionSeedNode ? this.deriveRevision(revisionSeedNode) : 1
    };
  }

  private async buildSyncNodesFromDataSetAsync(
    dataSet: AiraSyncBookmarkDataSet,
    deletedEntityIds: Set<string>,
    existingLocalIdsByEntityId: Map<string, string>,
    scope: string,
    deviceId: string
  ): Promise<BookmarkNode[]> {
    const normalizedScope = resolveBookmarkScope(scope);
    const nodes: BookmarkNode[] = [];
    const localIdsByEntityId = this.cloneEntityLocalIdMap(existingLocalIdsByEntityId);
    const orderPositionIndex = await this.buildOrderPositionIndexAsync(dataSet.bookmarkOrders);
    const reachableEntityIds = await this.buildReachableDataSetEntityIdSetAsync(dataSet, deletedEntityIds);
    for (let index = 0; index < dataSet.bookmarkFolders.length; index += 1) {
      const folder = dataSet.bookmarkFolders[index];
      const localId = this.resolveLocalNodeIdForEntityId(folder.id, localIdsByEntityId);
      localIdsByEntityId.set(folder.id, localId);
      if (!deletedEntityIds.has(folder.id) && reachableEntityIds.has(folder.id)) {
        nodes.push({
          id: localId,
          type: 'folder',
          scope: normalizedScope,
          parentId: this.toAiraParentId(folder.parentId, localIdsByEntityId),
          title: folder.title,
          position: this.resolvePositionFromIndex(orderPositionIndex, folder.parentId, folder.id),
          createdAt: this.toTimestamp(folder.createdAt),
          updatedAt: this.toTimestamp(folder.updatedAt),
          sync: {
            state: 'synced',
            source: 'cloud_sync',
            lastModifiedAt: this.toTimestamp(folder.updatedAt),
            lastModifiedBy: folder.updatedBy,
            deviceId: deviceId,
            originId: folder.id
          }
        });
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    await this.workThrottle.afterStage();
    for (let index = 0; index < dataSet.bookmarkItems.length; index += 1) {
      const item = dataSet.bookmarkItems[index];
      const localId = this.resolveLocalNodeIdForEntityId(item.id, localIdsByEntityId);
      localIdsByEntityId.set(item.id, localId);
      if (!deletedEntityIds.has(item.id) && reachableEntityIds.has(item.id)) {
        nodes.push({
          id: localId,
          type: 'bookmark',
          scope: normalizedScope,
          parentId: this.toAiraParentId(item.parentId, localIdsByEntityId),
          title: item.title,
          url: item.url,
          position: this.resolvePositionFromIndex(orderPositionIndex, item.parentId, item.id),
          createdAt: this.toTimestamp(item.createdAt),
          updatedAt: this.toTimestamp(item.updatedAt),
          sync: {
            state: 'synced',
            source: 'cloud_sync',
            lastModifiedAt: this.toTimestamp(item.updatedAt),
            lastModifiedBy: item.updatedBy,
            deviceId: deviceId,
            originId: item.id
          }
        });
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    await this.workThrottle.beforeMainThreadWrite();
    return nodes.sort((left: BookmarkNode, right: BookmarkNode) => {
      if (left.parentId === right.parentId) {
        return left.position - right.position;
      }
      return (left.parentId || '').localeCompare(right.parentId || '');
    });
  }

  private buildBookmarkNodesById(nodes: BookmarkNode[]): Map<string, BookmarkNode> {
    const result = new Map<string, BookmarkNode>();
    nodes.forEach((node: BookmarkNode) => {
      result.set(node.id, node);
    });
    return result;
  }

  private sameBookmarkNodeForSyncApply(left: BookmarkNode, right: BookmarkNode): boolean {
    const leftOriginId = left.sync.originId ?? '';
    const rightOriginId = right.sync.originId ?? '';
    return left.id === right.id &&
      left.type === right.type &&
      left.parentId === right.parentId &&
      left.title === right.title &&
      (left.url ?? '') === (right.url ?? '') &&
      left.position === right.position &&
      left.createdAt === right.createdAt &&
      left.updatedAt === right.updatedAt &&
      left.sync.state === right.sync.state &&
      left.sync.source === right.sync.source &&
      left.sync.lastModifiedAt === right.sync.lastModifiedAt &&
      left.sync.lastModifiedBy === right.sync.lastModifiedBy &&
      leftOriginId === rightOriginId &&
      left.sync.deletedAt === right.sync.deletedAt;
  }

  private async upsertSyncNodesWithCooperativeBatches(nodes: BookmarkNode[]): Promise<void> {
    if (nodes.length === 0) {
      return;
    }
    await this.workThrottle.beforeMainThreadWrite();
    await this.bookmarkRepository.upsertSyncNodes(nodes, {
      databaseBatchSize: AIRA_SYNC_LOCAL_DB_UPSERT_BATCH_SIZE,
      afterDatabaseBatch: async (stats: BookmarkRepositoryDatabaseBatchStats): Promise<void> => {
        if (stats.hasMore) {
          await this.workThrottle.afterStage();
          await this.workThrottle.beforeMainThreadWrite();
        }
      }
    });
    await this.workThrottle.afterStage();
  }

  private toAiraParentId(parentId: string | null, localIdsByEntityId: Map<string, string>): string | undefined {
    if (parentId === null) {
      return undefined;
    }
    return this.resolveLocalNodeIdForEntityId(parentId, localIdsByEntityId);
  }

  private async buildExistingLocalIdsByEntityIdAsync(nodes: BookmarkNode[]): Promise<Map<string, string>> {
    const result = new Map<string, string>();
    result.set(AIRA_TOOLBAR_ROOT_ID, BOOKMARK_TOOLBAR_ROOT_ID);
    result.set(AIRA_OTHER_ROOT_ID, BOOKMARK_OTHER_ROOT_ID);
    result.set(AIRA_PRIVATE_TOOLBAR_ROOT_ID, PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID);
    result.set(AIRA_PRIVATE_OTHER_ROOT_ID, PRIVATE_BOOKMARK_OTHER_ROOT_ID);
    const entityIdPlan = await this.buildBookmarkEntityIdPlanAsync(nodes);
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const entityId = this.resolvePlannedEntityId(node, entityIdPlan);
      if (!result.has(entityId)) {
        result.set(entityId, node.id);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const originId = node.sync.originId;
      if (originId !== undefined && originId.trim().length > 0 && !result.has(originId.trim())) {
        result.set(originId.trim(), node.id);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    return result;
  }

  private cloneEntityLocalIdMap(source: Map<string, string>): Map<string, string> {
    const result = new Map<string, string>();
    source.forEach((localId: string, entityId: string) => {
      result.set(entityId, localId);
    });
    return result;
  }

  private resolveLocalNodeIdForEntityId(entityId: string, localIdsByEntityId: Map<string, string>): string {
    const mapped = localIdsByEntityId.get(entityId);
    if (mapped !== undefined && mapped.length > 0) {
      return mapped;
    }
    return this.toAiraBookmarkNodeId(entityId);
  }

  private toAiraBookmarkNodeId(id: string): string {
    if (id === AIRA_TOOLBAR_ROOT_ID) {
      return BOOKMARK_TOOLBAR_ROOT_ID;
    }
    if (id === AIRA_OTHER_ROOT_ID) {
      return BOOKMARK_OTHER_ROOT_ID;
    }
    if (id === AIRA_PRIVATE_TOOLBAR_ROOT_ID) {
      return PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID;
    }
    if (id === AIRA_PRIVATE_OTHER_ROOT_ID) {
      return PRIVATE_BOOKMARK_OTHER_ROOT_ID;
    }
    return id;
  }

  private async buildDeletedBookmarkEntityIdSetAsync(tombstones: AiraSyncTombstone[]): Promise<Set<string>> {
    return this.buildDeletedTypedEntityIdSetAsync(tombstones, ['bookmark-folder', 'bookmark-item']);
  }

  private async buildDeletedTypedEntityIdSetAsync(
    tombstones: AiraSyncTombstone[],
    types: string[]
  ): Promise<Set<string>> {
    const deletedIdSet = new Set<string>();
    const typeSet = new Set<string>(types);
    for (let index = 0; index < tombstones.length; index += 1) {
      const entry = tombstones[index];
      if (typeSet.has(entry.type)) {
        deletedIdSet.add(entry.id);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    return deletedIdSet;
  }

  private resolveOrderKey(parentId: string | null): string {
    return parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : parentId;
  }

  private filterReachableActiveNodes(nodes: BookmarkNode[]): BookmarkNode[] {
    const nodesById = new Map<string, BookmarkNode>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    nodes.forEach((node: BookmarkNode) => {
      if (node.sync.deletedAt !== undefined) {
        return;
      }
      nodesById.set(node.id, node);
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
    });

    const reachableIds = new Set<string>();
    const roots = childrenByParent.get('') ?? [];
    roots.forEach((node: BookmarkNode) => {
      this.collectReachableActiveNodeIds(node.id, childrenByParent, reachableIds);
    });

    return nodes.filter((node: BookmarkNode) => {
      return node.sync.deletedAt === undefined && reachableIds.has(node.id) &&
        (node.parentId === undefined || nodesById.has(node.parentId));
    });
  }

  private async filterReachableActiveNodesAsync(nodes: BookmarkNode[]): Promise<BookmarkNode[]> {
    const nodesById = new Map<string, BookmarkNode>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.sync.deletedAt === undefined) {
        nodesById.set(node.id, node);
        const parentKey = node.parentId ?? '';
        const children = childrenByParent.get(parentKey) ?? [];
        children.push(node);
        childrenByParent.set(parentKey, children);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }

    const reachableIds = new Set<string>();
    const stack: string[] = [];
    const roots = childrenByParent.get('') ?? [];
    for (let index = 0; index < roots.length; index += 1) {
      stack.push(roots[index].id);
    }
    let processedCount = 0;
    while (stack.length > 0) {
      const nodeId = stack.pop() ?? '';
      if (nodeId.length === 0 || reachableIds.has(nodeId)) {
        continue;
      }
      reachableIds.add(nodeId);
      const children = childrenByParent.get(nodeId) ?? [];
      for (let index = 0; index < children.length; index += 1) {
        stack.push(children[index].id);
      }
      processedCount += 1;
      await this.workThrottle.afterBatchItem(processedCount);
    }

    const result: BookmarkNode[] = [];
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.sync.deletedAt === undefined && reachableIds.has(node.id) &&
        (node.parentId === undefined || nodesById.has(node.parentId))) {
        result.push(node);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    return result;
  }

  private async filterNodesByIdSetAsync(nodes: BookmarkNode[], includedIds: Set<string>): Promise<BookmarkNode[]> {
    const result: BookmarkNode[] = [];
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (includedIds.has(node.id)) {
        result.push(node);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    return result;
  }

  private buildScopedSyncNodeIdSet(nodes: BookmarkNode[], rootIds: string[]): Set<string> {
    const includedIds = new Set<string>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    nodes.forEach((node: BookmarkNode) => {
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
    });
    rootIds.forEach((rootId: string) => {
      this.collectChromeSyncNodeIds(rootId, childrenByParent, includedIds);
    });
    return includedIds;
  }

  private async buildScopedSyncNodeIdSetAsync(nodes: BookmarkNode[], rootIds: string[]): Promise<Set<string>> {
    const includedIds = new Set<string>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const parentKey = node.parentId ?? '';
      const children = childrenByParent.get(parentKey) ?? [];
      children.push(node);
      childrenByParent.set(parentKey, children);
      await this.workThrottle.afterBatchItem(index + 1);
    }
    const stack: string[] = rootIds.slice();
    let processedCount = 0;
    while (stack.length > 0) {
      const nodeId = stack.pop() ?? '';
      if (nodeId.length === 0 || includedIds.has(nodeId)) {
        continue;
      }
      includedIds.add(nodeId);
      const children = childrenByParent.get(nodeId) ?? [];
      for (let index = 0; index < children.length; index += 1) {
        stack.push(children[index].id);
      }
      processedCount += 1;
      await this.workThrottle.afterBatchItem(processedCount);
    }
    return includedIds;
  }

  private buildChromeSyncNodeIdSet(nodes: BookmarkNode[]): Set<string> {
    return this.buildScopedSyncNodeIdSet(nodes, LOCAL_CHROME_SYNC_ROOT_IDS);
  }

  private collectChromeSyncNodeIds(
    nodeId: string,
    childrenByParent: Map<string, BookmarkNode[]>,
    includedIds: Set<string>
  ): void {
    if (includedIds.has(nodeId)) {
      return;
    }
    includedIds.add(nodeId);
    const children = childrenByParent.get(nodeId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.collectChromeSyncNodeIds(child.id, childrenByParent, includedIds);
    });
  }

  private collectReachableActiveNodeIds(
    nodeId: string,
    childrenByParent: Map<string, BookmarkNode[]>,
    reachableIds: Set<string>
  ): void {
    if (reachableIds.has(nodeId)) {
      return;
    }
    reachableIds.add(nodeId);
    const children = childrenByParent.get(nodeId) ?? [];
    children.forEach((child: BookmarkNode) => {
      this.collectReachableActiveNodeIds(child.id, childrenByParent, reachableIds);
    });
  }

  private async buildReachableDataSetEntityIdSetAsync(
    dataSet: AiraSyncBookmarkDataSet,
    deletedEntityIds: Set<string>
  ): Promise<Set<string>> {
    const foldersById = new Map<string, AiraSyncBookmarkFolderEntity>();
    for (let index = 0; index < dataSet.bookmarkFolders.length; index += 1) {
      const folder = dataSet.bookmarkFolders[index];
      if (!deletedEntityIds.has(folder.id)) {
        foldersById.set(folder.id, folder);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    const itemsById = new Map<string, AiraSyncBookmarkItemEntity>();
    for (let index = 0; index < dataSet.bookmarkItems.length; index += 1) {
      const item = dataSet.bookmarkItems[index];
      if (!deletedEntityIds.has(item.id)) {
        itemsById.set(item.id, item);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    const ordersByParent = new Map<string, string[]>();
    for (let index = 0; index < dataSet.bookmarkOrders.length; index += 1) {
      const order = dataSet.bookmarkOrders[index];
      ordersByParent.set(this.resolveOrderKey(order.parentId), order.ids.slice());
      await this.workThrottle.afterBatchItem(index + 1);
    }

    const reachableIds = new Set<string>();
    const parentStack: string[] = [AIRA_SYNC_ROOT_ORDER_KEY];
    let processedCount = 0;
    while (parentStack.length > 0) {
      const parentKey = parentStack.pop() ?? '';
      const ids = ordersByParent.get(parentKey) ?? [];
      for (let index = 0; index < ids.length; index += 1) {
        const id = ids[index];
        if (reachableIds.has(id)) {
          continue;
        }
        if (foldersById.has(id)) {
          reachableIds.add(id);
          parentStack.push(id);
        } else if (itemsById.has(id)) {
          reachableIds.add(id);
        }
        processedCount += 1;
        await this.workThrottle.afterBatchItem(processedCount);
      }
    }
    return reachableIds;
  }

  private async buildOrderIdsByParentAsync(
    nodes: BookmarkNode[],
    entityIdPlan: AiraBookmarkEntityIdPlan
  ): Promise<AiraOrderIdsByParent[]> {
    const nodesByOrderKey = new Map<string, BookmarkNode[]>();
    nodesByOrderKey.set(AIRA_SYNC_ROOT_ORDER_KEY, []);
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const parentId = this.resolvePlannedParentEntityId(node, entityIdPlan);
      const orderKey = parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : parentId;
      const siblings = nodesByOrderKey.get(orderKey) ?? [];
      siblings.push(node);
      nodesByOrderKey.set(orderKey, siblings);
      await this.workThrottle.afterBatchItem(index + 1);
    }

    const result: AiraOrderIdsByParent[] = [];
    const entries = Array.from(nodesByOrderKey.entries());
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex += 1) {
      const orderKey = entries[entryIndex][0];
      const siblings = entries[entryIndex][1].slice().sort((left: BookmarkNode, right: BookmarkNode) => {
        return left.position - right.position;
      });
      const ids: string[] = [];
      for (let index = 0; index < siblings.length; index += 1) {
        ids.push(this.resolvePlannedEntityId(siblings[index], entityIdPlan));
        await this.workThrottle.afterBatchItem(index + 1);
      }
      result.push({
        orderKey: orderKey,
        ids: ids
      });
      await this.workThrottle.afterBatchItem(entryIndex + 1);
    }
    return result;
  }

  private createEntityMetadata(node: BookmarkNode): AiraEntityMetadata {
    return {
      createdAt: this.toIsoString(node.createdAt),
      updatedAt: this.toIsoString(node.updatedAt),
      updatedBy: node.sync.lastModifiedBy,
      revision: this.deriveRevision(node)
    };
  }

  private deriveRevision(node: BookmarkNode): number {
    const syncFactor = node.sync.state === 'synced' ? 2 : node.sync.state === 'conflict' ? 3 : 1;
    return Math.max(1, syncFactor);
  }

  private normalizeParentId(node: BookmarkNode): string | null {
    if (node.parentId !== undefined) {
      return this.toAiraBookmarkEntityId(node.parentId);
    }
    if (node.id === BOOKMARK_TOOLBAR_ROOT_ID || node.id === BOOKMARK_OTHER_ROOT_ID) {
      return null;
    }
    if (node.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || node.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
      return null;
    }
    if (resolveBookmarkScope(node.scope) === 'private') {
      return AIRA_PRIVATE_OTHER_ROOT_ID;
    }
    return AIRA_OTHER_ROOT_ID;
  }

  private toAiraBookmarkEntityId(id: string): string {
    if (id === BOOKMARK_TOOLBAR_ROOT_ID) {
      return AIRA_TOOLBAR_ROOT_ID;
    }
    if (id === BOOKMARK_OTHER_ROOT_ID) {
      return AIRA_OTHER_ROOT_ID;
    }
    if (id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID) {
      return AIRA_PRIVATE_TOOLBAR_ROOT_ID;
    }
    if (id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
      return AIRA_PRIVATE_OTHER_ROOT_ID;
    }
    return id;
  }

  private async buildBookmarkEntityIdPlanAsync(
    nodes: BookmarkNode[],
    reuseExistingOriginId: boolean = true
  ): Promise<AiraBookmarkEntityIdPlan> {
    const idsByNodeId = new Map<string, string>();
    const parentEntityIdsByNodeId = new Map<string, string | null>();
    const occurrenceByNodeId = await this.buildBookmarkEntityOccurrenceByNodeIdAsync(nodes);
    const nodesById = new Map<string, BookmarkNode>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      nodesById.set(node.id, node);
      await this.workThrottle.afterBatchItem(index + 1);
    }
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      this.resolveBookmarkEntityIdForNode(
        node,
        nodesById,
        idsByNodeId,
        parentEntityIdsByNodeId,
        occurrenceByNodeId,
        reuseExistingOriginId
      );
      await this.workThrottle.afterBatchItem(index + 1);
    }
    const suppressedTombstoneNodeIds = await this.resolveBookmarkEntityIdCollisionsAsync(nodes, idsByNodeId);
    await this.refreshPlannedParentEntityIdsAsync(nodes, idsByNodeId, parentEntityIdsByNodeId);
    return {
      idsByNodeId: idsByNodeId,
      parentEntityIdsByNodeId: parentEntityIdsByNodeId,
      occurrenceByNodeId: occurrenceByNodeId,
      suppressedTombstoneNodeIds: suppressedTombstoneNodeIds
    };
  }

  private async resolveBookmarkEntityIdCollisionsAsync(
    nodes: BookmarkNode[],
    idsByNodeId: Map<string, string>
  ): Promise<Set<string>> {
    const nodesByEntityId = new Map<string, BookmarkNode[]>();
    const reservedIds = new Set<string>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const entityId = idsByNodeId.get(node.id) ?? this.toAiraBookmarkEntityId(node.id);
      const collisions = nodesByEntityId.get(entityId) ?? [];
      collisions.push(node);
      nodesByEntityId.set(entityId, collisions);
      reservedIds.add(entityId);
      await this.workThrottle.afterBatchItem(index + 1);
    }

    const suppressedTombstoneNodeIds = new Set<string>();
    const entries = Array.from(nodesByEntityId.entries());
    for (let entryIndex = 0; entryIndex < entries.length; entryIndex += 1) {
      const entityId = entries[entryIndex][0];
      const collisionNodes = entries[entryIndex][1];
      if (collisionNodes.length <= 1) {
        await this.workThrottle.afterBatchItem(entryIndex + 1);
        continue;
      }
      const liveNodes = collisionNodes
        .filter((node: BookmarkNode): boolean => node.sync.deletedAt === undefined)
        .sort((left: BookmarkNode, right: BookmarkNode): number => {
          return this.compareBookmarkEntityCollisionOwner(left, right, entityId);
        });
      if (liveNodes.length <= 0) {
        await this.workThrottle.afterBatchItem(entryIndex + 1);
        continue;
      }

      collisionNodes.forEach((node: BookmarkNode): void => {
        if (node.sync.deletedAt !== undefined) {
          suppressedTombstoneNodeIds.add(node.id);
        }
      });
      for (let liveIndex = 1; liveIndex < liveNodes.length; liveIndex += 1) {
        const node = liveNodes[liveIndex];
        idsByNodeId.set(node.id, this.createBookmarkEntityCollisionId(node, entityId, reservedIds));
        await this.workThrottle.afterBatchItem(liveIndex + 1);
      }
      await this.workThrottle.afterBatchItem(entryIndex + 1);
    }
    return suppressedTombstoneNodeIds;
  }

  private compareBookmarkEntityCollisionOwner(
    left: BookmarkNode,
    right: BookmarkNode,
    entityId: string
  ): number {
    const leftOwnsCanonicalRoot = isBookmarkRootNodeId(left.id) &&
      this.toAiraBookmarkEntityId(left.id) === entityId;
    const rightOwnsCanonicalRoot = isBookmarkRootNodeId(right.id) &&
      this.toAiraBookmarkEntityId(right.id) === entityId;
    if (leftOwnsCanonicalRoot !== rightOwnsCanonicalRoot) {
      return leftOwnsCanonicalRoot ? -1 : 1;
    }
    const leftOwnsOrigin = (left.sync.originId ?? '').trim() === entityId;
    const rightOwnsOrigin = (right.sync.originId ?? '').trim() === entityId;
    if (leftOwnsOrigin !== rightOwnsOrigin) {
      return leftOwnsOrigin ? -1 : 1;
    }
    if (left.updatedAt !== right.updatedAt) {
      return right.updatedAt - left.updatedAt;
    }
    return left.id.localeCompare(right.id);
  }

  private createBookmarkEntityCollisionId(
    node: BookmarkNode,
    entityId: string,
    reservedIds: Set<string>
  ): string {
    const prefix = node.type === 'folder' ? 'bkf_local_collision' : 'bkm_local_collision';
    const base = `${prefix}_${this.shortHash(`${entityId}|${node.type}|${node.id}`)}`;
    let candidate = base;
    let suffix = 1;
    while (reservedIds.has(candidate)) {
      candidate = `${base}_${suffix}`;
      suffix += 1;
    }
    reservedIds.add(candidate);
    return candidate;
  }

  private async refreshPlannedParentEntityIdsAsync(
    nodes: BookmarkNode[],
    idsByNodeId: Map<string, string>,
    parentEntityIdsByNodeId: Map<string, string | null>
  ): Promise<void> {
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      if (node.parentId !== undefined) {
        parentEntityIdsByNodeId.set(
          node.id,
          idsByNodeId.get(node.parentId) ?? this.toAiraBookmarkEntityId(node.parentId)
        );
      } else if (node.id === BOOKMARK_TOOLBAR_ROOT_ID || node.id === BOOKMARK_OTHER_ROOT_ID ||
        node.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || node.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
        parentEntityIdsByNodeId.set(node.id, null);
      } else {
        parentEntityIdsByNodeId.set(
          node.id,
          resolveBookmarkScope(node.scope) === 'private' ? AIRA_PRIVATE_OTHER_ROOT_ID : AIRA_OTHER_ROOT_ID
        );
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
  }

  private resolveBookmarkParentEntityId(
    node: BookmarkNode,
    nodesById: Map<string, BookmarkNode>,
    idsByNodeId: Map<string, string>,
    parentEntityIdsByNodeId: Map<string, string | null>,
    occurrenceByNodeId: Map<string, number>,
    reuseExistingOriginId: boolean
  ): string | null {
    if (node.parentId !== undefined) {
      const parentNode = nodesById.get(node.parentId);
      if (parentNode !== undefined) {
        return this.resolveBookmarkEntityIdForNode(
          parentNode,
          nodesById,
          idsByNodeId,
          parentEntityIdsByNodeId,
          occurrenceByNodeId,
          reuseExistingOriginId
        );
      }
      return this.toAiraBookmarkEntityId(node.parentId);
    }
    if (node.id === BOOKMARK_TOOLBAR_ROOT_ID || node.id === BOOKMARK_OTHER_ROOT_ID ||
      node.id === PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID || node.id === PRIVATE_BOOKMARK_OTHER_ROOT_ID) {
      return null;
    }
    if (resolveBookmarkScope(node.scope) === 'private') {
      return AIRA_PRIVATE_OTHER_ROOT_ID;
    }
    return AIRA_OTHER_ROOT_ID;
  }

  private resolveBookmarkEntityIdForNode(
    node: BookmarkNode,
    nodesById: Map<string, BookmarkNode>,
    idsByNodeId: Map<string, string>,
    parentEntityIdsByNodeId: Map<string, string | null>,
    occurrenceByNodeId: Map<string, number>,
    reuseExistingOriginId: boolean
  ): string {
    const existing = idsByNodeId.get(node.id);
    if (existing !== undefined) {
      return existing;
    }
    const parentEntityId = this.resolveBookmarkParentEntityId(
      node,
      nodesById,
      idsByNodeId,
      parentEntityIdsByNodeId,
      occurrenceByNodeId,
      reuseExistingOriginId
    );
    parentEntityIdsByNodeId.set(node.id, parentEntityId);
    const entityId = this.createBookmarkEntityId(
      node,
      parentEntityId,
      occurrenceByNodeId.get(node.id) ?? 1,
      reuseExistingOriginId
    );
    idsByNodeId.set(node.id, entityId);
    return entityId;
  }

  private createBookmarkEntityId(
    node: BookmarkNode,
    parentEntityId: string | null,
    occurrence: number,
    reuseExistingOriginId: boolean
  ): string {
    const rootEntityId = this.toAiraBookmarkEntityId(node.id);
    if (rootEntityId === AIRA_TOOLBAR_ROOT_ID || rootEntityId === AIRA_OTHER_ROOT_ID ||
      rootEntityId === AIRA_PRIVATE_TOOLBAR_ROOT_ID || rootEntityId === AIRA_PRIVATE_OTHER_ROOT_ID) {
      return rootEntityId;
    }
    if (reuseExistingOriginId) {
      const existingOriginId = node.sync.originId;
      if (existingOriginId !== undefined && existingOriginId.trim().length > 0 &&
        !this.isCanonicalBookmarkRootEntityId(existingOriginId.trim())) {
        return existingOriginId.trim();
      }
    }
    if (node.type === 'folder') {
      return this.createFolderEntityId(parentEntityId, node.title, occurrence);
    }
    return this.createItemEntityId(parentEntityId, node.title, node.url ?? '', occurrence);
  }

  private isCanonicalBookmarkRootEntityId(id: string): boolean {
    return id === AIRA_TOOLBAR_ROOT_ID || id === AIRA_OTHER_ROOT_ID ||
      id === AIRA_PRIVATE_TOOLBAR_ROOT_ID || id === AIRA_PRIVATE_OTHER_ROOT_ID;
  }

  private async buildBookmarkEntityOccurrenceByNodeIdAsync(nodes: BookmarkNode[]): Promise<Map<string, number>> {
    const occurrenceByNodeId = new Map<string, number>();
    const childrenByParent = new Map<string, BookmarkNode[]>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const parentKey = node.parentId ?? '';
      const siblings = childrenByParent.get(parentKey) ?? [];
      siblings.push(node);
      childrenByParent.set(parentKey, siblings);
      await this.workThrottle.afterBatchItem(index + 1);
    }
    const siblingGroups = Array.from(childrenByParent.values());
    for (let groupIndex = 0; groupIndex < siblingGroups.length; groupIndex += 1) {
      const siblings = siblingGroups[groupIndex].slice().sort((left: BookmarkNode, right: BookmarkNode) => {
        return left.position - right.position;
      });
      const occurrenceBySignature = new Map<string, number>();
      for (let index = 0; index < siblings.length; index += 1) {
        const node = siblings[index];
        const signature = this.buildBookmarkEntityOccurrenceSignature(node);
        const occurrence = (occurrenceBySignature.get(signature) ?? 0) + 1;
        occurrenceBySignature.set(signature, occurrence);
        occurrenceByNodeId.set(node.id, occurrence);
        await this.workThrottle.afterBatchItem(index + 1);
      }
      await this.workThrottle.afterBatchItem(groupIndex + 1);
    }
    return occurrenceByNodeId;
  }

  private buildBookmarkEntityOccurrenceSignature(node: BookmarkNode): string {
    if (node.type === 'folder') {
      return `folder:${node.title}`;
    }
    return `bookmark:${node.title}:${node.url ?? ''}`;
  }

  private createFolderEntityId(parentId: string | null, title: string, occurrence: number): string {
    return `bkf_${this.slugify(title || 'folder')}_${this.shortHash(`${parentId || AIRA_SYNC_ROOT_ORDER_KEY}|${title}|${occurrence}`)}`;
  }

  private createItemEntityId(parentId: string | null, title: string, url: string, occurrence: number): string {
    return `bkm_${this.slugify(title || url || 'item')}_${this.shortHash(`${parentId || AIRA_SYNC_ROOT_ORDER_KEY}|${title}|${url}|${occurrence}`)}`;
  }

  private resolvePlannedEntityId(node: BookmarkNode, plan: AiraBookmarkEntityIdPlan): string {
    return plan.idsByNodeId.get(node.id) ?? this.toAiraBookmarkEntityId(node.id);
  }

  private resolvePlannedParentEntityId(node: BookmarkNode, plan: AiraBookmarkEntityIdPlan): string | null {
    return plan.parentEntityIdsByNodeId.get(node.id) ?? this.normalizeParentId(node);
  }

  private slugify(value: string): string {
    const lower = (value || '').toLowerCase();
    let result = '';
    let previousDash = false;
    for (let index = 0; index < lower.length && result.length < 32; index += 1) {
      const code = lower.charCodeAt(index);
      const isAlphaNumber = (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
      if (isAlphaNumber) {
        result += lower.charAt(index);
        previousDash = false;
      } else if (!previousDash && result.length > 0) {
        result += '-';
        previousDash = true;
      }
    }
    while (result.endsWith('-')) {
      result = result.slice(0, result.length - 1);
    }
    return result.length > 0 ? result : 'bookmark';
  }

  private shortHash(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(36);
  }

  private toIsoString(timestamp: number): string {
    return new Date(timestamp).toISOString();
  }

  private toTimestamp(value: string): number {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : Date.now();
  }

  private async buildOrderPositionIndexAsync(bookmarkOrders: AiraSyncBookmarkOrder[]): Promise<AiraOrderPositionIndex> {
    const result: AiraOrderPositionIndex = new Map<string, Map<string, number>>();
    for (let orderIndex = 0; orderIndex < bookmarkOrders.length; orderIndex += 1) {
      const order = bookmarkOrders[orderIndex];
      const orderKey = this.resolveOrderKey(order.parentId);
      const positions = new Map<string, number>();
      for (let idIndex = 0; idIndex < order.ids.length; idIndex += 1) {
        const id = order.ids[idIndex];
        if (!positions.has(id)) {
          positions.set(id, idIndex);
        }
        await this.workThrottle.afterBatchItem(idIndex + 1);
      }
      result.set(orderKey, positions);
      await this.workThrottle.afterBatchItem(orderIndex + 1);
    }
    return result;
  }

  private resolvePositionFromIndex(
    orderPositionIndex: AiraOrderPositionIndex,
    parentId: string | null,
    entityId: string
  ): number {
    const orderKey = parentId === null ? AIRA_SYNC_ROOT_ORDER_KEY : parentId;
    const positions = orderPositionIndex.get(orderKey);
    if (positions === undefined) {
      return 0;
    }
    const position = positions.get(entityId);
    return position === undefined ? positions.size : position;
  }

  private findOrderRevisionSeed(
    nodes: BookmarkNode[],
    nodesByEntityId: Map<string, BookmarkNode>,
    orderKey: string,
    ids: string[]
  ): BookmarkNode | undefined {
    const seedId = ids[0];
    if (seedId !== undefined) {
      return nodesByEntityId.get(seedId);
    }

    if (orderKey === AIRA_SYNC_ROOT_ORDER_KEY) {
      return nodes.find((node: BookmarkNode) => node.parentId === undefined);
    }

    return nodesByEntityId.get(orderKey);
  }

  private async buildNodesByPlannedEntityIdAsync(
    nodes: BookmarkNode[],
    entityIdPlan: AiraBookmarkEntityIdPlan
  ): Promise<Map<string, BookmarkNode>> {
    const result = new Map<string, BookmarkNode>();
    for (let index = 0; index < nodes.length; index += 1) {
      const node = nodes[index];
      const entityId = this.resolvePlannedEntityId(node, entityIdPlan);
      if (!result.has(entityId)) {
        result.set(entityId, node);
      }
      await this.workThrottle.afterBatchItem(index + 1);
    }
    return result;
  }

}

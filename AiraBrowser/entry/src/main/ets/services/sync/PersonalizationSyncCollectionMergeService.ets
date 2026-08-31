import { PersonalizationSyncItemTombstone } from '../../common/models/PersonalizationSyncModels';

export type PersonalizationSyncCollectionItemIdResolver<T> = (item: T) => string;
export type PersonalizationSyncCollectionItemTimestampResolver<T> = (item: T) => number;

export interface PersonalizationSyncCollectionMergeResult<T> {
  items: T[];
  tombstones: PersonalizationSyncItemTombstone[];
}

export type PersonalizationSyncCollectionMergeIntent = 'ordinary' | 'provider-switch';

export class PersonalizationSyncCollectionMergeService {
  merge<T>(
    localItems: T[],
    remoteItems: T[],
    localTombstones: PersonalizationSyncItemTombstone[],
    remoteTombstones: PersonalizationSyncItemTombstone[],
    resolveId: PersonalizationSyncCollectionItemIdResolver<T>,
    resolveUpdatedAt: PersonalizationSyncCollectionItemTimestampResolver<T>,
    intent: PersonalizationSyncCollectionMergeIntent = 'ordinary'
  ): PersonalizationSyncCollectionMergeResult<T> {
    const ids = this.collectIds(localItems, remoteItems, localTombstones, remoteTombstones, resolveId);
    const items: T[] = [];
    const tombstones: PersonalizationSyncItemTombstone[] = [];
    ids.forEach((id: string) => {
      const localItem = localItems.find((item: T): boolean => resolveId(item).trim() === id);
      const remoteItem = remoteItems.find((item: T): boolean => resolveId(item).trim() === id);
      const tombstone = this.resolveLatestTombstone(id, localTombstones, remoteTombstones);
      const localUpdatedAt = localItem === undefined ? 0 : this.normalizeTimestamp(resolveUpdatedAt(localItem));
      const remoteUpdatedAt = remoteItem === undefined ? 0 : this.normalizeTimestamp(resolveUpdatedAt(remoteItem));
      const liveUpdatedAt = Math.max(localUpdatedAt, remoteUpdatedAt);
      const preservesLive = intent === 'provider-switch' && liveUpdatedAt > 0;
      if (tombstone !== undefined && tombstone.deletedAt >= liveUpdatedAt && !preservesLive) {
        tombstones.push(tombstone);
        return;
      }
      if (localItem !== undefined) {
        items.push(localItem);
        return;
      }
      if (remoteItem !== undefined) {
        items.push(remoteItem);
      }
    });
    return {
      items: items,
      tombstones: tombstones
    };
  }

  private collectIds<T>(
    localItems: T[],
    remoteItems: T[],
    localTombstones: PersonalizationSyncItemTombstone[],
    remoteTombstones: PersonalizationSyncItemTombstone[],
    resolveId: PersonalizationSyncCollectionItemIdResolver<T>
  ): string[] {
    const ids: string[] = [];
    localItems.concat(remoteItems).forEach((item: T) => {
      this.appendUniqueId(ids, resolveId(item));
    });
    localTombstones.concat(remoteTombstones).forEach((value: PersonalizationSyncItemTombstone) => {
      this.appendUniqueId(ids, value.id);
    });
    return ids;
  }

  private appendUniqueId(ids: string[], value: string): void {
    const normalized = value.trim();
    if (normalized.length > 0 && ids.indexOf(normalized) < 0) {
      ids.push(normalized);
    }
  }

  private resolveLatestTombstone(
    id: string,
    localTombstones: PersonalizationSyncItemTombstone[],
    remoteTombstones: PersonalizationSyncItemTombstone[]
  ): PersonalizationSyncItemTombstone | undefined {
    let deletedAt = 0;
    localTombstones.concat(remoteTombstones).forEach((value: PersonalizationSyncItemTombstone) => {
      if (value.id.trim() === id) {
        deletedAt = Math.max(deletedAt, this.normalizeTimestamp(value.deletedAt));
      }
    });
    if (deletedAt <= 0) {
      return undefined;
    }
    return {
      id: id,
      deletedAt: deletedAt
    };
  }

  private normalizeTimestamp(value: number): number {
    const normalized = Number(value);
    if (!Number.isFinite(normalized) || normalized < 0) {
      return 0;
    }
    return Math.floor(normalized);
  }
}

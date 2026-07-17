import {
  createLeafTabSyncCommitId,
  normalizeLeafTabSyncSnapshot,
  type LeafTabSyncBaseline,
  type LeafTabSyncSnapshot,
} from './schema';

export interface LeafTabSyncBaselineStore {
  load(): Promise<LeafTabSyncBaseline | null>;
  save(baseline: LeafTabSyncBaseline): Promise<void>;
}

export class LeafTabSyncExtensionStorageBaselineStore implements LeafTabSyncBaselineStore {
  private readonly key: string;

  constructor(key: string) {
    this.key = key;
  }

  private getStorageArea() {
    const storageArea = globalThis.chrome?.storage?.local;
    if (!storageArea?.get || !storageArea?.set) {
      throw new Error('chrome.storage.local is required for bookmark sync baseline storage');
    }
    return storageArea;
  }

  async load() {
    const storageArea = this.getStorageArea();
    const result = await storageArea.get(this.key);
    const value = result?.[this.key];
    return value ? value as LeafTabSyncBaseline : null;
  }

  async save(baseline: LeafTabSyncBaseline) {
    const storageArea = this.getStorageArea();
    await storageArea.set({ [this.key]: baseline });
  }
}

export const createLeafTabSyncBaseline = (params: {
  snapshot: LeafTabSyncSnapshot;
  commitId?: string | null;
}) => {
  return {
    commitId: params.commitId ?? createLeafTabSyncCommitId(
      params.snapshot.meta.deviceId,
      params.snapshot.meta.generatedAt,
    ),
    snapshot: params.snapshot,
    savedAt: params.snapshot.meta.generatedAt,
  } satisfies LeafTabSyncBaseline;
};

export const getLeafTabSyncBaselineSnapshot = (
  baseline: LeafTabSyncBaseline | null,
): LeafTabSyncSnapshot | null => {
  return normalizeLeafTabSyncSnapshot(baseline?.snapshot || null);
};

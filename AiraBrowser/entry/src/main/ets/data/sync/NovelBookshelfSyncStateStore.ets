import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AiraSyncProviderKind
} from '../../common/models/AiraSyncModels';
import {
  NovelBookshelfSyncSelectionState
} from '../../common/models/NovelBookshelfSyncModels';

export type NovelBookshelfSyncLineageRole = 'active' | 'backup';

export interface NovelBookshelfSyncLineageState {
  remoteKind: AiraSyncProviderKind;
  role: NovelBookshelfSyncLineageRole;
  providerIdentity: string;
  revision: string;
  lastSuccessAt: number;
}

interface NovelBookshelfSyncStateDocument {
  schemaVersion: number;
  selection: NovelBookshelfSyncSelectionState;
  lineages: NovelBookshelfSyncLineageState[];
}

const NOVEL_BOOKSHELF_SYNC_STATE_SCHEMA_VERSION: number = 1;
const NOVEL_BOOKSHELF_SYNC_STATE_PREFERENCES: string = 'aira_novel_bookshelf_sync_g1';
const NOVEL_BOOKSHELF_SYNC_STATE_KEY: string = 'state';

export class NovelBookshelfSyncStateStore {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private document: NovelBookshelfSyncStateDocument = this.createDefaultDocument();
  private initializationPromise?: Promise<void>;
  private initialized: boolean = false;
  private mutationTail: Promise<void> = Promise.resolve();

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.getStore().then((store: preferences.Preferences): void => {
        const raw: string = String(store.getSync(NOVEL_BOOKSHELF_SYNC_STATE_KEY, ''));
        this.document = this.parseDocument(raw);
        this.initialized = true;
      }).catch((error: Error) => {
        this.initializationPromise = undefined;
        throw error;
      });
    }
    await this.initializationPromise;
  }

  getSelection(activeProviderPresent: boolean): NovelBookshelfSyncSelectionState {
    const selection = this.document.selection;
    return {
      initialized: selection.initialized,
      enabled: selection.initialized ? selection.enabled : !activeProviderPresent,
      updatedAt: selection.updatedAt
    };
  }

  async setSelection(enabled: boolean): Promise<NovelBookshelfSyncSelectionState> {
    await this.initialize();
    const next: NovelBookshelfSyncSelectionState = {
      initialized: true,
      enabled: enabled,
      updatedAt: Date.now()
    };
    await this.mutate((document: NovelBookshelfSyncStateDocument): void => {
      document.selection = next;
    });
    return this.getSelection(false);
  }

  findLineage(
    remoteKind: AiraSyncProviderKind,
    role: NovelBookshelfSyncLineageRole,
    providerIdentity: string
  ): NovelBookshelfSyncLineageState | undefined {
    const value = this.document.lineages.find((candidate: NovelBookshelfSyncLineageState): boolean => {
      return candidate.remoteKind === remoteKind && candidate.role === role &&
        candidate.providerIdentity === providerIdentity;
    });
    return value === undefined ? undefined : this.cloneLineage(value);
  }

  async saveLineage(
    remoteKind: AiraSyncProviderKind,
    role: NovelBookshelfSyncLineageRole,
    providerIdentity: string,
    revision: string
  ): Promise<void> {
    await this.initialize();
    const state: NovelBookshelfSyncLineageState = {
      remoteKind: remoteKind,
      role: role,
      providerIdentity: providerIdentity.trim(),
      revision: revision.trim(),
      lastSuccessAt: Date.now()
    };
    await this.mutate((document: NovelBookshelfSyncStateDocument): void => {
      document.lineages = document.lineages.filter((candidate: NovelBookshelfSyncLineageState): boolean => {
        return candidate.remoteKind !== remoteKind || candidate.role !== role;
      });
      document.lineages.push(state);
    });
  }

  private mutate(operation: (document: NovelBookshelfSyncStateDocument) => void): Promise<void> {
    const task: Promise<void> = this.mutationTail.then(async (): Promise<void> => {
      const next: NovelBookshelfSyncStateDocument = this.cloneDocument(this.document);
      operation(next);
      const store = await this.getStore();
      store.putSync(NOVEL_BOOKSHELF_SYNC_STATE_KEY, JSON.stringify(next));
      await store.flush();
      this.document = next;
    });
    this.mutationTail = task.catch((_error: Error): void => {});
    return task;
  }

  private parseDocument(raw: string): NovelBookshelfSyncStateDocument {
    if (raw.trim().length <= 0) {
      return this.createDefaultDocument();
    }
    try {
      const value = JSON.parse(raw) as NovelBookshelfSyncStateDocument;
      if (value.schemaVersion !== NOVEL_BOOKSHELF_SYNC_STATE_SCHEMA_VERSION) {
        return this.createDefaultDocument();
      }
      const selection = value.selection;
      const lineages = Array.isArray(value.lineages) ? value.lineages : [];
      return {
        schemaVersion: NOVEL_BOOKSHELF_SYNC_STATE_SCHEMA_VERSION,
        selection: {
          initialized: selection?.initialized === true,
          enabled: selection?.enabled === true,
          updatedAt: this.normalizeTimestamp(selection?.updatedAt)
        },
        lineages: lineages
          .filter((candidate: NovelBookshelfSyncLineageState): boolean => this.isValidLineage(candidate))
          .map((candidate: NovelBookshelfSyncLineageState): NovelBookshelfSyncLineageState =>
            this.cloneLineage(candidate))
      };
    } catch (_error) {
      return this.createDefaultDocument();
    }
  }

  private isValidLineage(value: NovelBookshelfSyncLineageState): boolean {
    return (value.remoteKind === 'aira_cloud' || value.remoteKind === 'webdav' ||
      value.remoteKind === 'huawei_space' || value.remoteKind === 'self_hosted') &&
      (value.role === 'active' || value.role === 'backup') &&
      String(value.providerIdentity ?? '').trim().length > 0 && String(value.revision ?? '').trim().length > 0 &&
      this.normalizeTimestamp(value.lastSuccessAt) > 0;
  }

  private normalizeTimestamp(value: number | undefined): number {
    const numeric: number = Number(value ?? 0);
    return Number.isFinite(numeric) && numeric > 0 ? Math.floor(numeric) : 0;
  }

  private createDefaultDocument(): NovelBookshelfSyncStateDocument {
    return {
      schemaVersion: NOVEL_BOOKSHELF_SYNC_STATE_SCHEMA_VERSION,
      selection: { initialized: false, enabled: false, updatedAt: 0 },
      lineages: []
    };
  }

  private cloneDocument(value: NovelBookshelfSyncStateDocument): NovelBookshelfSyncStateDocument {
    return {
      schemaVersion: NOVEL_BOOKSHELF_SYNC_STATE_SCHEMA_VERSION,
      selection: {
        initialized: value.selection.initialized,
        enabled: value.selection.enabled,
        updatedAt: value.selection.updatedAt
      },
      lineages: value.lineages.map(
        (candidate: NovelBookshelfSyncLineageState): NovelBookshelfSyncLineageState => this.cloneLineage(candidate)
      )
    };
  }

  private cloneLineage(value: NovelBookshelfSyncLineageState): NovelBookshelfSyncLineageState {
    return {
      remoteKind: value.remoteKind,
      role: value.role,
      providerIdentity: value.providerIdentity,
      revision: value.revision,
      lastSuccessAt: value.lastSuccessAt
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        NOVEL_BOOKSHELF_SYNC_STATE_PREFERENCES
      ).then((store: preferences.Preferences): preferences.Preferences => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }
}

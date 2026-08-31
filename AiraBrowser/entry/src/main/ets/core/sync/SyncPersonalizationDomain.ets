import {
  PersonalizationSyncConfig,
  PersonalizationSyncContentId,
  PersonalizationSyncItemId,
  PersonalizationSyncRunResult
} from '../../common/models/PersonalizationSyncModels';
import { NovelBookshelfSyncSelectionState } from '../../common/models/NovelBookshelfSyncModels';
import { PersonalizationSyncConfigStore } from '../../data/sync/PersonalizationSyncConfigStore';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import { PersonalizationSyncService } from '../../services/sync/PersonalizationSyncService';

export type SyncPersonalizationDomainRunOutcomeType =
  | 'sync-completed'
  | 'failed';

export interface SyncPersonalizationDomainRunOutcome {
  type: SyncPersonalizationDomainRunOutcomeType;
  title: string;
  message: string;
  config?: PersonalizationSyncConfig;
  result?: PersonalizationSyncRunResult;
}

export interface SyncPersonalizationDomainItemUpdateOutcome {
  ok: boolean;
  config: PersonalizationSyncConfig;
  novelBookshelfSelection: NovelBookshelfSyncSelectionState;
  message: string;
}

export class SyncPersonalizationDomain {
  private personalizationConfigStore: PersonalizationSyncConfigStore;
  private syncConfigStore: AiraSyncConfigStore;
  private personalizationSyncService: PersonalizationSyncService;

  constructor(
    personalizationConfigStore: PersonalizationSyncConfigStore,
    syncConfigStore: AiraSyncConfigStore,
    personalizationSyncService: PersonalizationSyncService
  ) {
    this.personalizationConfigStore = personalizationConfigStore;
    this.syncConfigStore = syncConfigStore;
    this.personalizationSyncService = personalizationSyncService;
  }

  async updateItemEnabled(
    id: PersonalizationSyncContentId,
    enabled: boolean
  ): Promise<SyncPersonalizationDomainItemUpdateOutcome> {
    try {
      const config = await this.personalizationConfigStore.initialize();
      if (id === 'novel_bookshelf') {
        const selection = await this.personalizationSyncService.setNovelBookshelfSelection(enabled);
        return { ok: true, config: config, novelBookshelfSelection: selection, message: '' };
      }
      const nextConfig = await this.personalizationConfigStore.setItemEnabled(id as PersonalizationSyncItemId, enabled);
      const selection = await this.personalizationSyncService.initializeNovelBookshelfSelection();
      return { ok: true, config: nextConfig, novelBookshelfSelection: selection, message: '' };
    } catch (error) {
      const config = this.personalizationConfigStore.getConfig();
      const selection = await this.personalizationSyncService.initializeNovelBookshelfSelection()
        .catch((_selectionError: Error): NovelBookshelfSyncSelectionState => ({
          initialized: true,
          enabled: false,
          updatedAt: 0
        }));
      return {
        ok: false,
        config: config,
        novelBookshelfSelection: selection,
        message: this.stringifyError(error as Error)
      };
    }
  }

  initializeNovelBookshelfSelection(): Promise<NovelBookshelfSyncSelectionState> {
    return this.personalizationSyncService.initializeNovelBookshelfSelection();
  }

  async restoreContentSelection(
    config: PersonalizationSyncConfig,
    novelBookshelfEnabled: boolean
  ): Promise<void> {
    for (let index: number = 0; index < config.items.length; index += 1) {
      const item = config.items[index];
      await this.personalizationConfigStore.setItemEnabled(item.id, item.enabled, item.updatedAt);
    }
    await this.personalizationSyncService.restoreNovelBookshelfSelection(novelBookshelfEnabled);
  }

  async syncDomainNow(forceBackupWrites: boolean = false): Promise<SyncPersonalizationDomainRunOutcome> {
    try {
      const result = await this.personalizationSyncService.syncNow({
        forceBackupWrites: forceBackupWrites
      });
      return {
        type: result.ok ? 'sync-completed' : 'failed',
        title: result.ok ? '同步完成' : '同步未完成',
        message: result.message,
        result: result
      };
    } catch (error) {
      return this.failure('同步未完成', error as Error);
    }
  }

  async disableDomain(): Promise<void> {
    await this.syncConfigStore.setPersonalizationSyncEnabled(false);
  }

  async enableDomain(): Promise<PersonalizationSyncRunResult> {
    await this.syncConfigStore.initialize();
    const settings = this.syncConfigStore.getSettings();
    const activeProvider = settings.remoteKind;
    if (activeProvider === 'none') {
      throw new Error('当前同步状态还未准备好，请稍后再试。');
    }
    const result = await this.personalizationSyncService.syncToProvider(activeProvider);
    await this.syncConfigStore.setPersonalizationSyncEnabled(true);
    return result;
  }

  private failure(title: string, error: Error): SyncPersonalizationDomainRunOutcome {
    return {
      type: 'failed',
      title: title,
      message: this.stringifyError(error)
    };
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}

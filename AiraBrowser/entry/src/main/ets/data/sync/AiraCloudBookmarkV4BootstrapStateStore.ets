import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
  AiraCloudBookmarkV4BootstrapPhase,
  AiraCloudBookmarkV4BootstrapRecord,
  AiraCloudBookmarkV4BootstrapStateDomain,
  AiraCloudBookmarkV4BootstrapStatus
} from '../../common/models/AiraCloudBookmarkV4BootstrapModels';

const PREFERENCES_NAME: string = 'aira_cloud_bookmark_v4_bootstrap';
const STATE_KEY: string = 'state';
const STATE_SCHEMA_VERSION: number = 1;
const MAX_RECORD_COUNT: number = 8;
const MAX_ID_LENGTH: number = 512;
const MAX_ERROR_LENGTH: number = 1024;

interface AiraCloudBookmarkV4BootstrapStateDocument {
  schemaVersion: number;
  records: AiraCloudBookmarkV4BootstrapRecord[];
}

export interface AiraCloudBookmarkV4BootstrapStateAdapter {
  read(): Promise<string>;
  write(value: string): Promise<void>;
}

class PreferencesAiraCloudBookmarkV4BootstrapStateAdapter implements
  AiraCloudBookmarkV4BootstrapStateAdapter {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;

  async read(): Promise<string> {
    const store = await this.getStore();
    return String(store.getSync(STATE_KEY, ''));
  }

  async write(value: string): Promise<void> {
    const store = await this.getStore();
    store.putSync(STATE_KEY, value);
    await store.flush();
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(
        AppRuntimeContext.getApplicationContext(),
        PREFERENCES_NAME
      ).then((store: preferences.Preferences): preferences.Preferences => {
        this.store = store;
        return store;
      });
    }
    return this.storePromise;
  }
}

export class AiraCloudBookmarkV4BootstrapStateStore implements AiraCloudBookmarkV4BootstrapStateDomain {
  private readonly adapter: AiraCloudBookmarkV4BootstrapStateAdapter;
  private mutationTask: Promise<void> = Promise.resolve();

  constructor(adapter?: AiraCloudBookmarkV4BootstrapStateAdapter) {
    this.adapter = adapter ?? new PreferencesAiraCloudBookmarkV4BootstrapStateAdapter();
  }

  async load(uid: string): Promise<AiraCloudBookmarkV4BootstrapRecord | undefined> {
    const normalizedUid = uid.trim();
    if (normalizedUid.length === 0) {
      return undefined;
    }
    const records = await this.readRecords();
    const record = records.find((candidate: AiraCloudBookmarkV4BootstrapRecord): boolean => {
      return candidate.uid === normalizedUid &&
        candidate.protocol === AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL;
    });
    return record === undefined ? undefined : this.copyRecord(record);
  }

  async listProtectedRecoveryPointIds(): Promise<string[]> {
    const records = await this.readRecords(true);
    const backupIds: string[] = [];
    records.forEach((record: AiraCloudBookmarkV4BootstrapRecord): void => {
      const backupId = record.backupId.trim();
      if (record.status !== 'completed' && record.status !== 'opted_out' &&
        backupId.length > 0 && backupIds.indexOf(backupId) < 0) {
        backupIds.push(backupId);
      }
    });
    return backupIds;
  }

  save(record: AiraCloudBookmarkV4BootstrapRecord): Promise<void> {
    const normalized = this.normalizeRecord(record);
    if (normalized === undefined) {
      return Promise.reject(new Error('Aira 云书签 V4 初始化状态无效。'));
    }
    return this.enqueue(async (): Promise<void> => {
      const records = await this.readRecords();
      const retained = records.filter((candidate: AiraCloudBookmarkV4BootstrapRecord): boolean => {
        return candidate.uid !== normalized.uid || candidate.protocol !== normalized.protocol;
      });
      retained.push(normalized);
      retained.sort((left: AiraCloudBookmarkV4BootstrapRecord,
        right: AiraCloudBookmarkV4BootstrapRecord): number => right.updatedAt - left.updatedAt);
      const document: AiraCloudBookmarkV4BootstrapStateDocument = {
        schemaVersion: STATE_SCHEMA_VERSION,
        records: retained.slice(0, MAX_RECORD_COUNT)
      };
      await this.adapter.write(JSON.stringify(document));
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.mutationTask.then(operation, operation);
    this.mutationTask = next.catch((): void => {});
    return next;
  }

  private async readRecords(rejectInvalidState: boolean = false): Promise<AiraCloudBookmarkV4BootstrapRecord[]> {
    let rawValue: string = '';
    try {
      rawValue = await this.adapter.read();
      if (rawValue.trim().length === 0) {
        return [];
      }
      const document = JSON.parse(rawValue) as AiraCloudBookmarkV4BootstrapStateDocument;
      if (document.schemaVersion !== STATE_SCHEMA_VERSION || !Array.isArray(document.records)) {
        if (rejectInvalidState) {
          throw new Error('Aira 云书签 V4 初始化状态文档无效。');
        }
        return [];
      }
      const records: AiraCloudBookmarkV4BootstrapRecord[] = [];
      for (let index = 0; index < document.records.length; index += 1) {
        const candidate = document.records[index];
        const normalized = this.normalizeRecord(candidate);
        if (normalized === undefined) {
          if (rejectInvalidState) {
            throw new Error('Aira 云书签 V4 初始化状态记录无效。');
          }
          continue;
        }
        records.push(normalized);
      }
      return records;
    } catch (error) {
      if (rejectInvalidState) {
        throw error instanceof Error ? error : new Error(JSON.stringify(error));
      }
      return [];
    }
  }

  private normalizeRecord(
    value: AiraCloudBookmarkV4BootstrapRecord
  ): AiraCloudBookmarkV4BootstrapRecord | undefined {
    const uid = typeof value?.uid === 'string' ? value.uid.trim().substring(0, MAX_ID_LENGTH) : '';
    const protocol = typeof value?.protocol === 'string' ? value.protocol.trim() : '';
    const status = this.normalizeStatus(value?.status);
    const phase = this.normalizePhase(value?.phase);
    if (uid.length === 0 || protocol !== AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL ||
      status === undefined || phase === undefined) {
      return undefined;
    }
    return {
      uid: uid,
      protocol: protocol,
      cutoverId: this.normalizeText(value.cutoverId, MAX_ID_LENGTH),
      status: status,
      phase: phase,
      backupId: this.normalizeText(value.backupId, MAX_ID_LENGTH),
      backupSha256: this.normalizeText(value.backupSha256, 128),
      remoteCommitId: this.normalizeText(value.remoteCommitId, MAX_ID_LENGTH),
      errorMessage: this.normalizeText(value.errorMessage, MAX_ERROR_LENGTH),
      updatedAt: this.normalizeTimestamp(value.updatedAt),
      completedAt: this.normalizeTimestamp(value.completedAt)
    };
  }

  private normalizeStatus(value: string | undefined): AiraCloudBookmarkV4BootstrapStatus | undefined {
    if (value === 'required' || value === 'running' || value === 'failed' ||
      value === 'completed' || value === 'opted_out') {
      return value;
    }
    return undefined;
  }

  private normalizePhase(value: string | undefined): AiraCloudBookmarkV4BootstrapPhase | undefined {
    if (value === 'required' || value === 'creating_backup' || value === 'reading_remote' ||
      value === 'replacing_local' || value === 'verifying_local' || value === 'completed' ||
      value === 'opted_out' || value === 'failed') {
      return value;
    }
    return undefined;
  }

  private normalizeText(value: string | undefined, maxLength: number): string {
    return typeof value === 'string' ? value.trim().substring(0, maxLength) : '';
  }

  private normalizeTimestamp(value: number | undefined): number {
    const timestamp = Number(value ?? 0);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.floor(timestamp) : 0;
  }

  private copyRecord(value: AiraCloudBookmarkV4BootstrapRecord): AiraCloudBookmarkV4BootstrapRecord {
    return {
      uid: value.uid,
      protocol: value.protocol,
      cutoverId: value.cutoverId,
      status: value.status,
      phase: value.phase,
      backupId: value.backupId,
      backupSha256: value.backupSha256,
      remoteCommitId: value.remoteCommitId,
      errorMessage: value.errorMessage,
      updatedAt: value.updatedAt,
      completedAt: value.completedAt
    };
  }
}

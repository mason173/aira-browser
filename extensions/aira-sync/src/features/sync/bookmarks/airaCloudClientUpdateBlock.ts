import { LEAFTAB_BACKGROUND_STORAGE_KEYS } from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { getExtensionManifest } from '@/platform/runtime';

interface AiraCloudClientUpdateBlockRecord {
  clientVersion: string;
  message: string;
}

export interface AiraCloudClientUpdateBlockState {
  blocked: boolean;
  message: string;
}

const getCurrentClientVersion = (): string => getExtensionManifest()?.version?.trim() || '';

const normalizeBlockRecord = (value: unknown): AiraCloudClientUpdateBlockRecord | null => {
  if (!value || typeof value !== 'object') return null;
  const record = value as Partial<AiraCloudClientUpdateBlockRecord>;
  const clientVersion = typeof record.clientVersion === 'string' ? record.clientVersion.trim() : '';
  const message = typeof record.message === 'string' ? record.message.trim() : '';
  if (!clientVersion || !message) return null;
  return { clientVersion, message };
};

export async function readAiraCloudClientUpdateBlock(): Promise<AiraCloudClientUpdateBlockState> {
  const key = LEAFTAB_BACKGROUND_STORAGE_KEYS.airaCloudClientUpdateRequired;
  const stored = await readExtensionStorageRecord([key]);
  const record = normalizeBlockRecord(stored[key]);
  if (!record) {
    return { blocked: false, message: '' };
  }
  const currentVersion = getCurrentClientVersion();
  if (!currentVersion || record.clientVersion !== currentVersion) {
    await removeExtensionStorageKeys([key]);
    return { blocked: false, message: '' };
  }
  return { blocked: true, message: record.message };
}

export async function persistAiraCloudClientUpdateBlock(message: string): Promise<void> {
  const clientVersion = getCurrentClientVersion();
  const normalizedMessage = message.trim();
  if (!clientVersion || !normalizedMessage) return;
  await writeExtensionStorageRecord({
    [LEAFTAB_BACKGROUND_STORAGE_KEYS.airaCloudClientUpdateRequired]: {
      clientVersion,
      message: normalizedMessage,
    },
  });
}

export function clearAiraCloudClientUpdateBlock(): Promise<void> {
  return removeExtensionStorageKeys([
    LEAFTAB_BACKGROUND_STORAGE_KEYS.airaCloudClientUpdateRequired,
  ]);
}

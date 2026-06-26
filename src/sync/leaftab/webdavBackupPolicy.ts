import { readExtensionStorageRecord, removeExtensionStorageKeys, writeExtensionStorageRecord } from '@/platform/extensionStorage';
import { WEBDAV_STORAGE_KEYS } from '@/utils/webdavConfig';

export const WEBDAV_BACKUP_REQUEST_TIMEOUT_MS = 3_000;
export const WEBDAV_BACKUP_TOTAL_TIMEOUT_MS = 8_000;
export const WEBDAV_BACKUP_FAILURE_COOLDOWN_MS = 600_000;

type WebdavBackupTarget = {
  url: string;
  username?: string;
  rootPath: string;
};

type WebdavBackupCooldownState = {
  cooldownKey: string;
  cooldownUntilMs: number;
  failureMessage: string;
};

const normalizePart = (value: string) => (value || '').trim();

const readLocalStorageValue = (key: string): string => {
  try {
    return localStorage.getItem(key) || '';
  } catch {
    return '';
  }
};

const writeLocalStorageValue = (key: string, value: string): void => {
  try {
    if (value) {
      localStorage.setItem(key, value);
      return;
    }
    localStorage.removeItem(key);
  } catch {}
};

const buildBackupCooldownKey = (target: WebdavBackupTarget): string => {
  return [
    'webdav',
    normalizePart(target.url),
    normalizePart(target.username || ''),
    normalizePart(target.rootPath),
  ].join('|');
};

const parseCooldownUntilMs = (value: string): number => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
};

const readCooldownStateFromStorage = (target: WebdavBackupTarget): WebdavBackupCooldownState | null => {
  const cooldownKey = buildBackupCooldownKey(target);
  const storedKey = readLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownKey);
  const storedUntilMs = parseCooldownUntilMs(readLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil));
  const storedMessage = readLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureMessage);
  if (storedKey === cooldownKey && storedUntilMs > Date.now()) {
    return {
      cooldownKey,
      cooldownUntilMs: storedUntilMs,
      failureMessage: storedMessage,
    };
  }
  return null;
};

export const readWebdavBackupCooldownResult = async (target: WebdavBackupTarget): Promise<string | null> => {
  const state = readCooldownStateFromStorage(target);
  if (!state) {
    const record = await readExtensionStorageRecord([
      WEBDAV_STORAGE_KEYS.backupFailureCooldownKey,
      WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil,
      WEBDAV_STORAGE_KEYS.backupFailureMessage,
    ]);
    const cooldownKey = String(record[WEBDAV_STORAGE_KEYS.backupFailureCooldownKey] || '');
    const cooldownUntilMs = parseCooldownUntilMs(String(record[WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil] || ''));
    const failureMessage = String(record[WEBDAV_STORAGE_KEYS.backupFailureMessage] || '');
    if (cooldownKey !== buildBackupCooldownKey(target) || cooldownUntilMs <= Date.now()) {
      return null;
    }
    writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownKey, cooldownKey);
    writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil, String(cooldownUntilMs));
    writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureMessage, failureMessage);
    return failureMessage.length > 0
      ? `WebDAV：上次备份失败，${failureMessage}，暂缓重试。`
      : 'WebDAV：上次备份失败，暂缓重试。';
  }
  return state.failureMessage.length > 0
    ? `WebDAV：上次备份失败，${state.failureMessage}，暂缓重试。`
    : 'WebDAV：上次备份失败，暂缓重试。';
};

export const recordWebdavBackupFailureCooldown = async (
  target: WebdavBackupTarget,
  error: unknown,
): Promise<void> => {
  const cooldownKey = buildBackupCooldownKey(target);
  const failureMessage = String((error as Error)?.message || error || 'WebDAV 备份失败');
  const cooldownUntilMs = Date.now() + WEBDAV_BACKUP_FAILURE_COOLDOWN_MS;
  writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownKey, cooldownKey);
  writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil, String(cooldownUntilMs));
  writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureMessage, failureMessage);
  await writeExtensionStorageRecord({
    [WEBDAV_STORAGE_KEYS.backupFailureCooldownKey]: cooldownKey,
    [WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil]: String(cooldownUntilMs),
    [WEBDAV_STORAGE_KEYS.backupFailureMessage]: failureMessage,
  });
};

export const clearWebdavBackupFailureCooldown = async (target: WebdavBackupTarget): Promise<void> => {
  const cooldownKey = buildBackupCooldownKey(target);
  const storedKey = readLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownKey);
  if (storedKey.length > 0 && storedKey !== cooldownKey) {
    return;
  }
  if (storedKey.length <= 0) {
    const record = await readExtensionStorageRecord([WEBDAV_STORAGE_KEYS.backupFailureCooldownKey]);
    const extensionStoredKey = String(record[WEBDAV_STORAGE_KEYS.backupFailureCooldownKey] || '');
    if (extensionStoredKey.length > 0 && extensionStoredKey !== cooldownKey) {
      return;
    }
  }
  writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownKey, '');
  writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil, '');
  writeLocalStorageValue(WEBDAV_STORAGE_KEYS.backupFailureMessage, '');
  await removeExtensionStorageKeys([
    WEBDAV_STORAGE_KEYS.backupFailureCooldownKey,
    WEBDAV_STORAGE_KEYS.backupFailureCooldownUntil,
    WEBDAV_STORAGE_KEYS.backupFailureMessage,
  ]);
};

export const withWebdavBackupTimeout = async <T>(
  task: Promise<T>,
  timeoutMs: number = WEBDAV_BACKUP_TOTAL_TIMEOUT_MS,
  message: string = 'WebDAV 备份连接超时，已跳过本次备份，不影响主同步。',
): Promise<T> => {
  let timeoutId: ReturnType<typeof globalThis.setTimeout> | null = null;
  try {
    return await Promise.race([
      task,
      new Promise<T>((_resolve, reject) => {
        timeoutId = globalThis.setTimeout(() => {
          reject(new Error(message));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId !== null) {
      globalThis.clearTimeout(timeoutId);
    }
  }
};

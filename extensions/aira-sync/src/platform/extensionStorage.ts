export type ExtensionStorageRecord = Record<string, unknown>;

export function getExtensionStorageArea(): chrome.storage.LocalStorageArea | null {
  const storageArea = globalThis.chrome?.storage?.local;
  if (!storageArea?.get || !storageArea?.set || !storageArea?.remove) {
    return null;
  }
  return storageArea;
}

export async function readExtensionStorageRecord(
  keys: string[],
): Promise<ExtensionStorageRecord> {
  const storageArea = getExtensionStorageArea();
  if (!storageArea || keys.length <= 0) {
    return {};
  }
  const result = await storageArea.get(keys);
  return result as ExtensionStorageRecord;
}

export async function readAllExtensionStorageRecords(): Promise<ExtensionStorageRecord> {
  const storageArea = getExtensionStorageArea();
  if (!storageArea) {
    return {};
  }
  const result = await storageArea.get(null);
  return result as ExtensionStorageRecord;
}

export async function writeExtensionStorageRecord(
  values: ExtensionStorageRecord,
): Promise<void> {
  const storageArea = getExtensionStorageArea();
  if (!storageArea || Object.keys(values).length <= 0) {
    return;
  }
  await storageArea.set(values);
}

export async function removeExtensionStorageKeys(keys: string[]): Promise<void> {
  const storageArea = getExtensionStorageArea();
  if (!storageArea || keys.length <= 0) {
    return;
  }
  await storageArea.remove(keys);
}

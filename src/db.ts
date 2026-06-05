
const DB_NAME = 'LeafTabDB';
const STORE_NAME = 'wallpapers';
const DB_VERSION = 1;
const CUSTOM_WALLPAPER_SELECTED_ID_KEY = 'customWallpaperSelectedIdV2';
const CUSTOM_WALLPAPER_RECORDS_KEY = 'customWallpaperRecordsV2';
const BING_WALLPAPER_BLOB_KEY = 'bingWallpaperBlob';

export type CustomWallpaperRecord = {
  id: string;
  blob: Blob;
  createdAt: string;
};

export const initDB = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
  });
};

const readStoreValue = async <T,>(key: string): Promise<T | null> => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.get(key);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve((request.result ?? null) as T | null);
  });
};

const writeStoreValue = async <T,>(key: string, value: T): Promise<void> => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.put(value, key);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
  });
};

const deleteStoreValue = async (key: string): Promise<void> => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.delete(key);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
  });
};

const createCustomWallpaperId = () => {
  const random = typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
  return `custom-wallpaper-${random}`;
};

const normalizeCustomWallpaperRecords = (value: unknown): CustomWallpaperRecord[] => {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is CustomWallpaperRecord => (
    typeof item?.id === 'string'
    && item.id.trim().length > 0
    && item.blob instanceof Blob
    && item.blob.size > 0
  ));
};

export const getCustomWallpaperLibrary = async (): Promise<{
  selectedId: string | null;
  records: CustomWallpaperRecord[];
}> => {
  const [selectedValue, recordsValue] = await Promise.all([
    readStoreValue<string>(CUSTOM_WALLPAPER_SELECTED_ID_KEY),
    readStoreValue<unknown>(CUSTOM_WALLPAPER_RECORDS_KEY),
  ]);
  const records = normalizeCustomWallpaperRecords(recordsValue);
  const selectedId = typeof selectedValue === 'string' && records.some((record) => record.id === selectedValue)
    ? selectedValue
    : records[0]?.id ?? null;

  if (records.length > 0) {
    if (selectedId !== selectedValue) {
      await (selectedId
        ? writeStoreValue(CUSTOM_WALLPAPER_SELECTED_ID_KEY, selectedId)
        : deleteStoreValue(CUSTOM_WALLPAPER_SELECTED_ID_KEY));
    }
    return { selectedId, records };
  }

  return { selectedId: null, records: [] };
};

export const saveCustomWallpaperLibrary = async ({
  selectedId,
  records,
}: {
  selectedId: string | null;
  records: CustomWallpaperRecord[];
}): Promise<void> => {
  const normalizedRecords = normalizeCustomWallpaperRecords(records);
  const normalizedSelectedId = selectedId && normalizedRecords.some((record) => record.id === selectedId)
    ? selectedId
    : normalizedRecords[0]?.id ?? null;
  await Promise.all([
    writeStoreValue(CUSTOM_WALLPAPER_RECORDS_KEY, normalizedRecords),
    normalizedSelectedId
      ? writeStoreValue(CUSTOM_WALLPAPER_SELECTED_ID_KEY, normalizedSelectedId)
      : deleteStoreValue(CUSTOM_WALLPAPER_SELECTED_ID_KEY),
  ]);
};

export const createCustomWallpaperRecords = (blobs: Blob[]): CustomWallpaperRecord[] => (
  blobs
    .filter((blob) => blob instanceof Blob && blob.size > 0)
    .map((blob) => ({
      id: createCustomWallpaperId(),
      blob,
      createdAt: new Date().toISOString(),
    }))
);

export const saveBingWallpaperBlob = async (blob: Blob): Promise<void> => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.put(blob, BING_WALLPAPER_BLOB_KEY);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
  });
};

export const getBingWallpaperBlob = async (): Promise<Blob | null> => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.get(BING_WALLPAPER_BLOB_KEY);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const value = request.result;
      if (value instanceof Blob) {
        resolve(value);
        return;
      }
      resolve(null);
    };
  });
};

export const deleteBingWallpaperBlob = async (): Promise<void> => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.delete(BING_WALLPAPER_BLOB_KEY);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
  });
};

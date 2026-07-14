import {
  readExtensionStorageRecord,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

export type AiraAccountBooleanPreferenceConfig = {
  legacyKey: string;
  scopedKeyPrefix: string;
  legacyOwnerKey: string;
  defaultValue: boolean;
};

export class AiraAccountBooleanPreferenceModule {
  constructor(private readonly config: AiraAccountBooleanPreferenceConfig) {}

  createKey(uid: string): string {
    return `${this.config.scopedKeyPrefix}:${encodeURIComponent(uid.trim())}`;
  }

  isStorageKey(key: string): boolean {
    return key === this.config.legacyKey
      || key === this.config.legacyOwnerKey
      || key.startsWith(`${this.config.scopedKeyPrefix}:`);
  }

  readLocal(uid: string): boolean {
    const normalizedUid = uid.trim();
    if (!normalizedUid) {
      return this.readLocalValue(this.config.legacyKey) ?? this.config.defaultValue;
    }

    const scopedKey = this.createKey(normalizedUid);
    const scopedValue = this.readLocalValue(scopedKey);
    if (scopedValue !== null) {
      return scopedValue;
    }

    const legacyOwner = this.readLocalString(this.config.legacyOwnerKey);
    if (legacyOwner && legacyOwner !== normalizedUid) {
      return this.config.defaultValue;
    }

    const legacyValue = this.readLocalValue(this.config.legacyKey);
    if (legacyValue === null) {
      return this.config.defaultValue;
    }

    this.writeLocalMigration(normalizedUid, legacyValue);
    void this.writeExtensionMigration(normalizedUid, legacyValue).catch(() => undefined);
    return legacyValue;
  }

  async readExtension(uid: string): Promise<boolean> {
    const normalizedUid = uid.trim();
    if (!normalizedUid) {
      const record = await readExtensionStorageRecord([this.config.legacyKey]);
      return this.parseValue(record[this.config.legacyKey]) ?? this.config.defaultValue;
    }

    const scopedKey = this.createKey(normalizedUid);
    const record = await readExtensionStorageRecord([
      scopedKey,
      this.config.legacyKey,
      this.config.legacyOwnerKey,
    ]);
    const scopedValue = this.parseValue(record[scopedKey]);
    if (scopedValue !== null) {
      return scopedValue;
    }

    const legacyOwner = String(record[this.config.legacyOwnerKey] || '').trim();
    if (legacyOwner && legacyOwner !== normalizedUid) {
      return this.config.defaultValue;
    }

    const legacyValue = this.parseValue(record[this.config.legacyKey]);
    if (legacyValue === null) {
      return this.config.defaultValue;
    }

    await writeExtensionStorageRecord({
      [scopedKey]: String(legacyValue),
      [this.config.legacyOwnerKey]: normalizedUid,
    });
    return legacyValue;
  }

  write(uid: string, value: boolean): void {
    const normalizedUid = uid.trim();
    const storageKey = normalizedUid ? this.createKey(normalizedUid) : this.config.legacyKey;
    try {
      localStorage.setItem(storageKey, String(value));
      if (normalizedUid && !this.readLocalString(this.config.legacyOwnerKey)) {
        localStorage.setItem(this.config.legacyOwnerKey, normalizedUid);
      }
    } catch {
      // Extension service workers do not expose localStorage.
    }
    void this.writeExtensionValue(normalizedUid, storageKey, value).catch(() => undefined);
  }

  private readLocalString(key: string): string {
    try {
      return String(localStorage.getItem(key) || '').trim();
    } catch {
      return '';
    }
  }

  private readLocalValue(key: string): boolean | null {
    try {
      return this.parseValue(localStorage.getItem(key));
    } catch {
      return null;
    }
  }

  private parseValue(value: unknown): boolean | null {
    if (value === undefined || value === null || value === '') {
      return null;
    }
    return String(value) !== 'false';
  }

  private writeLocalMigration(uid: string, value: boolean): void {
    try {
      localStorage.setItem(this.createKey(uid), String(value));
      localStorage.setItem(this.config.legacyOwnerKey, uid);
    } catch {
      // Extension service workers do not expose localStorage.
    }
  }

  private async writeExtensionMigration(uid: string, value: boolean): Promise<void> {
    const record = await readExtensionStorageRecord([this.config.legacyOwnerKey]);
    const existingOwner = String(record[this.config.legacyOwnerKey] || '').trim();
    if (existingOwner && existingOwner !== uid) {
      return;
    }
    await writeExtensionStorageRecord({
      [this.createKey(uid)]: String(value),
      [this.config.legacyOwnerKey]: uid,
    });
  }

  private async writeExtensionValue(uid: string, storageKey: string, value: boolean): Promise<void> {
    const values: Record<string, unknown> = {
      [storageKey]: String(value),
    };
    if (uid) {
      const record = await readExtensionStorageRecord([this.config.legacyOwnerKey]);
      if (!String(record[this.config.legacyOwnerKey] || '').trim()) {
        values[this.config.legacyOwnerKey] = uid;
      }
    }
    await writeExtensionStorageRecord(values);
  }
}

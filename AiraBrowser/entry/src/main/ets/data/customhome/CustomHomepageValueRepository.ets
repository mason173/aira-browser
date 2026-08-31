import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_browser_custom_homepage_values';
const VALUE_KEY_PREFIX: string = 'homepage_values_';
const MAX_INSTALLED_ID_LENGTH: number = 256;
const MAX_VALUE_KEY_LENGTH: number = 256;
const MAX_VALUE_COUNT: number = 512;
const MAX_VALUE_JSON_BYTES: number = 256 * 1024;
const MAX_HOMEPAGE_VALUE_BYTES: number = 1024 * 1024;

interface CustomHomepageStoredValueEntry {
  key?: string;
  valueJson?: string;
}

type CustomHomepageValueMap = Map<string, string>;

export class CustomHomepageValueRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private initializationPromise?: Promise<void>;
  private initialized: boolean = false;
  private valuesByInstalledId: Map<string, CustomHomepageValueMap> = new Map<string, CustomHomepageValueMap>();
  private commitTail: Promise<void> = Promise.resolve();
  private textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');

  initialize(): Promise<void> {
    if (this.initialized) {
      return Promise.resolve();
    }
    if (this.initializationPromise !== undefined) {
      return this.initializationPromise;
    }
    const pending = this.getStore()
      .then((): void => {
        this.initialized = true;
        this.initializationPromise = undefined;
      })
      .catch((error: Error): Promise<void> => {
        this.initializationPromise = undefined;
        return Promise.reject(error);
      });
    this.initializationPromise = pending;
    return pending;
  }

  async getValueJson(installedId: string, key: string): Promise<string | undefined> {
    await this.initialize();
    const normalizedInstalledId = this.normalizeInstalledId(installedId);
    const normalizedKey = this.normalizeValueKey(key);
    return this.loadValues(normalizedInstalledId).get(normalizedKey);
  }

  async setValueJson(installedId: string, key: string, valueJson: string): Promise<void> {
    await this.initialize();
    const normalizedInstalledId = this.normalizeInstalledId(installedId);
    const normalizedKey = this.normalizeValueKey(key);
    this.validateValueJson(valueJson);
    return this.enqueueCommit(async (): Promise<void> => {
      const nextValues = this.cloneValues(this.loadValues(normalizedInstalledId));
      nextValues.set(normalizedKey, valueJson);
      await this.persistValues(normalizedInstalledId, nextValues);
    });
  }

  async removeValue(installedId: string, key: string): Promise<void> {
    await this.initialize();
    const normalizedInstalledId = this.normalizeInstalledId(installedId);
    const normalizedKey = this.normalizeValueKey(key);
    return this.enqueueCommit(async (): Promise<void> => {
      const currentValues = this.loadValues(normalizedInstalledId);
      if (!currentValues.has(normalizedKey)) {
        return;
      }
      const nextValues = this.cloneValues(currentValues);
      nextValues.delete(normalizedKey);
      await this.persistValues(normalizedInstalledId, nextValues);
    });
  }

  async clearValues(installedId: string): Promise<void> {
    await this.initialize();
    const normalizedInstalledId = this.normalizeInstalledId(installedId);
    return this.enqueueCommit(async (): Promise<void> => {
      const store = await this.getStore();
      store.deleteSync(this.buildStorageKey(normalizedInstalledId));
      await store.flush();
      this.valuesByInstalledId.set(normalizedInstalledId, this.createEmptyValues());
    });
  }

  private enqueueCommit(operation: () => Promise<void>): Promise<void> {
    const readyTail = this.commitTail.catch((_error: Error): void => {});
    const result = readyTail.then((): Promise<void> => operation());
    this.commitTail = result.catch((_error: Error): void => {});
    return result;
  }

  private loadValues(installedId: string): CustomHomepageValueMap {
    const cached = this.valuesByInstalledId.get(installedId);
    if (cached !== undefined) {
      return cached;
    }
    const store = this.requireStore();
    const raw = String(store.getSync(this.buildStorageKey(installedId), '')).trim();
    const parsed: CustomHomepageValueMap = raw.length > 0 ?
      this.parseValues(raw) :
      this.createEmptyValues();
    this.valuesByInstalledId.set(installedId, parsed);
    return parsed;
  }

  private parseValues(raw: string): CustomHomepageValueMap {
    let parsed: CustomHomepageStoredValueEntry[];
    try {
      parsed = JSON.parse(raw) as CustomHomepageStoredValueEntry[];
    } catch (_error) {
      throw new Error('custom-homepage-value-state-invalid-json');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('custom-homepage-value-state-invalid-shape');
    }
    if (parsed.length > MAX_VALUE_COUNT) {
      throw new Error('custom-homepage-value-state-too-many-keys');
    }
    const values = this.createEmptyValues();
    parsed.forEach((entry: CustomHomepageStoredValueEntry): void => {
      if (entry === undefined || entry === null ||
        typeof entry.key !== 'string' || typeof entry.valueJson !== 'string') {
        throw new Error('custom-homepage-value-state-invalid-value');
      }
      const normalizedKey = this.normalizeValueKey(entry.key);
      if (values.has(normalizedKey)) {
        throw new Error('custom-homepage-value-state-duplicate-key');
      }
      const valueJson = entry.valueJson;
      this.validateValueJson(valueJson);
      values.set(normalizedKey, valueJson);
    });
    this.validateHomepageValues(values);
    return values;
  }

  private async persistValues(installedId: string, values: CustomHomepageValueMap): Promise<void> {
    const store = await this.getStore();
    const serialized = this.serializeValues(values);
    this.validateHomepageValues(values, serialized);
    store.putSync(this.buildStorageKey(installedId), serialized);
    await store.flush();
    this.valuesByInstalledId.set(installedId, this.cloneValues(values));
  }

  private validateHomepageValues(values: CustomHomepageValueMap, serialized?: string): void {
    const serializedValues = serialized ?? this.serializeValues(values);
    if (values.size > MAX_VALUE_COUNT || this.byteLength(serializedValues) > MAX_HOMEPAGE_VALUE_BYTES) {
      throw new Error('custom-homepage-value-state-quota-exceeded');
    }
  }

  private serializeValues(values: CustomHomepageValueMap): string {
    const entries: CustomHomepageStoredValueEntry[] = [];
    values.forEach((valueJson: string, key: string): void => {
      entries.push({
        key: key,
        valueJson: valueJson
      });
    });
    return JSON.stringify(entries);
  }

  private validateValueJson(valueJson: string): void {
    if (valueJson.length === 0 || this.byteLength(valueJson) > MAX_VALUE_JSON_BYTES) {
      throw new Error('custom-homepage-value-too-large');
    }
    try {
      JSON.parse(valueJson);
    } catch (_error) {
      throw new Error('custom-homepage-value-invalid-json');
    }
  }

  private normalizeInstalledId(value: string): string {
    const normalized = value.trim();
    if (normalized.length === 0 || normalized.length > MAX_INSTALLED_ID_LENGTH) {
      throw new Error('custom-homepage-installed-id-invalid');
    }
    return normalized;
  }

  private normalizeValueKey(value: string): string {
    const normalized = value.trim();
    if (normalized.length === 0 || normalized.length > MAX_VALUE_KEY_LENGTH) {
      throw new Error('custom-homepage-value-key-invalid');
    }
    return normalized;
  }

  private cloneValues(values: CustomHomepageValueMap): CustomHomepageValueMap {
    const cloned = this.createEmptyValues();
    values.forEach((valueJson: string, key: string): void => {
      cloned.set(key, valueJson);
    });
    return cloned;
  }

  private createEmptyValues(): CustomHomepageValueMap {
    return new Map<string, string>();
  }

  private buildStorageKey(installedId: string): string {
    return `${VALUE_KEY_PREFIX}${installedId}`;
  }

  private byteLength(value: string): number {
    return this.textEncoder.encodeInto(value).byteLength;
  }

  private requireStore(): preferences.Preferences {
    if (!this.initialized || this.store === undefined) {
      throw new Error('custom-homepage-value-state-not-ready');
    }
    return this.store;
  }

  private getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return Promise.resolve(this.store);
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences): preferences.Preferences => {
          this.store = store;
          return store;
        })
        .finally((): void => {
          this.storePromise = undefined;
        });
    }
    return this.storePromise;
  }
}

export const sharedCustomHomepageValueRepository: CustomHomepageValueRepository =
  new CustomHomepageValueRepository();

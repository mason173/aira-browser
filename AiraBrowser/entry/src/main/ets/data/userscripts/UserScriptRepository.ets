import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  cloneInstalledUserScriptState,
  InstalledUserScriptState,
  UserScriptGrant,
  UserScriptInstallSource,
  UserScriptResourceRecord,
  UserScriptRunAt,
  UserScriptSettings
} from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptCapabilityContractService } from '../../services/userscripts/UserScriptCapabilityContractService';
import { UserScriptIconService } from '../../services/userscripts/UserScriptIconService';

const PREFERENCES_NAME: string = 'aira_browser_userscripts';
const USER_SCRIPT_SETTINGS_KEY: string = 'user_script_settings';

export class UserScriptRepository {
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private iconService: UserScriptIconService = new UserScriptIconService();
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private initializationPromise?: Promise<void>;
  private initialized: boolean = false;
  private settings: UserScriptSettings = {
    scripts: [],
    autoUpdateEnabled: false,
    updatedAt: 0
  };
  async initialize(): Promise<UserScriptSettings> {
    if (this.initialized) {
      return this.getSettings();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.loadSettings();
    }
    try {
      await this.initializationPromise;
    } catch (error) {
      this.initializationPromise = undefined;
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('User script repository initialization failed.');
    }
    return this.getSettings();
  }

  private async loadSettings(): Promise<void> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(USER_SCRIPT_SETTINGS_KEY, ''));
    if (rawSettings.trim().length === 0) {
      this.settings = this.normalizeSettings(undefined);
      await this.persistSettings(this.settings);
    } else {
      this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    }
    this.initialized = true;
  }

  getSettings(): UserScriptSettings {
    return {
      scripts: this.settings.scripts.map((script: InstalledUserScriptState) => cloneInstalledUserScriptState(script)),
      autoUpdateEnabled: this.settings.autoUpdateEnabled === true,
      updatedAt: this.settings.updatedAt
    };
  }

  listScripts(): InstalledUserScriptState[] {
    return this.getSettings().scripts;
  }

  findScript(scriptId: string): InstalledUserScriptState | undefined {
    const record = this.settings.scripts.find((script: InstalledUserScriptState) => script.id === scriptId);
    return record === undefined ? undefined : cloneInstalledUserScriptState(record);
  }

  async saveInstalledState(state: InstalledUserScriptState): Promise<UserScriptSettings> {
    await this.initialize();
    const now = Date.now();
    const nextState = cloneInstalledUserScriptState(state);
    const nextScripts = this.settings.scripts
      .filter((script: InstalledUserScriptState) => script.id !== nextState.id)
      .concat(nextState)
      .sort((left: InstalledUserScriptState, right: InstalledUserScriptState) => left.createdAt - right.createdAt);
    return this.persistSettings({
      scripts: nextScripts,
      autoUpdateEnabled: this.settings.autoUpdateEnabled,
      updatedAt: now
    });
  }

  async setAutoUpdateEnabled(enabled: boolean): Promise<UserScriptSettings> {
    await this.initialize();
    if (this.settings.autoUpdateEnabled === enabled) {
      return this.getSettings();
    }
    return this.persistSettings({
      scripts: this.settings.scripts.map((script: InstalledUserScriptState) => cloneInstalledUserScriptState(script)),
      autoUpdateEnabled: enabled,
      updatedAt: Date.now()
    });
  }

  async deleteScript(scriptId: string): Promise<UserScriptSettings> {
    await this.initialize();
    const deletedAt = Date.now();
    return this.persistSettings({
      scripts: this.settings.scripts.filter((script: InstalledUserScriptState) => script.id !== scriptId),
      autoUpdateEnabled: this.settings.autoUpdateEnabled,
      updatedAt: deletedAt
    });
  }

  private normalizeSettings(value: UserScriptSettings | undefined): UserScriptSettings {
    return {
      scripts: this.normalizeScripts(value?.scripts ?? []),
      autoUpdateEnabled: value?.autoUpdateEnabled === true,
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeScripts(values: InstalledUserScriptState[]): InstalledUserScriptState[] {
    const results: InstalledUserScriptState[] = [];
    values.forEach((value: InstalledUserScriptState) => {
      const runAt: UserScriptRunAt = this.normalizeRunAt(value.runAt);
      const installSource: UserScriptInstallSource = value.installSource === 'url' ||
        value.installSource === 'file' ||
        value.installSource === 'gallery' ? value.installSource : 'paste';
      const grants: UserScriptGrant[] = this.normalizeGrants(value.grants);
      const record: InstalledUserScriptState = {
        id: String(value.id ?? '').trim(),
        name: String(value.name ?? '').trim(),
        namespace: String(value.namespace ?? '').trim(),
        version: String(value.version ?? '').trim(),
        description: String(value.description ?? '').trim(),
        iconUrl: this.normalizeIconUrl(value),
        source: String(value.source ?? ''),
        sourceUrl: String(value.sourceUrl ?? '').trim(),
        updateUrl: String(value.updateUrl ?? '').trim(),
        downloadUrl: String(value.downloadUrl ?? '').trim(),
        enabled: value.enabled !== false,
        matches: this.normalizeStringList(value.matches),
        includes: this.normalizeStringList(value.includes),
        excludeMatches: this.normalizeStringList(value.excludeMatches),
        excludes: this.normalizeStringList(value.excludes),
        grants: grants,
        requireUrls: this.normalizeStringList(value.requireUrls),
        requireSources: this.normalizeStringList(value.requireSources),
        resources: this.normalizeResources(value.resources),
        connectRules: this.normalizeStringList(value.connectRules),
        noframes: value.noframes === true,
        runAt: runAt,
        installSource: installSource,
        createdAt: this.normalizeTimestamp(value.createdAt),
        updatedAt: this.normalizeTimestamp(value.updatedAt),
        lastCheckedAt: this.normalizeTimestamp(value.lastCheckedAt)
      };
      const pendingUrlRecovery = record.installSource === 'url' &&
        record.enabled === false &&
        (record.sourceUrl.length > 0 || record.updateUrl.length > 0 || record.downloadUrl.length > 0);
      if (record.id.length > 0 && record.name.length > 0 && (record.source.length > 0 || pendingUrlRecovery)) {
        results.push(record);
      }
    });
    return results;
  }

  private normalizeGrants(value: UserScriptGrant[] | undefined): UserScriptGrant[] {
    if (!Array.isArray(value)) {
      return ['none'];
    }
    return this.capabilityContract.normalizeGrants(value);
  }

  private normalizeRunAt(value: UserScriptRunAt | string | undefined): UserScriptRunAt {
    if (value === 'document-start' ||
      value === 'document-idle' ||
      value === 'main-menu' ||
      value === 'tool-menu' ||
      value === 'context-menu') {
      return value;
    }
    return 'document-end';
  }

  private normalizeResources(value: UserScriptResourceRecord[] | undefined): UserScriptResourceRecord[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const results: UserScriptResourceRecord[] = [];
    value.forEach((resource: UserScriptResourceRecord) => {
      const record: UserScriptResourceRecord = {
        name: String(resource.name ?? '').trim(),
        url: String(resource.url ?? '').trim(),
        text: String(resource.text ?? ''),
        mimeType: String(resource.mimeType ?? '').trim(),
        contentBase64: typeof resource.contentBase64 === 'string' ? resource.contentBase64.trim() : undefined
      };
      if (record.name.length > 0 && record.url.length > 0) {
        results.push(record);
      }
    });
    return results;
  }

  private normalizeStringList(value: string[] | undefined): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    return value.map((item: string) => String(item ?? '').trim()).filter((item: string) => item.length > 0);
  }

  private parseSettings(value: string): UserScriptSettings {
    let parsed: UserScriptSettings;
    try {
      parsed = JSON.parse(value) as UserScriptSettings;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'parse-failed';
      throw new Error(`userscript-metadata-invalid-state: invalid-json:${message}`);
    }
    if (parsed === undefined || parsed === null || !Array.isArray(parsed.scripts) ||
      (parsed.autoUpdateEnabled !== undefined && typeof parsed.autoUpdateEnabled !== 'boolean') ||
      !this.isValidNonNegativeNumber(parsed.updatedAt)) {
      throw new Error('userscript-metadata-invalid-state: invalid-settings-shape');
    }
    const seenScriptIds: string[] = [];
    parsed.scripts.forEach((record: InstalledUserScriptState) => {
      this.validateScriptRecord(record, seenScriptIds);
      seenScriptIds.push(record.id.trim());
    });
    return parsed;
  }

  private validateScriptRecord(record: InstalledUserScriptState, seenScriptIds: string[]): void {
    if (record === undefined || record === null ||
      typeof record.id !== 'string' || record.id.trim().length === 0 ||
      seenScriptIds.includes(record.id.trim()) ||
      typeof record.name !== 'string' || record.name.trim().length === 0 ||
      typeof record.namespace !== 'string' ||
      typeof record.version !== 'string' ||
      typeof record.description !== 'string' ||
      (record.iconUrl !== undefined && typeof record.iconUrl !== 'string') ||
      typeof record.source !== 'string' ||
      typeof record.sourceUrl !== 'string' ||
      typeof record.updateUrl !== 'string' ||
      typeof record.downloadUrl !== 'string' ||
      typeof record.enabled !== 'boolean' ||
      !this.isValidStringList(record.matches) ||
      !this.isValidStringList(record.includes) ||
      !this.isValidOptionalStringList(record.excludeMatches) ||
      !this.isValidStringList(record.excludes) ||
      !this.isValidGrantList(record.grants) ||
      !this.isValidOptionalStringList(record.requireUrls) ||
      !this.isValidOptionalStringList(record.requireSources) ||
      !this.isValidOptionalResourceList(record.resources) ||
      !this.isValidOptionalStringList(record.connectRules) ||
      (record.noframes !== undefined && typeof record.noframes !== 'boolean') ||
      !this.isValidRunAt(record.runAt) ||
      !this.isValidInstallSource(record.installSource) ||
      !this.isValidNonNegativeNumber(record.createdAt) ||
      !this.isValidNonNegativeNumber(record.updatedAt) ||
      !this.isValidNonNegativeNumber(record.lastCheckedAt)) {
      throw new Error('userscript-metadata-invalid-state: invalid-script-record');
    }
    const pendingUrlRecovery = record.installSource === 'url' &&
      record.enabled === false &&
      (record.sourceUrl.trim().length > 0 ||
        record.updateUrl.trim().length > 0 ||
        record.downloadUrl.trim().length > 0);
    if (record.source.length === 0 && !pendingUrlRecovery) {
      throw new Error('userscript-metadata-invalid-state: invalid-script-record');
    }
  }

  private isValidStringList(value: string[] | undefined): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    return value.every((item: string) => typeof item === 'string' && item.trim().length > 0);
  }

  private isValidOptionalStringList(value: string[] | undefined): boolean {
    return value === undefined || this.isValidStringList(value);
  }

  private isValidGrantList(value: UserScriptGrant[] | undefined): boolean {
    if (!Array.isArray(value) || value.length === 0) {
      return false;
    }
    const seenGrants: UserScriptGrant[] = [];
    return value.every((grant: UserScriptGrant) => {
      if (typeof grant !== 'string' || this.capabilityContract.normalizeGrant(grant) !== grant ||
        seenGrants.includes(grant)) {
        return false;
      }
      seenGrants.push(grant);
      return true;
    });
  }

  private isValidOptionalResourceList(value: UserScriptResourceRecord[] | undefined): boolean {
    if (value === undefined) {
      return true;
    }
    if (!Array.isArray(value)) {
      return false;
    }
    return value.every((resource: UserScriptResourceRecord) => {
      return resource !== undefined && resource !== null &&
        typeof resource.name === 'string' && resource.name.trim().length > 0 &&
        typeof resource.url === 'string' && resource.url.trim().length > 0 &&
        typeof resource.text === 'string' &&
        typeof resource.mimeType === 'string' &&
        (resource.contentBase64 === undefined || typeof resource.contentBase64 === 'string');
    });
  }

  private isValidRunAt(value: UserScriptRunAt | string | undefined): boolean {
    return value === 'document-start' ||
      value === 'document-idle' ||
      value === 'document-end' ||
      value === 'main-menu' ||
      value === 'tool-menu' ||
      value === 'context-menu';
  }

  private isValidInstallSource(value: string | undefined): boolean {
    return value === 'paste' || value === 'url' || value === 'file' || value === 'gallery';
  }

  private isValidNonNegativeNumber(value: number | undefined): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0;
  }

  private async persistSettings(settings: UserScriptSettings): Promise<UserScriptSettings> {
    this.settings = this.normalizeSettings(settings);
    const store = await this.getStore();
    store.putSync(USER_SCRIPT_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    return this.getSettings();
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && value > 0 ? value : 0;
  }

  private normalizeIconUrl(value: InstalledUserScriptState): string {
    const iconUrl = String(value.iconUrl ?? '').trim();
    if (iconUrl.length > 0) {
      return this.iconService.resolveIconUrl(iconUrl, String(value.sourceUrl ?? ''));
    }
    return this.iconService.recoverIconUrl(String(value.source ?? ''), String(value.sourceUrl ?? ''));
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { PersonalizationSyncItemDeletionRecorder } from '../../common/models/PersonalizationSyncModels';
import {
  DEFAULT_SEARCH_ENGINE_ID,
  SEARCH_ENGINE_OPTIONS,
  SearchEngineFallbackSettings,
  SearchEngineId,
  SearchEngineOption,
  SearchEngineRecord,
  SearchEngineSettings,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { SearchEngineTemplateService } from '../../services/search/SearchEngineTemplateService';
import {
  SEARCH_ENGINE_PREFERENCES_NAME,
  SEARCH_ENGINE_SETTINGS_KEY,
  SEARCH_ENGINE_SETTINGS_REVISION_KEY
} from '../../common/constants/SearchPreferenceKeys';

const REMOTE_SEARCH_SUGGESTION_RESTORE_CUTOFF_AT: number = 1783186801000;
const DEFAULT_ENABLED_BUILT_IN_SEARCH_ENGINE_IDS: SearchEngineId[] = [
  'bing',
  'google',
  'duckduckgo',
  'baidu',
  'yandex'
];
const DEFAULT_FALLBACK_SEARCH_ENGINE_ID: SearchEngineId = 'baidu';

export type SearchEngineLocalChangeHandler = () => void;
export type DefaultSearchEngineChangeHandler = (engineId: SearchEngineId) => void;

export const DEFAULT_SEARCH_SUGGESTION_PREFERENCES: SearchSuggestionPreferences = {
  regularEnabled: true,
  privateEnabled: false,
  openTabsEnabled: false,
  bookmarksEnabled: false,
  shortcutsEnabled: false,
  historyEnabled: true,
  remoteEnabled: true
};

export class SearchEngineRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private templateService: SearchEngineTemplateService = new SearchEngineTemplateService();
  private settings: SearchEngineSettings = this.buildDefaultSettings();
  private deletionRecorder?: PersonalizationSyncItemDeletionRecorder;
  private localChangeHandler?: SearchEngineLocalChangeHandler;
  private defaultSearchEngineChangeHandler?: DefaultSearchEngineChangeHandler;
  private publishedDefaultSearchEngineId?: SearchEngineId;

  constructor(deletionRecorder?: PersonalizationSyncItemDeletionRecorder) {
    this.deletionRecorder = deletionRecorder;
  }

  setLocalChangeHandler(handler?: SearchEngineLocalChangeHandler): void {
    this.localChangeHandler = handler;
  }

  setDefaultSearchEngineChangeHandler(handler?: DefaultSearchEngineChangeHandler): void {
    this.defaultSearchEngineChangeHandler = handler;
  }

  async initialize(legacyDefaultSearchEngineId: SearchEngineId = DEFAULT_SEARCH_ENGINE_ID): Promise<SearchEngineSettings> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(SEARCH_ENGINE_SETTINGS_KEY, ''));
    const parsedSettings = this.parseSettings(rawSettings);
    this.settings = this.normalizeSettings(parsedSettings, legacyDefaultSearchEngineId);
    this.publishSettings();
    if (rawSettings.trim().length === 0 ||
      parsedSettings?.enabledBuiltInEngineIds === undefined ||
      parsedSettings?.fallbackSearch === undefined ||
      parsedSettings?.fallbackSearch?.noticeEnabled === undefined ||
      this.shouldRestoreRemoteSearchSuggestions(parsedSettings) ||
      this.settings.defaultSearchEngineId !== legacyDefaultSearchEngineId) {
      await this.persistSettings(this.settings);
    }
    return this.settings;
  }

  getSettings(): SearchEngineSettings {
    return this.cloneSettings(this.settings);
  }

  listEngines(): SearchEngineRecord[] {
    return this.buildAllEngines(
      this.settings.builtInEngineOrder,
      this.settings.enabledBuiltInEngineIds,
      this.settings.customEngines
    );
  }

  listBuiltInEngineCandidates(): SearchEngineRecord[] {
    return this.buildBuiltInEngines(this.settings.builtInEngineOrder);
  }

  getDefaultEngine(): SearchEngineRecord {
    return this.findEngine(this.settings.defaultSearchEngineId) ?? this.findEngine(DEFAULT_SEARCH_ENGINE_ID) ??
      this.buildBuiltInEngine(SEARCH_ENGINE_OPTIONS[0], 0);
  }

  findEngine(engineId: SearchEngineId): SearchEngineRecord | undefined {
    return this.listEngines().find((engine: SearchEngineRecord) => engine.id === engineId);
  }

  async setDefaultEngine(engineId: SearchEngineId): Promise<SearchEngineSettings> {
    const normalizedId = this.templateService.normalizeEngineId(engineId, this.listEngines());
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: normalizedId,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: this.ensureBuiltInEngineEnabled(
        this.settings.enabledBuiltInEngineIds,
        normalizedId
      ),
      customEngines: this.settings.customEngines.slice(),
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.normalizeFallbackSettings(
        this.settings.fallbackSearch,
        normalizedId,
        this.buildAllEngines(
          this.settings.builtInEngineOrder,
          this.ensureBuiltInEngineEnabled(this.settings.enabledBuiltInEngineIds, normalizedId),
          this.settings.customEngines
        )
      ),
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings, true);
  }

  async saveCustomEngine(
    engineId: SearchEngineId | undefined,
    name: string,
    searchUrlTemplate: string,
    iconUrl: string = ''
  ): Promise<SearchEngineSettings> {
    const validation = this.templateService.validateTemplate(searchUrlTemplate);
    if (!validation.valid) {
      throw new Error(validation.errorMessage);
    }
    const trimmedName = name.trim();
    const resolvedName = trimmedName.length > 0 ? trimmedName : validation.suggestedName;
    if (resolvedName.length === 0) {
      throw new Error('搜索引擎名称不能为空。');
    }
    const now = Date.now();
    const normalizedEngineId = this.resolveEditableCustomEngineId(engineId, resolvedName, now);
    const existing = this.settings.customEngines.find((engine: SearchEngineRecord) => engine.id === normalizedEngineId);
    const maxPosition = this.settings.customEngines.reduce((max: number, engine: SearchEngineRecord) => {
      return Math.max(max, engine.position);
    }, SEARCH_ENGINE_OPTIONS.length - 1);
    const nextRecord: SearchEngineRecord = {
      id: normalizedEngineId,
      kind: 'custom',
      name: resolvedName,
      searchUrlTemplate: validation.normalizedTemplate,
      homepageUrl: validation.homepageUrl,
      iconUrl: iconUrl.trim(),
      isEditable: true,
      position: existing?.position ?? maxPosition + 1,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now
    };
    const nextCustomEngines = this.settings.customEngines
      .filter((engine: SearchEngineRecord) => engine.id !== normalizedEngineId)
      .concat(nextRecord)
      .sort((left: SearchEngineRecord, right: SearchEngineRecord) => left.position - right.position);
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: this.settings.defaultSearchEngineId,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: this.settings.enabledBuiltInEngineIds.slice(),
      customEngines: nextCustomEngines,
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.cloneFallbackSettings(this.settings.fallbackSearch),
      updatedAt: now
    };
    return this.persistSettings(this.normalizeSettings(nextSettings, this.settings.defaultSearchEngineId), true);
  }

  async deleteCustomEngine(engineId: SearchEngineId): Promise<SearchEngineSettings> {
    const target = this.settings.customEngines.find((engine: SearchEngineRecord) => engine.id === engineId);
    if (target === undefined) {
      return this.getSettings();
    }
    const previous = this.getSettings();
    const nextDefault = this.settings.defaultSearchEngineId === engineId ? DEFAULT_SEARCH_ENGINE_ID :
      this.settings.defaultSearchEngineId;
    const deletedAt = Date.now();
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: nextDefault,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: this.ensureBuiltInEngineEnabled(
        this.settings.enabledBuiltInEngineIds,
        nextDefault
      ),
      customEngines: this.settings.customEngines.filter((engine: SearchEngineRecord) => engine.id !== engineId),
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.cloneFallbackSettings(this.settings.fallbackSearch),
      updatedAt: deletedAt
    };
    const settings = await this.persistSettings(this.normalizeSettings(nextSettings, nextDefault));
    try {
      await this.deletionRecorder?.(engineId, deletedAt);
    } catch (error) {
      await this.persistSettings(previous);
      throw new Error(error instanceof Error ? error.message : JSON.stringify(error));
    }
    this.notifyLocalChange();
    return settings;
  }

  async updateSearchSuggestionPreferences(preferences: SearchSuggestionPreferences): Promise<SearchEngineSettings> {
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: this.settings.defaultSearchEngineId,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: this.settings.enabledBuiltInEngineIds.slice(),
      customEngines: this.settings.customEngines.slice(),
      searchSuggestions: this.normalizeSuggestionPreferences(preferences),
      fallbackSearch: this.cloneFallbackSettings(this.settings.fallbackSearch),
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings, true);
  }

  async updateSearchFallbackSettings(fallbackSearch: SearchEngineFallbackSettings): Promise<SearchEngineSettings> {
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: this.settings.defaultSearchEngineId,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: this.settings.enabledBuiltInEngineIds.slice(),
      customEngines: this.settings.customEngines.slice(),
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.normalizeFallbackSettings(
        fallbackSearch,
        this.settings.defaultSearchEngineId,
        this.listEngines()
      ),
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings, true);
  }

  async setSearchFallbackEnabled(enabled: boolean): Promise<SearchEngineSettings> {
    const nextFallback = this.normalizeFallbackSettings(
      {
        enabled: enabled,
        fallbackSearchEngineId: this.settings.fallbackSearch.fallbackSearchEngineId,
        noticeEnabled: this.settings.fallbackSearch.noticeEnabled
      },
      this.settings.defaultSearchEngineId,
      this.listEngines()
    );
    return this.updateSearchFallbackSettings(nextFallback);
  }

  async setSearchFallbackNoticeEnabled(enabled: boolean): Promise<SearchEngineSettings> {
    const nextFallback = this.normalizeFallbackSettings(
      {
        enabled: this.settings.fallbackSearch.enabled,
        fallbackSearchEngineId: this.settings.fallbackSearch.fallbackSearchEngineId,
        noticeEnabled: enabled
      },
      this.settings.defaultSearchEngineId,
      this.listEngines()
    );
    return this.updateSearchFallbackSettings(nextFallback);
  }

  async setFallbackEngine(engineId: SearchEngineId): Promise<SearchEngineSettings> {
    const enabledBuiltInEngineIds = this.ensureBuiltInEngineEnabled(this.settings.enabledBuiltInEngineIds, engineId);
    const engines = this.buildAllEngines(
      this.settings.builtInEngineOrder,
      enabledBuiltInEngineIds,
      this.settings.customEngines
    );
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: this.settings.defaultSearchEngineId,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: enabledBuiltInEngineIds,
      customEngines: this.settings.customEngines.slice(),
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.normalizeFallbackSettings(
        {
          enabled: this.settings.fallbackSearch.enabled,
          fallbackSearchEngineId: engineId,
          noticeEnabled: this.settings.fallbackSearch.noticeEnabled
        },
        this.settings.defaultSearchEngineId,
        engines
      ),
      updatedAt: Date.now()
    };
    return this.persistSettings(nextSettings, true);
  }

  async reorderBuiltInEngines(engineIds: SearchEngineId[]): Promise<SearchEngineSettings> {
    const nextOrder = this.normalizeBuiltInEngineOrder(engineIds);
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: this.settings.defaultSearchEngineId,
      builtInEngineOrder: nextOrder,
      enabledBuiltInEngineIds: this.settings.enabledBuiltInEngineIds.slice(),
      customEngines: this.settings.customEngines.slice(),
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.cloneFallbackSettings(this.settings.fallbackSearch),
      updatedAt: Date.now()
    };
    return this.persistSettings(this.normalizeSettings(nextSettings, nextSettings.defaultSearchEngineId), true);
  }

  async setBuiltInEngineEnabled(engineId: SearchEngineId, enabled: boolean): Promise<SearchEngineSettings> {
    const currentEnabled = this.settings.enabledBuiltInEngineIds.slice();
    const candidate = this.normalizeBuiltInEngineId(engineId);
    if (candidate.length <= 0) {
      return this.getSettings();
    }
    let nextEnabled: SearchEngineId[] = [];
    if (enabled) {
      nextEnabled = this.ensureBuiltInEngineEnabled(currentEnabled, candidate);
    } else {
      nextEnabled = currentEnabled.filter((value: SearchEngineId): boolean => value !== candidate);
      if (candidate === this.settings.defaultSearchEngineId) {
        nextEnabled = this.ensureBuiltInEngineEnabled(nextEnabled, candidate);
      }
    }
    const nextSettings: SearchEngineSettings = {
      defaultSearchEngineId: this.settings.defaultSearchEngineId,
      builtInEngineOrder: this.settings.builtInEngineOrder.slice(),
      enabledBuiltInEngineIds: nextEnabled,
      customEngines: this.settings.customEngines.slice(),
      searchSuggestions: this.cloneSuggestionPreferences(this.settings.searchSuggestions),
      fallbackSearch: this.cloneFallbackSettings(this.settings.fallbackSearch),
      updatedAt: Date.now()
    };
    return this.persistSettings(this.normalizeSettings(nextSettings, nextSettings.defaultSearchEngineId), true);
  }

  async replaceSettings(settings: SearchEngineSettings): Promise<SearchEngineSettings> {
    return this.persistSettings(this.normalizeSettings(settings, settings.defaultSearchEngineId));
  }

  isLocalSuggestionSourceAllowed(dataScope: string | undefined): boolean {
    return dataScope !== 'session_ephemeral';
  }

  private resolveEditableCustomEngineId(engineId: SearchEngineId | undefined, name: string, now: number): SearchEngineId {
    const candidate = (engineId ?? '').trim();
    if (candidate.length > 0 && !this.templateService.isBuiltInEngineId(candidate)) {
      return candidate;
    }
    return this.templateService.buildCustomEngineId(name, now);
  }

  private buildAllEngines(
    builtInEngineOrder: SearchEngineId[] = [],
    enabledBuiltInEngineIds: SearchEngineId[] = [],
    customEngines: SearchEngineRecord[] = []
  ): SearchEngineRecord[] {
    const enabledIds = this.normalizeEnabledBuiltInEngineIds(enabledBuiltInEngineIds, DEFAULT_SEARCH_ENGINE_ID);
    return this.buildBuiltInEngines(builtInEngineOrder).filter((engine: SearchEngineRecord): boolean => {
      return enabledIds.indexOf(engine.id) >= 0;
    }).concat(customEngines).sort((left: SearchEngineRecord, right: SearchEngineRecord) => left.position - right.position);
  }

  private buildBuiltInEngines(builtInEngineOrder: SearchEngineId[] = []): SearchEngineRecord[] {
    return this.buildOrderedSearchEngineOptions(builtInEngineOrder).map((option: SearchEngineOption, index: number) => {
      return this.buildBuiltInEngine(option, index);
    });
  }

  private buildOrderedSearchEngineOptions(builtInEngineOrder: SearchEngineId[]): SearchEngineOption[] {
    const ordered: SearchEngineOption[] = [];
    const remaining = SEARCH_ENGINE_OPTIONS.slice();
    builtInEngineOrder.forEach((engineId: SearchEngineId) => {
      const index = remaining.findIndex((option: SearchEngineOption): boolean => option.id === engineId);
      if (index >= 0) {
        ordered.push(remaining[index]);
        remaining.splice(index, 1);
      }
    });
    return ordered.concat(remaining);
  }

  private buildBuiltInEngine(option: SearchEngineOption, index: number): SearchEngineRecord {
    const now = 0;
    return {
      id: option.id,
      kind: 'built_in',
      name: option.name,
      searchUrlTemplate: option.searchUrlTemplate ?? '',
      homepageUrl: option.homepageUrl ?? '',
      iconUrl: option.iconUrl ?? '',
      availabilityProbeUrl: option.availabilityProbeUrl ?? '',
      availabilityExpectedStatus: option.availabilityExpectedStatus,
      isEditable: false,
      position: index,
      createdAt: now,
      updatedAt: now
    };
  }

  private normalizeSettings(parsed: SearchEngineSettings | undefined, legacyDefaultSearchEngineId: SearchEngineId): SearchEngineSettings {
    const builtInEngineOrder = this.normalizeBuiltInEngineOrder(parsed?.builtInEngineOrder ?? []);
    const enabledBuiltInEngineIds = this.normalizeEnabledBuiltInEngineIds(
      parsed?.enabledBuiltInEngineIds,
      parsed?.defaultSearchEngineId ?? legacyDefaultSearchEngineId
    );
    const customEngines = this.normalizeCustomEngines(parsed?.customEngines ?? []);
    const allEngines = this.buildAllEngines(builtInEngineOrder, enabledBuiltInEngineIds, customEngines);
    const preferredDefault = (parsed?.defaultSearchEngineId ?? legacyDefaultSearchEngineId).trim();
    const defaultSearchEngineId = this.templateService.normalizeEngineId(preferredDefault, allEngines);
    const searchSuggestions = this.normalizeSuggestionPreferences(parsed?.searchSuggestions);
    const normalizedEnabledBuiltInEngineIds = this.normalizeEnabledBuiltInEngineIds(
      enabledBuiltInEngineIds,
      defaultSearchEngineId
    );
    const normalizedAllEngines = this.buildAllEngines(
      builtInEngineOrder,
      normalizedEnabledBuiltInEngineIds,
      customEngines
    );
    return {
      defaultSearchEngineId: defaultSearchEngineId,
      builtInEngineOrder: builtInEngineOrder,
      enabledBuiltInEngineIds: normalizedEnabledBuiltInEngineIds,
      customEngines: customEngines,
      searchSuggestions: this.shouldRestoreRemoteSearchSuggestions(parsed) ?
        this.restoreRemoteSearchSuggestions(searchSuggestions) :
        searchSuggestions,
      fallbackSearch: this.normalizeFallbackSettings(
        parsed?.fallbackSearch,
        defaultSearchEngineId,
        normalizedAllEngines
      ),
      updatedAt: this.normalizeTimestamp(parsed?.updatedAt)
    };
  }

  private normalizeCustomEngines(values: SearchEngineRecord[]): SearchEngineRecord[] {
    const results: SearchEngineRecord[] = [];
    values.forEach((value: SearchEngineRecord, index: number) => {
      const validation = this.templateService.validateTemplate(value.searchUrlTemplate ?? '');
      const id = (value.id ?? '').trim();
      const name = (value.name ?? '').trim();
      if (id.length === 0 || name.length === 0 || !validation.valid || this.templateService.isBuiltInEngineId(id)) {
        return;
      }
      results.push({
        id: id,
        kind: 'custom',
        name: name,
        searchUrlTemplate: validation.normalizedTemplate,
        homepageUrl: (value.homepageUrl ?? validation.homepageUrl).trim(),
        iconUrl: (value.iconUrl ?? '').trim(),
        availabilityProbeUrl: (value.availabilityProbeUrl ?? '').trim(),
        availabilityExpectedStatus: this.normalizeExpectedStatus(value.availabilityExpectedStatus),
        isEditable: true,
        position: typeof value.position === 'number' ? value.position : SEARCH_ENGINE_OPTIONS.length + index,
        createdAt: this.normalizeTimestamp(value.createdAt),
        updatedAt: this.normalizeTimestamp(value.updatedAt)
      });
    });
    return results.sort((left: SearchEngineRecord, right: SearchEngineRecord) => left.position - right.position);
  }

  private normalizeBuiltInEngineOrder(values: SearchEngineId[] | undefined): SearchEngineId[] {
    const ordered: SearchEngineId[] = [];
    const fallback: SearchEngineId[] = SEARCH_ENGINE_OPTIONS.map((option: SearchEngineOption) => option.id);
    if (values !== undefined) {
      values.forEach((value: SearchEngineId) => {
        const candidate = (value ?? '').trim();
        if (candidate.length > 0 &&
          fallback.indexOf(candidate) >= 0 &&
          ordered.indexOf(candidate) < 0) {
          ordered.push(candidate);
        }
      });
    }
    fallback.forEach((engineId: SearchEngineId) => {
      if (ordered.indexOf(engineId) < 0) {
        ordered.push(engineId);
      }
    });
    return ordered;
  }

  private normalizeEnabledBuiltInEngineIds(
    values: SearchEngineId[] | undefined,
    defaultSearchEngineId: SearchEngineId
  ): SearchEngineId[] {
    const source = values !== undefined && values.length > 0
      ? values
      : DEFAULT_ENABLED_BUILT_IN_SEARCH_ENGINE_IDS;
    let enabled: SearchEngineId[] = [];
    source.forEach((value: SearchEngineId) => {
      const candidate = this.normalizeBuiltInEngineId(value);
      if (candidate.length > 0 && enabled.indexOf(candidate) < 0) {
        enabled.push(candidate);
      }
    });
    enabled = this.ensureBuiltInEngineEnabled(enabled, defaultSearchEngineId);
    if (enabled.length <= 0) {
      enabled.push(DEFAULT_SEARCH_ENGINE_ID);
    }
    return enabled;
  }

  private ensureBuiltInEngineEnabled(values: SearchEngineId[], engineId: SearchEngineId): SearchEngineId[] {
    const candidate = this.normalizeBuiltInEngineId(engineId);
    const enabled = values.slice();
    if (candidate.length > 0 && enabled.indexOf(candidate) < 0) {
      enabled.push(candidate);
    }
    return enabled;
  }

  private normalizeBuiltInEngineId(engineId: SearchEngineId): SearchEngineId {
    const candidate = (engineId ?? '').trim();
    if (SEARCH_ENGINE_OPTIONS.some((option: SearchEngineOption): boolean => option.id === candidate)) {
      return candidate;
    }
    return '';
  }

  private normalizeSuggestionPreferences(value: SearchSuggestionPreferences | undefined): SearchSuggestionPreferences {
    return {
      regularEnabled: typeof value?.regularEnabled === 'boolean'
        ? value.regularEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.regularEnabled,
      privateEnabled: typeof value?.privateEnabled === 'boolean'
        ? value.privateEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.privateEnabled,
      openTabsEnabled: typeof value?.openTabsEnabled === 'boolean'
        ? value.openTabsEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.openTabsEnabled,
      bookmarksEnabled: typeof value?.bookmarksEnabled === 'boolean'
        ? value.bookmarksEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.bookmarksEnabled,
      shortcutsEnabled: typeof value?.shortcutsEnabled === 'boolean'
        ? value.shortcutsEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.shortcutsEnabled,
      historyEnabled: typeof value?.historyEnabled === 'boolean'
        ? value.historyEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.historyEnabled,
      remoteEnabled: typeof value?.remoteEnabled === 'boolean'
        ? value.remoteEnabled
        : DEFAULT_SEARCH_SUGGESTION_PREFERENCES.remoteEnabled
    };
  }

  private normalizeFallbackSettings(
    value: SearchEngineFallbackSettings | undefined,
    defaultSearchEngineId: SearchEngineId,
    availableEngines: SearchEngineRecord[]
  ): SearchEngineFallbackSettings {
    const fallbackSearchEngineId = this.resolveFallbackEngineId(
      value?.fallbackSearchEngineId,
      defaultSearchEngineId,
      availableEngines
    );
    const enabled = value?.enabled === true &&
      fallbackSearchEngineId.length > 0 &&
      fallbackSearchEngineId !== defaultSearchEngineId;
    return {
      enabled: enabled,
      fallbackSearchEngineId: fallbackSearchEngineId,
      noticeEnabled: value?.noticeEnabled !== false
    };
  }

  private resolveFallbackEngineId(
    preferredEngineId: SearchEngineId | undefined,
    defaultSearchEngineId: SearchEngineId,
    availableEngines: SearchEngineRecord[]
  ): SearchEngineId {
    const preferred = (preferredEngineId ?? '').trim();
    if (preferred.length > 0 &&
      preferred !== defaultSearchEngineId &&
      availableEngines.some((engine: SearchEngineRecord): boolean => engine.id === preferred)) {
      return preferred;
    }
    const preferredBuiltIn = defaultSearchEngineId === 'google' ? DEFAULT_FALLBACK_SEARCH_ENGINE_ID :
      DEFAULT_SEARCH_ENGINE_ID;
    const builtInCandidate = availableEngines.find((engine: SearchEngineRecord): boolean => {
      return engine.id === preferredBuiltIn && engine.id !== defaultSearchEngineId;
    });
    if (builtInCandidate !== undefined) {
      return builtInCandidate.id;
    }
    const firstDifferent = availableEngines.find((engine: SearchEngineRecord): boolean => {
      return engine.id !== defaultSearchEngineId;
    });
    return firstDifferent?.id ?? '';
  }

  private cloneFallbackSettings(value: SearchEngineFallbackSettings): SearchEngineFallbackSettings {
    return {
      enabled: value.enabled,
      fallbackSearchEngineId: value.fallbackSearchEngineId,
      noticeEnabled: value.noticeEnabled !== false
    };
  }

  private normalizeExpectedStatus(value: number | undefined): number | undefined {
    if (typeof value === 'number' && value >= 100 && value <= 599) {
      return Math.floor(value);
    }
    return undefined;
  }

  private shouldRestoreRemoteSearchSuggestions(settings: SearchEngineSettings | undefined): boolean {
    const preferences = this.normalizeSuggestionPreferences(settings?.searchSuggestions);
    return this.normalizeTimestamp(settings?.updatedAt) < REMOTE_SEARCH_SUGGESTION_RESTORE_CUTOFF_AT &&
      preferences.regularEnabled &&
      !preferences.privateEnabled &&
      !preferences.openTabsEnabled &&
      !preferences.bookmarksEnabled &&
      !preferences.shortcutsEnabled &&
      preferences.historyEnabled &&
      !preferences.remoteEnabled;
  }

  private restoreRemoteSearchSuggestions(preferences: SearchSuggestionPreferences): SearchSuggestionPreferences {
    return {
      regularEnabled: preferences.regularEnabled,
      privateEnabled: preferences.privateEnabled,
      openTabsEnabled: preferences.openTabsEnabled,
      bookmarksEnabled: preferences.bookmarksEnabled,
      shortcutsEnabled: preferences.shortcutsEnabled,
      historyEnabled: preferences.historyEnabled,
      remoteEnabled: true
    };
  }

  private cloneSuggestionPreferences(value: SearchSuggestionPreferences): SearchSuggestionPreferences {
    return {
      regularEnabled: value.regularEnabled,
      privateEnabled: value.privateEnabled,
      openTabsEnabled: value.openTabsEnabled,
      bookmarksEnabled: value.bookmarksEnabled,
      shortcutsEnabled: value.shortcutsEnabled,
      historyEnabled: value.historyEnabled,
      remoteEnabled: value.remoteEnabled
    };
  }

  private parseSettings(value: string): SearchEngineSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as SearchEngineSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private buildDefaultSettings(): SearchEngineSettings {
    return {
      defaultSearchEngineId: DEFAULT_SEARCH_ENGINE_ID,
      builtInEngineOrder: this.normalizeBuiltInEngineOrder([]),
      enabledBuiltInEngineIds: this.normalizeEnabledBuiltInEngineIds(undefined, DEFAULT_SEARCH_ENGINE_ID),
      customEngines: [],
      searchSuggestions: this.cloneSuggestionPreferences(DEFAULT_SEARCH_SUGGESTION_PREFERENCES),
      fallbackSearch: this.normalizeFallbackSettings(
        undefined,
        DEFAULT_SEARCH_ENGINE_ID,
        this.buildAllEngines(
          this.normalizeBuiltInEngineOrder([]),
          this.normalizeEnabledBuiltInEngineIds(undefined, DEFAULT_SEARCH_ENGINE_ID),
          []
        )
      ),
      updatedAt: 0
    };
  }

  private cloneSettings(settings: SearchEngineSettings): SearchEngineSettings {
    return {
      defaultSearchEngineId: settings.defaultSearchEngineId,
      builtInEngineOrder: this.normalizeBuiltInEngineOrder(settings.builtInEngineOrder),
      enabledBuiltInEngineIds: this.normalizeEnabledBuiltInEngineIds(
        settings.enabledBuiltInEngineIds,
        settings.defaultSearchEngineId
      ),
      customEngines: settings.customEngines.map((engine: SearchEngineRecord) => {
        return this.cloneEngine(engine);
      }),
      searchSuggestions: this.cloneSuggestionPreferences(settings.searchSuggestions),
      fallbackSearch: this.normalizeFallbackSettings(
        settings.fallbackSearch,
        settings.defaultSearchEngineId,
        this.buildAllEngines(
          settings.builtInEngineOrder,
          settings.enabledBuiltInEngineIds,
          settings.customEngines
        )
      ),
      updatedAt: settings.updatedAt
    };
  }

  private async persistSettings(
    settings: SearchEngineSettings,
    notifyLocalChange: boolean = false
  ): Promise<SearchEngineSettings> {
    this.settings = this.cloneSettings(settings);
    const store = await this.getStore();
    store.putSync(SEARCH_ENGINE_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    this.publishSettings();
    if (notifyLocalChange) {
      this.notifyLocalChange();
    }
    return this.getSettings();
  }

  private notifyLocalChange(): void {
    this.localChangeHandler?.();
  }

  private publishSettings(): void {
    const nextRevision = (AppStorage.get<number>(SEARCH_ENGINE_SETTINGS_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(SEARCH_ENGINE_SETTINGS_REVISION_KEY, nextRevision);
    if (this.publishedDefaultSearchEngineId !== this.settings.defaultSearchEngineId) {
      this.publishedDefaultSearchEngineId = this.settings.defaultSearchEngineId;
      this.defaultSearchEngineChangeHandler?.(this.settings.defaultSearchEngineId);
    }
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && value > 0 ? value : 0;
  }

  private cloneEngine(engine: SearchEngineRecord): SearchEngineRecord {
    return {
      id: engine.id,
      kind: engine.kind,
      name: engine.name,
      searchUrlTemplate: engine.searchUrlTemplate,
      homepageUrl: engine.homepageUrl,
      iconUrl: engine.iconUrl,
      availabilityProbeUrl: engine.availabilityProbeUrl,
      availabilityExpectedStatus: engine.availabilityExpectedStatus,
      isEditable: engine.isEditable,
      position: engine.position,
      createdAt: engine.createdAt,
      updatedAt: engine.updatedAt
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), SEARCH_ENGINE_PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

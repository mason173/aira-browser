import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchEngineSettings,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { ExternalAppSearchPreferencesRepository } from '../../data/search/ExternalAppSearchPreferencesRepository';
import { QuickSearchSwitchPreferencesRepository } from '../../data/search/QuickSearchSwitchPreferencesRepository';
import { SearchEngineRepository } from '../../data/search/SearchEngineRepository';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';

export class SearchSettingsBoundary {
  dataScope: BrowserDataScope | string;
  privacyMode: BrowserSessionPrivacyMode | string;

  constructor(dataScope: BrowserDataScope | string = '', privacyMode: BrowserSessionPrivacyMode | string = '') {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
  }
}

export class SearchEngineSettingsCoordinator {
  private searchEngineRepository: SearchEngineRepository;
  private preferencesRepository: PreferencesRepository;
  private quickSearchSwitchRepository: QuickSearchSwitchPreferencesRepository;
  private externalAppSearchRepository: ExternalAppSearchPreferencesRepository;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    searchEngineRepository: SearchEngineRepository,
    preferencesRepository: PreferencesRepository,
    quickSearchSwitchRepository: QuickSearchSwitchPreferencesRepository,
    externalAppSearchRepository: ExternalAppSearchPreferencesRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.searchEngineRepository = searchEngineRepository;
    this.preferencesRepository = preferencesRepository;
    this.quickSearchSwitchRepository = quickSearchSwitchRepository;
    this.externalAppSearchRepository = externalAppSearchRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  getDefaultEngineId(): SearchEngineId {
    return this.searchEngineRepository.getSettings().defaultSearchEngineId;
  }

  async setFallbackEnabled(
    enabled: boolean,
    boundary: SearchSettingsBoundary
  ): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.searchEngineRepository.setSearchFallbackEnabled(enabled);
  }

  async setDefaultEngine(engineId: SearchEngineId, boundary: SearchSettingsBoundary): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    const settings = await this.searchEngineRepository.setDefaultEngine(engineId);
    await this.preferencesRepository.updateSearchEngine(settings.defaultSearchEngineId);
    return settings;
  }

  async saveCustomEngine(
    engineId: SearchEngineId | undefined,
    name: string,
    searchUrlTemplate: string,
    boundary: SearchSettingsBoundary
  ): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.searchEngineRepository.saveCustomEngine(engineId, name, searchUrlTemplate);
  }

  async deleteCustomEngine(
    engineId: SearchEngineId,
    boundary: SearchSettingsBoundary
  ): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    const settings = await this.searchEngineRepository.deleteCustomEngine(engineId);
    await this.preferencesRepository.updateSearchEngine(settings.defaultSearchEngineId);
    return settings;
  }

  reorderBuiltInEngines(
    engineIds: SearchEngineId[],
    boundary: SearchSettingsBoundary
  ): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.searchEngineRepository.reorderBuiltInEngines(engineIds);
  }

  async setBuiltInEngineEnabled(
    engineId: SearchEngineId,
    enabled: boolean,
    boundary: SearchSettingsBoundary
  ): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    const settings = await this.searchEngineRepository.setBuiltInEngineEnabled(engineId, enabled);
    await this.preferencesRepository.updateSearchEngine(settings.defaultSearchEngineId);
    return settings;
  }

  setFallbackEngine(engineId: SearchEngineId, boundary: SearchSettingsBoundary): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.searchEngineRepository.setFallbackEngine(engineId);
  }

  setFallbackNoticeEnabled(enabled: boolean, boundary: SearchSettingsBoundary): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.searchEngineRepository.setSearchFallbackNoticeEnabled(enabled);
  }

  async updateSuggestionPreferences(
    preferences: SearchSuggestionPreferences,
    boundary: SearchSettingsBoundary
  ): Promise<SearchEngineSettings> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    const settings = await this.searchEngineRepository.updateSearchSuggestionPreferences(preferences);
    await this.preferencesRepository.updateSearchSuggestionPreferences(settings.searchSuggestions);
    return settings;
  }

  setQuickSearchSwitchingEnabled(enabled: boolean, boundary: SearchSettingsBoundary): Promise<boolean> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.quickSearchSwitchRepository.setEnabled(enabled);
  }

  setExternalAppSearchEnabled(
    enabled: boolean,
    boundary: SearchSettingsBoundary
  ): Promise<ExternalAppSearchPreferences> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.externalAppSearchRepository.setEnabled(enabled);
  }

  setExternalAppSearchTargetEnabled(
    targetId: ExternalAppSearchTargetId,
    enabled: boolean,
    boundary: SearchSettingsBoundary
  ): Promise<ExternalAppSearchPreferences> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.externalAppSearchRepository.setTargetEnabled(targetId, enabled);
  }

  setExternalAppSearchTargetOrder(
    targetOrder: ExternalAppSearchTargetId[],
    boundary: SearchSettingsBoundary
  ): Promise<ExternalAppSearchPreferences> {
    this.ensureDevicePreferenceWriteAllowed(boundary);
    return this.externalAppSearchRepository.setTargetOrder(targetOrder);
  }

  private ensureDevicePreferenceWriteAllowed(boundary: SearchSettingsBoundary): void {
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: boundary.dataScope,
        privacyMode: boundary.privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('Search device preference write privacy effect was not allowed.');
    }
  }

}

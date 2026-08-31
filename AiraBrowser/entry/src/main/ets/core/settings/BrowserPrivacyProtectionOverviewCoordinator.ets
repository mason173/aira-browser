import { AdBlockSettings } from '../../common/models/BrowserModels';
import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  BrowserPrivacyProtectionOverviewState,
  BrowserPrivacyProtectionOverviewViewModel
} from './BrowserPrivacyProtectionOverviewViewModel';

const PRIVACY_OVERVIEW_DAY_COUNT: number = 7;

export class BrowserPrivacyProtectionOverviewCoordinator {
  private readonly adBlockRepository: AdBlockRepository;
  private readonly preferencesRepository: PreferencesRepository;
  private readonly viewModel: BrowserPrivacyProtectionOverviewViewModel =
    new BrowserPrivacyProtectionOverviewViewModel();

  constructor(adBlockRepository: AdBlockRepository, preferencesRepository: PreferencesRepository) {
    this.adBlockRepository = adBlockRepository;
    this.preferencesRepository = preferencesRepository;
  }

  buildState(selectedDayIndex: number = PRIVACY_OVERVIEW_DAY_COUNT - 1, now: number = Date.now()):
    BrowserPrivacyProtectionOverviewState {
    const settings: AdBlockSettings = this.adBlockRepository.getSettings();
    return this.viewModel.buildState({
      activities: this.adBlockRepository.getDailyProtectionActivityTimeline(PRIVACY_OVERVIEW_DAY_COUNT, now),
      selectedDayIndex: selectedDayIndex,
      filterEnabled: settings.preferences.enabled,
      enhancedTrackingProtectionEnabled:
        this.preferencesRepository.getPreferences().general.enhancedTrackingProtectionEnabled === true
    });
  }

  refreshState(selectedDayIndex: number = PRIVACY_OVERVIEW_DAY_COUNT - 1):
    Promise<BrowserPrivacyProtectionOverviewState> {
    return this.adBlockRepository.initializeMetadata()
      .then((): BrowserPrivacyProtectionOverviewState => this.buildState(selectedDayIndex));
  }
}

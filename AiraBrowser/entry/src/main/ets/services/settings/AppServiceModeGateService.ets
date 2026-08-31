import { BrowserAppServiceMode } from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

export class AppServiceModeGateService {
  private preferencesRepository: PreferencesRepository;

  constructor(preferencesRepository: PreferencesRepository) {
    this.preferencesRepository = preferencesRepository;
  }

  getMode(): BrowserAppServiceMode {
    return this.preferencesRepository.getPreferences().appServiceMode;
  }

  isFullMode(): boolean {
    return this.getMode() !== 'basic';
  }

  canUseOptionalService(): boolean {
    return this.isFullMode();
  }
}

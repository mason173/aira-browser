import { BrowserHomePageStyle } from '../../common/models/HomePagePresentationSettingsModels';
import { HomePagePresentationSettingsRepository } from '../../data/preferences/HomePagePresentationSettingsRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { CustomHomepageSettingsCoordinator } from './CustomHomepageSettingsCoordinator';
import { HomePageSettingsCoordinator } from '../settings/HomePageSettingsCoordinator';
import { resolveSystemHomepageToolbarChrome } from './SystemHomepageStyleCatalog';

/**
 * Picking a built-in homepage writes two device-local stores: which homepage the new tab
 * renders (custom homepage repository) and how that frame looks (homepage presentation
 * settings). Both stay out of Personalization Sync.
 *
 * The recovery-entry guard runs last, so the chosen frame never ends up without a way back
 * to homepage settings: the centered frame pins its settings tile, and the classic frame
 * forces its bottom settings button on when favorites and recently closed are both off.
 */
export class SystemHomepageSelectionService {
  private customHomepageCoordinator: CustomHomepageSettingsCoordinator;
  private presentationRepository: HomePagePresentationSettingsRepository;
  private recoveryEntryGuard: HomePageSettingsCoordinator;
  private preferencesRepository: PreferencesRepository;

  constructor(
    customHomepageCoordinator: CustomHomepageSettingsCoordinator,
    presentationRepository: HomePagePresentationSettingsRepository,
    recoveryEntryGuard: HomePageSettingsCoordinator,
    preferencesRepository: PreferencesRepository
  ) {
    this.customHomepageCoordinator = customHomepageCoordinator;
    this.presentationRepository = presentationRepository;
    this.recoveryEntryGuard = recoveryEntryGuard;
    this.preferencesRepository = preferencesRepository;
  }

  async selectSystemHomepageStyle(style: BrowserHomePageStyle): Promise<void> {
    await this.customHomepageCoordinator.selectSystemHomepage();
    await this.presentationRepository.setHomePageStyle(style);
    await this.preferencesRepository.updateToolbarChromeStyle(resolveSystemHomepageToolbarChrome(style));
    await this.recoveryEntryGuard.ensureRecoveryEntryAvailable();
  }
}

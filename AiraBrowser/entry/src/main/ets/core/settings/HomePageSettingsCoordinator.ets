import {
  BrowserAppearanceSettings,
  BrowserHomeShortcutLayoutDensity
} from '../../common/models/BrowserModels';
import { HomePagePresentationSettings } from '../../common/models/HomePagePresentationSettingsModels';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import { HomePagePresentationSettingsRepository } from '../../data/preferences/HomePagePresentationSettingsRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { CustomHomepageSettingsCoordinator } from '../customhome/CustomHomepageSettingsCoordinator';
import {
  HomePageRecoveryEntry,
  HomePageRecoveryEntryDecision,
  HomePageRecoveryEntryPolicyService
} from '../../services/settings/HomePageRecoveryEntryPolicyService';
import { HomeRecentlyClosedSettingsViewModel } from './HomeRecentlyClosedSettingsViewModel';
import { SiteIconAppearanceSettingsViewModel } from './SiteIconAppearanceSettingsViewModel';

export const HOME_RECENTLY_CLOSED_LIMIT_OPTIONS: number[] = [3, 5, 8, 12, 24];

export interface HomePageSettingsSnapshot {
  showFavorites: boolean;
  compactFavorites: boolean;
  showFavoritesTitle: boolean;
  iconSizeRatio: number;
  iconCornerRadiusRatio: number;
  showShortcutNames: boolean;
  showRecentlyClosed: boolean;
  showRecentlyClosedTitle: boolean;
  recentlyClosedLimit: number;
  showSystemSearch: boolean;
  hideSystemSearchOnScroll: boolean;
  showSettingsButton: boolean;
}

export class HomePageSettingsCoordinator {
  private preferencesRepository: PreferencesRepository;
  private customHomepageRepository: CustomHomepageRepository;
  private presentationRepository: HomePagePresentationSettingsRepository;
  private customHomepageCoordinator: CustomHomepageSettingsCoordinator;
  private recentlyClosedViewModel: HomeRecentlyClosedSettingsViewModel =
    new HomeRecentlyClosedSettingsViewModel();
  private iconAppearanceViewModel: SiteIconAppearanceSettingsViewModel =
    new SiteIconAppearanceSettingsViewModel();
  private recoveryEntryPolicyService: HomePageRecoveryEntryPolicyService =
    new HomePageRecoveryEntryPolicyService();

  constructor(
    preferencesRepository: PreferencesRepository,
    customHomepageRepository: CustomHomepageRepository,
    presentationRepository: HomePagePresentationSettingsRepository
  ) {
    this.preferencesRepository = preferencesRepository;
    this.customHomepageRepository = customHomepageRepository;
    this.presentationRepository = presentationRepository;
    this.customHomepageCoordinator = new CustomHomepageSettingsCoordinator(customHomepageRepository);
  }

  getSnapshot(): HomePageSettingsSnapshot {
    const appearance = this.preferencesRepository.getPreferences().appearance;
    const customHomepageSettings = this.customHomepageRepository.getSettings();
    const presentation = this.presentationRepository.getSettings();
    return {
      showFavorites: appearance.showHomeShortcuts,
      compactFavorites: appearance.homeShortcutLayoutDensity === 'compact',
      showFavoritesTitle: presentation.showFavoritesTitle,
      iconSizeRatio: this.iconAppearanceViewModel.normalizeIconSizeRatio(
        appearance.homeShortcutIconSizeRatio
      ),
      iconCornerRadiusRatio: this.iconAppearanceViewModel.normalizeCornerRadiusRatio(
        appearance.siteIconCornerRadiusRatio
      ),
      showShortcutNames: presentation.showShortcutNames,
      showRecentlyClosed: appearance.showHomeRecentlyClosed,
      showRecentlyClosedTitle: presentation.showRecentlyClosedTitle,
      recentlyClosedLimit: this.normalizeRecentlyClosedLimit(appearance.homeRecentlyClosedLimit),
      showSystemSearch: customHomepageSettings.systemHomepageShowSystemSearchBar,
      hideSystemSearchOnScroll: customHomepageSettings.hideToolbarOnScroll,
      showSettingsButton: presentation.showSettingsButton
    };
  }

  async setFavoritesVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    this.ensureRecoveryEntryChangeAllowed('favorites', visible);
    const nextSettings = this.copyAppearanceSettings();
    nextSettings.showHomeShortcuts = visible;
    return this.updateAppearanceSettings(nextSettings);
  }

  async setCompactFavorites(compact: boolean): Promise<HomePageSettingsSnapshot> {
    const nextSettings = this.copyAppearanceSettings();
    nextSettings.homeShortcutLayoutDensity = this.resolveLayoutDensity(compact);
    return this.updateAppearanceSettings(nextSettings);
  }

  async setFavoritesTitleVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    const nextSettings = this.copyPresentationSettings();
    nextSettings.showFavoritesTitle = visible;
    return this.updatePresentationSettings(nextSettings);
  }

  async setIconSizeRatio(ratio: number): Promise<HomePageSettingsSnapshot> {
    const current = this.preferencesRepository.getPreferences().appearance;
    return this.updateAppearanceSettings(this.iconAppearanceViewModel.buildAppearanceSettings(
      current,
      ratio,
      current.siteIconCornerRadiusRatio
    ));
  }

  async setIconCornerRadiusRatio(ratio: number): Promise<HomePageSettingsSnapshot> {
    const current = this.preferencesRepository.getPreferences().appearance;
    return this.updateAppearanceSettings(this.iconAppearanceViewModel.buildAppearanceSettings(
      current,
      current.homeShortcutIconSizeRatio,
      ratio
    ));
  }

  async setShortcutNamesVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    const nextSettings = this.copyPresentationSettings();
    nextSettings.showShortcutNames = visible;
    return this.updatePresentationSettings(nextSettings);
  }

  async setRecentlyClosedVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    this.ensureRecoveryEntryChangeAllowed('recently_closed', visible);
    const current = this.preferencesRepository.getPreferences().appearance;
    const limit = visible ? this.normalizeRecentlyClosedLimit(current.homeRecentlyClosedLimit) : 0;
    return this.updateAppearanceSettings(
      this.recentlyClosedViewModel.buildAppearanceSettingsWithLimit(current, limit)
    );
  }

  async setRecentlyClosedTitleVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    const nextSettings = this.copyPresentationSettings();
    nextSettings.showRecentlyClosedTitle = visible;
    return this.updatePresentationSettings(nextSettings);
  }

  async setRecentlyClosedLimit(limit: number): Promise<HomePageSettingsSnapshot> {
    const current = this.preferencesRepository.getPreferences().appearance;
    return this.updateAppearanceSettings(
      this.recentlyClosedViewModel.buildAppearanceSettingsWithLimit(
        current,
        this.normalizeRecentlyClosedLimit(limit)
      )
    );
  }

  async setSystemSearchVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    await this.customHomepageCoordinator.updateSystemHomepageSearchBar(visible);
    return this.getSnapshot();
  }

  async setSystemSearchScrollBehavior(enabled: boolean): Promise<HomePageSettingsSnapshot> {
    await this.customHomepageCoordinator.updateHideToolbarOnScroll(enabled);
    return this.getSnapshot();
  }

  async setSettingsButtonVisible(visible: boolean): Promise<HomePageSettingsSnapshot> {
    this.ensureRecoveryEntryChangeAllowed('settings_button', visible);
    const nextSettings = this.copyPresentationSettings();
    nextSettings.showSettingsButton = visible;
    return this.updatePresentationSettings(nextSettings);
  }

  resolveRecoveryEntryChange(
    entry: HomePageRecoveryEntry,
    visible: boolean
  ): HomePageRecoveryEntryDecision {
    const snapshot = this.getSnapshot();
    return this.recoveryEntryPolicyService.resolveChange(entry, visible, {
      showFavorites: snapshot.showFavorites,
      showRecentlyClosed: snapshot.showRecentlyClosed,
      showSettingsButton: snapshot.showSettingsButton
    });
  }

  async ensureRecoveryEntryAvailable(): Promise<void> {
    const snapshot = this.getSnapshot();
    const showSettingsButton = this.recoveryEntryPolicyService.resolveSettingsButtonVisibility({
      showFavorites: snapshot.showFavorites,
      showRecentlyClosed: snapshot.showRecentlyClosed,
      showSettingsButton: snapshot.showSettingsButton
    });
    if (showSettingsButton === snapshot.showSettingsButton) {
      return;
    }
    const nextSettings = this.copyPresentationSettings();
    nextSettings.showSettingsButton = showSettingsButton;
    await this.updatePresentationSettings(nextSettings);
  }

  resolveRecentlyClosedSliderIndex(limit: number): number {
    const normalizedLimit = this.normalizeRecentlyClosedLimit(limit);
    return HOME_RECENTLY_CLOSED_LIMIT_OPTIONS.indexOf(normalizedLimit);
  }

  resolveRecentlyClosedLimitForSliderIndex(index: number): number {
    const safeIndex = Math.max(
      0,
      Math.min(HOME_RECENTLY_CLOSED_LIMIT_OPTIONS.length - 1, Math.round(index))
    );
    return HOME_RECENTLY_CLOSED_LIMIT_OPTIONS[safeIndex];
  }

  private async updateAppearanceSettings(
    settings: BrowserAppearanceSettings
  ): Promise<HomePageSettingsSnapshot> {
    await this.preferencesRepository.updateAppearanceSettings(settings);
    return this.getSnapshot();
  }

  private async updatePresentationSettings(
    settings: HomePagePresentationSettings
  ): Promise<HomePageSettingsSnapshot> {
    await this.presentationRepository.updateSettings(settings);
    return this.getSnapshot();
  }

  private ensureRecoveryEntryChangeAllowed(entry: HomePageRecoveryEntry, visible: boolean): void {
    const decision = this.resolveRecoveryEntryChange(entry, visible);
    if (!decision.allowed) {
      throw new Error(decision.message);
    }
  }

  private copyAppearanceSettings(): BrowserAppearanceSettings {
    const current = this.preferencesRepository.getPreferences().appearance;
    return {
      bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
      globalImmersionEnabled: current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: current.blurPrivateTabPreviews,
      showHomeRecentlyClosed: current.showHomeRecentlyClosed,
      showHomeShortcuts: current.showHomeShortcuts,
      homeRecentlyClosedLimit: current.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: current.homeShortcutIconSizeRatio,
      siteIconCornerRadiusRatio: current.siteIconCornerRadiusRatio,
      themePaletteId: current.themePaletteId,
      tabsOverviewLayoutStyle: current.tabsOverviewLayoutStyle,
      tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: current.showDesktopBookmarkBar
    };
  }

  private copyPresentationSettings(): HomePagePresentationSettings {
    const current = this.presentationRepository.getSettings();
    return {
      showFavoritesTitle: current.showFavoritesTitle,
      showShortcutNames: current.showShortcutNames,
      showRecentlyClosedTitle: current.showRecentlyClosedTitle,
      showSettingsButton: current.showSettingsButton
    };
  }

  private normalizeRecentlyClosedLimit(limit: number): number {
    if (HOME_RECENTLY_CLOSED_LIMIT_OPTIONS.indexOf(limit) >= 0) {
      return limit;
    }
    let selected = HOME_RECENTLY_CLOSED_LIMIT_OPTIONS[0];
    let selectedDistance = Math.abs(limit - selected);
    HOME_RECENTLY_CLOSED_LIMIT_OPTIONS.forEach((candidate: number) => {
      const distance = Math.abs(limit - candidate);
      if (distance < selectedDistance) {
        selected = candidate;
        selectedDistance = distance;
      }
    });
    return selected;
  }

  private resolveLayoutDensity(compact: boolean): BrowserHomeShortcutLayoutDensity {
    return compact ? 'compact' : 'standard';
  }
}

import { BrowserAppearanceSettings } from '../../common/models/BrowserModels';
import { sharedPreferencesRepository } from '../../app/bootstrap/BrowserAppRuntime';
import { SettingsDetailInteractionCoordinator } from '../settings/SettingsDetailInteractionCoordinator';
import { FeatureIntroCoordinator, FeatureIntroHost } from './FeatureIntroCoordinator';
import { FeatureIntroExitDestination } from './FeatureIntroRoutePolicy';
import {
  resolveFeatureIntroAppearancePalette,
  resolveFeatureIntroAppearanceTabStyle,
  resolveFeatureIntroDesktopTabPlacement
} from './FeatureIntroAppearanceViewModel';

export interface FeatureIntroAppearanceHost extends FeatureIntroHost {
  openAccount: () => void;
  leave: (destination: FeatureIntroExitDestination) => void;
}

export class FeatureIntroAppearanceCoordinator {
  private readonly host: FeatureIntroAppearanceHost;
  private readonly intro: FeatureIntroCoordinator;
  private readonly appearance: SettingsDetailInteractionCoordinator;
  private leaving: boolean = false;

  constructor(host: FeatureIntroAppearanceHost) {
    this.host = host;
    this.intro = new FeatureIntroCoordinator(host);
    this.appearance = new SettingsDetailInteractionCoordinator(sharedPreferencesRepository);
  }

  continueWith(paletteId: string, tabStyle: string, desktopTabPlacement: string = ''): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    const current = sharedPreferencesRepository.getPreferences().appearance;
    const usesDesktopTabs = desktopTabPlacement.length > 0;
    const nextSettings: BrowserAppearanceSettings = {
      bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
      toolbarChromeStyle: current.toolbarChromeStyle,
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
      themePaletteId: resolveFeatureIntroAppearancePalette(paletteId),
      tabsOverviewLayoutStyle: usesDesktopTabs ?
        current.tabsOverviewLayoutStyle : resolveFeatureIntroAppearanceTabStyle(tabStyle),
      tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: current.showDesktopBookmarkBar,
      desktopBookmarkBarVisibility: current.desktopBookmarkBarVisibility,
      verticalTabsEnabled: usesDesktopTabs ?
        resolveFeatureIntroDesktopTabPlacement(desktopTabPlacement) === 'vertical' :
        current.verticalTabsEnabled,
      verticalTabsCollapsed: current.verticalTabsCollapsed,
      verticalTabsDoubleClickCloseEnabled: current.verticalTabsDoubleClickCloseEnabled
    };
    this.appearance.commitAppearanceSettings({
      dataScope: '',
      privacyMode: ''
    }, nextSettings)
      .then((): void => {
        this.host.openAccount();
      })
      .catch((_error: Error): void => {
        this.host.openAccount();
      });
  }

  skip(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    this.intro.skipToBrowser();
  }

  abandonLeave(): void {
    this.leaving = false;
    this.intro.abandonLeave();
  }
}

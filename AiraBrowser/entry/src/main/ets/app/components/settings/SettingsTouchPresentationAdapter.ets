import { SettingsNavigationScreen } from './SettingsNavigationScreen';
import {
  createDefaultSettingsCenterPresentationSnapshot,
  SettingsCenterPresentationIntent,
  SettingsCenterPresentationIntentDispatcher,
  SettingsCenterPresentationSnapshot
} from './SettingsCenterPresentationContract';

@Component
export struct SettingsTouchPresentationAdapter {
  @Prop snapshot: SettingsCenterPresentationSnapshot = createDefaultSettingsCenterPresentationSnapshot();
  onIntent: SettingsCenterPresentationIntentDispatcher =
    (_intent: SettingsCenterPresentationIntent): void => {};

  build() {
    SettingsNavigationScreen({
      state: this.snapshot.state,
      searchState: this.snapshot.searchState,
      navigationSnapshot: this.snapshot.navigationSnapshot,
      dataScope: this.snapshot.boundary.dataScope,
      privacyMode: this.snapshot.boundary.privacyMode,
      boundarySource: this.snapshot.boundary.boundarySource,
      pageBackground: this.snapshot.theme.pageBackground,
      surfaceBackground: this.snapshot.theme.surfaceBackground,
      headerButtonBackground: this.snapshot.theme.headerButtonBackground,
      headerIconColor: this.snapshot.theme.headerIconColor,
      pressedBackground: this.snapshot.theme.pressedBackground,
      primaryTextColor: this.snapshot.theme.primaryTextColor,
      secondaryTextColor: this.snapshot.theme.secondaryTextColor,
      dividerColor: this.snapshot.theme.dividerColor,
      settingsIconBackgrounds: this.snapshot.theme.settingsIconBackgrounds,
      accountCard: this.snapshot.accountCard,
      layoutState: this.snapshot.layoutState,
      settingsRefreshRevision: this.snapshot.settingsRefreshRevision,
      onClose: () => {
        this.onIntent(SettingsCenterPresentationIntent.close());
      },
      onAccountAction: () => {
        this.onIntent(SettingsCenterPresentationIntent.accountAction());
      },
      onOpenAppProxyQuickSheet: () => {
        this.onIntent(SettingsCenterPresentationIntent.openAppProxyQuick());
      },
      onScanLoginAction: () => {
        this.onIntent(SettingsCenterPresentationIntent.scanLogin());
      },
      onSearchQueryChange: (query: string) => {
        this.onIntent(SettingsCenterPresentationIntent.changeSearchQuery(query));
      },
      onSelectSearchTarget: (targetId: string) => {
        this.onIntent(SettingsCenterPresentationIntent.selectSearchTarget(targetId));
      },
      onSelectDestination: (destination) => {
        this.onIntent(SettingsCenterPresentationIntent.selectDestination(destination));
      },
      onBackSettingsDetail: () => {
        this.onIntent(SettingsCenterPresentationIntent.backDetail());
      },
      onOpenWebAppDetail: (shortcutId: string) => {
        this.onIntent(SettingsCenterPresentationIntent.openWebAppDetail(shortcutId));
      },
      onOpenWebAppPermission: (host, origin, kind) => {
        this.onIntent(SettingsCenterPresentationIntent.openWebAppPermission(host, origin, kind));
      },
      onOpenWebAppDesktopSite: (host: string, origin: string) => {
        this.onIntent(SettingsCenterPresentationIntent.openWebAppDesktopSite(host, origin));
      },
      onOpenEmbeddedSubpage: (subpageId: string) => {
        this.onIntent(SettingsCenterPresentationIntent.openEmbeddedSubpage(subpageId));
      },
      onSettingsChanged: () => {
        this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
      }
    })
  }
}

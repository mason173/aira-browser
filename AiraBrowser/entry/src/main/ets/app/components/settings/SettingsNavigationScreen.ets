import {
  SettingsCenterDestination,
  SettingsCenterGroupState,
  SettingsCenterRowState,
  SettingsCenterState,
  SettingsCenterViewModel
} from '../../../core/settings/SettingsCenterViewModel';
import {
  DEFAULT_SETTINGS_CENTER_SEARCH_STATE,
  SettingsCenterSearchGroupState,
  SettingsCenterSearchResultState,
  SettingsCenterSearchState
} from '../../../core/settings/SettingsDestinationNavigationOwner';
import {
  SettingsAccountCardState
} from '../../../core/settings/SettingsAccountCardViewModel';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from './SettingsLayout';
import { SettingsAccountCardRow, SettingsNavigationRow } from './SettingsRows';
import { SettingsEmbeddedDetailPanel } from './SettingsEmbeddedDetailPanel';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SettingsCenterSearchHeader } from './SettingsCenterSearchHeader';
import { SitePermissionKind } from '../../../common/models/BrowserModels';
import {
  SettingsNavigationPathEntry,
  SettingsNavigationSnapshot
} from '../../../core/settings/SettingsDestinationNavigationOwner';
import { SettingsWebAppsDetailPanel } from './SettingsWebAppsDetailPanel';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import { HdsNavDestination, HdsNavigation } from '@kit.UIDesignKit';
import {
  SettingsHdsNavigationStackProjection
} from '../../router/SettingsHdsNavigationStackProjection';
import {
  DEFAULT_SETTINGS_TWO_PANE_LAYOUT_STATE,
  SettingsShellLayoutState
} from '../../../core/settings/SettingsShellLayoutPolicy';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { LocalBackupScreen } from '../backup/LocalBackupScreen';

@Component
export struct SettingsNavigationScreen {
  private navigationProjection: SettingsHdsNavigationStackProjection =
    new SettingsHdsNavigationStackProjection();
  private directoryScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string =
    DEFAULT_THEME_PALETTE.light.settingsIconForeground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop state: SettingsCenterState = new SettingsCenterViewModel().buildState();
  @Prop searchState: SettingsCenterSearchState = DEFAULT_SETTINGS_CENTER_SEARCH_STATE;
  @Prop @Watch('syncNavigationProjection') navigationSnapshot: SettingsNavigationSnapshot =
    new SettingsNavigationSnapshot('compact', 'general', 'primary', 1, '', '', '', 'camera', []);
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  @Prop pageBackground: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop headerButtonBackground: ResourceColor | undefined = undefined;
  @Prop headerIconColor: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop primaryTextColor: ResourceColor | undefined = undefined;
  @Prop secondaryTextColor: ResourceColor | undefined = undefined;
  @Prop dividerColor: ResourceColor | undefined = undefined;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet = DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  @Prop accountCard: SettingsAccountCardState = {
    title: '未登录',
    subtitle: '本地浏览功能已全部开启，登录后可使用账号与云服务',
    isLoggedIn: false,
    avatarUri: '',
    membershipBadge: 'none',
    recognitionBadge: 'none'
  };
  @Prop layoutState: SettingsShellLayoutState = DEFAULT_SETTINGS_TWO_PANE_LAYOUT_STATE;
  @Prop settingsRefreshRevision: number = 0;
  onClose?: () => void;
  onAccountAction?: () => void;
  onOpenAppProxyQuickSheet?: () => void;
  onScanLoginAction?: () => void;
  onSearchQueryChange?: (query: string) => void;
  onSelectSearchTarget?: (targetId: string) => void;
  onSelectDestination?: (destination: SettingsCenterDestination) => void;
  onBackSettingsDetail?: () => void;
  onOpenWebAppDetail?: (shortcutId: string) => void;
  onOpenWebAppPermission?: (host: string, origin: string, kind: SitePermissionKind) => void;
  onOpenWebAppDesktopSite?: (host: string, origin: string) => void;
  onOpenEmbeddedSubpage?: (subpageId: string) => void;
  onSettingsChanged?: () => void;

  aboutToAppear(): void {
    this.syncNavigationProjection();
  }

  build() {
    SettingsHdsScaffold({
      title: '设置',
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.resolveHeaderButtonBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      dividerColor: this.resolveDividerColor(),
      showPrivateIndicator: this.isPrivateContext(),
      contentKind: this.isTwoPaneMode() ? 'unframed' : 'standard',
      scrollers: [this.directoryScroller],
      onBack: () => {
        this.onClose?.();
      }
    }) {
      if (this.isTwoPaneMode()) {
        Row() {
          HdsNavigation(this.navigationProjection.pathStack) {
            this.buildDirectoryPanel()
          }
          .width('100%')
          .height('100%')
          .mode(this.resolveNavigationMode())
          .hideTitleBar(true)
          .hideToolBar(true)
          .hideBackButton(true)
          .hideNavBar(false)
          .navBarWidth(this.resolveNavigationBarWidth())
          .navBarWidthRange({
            minWidth: this.resolveNavigationBarWidth(),
            maxWidth: this.resolveNavigationBarWidth()
          })
          .divider(null)
          .enableDragBar(false)
          .enableModeChangeAnimation(false)
          .recoverable(false)
          .navDestination(this.buildNavigationDestination)
        }
        .width('100%')
        .height('100%')
        .padding({
          left: this.resolveShellHorizontalInset(),
          right: this.resolveShellHorizontalInset(),
          bottom: this.resolveShellBottomInset()
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Top)
        .zIndex(0)
      } else {
        this.buildDirectoryPanel()
      }
    }
  }

  private isPrivateContext(): boolean {
    return this.dataScope === 'session_ephemeral' || this.privacyMode === 'private';
  }

  @Builder
  private buildDirectoryPanel() {
    Column() {
      SettingsScrollBody({
        bottomPadding: this.resolveDirectoryBottomPadding(),
        scroller: this.directoryScroller
      }) {
        this.buildSearchHeader()
        if (!this.searchState.isActive && this.state.showAccountCard) {
          this.buildAccountCard()
        }
        if (this.searchState.isActive && this.searchState.resultCount <= 0) {
          this.buildEmptySearchResult()
        }
        if (this.searchState.isActive) {
          ForEach(this.searchState.groups, (group: SettingsCenterSearchGroupState) => {
            this.buildDirectorySearchSection(group)
          }, (group: SettingsCenterSearchGroupState) => this.resolveSearchGroupRenderKey(group))
        } else {
          ForEach(this.state.groups, (group: SettingsCenterGroupState) => {
            this.buildDirectorySection(group)
          }, (group: SettingsCenterGroupState) => this.resolveGroupRenderKey(group))
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ right: this.resolveDirectoryEndInset() })
  }

  @Builder
  private buildNavigationDestination(_name: string, pageInfos: Object) {
    HdsNavDestination() {
      Row() {
        Column() {
          this.buildDestinationContent(pageInfos as SettingsNavigationPathEntry)
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.resolveDestinationStartInset() })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .hideTitleBar(true)
    .hideToolBar(true)
    .hideBackButton(true)
    .backgroundColor(this.resolvePageBackground())
    .onBackPressed(() => {
      this.onBackSettingsDetail?.();
      return true;
    })
  }

  @Builder
  private buildDestinationContent(params: SettingsNavigationPathEntry) {
    if (params.subpageId === 'local_backup') {
      LocalBackupScreen({
        embedded: true,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        onBack: () => {
          this.onBackSettingsDetail?.();
        }
      })
        .width('100%')
        .height('100%')
    } else if (params.destination === 'web_apps') {
      SettingsWebAppsDetailPanel({
        panelMode: 'twoPane',
        refreshRevision: this.settingsRefreshRevision,
        detailKind: params.detailKind,
        shortcutId: params.shortcutId,
        host: params.host,
        origin: params.origin,
        permissionKind: params.permissionKind,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        pageBackground: this.resolvePageBackground(),
        surfaceBackground: this.resolveSurfaceBackground(),
        headerButtonBackground: this.resolveHeaderButtonBackground(),
        accentColor: this.resolveHeaderIconColor(),
        dividerColor: this.resolveDividerColor(),
        pressedBackground: this.resolvePressedBackground(),
        primaryTextColor: this.resolvePrimaryTextColor(),
        secondaryTextColor: this.resolveSecondaryTextColor(),
        onBack: () => {
          this.onBackSettingsDetail?.();
        },
        onOpenWebAppDetail: (shortcutId: string) => {
          this.onOpenWebAppDetail?.(shortcutId);
        },
        onOpenPermission: (host: string, origin: string, kind: SitePermissionKind) => {
          this.onOpenWebAppPermission?.(host, origin, kind);
        },
        onOpenDesktopSite: (host: string, origin: string) => {
          this.onOpenWebAppDesktopSite?.(host, origin);
        },
        onSettingsChanged: () => {
          this.onSettingsChanged?.();
        }
      })
    } else {
      SettingsEmbeddedDetailPanel({
        selectedDestination: params.destination,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource,
        surfaceBackground: this.resolveSurfaceBackground(),
        dividerColor: this.resolveDividerColor(),
        accentColor: this.resolveHeaderIconColor(),
        onAccentColor: this.storedSettingsIconForegroundColor,
        pressedBackground: this.resolvePressedBackground(),
        primaryTextColor: this.resolvePrimaryTextColor(),
        secondaryTextColor: this.resolveSecondaryTextColor(),
        settingsRefreshRevision: this.settingsRefreshRevision,
        onSelectDestination: (destination: SettingsCenterDestination) => {
          this.onSelectDestination?.(destination);
        },
        onOpenEmbeddedSubpage: (subpageId: string) => {
          this.onOpenEmbeddedSubpage?.(subpageId);
        },
        onSettingsChanged: () => {
          this.onSettingsChanged?.();
        }
      })
    }
  }

  @Builder
  private buildAccountCard() {
    SettingsGroupCard({ surfaceColor: this.resolveSurfaceBackground() }) {
      SettingsAccountCardRow({
        title: this.accountCard.title,
        subtitle: this.accountCard.subtitle,
        primaryTextColor: this.resolvePrimaryTextColor(),
        secondaryTextColor: this.resolveSecondaryTextColor(),
        pressedBackgroundColor: this.resolvePressedBackground(),
        avatarBackgroundColor: this.resolveHeaderIconColor(),
        avatarIconColor: this.storedSettingsIconForegroundColor,
        avatarUri: this.accountCard.avatarUri,
        membershipBadge: this.accountCard.membershipBadge,
        recognitionBadge: this.accountCard.recognitionBadge,
        rowPosition: 'single',
        onAction: () => {
          this.onAccountAction?.();
        }
      })
    }
  }

  @Builder
  private buildSearchHeader() {
    SettingsCenterSearchHeader({
      appProxyNotice: this.state.appProxyNotice,
      searchState: this.searchState,
      resolvedThemeMode: this.storedResolvedThemeMode,
      surfaceColor: this.resolveSurfaceBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      secondaryTextColor: this.resolveSecondaryTextColor(),
      accentColor: this.resolveHeaderIconColor(),
      statusColor: this.settingsIconBackgrounds.passwords,
      showScanAction: this.state.showScanLoginAction,
      onOpenAppProxyQuickSheet: () => {
        this.onOpenAppProxyQuickSheet?.();
      },
      onScanLoginAction: () => {
        this.onScanLoginAction?.();
      },
      onSearchQueryChange: (query: string) => {
        this.onSearchQueryChange?.(query);
      }
    })
  }

  @Builder
  private buildEmptySearchResult() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(26)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.resolveSecondaryTextColor()])

      Text('未找到匹配的设置项')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryTextColor())
        .textAlign(TextAlign.Center)

      Text('换个关键词试试')
        .fontSize(13)
        .fontColor(this.resolveSecondaryTextColor())
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 28, bottom: 30 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDirectorySection(group: SettingsCenterGroupState) {
    SettingsSection({
      title: group.title,
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({ surfaceColor: this.resolveSurfaceBackground() }) {
        ForEach(group.rows, (row: SettingsCenterRowState, index: number) => {
          SettingsNavigationRow({
            title: row.title,
            value: row.value,
            icon: row.icon,
            imageIcon: row.imageIcon,
            airaIconId: row.airaIconId,
            iconBackgroundColor: this.resolveRowIconBackgroundColor(row.id),
            iconColor: this.storedSettingsIconForegroundColor,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            selectedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: this.resolveRowPosition(index, group.rows.length),
            isEnabled: row.isEnabled,
            isSelected: this.isDirectoryDestinationSelected(row.id),
            onAction: () => {
              this.selectOrOpenDestination(row.id);
            }
          })
          if (index < group.rows.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (row: SettingsCenterRowState) => this.resolveRowRenderKey(row))
      }
    }
  }

  @Builder
  private buildDirectorySearchSection(group: SettingsCenterSearchGroupState) {
    SettingsSection({
      title: group.title,
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({ surfaceColor: this.resolveSurfaceBackground() }) {
        ForEach(group.rows, (row: SettingsCenterSearchResultState, index: number) => {
          SettingsNavigationRow({
            title: row.title,
            value: row.unavailableReason,
            icon: row.icon,
            imageIcon: row.imageIcon,
            airaIconId: row.airaIconId,
            iconBackgroundColor: this.resolveRowIconBackgroundColor(row.destination),
            iconColor: this.storedSettingsIconForegroundColor,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            selectedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: this.resolveRowPosition(index, group.rows.length),
            isEnabled: true,
            isSelected: this.isDirectoryDestinationSelected(row.destination),
            onAction: () => {
              this.selectOrOpenSearchResult(row);
            }
          })
          if (index < group.rows.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (row: SettingsCenterSearchResultState) => this.resolveSearchRowRenderKey(row))
      }
    }
  }

  private resolveThemeRenderKey(): string {
    return `${this.storedResolvedThemeMode}:${this.resolvePageBackground()}:${this.resolveSurfaceBackground()}:` +
      `${this.resolveHeaderButtonBackground()}:${this.resolveHeaderIconColor()}:${this.resolvePressedBackground()}:` +
      `${this.resolvePrimaryTextColor()}:${this.resolveSecondaryTextColor()}:${this.storedDividerColor}:` +
      `${this.storedSettingsIconForegroundColor}`;
  }

  private resolveGroupRenderKey(group: SettingsCenterGroupState): string {
    return `${this.resolveThemeRenderKey()}:${group.id}:${group.title}`;
  }

  private resolveSearchGroupRenderKey(group: SettingsCenterSearchGroupState): string {
    return `${this.resolveThemeRenderKey()}:${group.id}:${group.title}`;
  }

  private resolveRowRenderKey(row: SettingsCenterRowState): string {
    return `${this.resolveThemeRenderKey()}:${row.id}:${row.value}:${row.isEnabled ? '1' : '0'}:` +
      `${this.isDirectoryDestinationSelected(row.id) ? '1' : '0'}`;
  }

  private resolveSearchRowRenderKey(row: SettingsCenterSearchResultState): string {
    return `${this.resolveThemeRenderKey()}:${row.id}:${row.isAvailable ? '1' : '0'}:` +
      `${this.isDirectoryDestinationSelected(row.destination) ? '1' : '0'}`;
  }

  private isDirectoryDestinationSelected(destination: SettingsCenterDestination): boolean {
    return this.isTwoPaneMode() &&
      destination === this.navigationSnapshot.selectedPrimaryDestination;
  }

  private selectOrOpenDestination(destination: SettingsCenterDestination): void {
    this.onSelectDestination?.(destination);
  }

  private selectOrOpenSearchResult(row: SettingsCenterSearchResultState): void {
    this.onSelectSearchTarget?.(row.id);
  }

  private syncNavigationProjection(): void {
    this.navigationProjection.sync(this.navigationSnapshot);
  }

  private resolveNavigationMode(): NavigationMode {
    return this.isTwoPaneMode() ? NavigationMode.Split : NavigationMode.Stack;
  }

  private resolveNavigationBarWidth(): number {
    if (!this.isTwoPaneMode()) {
      return DEFAULT_SETTINGS_TWO_PANE_LAYOUT_STATE.sidebarWidth;
    }
    return this.layoutState.sidebarWidth + this.resolveHalfPaneGap();
  }

  private resolveShellHorizontalInset(): number {
    return this.isTwoPaneMode() ? this.layoutState.horizontalInset : 0;
  }

  private resolveShellBottomInset(): number {
    return this.isTwoPaneMode() ? this.layoutState.bottomInset : 0;
  }

  private resolveDirectoryBottomPadding(): number {
    return this.isTwoPaneMode() ? 18 : 22;
  }

  private resolveDirectoryEndInset(): number {
    return this.isTwoPaneMode() ? this.resolveHalfPaneGap() : 0;
  }

  private resolveDestinationStartInset(): number {
    return this.isTwoPaneMode() ? this.resolveHalfPaneGap() : 0;
  }

  private resolveHalfPaneGap(): number {
    return Math.floor(this.layoutState.paneGap / 2);
  }

  private isTwoPaneMode(): boolean {
    return this.navigationSnapshot.shellMode !== 'compact';
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private resolveHeaderIconColor(): ResourceColor {
    return this.headerIconColor === undefined ? this.storedSecondaryTextColor : this.headerIconColor;
  }

  private resolvePageBackground(): ResourceColor {
    return this.pageBackground === undefined ? this.storedPageBackgroundColor : this.pageBackground;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolveHeaderButtonBackground(): ResourceColor {
    return this.headerButtonBackground === undefined ? this.storedPressedBackgroundColor : this.headerButtonBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }

  private resolveDividerColor(): ResourceColor {
    return this.dividerColor === undefined ? this.storedDividerColor : this.dividerColor;
  }

  private resolveRowIconBackgroundColor(destination: SettingsCenterDestination): ResourceColor {
    switch (destination) {
      case 'general':
      case 'custom_homepage':
      case 'toolbar_customization':
      case 'app_service_mode':
        return this.settingsIconBackgrounds.general;
      case 'aira_pro':
        return this.settingsIconBackgrounds.sync;
      case 'search':
        return this.settingsIconBackgrounds.search;
      case 'privacy_security':
      case 'private_mode':
        return this.settingsIconBackgrounds.privacySecurity;
      case 'web_features':
      case 'user_scripts':
        return this.settingsIconBackgrounds.userScripts;
      case 'webpage_translation':
        return this.settingsIconBackgrounds.webpageTranslation;
      case 'passwords':
        return this.settingsIconBackgrounds.passwords;
      case 'downloads':
        return this.settingsIconBackgrounds.downloads;
      case 'user_agent':
        return this.settingsIconBackgrounds.userAgent;
      case 'appearance_toolbar':
        return this.settingsIconBackgrounds.appearance;
      case 'experiments':
        return this.settingsIconBackgrounds.experiments;
      case 'sync':
        return this.settingsIconBackgrounds.sync;
      case 'advanced_settings':
        return this.settingsIconBackgrounds.general;
      case 'about':
        return this.settingsIconBackgrounds.about;
      default:
        return this.settingsIconBackgrounds.general;
    }
  }
}

import {
  SettingsCenterDestination,
  SettingsCenterGroupState,
  SettingsCenterRowState
} from '../../../core/settings/SettingsCenterViewModel';
import {
  SettingsCenterSearchGroupState,
  SettingsCenterSearchResultState
} from '../../../core/settings/SettingsDestinationNavigationOwner';
import {
  createDefaultSettingsCenterPresentationSnapshot,
  SettingsCenterPresentationIntent,
  SettingsCenterPresentationIntentDispatcher,
  SettingsCenterPresentationSnapshot
} from './SettingsCenterPresentationContract';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { SitePermissionKind } from '../../../common/models/BrowserModels';
import { SettingsEmbeddedDetailPanel } from './SettingsEmbeddedDetailPanel';
import { SettingsWebAppsDetailPanel } from './SettingsWebAppsDetailPanel';
import { KeyboardShortcutsContent } from './KeyboardShortcutsContent';
import { AppIconSettingsContent } from './AppIconSettingsContent';
import { ThemePaletteSettingsContent } from './ThemePaletteSettingsContent';
import { BrowserTabletInterfaceModeSettingsContent } from './BrowserTabletInterfaceModeSettingsContent';
import { createCenteredDialogMaterial } from '../common/CenteredDialogSurface';
import { BrowserTrackingProtectionSettingsContent } from './BrowserTrackingProtectionSettingsContent';
import {
  SiteControlsExternalNavigationDefaultContent
} from './SiteControlsExternalNavigationDefaultContent';
import { CookieManagementContent } from './CookieManagementContent';
import { SecureDnsSettingsContent } from './SecureDnsSettingsContent';
import { SecureDnsProfileEditDialog, SecureDnsProfileEditHost } from './SecureDnsProfileEditHost';
import {
  SETTINGS_DESKTOP_SCROLLBAR_GUTTER,
  SettingsPresentationScrollBody
} from './SettingsLayout';
import { SettingsCenterSearchHeader } from './SettingsCenterSearchHeader';
import { SettingsDesktopDivider, SettingsDesktopGroup } from './SettingsDesktopRows';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';
import { SearchBuiltInEnginesHost } from '../search/SearchBuiltInEnginesHost';
import { AdBlockCustomRulesHost } from '../adblock/AdBlockCustomRulesHost';
import { ManualElementHideHost } from '../adblock/ManualElementHideHost';
import { AiraIcon } from '../common/AiraIcon';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import {
  CustomHomepageSettingsPageBinding
} from '../../../core/customhome/CustomHomepageSettingsPageBinding';
import {
  BrowserDownloadSettingsOptionScreen,
  BrowserDownloadSettingsSubpage
} from '../browser/BrowserDownloadSettingsScreen';
import { LocalBackupScreen } from '../backup/LocalBackupScreen';
import { BrowserToolbarCustomizationScreen } from './BrowserToolbarCustomizationScreen';

const LARGE_SCREEN_SETTINGS_HEADER_HEIGHT: number = 64;
const LARGE_SCREEN_SETTINGS_HEADER_TITLE_HORIZONTAL_PADDING: number = 24;
const LARGE_SCREEN_SETTINGS_SIDEBAR_LEFT_PADDING: number = 12;
const LARGE_SCREEN_SETTINGS_SIDEBAR_RIGHT_PADDING: number = 4;
const LARGE_SCREEN_SETTINGS_SIDEBAR_TOP_PADDING: number = 18;
const LARGE_SCREEN_SETTINGS_SIDEBAR_BOTTOM_PADDING: number = 18;
const LARGE_SCREEN_SETTINGS_SIDEBAR_SCROLLBAR_GUTTER: number = 4;
const LARGE_SCREEN_SETTINGS_MENU_ROW_HEIGHT: number = 48;
const LARGE_SCREEN_SETTINGS_MENU_ROW_RADIUS: number = 10;
const LARGE_SCREEN_SETTINGS_WORKSPACE_TOP_PADDING: number = 28;
const LARGE_SCREEN_SETTINGS_WORKSPACE_MAX_WIDTH: number = 1024;

@Component
struct SettingsLargeScreenMenuRow {
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop icon: Resource | undefined = undefined;
  @Prop imageIcon: Resource | undefined = undefined;
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop iconColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop hoverBackgroundColor: ResourceColor = '';
  @Prop selectedBackgroundColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop isEnabled: boolean = true;
  @Prop isSelected: boolean = false;
  @State private hovered: boolean = false;
  @State private pressed: boolean = false;
  @State private focused: boolean = false;
  onAction?: () => void;

  build() {
    Button() {
      Row({ space: 14 }) {
        this.buildLeadingIcon()

        Text(this.title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(this.isSelected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.isEnabled ? this.primaryTextColor : this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        if (this.value.trim().length > 0) {
          Text(this.value)
            .fontSize(12)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(LARGE_SCREEN_SETTINGS_MENU_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.resolveBackgroundColor())
    .border({
      width: this.focused ? 2 : 0,
      color: this.accentColor
    })
    .borderRadius(LARGE_SCREEN_SETTINGS_MENU_ROW_RADIUS)
    .clip(true)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .accessibilityText(this.title)
    .onHover((isHover: boolean) => {
      this.hovered = isHover && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  @Builder
  private buildLeadingIcon() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.airaIconId !== undefined) {
        AiraIcon({
          airaIconId: this.airaIconId as AiraRenderableIconId,
          iconSize: 21,
          iconColor: this.iconColor
        })
      } else if (this.imageIcon !== undefined) {
        Image(this.imageIcon as Resource)
          .width(21)
          .height(21)
          .objectFit(ImageFit.Contain)
      } else {
        AiraIcon({
          airaIconId: 'settings.general',
          iconSize: 21,
          iconColor: this.iconColor
        })
      }
    }
    .width(24)
    .height(24)
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.pressed) {
      return this.selectedBackgroundColor;
    }
    if (this.isSelected) {
      return this.selectedBackgroundColor;
    }
    if (this.hovered || this.focused) {
      return this.hoverBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }
}

@Component
export struct SettingsLargeScreenShell {
  customHomepagePageBinding: CustomHomepageSettingsPageBinding = new CustomHomepageSettingsPageBinding();
  @Prop snapshot: SettingsCenterPresentationSnapshot = createDefaultSettingsCenterPresentationSnapshot();
  onIntent: SettingsCenterPresentationIntentDispatcher =
    (_intent: SettingsCenterPresentationIntent): void => {};
  @State private secureDnsEditorVisible: boolean = false;
  @State private secureDnsEditorProfileId: string = '';
  private secureDnsAddDialogController: CustomDialogController = new CustomDialogController({
    builder: SecureDnsProfileEditDialog({
      dataScope: this.snapshot.boundary.dataScope,
      privacyMode: this.snapshot.boundary.privacyMode
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
  });

  build() {
    Column() {
      this.buildWindowHeader()

      Divider()
        .width('100%')
        .height(1)
        .color(this.snapshot.theme.dividerColor)

      Row() {
        this.buildPersistentMenu()

        Divider()
          .width(1)
          .height('100%')
          .color(this.snapshot.theme.dividerColor)

        this.buildWorkspace()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .clip(true)
      .zIndex(0)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.snapshot.theme.pageBackground)
    .clip(true)
  }

  @Builder
  private buildWindowHeader() {
    Row() {
      Row({ space: 8 }) {
        Text('设置')
          .layoutWeight(1)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.snapshot.theme.primaryTextColor)
          .maxLines(1)

        if (this.isPrivateContext()) {
          Text('私密')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.snapshot.theme.headerIconColor)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.snapshot.theme.headerButtonBackground)
            .borderRadius(10)
        }

        if (this.snapshot.showCloseButton) {
          Button() {
            AiraIcon({
              airaIconId: 'browser.toolbar.clearInput',
              iconSize: 17,
              iconColor: this.snapshot.theme.headerIconColor
            })
          }
          .width(36)
          .height(36)
          .type(ButtonType.Circle)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(this.snapshot.theme.headerButtonBackground)
          .stateEffect(true)
          .accessibilityText('关闭设置')
          .onClick(() => {
            this.onIntent(SettingsCenterPresentationIntent.close());
          })
        }
      }
      .width(this.snapshot.layoutState.sidebarWidth)
      .height('100%')
      .padding({
        left: LARGE_SCREEN_SETTINGS_HEADER_TITLE_HORIZONTAL_PADDING,
        right: LARGE_SCREEN_SETTINGS_SIDEBAR_RIGHT_PADDING
      })
      .alignItems(VerticalAlign.Center)

      Row() {
        SettingsCenterSearchHeader({
          showAppProxyNotice: false,
          showSearchField: true,
          showScanAction: this.snapshot.state.showScanLoginAction,
          useToolbarSearchStyle: true,
          searchState: this.snapshot.searchState,
          resolvedThemeMode: this.snapshot.theme.resolvedThemeMode,
          surfaceColor: this.snapshot.theme.headerButtonBackground,
          primaryTextColor: this.snapshot.theme.primaryTextColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          accentColor: this.snapshot.theme.headerIconColor,
          statusColor: this.snapshot.theme.settingsIconBackgrounds.passwords,
          onScanLoginAction: () => {
            this.onIntent(SettingsCenterPresentationIntent.scanLogin());
          },
          onSearchQueryChange: (query: string) => {
            this.onIntent(SettingsCenterPresentationIntent.changeSearchQuery(query));
          }
        })
        .width('100%')
        .constraintSize({ maxWidth: LARGE_SCREEN_SETTINGS_WORKSPACE_MAX_WIDTH })
      }
      .layoutWeight(1)
      .height('100%')
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING
      })
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .clip(true)
    }
    .width('100%')
    .height(LARGE_SCREEN_SETTINGS_HEADER_HEIGHT)
    .backgroundColor(this.snapshot.theme.pageBackground)
    .alignItems(VerticalAlign.Center)
    .clip(true)
    .zIndex(1)
  }

  @Builder
  private buildPersistentMenu() {
    Column({ space: 12 }) {
      if (this.snapshot.state.appProxyNotice.shouldShow) {
        SettingsCenterSearchHeader({
          showAppProxyNotice: true,
          showSearchField: false,
          appProxyNotice: this.snapshot.state.appProxyNotice,
          resolvedThemeMode: this.snapshot.theme.resolvedThemeMode,
          surfaceColor: this.snapshot.theme.surfaceBackground,
          primaryTextColor: this.snapshot.theme.primaryTextColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          accentColor: this.snapshot.theme.headerIconColor,
          statusColor: this.snapshot.theme.settingsIconBackgrounds.passwords,
          onOpenAppProxyQuickSheet: () => {
            this.onIntent(SettingsCenterPresentationIntent.openAppProxyQuick());
          }
        })
      }

      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.snapshot.state.groups, (group: SettingsCenterGroupState) => {
            this.buildMenuGroup(group)
          }, (group: SettingsCenterGroupState) => `large-menu-group-${group.id}`)
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ right: LARGE_SCREEN_SETTINGS_SIDEBAR_SCROLLBAR_GUTTER, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .clip(true)
    }
    .width(this.snapshot.layoutState.sidebarWidth)
    .height('100%')
    .padding({
      left: LARGE_SCREEN_SETTINGS_SIDEBAR_LEFT_PADDING,
      right: LARGE_SCREEN_SETTINGS_SIDEBAR_RIGHT_PADDING,
      top: LARGE_SCREEN_SETTINGS_SIDEBAR_TOP_PADDING,
      bottom: LARGE_SCREEN_SETTINGS_SIDEBAR_BOTTOM_PADDING
    })
    .clip(true)
  }

  @Builder
  private buildEmptySearchResult() {
    Column({ space: 8 }) {
      AiraIcon({
        airaIconId: 'settings.search',
        iconSize: 24,
        iconColor: this.snapshot.theme.secondaryTextColor
      })
      Text('未找到匹配的设置项')
        .fontSize(14)
        .fontColor(this.snapshot.theme.secondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildSearchWorkspace() {
    Column() {
      Row({ space: 12 }) {
        Text('搜索结果')
          .layoutWeight(1)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.snapshot.theme.primaryTextColor)
          .maxLines(1)

        Text(`${this.snapshot.searchState.resultCount} 项`)
          .fontSize(13)
          .fontColor(this.snapshot.theme.secondaryTextColor)
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)

      if (this.snapshot.searchState.resultCount <= 0) {
        this.buildEmptySearchResult()
      } else {
        Scroll() {
          Column({ space: 16 }) {
            ForEach(this.snapshot.searchState.groups, (group: SettingsCenterSearchGroupState) => {
              this.buildSearchWorkspaceGroup(group)
            }, (group: SettingsCenterSearchGroupState) => `large-search-workspace-group-${group.id}`)
          }
          .width('100%')
          .padding({ right: SETTINGS_DESKTOP_SCROLLBAR_GUTTER, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSearchWorkspaceGroup(group: SettingsCenterSearchGroupState) {
    Column({ space: 6 }) {
      Text(group.title)
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.snapshot.theme.secondaryTextColor)
        .padding({ left: 4, right: 4 })

      SettingsDesktopGroup({ surfaceColor: this.snapshot.theme.surfaceBackground }) {
        ForEach(group.rows, (row: SettingsCenterSearchResultState, index: number) => {
          this.buildSearchWorkspaceRow(row)
          if (index < group.rows.length - 1) {
            SettingsDesktopDivider({ dividerColor: this.snapshot.theme.dividerColor })
          }
        }, (row: SettingsCenterSearchResultState) => {
          return `large-search-workspace-${row.id}-${row.isAvailable ? '1' : '0'}`;
        })
      }
    }
    .width('100%')
  }

  @Builder
  private buildSearchWorkspaceRow(row: SettingsCenterSearchResultState) {
    SettingsLargeScreenMenuRow({
      title: row.title,
      value: row.unavailableReason,
      icon: row.icon,
      imageIcon: row.imageIcon,
      airaIconId: row.airaIconId,
      iconColor: this.snapshot.theme.primaryTextColor,
      primaryTextColor: this.snapshot.theme.primaryTextColor,
      secondaryTextColor: this.snapshot.theme.secondaryTextColor,
      hoverBackgroundColor: this.snapshot.theme.headerButtonBackground,
      selectedBackgroundColor: this.snapshot.theme.pressedBackground,
      accentColor: this.snapshot.theme.headerIconColor,
      isEnabled: true,
      isSelected: false,
      onAction: () => {
        this.closeSecureDnsEditor();
        this.onIntent(SettingsCenterPresentationIntent.selectSearchTarget(row.id));
        this.onIntent(SettingsCenterPresentationIntent.changeSearchQuery(''));
      }
    })
  }

  @Builder
  private buildMenuGroup(group: SettingsCenterGroupState) {
    Column({ space: 4 }) {
      ForEach(group.rows, (row: SettingsCenterRowState) => {
        this.buildMenuRow(row)
      }, (row: SettingsCenterRowState) => this.resolveMenuRowKey(row))
    }
    .width('100%')
  }

  @Builder
  private buildMenuRow(row: SettingsCenterRowState) {
    SettingsLargeScreenMenuRow({
      title: row.title,
      value: row.value,
      icon: row.icon,
      imageIcon: row.imageIcon,
      airaIconId: row.airaIconId,
      iconColor: this.snapshot.theme.primaryTextColor,
      primaryTextColor: this.snapshot.theme.primaryTextColor,
      secondaryTextColor: this.snapshot.theme.secondaryTextColor,
      hoverBackgroundColor: this.snapshot.theme.headerButtonBackground,
      selectedBackgroundColor: this.snapshot.theme.pressedBackground,
      accentColor: this.snapshot.theme.headerIconColor,
      isEnabled: row.isEnabled,
      isSelected: this.snapshot.navigationSnapshot.selectedPrimaryDestination === row.id,
      onAction: () => {
        this.closeSecureDnsEditor();
        this.onIntent(SettingsCenterPresentationIntent.selectDestination(row.id));
      }
    })
  }

  @Builder
  private buildWorkspace() {
    Row() {
      Column() {
        if (this.snapshot.searchState.isActive) {
          this.buildSearchWorkspace()
        } else {
          if (this.shouldShowWorkspaceHeader()) {
            this.buildWorkspaceHeader()
          }

          Column() {
            this.buildWorkspaceContent()
          }
          .layoutWeight(1)
          .width('100%')
          .clip(true)
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: LARGE_SCREEN_SETTINGS_WORKSPACE_MAX_WIDTH })
    }
    .layoutWeight(1)
    .height('100%')
    .padding({
      left: APP_STANDARD_HORIZONTAL_PADDING,
      right: APP_STANDARD_HORIZONTAL_PADDING,
      top: LARGE_SCREEN_SETTINGS_WORKSPACE_TOP_PADDING
    })
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
    .clip(true)
  }

  @Builder
  private buildWorkspaceHeader() {
    SettingsDesktopWorkspaceHeader({
      title: this.snapshot.navigationSnapshot.workspaceTitle,
      showBackButton: this.snapshot.navigationSnapshot.detailDepth > 1,
      primaryTextColor: this.snapshot.theme.primaryTextColor,
      iconColor: this.snapshot.theme.headerIconColor,
      buttonBackgroundColor: this.snapshot.theme.headerButtonBackground,
      primaryActionIconId: this.snapshot.navigationSnapshot.activePanelKind === 'secure_dns'
        ? 'browser.tabs.add'
        : undefined,
      primaryActionLabel: '添加自定义 DNS',
      onBack: () => {
        this.onIntent(SettingsCenterPresentationIntent.backDetail());
      },
      onPrimaryAction: () => {
        this.secureDnsAddDialogController.open();
      }
    })
  }

  @Builder
  private buildWorkspaceContent() {
    if (this.secureDnsEditorVisible && this.snapshot.navigationSnapshot.activePanelKind === 'secure_dns') {
      SecureDnsProfileEditHost({
        profileId: this.secureDnsEditorProfileId,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        presentationMode: 'workspace',
        desktopPresentation: true,
        onBack: () => {
          this.closeSecureDnsEditor();
          this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.snapshot.navigationSnapshot.activeDetailKind === 'embedded_subpage') {
      this.buildEmbeddedSubpagePanel()
    } else if (this.snapshot.navigationSnapshot.selectedPrimaryDestination === 'web_apps') {
      SettingsWebAppsDetailPanel({
        panelMode: 'twoPane',
        desktopPresentation: true,
        refreshRevision: this.snapshot.settingsRefreshRevision,
        detailKind: this.snapshot.navigationSnapshot.activeDetailKind,
        shortcutId: this.snapshot.navigationSnapshot.shortcutId,
        host: this.snapshot.navigationSnapshot.host,
        origin: this.snapshot.navigationSnapshot.origin,
        permissionKind: this.snapshot.navigationSnapshot.permissionKind,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        pageBackground: this.snapshot.theme.pageBackground,
        surfaceBackground: this.snapshot.theme.surfaceBackground,
        headerButtonBackground: this.snapshot.theme.headerButtonBackground,
        accentColor: this.snapshot.theme.headerIconColor,
        dividerColor: this.snapshot.theme.dividerColor,
        pressedBackground: this.snapshot.theme.pressedBackground,
        primaryTextColor: this.snapshot.theme.primaryTextColor,
        secondaryTextColor: this.snapshot.theme.secondaryTextColor,
        onBack: () => {
          this.onIntent(SettingsCenterPresentationIntent.backDetail());
        },
        onOpenWebAppDetail: (shortcutId: string) => {
          this.onIntent(SettingsCenterPresentationIntent.openWebAppDetail(shortcutId));
        },
        onOpenPermission: (host: string, origin: string, kind: SitePermissionKind) => {
          this.onIntent(SettingsCenterPresentationIntent.openWebAppPermission(host, origin, kind));
        },
        onOpenDesktopSite: (host: string, origin: string) => {
          this.onIntent(SettingsCenterPresentationIntent.openWebAppDesktopSite(host, origin));
        },
        onSettingsChanged: () => {
          this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
        }
      })
    } else {
      SettingsEmbeddedDetailPanel({
        customHomepagePageBinding: this.customHomepagePageBinding,
        shellFamily: 'large_screen',
        selectedDestination: this.snapshot.navigationSnapshot.selectedPrimaryDestination,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        surfaceBackground: this.snapshot.theme.surfaceBackground,
        dividerColor: this.snapshot.theme.dividerColor,
        accentColor: this.snapshot.theme.headerIconColor,
        onAccentColor: this.snapshot.theme.iconForegroundColor,
        pressedBackground: this.snapshot.theme.pressedBackground,
        primaryTextColor: this.snapshot.theme.primaryTextColor,
        secondaryTextColor: this.snapshot.theme.secondaryTextColor,
        revealTargetId: this.snapshot.navigationSnapshot.revealTargetId,
        revealRevision: this.snapshot.navigationSnapshot.revealRevision,
        settingsRefreshRevision: this.snapshot.settingsRefreshRevision,
        onSelectDestination: (destination: SettingsCenterDestination) => {
          this.onIntent(SettingsCenterPresentationIntent.selectDestination(destination));
        },
        onOpenAppProxySettings: () => {
          this.onIntent(SettingsCenterPresentationIntent.openAppProxySettings());
        },
        onOpenEmbeddedSubpage: (subpageId: string) => {
          this.onIntent(SettingsCenterPresentationIntent.openEmbeddedSubpage(subpageId));
        },
        onOpenUserScriptGallerySource: (url: string) => {
          this.onIntent(SettingsCenterPresentationIntent.openUserScriptGallerySource(url));
        },
        onSettingsChanged: () => {
          this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
        }
      })
    }
  }

  @Builder
  private buildEmbeddedSubpagePanel() {
    if (this.snapshot.navigationSnapshot.activePanelKind === 'local_backup') {
      LocalBackupScreen({
        embedded: true,
        desktopPresentation: true,
        useCenteredImportDialog: true,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        onBack: () => {
          this.onIntent(SettingsCenterPresentationIntent.backDetail());
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'keyboard_shortcuts') {
      KeyboardShortcutsContent({ desktopPresentation: true })
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'app_icon') {
      AppIconSettingsContent({ desktopPresentation: true })
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'theme_palette') {
      ThemePaletteSettingsContent({
        desktopPresentation: true,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode
      })
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'tablet_interface_mode') {
      SettingsPresentationScrollBody({ desktopPresentation: true, topPadding: 16 }) {
        BrowserTabletInterfaceModeSettingsContent({
          surfaceBackground: this.snapshot.theme.surfaceBackground,
          dividerColor: this.snapshot.theme.dividerColor,
          accentColor: this.snapshot.theme.headerIconColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          dataScope: this.snapshot.boundary.dataScope,
          privacyMode: this.snapshot.boundary.privacyMode,
          desktopPresentation: true,
          onSettingsChanged: (): void => {
            this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
          }
        })
      }
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'tracking_protection') {
      SettingsPresentationScrollBody({ desktopPresentation: true, topPadding: 16 }) {
        BrowserTrackingProtectionSettingsContent({
          surfaceBackground: this.snapshot.theme.surfaceBackground,
          dividerColor: this.snapshot.theme.dividerColor,
          accentColor: this.snapshot.theme.headerIconColor,
          primaryTextColor: this.snapshot.theme.primaryTextColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          pressedBackground: this.snapshot.theme.pressedBackground,
          desktopPresentation: true,
          dataScope: this.snapshot.boundary.dataScope,
          privacyMode: this.snapshot.boundary.privacyMode,
          onSettingsChanged: (): void => {
            this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
          }
        })
      }
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'external_navigation') {
      SettingsPresentationScrollBody({ desktopPresentation: true, topPadding: 16 }) {
        SiteControlsExternalNavigationDefaultContent({
          surfaceBackground: this.snapshot.theme.surfaceBackground,
          dividerColor: this.snapshot.theme.dividerColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          accentColor: this.snapshot.theme.headerIconColor,
          dataScope: this.snapshot.boundary.dataScope,
          privacyMode: this.snapshot.boundary.privacyMode,
          desktopPresentation: true,
          onPolicyApplied: (): void => {
            this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
          }
        })
      }
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'cookie_management') {
      SettingsPresentationScrollBody({ desktopPresentation: true, topPadding: 16 }) {
        CookieManagementContent({
          surfaceBackground: this.snapshot.theme.surfaceBackground,
          dividerColor: this.snapshot.theme.dividerColor,
          accentColor: this.snapshot.theme.headerIconColor,
          pressedBackground: this.snapshot.theme.pressedBackground,
          primaryTextColor: this.snapshot.theme.primaryTextColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          dataScope: this.snapshot.boundary.dataScope,
          privacyMode: this.snapshot.boundary.privacyMode,
          desktopPresentation: true,
          onPolicyApplied: (): void => {
            this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
          }
        })
      }
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'secure_dns') {
      SettingsPresentationScrollBody({ desktopPresentation: true, topPadding: 16 }) {
        SecureDnsSettingsContent({
          surfaceBackground: this.snapshot.theme.surfaceBackground,
          dividerColor: this.snapshot.theme.dividerColor,
          accentColor: this.snapshot.theme.headerIconColor,
          pressedBackground: this.snapshot.theme.pressedBackground,
          primaryTextColor: this.snapshot.theme.primaryTextColor,
          secondaryTextColor: this.snapshot.theme.secondaryTextColor,
          dataScope: this.snapshot.boundary.dataScope,
          privacyMode: this.snapshot.boundary.privacyMode,
          desktopPresentation: true,
          onSettingsChanged: (): void => {
            this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
          },
          onEditCustomProfile: (profileId: string): void => {
            this.secureDnsEditorProfileId = profileId;
            this.secureDnsEditorVisible = true;
          }
        })
      }
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'search_built_in_engines') {
      SearchBuiltInEnginesHost({
        embedded: true,
        desktopPresentation: true,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        revealTargetId: this.snapshot.navigationSnapshot.revealTargetId,
        revealRevision: this.snapshot.navigationSnapshot.revealRevision,
        onBack: () => {
          this.onIntent(SettingsCenterPresentationIntent.backDetail());
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'download_settings_option') {
      BrowserDownloadSettingsOptionScreen({
        subpage: this.snapshot.navigationSnapshot.subpageId as BrowserDownloadSettingsSubpage,
        desktopPresentation: true,
        showBackButton: false,
        showTitleBar: false,
        useTopSafeInset: false,
        onBack: () => {
          this.onIntent(SettingsCenterPresentationIntent.backDetail());
        },
        onSettingsChanged: () => {
          this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'adblock_rules') {
      AdBlockCustomRulesHost({
        embedded: true,
        desktopPresentation: true,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        onBack: () => {
          this.onIntent(SettingsCenterPresentationIntent.backDetail());
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'adblock_hidden_elements') {
      ManualElementHideHost({
        embedded: true,
        desktopPresentation: true,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        onBack: () => {
          this.onIntent(SettingsCenterPresentationIntent.backDetail());
        }
      })
        .width('100%')
        .height('100%')
    } else if (this.snapshot.navigationSnapshot.activePanelKind === 'toolbar_scroll_behavior') {
      BrowserToolbarCustomizationScreen({
        desktopPresentation: true,
        initialDesktopView: 'scroll_behavior',
        showDesktopHeader: false,
        showTitleBar: false,
        showBackButton: false,
        useTopSafeInset: false,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        onSettingsChanged: () => {
          this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
        }
      })
        .width('100%')
        .height('100%')
    } else {
      SettingsEmbeddedDetailPanel({
        customHomepagePageBinding: this.customHomepagePageBinding,
        shellFamily: 'large_screen',
        selectedDestination: this.snapshot.navigationSnapshot.activeDestination,
        dataScope: this.snapshot.boundary.dataScope,
        privacyMode: this.snapshot.boundary.privacyMode,
        boundarySource: this.snapshot.boundary.boundarySource,
        surfaceBackground: this.snapshot.theme.surfaceBackground,
        dividerColor: this.snapshot.theme.dividerColor,
        accentColor: this.snapshot.theme.headerIconColor,
        onAccentColor: this.snapshot.theme.iconForegroundColor,
        pressedBackground: this.snapshot.theme.pressedBackground,
        primaryTextColor: this.snapshot.theme.primaryTextColor,
        secondaryTextColor: this.snapshot.theme.secondaryTextColor,
        revealTargetId: this.snapshot.navigationSnapshot.revealTargetId,
        revealRevision: this.snapshot.navigationSnapshot.revealRevision,
        settingsRefreshRevision: this.snapshot.settingsRefreshRevision,
        onSelectDestination: (destination: SettingsCenterDestination) => {
          this.onIntent(SettingsCenterPresentationIntent.selectDestination(destination));
        },
        onOpenAppProxySettings: () => {
          this.onIntent(SettingsCenterPresentationIntent.openAppProxySettings());
        },
        onOpenEmbeddedSubpage: (subpageId: string) => {
          this.onIntent(SettingsCenterPresentationIntent.openEmbeddedSubpage(subpageId));
        },
        onOpenUserScriptGallerySource: (url: string) => {
          this.onIntent(SettingsCenterPresentationIntent.openUserScriptGallerySource(url));
        },
        onSettingsChanged: () => {
          this.onIntent(SettingsCenterPresentationIntent.settingsChanged());
        }
      })
    }
  }

  private isPrivateContext(): boolean {
    return this.snapshot.boundary.dataScope === 'session_ephemeral' || this.snapshot.boundary.privacyMode === 'private';
  }

  private shouldShowWorkspaceHeader(): boolean {
    if (this.secureDnsEditorVisible && this.snapshot.navigationSnapshot.activePanelKind === 'secure_dns') {
      return false;
    }
    if (this.snapshot.navigationSnapshot.detailDepth <= 1) {
      return false;
    }
    return this.snapshot.navigationSnapshot.activePanelKind !== 'adblock_rules' &&
      this.snapshot.navigationSnapshot.activePanelKind !== 'adblock_hidden_elements';
  }

  private closeSecureDnsEditor(): void {
    this.secureDnsEditorVisible = false;
    this.secureDnsEditorProfileId = '';
  }

  private resolveMenuRowKey(row: SettingsCenterRowState): string {
    return `large-menu-${row.id}-${row.value}-${row.isEnabled ? '1' : '0'}-` +
      `${this.snapshot.navigationSnapshot.selectedPrimaryDestination === row.id ? '1' : '0'}`;
  }
}

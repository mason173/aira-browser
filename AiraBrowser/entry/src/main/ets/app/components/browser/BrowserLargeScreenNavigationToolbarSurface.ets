import { inputMethod } from '@kit.IMEKit';
import {
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchSuggestion,
  SitePermissionKind,
  SitePermissionRule
} from '../../../common/models/BrowserModels';
import {
  BrowserLargeScreenActiveTabChromePresentation
} from '../../../core/browser/BrowserLargeScreenPresentationViewModel';
import {
  BrowserLargeScreenOmniboxPresentation,
  createBrowserLargeScreenOmniboxPresentation
} from '../../../core/browser/BrowserLargeScreenSearchInvocationAdapter';
import {
  BrowserLargeScreenNavigationIntent
} from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import {
  BrowserSearchSuggestionSnapshot
} from '../../../core/browser/BrowserSearchSuggestionCoordinator';
import {
  BrowserBottomAddressPanelAction,
  resolveBrowserBottomAddressPanelActionAiraIconId
} from '../../../core/browser/BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelActionSnapshot } from '../../../core/browser/BrowserBottomPanelActionPresentationCoordinator';
import {
  BROWSER_LARGE_SCREEN_OVERFLOW_MENU_GROUP_HEADER_HEIGHT_VP,
  BROWSER_LARGE_SCREEN_OVERFLOW_MENU_SECTION_GAP_VP,
  BrowserLargeScreenToolbarMenuEntry,
  BrowserLargeScreenToolbarMenuHeight,
  BrowserLargeScreenToolbarMenuPageToolGroup,
  BrowserLargeScreenToolbarMenuPlan,
  BrowserLargeScreenToolbarMenuSection,
  BrowserLargeScreenToolbarMenuViewModel,
  resolveBrowserLargeScreenOverflowMenuHeight
} from '../../../core/browser/BrowserLargeScreenToolbarMenuViewModel';
import { BrowserLargeScreenInputProfile } from '../../../core/browser/BrowserLargeScreenTabStripViewModel';
import {
  BrowserBookmarkActionSessionSnapshot,
  BrowserBookmarkFolderSelectionAction
} from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';
import { BrowserLargeScreenAccountPopover } from './BrowserLargeScreenAccountPopover';
import { BrowserLargeScreenBookmarkPopover } from './BrowserLargeScreenBookmarkPopover';
import { BrowserSiteInfoSheet } from './BrowserSiteInfoSheet';
import {
  BrowserLargeScreenOmniboxSearchSurface,
  BrowserLargeScreenSearchEngineButton
} from './BrowserLargeScreenOmniboxSearchSurface';
import {
  BrowserSearchEngineChromePresentation
} from '../../../core/browser/BrowserSearchEnginePresentationViewModel';
import {
  BrowserSiteControlsApplicationSnapshot,
  BrowserSiteControlsUserAction,
  DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT
} from '../../../core/browser/BrowserSiteControlsRuntimeCoordinator';
import {
  BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP
} from '../../../core/browser/BrowserModalPresentationTokens';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP,
  BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP,
  BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BrowserLargeScreenWebZoomAction,
  BrowserLargeScreenWebZoomSnapshot,
  createBrowserLargeScreenWebZoomSnapshot
} from '../../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import {
  BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP,
  BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP,
  BrowserLargeScreenOverflowBookmarkItem,
  BrowserLargeScreenOverflowHistoryItem
} from '../../../core/browser/BrowserLargeScreenOverflowFlyoutViewModel';
import { BrowserLargeScreenOverflowFlyoutHost } from './BrowserLargeScreenOverflowFlyout';
import {
  BrowserUserScriptApplicationAction,
  BrowserUserScriptApplicationSnapshot,
  createBrowserUserScriptApplicationSnapshot
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import { UserScriptPageActionsSheet } from '../userscripts/UserScriptPageActionsSheet';
import { BrowserCrossDeviceTabsSheet } from './BrowserCrossDeviceTabsOverlay';
import { CrossDeviceTabsEmptyAction } from '../../../core/deviceTabs/CrossDeviceTabsEmptyPresentation';
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';

const LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP: number = 48;
const LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP: number = 34;
const LARGE_SCREEN_NAVIGATION_ICON_SIZE_VP: number = 17;
const LARGE_SCREEN_OMNIBOX_HEIGHT_VP: number = 36;
const LARGE_SCREEN_OMNIBOX_RADIUS_VP: number = 18;
const LARGE_SCREEN_OMNIBOX_FOCUS_ID: string = 'aira-large-screen-omnibox';
const LARGE_SCREEN_OMNIBOX_FOCUS_DELAY_MS: number = 24;
const LARGE_SCREEN_OMNIBOX_SELECTION_DELAY_MS: number = 0;
const LARGE_SCREEN_OMNIBOX_BLUR_COLLAPSE_DELAY_MS: number = 120;
const LARGE_SCREEN_OVERFLOW_MENU_WIDTH_VP: number = 272;
const LARGE_SCREEN_OVERFLOW_FLYOUT_CLOSE_DELAY_MS: number = 200;
const LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP: number = 28;
const LARGE_SCREEN_OVERFLOW_MENU_WINDOW_MARGIN_VP: number = 8;
const LARGE_SCREEN_SITE_INFO_BUTTON_SIZE_VP: number = 28;
const LARGE_SCREEN_SITE_INFO_POPUP_WIDTH_VP: number = 520;
const LARGE_SCREEN_SITE_INFO_POPUP_HEIGHT_VP: number = 580;
const LARGE_SCREEN_USER_SCRIPT_POPUP_WIDTH_VP: number = 420;
const LARGE_SCREEN_USER_SCRIPT_POPUP_HEIGHT_VP: number = 560;
const LARGE_SCREEN_CROSS_DEVICE_TABS_POPUP_WIDTH_VP: number = 420;
const LARGE_SCREEN_CROSS_DEVICE_TABS_POPUP_HEIGHT_VP: number = 560;
type BrowserLargeScreenNavigationControlKind = 'back' | 'forward' | 'reload_or_stop';

const EMPTY_ACTIVE_TAB_CHROME: BrowserLargeScreenActiveTabChromePresentation = {
  scene: 'home',
  tabId: '',
  title: '新标签页',
  displayUrl: '',
  nativeRouteUrl: '',
  canGoBack: false,
  canGoForward: false,
  loading: false,
  privateMode: false
};

const EMPTY_SEARCH_SUGGESTION_SNAPSHOT: BrowserSearchSuggestionSnapshot = {
  homeSearchFocused: false,
  homeSearchOverlayVisible: false,
  showSearchSuggestions: false,
  searchSuggestions: []
};

const EMPTY_BOOKMARK_ACTION_SESSION: BrowserBookmarkActionSessionSnapshot = {
  actionVersion: 0,
  scope: 'regular',
  addToHome: false,
  preparing: false,
  options: []
};

const EMPTY_SEARCH_ENGINE_PRESENTATION: BrowserSearchEngineChromePresentation =
  new BrowserSearchEngineChromePresentation('bing', [], '搜索或输入网址');

@Component
export struct BrowserLargeScreenNavigationToolbarSurface {
  @Prop
  activeTabChrome: BrowserLargeScreenActiveTabChromePresentation = EMPTY_ACTIVE_TAB_CHROME;
  @Prop
  @Watch('syncOmniboxFocusRequest')
  omniboxPresentation: BrowserLargeScreenOmniboxPresentation = createBrowserLargeScreenOmniboxPresentation();
  @Prop suggestionSnapshot: BrowserSearchSuggestionSnapshot = EMPTY_SEARCH_SUGGESTION_SNAPSHOT;
  @Prop searchEnginePresentation: BrowserSearchEngineChromePresentation = EMPTY_SEARCH_ENGINE_PRESENTATION;
  @Prop actionSnapshot: BrowserBottomPanelActionSnapshot | undefined = undefined;
  @Prop bookmarkActionSession: BrowserBookmarkActionSessionSnapshot = EMPTY_BOOKMARK_ACTION_SESSION;
  @Prop @Watch('syncSiteInfoPopup') siteInfoVisible: boolean = false;
  @Prop siteControlsSnapshot: BrowserSiteControlsApplicationSnapshot =
    DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT;
  @Prop webZoomSnapshot: BrowserLargeScreenWebZoomSnapshot = createBrowserLargeScreenWebZoomSnapshot();
  @Prop userScriptApplicationSnapshot: BrowserUserScriptApplicationSnapshot =
    createBrowserUserScriptApplicationSnapshot();
  @Prop inputProfile: BrowserLargeScreenInputProfile = 'touch';
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onIntent: (intent: BrowserLargeScreenNavigationIntent) => void =
    (_intent: BrowserLargeScreenNavigationIntent): void => {};
  onUserScriptAction: (action: BrowserUserScriptApplicationAction) => void =
    (_action: BrowserUserScriptApplicationAction): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  private omniboxController: TextInputController = new TextInputController();
  private focusRequestTimer: number = -1;
  private selectionRequestTimer: number = -1;
  private omniboxBlurCollapseTimer: number = -1;
  private scheduledOmniboxFocusRequestVersion: number = 0;
  private pendingOmniboxSelectionRequestVersion: number = 0;
  private pendingOmniboxSelection: 'all' | 'preserve' | 'caret_end' = 'preserve';
  private lastOmniboxEditing: boolean = false;
  private omniboxRefocusRequired: boolean = false;
  @State private omniboxInputFocused: boolean = false;
  @State private omniboxDraftText: string = '';
  @State private siteInfoPopupVisible: boolean = false;
  @State private crossDeviceTabsPopupVisible: boolean = false;
  @State private hoveredOverflowActionId: string = '';
  @State private overflowMenuVisible: boolean = false;
  @State private overflowFlyoutKind: string = '';
  @State private overflowFlyoutColumnCount: number = 0;
  private overflowFlyoutCloseTimer: number = -1;
  private toolbarMenuViewModel: BrowserLargeScreenToolbarMenuViewModel =
    new BrowserLargeScreenToolbarMenuViewModel();
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();

  aboutToDisappear(): void {
    this.clearFocusRequest();
    this.clearSelectionRequest();
    this.clearOmniboxBlurCollapse();
    this.clearOverflowFlyoutTimer();
    this.onIntent({ kind: 'set_omnibox_editing', text: '', omniboxEditing: false });
  }

  aboutToAppear(): void {
    this.lastOmniboxEditing = this.omniboxPresentation.editing;
    this.omniboxDraftText = this.omniboxPresentation.draft;
    this.onIntent({
      kind: 'set_omnibox_editing',
      text: '',
      omniboxEditing: this.omniboxPresentation.editing
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 4 }) {
        this.buildNavigationButton('back')
        this.buildNavigationButton('forward')
        this.buildNavigationButton('reload_or_stop')

        Column({ space: 0 }) {
          Row({ space: 6 }) {
            this.buildOmniboxLeadingButtonSlot()

            TextInput({
              text: this.resolveOmniboxText(),
              placeholder: this.searchEnginePresentation.placeholder,
              controller: this.omniboxController
            })
            .id(LARGE_SCREEN_OMNIBOX_FOCUS_ID)
            .layoutWeight(1)
            .height(LARGE_SCREEN_OMNIBOX_HEIGHT_VP)
            .fontSize(14)
            .fontColor(this.storedPrimaryTextColor)
            .placeholderColor(this.storedSecondaryTextColor)
            .caretColor(this.storedAccentColor)
            .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
            .padding({ left: 0, right: 0, top: 0, bottom: 0 })
            .enterKeyType(EnterKeyType.Go)
            .focusable(this.omniboxPresentation.editing)
            .focusOnTouch(this.omniboxPresentation.editing)
            .enableKeyboardOnFocus(this.omniboxPresentation.editing)
            .onAppear(() => {
              this.syncOmniboxFocusRequest();
            })
            .onFocus(() => {
              if (!this.omniboxPresentation.editing) {
                return;
              }
              this.clearOmniboxBlurCollapse();
              this.omniboxInputFocused = true;
              this.scheduleOmniboxSelectionIfPending();
            })
            .onClick(() => {
              if (!this.omniboxPresentation.editing || this.omniboxRefocusRequired) {
                this.omniboxRefocusRequired = false;
                this.onIntent({ kind: 'activate_omnibox', text: '' });
              }
            })
            .onBlur(() => {
              this.omniboxRefocusRequired = this.omniboxPresentation.editing;
              this.scheduleOmniboxBlurCollapse();
            })
            .onChange((value: string) => {
              if (!this.omniboxPresentation.editing) {
                return;
              }
              this.omniboxDraftText = value;
              this.onIntent({ kind: 'update_omnibox_draft', text: value });
            })
            .onSubmit((_enterKey: EnterKeyType) => {
              this.onIntent({ kind: 'submit_omnibox', text: this.resolveOmniboxText() });
            })

            if (this.shouldShowBookmarkButton()) {
              BrowserLargeScreenBookmarkPopover({
                actionEnabled: this.actionSnapshot?.actionInput.bookmarksEnabled === true,
                actionSelected: this.actionSnapshot?.actionInput.bookmarksActionSelected === true,
                disabledMessage: this.actionSnapshot?.actionInput.bookmarksActionDisabledMessage ?? '',
                session: this.bookmarkActionSession,
                viewportWidthVp: this.viewportWidthVp,
                viewportHeightVp: this.viewportHeightVp,
                popupReservedTopVp: this.popupReservedTopVp,
                onOpen: (): void => {
                  this.onIntent({ kind: 'open_bookmark_popup', text: '' });
                },
                onAction: (action: BrowserBookmarkFolderSelectionAction): void => {
                  this.onIntent({ kind: 'bookmark_popup_action', text: '', bookmarkAction: action });
                }
              })
            }
          }
          .width('100%')
          .height(LARGE_SCREEN_OMNIBOX_HEIGHT_VP)
          .padding({ left: 12, right: 12 })
          .borderRadius(LARGE_SCREEN_OMNIBOX_RADIUS_VP)
          .backgroundColor(this.storedControlBackgroundColor)

          if (this.omniboxPresentation.editing) {
            BrowserLargeScreenOmniboxSearchSurface({
              editing: this.omniboxPresentation.editing,
              inputFocused: this.omniboxInputFocused,
              query: this.omniboxPresentation.draft,
              suggestions: this.suggestionSnapshot.searchSuggestions,
              onOpenSuggestion: (suggestion: SearchSuggestion): void => {
                this.onIntent({ kind: 'open_suggestion', text: suggestion.target, suggestion: suggestion });
              },
              onDeleteHistorySuggestion: (suggestion: SearchSuggestion): void => {
                this.onIntent({ kind: 'delete_history_suggestion', text: '', suggestion: suggestion });
              },
              onClearHistorySuggestions: (): void => {
                this.onIntent({ kind: 'clear_history_suggestions', text: '' });
              },
              onExternalAppSearch: (targetId: ExternalAppSearchTargetId, query: string): void => {
                this.onIntent({
                  kind: 'external_app_search',
                  text: query,
                  externalAppSearchTargetId: targetId
                });
              },
              viewportHeightVp: this.viewportHeightVp,
              popupReservedTopVp: this.popupReservedTopVp
            })
            .width('100%')
            .position({ x: 0, y: LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP })
            .zIndex(20)
          }
        }
        .layoutWeight(1)
        .height(LARGE_SCREEN_OMNIBOX_HEIGHT_VP)
        .clip(false)

        if (this.inputProfile !== 'touch') {
          // The account popover signs in to Huawei and opens Aira Pro, both Official-only
          // capabilities. Community has no Huawei project, cloud, or payment approval, so it
          // must not offer an account entry that can never complete.
          if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
            BrowserLargeScreenAccountPopover({
              privateMode: this.activeTabChrome.privateMode,
              viewportWidthVp: this.viewportWidthVp,
              viewportHeightVp: this.viewportHeightVp,
              popupReservedTopVp: this.popupReservedTopVp,
              onOpenAiraPro: (): void => {
                this.onIntent({
                  kind: 'open_settings_target',
                  text: '',
                  settingsDestination: 'aira_pro'
                });
              }
            })
          }

          this.buildCrossDeviceTabsButton()
          this.buildUserScriptButton()
        }

        this.buildOverflowButton()
      }
      .width('100%')
      .height(LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .border({
        width: { bottom: 1 },
        color: this.storedDividerColor
      })

    }
    .width('100%')
    .height(LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP)
    .clip(false)
  }

  @Builder
  private buildOmniboxLeadingButtonSlot() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.omniboxPresentation.editing) {
        BrowserLargeScreenSearchEngineButton({
          presentation: this.searchEnginePresentation,
          viewportWidthVp: this.viewportWidthVp,
          viewportHeightVp: this.viewportHeightVp,
          popupReservedTopVp: this.popupReservedTopVp,
          onSelectSearchEngine: (engineId: SearchEngineId): void => {
            this.onIntent({ kind: 'select_search_engine', text: '', searchEngineId: engineId });
          }
        })
      } else {
        this.buildSiteInfoButton()
      }
    }
    .width(LARGE_SCREEN_SITE_INFO_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_SITE_INFO_BUTTON_SIZE_VP)
  }

  @Builder
  private buildSiteInfoButton() {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        AiraIcon({
          airaIconId: this.activeTabChrome.privateMode
            ? 'browser.toolbar.privacyMode'
            : 'browser.toolbar.connectionSecurity',
          iconSize: 15,
          iconColor: this.storedSecondaryTextColor
        })
      }
    }
    .width(LARGE_SCREEN_SITE_INFO_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_SITE_INFO_BUTTON_SIZE_VP)
    .backgroundColor(Color.Transparent)
    .stateEffect(this.activeTabChrome.scene === 'web')
    .enabled(this.activeTabChrome.scene === 'web')
    .accessibilityText(this.shouldShowSiteInfoProtectionFeedback()
      ? `${this.siteControlsSnapshot.webProtectionFeedback.accessibilityLabel}，打开网页保护报告`
      : '站点信息')
    .onClick(() => {
      this.onIntent({ kind: 'open_site_info', text: '' });
    })
    .bindPopup(this.siteInfoPopupVisible, {
      builder: this.buildSiteInfoPopup,
      placement: Placement.BottomLeft,
      popupColor: this.storedSurfaceBackgroundColor,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: 6,
      width: this.resolvePopupWidth(LARGE_SCREEN_SITE_INFO_POPUP_WIDTH_VP),
      onStateChange: (event: PopupStateChangeParam) => {
        const wasVisible = this.siteInfoPopupVisible;
        this.siteInfoPopupVisible = event.isVisible;
        if (wasVisible && !event.isVisible && this.siteInfoVisible) {
          this.onIntent({
            kind: 'site_info_action',
            text: '',
            siteControlsAction: 'close'
          });
        }
      }
    })
  }

  @Builder
  private buildSiteInfoPopup() {
    Column() {
      BrowserSiteInfoSheet({
        snapshot: this.siteControlsSnapshot,
        onAction: (
          action: BrowserSiteControlsUserAction,
          permissionKind?: SitePermissionKind,
          permissionRule?: SitePermissionRule
        ): void => {
          this.onIntent({
            kind: 'site_info_action',
            text: '',
            siteControlsAction: action,
            permissionKind: permissionKind,
            permissionRule: permissionRule
          });
        }
      })
    }
    .width(this.resolvePopupWidth(LARGE_SCREEN_SITE_INFO_POPUP_WIDTH_VP))
    .height(this.resolvePopupHeight(LARGE_SCREEN_SITE_INFO_POPUP_HEIGHT_VP))
    .borderRadius(BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP)
    .clip(true)
  }

  private syncSiteInfoPopup(): void {
    this.siteInfoPopupVisible = this.siteInfoVisible;
  }

  @Builder
  private buildCrossDeviceTabsButton() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.tabs',
        iconSize: LARGE_SCREEN_NAVIGATION_ICON_SIZE_VP,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText('跨设备标签页')
    .onClick(() => {
      this.crossDeviceTabsPopupVisible = true;
    })
    .bindPopup(this.crossDeviceTabsPopupVisible, {
      builder: this.buildCrossDeviceTabsPopup,
      placement: Placement.BottomRight,
      popupColor: this.storedSurfaceBackgroundColor,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: 6,
      width: this.resolvePopupWidth(LARGE_SCREEN_CROSS_DEVICE_TABS_POPUP_WIDTH_VP),
      onStateChange: (event: PopupStateChangeParam): void => {
        this.crossDeviceTabsPopupVisible = event.isVisible;
      }
    })
  }

  @Builder
  private buildCrossDeviceTabsPopup() {
    Column() {
      Text('跨设备标签页')
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .padding({ left: 16, right: 16, top: 14, bottom: 6 })

      Column() {
        BrowserCrossDeviceTabsSheet({
          privacyMode: this.activeTabChrome.privateMode ? 'private' : 'regular',
          dataScope: this.activeTabChrome.privateMode ? 'session_ephemeral' : 'profile_persistent',
          onNavigate: (action: CrossDeviceTabsEmptyAction): boolean => this.handleCrossDeviceEmptyNavigate(action),
          onOpenRemoteTab: (url: string, title: string): void => {
            this.crossDeviceTabsPopupVisible = false;
            this.onIntent({ kind: 'open_external_url', text: '', url: url, title: title });
          }
        })
      }
      .width('100%')
      .layoutWeight(1)

      Divider()
        .color(this.storedDividerColor)
        .strokeWidth(BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP)
        .margin({ left: 16, right: 16 })

      this.buildCrossDeviceScanRow()
    }
    .width(this.resolvePopupWidth(LARGE_SCREEN_CROSS_DEVICE_TABS_POPUP_WIDTH_VP))
    .height(this.resolvePopupHeight(LARGE_SCREEN_CROSS_DEVICE_TABS_POPUP_HEIGHT_VP))
    .borderRadius(BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP)
    .clip(true)
  }

  private handleCrossDeviceEmptyNavigate(action: CrossDeviceTabsEmptyAction): boolean {
    if (action === 'sign_in' || action === 'enable_link' || action === 'refresh' || action === 'none') {
      return false;
    }
    this.crossDeviceTabsPopupVisible = false;
    if (action === 'open_pro') {
      this.onIntent({ kind: 'open_settings_target', text: '', settingsDestination: 'aira_pro' });
      return true;
    }
    if (action === 'open_sync_settings') {
      this.onIntent({ kind: 'open_settings_target', text: '', settingsDestination: 'sync' });
      return true;
    }
    if (action === 'open_setup') {
      this.onIntent({ kind: 'open_settings_target', text: '', settingsDestination: 'cross_device_link' });
      return true;
    }
    return false;
  }

  @Builder
  private buildUserScriptButton() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.userScripts',
        iconSize: LARGE_SCREEN_NAVIGATION_ICON_SIZE_VP,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText('当前页用户脚本')
    .onClick(() => {
      this.onUserScriptAction({ type: 'open_page_actions' });
    })
    .bindPopup(this.userScriptApplicationSnapshot.pageActionsPopupVisible, {
      builder: this.buildUserScriptPopup,
      placement: Placement.BottomRight,
      popupColor: this.storedSurfaceBackgroundColor,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: 6,
      width: this.resolvePopupWidth(LARGE_SCREEN_USER_SCRIPT_POPUP_WIDTH_VP),
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible && this.userScriptApplicationSnapshot.pageActionsPopupVisible) {
          this.onUserScriptAction({ type: 'dismiss_page_actions' });
        }
      }
    })
  }

  @Builder
  private buildUserScriptPopup() {
    Column() {
      UserScriptPageActionsSheet({
        state: this.userScriptApplicationSnapshot.pageActionsState,
        layoutMode: 'large_screen',
        showHeader: true,
        onAction: (action: BrowserUserScriptApplicationAction): void => {
          this.onUserScriptAction(action);
        }
      })
    }
    .width(this.resolvePopupWidth(LARGE_SCREEN_USER_SCRIPT_POPUP_WIDTH_VP))
    .height(this.resolvePopupHeight(LARGE_SCREEN_USER_SCRIPT_POPUP_HEIGHT_VP))
    .borderRadius(BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP)
    .clip(true)
  }

  @Builder
  private buildOverflowButton() {
    if (this.inputProfile === 'touch') {
      this.buildTouchOverflowButton()
    } else {
      this.buildPointerOverflowButton()
    }
  }

  @Builder
  private buildTouchOverflowButton() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.more',
        iconSize: LARGE_SCREEN_NAVIGATION_ICON_SIZE_VP,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText('更多浏览器工具')
    .bindMenu(this.buildOverflowMenu(), {
      placement: Placement.BottomRight,
      offset: { x: 0, y: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP },
      enableArrow: false,
      showInSubWindow: false,
      borderRadius: BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
      layoutRegionMargin: {
        left: LARGE_SCREEN_OVERFLOW_MENU_WINDOW_MARGIN_VP,
        right: LARGE_SCREEN_OVERFLOW_MENU_WINDOW_MARGIN_VP,
        top: LARGE_SCREEN_OVERFLOW_MENU_WINDOW_MARGIN_VP,
        bottom: LARGE_SCREEN_OVERFLOW_MENU_WINDOW_MARGIN_VP
      }
    })
  }

  @Builder
  private buildPointerOverflowButton() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.more',
        iconSize: LARGE_SCREEN_NAVIGATION_ICON_SIZE_VP,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText('更多浏览器工具')
    .onClick((): void => {
      this.overflowMenuVisible = true;
    })
    .bindPopup(this.overflowMenuVisible, {
      builder: this.buildPointerOverflowPopup,
      placement: Placement.BottomRight,
      popupColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
      width: this.resolveOverflowPopupWidth(),
      radius: 0,
      borderWidth: 0,
      outlineWidth: 0,
      shadow: {
        radius: 0,
        color: '#00000000',
        offsetX: 0,
        offsetY: 0
      },
      showInSubWindow: false,
      focusable: true,
      onStateChange: (event: PopupStateChangeParam): void => {
        this.overflowMenuVisible = event.isVisible;
        if (!event.isVisible) {
          this.closeOverflowFlyout();
        }
      }
    })
  }

  @Builder
  private buildCrossDeviceScanRow() {
    Row({ space: 10 }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.scanQr',
        iconSize: 18,
        iconColor: this.storedPrimaryTextColor
      })
      Text('扫一扫')
        .layoutWeight(1)
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .margin({ bottom: 8 })
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText('扫一扫')
    .onClick((): void => {
      this.crossDeviceTabsPopupVisible = false;
      this.onIntent({ kind: 'open_browser_action', text: '', actionId: 'scanQr' });
    })
  }

  @Builder
  private buildOverflowMenu() {
    Menu() {
      this.buildTouchOverflowItems()
    }
    .width(LARGE_SCREEN_OVERFLOW_MENU_WIDTH_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
      right: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
      top: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
      bottom: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
    })
    .radius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
  }

  @Builder
  private buildTouchOverflowItems() {
    ForEach(this.resolveOverflowActions(), (item: BrowserBottomAddressPanelAction) => {
      this.buildOverflowMenuItem(item)
    }, (item: BrowserBottomAddressPanelAction) => this.buildOverflowMenuItemKey(item))
  }

  @Builder
  private buildPointerOverflowPopup() {
    Row() {
      if (this.overflowFlyoutKind.length > 0) {
        BrowserLargeScreenOverflowFlyoutHost({
          kind: this.overflowFlyoutKind,
          privateMode: this.activeTabChrome.privateMode,
          canAddBookmark: this.activeTabChrome.scene === 'web',
          maxHeightVp: this.resolvePointerOverflowMenuHeight().heightVp,
          onColumnCountChange: (count: number): void => {
            this.overflowFlyoutColumnCount = count;
          },
          onHoverChange: (hovered: boolean): void => {
            if (hovered) {
              this.clearOverflowFlyoutTimer();
              return;
            }
            this.scheduleOverflowFlyoutClose();
          },
          onOpenHistory: (item: BrowserLargeScreenOverflowHistoryItem): void => {
            this.closeOverflowMenu();
            this.onIntent({
              kind: 'open_history_visit',
              text: '',
              url: item.url,
              title: item.title
            });
          },
          onOpenBookmark: (item: BrowserLargeScreenOverflowBookmarkItem): void => {
            this.closeOverflowMenu();
            this.onIntent({
              kind: 'open_bookmark_node',
              text: '',
              url: item.url,
              title: item.title
            });
          },
          onAddBookmark: (): void => {
            this.closeOverflowMenu();
            this.onIntent({ kind: 'open_bookmark_popup', text: '' });
          },
          onOpenManager: (): void => {
            this.closeOverflowMenu();
            this.onIntent({ kind: 'open_bookmarks', text: '' });
          }
        })
      }
      this.buildPointerOverflowMenuColumn()
    }
    .width(this.resolveOverflowPopupWidth())
    // Bleed only on the sides away from the anchor. Top or right padding, or a
    // negative offset, makes the system slide this tall popup up to the window edge.
    .padding({
      left: BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP,
      bottom: BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP
    })
    .alignItems(VerticalAlign.Top)
    .justifyContent(FlexAlign.End)
  }

  @Builder
  private buildPointerOverflowMenuColumn() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.resolvePointerMenu().sections, (section: BrowserLargeScreenToolbarMenuSection, index: number) => {
            if (index > 0) {
              this.buildPointerOverflowSectionGap()
            }
            this.buildPointerOverflowSection(section)
          }, (section: BrowserLargeScreenToolbarMenuSection) => section.id)
        }
        .width('100%')
        .padding({
          left: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
          right: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
          top: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
          bottom: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
        })
      }
      .width(LARGE_SCREEN_OVERFLOW_MENU_WIDTH_VP)
      .height(this.resolvePointerOverflowMenuHeight().heightVp)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(this.resolvePointerOverflowMenuHeight().scrollable ? BarState.Auto : BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
      .clip(true)
      .borderRadius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
    }
    .width(LARGE_SCREEN_OVERFLOW_MENU_WIDTH_VP)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
    .clip(false)
    .shadow({
      radius: BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP
    })
  }

  @Builder
  private buildPointerOverflowSection(section: BrowserLargeScreenToolbarMenuSection) {
    Column() {
      ForEach(section.items, (entry: BrowserLargeScreenToolbarMenuEntry) => {
        if (entry.activation === 'web_zoom') {
          this.buildPointerOverflowZoomRow()
        } else {
          this.buildPointerOverflowRow(entry)
        }
      }, (entry: BrowserLargeScreenToolbarMenuEntry) => this.buildPointerOverflowMenuItemKey(entry))
      ForEach(section.pageTools, (group: BrowserLargeScreenToolbarMenuPageToolGroup) => {
        this.buildPointerOverflowToolGroup(group)
      }, (group: BrowserLargeScreenToolbarMenuPageToolGroup) => group.id)
    }
    .width('100%')
  }

  @Builder
  private buildPointerOverflowToolGroup(group: BrowserLargeScreenToolbarMenuPageToolGroup) {
    Column() {
      if (group.title.length > 0) {
        Row() {
          Text(group.title)
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
        }
        .width('100%')
        .height(BROWSER_LARGE_SCREEN_OVERFLOW_MENU_GROUP_HEADER_HEIGHT_VP)
        .padding({
          left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
          right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
        })
        .alignItems(VerticalAlign.Center)
      }
      ForEach(group.items, (entry: BrowserLargeScreenToolbarMenuEntry) => {
        if (entry.activation === 'web_zoom') {
          this.buildPointerOverflowZoomRow()
        } else {
          this.buildPointerOverflowRow(entry)
        }
      }, (entry: BrowserLargeScreenToolbarMenuEntry) => this.buildPointerOverflowMenuItemKey(entry))
    }
    .width('100%')
  }

  @Builder
  private buildPointerOverflowSectionGap() {
    Column() {
      Divider()
        .strokeWidth(BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP)
        .color(this.storedDividerColor)
        .margin({
          left: BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
          right: BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP
        })
    }
    .width('100%')
    .height(BROWSER_LARGE_SCREEN_OVERFLOW_MENU_SECTION_GAP_VP)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildPointerOverflowRow(entry: BrowserLargeScreenToolbarMenuEntry) {
    Row() {
      this.buildOverflowMenuItemContent(entry.action, entry.showsSelection)
    }
    .width('100%')
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .backgroundColor(this.resolveOverflowMenuItemBackground(entry.action))
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(HoverEffect.None)
    .onHover((hovered: boolean): void => {
      this.handlePointerOverflowHover(entry.action.id, hovered);
    })
    .onClick((): void => {
      this.hoveredOverflowActionId = '';
      this.closeOverflowMenu();
      this.dispatchOverflowEntry(entry);
    })
  }

  @Builder
  private buildPointerOverflowZoomRow() {
    Row({ space: 8 }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.search',
        iconSize: 18,
        iconColor: this.storedPrimaryTextColor
      })
      Text('缩放')
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
      Blank()
        .layoutWeight(1)
      if (this.webZoomSnapshot.canDecrease) {
        this.buildOverflowZoomButton('browser.toolbar.zoomOut', '缩小网页', 'decrease', true)
      } else {
        this.buildOverflowZoomButton('browser.toolbar.zoomOut', '缩小网页', 'decrease', false)
      }
      Text(this.webZoomSnapshot.percentLabel)
        .width(48)
        .fontSize(13)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .opacity(this.webZoomSnapshot.available ? 1 : 0.38)
        .onClick((): void => {
          this.applyOverflowZoom('reset');
        })
      if (this.webZoomSnapshot.canIncrease) {
        this.buildOverflowZoomButton('browser.toolbar.zoomIn', '放大网页', 'increase', true)
      } else {
        this.buildOverflowZoomButton('browser.toolbar.zoomIn', '放大网页', 'increase', false)
      }
      Divider()
        .vertical(true)
        .strokeWidth(1)
        .height(16)
        .color(this.storedDividerColor)
      this.buildOverflowFullscreenButton()
    }
    .width('100%')
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
      right: 6
    })
    .alignItems(VerticalAlign.Center)
    .onHover((hovered: boolean): void => {
      if (hovered) {
        this.closeOverflowFlyout();
      }
    })
  }

  @Builder
  private buildOverflowZoomButton(
    iconId: AiraRenderableIconId,
    label: string,
    action: BrowserLargeScreenWebZoomAction,
    enabled: boolean
  ) {
    Row() {
      AiraIcon({
        airaIconId: iconId,
        iconSize: 14,
        iconColor: enabled ? this.storedPrimaryTextColor : this.storedSecondaryTextColor
      })
    }
    .width(LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP)
    .constraintSize({ minWidth: LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP / 2)
    .enabled(enabled && this.webZoomSnapshot.available)
    .opacity(enabled && this.webZoomSnapshot.available ? 1 : 0.38)
    .accessibilityText(label)
    .onClick((): void => {
      if (action === 'decrease' && !this.webZoomSnapshot.canDecrease) {
        return;
      }
      if (action === 'increase' && !this.webZoomSnapshot.canIncrease) {
        return;
      }
      this.applyOverflowZoom(action);
    })
  }

  @Builder
  private buildOverflowFullscreenButton() {
    Row() {
      AiraIcon({
        airaIconId: 'browser.toolbar.fullScreen',
        iconSize: 14,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP)
    .constraintSize({ minWidth: LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(LARGE_SCREEN_OVERFLOW_ZOOM_BUTTON_SIZE_VP / 2)
    .opacity(this.activeTabChrome.scene === 'web' ? 1 : 0.38)
    .accessibilityText('全屏模式')
    .onClick((): void => {
      this.toggleOverflowFullscreen();
    })
  }

  @Builder
  private buildOverflowMenuItem(item: BrowserBottomAddressPanelAction) {
    MenuItem(() => {
      this.buildOverflowMenuItemContent(item, false)
    })
    .padding(0)
    .backgroundColor(this.resolveOverflowMenuItemBackground(item))
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(HoverEffect.None)
    .onHover((hovered: boolean): void => {
      this.hoveredOverflowActionId = hovered
        ? item.id
        : (this.hoveredOverflowActionId === item.id ? '' : this.hoveredOverflowActionId);
    })
    .onClick(() => {
      this.hoveredOverflowActionId = '';
      this.dispatchOverflowAction(item);
    })
  }

  @Builder
  private buildOverflowMenuItemContent(item: BrowserBottomAddressPanelAction, showsSelection: boolean) {
    Row({ space: 10 }) {
      AiraIcon({
        airaIconId: item.airaIconId ?? resolveBrowserBottomAddressPanelActionAiraIconId(item.id),
        iconSize: 18,
        iconColor: item.selected === true ? this.storedAccentColor : this.storedPrimaryTextColor
      })

      Text(item.title)
        .layoutWeight(1)
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (showsSelection && item.selected === true) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.storedAccentColor])
      }
      if (this.inputProfile !== 'touch' && this.isOverflowSubmenuAction(item.id)) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(12)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width('100%')
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
      right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
    })
    .opacity(item.enabled ? 1 : 0.38)
  }

  @Builder
  private buildNavigationButton(kind: BrowserLargeScreenNavigationControlKind) {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: this.resolveNavigationButtonIcon(kind),
        iconSize: LARGE_SCREEN_NAVIGATION_ICON_SIZE_VP,
        iconColor: this.isNavigationButtonEnabled(kind)
          ? this.storedPrimaryTextColor
          : this.storedSecondaryTextColor
      })
    }
    .width(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_NAVIGATION_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(this.isNavigationButtonEnabled(kind))
    .enabled(this.isNavigationButtonEnabled(kind))
    .opacity(this.isNavigationButtonEnabled(kind) ? 1 : 0.38)
    .accessibilityText(this.resolveNavigationButtonAccessibilityText(kind))
    .onClick(() => {
      this.onIntent({ kind: kind, text: '' });
    })
  }

  private isNavigationButtonEnabled(kind: BrowserLargeScreenNavigationControlKind): boolean {
    if (kind === 'back') {
      return this.activeTabChrome.canGoBack;
    }
    if (kind === 'forward') {
      return this.activeTabChrome.canGoForward;
    }
    return this.activeTabChrome.scene === 'web';
  }

  private resolveNavigationButtonIcon(kind: BrowserLargeScreenNavigationControlKind): AiraRenderableIconId {
    if (kind === 'reload_or_stop') {
      return this.activeTabChrome.loading ? 'browser.tabs.delete' : 'browser.toolbar.refresh';
    }
    return kind === 'forward' ? 'browser.toolbar.forward' : 'browser.toolbar.back';
  }

  private resolveNavigationButtonAccessibilityText(kind: BrowserLargeScreenNavigationControlKind): string {
    if (kind === 'back') {
      return '后退';
    }
    if (kind === 'forward') {
      return '前进';
    }
    return this.activeTabChrome.loading ? '停止加载' : '刷新';
  }

  private resolveOverflowActions(): BrowserBottomAddressPanelAction[] {
    return this.toolbarMenuViewModel.resolveActions(
      this.actionSnapshot,
      this.inputProfile,
      this.webZoomSnapshot.available
    );
  }

  private resolvePointerMenu(): BrowserLargeScreenToolbarMenuPlan {
    return this.toolbarMenuViewModel.resolvePointerMenu(
      this.actionSnapshot,
      this.webZoomSnapshot.available
    );
  }

  private resolvePointerOverflowMenuHeight(): BrowserLargeScreenToolbarMenuHeight {
    return resolveBrowserLargeScreenOverflowMenuHeight(
      this.resolvePointerMenu(),
      this.viewportHeightVp,
      this.popupReservedTopVp + BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP
    );
  }

  private shouldShowBookmarkButton(): boolean {
    return this.inputProfile !== 'touch' && this.activeTabChrome.scene === 'web';
  }

  private buildOverflowMenuItemKey(item: BrowserBottomAddressPanelAction): string {
    return `${item.id}:${item.renderVersion ?? 0}:${item.selected === true ? 1 : 0}:${item.enabled ? 1 : 0}`;
  }

  private buildPointerOverflowMenuItemKey(entry: BrowserLargeScreenToolbarMenuEntry): string {
    return `${entry.activation}:${entry.showsSelection ? 1 : 0}:${this.buildOverflowMenuItemKey(entry.action)}:${entry.action.title}`;
  }

  private resolveOverflowMenuItemBackground(item: BrowserBottomAddressPanelAction): ResourceColor {
    return this.isOverflowRowHighlighted(item.id)
      ? this.storedControlBackgroundColor
      : Color.Transparent;
  }

  private isOverflowRowHighlighted(actionId: string): boolean {
    if (this.hoveredOverflowActionId === actionId) {
      return true;
    }
    return (actionId === 'history' && this.overflowFlyoutKind === 'history') ||
      (actionId === 'openBookmarks' && this.overflowFlyoutKind === 'bookmarks');
  }

  private isOverflowSubmenuAction(actionId: string): boolean {
    return actionId === 'history' || actionId === 'openBookmarks';
  }

  private resolveOverflowPopupWidth(): number {
    const flyoutSpan = this.overflowFlyoutColumnCount *
      (BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_WIDTH_VP + BROWSER_LARGE_SCREEN_OVERFLOW_FLYOUT_GAP_VP);
    return LARGE_SCREEN_OVERFLOW_MENU_WIDTH_VP + flyoutSpan + BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP;
  }

  private handlePointerOverflowHover(actionId: string, hovered: boolean): void {
    this.hoveredOverflowActionId = hovered
      ? actionId
      : (this.hoveredOverflowActionId === actionId ? '' : this.hoveredOverflowActionId);
    if (!hovered) {
      if (this.isOverflowSubmenuAction(actionId)) {
        this.scheduleOverflowFlyoutClose();
      }
      return;
    }
    if (actionId === 'history') {
      this.showOverflowFlyout('history');
      return;
    }
    if (actionId === 'openBookmarks') {
      this.showOverflowFlyout('bookmarks');
      return;
    }
    this.closeOverflowFlyout();
  }

  private showOverflowFlyout(kind: string): void {
    this.clearOverflowFlyoutTimer();
    if (this.overflowFlyoutKind !== kind) {
      this.overflowFlyoutColumnCount = 1;
    } else if (this.overflowFlyoutColumnCount < 1) {
      this.overflowFlyoutColumnCount = 1;
    }
    this.overflowFlyoutKind = kind;
  }

  private scheduleOverflowFlyoutClose(): void {
    this.clearOverflowFlyoutTimer();
    this.overflowFlyoutCloseTimer = setTimeout((): void => {
      this.overflowFlyoutCloseTimer = -1;
      this.overflowFlyoutKind = '';
      this.overflowFlyoutColumnCount = 0;
    }, LARGE_SCREEN_OVERFLOW_FLYOUT_CLOSE_DELAY_MS);
  }

  private closeOverflowFlyout(): void {
    this.clearOverflowFlyoutTimer();
    this.overflowFlyoutKind = '';
    this.overflowFlyoutColumnCount = 0;
  }

  private closeOverflowMenu(): void {
    this.closeOverflowFlyout();
    this.overflowMenuVisible = false;
  }

  private clearOverflowFlyoutTimer(): void {
    if (this.overflowFlyoutCloseTimer < 0) {
      return;
    }
    clearTimeout(this.overflowFlyoutCloseTimer);
    this.overflowFlyoutCloseTimer = -1;
  }

  private applyOverflowZoom(action: BrowserLargeScreenWebZoomAction): void {
    if (!this.webZoomSnapshot.available) {
      return;
    }
    if (action === 'decrease' && !this.webZoomSnapshot.canDecrease) {
      return;
    }
    if (action === 'increase' && !this.webZoomSnapshot.canIncrease) {
      return;
    }
    this.onIntent({
      kind: 'web_zoom',
      text: '',
      zoomAction: action,
      presentZoomDialog: false
    });
  }

  private toggleOverflowFullscreen(): void {
    if (this.activeTabChrome.scene !== 'web') {
      return;
    }
    this.closeOverflowMenu();
    this.onIntent({ kind: 'open_browser_action', text: '', actionId: 'fullScreenMode' });
  }

  private dispatchOverflowAction(item: BrowserBottomAddressPanelAction): void {
    if (!item.enabled) {
      const message = item.disabledMessage.trim();
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      }
      return;
    }
    if (this.inputProfile !== 'touch' && item.id === 'textZoom') {
      this.onIntent({ kind: 'open_web_zoom_dialog', text: '' });
      return;
    }
    this.onIntent({ kind: 'open_browser_action', text: '', actionId: item.id });
  }

  private dispatchOverflowEntry(entry: BrowserLargeScreenToolbarMenuEntry): void {
    const item = entry.action;
    if (!item.enabled) {
      const message = item.disabledMessage.trim();
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      }
      return;
    }
    if (entry.activation === 'web_zoom') {
      this.onIntent({ kind: 'open_web_zoom_dialog', text: '' });
      return;
    }
    if (entry.activation === 'user_script_management') {
      this.onIntent({ kind: 'open_user_scripts', text: '' });
      return;
    }
    this.onIntent({ kind: 'open_browser_action', text: '', actionId: item.id });
  }

  private resolveOmniboxText(): string {
    if (this.omniboxPresentation.editing) {
      return this.omniboxDraftText;
    }
    return this.activeTabChrome.displayUrl;
  }

  private shouldShowSiteInfoProtectionFeedback(): boolean {
    const feedback = this.siteControlsSnapshot.webProtectionFeedback;
    return feedback.visible && feedback.tabId === this.activeTabChrome.tabId;
  }

  private syncOmniboxFocusRequest(): void {
    const shouldReleaseEditing = this.lastOmniboxEditing && !this.omniboxPresentation.editing;
    if (this.omniboxPresentation.editing !== this.lastOmniboxEditing) {
      this.lastOmniboxEditing = this.omniboxPresentation.editing;
      this.onIntent({
        kind: 'set_omnibox_editing',
        text: '',
        omniboxEditing: this.omniboxPresentation.editing
      });
      if (this.omniboxPresentation.editing) {
        this.omniboxRefocusRequired = false;
        this.omniboxDraftText = this.omniboxPresentation.draft;
      }
    }
    if (shouldReleaseEditing) {
      this.releaseOmniboxEditing();
    }
    if (!this.omniboxPresentation.editing) {
      this.clearFocusRequest();
      this.clearSelectionRequest();
      this.omniboxInputFocused = false;
      return;
    }
    if (!this.omniboxPresentation.focusRequestPending) {
      return;
    }
    const requestVersion = this.omniboxPresentation.requestVersion;
    if (requestVersion <= 0 || requestVersion === this.scheduledOmniboxFocusRequestVersion) {
      return;
    }
    this.scheduledOmniboxFocusRequestVersion = requestVersion;
    this.clearFocusRequest();
    this.clearSelectionRequest();
    this.pendingOmniboxSelectionRequestVersion = requestVersion;
    this.pendingOmniboxSelection = this.omniboxPresentation.selection;
    this.focusRequestTimer = setTimeout(() => {
      this.focusRequestTimer = -1;
      if (!this.omniboxPresentation.editing || this.omniboxPresentation.requestVersion !== requestVersion) {
        this.clearSelectionRequest();
        return;
      }
      const accepted = focusControl.requestFocus(LARGE_SCREEN_OMNIBOX_FOCUS_ID);
      if (!accepted) {
        this.clearSelectionRequest();
        return;
      }
      this.scheduleOmniboxSelectionIfPending();
    }, LARGE_SCREEN_OMNIBOX_FOCUS_DELAY_MS);
    this.onIntent({
      kind: 'ack_omnibox_focus_request',
      text: '',
      focusRequestVersion: requestVersion
    });
  }

  private clearFocusRequest(): void {
    if (this.focusRequestTimer >= 0) {
      clearTimeout(this.focusRequestTimer);
      this.focusRequestTimer = -1;
    }
  }

  private scheduleOmniboxSelectionIfPending(): void {
    const requestVersion = this.pendingOmniboxSelectionRequestVersion;
    const selection = this.pendingOmniboxSelection;
    if (requestVersion <= 0 || !this.omniboxInputFocused || this.selectionRequestTimer >= 0) {
      return;
    }
    this.selectionRequestTimer = setTimeout(() => {
      this.selectionRequestTimer = -1;
      if (this.pendingOmniboxSelectionRequestVersion !== requestVersion) {
        return;
      }
      this.pendingOmniboxSelectionRequestVersion = 0;
      if (!this.omniboxInputFocused || !this.omniboxPresentation.editing ||
        this.omniboxPresentation.requestVersion !== requestVersion) {
        return;
      }
      if (selection === 'all') {
        this.omniboxController.setTextSelection(0, this.omniboxPresentation.draft.length, {
          menuPolicy: MenuPolicy.HIDE
        });
      } else if (selection === 'caret_end') {
        const caret = this.omniboxPresentation.draft.length;
        this.omniboxController.setTextSelection(caret, caret, { menuPolicy: MenuPolicy.HIDE });
      }
    }, LARGE_SCREEN_OMNIBOX_SELECTION_DELAY_MS);
  }

  private clearSelectionRequest(): void {
    this.pendingOmniboxSelectionRequestVersion = 0;
    this.pendingOmniboxSelection = 'preserve';
    if (this.selectionRequestTimer >= 0) {
      clearTimeout(this.selectionRequestTimer);
      this.selectionRequestTimer = -1;
    }
  }

  private releaseOmniboxEditing(): void {
    this.clearOmniboxBlurCollapse();
    this.omniboxRefocusRequired = false;
    this.omniboxController.stopEditing();
    this.getUIContext().getFocusController().clearFocus();
    inputMethod.getController().hideTextInput()
      .catch((_error: Error): void => {
      });
  }

  private scheduleOmniboxBlurCollapse(): void {
    this.clearOmniboxBlurCollapse();
    this.omniboxBlurCollapseTimer = setTimeout(() => {
      this.omniboxBlurCollapseTimer = -1;
      this.omniboxInputFocused = false;
    }, LARGE_SCREEN_OMNIBOX_BLUR_COLLAPSE_DELAY_MS);
  }

  private clearOmniboxBlurCollapse(): void {
    if (this.omniboxBlurCollapseTimer >= 0) {
      clearTimeout(this.omniboxBlurCollapseTimer);
      this.omniboxBlurCollapseTimer = -1;
    }
  }

  private resolvePopupWidth(preferredWidth: number): number {
    return this.modalLayoutService.resolvePopupWidth(this.viewportWidthVp, preferredWidth);
  }

  private resolvePopupHeight(preferredHeight: number): number {
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      preferredHeight,
      this.popupReservedTopVp
    );
  }

}

import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserLargeScreenPresentationSnapshot
} from '../../../core/browser/BrowserLargeScreenPresentationViewModel';
import { BrowserLargeScreenSidePanelSurface } from './BrowserLargeScreenSidePanelSurface';
import { BrowserLargeScreenTopShellSurface } from './BrowserLargeScreenTopShellSurface';
import { BrowserQuickSearchSwitchBar } from './BrowserQuickSearchSwitchBar';
import {
  BrowserQuickSearchSwitchingPresentation,
  createHiddenBrowserQuickSearchSwitchingPresentation
} from '../../../core/search/BrowserQuickSearchSwitchingCoordinator';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserLargeScreenOmniboxPresentation,
  createBrowserLargeScreenOmniboxPresentation
} from '../../../core/browser/BrowserLargeScreenSearchInvocationAdapter';
import {
  BrowserLargeScreenNavigationIntent,
  BrowserLargeScreenTabStripIntent
} from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import { BrowserSearchSuggestionSnapshot } from '../../../core/browser/BrowserSearchSuggestionCoordinator';
import { BrowserBottomPanelActionSnapshot } from '../../../core/browser/BrowserBottomPanelActionPresentationCoordinator';
import { BrowserBookmarkActionSessionSnapshot } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import {
  BrowserSearchEngineChromePresentation
} from '../../../core/browser/BrowserSearchEnginePresentationViewModel';
import {
  BrowserSiteControlsApplicationSnapshot,
  DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT
} from '../../../core/browser/BrowserSiteControlsRuntimeCoordinator';
import {
  BrowserLargeScreenWebZoomSnapshot,
  createBrowserLargeScreenWebZoomSnapshot
} from '../../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import { BookmarkLargeScreenWorkspace } from '../bookmarks/BookmarkLargeScreenWorkspace';
import { HistoryLargeScreenWorkspace } from '../history/HistoryLargeScreenWorkspace';
import { SettingsCenterScreen } from '../settings/SettingsCenterScreen';
import { BrowserDownloadManagementScreen } from './BrowserDownloadManagementScreen';
import { UserScriptManagementHost } from '../userscripts/UserScriptManagementHost';
import { AppProxySettingsScreen } from '../settings/AppProxySettingsScreen';
import { OfflinePagesScreen } from '../offline/OfflinePagesScreen';
import { BrowserLargeScreenWebZoomNotification } from './BrowserLargeScreenWebZoomNotification';
import {
  BrowserUserScriptApplicationAction,
  BrowserUserScriptApplicationSnapshot,
  createBrowserUserScriptApplicationSnapshot
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import { BrowserDesktopBookmarkBarAction } from './BrowserLargeScreenBookmarkBar';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import {
  sharedBrowserLargeScreenWindowChromeService
} from '../../../services/browser/BrowserLargeScreenWindowChromeService';
import {
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { browserNativeTabSceneService } from '../../../core/browser/BrowserNativeTabSceneService';
import { SettingsCenterDestination } from '../../../core/settings/SettingsCenterViewModel';

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

// The top shell owns chrome overlays (including the omnibox search panels).
// Keep it above the main stage so positioned panels can extend below the
// fixed chrome row without being covered by the web/native content sibling.
const LARGE_SCREEN_TOP_SHELL_Z_INDEX: number = 20;
const LARGE_SCREEN_QUICK_SEARCH_BAR_HEIGHT_VP: number = 40;

/**
 * Structural Large-Screen Shell skeleton.
 *
 * This deliberately contains no visual tokens or product controls. It fixes
 * the macro regions that a later tablet/2-in-1 design will fill while keeping
 * the Web surface supplied by the stable host and the browser Session.
 */
@Component
export struct BrowserLargeScreenPrimarySurface {
  @Prop presentation: BrowserLargeScreenPresentationSnapshot | undefined = undefined;
  @Prop sidePanelVisible: boolean = false;
  @Prop bottomStatusVisible: boolean = false;
  @Prop omniboxPresentation: BrowserLargeScreenOmniboxPresentation =
    createBrowserLargeScreenOmniboxPresentation();
  @Prop suggestionSnapshot: BrowserSearchSuggestionSnapshot = EMPTY_SEARCH_SUGGESTION_SNAPSHOT;
  @Prop searchEnginePresentation: BrowserSearchEngineChromePresentation = EMPTY_SEARCH_ENGINE_PRESENTATION;
  @Prop actionSnapshot: BrowserBottomPanelActionSnapshot | undefined = undefined;
  @Prop bookmarkActionSession: BrowserBookmarkActionSessionSnapshot = EMPTY_BOOKMARK_ACTION_SESSION;
  @Prop siteInfoVisible: boolean = false;
  @Prop siteControlsSnapshot: BrowserSiteControlsApplicationSnapshot =
    DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT;
  @Prop webZoomSnapshot: BrowserLargeScreenWebZoomSnapshot = createBrowserLargeScreenWebZoomSnapshot();
  @Prop userScriptApplicationSnapshot: BrowserUserScriptApplicationSnapshot =
    createBrowserUserScriptApplicationSnapshot();
  @Prop nativeVideoTakeoverActive: boolean = false;
  @Prop quickSearchPresentation: BrowserQuickSearchSwitchingPresentation =
    createHiddenBrowserQuickSearchSwitchingPresentation();
  @Prop recentlyClosed: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  onSelectQuickSearchEngine: (engineId: string) => void = (_engineId: string): void => {};
  onTabStripIntent: (intent: BrowserLargeScreenTabStripIntent) => void =
    (_intent: BrowserLargeScreenTabStripIntent): void => {};
  onNavigationIntent: (intent: BrowserLargeScreenNavigationIntent) => void =
    (_intent: BrowserLargeScreenNavigationIntent): void => {};
  onUserScriptAction: (action: BrowserUserScriptApplicationAction) => void =
    (_action: BrowserUserScriptApplicationAction): void => {};
  onBookmarkBarAction: (action: BrowserDesktopBookmarkBarAction) => void =
    (_action: BrowserDesktopBookmarkBarAction): void => {};

  @BuilderParam webSurface: () => void = this.emptyBuilder;
  @BuilderParam sidePanel: () => void = this.emptyBuilder;
  @BuilderParam bottomStatus: () => void = this.emptyBuilder;

  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @State private viewportWidthVp: number = 0;
  @State private viewportHeightVp: number = 0;
  private titleBarWindowChromeLeaseId: string = '';

  aboutToAppear(): void {
    this.titleBarWindowChromeLeaseId = sharedBrowserLargeScreenWindowChromeService.activate(
      BrowserWindowRuntime.getActiveWindowId()
    );
  }

  aboutToDisappear(): void {
    sharedBrowserLargeScreenWindowChromeService.restoreLease(this.titleBarWindowChromeLeaseId);
    this.titleBarWindowChromeLeaseId = '';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Keep the hosted Web node in one stable Column -> Row -> Stack path for
      // the entire session. Reparenting the ArkWeb node when takeover starts can
      // detach its media surface on large screens even though audio continues.
      Column({ space: 0 }) {
        if (!this.nativeVideoTakeoverActive) {
          BrowserLargeScreenTopShellSurface({
        windowChromeLeaseId: this.titleBarWindowChromeLeaseId,
        presentation: this.presentation,
        omniboxPresentation: this.omniboxPresentation,
        suggestionSnapshot: this.suggestionSnapshot,
        searchEnginePresentation: this.searchEnginePresentation,
        actionSnapshot: this.actionSnapshot,
        bookmarkActionSession: this.bookmarkActionSession,
        siteInfoVisible: this.siteInfoVisible,
        siteControlsSnapshot: this.siteControlsSnapshot,
        webZoomSnapshot: this.webZoomSnapshot,
        userScriptApplicationSnapshot: this.userScriptApplicationSnapshot,
        viewportWidthVp: this.viewportWidthVp,
        viewportHeightVp: this.viewportHeightVp,
        recentlyClosed: this.recentlyClosed,
        onTabStripIntent: (intent: BrowserLargeScreenTabStripIntent): void => {
          this.onTabStripIntent(intent);
        },
        onNavigationIntent: (intent: BrowserLargeScreenNavigationIntent): void => {
          this.onNavigationIntent(intent);
        },
        onUserScriptAction: (action: BrowserUserScriptApplicationAction): void => {
          this.onUserScriptAction(action);
        },
        onBookmarkBarAction: (action: BrowserDesktopBookmarkBarAction): void => {
          this.onBookmarkBarAction(action);
        }
          })
          .zIndex(LARGE_SCREEN_TOP_SHELL_Z_INDEX)
          .visibility(Visibility.Visible)

      // Quick search-engine switch bar. On phone this lives in the web top-chrome
      // overlay; the large-screen shell has its own chrome, so surface it here as
      // a chrome row that reserves space (pushing the web stage down) when active.
          if (this.quickSearchPresentation.visible) {
            Row() {
              BrowserQuickSearchSwitchBar({
                presentation: this.quickSearchPresentation,
                surfaceColor: this.storedPageBackgroundColor,
                onSelectEngine: (engineId: string): void => {
                  this.onSelectQuickSearchEngine(engineId);
                }
              })
            }
            .width('100%')
            .height(LARGE_SCREEN_QUICK_SEARCH_BAR_HEIGHT_VP)
            .backgroundColor(this.storedPageBackgroundColor)
          }
        }

          Row({ space: 0 }) {
            if (this.shouldRenderSidePanelOnLeft()) {
              this.buildSidePanelSurface()
            }

            Stack({ alignContent: Alignment.Top }) {
              this.buildMainStageSurface()

              BrowserLargeScreenWebZoomNotification({
                snapshot: this.webZoomSnapshot
              })
            }
            .layoutWeight(1)
            .height('100%')
            .zIndex(0)

            if (this.shouldRenderSidePanelOnRight()) {
              this.buildSidePanelSurface()
            }
          }
          .layoutWeight(1)
          .width('100%')

          if (this.shouldRenderBottomStatus()) {
            this.bottomStatus()
          }
        }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportSize(newArea);
    })
  }

  private updateViewportSize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.viewportWidthVp) {
      this.viewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.viewportHeightVp) {
      this.viewportHeightVp = height;
    }
  }

  private shouldRenderSidePanelOnLeft(): boolean {
    return this.shouldRenderSidePanel() && this.presentation?.sidePanel.position === 'left';
  }

  private shouldRenderSidePanelOnRight(): boolean {
    return this.shouldRenderSidePanel() &&
      (this.presentation === undefined || this.presentation.sidePanel.position === 'right');
  }

  private shouldRenderSidePanel(): boolean {
    if (this.nativeVideoTakeoverActive) {
      return false;
    }
    return this.presentation === undefined ? this.sidePanelVisible : this.presentation.sidePanel.visible;
  }

  private shouldRenderBottomStatus(): boolean {
    if (this.nativeVideoTakeoverActive) {
      return false;
    }
    return this.presentation === undefined ? this.bottomStatusVisible : this.presentation.bottomStatusVisible;
  }

  @Builder
  private buildMainStageSurface() {
    if (this.presentation?.activeTabChrome.scene === 'bookmarks') {
      BookmarkLargeScreenWorkspace({
        tabId: this.presentation.activeTabChrome.tabId,
        routeUrl: this.presentation.activeTabChrome.nativeRouteUrl,
        privateMode: this.presentation.activeTabChrome.privateMode,
        onRouteChange: (routeUrl: string): void => {
          this.onNavigationIntent({
            kind: 'update_bookmark_workspace_route',
            text: '',
            tabId: this.presentation?.activeTabChrome.tabId ?? '',
            url: routeUrl
          });
        },
        onOpenBookmark: (url: string, title: string, openInNewTab: boolean): void => {
          this.onNavigationIntent({
            kind: 'open_bookmark_node',
            text: '',
            url: url,
            title: title,
            openInNewTab: openInNewTab
          });
        }
      })
    } else if (this.presentation?.activeTabChrome.scene === 'history') {
      HistoryLargeScreenWorkspace({
        tabId: this.presentation.activeTabChrome.tabId,
        routeUrl: this.presentation.activeTabChrome.nativeRouteUrl,
        privateMode: this.presentation.activeTabChrome.privateMode,
        onRouteChange: (tabId: string, routeUrl: string): void => {
          this.onNavigationIntent({
            kind: 'update_history_workspace_route',
            text: '',
            tabId: tabId,
            url: routeUrl
          });
        },
        onOpenHistory: (url: string, title: string, openInNewTab: boolean): void => {
          this.onNavigationIntent({
            kind: 'open_history_visit',
            text: '',
            url: url,
            title: title,
            openInNewTab: openInNewTab
          });
        }
      })
    } else if (this.presentation?.activeTabChrome.scene === 'settings') {
      SettingsCenterScreen({
        presentationMode: 'native_tab',
        embeddedDataScope: this.resolveNativeTabDataScope(),
        embeddedPrivacyMode: this.resolveNativeTabPrivacyMode(),
        embeddedBoundarySource: 'large_screen_native_tab',
        requestedDestination: browserNativeTabSceneService.parseSettingsRoute(
          this.presentation.activeTabChrome.nativeRouteUrl
        ).destination,
        onPrimaryDestinationChanged: (destination: SettingsCenterDestination): void => {
          this.onNavigationIntent({
            kind: 'update_settings_workspace_route',
            text: '',
            tabId: this.presentation?.activeTabChrome.tabId,
            url: browserNativeTabSceneService.buildSettingsRoute({ destination: destination })
          });
        },
        onOpenAppProxySettings: (): void => {
          this.onNavigationIntent({ kind: 'open_app_proxy', text: '' });
        }
      })
    } else if (this.presentation?.activeTabChrome.scene === 'downloads') {
      BrowserDownloadManagementScreen({
        presentationMode: 'native_tab',
        embeddedDataScope: this.resolveNativeTabDataScope(),
        embeddedPrivacyMode: this.resolveNativeTabPrivacyMode()
      })
    } else if (this.presentation?.activeTabChrome.scene === 'user_scripts') {
      UserScriptManagementHost({
        presentationMode: 'native_tab',
        dataScope: this.resolveNativeTabDataScope(),
        privacyMode: this.resolveNativeTabPrivacyMode(),
        boundarySource: 'large_screen_native_tab',
        onRequestClose: (): void => {
          this.onNavigationIntent({ kind: 'close_active_tab', text: '' });
        },
        onRequestOpenGallerySource: (url: string): void => {
          this.onNavigationIntent({ kind: 'open_user_script_gallery', text: '', url: url });
        }
      })
    } else if (this.presentation?.activeTabChrome.scene === 'app_proxy') {
      AppProxySettingsScreen({
        presentationMode: 'native_tab',
        embeddedDataScope: this.resolveNativeTabDataScope(),
        embeddedPrivacyMode: this.resolveNativeTabPrivacyMode(),
        embeddedBoundarySource: 'large_screen_native_tab'
      })
    } else if (this.presentation?.activeTabChrome.scene === 'saved_pages') {
      OfflinePagesScreen({
        presentationMode: 'native_tab',
        dataScope: this.resolveNativeTabDataScope(),
        privacyMode: this.resolveNativeTabPrivacyMode(),
        onOpenOriginalPage: (url: string): void => {
          this.onNavigationIntent({ kind: 'open_saved_page_original', text: '', url: url });
        }
      })
    } else {
      this.webSurface()
    }
  }

  private resolveNativeTabDataScope(): string {
    return this.presentation?.activeTabChrome.privateMode === true
      ? 'session_ephemeral'
      : 'profile_persistent';
  }

  private resolveNativeTabPrivacyMode(): string {
    return this.presentation?.activeTabChrome.privateMode === true ? 'private' : 'regular';
  }

  @Builder
  private buildSidePanelSurface() {
    if (this.presentation !== undefined) {
      BrowserLargeScreenSidePanelSurface({
        presentation: this.presentation.sidePanel,
        content: this.buildSidePanelContent
      })
    } else {
      this.sidePanel()
    }
  }

  @Builder
  private buildSidePanelContent() {
    this.sidePanel()
  }

  @Builder
  private emptyBuilder() {
  }
}

import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserLargeScreenPresentationSnapshot } from '../../../core/browser/BrowserLargeScreenPresentationViewModel';
import {
  BrowserLargeScreenOmniboxPresentation,
  createBrowserLargeScreenOmniboxPresentation
} from '../../../core/browser/BrowserLargeScreenSearchInvocationAdapter';
import {
  BrowserLargeScreenNavigationIntent,
  BrowserLargeScreenTabStripIntent
} from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import {
  BrowserSearchSuggestionSnapshot
} from '../../../core/browser/BrowserSearchSuggestionCoordinator';
import { BrowserBottomPanelActionSnapshot } from '../../../core/browser/BrowserBottomPanelActionPresentationCoordinator';
import { BrowserBookmarkActionSessionSnapshot } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import {
  BrowserSearchEngineChromePresentation
} from '../../../core/browser/BrowserSearchEnginePresentationViewModel';
import {
  BrowserSiteControlsApplicationSnapshot,
  DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT
} from '../../../core/browser/BrowserSiteControlsRuntimeCoordinator';
import { BrowserLargeScreenNavigationToolbarSurface } from './BrowserLargeScreenNavigationToolbarSurface';
import { BrowserLargeScreenTabStripSurface } from './BrowserLargeScreenTabStripSurface';
import {
  BrowserDesktopBookmarkBarAction,
  BrowserLargeScreenBookmarkBar
} from './BrowserLargeScreenBookmarkBar';
import {
  BrowserLargeScreenWebZoomSnapshot,
  createBrowserLargeScreenWebZoomSnapshot
} from '../../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import {
  BrowserUserScriptApplicationAction,
  BrowserUserScriptApplicationSnapshot,
  createBrowserUserScriptApplicationSnapshot
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import { BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP
} from '../../../core/browser/BrowserLargeScreenTitleBarTokens';
import {
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';

const LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP: number = 48;
const LARGE_SCREEN_BOOKMARK_BAR_HEIGHT_VP: number = 36;
const LARGE_SCREEN_BASE_CHROME_LAYER_Z_INDEX: number = 0;
const LARGE_SCREEN_NAVIGATION_LAYER_Z_INDEX: number = 1;

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

/**
 * Stable structural host for the Large-Screen browser chrome.
 *
 * It renders the Huawei-style two-row ownership shape from Session and Search
 * Invocation presentation snapshots. It never reads browser owners or
 * WindowStage facts directly.
 */
@Component
export struct BrowserLargeScreenTopShellSurface {
  @Prop windowChromeLeaseId: string = '';
  @Prop presentation: BrowserLargeScreenPresentationSnapshot | undefined = undefined;
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
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  @Prop recentlyClosed: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  onTabStripIntent: (intent: BrowserLargeScreenTabStripIntent) => void =
    (_intent: BrowserLargeScreenTabStripIntent): void => {};
  onNavigationIntent: (intent: BrowserLargeScreenNavigationIntent) => void =
    (_intent: BrowserLargeScreenNavigationIntent): void => {};
  onUserScriptAction: (action: BrowserUserScriptApplicationAction) => void =
    (_action: BrowserUserScriptApplicationAction): void => {};
  onBookmarkBarAction: (action: BrowserDesktopBookmarkBarAction) => void =
    (_action: BrowserDesktopBookmarkBarAction): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_DESKTOP_BOOKMARK_BAR_VISIBLE_KEY)
  private storedBookmarkBarVisible: boolean = true;
  build() {
    Column({ space: 0 }) {
      if (this.presentation !== undefined) {
        BrowserLargeScreenTabStripSurface({
          windowChromeLeaseId: this.windowChromeLeaseId,
          presentation: this.presentation.tabStrip,
          recentlyClosed: this.recentlyClosed,
          inputProfile: this.presentation.inputProfile,
          viewportWidthVp: this.viewportWidthVp,
          viewportHeightVp: this.viewportHeightVp,
          onIntent: (intent: BrowserLargeScreenTabStripIntent): void => {
            this.onTabStripIntent(intent);
          }
        })
        .width('100%')
        .height(this.resolveTitleBarHeightVp())
      } else {
        Row()
          .width('100%')
          .height(this.resolveTitleBarHeightVp())
      }

      if (this.presentation !== undefined) {
        BrowserLargeScreenNavigationToolbarSurface({
          activeTabChrome: this.presentation.activeTabChrome,
          omniboxPresentation: this.omniboxPresentation,
          suggestionSnapshot: this.suggestionSnapshot,
          searchEnginePresentation: this.searchEnginePresentation,
          actionSnapshot: this.actionSnapshot,
          bookmarkActionSession: this.bookmarkActionSession,
          siteInfoVisible: this.siteInfoVisible,
          siteControlsSnapshot: this.siteControlsSnapshot,
          webZoomSnapshot: this.webZoomSnapshot,
          userScriptApplicationSnapshot: this.userScriptApplicationSnapshot,
          inputProfile: this.presentation.inputProfile,
          viewportWidthVp: this.viewportWidthVp,
          viewportHeightVp: this.viewportHeightVp,
          popupReservedTopVp: this.resolveNavigationPopupTopVp(),
          onIntent: (intent: BrowserLargeScreenNavigationIntent): void => {
            this.onNavigationIntent(intent);
          },
          onUserScriptAction: (action: BrowserUserScriptApplicationAction): void => {
            this.onUserScriptAction(action);
          }
        })
        .width('100%')
        .height(LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP)
        .zIndex(LARGE_SCREEN_NAVIGATION_LAYER_Z_INDEX)
      } else {
        Row()
          .width('100%')
          .height(LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP)
      }

      if (this.presentation !== undefined && this.storedBookmarkBarVisible) {
        BrowserLargeScreenBookmarkBar({
          privateMode: this.presentation.activeTabChrome.privateMode,
          availableWidthVp: this.viewportWidthVp,
          barEnabled: true,
          onAction: (action: BrowserDesktopBookmarkBarAction): void => {
            this.onBookmarkBarAction(action);
          }
        })
          .width('100%')
          .height(LARGE_SCREEN_BOOKMARK_BAR_HEIGHT_VP)
          .zIndex(LARGE_SCREEN_BASE_CHROME_LAYER_Z_INDEX)
      }
    }
    .width('100%')
    .height(this.resolveTotalHeight())
    // Reserve the system status-bar strip above the tab row so the tabs are
    // not pushed under the status bar on a tablet (immersive full-screen
    // layout). The strip is painted with the page background. On a 2-in-1/PC
    // window the inset collapses to ~0, so this is device-adaptive without a
    // device-type branch — mirroring Huawei's PcMainPage statusBarHeight.
    .padding({ top: this.resolveSafeTopInsetVp() })
    // Omnibox panels are positioned below the fixed navigation toolbar and
    // must be allowed to extend into the main-stage area.
    .clip(false)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private resolveSafeTopInsetVp(): number {
    const inset = this.presentation?.safeTopInsetVp ?? 0;
    return inset > 0 ? inset : 0;
  }

  private resolveTotalHeight(): number {
    const bookmarkBarHeight = this.presentation !== undefined && this.storedBookmarkBarVisible
      ? LARGE_SCREEN_BOOKMARK_BAR_HEIGHT_VP
      : 0;
    return this.resolveTitleBarHeightVp() + LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP + bookmarkBarHeight +
      this.resolveSafeTopInsetVp();
  }

  private resolveNavigationPopupTopVp(): number {
    return this.resolveTitleBarHeightVp() + LARGE_SCREEN_NAVIGATION_TOOLBAR_HEIGHT_VP +
      this.resolveSafeTopInsetVp();
  }

  private resolveTitleBarHeightVp(): number {
    return this.presentation?.tabStrip.titleBarHeightVp ?? BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP;
  }
}

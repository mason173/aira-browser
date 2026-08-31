import {
  BrowserShellPresentationSurface,
  BrowserShellPresentationSnapshot
} from '../../../core/browser/BrowserShellPresentationCoordinator';
import { BrowserLargeScreenPresentationSnapshot } from '../../../core/browser/BrowserLargeScreenPresentationViewModel';
import { BrowserTabsOverviewSceneRenderState } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSceneDriver';
import { BrowserLargeScreenPrimarySurface } from './BrowserLargeScreenPrimarySurface';
import {
  BrowserQuickSearchSwitchingPresentation,
  createHiddenBrowserQuickSearchSwitchingPresentation
} from '../../../core/search/BrowserQuickSearchSwitchingCoordinator';
import { BrowserPhonePrimarySurface } from './BrowserPhonePrimarySurface';
import { BrowserWebAppPrimarySurface } from './BrowserWebAppPrimarySurface';
import { BrowserShellPresentationUnavailableSurface } from './BrowserShellPresentationUnavailableSurface';
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
import {
  BrowserUserScriptApplicationAction,
  BrowserUserScriptApplicationSnapshot,
  createBrowserUserScriptApplicationSnapshot
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import { BrowserDesktopBookmarkBarAction } from './BrowserLargeScreenBookmarkBar';
import {
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';

const DEFAULT_BROWSER_TABS_OVERVIEW_SCENE_RENDER_STATE: BrowserTabsOverviewSceneRenderState = {
  homeLayerMounted: false,
  homeLiveContentMounted: false,
  homeBackdropLayerMounted: false,
  homeLayerInteractive: false,
  webLayerMounted: false,
  webLayerInteractive: false,
  cardsLayerMounted: false,
  cardsLayerOpacity: 0,
  cardsLayerInteractive: false,
  rootBottomPanelHostRetained: false
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

/**
 * Presentation-only mount point. The Session decides the surface; this host
 * only mounts the corresponding ArkUI adapter and forwards shaped content.
 */
@Component
export struct BrowserShellPrimarySurfaceHost {
  @Prop presentationSurface: BrowserShellPresentationSurface | undefined = undefined;
  @Prop presentationSnapshot: BrowserShellPresentationSnapshot | undefined = undefined;
  @Prop tabsOverviewSceneRenderState: BrowserTabsOverviewSceneRenderState =
    DEFAULT_BROWSER_TABS_OVERVIEW_SCENE_RENDER_STATE;
  @Prop showHomePage: boolean = false;
  @Prop largeScreenOmniboxPresentation: BrowserLargeScreenOmniboxPresentation =
    createBrowserLargeScreenOmniboxPresentation();
  @Prop searchSuggestionSnapshot: BrowserSearchSuggestionSnapshot = EMPTY_SEARCH_SUGGESTION_SNAPSHOT;
  @Prop largeScreenSearchEnginePresentation: BrowserSearchEngineChromePresentation = EMPTY_SEARCH_ENGINE_PRESENTATION;
  @Prop largeScreenActionSnapshot: BrowserBottomPanelActionSnapshot | undefined = undefined;
  @Prop largeScreenBookmarkActionSession: BrowserBookmarkActionSessionSnapshot = EMPTY_BOOKMARK_ACTION_SESSION;
  @Prop largeScreenSiteInfoVisible: boolean = false;
  @Prop largeScreenSiteControlsSnapshot: BrowserSiteControlsApplicationSnapshot =
    DEFAULT_BROWSER_SITE_CONTROLS_APPLICATION_SNAPSHOT;
  @Prop largeScreenWebZoomSnapshot: BrowserLargeScreenWebZoomSnapshot =
    createBrowserLargeScreenWebZoomSnapshot();
  @Prop userScriptApplicationSnapshot: BrowserUserScriptApplicationSnapshot =
    createBrowserUserScriptApplicationSnapshot();
  @Prop largeScreenNativeVideoTakeoverActive: boolean = false;
  @Prop largeScreenQuickSearchPresentation: BrowserQuickSearchSwitchingPresentation =
    createHiddenBrowserQuickSearchSwitchingPresentation();
  @Prop recentlyClosedApplicationSnapshot: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  onLargeScreenTabStripIntent: (intent: BrowserLargeScreenTabStripIntent) => void =
    (_intent: BrowserLargeScreenTabStripIntent): void => {};
  onLargeScreenNavigationIntent: (intent: BrowserLargeScreenNavigationIntent) => void =
    (_intent: BrowserLargeScreenNavigationIntent): void => {};
  onLargeScreenSelectQuickSearchEngine: (engineId: string) => void = (_engineId: string): void => {};
  onUserScriptAction: (action: BrowserUserScriptApplicationAction) => void =
    (_action: BrowserUserScriptApplicationAction): void => {};
  onLargeScreenBookmarkBarAction: (action: BrowserDesktopBookmarkBarAction) => void =
    (_action: BrowserDesktopBookmarkBarAction): void => {};

  @BuilderParam homeSurfaceSlot: () => void = this.emptyBuilder;
  @BuilderParam homeBackdropSurfaceSlot: () => void = this.emptyBuilder;
  @BuilderParam webSurfaceSlot: () => void = this.emptyBuilder;
  @BuilderParam sidePanelSlot: () => void = this.emptyBuilder;
  @BuilderParam bottomStatusSlot: () => void = this.emptyBuilder;

  build() {
    if (this.presentationSurface === 'large_screen') {
      BrowserLargeScreenPrimarySurface({
        presentation: this.resolveLargeScreenPresentation(),
        sidePanelVisible: this.resolveLargeScreenSidePanelVisible(),
        bottomStatusVisible: this.resolveLargeScreenBottomStatusVisible(),
        omniboxPresentation: this.largeScreenOmniboxPresentation,
        suggestionSnapshot: this.searchSuggestionSnapshot,
        searchEnginePresentation: this.largeScreenSearchEnginePresentation,
        actionSnapshot: this.largeScreenActionSnapshot,
        bookmarkActionSession: this.largeScreenBookmarkActionSession,
        siteInfoVisible: this.largeScreenSiteInfoVisible,
        siteControlsSnapshot: this.largeScreenSiteControlsSnapshot,
        webZoomSnapshot: this.largeScreenWebZoomSnapshot,
        userScriptApplicationSnapshot: this.userScriptApplicationSnapshot,
        nativeVideoTakeoverActive: this.largeScreenNativeVideoTakeoverActive,
        quickSearchPresentation: this.largeScreenQuickSearchPresentation,
        recentlyClosed: this.recentlyClosedApplicationSnapshot,
        onSelectQuickSearchEngine: (engineId: string): void => {
          this.onLargeScreenSelectQuickSearchEngine(engineId);
        },
        onTabStripIntent: (intent: BrowserLargeScreenTabStripIntent): void => {
          this.onLargeScreenTabStripIntent(intent);
        },
        onNavigationIntent: (intent: BrowserLargeScreenNavigationIntent): void => {
          this.onLargeScreenNavigationIntent(intent);
        },
        onUserScriptAction: (action: BrowserUserScriptApplicationAction): void => {
          this.onUserScriptAction(action);
        },
        onBookmarkBarAction: (action: BrowserDesktopBookmarkBarAction): void => {
          this.onLargeScreenBookmarkBarAction(action);
        },
        webSurface: () => {
          this.buildLargeScreenWebSurface()
        },
        sidePanel: this.emptyBuilder,
        bottomStatus: this.emptyBuilder
      })
    } else if (this.presentationSurface === 'web_app') {
      BrowserWebAppPrimarySurface({
        webSurface: () => {
          this.buildWebSurface()
        }
      })
    } else if (this.presentationSurface === undefined || this.presentationSurface === 'phone') {
      BrowserPhonePrimarySurface({
        homeLiveContentMounted: this.tabsOverviewSceneRenderState.homeLiveContentMounted,
        homeBackdropLayerMounted: this.tabsOverviewSceneRenderState.homeBackdropLayerMounted,
        webLayerMounted: this.tabsOverviewSceneRenderState.webLayerMounted,
        homeSurface: () => {
          this.buildHomeSurface()
        },
        homeBackdropSurface: () => {
          this.buildHomeBackdropSurface()
        },
        webSurface: () => {
          this.buildWebSurface()
        }
      })
    } else {
      BrowserShellPresentationUnavailableSurface()
    }
  }

  private resolveLargeScreenSidePanelVisible(): boolean {
    return this.presentationSnapshot?.largeScreenPresentation?.sidePanel.visible ?? false;
  }

  private resolveLargeScreenPresentation(): BrowserLargeScreenPresentationSnapshot | undefined {
    return this.presentationSnapshot?.largeScreenPresentation;
  }

  private resolveLargeScreenBottomStatusVisible(): boolean {
    return this.presentationSnapshot?.largeScreenPresentation?.bottomStatusVisible ?? false;
  }

  @Builder
  private emptyBuilder() {
  }

  @Builder
  private buildHomeSurface() {
    this.homeSurfaceSlot()
  }

  @Builder
  private buildHomeBackdropSurface() {
    this.homeBackdropSurfaceSlot()
  }

  @Builder
  private buildWebSurface() {
    this.webSurfaceSlot()
  }

  @Builder
  private buildLargeScreenWebSurface() {
    if (this.showHomePage) {
      Stack({ alignContent: Alignment.Top }) {
        this.homeSurfaceSlot()
      }
      .width('100%')
      .height('100%')
    } else {
      Stack({ alignContent: Alignment.Top }) {
        this.webSurfaceSlot()
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private buildSidePanel() {
    this.sidePanelSlot()
  }

  @Builder
  private buildBottomStatus() {
    this.bottomStatusSlot()
  }
}

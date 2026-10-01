import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTabsOverviewSceneDriver,
  shouldShowTabsOverviewHomeBackdrop,
  shouldUseHomeSurfaceForLargeScreen
} from
  '../main/ets/core/browser/tabsOverview/BrowserTabsOverviewSceneDriver';

export default function browserTabsOverviewSceneDriverTest(): void {
  describe('BrowserTabsOverviewSceneDriver', () => {
    it('uses the complete home surface behind a web-entry overview after settling', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      const renderState = driver.buildRenderState({
        sceneState: {
          phase: 'settled',
          backgroundMode: 'home',
          openedFromHome: false,
          activeTabIdAtOpen: 'tab-1',
          morphCoveredTabId: ''
        },
        showHomePage: false,
        showTabsSheet: true,
        keepHomeResident: false
      });

      expect(renderState.homeLiveContentMounted).assertTrue();
      expect(renderState.homeBackdropLayerMounted).assertFalse();
      expect(renderState.webLayerMounted).assertFalse();
      expect(renderState.cardsLayerMounted).assertTrue();
    });

    it('keeps the home surface path unchanged when opened from home', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      const renderState = driver.buildRenderState({
        sceneState: {
          phase: 'settled',
          backgroundMode: 'home',
          openedFromHome: true,
          activeTabIdAtOpen: 'home-tab',
          morphCoveredTabId: ''
        },
        showHomePage: true,
        showTabsSheet: true,
        keepHomeResident: false
      });

      expect(renderState.homeLiveContentMounted).assertTrue();
      expect(renderState.homeBackdropLayerMounted).assertFalse();
      expect(renderState.webLayerMounted).assertFalse();
    });

    it('uses home on large screens only while the tabs overview is mounted', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      const overviewRenderState = driver.buildRenderState({
        sceneState: {
          phase: 'settled',
          backgroundMode: 'home',
          openedFromHome: false,
          activeTabIdAtOpen: 'tab-1',
          morphCoveredTabId: ''
        },
        showHomePage: false,
        showTabsSheet: true,
        keepHomeResident: false
      });
      const residentHomeRenderState = driver.buildRenderState({
        sceneState: {
          phase: 'closed',
          backgroundMode: 'home',
          openedFromHome: false,
          activeTabIdAtOpen: '',
          morphCoveredTabId: ''
        },
        showHomePage: false,
        showTabsSheet: false,
        keepHomeResident: true
      });

      expect(shouldUseHomeSurfaceForLargeScreen(false, overviewRenderState)).assertTrue();
      expect(shouldUseHomeSurfaceForLargeScreen(false, residentHomeRenderState)).assertFalse();
      expect(shouldUseHomeSurfaceForLargeScreen(true, residentHomeRenderState)).assertTrue();
    });

    it('keeps a suppressed home subtree out of the large-screen home path', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      const renderState = driver.buildRenderState({
        sceneState: {
          phase: 'settled',
          backgroundMode: 'home',
          openedFromHome: false,
          activeTabIdAtOpen: 'tab-1',
          morphCoveredTabId: ''
        },
        showHomePage: false,
        showTabsSheet: true,
        keepHomeResident: false
      });

      // The driver itself never suppresses; the card-morph resolver in the shell does.
      expect(renderState.homeLiveContentSuppressed).assertFalse();
      renderState.homeLiveContentSuppressed = true;
      expect(shouldUseHomeSurfaceForLargeScreen(false, renderState)).assertFalse();
    });

    it('drops the resident home surface when closing onto a web tab', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      const renderState = driver.buildRenderState({
        sceneState: {
          phase: 'closing',
          backgroundMode: 'home',
          openedFromHome: true,
          activeTabIdAtOpen: 'home-tab',
          morphCoveredTabId: ''
        },
        showHomePage: false,
        showTabsSheet: true,
        keepHomeResident: true
      });

      expect(renderState.homeLiveContentMounted).assertFalse();
      expect(renderState.webLayerMounted).assertTrue();
      expect(shouldUseHomeSurfaceForLargeScreen(false, renderState)).assertFalse();
      expect(shouldShowTabsOverviewHomeBackdrop('closing', true, false)).assertFalse();
    });

    it('keeps the home surface when the close is returning home', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      const renderState = driver.buildRenderState({
        sceneState: {
          phase: 'closing',
          backgroundMode: 'home',
          openedFromHome: true,
          activeTabIdAtOpen: 'home-tab',
          morphCoveredTabId: ''
        },
        showHomePage: true,
        showTabsSheet: true,
        keepHomeResident: true
      });

      expect(renderState.homeLiveContentMounted).assertTrue();
      expect(renderState.webLayerMounted).assertFalse();
      expect(shouldShowTabsOverviewHomeBackdrop('closing', true, true)).assertTrue();
    });

    it('defers the home-reveal settle while a web-entry morph is still playing', 0, () => {
      const driver = new BrowserTabsOverviewSceneDriver();
      expect(driver.shouldDeferEntryAnimationSettle({
        phase: 'openingMorphingActiveTab',
        backgroundMode: 'home',
        openedFromHome: false,
        activeTabIdAtOpen: 'tab-1',
        morphCoveredTabId: 'tab-1'
      })).assertTrue();
      expect(driver.shouldDeferEntryAnimationSettle({
        phase: 'openingHomeCards',
        backgroundMode: 'home',
        openedFromHome: true,
        activeTabIdAtOpen: 'home-tab',
        morphCoveredTabId: ''
      })).assertFalse();
      expect(driver.shouldDeferEntryAnimationSettle({
        phase: 'settled',
        backgroundMode: 'home',
        openedFromHome: false,
        activeTabIdAtOpen: 'tab-1',
        morphCoveredTabId: ''
      })).assertFalse();
    });
  });
}

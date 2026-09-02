import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserTabsOverviewSceneDriver,
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
  });
}

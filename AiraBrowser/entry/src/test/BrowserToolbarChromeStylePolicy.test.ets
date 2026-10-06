import { describe, expect, it } from '@ohos/hypium';
import { isAppString } from '../main/ets/core/resources/AppResourceText';
import {
  DOCK_TOOLBAR_BOTTOM_BLOCK_VP,
  DOCK_TOOLBAR_NAV_ROW_VP,
  DOCK_TOOLBAR_PILL_ROW_VP,
  isSplitFamilyStyle,
  isSplitToolbarChromeActive,
  normalizeToolbarChromeStyle,
  resolveDockToolbarBottomReserveVp,
  resolveSplitToolbarBarBackgroundColor,
  resolveSplitToolbarCanGoBack,
  resolveSplitToolbarCanGoForward,
  resolveSplitToolbarHomeBackdrop,
  shouldClearSplitToolbarOverWallpaper,
  SPLIT_TOOLBAR_CLEARED_BAR_COLOR,
  canCollapseSplitAddressBarForTopImmersion,
  resolveScrollTopImmersionFooter,
  resolveSplitToolbarScrollBehavior,
  resolveTopImmersionPreference,
  shouldApplyAlwaysTopImmersion,
  shouldShowAlwaysTopImmersionSetting,
  shouldShowToolbarTopImmersionSettings,
  shouldCollapseSplitToolbarForScroll,
  SplitAddressBarImmersionScrollCoordinator,
  shouldReserveSplitToolbarHomeInsets,
  shouldRouteCenteredHomeSearchToFloatingToolbar,
  shouldSuppressLegacyFloatingToolbar,
  resolveSplitToolbarBottomReserveVp,
  resolveSplitToolbarBottomRowHeightVp,
  resolveSplitToolbarTopRowHeightVp,
  resolveSplitToolbarTopRowReserveVp,
  resolveSplitToolbarWebReserve,
  SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  SPLIT_TOOLBAR_BOTTOM_BAR_VP,
  SPLIT_TOOLBAR_PILL_ROW_VP,
  SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP
} from '../main/ets/core/browser/BrowserToolbarChromeStylePolicy';
import { BrowserToolbarScrollBehaviorSettingsViewModel } from '../main/ets/core/settings/BrowserToolbarScrollBehaviorSettingsViewModel';

describe('BrowserToolbarChromeStylePolicy', () => {
  it('keeps an unknown style on the floating chrome', 0, () => {
    expect(normalizeToolbarChromeStyle(undefined)).assertEqual('floating');
    expect(normalizeToolbarChromeStyle('compact')).assertEqual('floating');
    expect(normalizeToolbarChromeStyle('split')).assertEqual('split');
    expect(normalizeToolbarChromeStyle('dock')).assertEqual('dock');
  });

  it('treats split and dock as one phone frame family', 0, () => {
    expect(isSplitFamilyStyle('split')).assertTrue();
    expect(isSplitFamilyStyle('dock')).assertTrue();
    expect(isSplitFamilyStyle('floating')).assertFalse();
    // The dock shares the split frame, so the split chrome mounts and the legacy floating
    // toolbar stays suppressed for it too.
    expect(isSplitToolbarChromeActive({
      style: 'dock',
      largeScreenShellActive: false,
      immersiveChromeHidden: false,
      documentViewerActive: false,
      readerVisible: false,
      novelReaderVisible: false
    })).assertTrue();
    expect(shouldSuppressLegacyFloatingToolbar('dock', false)).assertTrue();
    expect(shouldReserveSplitToolbarHomeInsets('dock', false)).assertTrue();
    expect(shouldRouteCenteredHomeSearchToFloatingToolbar('dock', true, false)).assertFalse();
    // Always-on immersion has no separate top bar to drive, and the immersion footer is the
    // split one for both frame members.
    expect(shouldShowAlwaysTopImmersionSetting('dock')).assertFalse();
    expect(isAppString(resolveScrollTopImmersionFooter('dock'),
      $r('app.string.toolbar_settings_immersion_footer_split'))).assertTrue();
    // The dock keeps the split scroll behavior: only hide is honored.
    expect(resolveSplitToolbarScrollBehavior('compact')).assertEqual('fixed');
  });

  it('stacks the dock search row above the navigation row and reserves the whole block', 0, () => {
    // The dock block is taller than the plain split nav row: it carries the search pill row too.
    expect(DOCK_TOOLBAR_BOTTOM_BLOCK_VP).assertLarger(SPLIT_TOOLBAR_BOTTOM_BAR_VP);
    // Both dock rows are shorter than their split counterparts, so the whole block stays low.
    expect(DOCK_TOOLBAR_PILL_ROW_VP).assertLarger(0);
    expect(SPLIT_TOOLBAR_PILL_ROW_VP).assertLarger(DOCK_TOOLBAR_PILL_ROW_VP);
    expect(SPLIT_TOOLBAR_BOTTOM_BAR_VP).assertLarger(DOCK_TOOLBAR_NAV_ROW_VP);
    // The bottom block reserve grows with the system gesture inset, exactly like the split row.
    expect(resolveDockToolbarBottomReserveVp(0)).assertEqual(DOCK_TOOLBAR_BOTTOM_BLOCK_VP);
    expect(resolveDockToolbarBottomReserveVp(12)).assertEqual(DOCK_TOOLBAR_BOTTOM_BLOCK_VP + 12);
    // A web page on the dock frame clears that whole block on its bottom edge, and nothing on top.
    const dockReserve = resolveSplitToolbarWebReserve({
      statusBarStripVp: 36,
      statusBarVisible: true,
      stackedChromeHeightVp: 0,
      addressRowSafeInsetVp: 36,
      bottomRowSafeInsetVp: 12,
      contentGapVp: 16,
      addressRowPainted: false,
      bottomRowPainted: true,
      bottomBlockHeightVp: DOCK_TOOLBAR_BOTTOM_BLOCK_VP
    });
    expect(dockReserve.bottomVp).assertEqual(DOCK_TOOLBAR_BOTTOM_BLOCK_VP + 12);
    expect(dockReserve.topVp).assertEqual(36 + 16);
    // Without the block height the reserve is the plain split row, so existing frames are unchanged.
    const splitReserve = resolveSplitToolbarWebReserve({
      statusBarStripVp: 36,
      statusBarVisible: true,
      stackedChromeHeightVp: 0,
      addressRowSafeInsetVp: 36,
      bottomRowSafeInsetVp: 12,
      contentGapVp: 16,
      addressRowPainted: true,
      bottomRowPainted: true
    });
    expect(splitReserve.bottomVp).assertEqual(SPLIT_TOOLBAR_BOTTOM_BAR_VP + 12);
    expect(splitReserve.topVp).assertEqual(36 + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP);
  });

  it('activates split chrome only for an ordinary phone browsing frame', 0, () => {
    expect(isSplitToolbarChromeActive({
      style: 'split',
      largeScreenShellActive: false,
      immersiveChromeHidden: false,
      documentViewerActive: false,
      readerVisible: false,
      novelReaderVisible: false
    })).assertTrue();
    expect(isSplitToolbarChromeActive({
      style: 'floating',
      largeScreenShellActive: false,
      immersiveChromeHidden: false,
      documentViewerActive: false,
      readerVisible: false,
      novelReaderVisible: false
    })).assertFalse();
    expect(isSplitToolbarChromeActive({
      style: 'split',
      largeScreenShellActive: true,
      immersiveChromeHidden: false,
      documentViewerActive: false,
      readerVisible: false,
      novelReaderVisible: false
    })).assertFalse();
    expect(shouldSuppressLegacyFloatingToolbar('split', false)).assertTrue();
    expect(shouldSuppressLegacyFloatingToolbar('split', true)).assertFalse();
    expect(shouldSuppressLegacyFloatingToolbar('floating', false)).assertFalse();
    expect(shouldReserveSplitToolbarHomeInsets('split', false)).assertTrue();
    expect(shouldReserveSplitToolbarHomeInsets('floating', false)).assertFalse();
    expect(shouldRouteCenteredHomeSearchToFloatingToolbar('floating', true, false)).assertTrue();
    expect(shouldRouteCenteredHomeSearchToFloatingToolbar('split', true, false)).assertFalse();
    expect(shouldRouteCenteredHomeSearchToFloatingToolbar('floating', false, false)).assertFalse();
    expect(shouldRouteCenteredHomeSearchToFloatingToolbar('floating', true, true)).assertFalse();
    expect(SPLIT_TOOLBAR_ADDRESS_BLOCK_VP).assertLarger(0);
    expect(SPLIT_TOOLBAR_BOTTOM_BAR_VP).assertLarger(0);
  });

  it('keeps the web page between the two split rows in every chrome state', 0, () => {
    const contentGapVp = 16;
    const statusBarStripVp = 36;
    const topRowSafeInsetVp = 36;
    const bottomRowSafeInsetVp = 12;
    const buildReserve = (
      statusBarStrip: number,
      statusBarVisible: boolean,
      stackedHeightVp: number,
      addressRowPainted: boolean,
      bottomRowPainted: boolean
    ): SplitToolbarWebReserve => resolveSplitToolbarWebReserve({
      statusBarStripVp: statusBarStrip,
      statusBarVisible: statusBarVisible,
      stackedChromeHeightVp: stackedHeightVp,
      addressRowSafeInsetVp: topRowSafeInsetVp,
      bottomRowSafeInsetVp: bottomRowSafeInsetVp,
      contentGapVp: contentGapVp,
      addressRowPainted: addressRowPainted,
      bottomRowPainted: bottomRowPainted
    });
    expect(SPLIT_TOOLBAR_ADDRESS_BLOCK_VP).assertEqual(
      SPLIT_TOOLBAR_PILL_ROW_VP + SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP);
    // The page meets the row that is painted, and the row paints with its own safe padding.
    for (const safeInsetVp of [0, 24, 36, 48]) {
      expect(resolveSplitToolbarTopRowReserveVp(safeInsetVp, contentGapVp))
        .assertEqual(resolveSplitToolbarTopRowHeightVp(safeInsetVp));
    }
    expect(resolveSplitToolbarBottomReserveVp(0)).assertEqual(SPLIT_TOOLBAR_BOTTOM_BAR_VP);
    expect(resolveSplitToolbarBottomReserveVp(bottomRowSafeInsetVp))
      .assertEqual(resolveSplitToolbarBottomRowHeightVp(bottomRowSafeInsetVp));

    // A painted split row is an opaque row, not a floating pill: the page meets that row.
    const restingRows = buildReserve(statusBarStripVp, true, 0, true, true);
    expect(restingRows.topVp).assertEqual(topRowSafeInsetVp + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP);
    expect(restingRows.topVp - resolveSplitToolbarTopRowHeightVp(topRowSafeInsetVp)).assertEqual(0);
    expect(restingRows.bottomVp).assertEqual(SPLIT_TOOLBAR_BOTTOM_BAR_VP + bottomRowSafeInsetVp);
    // A visible status bar whose strip is shorter than the row keeps the row's own safe padding.
    expect(buildReserve(16, true, 0, true, true).topVp)
      .assertEqual(topRowSafeInsetVp + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP);
    // A hidden status bar keeps the painted row: this is the top coverage the reserve exists for.
    const hiddenStatusBar = buildReserve(16, false, 0, true, true);
    expect(hiddenStatusBar.topVp).assertEqual(resolveSplitToolbarTopRowHeightVp(topRowSafeInsetVp));
    expect(hiddenStatusBar.topVp).assertEqual(topRowSafeInsetVp + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP);
    expect(hiddenStatusBar.bottomVp).assertEqual(SPLIT_TOOLBAR_BOTTOM_BAR_VP + bottomRowSafeInsetVp);
    // The bottom row owns the bottom edge while it is on screen, keyboard or not.
    expect(buildReserve(statusBarStripVp, true, 0, false, true).bottomVp)
      .assertEqual(SPLIT_TOOLBAR_BOTTOM_BAR_VP + bottomRowSafeInsetVp);
    // Rows away: the page keeps the clearance of whatever is still covering its edge, and the
    // floating chrome keeps its content gap.
    const rowsAway = buildReserve(statusBarStripVp, true, 0, false, false);
    expect(rowsAway.topVp).assertEqual(statusBarStripVp + contentGapVp);
    expect(rowsAway.bottomVp).assertEqual(0);
    expect(buildReserve(16, false, 0, false, false).topVp).assertEqual(0);
  });

  it('stacks chrome rows above the page instead of trading one for the other', 0, () => {
    const contentGapVp = 16;
    const statusBarStripVp = 36;
    const topRowSafeInsetVp = 36;
    const stackedChromeHeightVp = 48;
    for (const statusBarVisible of [true, false]) {
      const withRow = resolveSplitToolbarWebReserve({
        statusBarStripVp: statusBarStripVp,
        statusBarVisible: statusBarVisible,
        stackedChromeHeightVp: stackedChromeHeightVp,
        addressRowSafeInsetVp: topRowSafeInsetVp,
        bottomRowSafeInsetVp: 12,
        contentGapVp: contentGapVp,
        addressRowPainted: true,
        bottomRowPainted: true
      });
      const withoutRow = resolveSplitToolbarWebReserve({
        statusBarStripVp: statusBarStripVp,
        statusBarVisible: statusBarVisible,
        stackedChromeHeightVp: stackedChromeHeightVp,
        addressRowSafeInsetVp: topRowSafeInsetVp,
        bottomRowSafeInsetVp: 12,
        contentGapVp: contentGapVp,
        addressRowPainted: false,
        bottomRowPainted: false
      });
      // The stacked row (the quick search row) keeps its own height and the address row keeps
      // its clearance, so the page meets the row that is on screen instead of sliding under it.
      expect(withRow.topVp - stackedChromeHeightVp)
        .assertEqual(resolveSplitToolbarTopRowHeightVp(topRowSafeInsetVp));
      expect(withRow.topVp - stackedChromeHeightVp)
        .assertLarger(withoutRow.topVp - stackedChromeHeightVp);
      expect(withRow.topVp > stackedChromeHeightVp).assertTrue();
    }
  });

  it('enables split back and forward from the floating toolbar rule', 0, () => {
    expect(resolveSplitToolbarCanGoBack(true, true, true)).assertFalse();
    expect(resolveSplitToolbarCanGoBack(false, false, true)).assertTrue();
    expect(resolveSplitToolbarCanGoBack(false, true, false)).assertTrue();
    expect(resolveSplitToolbarCanGoBack(false, false, false)).assertFalse();
    expect(resolveSplitToolbarCanGoForward(true, true, true)).assertFalse();
    expect(resolveSplitToolbarCanGoForward(false, false, true)).assertTrue();
    expect(resolveSplitToolbarCanGoForward(false, true, false)).assertTrue();
    expect(resolveSplitToolbarCanGoForward(false, false, false)).assertFalse();
  });

  it('follows the homepage theme color and keeps wallpaper and web bars neutral', 0, () => {
    expect(resolveSplitToolbarHomeBackdrop('default', 'system_home')).assertEqual('theme_color');
    expect(resolveSplitToolbarHomeBackdrop('default', 'theme')).assertEqual('theme_color');
    expect(resolveSplitToolbarHomeBackdrop('image', 'system_home')).assertEqual('wallpaper');
    // An auto black/white home and a flat color are painted edge to edge too, so their bars
    // clear exactly like a photo's.
    expect(resolveSplitToolbarHomeBackdrop('solid', 'system_home')).assertEqual('wallpaper');
    expect(resolveSplitToolbarHomeBackdrop('auto', 'system_home')).assertEqual('wallpaper');
    expect(resolveSplitToolbarHomeBackdrop('default', 'web_home')).assertEqual('web_home');
    expect(resolveSplitToolbarBarBackgroundColor({
      homeScene: true,
      backdrop: 'theme_color',
      homeBackgroundColor: '#EEF3F8',
      surfaceBackgroundColor: '#FFFFFF'
    })).assertEqual('#EEF3F8');
    expect(resolveSplitToolbarBarBackgroundColor({
      homeScene: true,
      backdrop: 'wallpaper',
      homeBackgroundColor: '#EEF3F8',
      surfaceBackgroundColor: '#FFFFFF'
    })).assertEqual('#FFFFFF');
    expect(resolveSplitToolbarBarBackgroundColor({
      homeScene: true,
      backdrop: 'web_home',
      homeBackgroundColor: '#EEF3F8',
      surfaceBackgroundColor: '#1C1C1E'
    })).assertEqual('#1C1C1E');
    expect(resolveSplitToolbarBarBackgroundColor({
      homeScene: false,
      backdrop: 'theme_color',
      homeBackgroundColor: '#EEF3F8',
      surfaceBackgroundColor: '#FFFFFF'
    })).assertEqual('#FFFFFF');
    expect(resolveSplitToolbarBarBackgroundColor({
      homeScene: true,
      backdrop: 'theme_color',
      homeBackgroundColor: '   ',
      surfaceBackgroundColor: '#FFFFFF'
    })).assertEqual('#FFFFFF');
  });

  it('clears every system home bar over a painted wallpaper', 0, () => {
    expect(shouldClearSplitToolbarOverWallpaper(true, 'image')).assertTrue();
    expect(shouldClearSplitToolbarOverWallpaper(true, 'video')).assertTrue();
    expect(shouldClearSplitToolbarOverWallpaper(true, 'solid')).assertTrue();
    expect(shouldClearSplitToolbarOverWallpaper(true, 'auto')).assertTrue();
    expect(SPLIT_TOOLBAR_CLEARED_BAR_COLOR).assertEqual('#00000000');
    expect(shouldClearSplitToolbarOverWallpaper(true, 'default')).assertFalse();
    expect(shouldClearSplitToolbarOverWallpaper(false, 'image')).assertFalse();
    expect(shouldClearSplitToolbarOverWallpaper(false, 'video')).assertFalse();
  });

  it('keeps split scroll fixed unless the user chose hide, then collapses both bars together', 0, () => {
    expect(resolveSplitToolbarScrollBehavior('fixed')).assertEqual('fixed');
    expect(resolveSplitToolbarScrollBehavior('compact')).assertEqual('fixed');
    expect(resolveSplitToolbarScrollBehavior('hidden')).assertEqual('hidden');
    const collapsed = {
      splitChromeActive: true,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 0,
      scrollPresentationHidden: true
    };
    expect(shouldCollapseSplitToolbarForScroll(collapsed)).assertTrue();
    expect(shouldCollapseSplitToolbarForScroll({
      splitChromeActive: true,
      homeScene: true,
      addressFocused: false,
      keyboardInsetVp: 0,
      scrollPresentationHidden: true
    })).assertFalse();
    expect(shouldCollapseSplitToolbarForScroll({
      splitChromeActive: true,
      homeScene: false,
      addressFocused: true,
      keyboardInsetVp: 0,
      scrollPresentationHidden: true
    })).assertFalse();
    expect(shouldCollapseSplitToolbarForScroll({
      splitChromeActive: true,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 12,
      scrollPresentationHidden: true
    })).assertFalse();
    expect(shouldCollapseSplitToolbarForScroll({
      splitChromeActive: true,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 0,
      scrollPresentationHidden: false
    })).assertFalse();
    expect(shouldCollapseSplitToolbarForScroll({
      splitChromeActive: false,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 0,
      scrollPresentationHidden: true
    })).assertFalse();

    const viewModel = new BrowserToolbarScrollBehaviorSettingsViewModel();
    const splitState = viewModel.buildStateForBehavior('compact', 'split');
    expect(splitState.behavior).assertEqual('fixed');
    expect(splitState.options.length).assertEqual(2);
    expect(isAppString(splitState.options[0].title, $r('app.string.toolbar_settings_scroll_split_fixed'))).assertTrue();
    expect(isAppString(splitState.options[1].title, $r('app.string.toolbar_settings_scroll_split_hidden'))).assertTrue();
    expect(isAppString(viewModel.formatBehaviorTitle('compact', 'split'), $r('app.string.toolbar_settings_scroll_split_fixed'))).assertTrue();
    expect(isAppString(viewModel.formatBehaviorTitle('hidden', 'split'), $r('app.string.toolbar_settings_scroll_split_hidden'))).assertTrue();
    expect(viewModel.buildStateForBehavior('compact', 'floating').options.length).assertEqual(3);
  });

  it('keeps always-on top immersion off the split toolbar without clearing it', 0, () => {
    expect(shouldShowToolbarTopImmersionSettings(false)).assertTrue();
    expect(shouldShowToolbarTopImmersionSettings(true)).assertFalse();
    expect(shouldShowAlwaysTopImmersionSetting('floating')).assertTrue();
    expect(shouldShowAlwaysTopImmersionSetting('split')).assertFalse();
    expect(shouldApplyAlwaysTopImmersion(true, false)).assertTrue();
    expect(shouldApplyAlwaysTopImmersion(true, true)).assertFalse();
    expect(shouldApplyAlwaysTopImmersion(false, false)).assertFalse();
    expect(isAppString(resolveScrollTopImmersionFooter('split'), $r('app.string.toolbar_settings_immersion_footer_split'))).assertTrue();
    expect(isAppString(resolveScrollTopImmersionFooter('floating'), $r('app.string.toolbar_settings_immersion_footer_floating'))).assertTrue();

    const stored = resolveTopImmersionPreference({
      globalImmersionEnabled: false,
      alwaysTopImmersionEnabled: true
    }, 'scroll', false);
    expect(stored.alwaysTopImmersionEnabled).assertTrue();
    const turnedOn = resolveTopImmersionPreference(stored, 'scroll', true);
    expect(turnedOn.globalImmersionEnabled).assertTrue();
    expect(turnedOn.alwaysTopImmersionEnabled).assertFalse();
  });

  it('collapses only the split address bar while top immersion is on and the page scrolls up', 0, () => {
    expect(canCollapseSplitAddressBarForTopImmersion({
      splitChromeActive: true,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 0,
      topImmersionEnabled: true
    })).assertTrue();
    expect(canCollapseSplitAddressBarForTopImmersion({
      splitChromeActive: true,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 0,
      topImmersionEnabled: false
    })).assertFalse();
    expect(canCollapseSplitAddressBarForTopImmersion({
      splitChromeActive: false,
      homeScene: false,
      addressFocused: false,
      keyboardInsetVp: 0,
      topImmersionEnabled: true
    })).assertFalse();

    const coordinator = new SplitAddressBarImmersionScrollCoordinator();
    expect(coordinator.handleScroll({
      tabId: 'tab',
      scrollOffsetY: 0,
      eligible: true,
      track: true
    }).collapsed).assertFalse();
    expect(coordinator.handleScroll({
      tabId: 'tab',
      scrollOffsetY: 40,
      eligible: true,
      track: true
    }).collapsed).assertTrue();
    const kept = coordinator.handleScroll({
      tabId: 'tab',
      scrollOffsetY: 200,
      eligible: true,
      track: false
    });
    expect(kept.collapsed).assertTrue();
    expect(kept.changed).assertFalse();
    const restored = coordinator.handleScroll({
      tabId: 'tab',
      scrollOffsetY: 150,
      eligible: true,
      track: true
    });
    expect(restored.collapsed).assertFalse();
    expect(restored.changed).assertTrue();
  });
});

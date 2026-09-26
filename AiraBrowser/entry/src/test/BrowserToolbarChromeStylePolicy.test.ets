import { describe, expect, it } from '@ohos/hypium';
import {
  isSplitToolbarChromeActive,
  normalizeToolbarChromeStyle,
  resolveSplitToolbarBarBackgroundColor,
  resolveSplitToolbarCanGoBack,
  resolveSplitToolbarCanGoForward,
  resolveSplitToolbarHomeBackdrop,
  canCollapseSplitAddressBarForTopImmersion,
  resolveSplitToolbarScrollBehavior,
  shouldCollapseSplitToolbarForScroll,
  SplitAddressBarImmersionScrollCoordinator,
  shouldReserveSplitToolbarHomeInsets,
  shouldSuppressLegacyFloatingToolbar,
  SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  SPLIT_TOOLBAR_BOTTOM_BAR_VP
} from '../main/ets/core/browser/BrowserToolbarChromeStylePolicy';
import { BrowserToolbarScrollBehaviorSettingsViewModel } from '../main/ets/core/settings/BrowserToolbarScrollBehaviorSettingsViewModel';

describe('BrowserToolbarChromeStylePolicy', () => {
  it('keeps an unknown style on the floating chrome', 0, () => {
    expect(normalizeToolbarChromeStyle(undefined)).assertEqual('floating');
    expect(normalizeToolbarChromeStyle('compact')).assertEqual('floating');
    expect(normalizeToolbarChromeStyle('split')).assertEqual('split');
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
    expect(SPLIT_TOOLBAR_ADDRESS_BLOCK_VP).assertLarger(0);
    expect(SPLIT_TOOLBAR_BOTTOM_BAR_VP).assertLarger(0);
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
    expect(splitState.options[0].title).assertEqual('固定');
    expect(splitState.options[1].title).assertEqual('收起地址栏和工具栏');
    expect(viewModel.formatBehaviorTitle('compact', 'split')).assertEqual('固定');
    expect(viewModel.formatBehaviorTitle('hidden', 'split')).assertEqual('收起地址栏和工具栏');
    expect(viewModel.buildStateForBehavior('compact', 'floating').options.length).assertEqual(3);
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

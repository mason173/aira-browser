import { describe, expect, it } from '@ohos/hypium';
import {
  isSplitToolbarChromeActive,
  normalizeToolbarChromeStyle,
  resolveSplitToolbarBarBackgroundColor,
  resolveSplitToolbarCanGoBack,
  resolveSplitToolbarCanGoForward,
  resolveSplitToolbarHomeBackdrop,
  shouldReserveSplitToolbarHomeInsets,
  shouldSuppressLegacyFloatingToolbar,
  SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  SPLIT_TOOLBAR_BOTTOM_BAR_VP
} from '../main/ets/core/browser/BrowserToolbarChromeStylePolicy';

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
});

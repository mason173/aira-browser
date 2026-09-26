import {
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarChromeStyle
} from '../../common/models/BrowserModels';
import { HomeWallpaperPresentationKind } from '../../common/models/WallpaperModels';
import { BrowserHomeForegroundBackdropSource } from './BrowserHomeSurfaceProfileViewModel';

/** Height of the address pill row under the status bar, in vp. */
export const SPLIT_TOOLBAR_ADDRESS_BLOCK_VP: number = 62;
/** Height of the bottom navigation row above the system gesture inset, in vp. */
export const SPLIT_TOOLBAR_BOTTOM_BAR_VP: number = 56;
/** Matches the floating toolbar's scroll transition, so both bars leave and return together. */
export const SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS: number = 180;

export interface SplitToolbarChromeActivityInput {
  style: BrowserToolbarChromeStyle;
  largeScreenShellActive: boolean;
  immersiveChromeHidden: boolean;
  documentViewerActive: boolean;
  readerVisible: boolean;
  novelReaderVisible: boolean;
}

/**
 * The split chrome is a phone browsing frame. Large-screen, immersive, reader, and document
 * surfaces keep the chrome they already own. Tabs overview is an overlay above this chrome, so
 * it must not unmount the bars or the legacy floating toolbar flashes back in.
 */
export function isSplitToolbarChromeActive(input: SplitToolbarChromeActivityInput): boolean {
  return input.style === 'split' &&
    !input.largeScreenShellActive &&
    !input.immersiveChromeHidden &&
    !input.documentViewerActive &&
    !input.readerVisible &&
    !input.novelReaderVisible;
}

/**
 * Once the phone is on the split style, the legacy floating toolbar stays out of the frame even
 * while another surface temporarily covers the new bars.
 */
export function shouldSuppressLegacyFloatingToolbar(
  style: BrowserToolbarChromeStyle,
  largeScreenShellActive: boolean
): boolean {
  return isSplitToolbarPhoneStyleSelected(style, largeScreenShellActive);
}

/**
 * Home content reserves the fixed bars from the style choice, not from whether the bars are
 * painted this frame. Otherwise returning home applies the top inset late and the shortcuts jump.
 */
export function shouldReserveSplitToolbarHomeInsets(
  style: BrowserToolbarChromeStyle,
  largeScreenShellActive: boolean
): boolean {
  return isSplitToolbarPhoneStyleSelected(style, largeScreenShellActive);
}

function isSplitToolbarPhoneStyleSelected(
  style: BrowserToolbarChromeStyle,
  largeScreenShellActive: boolean
): boolean {
  return style === 'split' && !largeScreenShellActive;
}

/**
 * Split bars have no capsule, so the floating "compact" preference stays fixed until the user
 * explicitly chooses hide. That choice reuses `hidden` and must not rewrite a stored compact value.
 */
export function resolveSplitToolbarScrollBehavior(
  behavior: BrowserBottomToolbarScrollBehavior
): BrowserBottomToolbarScrollBehavior {
  return behavior === 'hidden' ? 'hidden' : 'fixed';
}

export interface SplitToolbarScrollCollapseInput {
  splitChromeActive: boolean;
  homeScene: boolean;
  addressFocused: boolean;
  keyboardInsetVp: number;
  scrollPresentationHidden: boolean;
}

/**
 * Collapse is the existing scroll presentation, applied to both split bars. Home, search, and the
 * keyboard keep the bars because those surfaces are not a scrolling web page.
 */
export function shouldCollapseSplitToolbarForScroll(input: SplitToolbarScrollCollapseInput): boolean {
  return input.splitChromeActive &&
    !input.homeScene &&
    !input.addressFocused &&
    input.keyboardInsetVp <= 0 &&
    input.scrollPresentationHidden;
}

export function normalizeToolbarChromeStyle(
  value: BrowserToolbarChromeStyle | string | undefined
): BrowserToolbarChromeStyle {
  return value === 'split' ? 'split' : 'floating';
}

/**
 * Same availability the floating toolbar uses: a non-home page can leave for home even when the
 * webview has not reported accessBackward yet.
 */
export function resolveSplitToolbarCanGoBack(
  homeScene: boolean,
  webViewCanGoBack: boolean,
  terminalBackAvailable: boolean
): boolean {
  return !homeScene && (webViewCanGoBack || terminalBackAvailable);
}

/**
 * Same availability the floating toolbar uses: history position or a live webview accessForward.
 */
export function resolveSplitToolbarCanGoForward(
  homeScene: boolean,
  webViewCanGoForward: boolean,
  historyCanGoForward: boolean
): boolean {
  return !homeScene && (webViewCanGoForward || historyCanGoForward);
}

/**
 * Homepage bars follow the painted home backdrop. A theme-color home blends the bars into that
 * color. A wallpaper or a custom web home keeps the neutral light/dark surface, because those
 * backdrops are not a single theme color.
 */
export type SplitToolbarHomeBackdrop = 'theme_color' | 'wallpaper' | 'web_home';

export function resolveSplitToolbarHomeBackdrop(
  wallpaperKind: HomeWallpaperPresentationKind,
  foregroundBackdropSource: BrowserHomeForegroundBackdropSource
): SplitToolbarHomeBackdrop {
  if (wallpaperKind === 'image') {
    return 'wallpaper';
  }
  if (foregroundBackdropSource === 'web_home') {
    return 'web_home';
  }
  return 'theme_color';
}

export interface SplitToolbarBarBackgroundInput {
  homeScene: boolean;
  backdrop: SplitToolbarHomeBackdrop;
  homeBackgroundColor: string;
  surfaceBackgroundColor: string;
}

export function resolveSplitToolbarBarBackgroundColor(input: SplitToolbarBarBackgroundInput): string {
  if (!input.homeScene || input.backdrop !== 'theme_color') {
    return input.surfaceBackgroundColor;
  }
  const homeColor = input.homeBackgroundColor.trim();
  return homeColor.length > 0 ? homeColor : input.surfaceBackgroundColor;
}

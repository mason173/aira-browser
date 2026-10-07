import {
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarChromeStyle
} from '../../common/models/BrowserModels';
import { HomeWallpaperPresentationKind, paintsHomeBackdrop } from '../../common/models/WallpaperModels';
import { BrowserHomeForegroundBackdropSource } from './BrowserHomeSurfaceProfileViewModel';

/** Resting height of the address or search pill itself, in vp. */
export const SPLIT_TOOLBAR_PILL_ROW_VP: number = 46;
/** Gap the top row keeps under its pill, inside its own opaque background, in vp. */
export const SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP: number = 8;
/**
 * Painted content height of the split address row below its top safe padding, in vp.
 * It is the pill plus the under-pill gap. The web page starts on this edge, so its top
 * meets the address row bottom instead of leaving a band under the row.
 */
export const SPLIT_TOOLBAR_ADDRESS_BLOCK_VP: number =
  SPLIT_TOOLBAR_PILL_ROW_VP + SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP;
/** Side inset of the split address and search pills, in vp. */
export const SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP: number = 16;
/** Height of the bottom navigation row above the system gesture inset, in vp. */
export const SPLIT_TOOLBAR_BOTTOM_BAR_VP: number = 56;
/** Matches the floating toolbar's scroll transition, so both bars leave and return together. */
export const SPLIT_TOOLBAR_SCROLL_COLLAPSE_DURATION_MS: number = 180;

/**
 * The `dock` frame is the split family anchored to the bottom: one search pill row directly above
 * the navigation row, with no top address bar. These are the dock-only measurements, in vp.
 */
/** Dock search pill row. Shorter than the split address pill, so the dock block stays low. */
export const DOCK_TOOLBAR_PILL_ROW_VP: number = 40;
/** Gap the dock keeps above its search pill row, inside the block, in vp. */
export const DOCK_TOOLBAR_PILL_ROW_TOP_GAP_VP: number = 4;
/** Gap the dock keeps between its search pill row and the navigation row below it, in vp. */
export const DOCK_TOOLBAR_PILL_ROW_GAP_VP: number = 2;
/**
 * Dock navigation row. Shorter than the split nav row: the block is a bottom dock, so the icon
 * row sits lower, closer to the gesture area, and the whole block stops covering the page.
 */
export const DOCK_TOOLBAR_NAV_ROW_VP: number = 46;
/** Painted content height of the whole dock block above the system gesture inset, in vp. */
export const DOCK_TOOLBAR_BOTTOM_BLOCK_VP: number =
  DOCK_TOOLBAR_PILL_ROW_TOP_GAP_VP + DOCK_TOOLBAR_PILL_ROW_VP +
  DOCK_TOOLBAR_PILL_ROW_GAP_VP + DOCK_TOOLBAR_NAV_ROW_VP;

/** Painted height of the dock block, including the system gesture inset, in vp. */
export function resolveDockToolbarBottomBlockHeightVp(bottomSafeInsetVp: number): number {
  return DOCK_TOOLBAR_BOTTOM_BLOCK_VP + Math.max(0, Math.ceil(toFiniteVp(bottomSafeInsetVp)));
}

/** Bottom reserve the web page keeps for the dock block, in vp. */
export function resolveDockToolbarBottomReserveVp(bottomSafeInsetVp: number): number {
  return resolveDockToolbarBottomBlockHeightVp(bottomSafeInsetVp);
}

/** Painted height of the split address row, including its own top safe padding, in vp. */
export function resolveSplitToolbarTopRowHeightVp(topSafeInsetVp: number): number {
  return Math.max(0, Math.ceil(toFiniteVp(topSafeInsetVp))) +
    SPLIT_TOOLBAR_PILL_ROW_VP + SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP;
}

/**
 * Painted height of the bottom row, including the system gesture inset, in vp.
 *
 * The split row is the plain navigation row. The dock stacks its search pill row on top of that
 * same row, so it passes its own taller block height; every other caller keeps the split default.
 */
export function resolveSplitToolbarBottomRowHeightVp(
  bottomSafeInsetVp: number,
  bottomBlockHeightVp: number = SPLIT_TOOLBAR_BOTTOM_BAR_VP
): number {
  const blockVp = Number.isFinite(bottomBlockHeightVp) && bottomBlockHeightVp > 0 ?
    bottomBlockHeightVp : SPLIT_TOOLBAR_BOTTOM_BAR_VP;
  return blockVp + Math.max(0, Math.ceil(toFiniteVp(bottomSafeInsetVp)));
}

/**
 * Top reserve the web page keeps for the split address row. The row paints with its own safe
 * padding (`topSafeInsetVp`), so the reserve is that same inset plus the painted block.
 * The floating content gap is not added: that addition is the empty band under the address row.
 */
export function resolveSplitToolbarTopRowReserveVp(topSafeInsetVp: number, _contentGapVp: number): number {
  return resolveSplitToolbarTopRowHeightVp(topSafeInsetVp);
}

/** Bottom reserve the web page keeps for the bottom row, in vp. */
export function resolveSplitToolbarBottomReserveVp(
  bottomSafeInsetVp: number,
  bottomBlockHeightVp: number = SPLIT_TOOLBAR_BOTTOM_BAR_VP
): number {
  return resolveSplitToolbarBottomRowHeightVp(bottomSafeInsetVp, bottomBlockHeightVp);
}

export interface SplitToolbarWebReserveInput {
  /** System strip above the chrome: the status bar or cutout area, without any chrome content gap. */
  statusBarStripVp: number;
  /** Gap the floating chrome keeps between that strip and the page. */
  contentGapVp: number;
  /** A hidden status bar stops reserving its strip; the rows still reserve their own height. */
  statusBarVisible: boolean;
  /**
   * Height of the chrome rows stacked between that strip and the page (the quick search row).
   * They are ordinary top chrome, so their height adds to the reserve instead of replacing it.
   */
  stackedChromeHeightVp: number;
  /** The address row's own top safe padding; it is what the row actually paints with. */
  addressRowSafeInsetVp: number;
  bottomRowSafeInsetVp: number;
  /** The address row is on screen for this frame (not home, not scrolled or immersed away). */
  addressRowPainted: boolean;
  /** The bottom row is on screen for this frame (not home, not scrolled away). */
  bottomRowPainted: boolean;
  /**
   * Painted height of the bottom block above its safe inset, in vp. Omitted by the split frame,
   * which is the plain navigation row. The dock stacks its search pill row on top of that row and
   * passes its own taller block, so the page still meets the bottom of what is really painted.
   */
  bottomBlockHeightVp?: number;
}

export interface SplitToolbarWebReserve {
  topVp: number;
  bottomVp: number;
}

/**
 * The two hard edges of a phone split frame. The web page lives between them: it never slides
 * under a painted row or under the chrome stacked above it, and it keeps the full height while
 * the rows are away.
 *
 * The two top edges are not the same measurement. A floating pill only floats over the page, so
 * the page clears the status bar strip and the content gap. The split address row is an opaque
 * row that already covers that strip with its own safe padding, so once it is on screen the page
 * and every stacked row meet the painted row itself, `SPLIT_TOOLBAR_ADDRESS_BLOCK_VP` tall.
 * Adding the strip's content gap, or any breathing room, on top of a painted row is what leaves
 * a band of empty chrome under the address row.
 */
export function resolveSplitToolbarWebReserve(input: SplitToolbarWebReserveInput): SplitToolbarWebReserve {
  const stackedHeightVp = Math.max(0, Math.ceil(toFiniteVp(input.stackedChromeHeightVp)));
  const statusBarStripVp = input.statusBarVisible ?
    Math.max(0, Math.ceil(toFiniteVp(input.statusBarStripVp))) : 0;
  // The floating content gap belongs to that strip: with nothing above the page, nothing is left
  // to breathe under and the stacked rows sit at the very top.
  const contentGapVp = input.statusBarVisible ? Math.max(0, Math.ceil(toFiniteVp(input.contentGapVp))) : 0;
  const addressRowClearanceVp = input.addressRowPainted ?
    Math.max(statusBarStripVp, Math.max(0, Math.ceil(toFiniteVp(input.addressRowSafeInsetVp)))) +
    SPLIT_TOOLBAR_ADDRESS_BLOCK_VP :
    statusBarStripVp + contentGapVp;
  return {
    topVp: stackedHeightVp + addressRowClearanceVp,
    bottomVp: input.bottomRowPainted ?
      resolveSplitToolbarBottomReserveVp(input.bottomRowSafeInsetVp, input.bottomBlockHeightVp) : 0
  };
}

function toFiniteVp(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

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
  return isSplitFamilyStyle(input.style) &&
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
  return isSplitFamilyStyle(style) && !largeScreenShellActive;
}

/**
 * The two-row phone chrome frame. `split` and `dock` share the frame geometry, the reserves, the
 * scroll and top-immersion rules, and the settings behaviors; they differ only in what the rows
 * paint. Every frame decision goes through this instead of comparing to `'split'` alone, so a new
 * family member cannot be half-integrated.
 */
export function isSplitFamilyStyle(style: BrowserToolbarChromeStyle): boolean {
  return style === 'split' || style === 'dock';
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

export interface SplitAddressBarImmersionCollapseInput {
  splitChromeActive: boolean;
  homeScene: boolean;
  addressFocused: boolean;
  keyboardInsetVp: number;
  topImmersionEnabled: boolean;
}

/**
 * Top immersion only asks the split address bar to leave. The bottom bar stays unless the
 * toolbar's own scroll behavior already hides both.
 */
export function canCollapseSplitAddressBarForTopImmersion(
  input: SplitAddressBarImmersionCollapseInput
): boolean {
  return input.splitChromeActive &&
    !input.homeScene &&
    !input.addressFocused &&
    input.keyboardInsetVp <= 0 &&
    input.topImmersionEnabled;
}

export type ToolbarTopImmersionSwitch = 'scroll' | 'always';

export interface ToolbarTopImmersionPreference {
  globalImmersionEnabled: boolean;
  alwaysTopImmersionEnabled: boolean;
}

/** Phone toolbar settings own these switches. Desktop has no top address bar to immerse. */
export function shouldShowToolbarTopImmersionSettings(desktopPresentation: boolean): boolean {
  return !desktopPresentation;
}

/** Always-on immersion would leave the split address bar with nowhere to return. */
export function shouldShowAlwaysTopImmersionSetting(style: BrowserToolbarChromeStyle): boolean {
  return !isSplitFamilyStyle(style);
}

export function shouldApplyAlwaysTopImmersion(enabled: boolean, splitChromeActive: boolean): boolean {
  return enabled && !splitChromeActive;
}

export function resolveScrollTopImmersionFooter(style: BrowserToolbarChromeStyle): ResourceStr {
  if (isSplitFamilyStyle(style)) {
    return $r('app.string.toolbar_settings_immersion_footer_split');
  }
  return $r('app.string.toolbar_settings_immersion_footer_floating');
}

/** Turning one on clears the other. Hiding a switch does not clear its stored value. */
export function resolveTopImmersionPreference(
  current: ToolbarTopImmersionPreference,
  kind: ToolbarTopImmersionSwitch,
  enabled: boolean
): ToolbarTopImmersionPreference {
  if (kind === 'always') {
    return {
      globalImmersionEnabled: enabled ? false : current.globalImmersionEnabled,
      alwaysTopImmersionEnabled: enabled
    };
  }
  return {
    globalImmersionEnabled: enabled,
    alwaysTopImmersionEnabled: enabled ? false : current.alwaysTopImmersionEnabled
  };
}

export interface SplitAddressBarImmersionScrollInput {
  tabId: string;
  scrollOffsetY: number;
  eligible: boolean;
  track: boolean;
}

export interface SplitAddressBarImmersionScrollDecision {
  collapsed: boolean;
  changed: boolean;
}

const SPLIT_ADDRESS_BAR_IMMERSION_HIDE_DELTA_PX: number = 24;
const SPLIT_ADDRESS_BAR_IMMERSION_REVEAL_DELTA_PX: number = 32;

/**
 * Content moving up (the finger-up scroll) hides the address bar. The reverse scroll brings it
 * back. A layout correction only resets the baseline so it does not pop the bar open.
 */
export class SplitAddressBarImmersionScrollCoordinator {
  private tabId: string = '';
  private lastScrollOffsetY: number = 0;
  private downwardDelta: number = 0;
  private upwardDelta: number = 0;
  private collapsed: boolean = false;

  handleScroll(input: SplitAddressBarImmersionScrollInput): SplitAddressBarImmersionScrollDecision {
    const scrollY = Math.max(0, Math.floor(input.scrollOffsetY));
    if (!input.eligible) {
      const changed = this.collapsed;
      this.remember(input.tabId, scrollY, false);
      return { collapsed: false, changed: changed };
    }
    if (!input.track || this.tabId !== input.tabId) {
      this.remember(input.tabId, scrollY, this.tabId === input.tabId && this.collapsed);
      return { collapsed: this.collapsed, changed: false };
    }
    const delta = scrollY - this.lastScrollOffsetY;
    this.lastScrollOffsetY = scrollY;
    if (delta > 0) {
      this.downwardDelta += delta;
      this.upwardDelta = 0;
    } else if (delta < 0) {
      this.upwardDelta += Math.abs(delta);
      this.downwardDelta = 0;
    }
    if (!this.collapsed && scrollY > 0 &&
      this.downwardDelta >= SPLIT_ADDRESS_BAR_IMMERSION_HIDE_DELTA_PX) {
      this.downwardDelta = 0;
      this.collapsed = true;
      return { collapsed: true, changed: true };
    }
    if (this.collapsed && this.upwardDelta >= SPLIT_ADDRESS_BAR_IMMERSION_REVEAL_DELTA_PX) {
      this.upwardDelta = 0;
      this.collapsed = false;
      return { collapsed: false, changed: true };
    }
    return { collapsed: this.collapsed, changed: false };
  }

  private remember(tabId: string, scrollY: number, collapsed: boolean): void {
    this.tabId = tabId;
    this.lastScrollOffsetY = scrollY;
    this.downwardDelta = 0;
    this.upwardDelta = 0;
    this.collapsed = collapsed;
  }
}

export function normalizeToolbarChromeStyle(
  value: BrowserToolbarChromeStyle | string | undefined
): BrowserToolbarChromeStyle {
  if (value === 'split' || value === 'dock') {
    return value;
  }
  return 'floating';
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
 * color. A custom web home keeps the neutral light/dark surface. A painted wallpaper clears the
 * bars on every system home instead; see shouldClearSplitToolbarOverWallpaper.
 */
export type SplitToolbarHomeBackdrop = 'theme_color' | 'wallpaper' | 'web_home';

export function resolveSplitToolbarHomeBackdrop(
  wallpaperKind: HomeWallpaperPresentationKind,
  foregroundBackdropSource: BrowserHomeForegroundBackdropSource
): SplitToolbarHomeBackdrop {
  if (paintsHomeBackdrop(wallpaperKind)) {
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

/** Fully clear fill. The wallpaper behind the bars stays visible. */
export const SPLIT_TOOLBAR_CLEARED_BAR_COLOR: string = '#00000000';

/**
 * Classic, 简约 and 极简 paint a chosen wallpaper edge to edge: a photo, a looping video, a flat
 * color, or auto black/white. Their split bars drop the fill so that wallpaper shows through, and
 * their icons follow the same black-or-white tone as the page. A theme-color home and any web
 * page keep the normal bar fill.
 */
export function shouldClearSplitToolbarOverWallpaper(
  homeScene: boolean,
  wallpaperKind: HomeWallpaperPresentationKind
): boolean {
  return homeScene && paintsHomeBackdrop(wallpaperKind);
}

/**
 * 简约 and 极简 keep a center search field. With the floating toolbar selected, that field
 * opens the toolbar's own search instead of the split search page. Large screens type
 * into the field itself, and the split toolbar keeps its search page.
 */
export function shouldRouteCenteredHomeSearchToFloatingToolbar(
  style: BrowserToolbarChromeStyle,
  centeredHomeFrame: boolean,
  largeScreenShellActive: boolean
): boolean {
  return centeredHomeFrame && !largeScreenShellActive && !isSplitFamilyStyle(style);
}

/**
 * Hit-test family for the split-family chrome overlay.
 * - `transparent` while the frame rests over the page: its bars float above the page, so a tap
 *   between them must still reach the web content underneath.
 * - `block` while a full-screen search surface is painted: the search page is opaque and owns the
 *   whole screen, so a blank-area tap must be swallowed instead of falling through to the page.
 */
export type SplitToolbarChromeHitTestMode = 'transparent' | 'block';

export function resolveSplitToolbarChromeHitTestMode(searchSurfaceVisible: boolean): SplitToolbarChromeHitTestMode {
  return searchSurfaceVisible ? 'block' : 'transparent';
}

// Desktop tab titles share one fixed-height strip. The slot beside the favicon
// and close button is often only a few glyphs wide, so the hide-vs-ellipsis
// decision has to use that slot, not the whole tab width.
//
// HarmonyOS Text ellipsizes on word boundaries when width is unset. A title
// whose first word does not fit becomes "..." and leaves the rest of the slot
// blank. Callers must paint a visible title at titleSlot.widthVp with
// WordBreak.BREAK_ALL so every remaining pixel shows a character.

export const BROWSER_LARGE_SCREEN_TAB_ICON_SIZE_VP: number = 14;
export const BROWSER_LARGE_SCREEN_TAB_ACTION_BUTTON_SIZE_VP: number = 24;
export const BROWSER_LARGE_SCREEN_TAB_ACTION_GAP_VP: number = 4;
export const BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP: number = 13;

// Keep roomy insets once the title can show a recognizable fragment
// (about four CJK glyphs, or eight Latin glyphs, plus the ellipsis).
const COMFORTABLE_TITLE_SLOT_VP: number = 72;
const TITLE_ELLIPSIS_WIDTH_VP: number = BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP;
const NARROW_GLYPH_WIDTH_VP: number = 8;
const EMPTY_TAB_TITLE: string = '新标签页';

interface BrowserLargeScreenTabTitleChrome {
  leadingPaddingVp: number;
  trailingPaddingVp: number;
  iconTextGapVp: number;
  contentEndPaddingVp: number;
}

const COMFORTABLE_TITLE_CHROME: BrowserLargeScreenTabTitleChrome = {
  leadingPaddingVp: 16,
  trailingPaddingVp: 10,
  iconTextGapVp: 6,
  contentEndPaddingVp: 4
};

// Used only when the comfortable slot cannot show a recognizable title.
// The saved padding is given to the title instead of sitting as blank inset.
const COMPRESSED_TITLE_CHROME: BrowserLargeScreenTabTitleChrome = {
  leadingPaddingVp: 8,
  trailingPaddingVp: 6,
  iconTextGapVp: 4,
  contentEndPaddingVp: 0
};

export interface BrowserLargeScreenTabTitleSlotInput {
  tabWidthVp: number;
  title: string;
  pinned: boolean;
  closable: boolean;
  hasAudioAction: boolean;
}

export interface BrowserLargeScreenTabTitleSlot {
  visible: boolean;
  widthVp: number;
  leadingPaddingVp: number;
  trailingPaddingVp: number;
  iconTextGapVp: number;
  contentEndPaddingVp: number;
}

export const HIDDEN_BROWSER_LARGE_SCREEN_TAB_TITLE_SLOT: BrowserLargeScreenTabTitleSlot = {
  visible: false,
  widthVp: 0,
  leadingPaddingVp: COMFORTABLE_TITLE_CHROME.leadingPaddingVp,
  trailingPaddingVp: COMFORTABLE_TITLE_CHROME.trailingPaddingVp,
  iconTextGapVp: COMFORTABLE_TITLE_CHROME.iconTextGapVp,
  contentEndPaddingVp: COMFORTABLE_TITLE_CHROME.contentEndPaddingVp
};

export function resolveBrowserLargeScreenTabDisplayTitle(title: string): string {
  const trimmed = title.trim();
  return trimmed.length > 0 ? trimmed : EMPTY_TAB_TITLE;
}

export function resolveBrowserLargeScreenTabTitleSlots(
  tabs: BrowserLargeScreenTabTitleSlotInput[]
): BrowserLargeScreenTabTitleSlot[] {
  let compress = false;
  tabs.forEach((tab: BrowserLargeScreenTabTitleSlotInput): void => {
    if (tab.pinned || normalizeWidth(tab.tabWidthVp) <= 0) {
      return;
    }
    if (resolveTitleWidth(tab, COMFORTABLE_TITLE_CHROME) < COMFORTABLE_TITLE_SLOT_VP) {
      compress = true;
    }
  });
  const chrome = compress ? COMPRESSED_TITLE_CHROME : COMFORTABLE_TITLE_CHROME;
  const slots: BrowserLargeScreenTabTitleSlot[] = [];
  tabs.forEach((tab: BrowserLargeScreenTabTitleSlotInput): void => {
    slots.push(resolveTitleSlot(tab, chrome));
  });
  return slots;
}

function resolveTitleSlot(
  tab: BrowserLargeScreenTabTitleSlotInput,
  chrome: BrowserLargeScreenTabTitleChrome
): BrowserLargeScreenTabTitleSlot {
  const widthVp = resolveTitleWidth(tab, chrome);
  const visible = !tab.pinned && widthVp >= minimumVisibleTitleWidthVp(tab.title);
  return {
    visible: visible,
    widthVp: visible ? widthVp : 0,
    leadingPaddingVp: chrome.leadingPaddingVp,
    trailingPaddingVp: chrome.trailingPaddingVp,
    iconTextGapVp: chrome.iconTextGapVp,
    contentEndPaddingVp: chrome.contentEndPaddingVp
  };
}

function resolveTitleWidth(
  tab: BrowserLargeScreenTabTitleSlotInput,
  chrome: BrowserLargeScreenTabTitleChrome
): number {
  const tabWidthVp = normalizeWidth(tab.tabWidthVp);
  if (tab.pinned || tabWidthVp <= 0) {
    return 0;
  }
  return Math.max(0, tabWidthVp - reservedChromeWidth(tab, chrome));
}

function reservedChromeWidth(
  tab: BrowserLargeScreenTabTitleSlotInput,
  chrome: BrowserLargeScreenTabTitleChrome
): number {
  const trailingActions = (tab.closable ? 1 : 0) + (tab.hasAudioAction ? 1 : 0);
  return chrome.leadingPaddingVp +
    BROWSER_LARGE_SCREEN_TAB_ICON_SIZE_VP +
    chrome.iconTextGapVp +
    chrome.contentEndPaddingVp +
    chrome.trailingPaddingVp +
    trailingActions * (BROWSER_LARGE_SCREEN_TAB_ACTION_GAP_VP + BROWSER_LARGE_SCREEN_TAB_ACTION_BUTTON_SIZE_VP);
}

function minimumVisibleTitleWidthVp(title: string): number {
  const displayTitle = resolveBrowserLargeScreenTabDisplayTitle(title);
  const firstCode = displayTitle.charCodeAt(0);
  const glyphWidthVp = isWideGlyph(firstCode) ? BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP : NARROW_GLYPH_WIDTH_VP;
  return glyphWidthVp + TITLE_ELLIPSIS_WIDTH_VP;
}

function isWideGlyph(code: number): boolean {
  return Number.isFinite(code) && code > 0x00FF;
}

function normalizeWidth(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.round(value);
}

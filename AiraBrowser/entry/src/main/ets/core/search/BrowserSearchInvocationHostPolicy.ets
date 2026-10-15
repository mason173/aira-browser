/**
 * Which visible search host should own the next presentation.
 * A hidden chrome is not a successful target: split style with the bars covered
 * stays unavailable instead of falling through to the suppressed floating panel.
 */
export type BrowserSearchInvocationHostKind = 'large_screen' | 'split' | 'floating' | 'unavailable';

export interface BrowserSearchInvocationHostInput {
  largeScreenShellActive: boolean;
  splitToolbarChromeActive: boolean;
  /** Centered-home search overlay is already opening, even if the bars are not painted. */
  splitSearchOverlayPrepared: boolean;
  legacyFloatingToolbarSuppressed: boolean;
}

export function resolveBrowserSearchInvocationHost(
  input: BrowserSearchInvocationHostInput
): BrowserSearchInvocationHostKind {
  if (input.largeScreenShellActive) {
    return 'large_screen';
  }
  if (input.splitToolbarChromeActive) {
    return 'split';
  }
  // The selected toolbar outranks flags left by a split overlay that is closing.
  // Otherwise switching back to floating can re-enter the old split search host.
  if (!input.legacyFloatingToolbarSuppressed) {
    return 'floating';
  }
  return input.splitSearchOverlayPrepared ? 'split' : 'unavailable';
}

/**
 * A close animation may finish after a newer search has opened. Only the close
 * that is still current, and that was not reopened, may reset shared state.
 */
export function shouldCompleteSearchClose(
  closeGeneration: number,
  callbackGeneration: number,
  searchReopened: boolean
): boolean {
  return closeGeneration > 0 &&
    callbackGeneration === closeGeneration &&
    !searchReopened;
}

/**
 * One open command for the split search field. Version, draft and selection
 * travel together so the field cannot open on a newer tick and an older draft.
 */
export class BrowserSplitToolbarSearchOpen {
  version: number;
  draft: string;
  selectAll: boolean;

  constructor(version: number, draft: string, selectAll: boolean) {
    this.version = version;
    this.draft = draft;
    this.selectAll = selectAll;
  }
}

/**
 * A fresh homepage search starts empty. A fresh web search starts from the
 * page address already on the address row: the published draft can still be
 * empty because the previous close cleared it, or because that draft has not
 * reached the field yet. Only an edit that is already open keeps its draft.
 */
export function resolveSplitToolbarSearchPrefill(
  homeScene: boolean,
  keepPublishedDraft: boolean,
  publishedDraft: string,
  pageAddress: string = ''
): string {
  if (keepPublishedDraft) {
    return publishedDraft;
  }
  if (homeScene) {
    return '';
  }
  if (publishedDraft.length > 0) {
    return publishedDraft;
  }
  return pageAddress;
}

/**
 * A fresh web search selects the page address. Homepage has nothing to select.
 * An edit that is already open keeps the selection the session published.
 */
export function resolveSplitToolbarSearchSelectAll(
  homeScene: boolean,
  continuingEdit: boolean,
  draft: string,
  publishedSelectAll: boolean
): boolean {
  if (continuingEdit) {
    return publishedSelectAll;
  }
  return !homeScene && draft.length > 0;
}

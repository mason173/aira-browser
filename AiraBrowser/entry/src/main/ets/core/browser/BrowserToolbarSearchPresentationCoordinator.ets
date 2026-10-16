import {
  BrowserSplitToolbarSearchOpen,
  shouldCompleteSearchClose
} from '../search/BrowserSearchInvocationHostPolicy';
import { BrowserSplitToolbarSearchPresentation } from './BrowserSplitToolbarSearchInvocationAdapter';

/**
 * Presentation requests and close generations for the shared split/dock host.
 * The window Search Invocation Session owns authority and the canonical draft;
 * this owner only projects accepted presentations into native UI commands.
 */
export class BrowserToolbarSearchPresentationCoordinator {
  private openRequest: BrowserSplitToolbarSearchOpen = new BrowserSplitToolbarSearchOpen(0, '', false);
  private closeGeneration: number = 0;
  private closing: boolean = false;

  accept(presentation: BrowserSplitToolbarSearchPresentation): BrowserSplitToolbarSearchOpen {
    this.closeGeneration += 1;
    this.closing = false;
    this.openRequest = new BrowserSplitToolbarSearchOpen(
      this.openRequest.version + 1, presentation.draft, presentation.selection === 'all'
    );
    return this.openRequest;
  }

  clearDraft(): BrowserSplitToolbarSearchOpen {
    this.openRequest = new BrowserSplitToolbarSearchOpen(this.openRequest.version, '', false);
    return this.openRequest;
  }

  /** Zero means the same close is already running. Suspension supersedes it. */
  beginClose(supersede: boolean = false): number {
    if (this.closing && !supersede) {
      return 0;
    }
    this.closing = true;
    this.closeGeneration += 1;
    return this.closeGeneration;
  }

  completeClose(generation: number, reopened: boolean = false): boolean {
    if (!this.closing || !shouldCompleteSearchClose(generation, this.closeGeneration, reopened)) {
      return false;
    }
    this.closing = false;
    return true;
  }
}

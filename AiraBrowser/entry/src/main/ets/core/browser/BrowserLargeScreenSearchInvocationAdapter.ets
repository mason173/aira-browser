import {
  BrowserSearchInvocationEndReason,
  BrowserSearchInvocationScene,
  BrowserSearchInvocationSurfaceAdapter,
  BrowserSearchPresentationCommitResult,
  BrowserSearchPresentationRequest,
  BrowserSearchSceneSnapshot
} from '../search/BrowserSearchInvocationSessionCoordinator';
import { BrowserSearchSuggestionCoordinator } from './BrowserSearchSuggestionCoordinator';

export interface BrowserLargeScreenSearchInvocationSceneFacts {
  homeScene: boolean;
  webSceneVisible: boolean;
  editableWebAddress: string;
}

export interface BrowserLargeScreenOmniboxPresentation {
  authorityId: string;
  scene: BrowserSearchInvocationScene;
  editing: boolean;
  draft: string;
  selection: 'all' | 'preserve' | 'caret_end';
  requestVersion: number;
  focusRequestPending: boolean;
}

export function createBrowserLargeScreenOmniboxPresentation(): BrowserLargeScreenOmniboxPresentation {
  return {
    authorityId: '',
    scene: 'home',
    editing: false,
    draft: '',
    selection: 'caret_end',
    requestVersion: 0,
    focusRequestPending: false
  };
}

export interface BrowserLargeScreenSearchInvocationHost {
  resolveSceneFacts: () => BrowserLargeScreenSearchInvocationSceneFacts;
  publishPresentation: (presentation: BrowserLargeScreenOmniboxPresentation) => void;
}

/**
 * Large-Screen adapter at the existing Search Invocation surface seam.
 *
 * Search authority and draft ownership remain in the Window-scoped Search
 * Invocation Session. This adapter only commits that session into the top
 * Omnibox and supplies its query/focus state to the shared suggestion owner.
 */
export class BrowserLargeScreenSearchInvocationAdapter implements BrowserSearchInvocationSurfaceAdapter {
  private readonly searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator;
  private readonly host: BrowserLargeScreenSearchInvocationHost;
  private presentation: BrowserLargeScreenOmniboxPresentation =
    createBrowserLargeScreenOmniboxPresentation();

  constructor(
    searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator,
    host: BrowserLargeScreenSearchInvocationHost
  ) {
    this.searchSuggestionCoordinator = searchSuggestionCoordinator;
    this.host = host;
  }

  resolveScene(): BrowserSearchSceneSnapshot {
    const facts = this.host.resolveSceneFacts();
    if (facts.homeScene) {
      return new BrowserSearchSceneSnapshot('home', true, '', 'caret_end');
    }
    if (facts.webSceneVisible) {
      return new BrowserSearchSceneSnapshot('web', true, facts.editableWebAddress, 'all');
    }
    return new BrowserSearchSceneSnapshot('home', true, '', 'caret_end');
  }

  async present(request: BrowserSearchPresentationRequest): Promise<BrowserSearchPresentationCommitResult> {
    const facts = this.host.resolveSceneFacts();
    if (request.scene === 'web' && !facts.webSceneVisible) {
      return new BrowserSearchPresentationCommitResult('failed', 'presentation_commit_failed');
    }
    this.publish({
      authorityId: request.authorityId,
      scene: request.scene,
      editing: true,
      draft: request.draft,
      selection: request.selection,
      requestVersion: this.presentation.requestVersion + 1,
      focusRequestPending: true
    });
    this.searchSuggestionCoordinator.beginSearchSession(request.authorityId, {
      query: request.draft,
      focused: true,
      protectKeyboardSession: false
    });
    return new BrowserSearchPresentationCommitResult('committed');
  }

  suspend(authorityId: string): void {
    if (authorityId !== this.presentation.authorityId) {
      return;
    }
    this.finishPresentation();
  }

  end(authorityId: string, _reason: BrowserSearchInvocationEndReason): void {
    if (authorityId !== this.presentation.authorityId) {
      return;
    }
    this.finishPresentation();
  }

  updateDraft(authorityId: string, draft: string): boolean {
    if (!this.presentation.editing || authorityId !== this.presentation.authorityId) {
      return false;
    }
    this.publish({
      authorityId: authorityId,
      scene: this.presentation.scene,
      editing: true,
      draft: draft,
      selection: 'preserve',
      requestVersion: this.presentation.requestVersion,
      focusRequestPending: this.presentation.focusRequestPending
    });
    this.searchSuggestionCoordinator.updateSearchSessionInput(authorityId, {
      query: draft,
      focused: true,
      protectKeyboardSession: false
    });
    this.searchSuggestionCoordinator.refreshDeferred();
    return true;
  }

  snapshot(): BrowserLargeScreenOmniboxPresentation {
    return this.copyPresentation(this.presentation);
  }

  acknowledgeFocusRequest(requestVersion: number): boolean {
    if (!this.presentation.editing || !this.presentation.focusRequestPending ||
      requestVersion !== this.presentation.requestVersion) {
      return false;
    }
    this.publish({
      authorityId: this.presentation.authorityId,
      scene: this.presentation.scene,
      editing: true,
      draft: this.presentation.draft,
      selection: this.presentation.selection,
      requestVersion: this.presentation.requestVersion,
      focusRequestPending: false
    });
    return true;
  }

  private finishPresentation(): void {
    this.searchSuggestionCoordinator.reset();
    this.publish({
      authorityId: '',
      scene: this.presentation.scene,
      editing: false,
      draft: '',
      selection: 'caret_end',
      requestVersion: this.presentation.requestVersion,
      focusRequestPending: false
    });
  }

  private publish(presentation: BrowserLargeScreenOmniboxPresentation): void {
    this.presentation = this.copyPresentation(presentation);
    this.host.publishPresentation(this.copyPresentation(this.presentation));
  }

  private copyPresentation(
    presentation: BrowserLargeScreenOmniboxPresentation
  ): BrowserLargeScreenOmniboxPresentation {
    return {
      authorityId: presentation.authorityId,
      scene: presentation.scene,
      editing: presentation.editing,
      draft: presentation.draft,
      selection: presentation.selection,
      requestVersion: presentation.requestVersion,
      focusRequestPending: presentation.focusRequestPending
    };
  }
}

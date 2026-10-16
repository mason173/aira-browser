import { BrowserSearchSuggestionSessionInput } from './BrowserSearchSuggestionCoordinator';
import {
  resolveSplitToolbarSearchPrefill,
  resolveSplitToolbarSearchSelectAll
} from '../search/BrowserSearchInvocationHostPolicy';
import {
  BrowserSearchDraftSelection,
  BrowserSearchInvocationEndReason,
  BrowserSearchInvocationScene,
  BrowserSearchInvocationSurfaceAdapter,
  BrowserSearchPresentationCommitResult,
  BrowserSearchPresentationRequest,
  BrowserSearchSceneSnapshot
} from '../search/BrowserSearchInvocationSessionCoordinator';

export interface BrowserSplitToolbarSearchSceneFacts {
  homeScene: boolean;
  webSceneVisible: boolean;
  editableWebAddress: string;
}

export interface BrowserSplitToolbarSearchPresentation {
  authorityId: string;
  scene: BrowserSearchInvocationScene;
  editing: boolean;
  draft: string;
  selection: BrowserSearchDraftSelection;
}

export function createBrowserSplitToolbarSearchPresentation(): BrowserSplitToolbarSearchPresentation {
  return {
    authorityId: '',
    scene: 'home',
    editing: false,
    draft: '',
    selection: 'caret_end'
  };
}

export interface BrowserSplitToolbarSearchSuggestionPort {
  beginSearchSession: (authorityId: string, input: BrowserSearchSuggestionSessionInput) => void;
  cancelPendingWork: () => void;
}

/**
 * The shell applies this presentation onto the split search chrome. The adapter
 * does not own a second session; the Window search invocation does.
 */
export interface BrowserSplitToolbarSearchInvocationHost {
  resolveSceneFacts: () => BrowserSplitToolbarSearchSceneFacts;
  canPresent: () => boolean;
  ensureHomeScene: () => void;
  publishPresentation: (presentation: BrowserSplitToolbarSearchPresentation) => void;
  dismissPresentation: () => void;
  suspendPresentation: () => void;
}

/**
 * Split-toolbar adapter at the existing Search Invocation surface seam.
 *
 * External shortcuts and a tap on the split address row both present through
 * this adapter. The chrome reports edits; it does not open a parallel session.
 */
export class BrowserSplitToolbarSearchInvocationAdapter implements BrowserSearchInvocationSurfaceAdapter {
  private readonly suggestions: BrowserSplitToolbarSearchSuggestionPort;
  private readonly host: BrowserSplitToolbarSearchInvocationHost;
  private presentation: BrowserSplitToolbarSearchPresentation =
    createBrowserSplitToolbarSearchPresentation();

  constructor(
    suggestions: BrowserSplitToolbarSearchSuggestionPort,
    host: BrowserSplitToolbarSearchInvocationHost
  ) {
    this.suggestions = suggestions;
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
    if (request.scene === 'home') {
      this.host.ensureHomeScene();
    }
    const facts = this.host.resolveSceneFacts();
    if (request.scene === 'web' && !facts.webSceneVisible) {
      return new BrowserSearchPresentationCommitResult('failed', 'presentation_commit_failed');
    }
    if (!this.host.canPresent()) {
      return new BrowserSearchPresentationCommitResult('failed', 'presentation_commit_failed');
    }
    const continuingSearch = request.reinforced || request.selection === 'preserve' ||
      this.matches(request.authorityId);
    const draft = resolveSplitToolbarSearchPrefill(
      request.scene === 'home',
      continuingSearch,
      request.draft,
      facts.editableWebAddress
    );
    this.suggestions.beginSearchSession(request.authorityId, {
      query: draft,
      focused: true,
      protectKeyboardSession: true
    });
    this.publish({
      authorityId: request.authorityId,
      scene: request.scene,
      editing: true,
      draft: draft,
      selection: continuingSearch ? request.selection : (resolveSplitToolbarSearchSelectAll(
        request.scene === 'home', false, draft, request.selection === 'all'
      ) ? 'all' : 'caret_end')
    });
    return new BrowserSearchPresentationCommitResult('committed');
  }

  suspend(authorityId: string): void {
    if (!this.matches(authorityId)) {
      return;
    }
    this.suggestions.cancelPendingWork();
    this.host.suspendPresentation();
    this.publishIdle();
  }

  end(authorityId: string, reason: BrowserSearchInvocationEndReason): void {
    if (!this.matches(authorityId)) {
      return;
    }
    if (reason === 'explicit_exit') {
      this.host.dismissPresentation();
    } else {
      this.host.suspendPresentation();
    }
    this.publishIdle();
  }

  snapshot(): BrowserSplitToolbarSearchPresentation {
    return this.copyPresentation(this.presentation);
  }

  private matches(authorityId: string): boolean {
    return this.presentation.editing &&
      this.presentation.authorityId.length > 0 &&
      this.presentation.authorityId === authorityId;
  }

  private publishIdle(): void {
    this.publish({
      authorityId: '',
      scene: this.presentation.scene,
      editing: false,
      draft: '',
      selection: 'caret_end'
    });
  }

  private publish(presentation: BrowserSplitToolbarSearchPresentation): void {
    this.presentation = this.copyPresentation(presentation);
    this.host.publishPresentation(this.copyPresentation(this.presentation));
  }

  private copyPresentation(
    presentation: BrowserSplitToolbarSearchPresentation
  ): BrowserSplitToolbarSearchPresentation {
    return {
      authorityId: presentation.authorityId,
      scene: presentation.scene,
      editing: presentation.editing,
      draft: presentation.draft,
      selection: presentation.selection
    };
  }
}

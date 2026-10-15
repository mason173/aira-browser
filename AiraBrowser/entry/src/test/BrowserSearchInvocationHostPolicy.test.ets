import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserSplitToolbarSearchInvocationAdapter,
  BrowserSplitToolbarSearchInvocationHost,
  BrowserSplitToolbarSearchPresentation,
  BrowserSplitToolbarSearchSceneFacts,
  BrowserSplitToolbarSearchSuggestionPort
} from '../main/ets/core/browser/BrowserSplitToolbarSearchInvocationAdapter';
import { BrowserSearchSuggestionSessionInput } from '../main/ets/core/browser/BrowserSearchSuggestionCoordinator';
import {
  BrowserSearchInvocationHostRouter,
  BrowserSearchInvocationHostRouterHost
} from '../main/ets/core/search/BrowserSearchInvocationHostRouter';
import {
  BrowserSearchInvocationHostKind,
  resolveBrowserSearchInvocationHost,
  resolveSplitToolbarSearchPrefill,
  resolveSplitToolbarSearchSelectAll,
  shouldCompleteSearchClose
} from '../main/ets/core/search/BrowserSearchInvocationHostPolicy';
import {
  BrowserSearchInvocationEndReason,
  BrowserSearchInvocationSessionCoordinator,
  BrowserSearchInvocationSurfaceAdapter,
  BrowserSearchPresentationCommitResult,
  BrowserSearchPresentationRequest,
  BrowserSearchSceneSnapshot
} from '../main/ets/core/search/BrowserSearchInvocationSessionCoordinator';

class RecordingSurface implements BrowserSearchInvocationSurfaceAdapter {
  presentCount: number = 0;
  suspendCount: number = 0;
  endCount: number = 0;
  lastDraft: string = '';
  scene: BrowserSearchSceneSnapshot = new BrowserSearchSceneSnapshot('home', true, '', 'caret_end');

  resolveScene(): BrowserSearchSceneSnapshot {
    return this.scene;
  }

  async present(request: BrowserSearchPresentationRequest): Promise<BrowserSearchPresentationCommitResult> {
    this.presentCount += 1;
    this.lastDraft = request.draft;
    return new BrowserSearchPresentationCommitResult('committed');
  }

  suspend(_authorityId: string): void {
    this.suspendCount += 1;
  }

  end(_authorityId: string, _reason: BrowserSearchInvocationEndReason): void {
    this.endCount += 1;
  }
}

class SplitHost implements BrowserSplitToolbarSearchInvocationHost {
  canPresentSearch: boolean = true;
  homeScene: boolean = true;
  webSceneVisible: boolean = false;
  editableWebAddress: string = '';
  dismissCount: number = 0;
  suspendCount: number = 0;
  published: BrowserSplitToolbarSearchPresentation | undefined = undefined;

  resolveSceneFacts(): BrowserSplitToolbarSearchSceneFacts {
    return {
      homeScene: this.homeScene,
      webSceneVisible: this.webSceneVisible,
      editableWebAddress: this.editableWebAddress
    };
  }

  canPresent(): boolean {
    return this.canPresentSearch;
  }

  ensureHomeScene(): void {
    this.homeScene = true;
  }

  publishPresentation(presentation: BrowserSplitToolbarSearchPresentation): void {
    this.published = presentation;
  }

  dismissPresentation(): void {
    this.dismissCount += 1;
  }

  suspendPresentation(): void {
    this.suspendCount += 1;
  }
}

class SuggestionPort implements BrowserSplitToolbarSearchSuggestionPort {
  authorityId: string = '';
  query: string = '';
  began: number = 0;
  cancelled: number = 0;

  beginSearchSession(authorityId: string, input: BrowserSearchSuggestionSessionInput): void {
    this.began += 1;
    this.authorityId = authorityId;
    this.query = input.query;
  }

  cancelPendingWork(): void {
    this.cancelled += 1;
  }
}

class HostKindSource implements BrowserSearchInvocationHostRouterHost {
  private kind: BrowserSearchInvocationHostKind = 'floating';

  setKind(kind: BrowserSearchInvocationHostKind): void {
    this.kind = kind;
  }

  resolveHostKind(): BrowserSearchInvocationHostKind {
    return this.kind;
  }
}

class ReentrantEndSurface implements BrowserSearchInvocationSurfaceAdapter {
  endCount: number = 0;
  reentrantResult: boolean | undefined = undefined;
  private coordinator: BrowserSearchInvocationSessionCoordinator | undefined = undefined;

  bind(coordinator: BrowserSearchInvocationSessionCoordinator): void {
    this.coordinator = coordinator;
  }

  resolveScene(): BrowserSearchSceneSnapshot {
    return new BrowserSearchSceneSnapshot('home', true, '', 'caret_end');
  }

  async present(_request: BrowserSearchPresentationRequest): Promise<BrowserSearchPresentationCommitResult> {
    return new BrowserSearchPresentationCommitResult('committed');
  }

  suspend(_authorityId: string): void {
  }

  end(_authorityId: string, _reason: BrowserSearchInvocationEndReason): void {
    this.endCount += 1;
    const coordinator = this.coordinator;
    if (coordinator === undefined) {
      return;
    }
    // The floating host releases address focus while ending, which re-enters end()
    // through the shell. That must observe an already-retired session, not recurse.
    this.reentrantResult = coordinator.end(coordinator.currentAuthorityId(), 'explicit_exit');
  }
}

function flushPresentation(): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, 0);
  });
}

export default function browserSearchInvocationHostPolicyTest(): void {
  describe('BrowserSearchInvocationHostPolicy', () => {
    it('routes_a_visible_split_toolbar_to_the_split_host', 0, () => {
      expect(resolveBrowserSearchInvocationHost({
        largeScreenShellActive: false,
        splitToolbarChromeActive: true,
        splitSearchOverlayPrepared: false,
        legacyFloatingToolbarSuppressed: true
      })).assertEqual('split');
      expect(resolveBrowserSearchInvocationHost({
        largeScreenShellActive: false,
        splitToolbarChromeActive: false,
        splitSearchOverlayPrepared: true,
        legacyFloatingToolbarSuppressed: true
      })).assertEqual('split');
    });

    it('keeps_large_screen_and_hidden_split_chrome_off_the_floating_panel', 0, () => {
      expect(resolveBrowserSearchInvocationHost({
        largeScreenShellActive: true,
        splitToolbarChromeActive: false,
        splitSearchOverlayPrepared: false,
        legacyFloatingToolbarSuppressed: false
      })).assertEqual('large_screen');
      expect(resolveBrowserSearchInvocationHost({
        largeScreenShellActive: false,
        splitToolbarChromeActive: false,
        splitSearchOverlayPrepared: false,
        legacyFloatingToolbarSuppressed: true
      })).assertEqual('unavailable');
      expect(resolveBrowserSearchInvocationHost({
        largeScreenShellActive: false,
        splitToolbarChromeActive: false,
        splitSearchOverlayPrepared: false,
        legacyFloatingToolbarSuppressed: false
      })).assertEqual('floating');
    });

    it('ignores_a_stale_close_after_a_newer_search_opens', 0, () => {
      expect(shouldCompleteSearchClose(2, 2, false)).assertTrue();
      expect(shouldCompleteSearchClose(2, 2, true)).assertFalse();
      expect(shouldCompleteSearchClose(2, 3, false)).assertFalse();
      expect(shouldCompleteSearchClose(0, 0, false)).assertFalse();
    });

    it('ignores_the_previous_split_overlay_after_selecting_floating', 0, () => {
      expect(resolveBrowserSearchInvocationHost({
        largeScreenShellActive: false,
        splitToolbarChromeActive: false,
        splitSearchOverlayPrepared: true,
        legacyFloatingToolbarSuppressed: false
      })).assertEqual('floating');
    });

    it('presents_the_split_adapter_for_a_split_host_and_fails_when_hidden', 0, async () => {
      const kind = new HostKindSource();
      const floating = new RecordingSurface();
      const split = new RecordingSurface();
      const largeScreen = new RecordingSurface();
      const router = new BrowserSearchInvocationHostRouter(kind, floating, split, largeScreen);
      kind.setKind('split');
      const coordinator = new BrowserSearchInvocationSessionCoordinator();
      coordinator.registerSurfaceAdapter(router);
      const opened = coordinator.open('keyboard', true);
      const outcome = await opened.presentation;
      expect(outcome.kind).assertEqual('presentation_committed');
      expect(split.presentCount).assertEqual(1);
      expect(floating.presentCount).assertEqual(0);
      expect(coordinator.snapshot().phase).assertEqual('committed');

      kind.setKind('unavailable');
      const hidden = coordinator.open('app_shortcut', true);
      const hiddenOutcome = await hidden.presentation;
      expect(hiddenOutcome.kind).assertEqual('failed');
      expect(floating.presentCount).assertEqual(0);
      expect(split.suspendCount).assertEqual(1);
    });

    it('suspends_the_previous_host_when_the_same_session_changes_surface', 0, async () => {
      const kind = new HostKindSource();
      kind.setKind('split');
      const floating = new RecordingSurface();
      const split = new RecordingSurface();
      split.scene = new BrowserSearchSceneSnapshot('web', true, 'https://example.com', 'all');
      const largeScreen = new RecordingSurface();
      // A host change keeps the same page; a home snapshot would intentionally invalidate the web draft.
      largeScreen.scene = split.scene;
      const router = new BrowserSearchInvocationHostRouter(kind, floating, split, largeScreen);
      const coordinator = new BrowserSearchInvocationSessionCoordinator();
      coordinator.registerSurfaceAdapter(router);
      const opened = coordinator.open('keyboard', true);
      await opened.presentation;
      expect(coordinator.updateDraft(opened.authorityId, 'typed query')).assertTrue();
      kind.setKind('large_screen');
      expect(coordinator.refreshPresentation()).assertTrue();
      await flushPresentation();
      expect(split.suspendCount).assertEqual(1);
      expect(largeScreen.presentCount).assertEqual(1);
      expect(largeScreen.lastDraft).assertEqual('typed query');
      expect(coordinator.snapshot().draft).assertEqual('typed query');
      expect(coordinator.snapshot().phase).assertEqual('committed');
    });

    it('commits_a_visible_split_search_and_ends_only_that_authority', 0, async () => {
      const host = new SplitHost();
      host.homeScene = false;
      host.webSceneVisible = true;
      host.editableWebAddress = 'https://example.com/path';
      const suggestions = new SuggestionPort();
      const adapter = new BrowserSplitToolbarSearchInvocationAdapter(suggestions, host);
      const coordinator = new BrowserSearchInvocationSessionCoordinator();
      coordinator.registerSurfaceAdapter(adapter);
      const opened = coordinator.open('browser_chrome', true);
      const outcome = await opened.presentation;
      expect(outcome.kind).assertEqual('presentation_committed');
      expect(suggestions.began).assertEqual(1);
      expect(suggestions.authorityId).assertEqual(opened.authorityId);
      expect(suggestions.query).assertEqual('https://example.com/path');
      expect(host.published?.editing === true).assertTrue();
      expect(host.published?.draft).assertEqual('https://example.com/path');
      expect(host.published?.selection).assertEqual('all');

      adapter.end('other-authority', 'explicit_exit');
      expect(host.dismissCount).assertEqual(0);
      expect(coordinator.end(opened.authorityId, 'explicit_exit')).assertTrue();
      expect(host.dismissCount).assertEqual(1);
      expect(host.published?.editing === false).assertTrue();
    });

    it('retires_the_session_before_notifying_a_reentrant_surface', 0, async () => {
      const surface = new ReentrantEndSurface();
      const coordinator = new BrowserSearchInvocationSessionCoordinator();
      coordinator.registerSurfaceAdapter(surface);
      surface.bind(coordinator);
      const opened = coordinator.open('keyboard', true);
      await opened.presentation;
      expect(coordinator.end(opened.authorityId, 'explicit_exit')).assertTrue();
      expect(surface.endCount).assertEqual(1);
      expect(surface.reentrantResult === false).assertTrue();
      expect(coordinator.snapshot().phase).assertEqual('ended');
    });

    it('opens_home_search_empty_even_when_the_previous_page_address_is_still_known', 0, async () => {
      const host = new SplitHost();
      host.homeScene = true;
      host.webSceneVisible = false;
      host.editableWebAddress = 'https://example.com/just-visited';
      const suggestions = new SuggestionPort();
      const adapter = new BrowserSplitToolbarSearchInvocationAdapter(suggestions, host);
      const coordinator = new BrowserSearchInvocationSessionCoordinator();
      coordinator.registerSurfaceAdapter(adapter);
      const opened = coordinator.open('browser_chrome', true);
      const outcome = await opened.presentation;
      expect(outcome.kind).assertEqual('presentation_committed');
      expect(host.published?.scene).assertEqual('home');
      expect(host.published?.draft).assertEqual('');
      expect(suggestions.query).assertEqual('');
      expect(resolveSplitToolbarSearchPrefill(true, false, 'https://example.com/just-visited')).assertEqual('');
      expect(resolveSplitToolbarSearchPrefill(true, true, 'typed on home')).assertEqual('typed on home');
      expect(resolveSplitToolbarSearchPrefill(false, false, 'https://example.com/just-visited'))
        .assertEqual('https://example.com/just-visited');
      expect(resolveSplitToolbarSearchPrefill(false, false, '', 'https://example.com/current'))
        .assertEqual('https://example.com/current');
      expect(resolveSplitToolbarSearchPrefill(true, false, '', 'https://example.com/current')).assertEqual('');
      expect(resolveSplitToolbarSearchPrefill(false, true, '', 'https://example.com/current')).assertEqual('');
      expect(resolveSplitToolbarSearchSelectAll(false, false, 'https://example.com/current', false)).assertTrue();
      expect(resolveSplitToolbarSearchSelectAll(true, false, '', false)).assertFalse();
      expect(resolveSplitToolbarSearchSelectAll(false, true, 'typed', false)).assertFalse();
    });

    it('does_not_keep_a_leaked_page_address_when_a_fresh_home_search_is_presented', 0, async () => {
      const host = new SplitHost();
      host.homeScene = true;
      const suggestions = new SuggestionPort();
      const adapter = new BrowserSplitToolbarSearchInvocationAdapter(suggestions, host);
      const result = await adapter.present(new BrowserSearchPresentationRequest(
        'search-session-1',
        'search-session-1-authority-1',
        1,
        'home',
        'https://example.com/just-visited',
        'all',
        false
      ));
      expect(result.kind).assertEqual('committed');
      expect(host.published?.draft).assertEqual('');
      expect(host.published?.selection).assertEqual('caret_end');
      expect(suggestions.query).assertEqual('');

      const continued = await adapter.present(new BrowserSearchPresentationRequest(
        'search-session-1',
        'search-session-1-authority-1',
        2,
        'home',
        'typed on home',
        'preserve',
        true
      ));
      expect(continued.kind).assertEqual('committed');
      expect(host.published?.draft).assertEqual('typed on home');
    });

    it('opens_web_search_with_the_page_address_when_the_published_draft_is_empty', 0, async () => {
      const host = new SplitHost();
      host.homeScene = false;
      host.webSceneVisible = true;
      host.editableWebAddress = 'https://example.com/current';
      const suggestions = new SuggestionPort();
      const adapter = new BrowserSplitToolbarSearchInvocationAdapter(suggestions, host);
      const result = await adapter.present(new BrowserSearchPresentationRequest(
        'search-session-1',
        'search-session-1-authority-1',
        1,
        'web',
        '',
        'all',
        false
      ));
      expect(result.kind).assertEqual('committed');
      expect(host.published?.scene).assertEqual('web');
      expect(host.published?.draft).assertEqual('https://example.com/current');
      expect(suggestions.query).assertEqual('https://example.com/current');
    });

    it('does_not_commit_split_search_when_the_host_cannot_present', 0, async () => {
      const host = new SplitHost();
      host.canPresentSearch = false;
      const suggestions = new SuggestionPort();
      const adapter = new BrowserSplitToolbarSearchInvocationAdapter(suggestions, host);
      const coordinator = new BrowserSearchInvocationSessionCoordinator();
      coordinator.registerSurfaceAdapter(adapter);
      const opened = coordinator.open('desktop_card', true);
      const outcome = await opened.presentation;
      expect(outcome.kind).assertEqual('failed');
      expect(suggestions.began).assertEqual(0);
      expect(host.dismissCount).assertEqual(0);
    });
  });
}

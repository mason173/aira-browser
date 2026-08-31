import { SearchSuggestion } from '../../common/models/BrowserModels';
import {
  BrowserSearchInvocationEndReason,
  BrowserSearchInvocationScene,
  BrowserSearchInvocationSurfaceAdapter,
  BrowserSearchPresentationCommitResult,
  BrowserSearchPresentationRequest,
  BrowserSearchSceneSnapshot
} from '../search/BrowserSearchInvocationSessionCoordinator';
import {
  BrowserRootAddressInputSessionSnapshot,
  BrowserRootBottomPanelChromePlan,
  BrowserRootBottomPanelSessionCoordinator
} from './BrowserRootBottomPanelSessionCoordinator';
import { BrowserSearchSuggestionCoordinator } from './BrowserSearchSuggestionCoordinator';
import { BrowserCreateTabOptions } from '../tabs/TabManager';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserKeyboardShortcutCoordinator } from './BrowserKeyboardShortcutCoordinator';
import {
  BrowserSearchInvocationAuthorityGate,
  BrowserSearchInvocationRuntime
} from '../../app/runtime/BrowserSearchInvocationRuntime';

export interface BrowserShellSearchInvocationSceneFacts {
  homeScene: boolean;
  webSceneVisible: boolean;
  editableWebAddress: string;
  homeCreateOptions: BrowserCreateTabOptions;
}

export interface BrowserShellSearchInvocationHost {
  resolveSceneFacts: () => BrowserShellSearchInvocationSceneFacts;
  resolveAddressSessionSnapshot: () => BrowserRootAddressInputSessionSnapshot;
  applyDraft: (scene: BrowserSearchInvocationScene, draft: string) => void;
  applySearchChromePlan: (plan: BrowserRootBottomPanelChromePlan) => void;
  suspendSearch: () => void;
}

export class BrowserShellSearchInvocationAdapter implements BrowserSearchInvocationSurfaceAdapter {
  private readonly rootBottomPanelSessionCoordinator: BrowserRootBottomPanelSessionCoordinator;
  private readonly searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator;
  private readonly tabHomeCoordinator: BrowserTabHomeCoordinator;
  private readonly keyboardShortcutCoordinator: BrowserKeyboardShortcutCoordinator;
  private readonly host: BrowserShellSearchInvocationHost;

  constructor(
    rootBottomPanelSessionCoordinator: BrowserRootBottomPanelSessionCoordinator,
    searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator,
    tabHomeCoordinator: BrowserTabHomeCoordinator,
    keyboardShortcutCoordinator: BrowserKeyboardShortcutCoordinator,
    host: BrowserShellSearchInvocationHost
  ) {
    this.rootBottomPanelSessionCoordinator = rootBottomPanelSessionCoordinator;
    this.searchSuggestionCoordinator = searchSuggestionCoordinator;
    this.tabHomeCoordinator = tabHomeCoordinator;
    this.keyboardShortcutCoordinator = keyboardShortcutCoordinator;
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
    let facts = this.host.resolveSceneFacts();
    if (request.scene === 'home' && !facts.homeScene) {
      this.tabHomeCoordinator.showHomeSurface('已回到主页', facts.homeCreateOptions);
      facts = this.host.resolveSceneFacts();
    }
    if (request.scene === 'web' && !facts.webSceneVisible) {
      return new BrowserSearchPresentationCommitResult('failed', 'presentation_commit_failed');
    }
    if (request.scene === 'web') {
      this.host.applyDraft('web', request.draft);
    }
    const hostPreparation = request.scene === 'home'
      ? await this.rootBottomPanelSessionCoordinator.prepareHomeSearchPresentationHost()
      : undefined;
    if (hostPreparation !== undefined && hostPreparation.status !== 'ready') {
      return new BrowserSearchPresentationCommitResult('failed', 'presentation_commit_failed');
    }
    const plan = this.rootBottomPanelSessionCoordinator.buildSearchPresentationPlan(request.scene);
    const chromePlanCommitted = hostPreparation === undefined
      ? this.commitSearchChromePlan(plan)
      : this.rootBottomPanelSessionCoordinator.commitPreparedHomeSearchPresentation(hostPreparation, plan);
    if (!chromePlanCommitted) {
      return new BrowserSearchPresentationCommitResult('failed', 'presentation_commit_failed');
    }
    if (request.scene === 'home') {
      this.host.applyDraft('home', request.draft);
    }
    this.searchSuggestionCoordinator.beginSearchSession(request.authorityId);
    return new BrowserSearchPresentationCommitResult('committed');
  }

  suspend(_authorityId: string): void {
    this.rootBottomPanelSessionCoordinator.cancelSearchPresentationHostPreparation();
    this.host.suspendSearch();
  }

  end(_authorityId: string, _reason: BrowserSearchInvocationEndReason): void {
    this.rootBottomPanelSessionCoordinator.cancelSearchPresentationHostPreparation();
    this.searchSuggestionCoordinator.cancelPendingWork();
    this.keyboardShortcutCoordinator.releaseAddressFocus();
  }

  openSuggestion(suggestion: SearchSuggestion): void {
    this.host.applySearchChromePlan(
      this.rootBottomPanelSessionCoordinator.buildHomeSuggestionOpenPlan(
        this.host.resolveAddressSessionSnapshot()
      )
    );
    this.searchSuggestionCoordinator.openSuggestion(suggestion);
  }

  openThirdPartyHomepageSearch(
    windowId: string,
    authorityGate: BrowserSearchInvocationAuthorityGate
  ): void {
    BrowserSearchInvocationRuntime.bindThirdPartyHomeTrigger(windowId, authorityGate).open();
  }

  dismissHomeSearch(): void {
    this.host.applySearchChromePlan(
      this.rootBottomPanelSessionCoordinator.buildHomeSearchExitPlan()
    );
    if (this.searchSuggestionCoordinator.getSnapshot().homeSearchOverlayVisible) {
      this.searchSuggestionCoordinator.reset();
    }
  }

  releaseHomeSearchFocus(): void {
    const snapshot = this.searchSuggestionCoordinator.getSnapshot();
    const plan = this.rootBottomPanelSessionCoordinator.buildHomeSearchReleasePlan({
      homeSearchFocused: snapshot.homeSearchFocused,
      homeSearchOverlayVisible: snapshot.homeSearchOverlayVisible
    });
    if (plan.mode === 'closing') {
      this.searchSuggestionCoordinator.beginClosingOverlay();
      return;
    }
    if (plan.mode === 'dismissed') {
      this.searchSuggestionCoordinator.reset();
    }
  }

  private commitSearchChromePlan(plan: BrowserRootBottomPanelChromePlan): boolean {
    this.host.applySearchChromePlan(plan);
    return true;
  }
}

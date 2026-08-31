import { BrowserStartupRestorePolicy } from '../../common/models/BrowserModels';
import { BrowserTabsOverviewHomeRevealMotion } from './BrowserTabsOverviewActionBarPolicy';
import {
  BrowserHomePresentationViewModel,
  BrowserHomeStartupEntranceVisualState
} from './BrowserHomePresentationViewModel';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import { BrowserTabsOverviewSessionCoordinator } from './BrowserTabsOverviewSessionCoordinator';

const HOME_BOTTOM_PANEL_RESTORE_FROM_PEEK_DELAY_MS: number = 80;

export interface BrowserHomePresentationSessionState {
  startupEntranceState: BrowserHomeStartupEntranceVisualState;
  contentEntranceProgress: number;
  revealProgress: number;
  revealInteractionBlocked: boolean;
  bottomPanelEntryFromTabsOverviewRequestVersion: number;
}

export interface BrowserHomePresentationSessionFacts {
  showHomePage: boolean;
  thirdPartyHomepageActive: boolean;
  showTabsSheet: boolean;
  homeSearchFocused: boolean;
  rootBottomPanelDetent: HomeSearchPanelDetent;
  startupRestorePolicy: BrowserStartupRestorePolicy;
  tabsOverviewAnimationVersion: number;
}

export interface BrowserHomePresentationAnimationPlan {
  durationMs: number;
  curve: Curve | string | ICurve;
  apply: () => void;
  onFinish?: () => void;
}

export interface BrowserHomeRevealPlaybackRequest {
  fadeBackdrop?: boolean;
  restoreBottomPanelFromPeek?: boolean;
}

export interface BrowserHomePresentationSessionHost {
  resolveFacts: () => BrowserHomePresentationSessionFacts;
  publishState: (state: BrowserHomePresentationSessionState) => void;
  executeAnimation: (plan: BrowserHomePresentationAnimationPlan) => void;
  restoreBottomPanelFromPeek: () => void;
}

interface BrowserHomePresentationSessionStatePatch {
  startupEntranceState?: BrowserHomeStartupEntranceVisualState;
  contentEntranceProgress?: number;
  revealProgress?: number;
  revealInteractionBlocked?: boolean;
  bottomPanelEntryFromTabsOverviewRequestVersion?: number;
}

export class BrowserHomePresentationSessionCoordinator {
  private readonly presentationViewModel: BrowserHomePresentationViewModel;
  private readonly tabsOverviewSessionCoordinator: BrowserTabsOverviewSessionCoordinator;
  private readonly host: BrowserHomePresentationSessionHost;
  private state: BrowserHomePresentationSessionState = {
    startupEntranceState: {
      opacity: 1,
      scale: 1,
      hitTestBlocked: false
    },
    contentEntranceProgress: 1,
    revealProgress: 1,
    revealInteractionBlocked: false,
    bottomPanelEntryFromTabsOverviewRequestVersion: 0
  };
  private startupEntranceAnimationRunId: number = 0;
  private startupEntrancePendingInitialPlay: boolean = false;
  private startupEntranceWaitingForThirdPartyCommit: boolean = false;
  private startupEntrancePageShown: boolean = false;
  private contentEntranceAnimationRunId: number = 0;
  private revealAnimationRunId: number = 0;
  private suppressNextContentEntranceAnimation: boolean = false;

  constructor(
    presentationViewModel: BrowserHomePresentationViewModel,
    tabsOverviewSessionCoordinator: BrowserTabsOverviewSessionCoordinator,
    host: BrowserHomePresentationSessionHost
  ) {
    this.presentationViewModel = presentationViewModel;
    this.tabsOverviewSessionCoordinator = tabsOverviewSessionCoordinator;
    this.host = host;
  }

  getState(): BrowserHomePresentationSessionState {
    return this.cloneState(this.state);
  }

  initializeStartupEntrance(): void {
    if (!this.shouldUseStartupEntrance()) {
      this.startupEntrancePendingInitialPlay = false;
      this.startupEntranceWaitingForThirdPartyCommit = false;
      this.startupEntrancePageShown = false;
      this.updateState({
        startupEntranceState: this.buildCompletedStartupEntranceState()
      });
      return;
    }
    const facts = this.host.resolveFacts();
    const initialScale = this.presentationViewModel.resolveStartupEntranceInitialScale(
      facts.thirdPartyHomepageActive
    );
    this.suppressNextContentEntrance();
    this.startupEntrancePendingInitialPlay = true;
    this.startupEntranceWaitingForThirdPartyCommit = facts.thirdPartyHomepageActive;
    this.startupEntrancePageShown = false;
    this.updateState({
      startupEntranceState: this.presentationViewModel.buildStartupEntranceVisualState(
        0,
        initialScale
      )
    });
  }

  playPendingStartupEntrance(): void {
    if (!this.startupEntrancePendingInitialPlay) {
      return;
    }
    this.startupEntrancePageShown = true;
    if (this.startupEntranceWaitingForThirdPartyCommit) {
      return;
    }
    this.startupEntrancePendingInitialPlay = false;
    this.playStartupEntranceIfNeeded();
  }

  handleThirdPartyHomeDocumentCommitted(): void {
    if (!this.startupEntrancePendingInitialPlay ||
      !this.startupEntranceWaitingForThirdPartyCommit) {
      return;
    }
    this.startupEntranceWaitingForThirdPartyCommit = false;
    if (!this.startupEntrancePageShown) {
      return;
    }
    this.startupEntrancePendingInitialPlay = false;
    this.playStartupEntranceIfNeeded();
  }

  handleHomeBecameVisible(): void {
    if (this.consumeContentEntranceSuppression()) {
      return;
    }
    this.playContentEntrance();
  }

  prepareTabsOverviewReveal(motion: BrowserTabsOverviewHomeRevealMotion): void {
    this.suppressNextContentEntrance();
    this.revealAnimationRunId += 1;
    this.updateState({
      startupEntranceState: motion === 'scale' ?
        this.buildCompletedStartupEntranceState() :
        this.state.startupEntranceState,
      revealProgress: 1,
      revealInteractionBlocked: motion === 'scale',
      bottomPanelEntryFromTabsOverviewRequestVersion:
        this.state.bottomPanelEntryFromTabsOverviewRequestVersion + 1
    });
  }

  prepareDirectReveal(): void {
    this.suppressNextContentEntrance();
    this.revealAnimationRunId += 1;
    this.updateState({
      startupEntranceState: this.buildCompletedStartupEntranceState(),
      revealProgress: 0,
      revealInteractionBlocked: true
    });
    this.tabsOverviewSessionCoordinator.prepareBackdropForHomeReveal();
  }

  playReveal(request: BrowserHomeRevealPlaybackRequest = {}): void {
    const runId = ++this.revealAnimationRunId;
    this.host.executeAnimation({
      durationMs: this.presentationViewModel.getRevealDurationMs(),
      curve: this.presentationViewModel.getRevealCurve(),
      apply: (): void => {
        if (this.revealAnimationRunId === runId) {
          this.updateState({ revealProgress: 1 });
        }
      },
      onFinish: (): void => {
        if (this.revealAnimationRunId === runId) {
          this.updateState({
            revealProgress: 1,
            revealInteractionBlocked: false
          });
        }
      }
    });
    if (request.fadeBackdrop === true) {
      this.tabsOverviewSessionCoordinator.playBackdropHomeRevealFade();
    }
    if (request.restoreBottomPanelFromPeek === true) {
      this.scheduleBottomPanelRestoreFromPeek();
    }
  }

  resetReveal(): void {
    this.revealAnimationRunId += 1;
    this.updateState({
      revealProgress: 1,
      revealInteractionBlocked: false
    });
  }

  private playStartupEntranceIfNeeded(): void {
    if (!this.shouldUseStartupEntrance()) {
      this.updateState({
        startupEntranceState: this.buildCompletedStartupEntranceState()
      });
      return;
    }
    const initialFacts = this.host.resolveFacts();
    const initialScale = this.presentationViewModel.resolveStartupEntranceInitialScale(
      initialFacts.thirdPartyHomepageActive
    );
    const delayMs = this.presentationViewModel.getStartupEntranceDelayMs(
      initialFacts.thirdPartyHomepageActive
    );
    const durationMs = this.presentationViewModel.getStartupEntranceDurationMs(
      initialFacts.thirdPartyHomepageActive
    );
    const runId = ++this.startupEntranceAnimationRunId;
    this.updateState({
      startupEntranceState: this.presentationViewModel.buildStartupEntranceVisualState(0, initialScale)
    });
    setTimeout(() => {
      if (this.startupEntranceAnimationRunId !== runId) {
        return;
      }
      const facts = this.host.resolveFacts();
      if (!facts.showHomePage || facts.showTabsSheet) {
        this.updateState({
          startupEntranceState: this.buildCompletedStartupEntranceState()
        });
        return;
      }
      const applyCompletedState = (): void => {
        if (this.startupEntranceAnimationRunId === runId) {
          this.updateState({
            startupEntranceState: this.presentationViewModel.buildStartupEntranceVisualState(1, initialScale)
          });
        }
      };
      this.host.executeAnimation({
        durationMs: durationMs,
        curve: this.presentationViewModel.getStartupEntranceCurve(facts.thirdPartyHomepageActive),
        apply: applyCompletedState,
        onFinish: applyCompletedState
      });
    }, delayMs);
  }

  private playContentEntrance(): void {
    if (!this.host.resolveFacts().showHomePage) {
      return;
    }
    const runId = ++this.contentEntranceAnimationRunId;
    this.updateState({ contentEntranceProgress: 0 });
    setTimeout(() => {
      if (this.contentEntranceAnimationRunId !== runId) {
        return;
      }
      const facts = this.host.resolveFacts();
      if (!facts.showHomePage || facts.showTabsSheet) {
        this.updateState({ contentEntranceProgress: 1 });
        return;
      }
      this.host.executeAnimation({
        durationMs: this.presentationViewModel.getContentEntranceDurationMs(),
        curve: this.presentationViewModel.getContentEntranceCurve(),
        apply: (): void => {
          if (this.contentEntranceAnimationRunId === runId) {
            this.updateState({ contentEntranceProgress: 1 });
          }
        }
      });
    }, this.presentationViewModel.getContentEntranceDelayMs());
  }

  private suppressNextContentEntrance(): void {
    this.suppressNextContentEntranceAnimation = true;
    this.contentEntranceAnimationRunId += 1;
    this.updateState({ contentEntranceProgress: 1 });
  }

  private consumeContentEntranceSuppression(): boolean {
    if (!this.suppressNextContentEntranceAnimation) {
      return false;
    }
    this.suppressNextContentEntranceAnimation = false;
    this.contentEntranceAnimationRunId += 1;
    this.updateState({ contentEntranceProgress: 1 });
    return true;
  }

  private scheduleBottomPanelRestoreFromPeek(): void {
    const animationVersion = this.host.resolveFacts().tabsOverviewAnimationVersion;
    setTimeout(() => {
      const facts = this.host.resolveFacts();
      if (facts.tabsOverviewAnimationVersion !== animationVersion ||
        facts.showTabsSheet ||
        !facts.showHomePage ||
        facts.homeSearchFocused ||
        facts.rootBottomPanelDetent !== 'peek') {
        return;
      }
      this.host.restoreBottomPanelFromPeek();
    }, HOME_BOTTOM_PANEL_RESTORE_FROM_PEEK_DELAY_MS);
  }

  private shouldUseStartupEntrance(): boolean {
    const facts = this.host.resolveFacts();
    return facts.showHomePage &&
      (facts.thirdPartyHomepageActive || facts.startupRestorePolicy === 'open_home');
  }

  private buildCompletedStartupEntranceState(): BrowserHomeStartupEntranceVisualState {
    return this.presentationViewModel.buildStartupEntranceVisualState(1, 1);
  }

  private updateState(patch: BrowserHomePresentationSessionStatePatch): void {
    this.state = {
      startupEntranceState: patch.startupEntranceState ?? this.state.startupEntranceState,
      contentEntranceProgress: patch.contentEntranceProgress ?? this.state.contentEntranceProgress,
      revealProgress: patch.revealProgress ?? this.state.revealProgress,
      revealInteractionBlocked: patch.revealInteractionBlocked ?? this.state.revealInteractionBlocked,
      bottomPanelEntryFromTabsOverviewRequestVersion:
        patch.bottomPanelEntryFromTabsOverviewRequestVersion ??
          this.state.bottomPanelEntryFromTabsOverviewRequestVersion
    };
    this.host.publishState(this.cloneState(this.state));
  }

  private cloneState(state: BrowserHomePresentationSessionState): BrowserHomePresentationSessionState {
    return {
      startupEntranceState: {
        opacity: state.startupEntranceState.opacity,
        scale: state.startupEntranceState.scale,
        hitTestBlocked: state.startupEntranceState.hitTestBlocked
      },
      contentEntranceProgress: state.contentEntranceProgress,
      revealProgress: state.revealProgress,
      revealInteractionBlocked: state.revealInteractionBlocked,
      bottomPanelEntryFromTabsOverviewRequestVersion: state.bottomPanelEntryFromTabsOverviewRequestVersion
    };
  }
}

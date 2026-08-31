import { common } from '@kit.AbilityKit';
import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceCoordinator
} from '../browser/BrowserTransientSurfaceCoordinator';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import { BrowserShellFamily } from '../browser/BrowserWindowPresentationProfile';
import { AppReviewPromptCoordinator } from '../review/AppReviewPromptCoordinator';
import {
  HIDDEN_RELEASE_NOTICE_UI_STATE,
  ReleaseNoticeCoordinator,
  ReleaseNoticeUiState
} from './ReleaseNoticeCoordinator';

export interface ReleaseNoticePresentationShellFacts {
  context: common.Context;
  homeVisible: boolean;
  privateMode: boolean;
  appVisible: boolean;
  shellFamily?: BrowserShellFamily;
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

export interface ReleaseNoticePresentationShell {
  resolveFacts: () => ReleaseNoticePresentationShellFacts;
  publishState: (state: ReleaseNoticeUiState) => void;
}

export type ReleaseNoticePresentationAction = 'confirm' | 'open_full_changelog';

const RELEASE_NOTICE_EVALUATION_DELAY_MS: number = 900;

export class ReleaseNoticePresentationCoordinator {
  private readonly releaseNoticeCoordinator: ReleaseNoticeCoordinator;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly appReviewPromptCoordinator: AppReviewPromptCoordinator;
  private readonly routeCoordinator: BrowserShellRouteCoordinator;
  private readonly shell: ReleaseNoticePresentationShell;
  private evaluateTimer: number = -1;
  private evaluationGeneration: number = 0;
  private state: ReleaseNoticeUiState = HIDDEN_RELEASE_NOTICE_UI_STATE;

  constructor(
    releaseNoticeCoordinator: ReleaseNoticeCoordinator,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    appReviewPromptCoordinator: AppReviewPromptCoordinator,
    routeCoordinator: BrowserShellRouteCoordinator,
    shell: ReleaseNoticePresentationShell
  ) {
    this.releaseNoticeCoordinator = releaseNoticeCoordinator;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.appReviewPromptCoordinator = appReviewPromptCoordinator;
    this.routeCoordinator = routeCoordinator;
    this.shell = shell;
  }

  getSnapshot(): ReleaseNoticeUiState {
    return this.state;
  }

  scheduleEvaluation(): void {
    this.cancelEvaluation();
    const generation = this.evaluationGeneration;
    this.evaluateTimer = setTimeout(() => {
      this.evaluateTimer = -1;
      void this.evaluate(generation);
    }, RELEASE_NOTICE_EVALUATION_DELAY_MS);
  }

  handleAction(action: ReleaseNoticePresentationAction): void {
    const hadPresentation = this.clearPresentation(true);
    this.transientSurfaceCoordinator.closeSystemSheet();
    if (hadPresentation && action === 'open_full_changelog') {
      this.routeCoordinator.openChangelogPage();
    }
  }

  handleSystemSheetDisappear(): void {
    this.clearPresentation(true);
  }

  handleShellReset(): void {
    this.cancelEvaluation();
    this.clearPresentation(false);
  }

  private cancelEvaluation(): void {
    this.evaluationGeneration += 1;
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private async evaluate(generation: number): Promise<void> {
    const initialFacts = this.resolveEligibleFacts(generation);
    if (initialFacts === undefined) {
      return;
    }
    try {
      const noticeState = await this.releaseNoticeCoordinator.buildNoticeState(initialFacts.context);
      if (!noticeState.visible || !this.canPresent(generation)) {
        return;
      }
      await this.releaseNoticeCoordinator.acknowledgeCurrentVersion();
      if (!this.canPresent(generation)) {
        return;
      }
      this.publishState(noticeState);
      this.transientSurfaceCoordinator.openSystemSheet('releaseNotice');
    } catch (_error) {
    }
  }

  private canPresent(generation: number): boolean {
    return this.resolveEligibleFacts(generation) !== undefined;
  }

  private resolveEligibleFacts(generation: number): ReleaseNoticePresentationShellFacts | undefined {
    if (generation !== this.evaluationGeneration || this.state.visible) {
      return undefined;
    }
    const facts = this.shell.resolveFacts();
    if (facts.shellFamily !== 'phone' || !facts.appVisible || !facts.homeVisible || facts.privateMode ||
      this.transientSurfaceCoordinator.isReleaseNoticeBlocked(facts.promptBlockingFacts)) {
      return undefined;
    }
    return facts;
  }

  private clearPresentation(notifyAppReview: boolean): boolean {
    if (!this.state.visible) {
      return false;
    }
    this.publishState(HIDDEN_RELEASE_NOTICE_UI_STATE);
    if (notifyAppReview) {
      this.appReviewPromptCoordinator.handleReleaseNoticePresentationCleared();
    }
    return true;
  }

  private publishState(state: ReleaseNoticeUiState): void {
    this.state = state;
    this.shell.publishState(state);
  }
}

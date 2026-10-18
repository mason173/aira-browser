import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceId,
  BrowserTransientSurfacePresentationRequest,
  BrowserTransientSurfaceToken
} from '../browser/BrowserTransientSurfaceCoordinator';
import { AppRecommendationRepository } from '../../data/onboarding/AppRecommendationRepository';

export type AppRecommendationAction = 'dismiss' | 'open_market';

export interface AppRecommendationSnapshot {
  visible: boolean;
  /** The campaign the card is showing; empty while nothing is on screen. */
  recommendationId: string;
}

export function createHiddenAppRecommendationSnapshot(): AppRecommendationSnapshot {
  return {
    visible: false,
    recommendationId: ''
  };
}

export interface AppRecommendationShellFacts {
  /** The recommendation card is a phone bottom sheet; the large-screen shell does not present it. */
  shellFamily: 'phone' | 'large_screen';
  /** The homepage is the only surface it belongs on, so a Web page or a pushed route stays silent. */
  homeVisible: boolean;
  appVisible: boolean;
  privacyMode: string;
  /**
   * Ordered recommendation campaigns from the catalog. The coordinator offers the
   * first one this device has not spent, so adding a recommendation is a catalog
   * change and nothing else.
   */
  recommendationIds: string[];
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

/**
 * The narrow slice of the transient-surface owner this card needs, so the
 * recommendation stays free of the whole browser stack it presents over.
 */
export interface AppRecommendationSurface {
  present: (request: BrowserTransientSurfacePresentationRequest) => BrowserTransientSurfaceToken;
  dismiss: (id: BrowserTransientSurfaceId) => void;
  isReleaseNoticeBlocked: (facts: BrowserTransientPromptBlockingFacts) => boolean;
}

export interface AppRecommendationShell {
  resolveFacts: () => AppRecommendationShellFacts;
  publishState: (snapshot: AppRecommendationSnapshot) => void;
  /**
   * Hands the campaign's store page to the platform. The shell owns how a store
   * page opens; this owner only decides that the user asked for it.
   */
  openStore: (recommendationId: string) => void;
}

const APP_RECOMMENDATION_EVALUATION_DELAY_MS: number = 900;

/**
 * Announces companion apps on the phone homepage, once per recommendation.
 *
 * Eligibility is one device-local fact per campaign, so the memory is per
 * recommendation rather than per install: a user who closed the first card is
 * asked once about the next app, and a user who closes that one is never asked
 * about it again. Which apps are on offer, and in what order, comes in through
 * the shell facts, so the campaign catalog can grow without touching this owner.
 *
 * At most one card is offered per homepage arrival. The lane that automatic
 * prompts share can be held by a release notice or another announcement, and a
 * prompt holding the lane defers the card rather than dropping it; the card is
 * re-decided whenever that lane clears. Deferring does not re-arm: only arriving
 * at the homepage again opens the next opportunity, so two pending campaigns can
 * never land back to back.
 *
 * Only a card that actually reveals spends its campaign: a custom bottom surface
 * mounts asynchronously, and an abandoned mount must not consume the telling.
 *
 * Phone only: the phone homepage is the surface this announcement belongs to,
 * and the large-screen shell opens into its own information architecture.
 */
export class AppRecommendationCoordinator {
  private readonly repository: AppRecommendationRepository;
  private readonly surface: AppRecommendationSurface;
  private readonly shell: AppRecommendationShell;
  private readonly evaluationDelayMs: number;
  private evaluateTimer: number = -1;
  private evaluationGeneration: number = 0;
  private presentationGeneration: number = 0;
  /**
   * The user has arrived at the homepage and one campaign may be offered. Cleared
   * by the reveal, by a dismissal, and by a shell reset, so a later evaluation
   * cannot turn a single arrival into a queue of cards.
   */
  private armed: boolean = false;
  private snapshot: AppRecommendationSnapshot = createHiddenAppRecommendationSnapshot();

  constructor(
    repository: AppRecommendationRepository,
    surface: AppRecommendationSurface,
    shell: AppRecommendationShell,
    evaluationDelayMs: number = APP_RECOMMENDATION_EVALUATION_DELAY_MS
  ) {
    this.repository = repository;
    this.surface = surface;
    this.shell = shell;
    this.evaluationDelayMs = evaluationDelayMs;
  }

  getSnapshot(): AppRecommendationSnapshot {
    return this.snapshot;
  }

  /**
   * The user is looking at the homepage. That arrival is the opportunity: it arms
   * the next unspent campaign, if there is one, and decides whether it may
   * present now.
   */
  handleHomeSurfaceVisible(): void {
    this.armed = true;
    this.scheduleEvaluation();
  }

  /**
   * Re-decides whether the armed card may present now. Safe to call at any time:
   * it is a no-op until a homepage arrival armed it, and a no-op once the arrival
   * has already offered its one card.
   */
  scheduleEvaluation(): void {
    this.cancelEvaluation();
    if (!this.armed) {
      return;
    }
    const generation = this.evaluationGeneration;
    this.evaluateTimer = setTimeout((): void => {
      this.evaluateTimer = -1;
      void this.evaluate(generation);
    }, this.evaluationDelayMs);
  }

  handleAction(action: AppRecommendationAction): void {
    if (action !== 'dismiss' && action !== 'open_market') {
      return;
    }
    const recommendationId = this.snapshot.recommendationId;
    if (recommendationId.length === 0) {
      return;
    }
    if (action === 'open_market') {
      this.shell.openStore(recommendationId);
    }
    // Both actions end the telling: the card is spent at reveal either way, and
    // opening the store page is the user acting on what the card said.
    void this.repository.markDismissed(recommendationId).catch((_error: Error): void => {
    });
    this.surface.dismiss('app_recommendation');
  }

  /**
   * Records that the recommendation reached the user. A custom bottom surface
   * mounts asynchronously, so a presentation abandoned before its reveal must not
   * spend the one-time announcement.
   */
  handleSurfaceRevealed(): void {
    const recommendationId = this.snapshot.recommendationId;
    if (!this.snapshot.visible || recommendationId.length === 0) {
      return;
    }
    this.armed = false;
    void this.repository.markShown(recommendationId).catch((_error: Error): void => {
    });
  }

  handleSurfaceDismissed(): void {
    this.presentationGeneration += 1;
    this.armed = false;
    this.publishState(createHiddenAppRecommendationSnapshot());
  }

  handleShellReset(): void {
    this.cancelEvaluation();
    this.presentationGeneration += 1;
    this.armed = false;
    this.publishState(createHiddenAppRecommendationSnapshot());
  }

  private cancelEvaluation(): void {
    this.evaluationGeneration += 1;
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private async evaluate(generation: number): Promise<void> {
    if (generation !== this.evaluationGeneration || this.snapshot.visible || !this.armed) {
      return;
    }
    await this.repository.initialize().catch((_error: Error): void => {
    });
    if (generation !== this.evaluationGeneration || this.snapshot.visible || !this.armed) {
      return;
    }
    if (!this.canPresent(generation)) {
      return;
    }
    const recommendationId = this.resolvePendingRecommendationId();
    if (recommendationId.length === 0) {
      return;
    }
    this.presentRecommendation(recommendationId);
  }

  /** The first campaign in catalog order that this device has neither seen nor closed. */
  private resolvePendingRecommendationId(): string {
    const recommendationIds = this.shell.resolveFacts().recommendationIds;
    for (let index = 0; index < recommendationIds.length; index++) {
      const recommendationId = recommendationIds[index];
      if (recommendationId.length > 0 && !this.repository.hasCompleted(recommendationId)) {
        return recommendationId;
      }
    }
    return '';
  }

  /**
   * Whether a presentation may still start. The published snapshot is not
   * consulted here: publishing it is what expresses the intent to present, so
   * treating it as a blocker would abandon every presentation at the reveal step.
   */
  private canPresent(generation: number): boolean {
    if (generation !== this.evaluationGeneration) {
      return false;
    }
    const facts = this.shell.resolveFacts();
    if (facts.shellFamily !== 'phone') {
      return false;
    }
    if (!facts.appVisible || !facts.homeVisible || facts.privacyMode === 'private') {
      return false;
    }
    return !this.surface.isReleaseNoticeBlocked(facts.promptBlockingFacts);
  }

  private presentRecommendation(recommendationId: string): void {
    this.publishState({ visible: true, recommendationId: recommendationId });
    this.presentationGeneration += 1;
    const presentationGeneration = this.presentationGeneration;
    this.surface.present({
      id: 'app_recommendation',
      revealDelayMs: 0,
      dismissDurationMs: 0,
      shouldReveal: (): boolean =>
        presentationGeneration === this.presentationGeneration && this.snapshot.visible
    });
  }

  private publishState(snapshot: AppRecommendationSnapshot): void {
    this.snapshot = snapshot;
    this.shell.publishState(snapshot);
  }
}

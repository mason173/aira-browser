import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceId,
  BrowserTransientSurfacePresentationRequest,
  BrowserTransientSurfaceToken
} from '../browser/BrowserTransientSurfaceCoordinator';
import { BottomToolbarGuideRepository } from '../../data/onboarding/BottomToolbarGuideRepository';
import { BrowserDeviceFormFactor } from '../browser/BrowserDeviceFormFactorCoordinator';

export type BottomToolbarGuideAction = 'acknowledge' | 'never_show_again';

export interface BottomToolbarGuideSnapshot {
  visible: boolean;
  title: string;
  message: string;
  primaryActionTitle: string;
  secondaryActionTitle: string;
}

export function createHiddenBottomToolbarGuideSnapshot(): BottomToolbarGuideSnapshot {
  return {
    visible: false,
    title: '',
    message: '',
    primaryActionTitle: '',
    secondaryActionTitle: ''
  };
}

export interface BottomToolbarGuideShellFacts {
  shellFamily: 'phone' | 'large_screen';
  /**
   * What the platform says the device is, before the shell falls back to its phone
   * adapter. A PC and a 2in1 device can end up on the phone shell, so the shell family
   * alone cannot tell them apart from a phone.
   */
  deviceFormFactor: BrowserDeviceFormFactor;
  appVisible: boolean;
  /** The phone lesson explains the floating toolbar. The split frame has no such gesture. */
  floatingToolbarChromeActive: boolean;
  privacyMode: string;
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

/**
 * The narrow slice of the transient-surface owner this lesson needs. Keeping it
 * this small keeps the lesson free of the whole browser stack it presents over.
 */
export interface BottomToolbarGuideSurface {
  present: (request: BrowserTransientSurfacePresentationRequest) => BrowserTransientSurfaceToken;
  dismiss: (id: BrowserTransientSurfaceId) => void;
  isReleaseNoticeBlocked: (facts: BrowserTransientPromptBlockingFacts) => boolean;
}

export interface BottomToolbarGuideShell {
  resolveFacts: () => BottomToolbarGuideShellFacts;
  publishState: (snapshot: BottomToolbarGuideSnapshot) => void;
}

const BOTTOM_TOOLBAR_GUIDE_EVALUATION_DELAY_MS: number = 700;
const BOTTOM_TOOLBAR_GUIDE_TITLE: string = '向下滑动隐藏悬浮工具条';
const BOTTOM_TOOLBAR_GUIDE_MESSAGE: string = '工具条就会收起来，只看网页内容，浏览更清爽。';
const BOTTOM_TOOLBAR_GUIDE_PRIMARY_ACTION_TITLE: string = '我知道了';
const BOTTOM_TOOLBAR_GUIDE_SECONDARY_ACTION_TITLE: string = '不再提示';

/**
 * Teaches a first-time user, once, that the phone floating toolbar can be swiped
 * down out of the way. The lesson is armed by the first Web page that finishes
 * loading and is spent only when the card actually reaches the user, so a load
 * that lands while another prompt holds the lane defers the lesson instead of
 * losing it.
 *
 * Phone only: the large-screen shell has its own toolbar that is not swiped away.
 */
export class BottomToolbarGuideCoordinator {
  private readonly repository: BottomToolbarGuideRepository;
  private readonly surface: BottomToolbarGuideSurface;
  private readonly shell: BottomToolbarGuideShell;
  private readonly evaluationDelayMs: number;
  private armed: boolean = false;
  private evaluateTimer: number = -1;
  private evaluationGeneration: number = 0;
  private presentationGeneration: number = 0;
  private snapshot: BottomToolbarGuideSnapshot = createHiddenBottomToolbarGuideSnapshot();

  constructor(
    repository: BottomToolbarGuideRepository,
    surface: BottomToolbarGuideSurface,
    shell: BottomToolbarGuideShell,
    evaluationDelayMs: number = BOTTOM_TOOLBAR_GUIDE_EVALUATION_DELAY_MS
  ) {
    this.repository = repository;
    this.surface = surface;
    this.shell = shell;
    this.evaluationDelayMs = evaluationDelayMs;
  }

  getSnapshot(): BottomToolbarGuideSnapshot {
    return this.snapshot;
  }

  /**
   * The active phone tab finished loading a Web page. The first such load arms
   * the guide, and every later load re-decides whether the pending lesson may
   * present now.
   */
  handleWebPageLoadCompleted(): void {
    if (this.repository.hasCompleted()) {
      return;
    }
    this.armed = true;
    this.scheduleEvaluation();
  }

  /**
   * Re-decides whether the armed guide may present now. Safe to call at any time:
   * it is a no-op until a Web page has armed the guide.
   */
  scheduleEvaluation(): void {
    this.cancelEvaluation();
    if (!this.armed || this.repository.hasCompleted()) {
      return;
    }
    const generation = this.evaluationGeneration;
    this.evaluateTimer = setTimeout((): void => {
      this.evaluateTimer = -1;
      void this.evaluate(generation);
    }, this.evaluationDelayMs);
  }

  handleAction(action: BottomToolbarGuideAction): void {
    if (action === 'never_show_again') {
      void this.repository.markCompleted().catch((_error: Error): void => {
      });
    }
    this.surface.dismiss('bottom_toolbar_guide');
  }

  /**
   * Records that the lesson reached the user. A custom bottom surface mounts
   * asynchronously, so a presentation abandoned before its reveal must not spend
   * the one-time guide.
   */
  handleSurfaceRevealed(): void {
    if (!this.snapshot.visible) {
      return;
    }
    this.armed = false;
    void this.repository.markShown().catch((_error: Error): void => {
    });
  }

  handleSurfaceDismissed(): void {
    this.presentationGeneration += 1;
    this.publishState(createHiddenBottomToolbarGuideSnapshot());
  }

  handleShellReset(): void {
    this.cancelEvaluation();
    // A route or window reset drops the lesson back to unarmed; the next Web page
    // that finishes loading offers it again unless the user already saw it.
    this.armed = false;
    this.presentationGeneration += 1;
    this.publishState(createHiddenBottomToolbarGuideSnapshot());
  }

  private cancelEvaluation(): void {
    this.evaluationGeneration += 1;
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private async evaluate(generation: number): Promise<void> {
    if (generation !== this.evaluationGeneration || this.snapshot.visible) {
      return;
    }
    if (!this.armed) {
      return;
    }
    await this.repository.initialize().catch((_error: Error): void => {
    });
    if (generation !== this.evaluationGeneration || this.snapshot.visible) {
      return;
    }
    if (this.repository.hasCompleted() || !this.canPresent(generation)) {
      return;
    }
    this.presentGuide();
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
    if (!facts.floatingToolbarChromeActive) {
      return false;
    }
    // A desktop has no bottom floating toolbar to swipe away, and a cockpit
    // must not teach a glance-heavy gesture while driving.
    if (facts.deviceFormFactor === 'pc' || facts.deviceFormFactor === 'two_in_one' ||
      facts.deviceFormFactor === 'car') {
      return false;
    }
    if (!facts.appVisible || facts.privacyMode === 'private') {
      return false;
    }
    return !this.surface.isReleaseNoticeBlocked(facts.promptBlockingFacts);
  }

  private presentGuide(): void {
    this.publishState({
      visible: true,
      title: BOTTOM_TOOLBAR_GUIDE_TITLE,
      message: BOTTOM_TOOLBAR_GUIDE_MESSAGE,
      primaryActionTitle: BOTTOM_TOOLBAR_GUIDE_PRIMARY_ACTION_TITLE,
      secondaryActionTitle: BOTTOM_TOOLBAR_GUIDE_SECONDARY_ACTION_TITLE
    });
    this.presentationGeneration += 1;
    const presentationGeneration = this.presentationGeneration;
    this.surface.present({
      id: 'bottom_toolbar_guide',
      revealDelayMs: 0,
      dismissDurationMs: 0,
      shouldReveal: (): boolean =>
        presentationGeneration === this.presentationGeneration && this.snapshot.visible
    });
  }

  private publishState(snapshot: BottomToolbarGuideSnapshot): void {
    this.snapshot = snapshot;
    this.shell.publishState(snapshot);
  }
}

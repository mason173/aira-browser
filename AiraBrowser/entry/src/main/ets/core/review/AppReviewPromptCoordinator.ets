import { common } from '@kit.AbilityKit';
import bundleManager from '@ohos.bundle.bundleManager';
import { APP_PREVIEW_VERSION_NAME } from '../../common/constants/AppVersionInfo';
import {
  AppReviewPromptRepository,
  AppReviewPromptState
} from '../../data/review/AppReviewPromptRepository';
import { SystemSettingsLaunchService } from '../../services/system/SystemSettingsLaunchService';
import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceCoordinator
} from '../browser/BrowserTransientSurfaceCoordinator';

const MIN_FIRST_SEEN_AGE_MS: number = 3 * 24 * 60 * 60 * 1000;
const MIN_LAUNCH_COUNT: number = 5;
const MIN_REGULAR_PAGE_VISIT_COUNT: number = 30;
const DEFER_COOLDOWN_MS: number = 30 * 24 * 60 * 60 * 1000;
const PROMPT_COOLDOWN_MS: number = 90 * 24 * 60 * 60 * 1000;
const MAX_PROMPT_COUNT: number = 2;
const APP_REVIEW_PROMPT_EVALUATION_DELAY_MS: number = 1200;

export interface AppReviewPromptVisitInput {
  url: string;
  privacyMode: string;
  dataScope: string;
}

export interface AppReviewPromptShellFacts {
  context: common.UIAbilityContext;
  homeVisible: boolean;
  privateMode: boolean;
  appVisible: boolean;
  promptBlockingFacts: BrowserTransientPromptBlockingFacts;
}

export interface AppReviewPromptShell {
  resolveFacts: () => AppReviewPromptShellFacts;
  showToast: (message: string) => void;
}

export class AppReviewPromptCoordinator {
  private readonly repository: AppReviewPromptRepository;
  private readonly systemSettingsLaunchService: SystemSettingsLaunchService;
  private readonly transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  private readonly shell: AppReviewPromptShell;
  private evaluateTimer: number = -1;
  private evaluationDeferredByReleaseNotice: boolean = false;
  private systemPromptInFlight: boolean = false;

  constructor(
    repository: AppReviewPromptRepository,
    systemSettingsLaunchService: SystemSettingsLaunchService,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    shell: AppReviewPromptShell
  ) {
    this.repository = repository;
    this.systemSettingsLaunchService = systemSettingsLaunchService;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.shell = shell;
  }

  recordRegularPageVisit(input: AppReviewPromptVisitInput): void {
    if (!this.shouldCountVisit(input)) {
      return;
    }
    this.repository.recordRegularPageVisit()
      .then(() => {})
      .catch((_error: Error) => {});
  }

  scheduleEvaluation(): void {
    this.cancelEvaluationTimer();
    this.evaluationDeferredByReleaseNotice = false;
    this.evaluateTimer = setTimeout(() => {
      this.evaluateTimer = -1;
      this.evaluate();
    }, APP_REVIEW_PROMPT_EVALUATION_DELAY_MS);
  }

  handleReleaseNoticePresentationCleared(): void {
    if (this.evaluationDeferredByReleaseNotice) {
      this.scheduleEvaluation();
    }
  }

  handleShellReset(): void {
    this.cancelEvaluationTimer();
    this.evaluationDeferredByReleaseNotice = false;
  }

  private evaluate(): void {
    if (this.systemPromptInFlight) {
      return;
    }
    const facts = this.shell.resolveFacts();
    const blockingSurfaceVisible = this.transientSurfaceCoordinator.isAppReviewPromptBlocked(
      facts.promptBlockingFacts
    );
    if (!facts.appVisible || !facts.homeVisible || facts.privateMode) {
      this.evaluationDeferredByReleaseNotice = false;
      return;
    }
    if (blockingSurfaceVisible) {
      this.evaluationDeferredByReleaseNotice = facts.promptBlockingFacts.releaseNoticeVisible;
      return;
    }
    this.evaluationDeferredByReleaseNotice = false;
    if (!this.shouldOfferPrompt(this.repository.getState())) {
      return;
    }
    void this.presentNativeReviewDialog(facts.context);
  }

  private async presentNativeReviewDialog(context: common.UIAbilityContext): Promise<void> {
    if (this.systemPromptInFlight) {
      return;
    }
    this.systemPromptInFlight = true;
    try {
      const result = await this.systemSettingsLaunchService.showAppReviewPrompt(context);
      if (!result.success) {
        this.shell.showToast(result.message.length > 0 ? result.message : '暂时无法打开评分弹窗。');
        return;
      }
      await this.repository.markPromptShown().catch((_error: Error) => {});
    } catch (_error) {
      this.shell.showToast('暂时无法打开评分弹窗。');
    } finally {
      this.systemPromptInFlight = false;
    }
  }

  private cancelEvaluationTimer(): void {
    if (this.evaluateTimer >= 0) {
      clearTimeout(this.evaluateTimer);
      this.evaluateTimer = -1;
    }
  }

  private shouldOfferPrompt(state: AppReviewPromptState): boolean {
    const now = Date.now();
    if (state.suppressedAt > 0) {
      return false;
    }
    if (state.acceptedAt > 0 && state.acceptedVersionName === this.resolveCurrentVersionName()) {
      return false;
    }
    if (state.promptCount >= MAX_PROMPT_COUNT) {
      return false;
    }
    if (state.firstSeenAt <= 0 || now - state.firstSeenAt < MIN_FIRST_SEEN_AGE_MS) {
      return false;
    }
    if (state.launchCount < MIN_LAUNCH_COUNT || state.regularPageVisitCount < MIN_REGULAR_PAGE_VISIT_COUNT) {
      return false;
    }
    if (state.lastDeferredAt > 0 && now - state.lastDeferredAt < DEFER_COOLDOWN_MS) {
      return false;
    }
    if (state.lastPromptAt > 0 && now - state.lastPromptAt < PROMPT_COOLDOWN_MS) {
      return false;
    }
    return true;
  }

  private shouldCountVisit(input: AppReviewPromptVisitInput): boolean {
    const url = input.url.trim();
    if (!this.isHttpOrHttpsUrl(url)) {
      return false;
    }
    return input.privacyMode !== 'private' && input.dataScope !== 'session_ephemeral';
  }

  private isHttpOrHttpsUrl(url: string): boolean {
    const normalizedUrl = url.trim().toLowerCase();
    return normalizedUrl.startsWith('https://') || normalizedUrl.startsWith('http://');
  }

  private resolveCurrentVersionName(): string {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const versionName = `${bundleInfo.versionName ?? ''}`.trim();
      return versionName.length > 0 ? versionName : APP_PREVIEW_VERSION_NAME;
    } catch (_error) {
      return APP_PREVIEW_VERSION_NAME;
    }
  }
}

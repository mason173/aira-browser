import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  sharedBrowserArkWebProcessLifecycleCoordinator
} from '../../core/browser/BrowserArkWebProcessLifecycleCoordinator';

const DOMAIN: number = 0x0000;
const TAG: string = 'WebVideoPipBackground';
const TIMER_HOLD_REASON: string = 'web_picture_in_picture';
const BACKGROUND_PLAY_MODE_MIN_API: number = 24;
const ENABLE_BACKGROUND_PLAY_MODE: number = 0;
const DISABLE_BACKGROUND_PLAY_MODE: number = 1;
const SESSION_RETRY_LIMIT: number = 6;
const SESSION_RETRY_DELAY_MS: number = 400;
const CONTINUOUS_TASK_RETRY_DELAY_MS: number = 500;
const OPEN_BROWSER_WANT_REQUEST_CODE: number = 240180;

interface BackgroundPlayModeSession {
  setBackgroundPlayMode?: (mode: number) => Promise<void>;
}

export class WebVideoPictureInPictureBackgroundKeeper {
  private activeTabIds: string[] = [];
  private generation: number = 0;
  private pending: Promise<void> = Promise.resolve();
  private continuousTaskContext?: common.UIAbilityContext;
  private continuousTaskId?: number;
  private borrowedVideoSession?: avSession.AVSession;
  private backgroundPlayEnabled: boolean = false;

  observe(tabId: string, active: boolean): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    const wasActive = this.activeTabIds.length > 0;
    if (active) {
      if (this.activeTabIds.indexOf(normalizedTabId) < 0) {
        this.activeTabIds.push(normalizedTabId);
      }
    } else {
      this.activeTabIds = this.activeTabIds.filter((id: string): boolean => id !== normalizedTabId);
    }
    const isActive = this.activeTabIds.length > 0;
    if (isActive === wasActive) {
      return;
    }
    this.generation += 1;
    const generation = this.generation;
    if (isActive) {
      sharedBrowserArkWebProcessLifecycleCoordinator.holdBackgroundTimers(TIMER_HOLD_REASON);
      this.enqueue((): Promise<void> => this.ensure(generation));
      return;
    }
    sharedBrowserArkWebProcessLifecycleCoordinator.releaseBackgroundTimerHold(TIMER_HOLD_REASON);
    this.enqueue((): Promise<void> => this.release());
  }

  clearTab(tabId: string): void {
    this.observe(tabId, false);
  }

  private enqueue(work: () => Promise<void>): void {
    this.pending = this.pending.then(work, work);
  }

  private isCurrent(generation: number): boolean {
    return generation === this.generation && this.activeTabIds.length > 0;
  }

  private async ensure(generation: number): Promise<void> {
    if (!this.isCurrent(generation)) {
      return;
    }
    await this.startContinuousTask();
    if (!this.isCurrent(generation)) {
      await this.stopContinuousTask();
      return;
    }
    if (this.continuousTaskId === undefined) {
      await this.delay(CONTINUOUS_TASK_RETRY_DELAY_MS);
      if (!this.isCurrent(generation)) {
        return;
      }
      await this.startContinuousTask();
    }
    await this.enableBorrowedBackgroundPlay(generation);
  }

  private async release(): Promise<void> {
    if (this.activeTabIds.length > 0) {
      return;
    }
    await this.restoreBorrowedBackgroundPlay();
    await this.stopContinuousTask();
  }

  private async startContinuousTask(): Promise<void> {
    if (this.continuousTaskId !== undefined) {
      return;
    }
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      hilog.warn(DOMAIN, TAG, 'audioPlayback skipped because UIAbilityContext is unavailable');
      return;
    }
    const context = AppRuntimeContext.getUIAbilityContext();
    try {
      const result = await backgroundTaskManager.startBackgroundRunning(
        context,
        ['audioPlayback'],
        await this.createOpenBrowserWantAgent(context)
      );
      this.continuousTaskContext = context;
      this.continuousTaskId = result.continuousTaskId;
      hilog.info(
        DOMAIN,
        TAG,
        'audioPlayback started notificationId=%{public}d taskId=%{public}d',
        result.notificationId,
        result.continuousTaskId ?? -1
      );
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'audioPlayback start failed code=%{public}d message=%{public}s',
        Number(businessError?.code ?? 0),
        businessError?.message ?? ''
      );
    }
  }

  private async stopContinuousTask(): Promise<void> {
    const context = this.continuousTaskContext;
    const taskId = this.continuousTaskId;
    this.continuousTaskContext = undefined;
    this.continuousTaskId = undefined;
    if (context === undefined || taskId === undefined || taskId < 0) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context, taskId);
      hilog.info(DOMAIN, TAG, 'audioPlayback stopped taskId=%{public}d', taskId);
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'audioPlayback stop failed code=%{public}d message=%{public}s',
        Number(businessError?.code ?? 0),
        businessError?.message ?? ''
      );
    }
  }

  private async enableBorrowedBackgroundPlay(generation: number): Promise<void> {
    if (deviceInfo.sdkApiVersion < BACKGROUND_PLAY_MODE_MIN_API || this.backgroundPlayEnabled) {
      return;
    }
    for (let attempt: number = 0; attempt < SESSION_RETRY_LIMIT; attempt += 1) {
      if (!this.isCurrent(generation)) {
        return;
      }
      const session = await this.readCurrentSession();
      if (session !== undefined && session.sessionType === 'video' &&
        await this.setBackgroundPlayMode(session, ENABLE_BACKGROUND_PLAY_MODE)) {
        this.borrowedVideoSession = session;
        this.backgroundPlayEnabled = true;
        hilog.info(DOMAIN, TAG, 'enabled background play on the web video session');
        return;
      }
      if (session !== undefined && session.sessionType !== 'video') {
        return;
      }
      await this.delay(SESSION_RETRY_DELAY_MS);
    }
  }

  private async restoreBorrowedBackgroundPlay(): Promise<void> {
    const session = this.borrowedVideoSession;
    const enabled = this.backgroundPlayEnabled;
    this.borrowedVideoSession = undefined;
    this.backgroundPlayEnabled = false;
    if (!enabled || session === undefined) {
      return;
    }
    await this.setBackgroundPlayMode(session, DISABLE_BACKGROUND_PLAY_MODE);
  }

  private async readCurrentSession(): Promise<avSession.AVSession | undefined> {
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      return undefined;
    }
    try {
      return await avSession.getAVSession(AppRuntimeContext.getUIAbilityContext());
    } catch (_error) {
      return undefined;
    }
  }

  private async setBackgroundPlayMode(session: avSession.AVSession, mode: number): Promise<boolean> {
    if (deviceInfo.sdkApiVersion < BACKGROUND_PLAY_MODE_MIN_API) {
      return false;
    }
    const candidate = session as object as BackgroundPlayModeSession;
    if (candidate.setBackgroundPlayMode === undefined) {
      return false;
    }
    try {
      await candidate.setBackgroundPlayMode(mode);
      return true;
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'setBackgroundPlayMode failed mode=%{public}d code=%{public}d message=%{public}s',
        mode,
        Number(businessError?.code ?? 0),
        businessError?.message ?? ''
      );
      return false;
    }
  }

  private async createOpenBrowserWantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    return wantAgent.getWantAgent({
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: OPEN_BROWSER_WANT_REQUEST_CODE,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }) as Promise<WantAgent>;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }
}

export const sharedWebVideoPictureInPictureBackgroundKeeper: WebVideoPictureInPictureBackgroundKeeper =
  new WebVideoPictureInPictureBackgroundKeeper();

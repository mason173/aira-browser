import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ArkWebProcessLifecycle';

export type BrowserArkWebTimerTransition =
  'unchanged' | 'paused' | 'resumed' | 'pause_failed' | 'resume_failed';

export class BrowserArkWebProcessLifecycleCoordinator {
  private timersPausedForBackground: boolean = false;

  pauseForProcessBackground(): BrowserArkWebTimerTransition {
    if (this.timersPausedForBackground) {
      return 'unchanged';
    }
    try {
      webview.WebviewController.pauseAllTimers();
      this.timersPausedForBackground = true;
      hilog.info(DOMAIN, TAG, 'Paused all ArkWeb JavaScript timers for process background');
      return 'paused';
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to pause ArkWeb timers: %{public}s', JSON.stringify(error));
      return 'pause_failed';
    }
  }

  resumeForProcessForeground(): BrowserArkWebTimerTransition {
    if (!this.timersPausedForBackground) {
      return 'unchanged';
    }
    try {
      webview.WebviewController.resumeAllTimers();
      this.timersPausedForBackground = false;
      hilog.info(DOMAIN, TAG, 'Resumed ArkWeb JavaScript timers for process foreground');
      return 'resumed';
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to resume ArkWeb timers: %{public}s', JSON.stringify(error));
      return 'resume_failed';
    }
  }
}

export const sharedBrowserArkWebProcessLifecycleCoordinator: BrowserArkWebProcessLifecycleCoordinator =
  new BrowserArkWebProcessLifecycleCoordinator();

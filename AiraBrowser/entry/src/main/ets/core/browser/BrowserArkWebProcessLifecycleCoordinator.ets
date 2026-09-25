import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ArkWebBackgroundTimerEvent,
  planArkWebBackgroundTimerCommand
} from './BrowserArkWebBackgroundTimerPolicy';

const DOMAIN: number = 0x0000;
const TAG: string = 'ArkWebProcessLifecycle';

export type BrowserArkWebTimerTransition =
  'unchanged' | 'paused' | 'resumed' | 'pause_failed' | 'resume_failed';

export class BrowserArkWebProcessLifecycleCoordinator {
  private processBackground: boolean = false;
  private backgroundTimerHolds: string[] = [];
  private timersPausedForBackground: boolean = false;

  pauseForProcessBackground(): BrowserArkWebTimerTransition {
    return this.apply('process_background');
  }

  resumeForProcessForeground(): BrowserArkWebTimerTransition {
    return this.apply('process_foreground');
  }

  holdBackgroundTimers(reason: string): BrowserArkWebTimerTransition {
    return this.apply('hold', reason);
  }

  releaseBackgroundTimerHold(reason: string): BrowserArkWebTimerTransition {
    return this.apply('release', reason);
  }

  private apply(event: ArkWebBackgroundTimerEvent, reason: string = ''): BrowserArkWebTimerTransition {
    const plan = planArkWebBackgroundTimerCommand(
      this.processBackground,
      this.backgroundTimerHolds,
      this.timersPausedForBackground,
      event,
      reason
    );
    this.processBackground = plan.processBackground;
    this.backgroundTimerHolds = plan.holds;
    if (event === 'process_background' && plan.holds.length > 0) {
      hilog.info(DOMAIN, TAG, 'Kept ArkWeb timers for background playback hold');
    }
    if (plan.command === 'pause') {
      return this.pauseTimers();
    }
    if (plan.command === 'resume') {
      return this.resumeTimers();
    }
    return 'unchanged';
  }

  private pauseTimers(): BrowserArkWebTimerTransition {
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

  private resumeTimers(): BrowserArkWebTimerTransition {
    try {
      webview.WebviewController.resumeAllTimers();
      this.timersPausedForBackground = false;
      hilog.info(DOMAIN, TAG, 'Resumed all ArkWeb JavaScript timers');
      return 'resumed';
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to resume ArkWeb timers: %{public}s', JSON.stringify(error));
      return 'resume_failed';
    }
  }
}

export const sharedBrowserArkWebProcessLifecycleCoordinator: BrowserArkWebProcessLifecycleCoordinator =
  new BrowserArkWebProcessLifecycleCoordinator();

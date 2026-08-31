import { ActivityTracker } from '../../services/activity/ActivityTracker';

const MAX_SINGLE_ACTIVE_SECONDS: number = 5 * 60;
const BACKGROUND_FLUSH_DELAY_MS: number = 10 * 1000;

export class ActivityForegroundSessionCoordinator {
  private tracker: ActivityTracker;
  private foreground: boolean = false;
  private foregroundStartedAt: number = 0;

  constructor(tracker: ActivityTracker) {
    this.tracker = tracker;
  }

  markForeground(now: number = Date.now()): void {
    if (this.foreground) {
      return;
    }
    this.foreground = true;
    this.foregroundStartedAt = now;
  }

  markBackground(now: number = Date.now()): void {
    if (!this.foreground) {
      return;
    }
    this.recordElapsed(now);
    this.foreground = false;
    this.foregroundStartedAt = 0;
    this.tracker.flushDeferred(BACKGROUND_FLUSH_DELAY_MS);
  }

  private recordElapsed(now: number): void {
    if (!this.foreground || this.foregroundStartedAt <= 0 || now <= this.foregroundStartedAt) {
      this.foregroundStartedAt = now;
      return;
    }
    const elapsedSeconds = Math.min(MAX_SINGLE_ACTIVE_SECONDS, Math.floor((now - this.foregroundStartedAt) / 1000));
    this.foregroundStartedAt = now;
    if (elapsedSeconds <= 0) {
      return;
    }
    this.tracker.recordActiveSeconds(elapsedSeconds, now);
  }
}

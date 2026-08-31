export type BrowserRuntimeMaintenanceTaskId =
  | 'adblock_remote_source_update'
  | 'membership_refresh'
  | 'download_restore';

export interface BrowserRuntimeMaintenanceTask {
  id: BrowserRuntimeMaintenanceTaskId;
  run: () => Promise<void>;
}

export interface BrowserRuntimeMaintenanceClock {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(timerId: number): void;
}

class DefaultBrowserRuntimeMaintenanceClock implements BrowserRuntimeMaintenanceClock {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs);
  }

  clearTimeout(timerId: number): void {
    clearTimeout(timerId);
  }
}

export class BrowserRuntimeMaintenanceCoordinator {
  private clock: BrowserRuntimeMaintenanceClock;
  private timerId: number = -1;
  private foreground: boolean = true;
  private running: boolean = false;
  private tasks: BrowserRuntimeMaintenanceTask[] = [];
  private nextIndex: number = 0;
  private initialDelayMs: number = 0;
  private taskGapMs: number = 0;

  constructor(clock?: BrowserRuntimeMaintenanceClock) {
    this.clock = clock ?? new DefaultBrowserRuntimeMaintenanceClock();
  }

  schedule(tasks: BrowserRuntimeMaintenanceTask[], initialDelayMs: number, taskGapMs: number): void {
    this.tasks = tasks;
    this.nextIndex = 0;
    this.initialDelayMs = Math.max(0, Math.floor(initialDelayMs));
    this.taskGapMs = Math.max(0, Math.floor(taskGapMs));
    this.cancelTimer();
    if (this.tasks.length <= 0 || !this.foreground) {
      return;
    }
    this.scheduleNext(this.initialDelayMs);
  }

  notifyForeground(): void {
    this.foreground = true;
    if (this.running || this.timerId >= 0 || this.nextIndex >= this.tasks.length) {
      return;
    }
    this.scheduleNext(this.initialDelayMs);
  }

  notifyBackground(): void {
    this.foreground = false;
    this.cancelTimer();
  }

  cancel(): void {
    this.cancelTimer();
    this.running = false;
    this.tasks = [];
    this.nextIndex = 0;
  }

  private scheduleNext(delayMs: number): void {
    if (!this.foreground || this.nextIndex >= this.tasks.length) {
      return;
    }
    this.cancelTimer();
    this.timerId = this.clock.setTimeout(() => {
      this.timerId = -1;
      void this.runNext();
    }, delayMs);
  }

  private async runNext(): Promise<void> {
    if (!this.foreground || this.running || this.nextIndex >= this.tasks.length) {
      return;
    }
    const task = this.tasks[this.nextIndex];
    this.nextIndex += 1;
    this.running = true;
    try {
      await task.run();
    } finally {
      this.running = false;
      this.scheduleNext(this.taskGapMs);
    }
  }

  private cancelTimer(): void {
    if (this.timerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.timerId);
    this.timerId = -1;
  }
}

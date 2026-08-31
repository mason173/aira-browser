import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserTabDiscardIneligibilityReason,
  BrowserTabDiscardTask
} from './BrowserTabBackgroundTypes';

export interface BrowserTabBackgroundQueueClock {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(timerId: number): void;
}

class DefaultBrowserTabBackgroundQueueClock implements BrowserTabBackgroundQueueClock {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs);
  }

  clearTimeout(timerId: number): void {
    clearTimeout(timerId);
  }
}

export interface BrowserTabBackgroundDiscardQueueSyncRequest {
  tasks: BrowserTabDiscardTask[];
  tabs: BrowserTabState[];
  activeTabId: string;
  protectedReasonsByTabId: Record<string, string>;
  executableTabIds?: string[];
  resolveTab?: (tabId: string) => BrowserTabState | undefined;
  executeDiscardTask: (task: BrowserTabDiscardTask) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  intervalMs?: number;
  maxPendingTasks?: number;
}

interface BrowserTabBackgroundDiscardQueueContext {
  tabIds: string[];
  activeTabId: string;
  protectedReasonsByTabId: Record<string, string>;
  resolveTab?: (tabId: string) => BrowserTabState | undefined;
  executeDiscardTask: (task: BrowserTabDiscardTask) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  intervalMs: number;
}

const DEFAULT_DISCARD_QUEUE_INTERVAL_MS = 1000;
const DEFAULT_DISCARD_QUEUE_MAX_PENDING_TASKS = 4;

type BrowserTabBackgroundQueueUpsertResult =
  'inserted' |
  'updated' |
  'unchanged';

export class BrowserTabBackgroundQueueCoordinator {
  private clock: BrowserTabBackgroundQueueClock;
  private pendingTasks: BrowserTabDiscardTask[] = [];
  private running: boolean = false;
  private timerId: number = -1;
  private context?: BrowserTabBackgroundDiscardQueueContext;
  private completedReasonByTabId: Record<string, string> = {};

  constructor(clock?: BrowserTabBackgroundQueueClock) {
    this.clock = clock ?? new DefaultBrowserTabBackgroundQueueClock();
  }

  syncDiscardQueue(request: BrowserTabBackgroundDiscardQueueSyncRequest): void {
    const tabIds = request.tabs.map((tab: BrowserTabState): string => tab.id);
    const intervalMs = Math.max(0, Math.floor(request.intervalMs ?? DEFAULT_DISCARD_QUEUE_INTERVAL_MS));
    const maxPendingTasks = Math.max(1, Math.floor(request.maxPendingTasks ?? DEFAULT_DISCARD_QUEUE_MAX_PENDING_TASKS));
    this.context = {
      tabIds: tabIds,
      activeTabId: request.activeTabId,
      protectedReasonsByTabId: request.protectedReasonsByTabId,
      resolveTab: request.resolveTab,
      executeDiscardTask: request.executeDiscardTask,
      recordRuntimeEvent: request.recordRuntimeEvent,
      intervalMs: intervalMs
    };

    const latestTaskByTabId: Record<string, BrowserTabDiscardTask> = {};
    request.tasks.forEach((task: BrowserTabDiscardTask) => {
      latestTaskByTabId[task.tabId] = task;
    });
    this.pruneCompletedReasons(latestTaskByTabId, tabIds);
    this.prunePendingTasks(latestTaskByTabId, request.recordRuntimeEvent);
    this.enqueueLatestExecutableTasks(request, latestTaskByTabId, maxPendingTasks);
    this.sortPendingTasks();
    this.scheduleNext(intervalMs);
  }

  cancelForTab(
    tabId: string,
    reason: string,
    recordRuntimeEvent?: (type: string, message: string, tabId: string) => void
  ): void {
    if (tabId.length === 0) {
      return;
    }
    const previousLength = this.pendingTasks.length;
    this.pendingTasks = this.pendingTasks.filter((task: BrowserTabDiscardTask): boolean => task.tabId !== tabId);
    this.completedReasonByTabId = this.removeCompletedReason(tabId);
    if (previousLength === this.pendingTasks.length) {
      return;
    }
    const eventRecorder = recordRuntimeEvent ?? this.context?.recordRuntimeEvent;
    if (eventRecorder !== undefined) {
      eventRecorder('tab_background_discard_cancelled', `reason=${reason}`, tabId);
    }
    if (this.pendingTasks.length <= 0) {
      this.cancelTimer();
    }
  }

  cancelAll(
    reason: string,
    recordRuntimeEvent?: (type: string, message: string, tabId: string) => void
  ): void {
    if (this.pendingTasks.length <= 0) {
      this.cancelTimer();
      return;
    }
    const eventRecorder = recordRuntimeEvent ?? this.context?.recordRuntimeEvent;
    this.pendingTasks.forEach((task: BrowserTabDiscardTask) => {
      if (eventRecorder !== undefined) {
        eventRecorder('tab_background_discard_cancelled', `reason=${reason}`, task.tabId);
      }
    });
    this.pendingTasks = [];
    this.cancelTimer();
  }

  getPendingTaskIds(): string[] {
    return this.pendingTasks.map((task: BrowserTabDiscardTask): string => task.tabId);
  }

  private enqueueLatestExecutableTasks(
    request: BrowserTabBackgroundDiscardQueueSyncRequest,
    latestTaskByTabId: Record<string, BrowserTabDiscardTask>,
    maxPendingTasks: number
  ): void {
    const executableTabIds = request.executableTabIds;
    request.tasks.forEach((task: BrowserTabDiscardTask) => {
      const tabId = task.tabId;
      if (latestTaskByTabId[tabId] !== task) {
        return;
      }
      if (!this.isTaskStillEligible(task, this.context)) {
        return;
      }
      if (executableTabIds !== undefined && !executableTabIds.includes(tabId) && !this.hasPendingTask(tabId)) {
        return;
      }
      if ((this.completedReasonByTabId[tabId] ?? '') === task.reason && !this.hasPendingTask(tabId)) {
        return;
      }
      if (!this.hasPendingTask(tabId) && this.pendingTasks.length >= maxPendingTasks) {
        const reason: BrowserTabDiscardIneligibilityReason = 'batch_limit';
        request.recordRuntimeEvent(
          'tab_background_discard_skipped',
          `reason=${reason} limit=${maxPendingTasks} pending=${this.pendingTasks.length}`,
          tabId
        );
        return;
      }
      const upsertResult = this.upsertPendingTask(task);
      if (upsertResult === 'unchanged') {
        return;
      }
      request.recordRuntimeEvent(
        'tab_background_discard_queued',
        `reason=${task.reason} priority=${task.priority} action=${upsertResult}`,
        tabId
      );
    });
  }

  private pruneCompletedReasons(latestTaskByTabId: Record<string, BrowserTabDiscardTask>, tabIds: string[]): void {
    const nextCompleted: Record<string, string> = {};
    Object.keys(this.completedReasonByTabId).forEach((tabId: string) => {
      const latestTask = latestTaskByTabId[tabId];
      if (latestTask === undefined || !tabIds.includes(tabId)) {
        return;
      }
      nextCompleted[tabId] = this.completedReasonByTabId[tabId];
    });
    this.completedReasonByTabId = nextCompleted;
  }

  private prunePendingTasks(
    latestTaskByTabId: Record<string, BrowserTabDiscardTask>,
    recordRuntimeEvent: (type: string, message: string, tabId: string) => void
  ): void {
    const retainedTasks: BrowserTabDiscardTask[] = [];
    this.pendingTasks.forEach((task: BrowserTabDiscardTask) => {
      const latestTask = latestTaskByTabId[task.tabId];
      if (latestTask === undefined) {
        const reason: BrowserTabDiscardIneligibilityReason = 'no_longer_candidate';
        recordRuntimeEvent('tab_background_discard_cancelled', `reason=${reason}`, task.tabId);
        return;
      }
      const ineligibilityReason = this.resolveTaskIneligibilityReason(latestTask, this.context);
      if (ineligibilityReason.length > 0) {
        recordRuntimeEvent('tab_background_discard_cancelled', `reason=${ineligibilityReason}`, task.tabId);
        return;
      }
      retainedTasks.push({
        tabId: latestTask.tabId,
        reason: latestTask.reason,
        priority: latestTask.priority,
        queuedAt: task.queuedAt
      });
    });
    this.pendingTasks = retainedTasks;
  }

  private scheduleNext(delayMs: number): void {
    if (this.running || this.timerId >= 0 || this.pendingTasks.length <= 0 || this.context === undefined) {
      return;
    }
    this.timerId = this.clock.setTimeout(() => {
      this.timerId = -1;
      this.runNextTask();
    }, delayMs);
  }

  private runNextTask(): void {
    if (this.running || this.context === undefined || this.pendingTasks.length <= 0) {
      return;
    }
    const task = this.pendingTasks.shift();
    if (task === undefined) {
      return;
    }
    this.running = true;
    try {
      const ineligibilityReason = this.resolveTaskIneligibilityReason(task, this.context);
      if (ineligibilityReason.length > 0) {
        this.context.recordRuntimeEvent('tab_background_discard_skipped', `reason=${ineligibilityReason}`, task.tabId);
        return;
      }
      this.completedReasonByTabId[task.tabId] = task.reason;
      this.context.recordRuntimeEvent(
        'tab_background_discard_execute',
        `reason=${task.reason} priority=${task.priority}`,
        task.tabId
      );
      this.context.executeDiscardTask(task);
    } finally {
      this.running = false;
      const nextIntervalMs = this.context?.intervalMs ?? DEFAULT_DISCARD_QUEUE_INTERVAL_MS;
      this.scheduleNext(nextIntervalMs);
    }
  }

  private isTaskStillEligible(
    task: BrowserTabDiscardTask,
    context: BrowserTabBackgroundDiscardQueueContext | undefined
  ): boolean {
    return this.resolveTaskIneligibilityReason(task, context).length <= 0;
  }

  private resolveTaskIneligibilityReason(
    task: BrowserTabDiscardTask,
    context: BrowserTabBackgroundDiscardQueueContext | undefined
  ): BrowserTabDiscardIneligibilityReason | '' {
    if (context === undefined) {
      return 'missing_context';
    }
    if (!context.tabIds.includes(task.tabId)) {
      return 'tab_missing';
    }
    if (task.tabId === context.activeTabId) {
      return 'active_tab';
    }
    const currentTab = context.resolveTab?.(task.tabId);
    if (context.resolveTab !== undefined && currentTab === undefined) {
      return 'tab_missing';
    }
    if (currentTab !== undefined && task.queuedAt > 0 && currentTab.lastActiveAt > task.queuedAt) {
      return 'recent_activity_after_queue';
    }
    if (currentTab !== undefined && currentTab.runtimeState === 'active') {
      return 'active_state';
    }
    if ((context.protectedReasonsByTabId[task.tabId] ?? '').length > 0) {
      return 'protected';
    }
    return '';
  }

  private upsertPendingTask(task: BrowserTabDiscardTask): BrowserTabBackgroundQueueUpsertResult {
    for (let index = 0; index < this.pendingTasks.length; index += 1) {
      const candidate = this.pendingTasks[index];
      if (candidate.tabId !== task.tabId) {
        continue;
      }
      if (candidate.reason === task.reason && candidate.priority === task.priority) {
        return 'unchanged';
      }
      this.pendingTasks[index] = {
        tabId: task.tabId,
        reason: task.reason,
        priority: task.priority,
        queuedAt: candidate.queuedAt
      };
      return 'updated';
    }
    this.pendingTasks.push(task);
    return 'inserted';
  }

  private hasPendingTask(tabId: string): boolean {
    return this.pendingTasks.some((task: BrowserTabDiscardTask): boolean => task.tabId === tabId);
  }

  private sortPendingTasks(): void {
    this.pendingTasks = this.pendingTasks.sort((left: BrowserTabDiscardTask, right: BrowserTabDiscardTask): number => {
      if (left.priority !== right.priority) {
        return left.priority - right.priority;
      }
      if (left.queuedAt !== right.queuedAt) {
        return left.queuedAt - right.queuedAt;
      }
      return left.tabId.localeCompare(right.tabId);
    });
  }

  private removeCompletedReason(tabId: string): Record<string, string> {
    const nextReasons: Record<string, string> = {};
    Object.keys(this.completedReasonByTabId).forEach((key: string) => {
      if (key !== tabId) {
        nextReasons[key] = this.completedReasonByTabId[key];
      }
    });
    return nextReasons;
  }

  private cancelTimer(): void {
    if (this.timerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.timerId);
    this.timerId = -1;
  }
}

import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { DownloadNetworkStartAdmission } from './DownloadNetworkPolicyService';

export type DownloadQueueAdmissionReason =
  'start_now' |
  'concurrency_limit' |
  'waiting_wifi' |
  'offline_network' |
  'network_unknown' |
  'not_startable';

export interface DownloadQueuePolicyConfig {
  maxConcurrentDownloads?: number;
}

export interface DownloadQueueAdmission {
  canStartNow: boolean;
  reason: DownloadQueueAdmissionReason;
  runningCount: number;
  queuedCount: number;
  maxConcurrentDownloads: number;
  networkMessage?: string;
}

export interface DownloadQueueSchedulePlan extends DownloadQueueAdmission {
  nextGuid?: string;
}

const DEFAULT_MAX_CONCURRENT_DOWNLOADS = 3;

export class DownloadQueuePolicyService {
  private maxConcurrentDownloads: number;

  constructor(config?: DownloadQueuePolicyConfig) {
    this.maxConcurrentDownloads = this.normalizeMaxConcurrentDownloads(config?.maxConcurrentDownloads);
  }

  resolveStartAdmission(
    tasks: DownloadV2TaskEntity[],
    candidateGuid: string,
    networkAdmission?: DownloadNetworkStartAdmission
  ): DownloadQueueAdmission {
    const runningCount = this.countRunningTasks(tasks);
    const queuedCount = this.countStartableQueuedTasks(tasks);
    const candidate = tasks.find((task: DownloadV2TaskEntity) => task.guid === candidateGuid);
    if (candidate === undefined || !this.isStartableQueuedTask(candidate)) {
      return {
        canStartNow: false,
        reason: 'not_startable',
        runningCount: runningCount,
        queuedCount: queuedCount,
        maxConcurrentDownloads: this.maxConcurrentDownloads
      };
    }
    if (runningCount >= this.maxConcurrentDownloads) {
      return {
        canStartNow: false,
        reason: 'concurrency_limit',
        runningCount: runningCount,
        queuedCount: queuedCount,
        maxConcurrentDownloads: this.maxConcurrentDownloads
      };
    }
    if (networkAdmission !== undefined && !networkAdmission.canStartNow) {
      return {
        canStartNow: false,
        reason: networkAdmission.reason,
        runningCount: runningCount,
        queuedCount: queuedCount,
        maxConcurrentDownloads: this.maxConcurrentDownloads,
        networkMessage: networkAdmission.message
      };
    }
    return {
      canStartNow: true,
      reason: 'start_now',
      runningCount: runningCount,
      queuedCount: queuedCount,
      maxConcurrentDownloads: this.maxConcurrentDownloads
    };
  }

  buildSchedulePlan(
    tasks: DownloadV2TaskEntity[],
    networkAdmission?: DownloadNetworkStartAdmission
  ): DownloadQueueSchedulePlan {
    const runningCount = this.countRunningTasks(tasks);
    const queuedTasks = this.listStartableQueuedTasks(tasks);
    if (queuedTasks.length <= 0) {
      return {
        canStartNow: false,
        reason: 'not_startable',
        runningCount: runningCount,
        queuedCount: 0,
        maxConcurrentDownloads: this.maxConcurrentDownloads
      };
    }
    if (runningCount >= this.maxConcurrentDownloads) {
      return {
        canStartNow: false,
        reason: 'concurrency_limit',
        runningCount: runningCount,
        queuedCount: queuedTasks.length,
        maxConcurrentDownloads: this.maxConcurrentDownloads
      };
    }
    if (networkAdmission !== undefined && !networkAdmission.canStartNow) {
      return {
        canStartNow: false,
        reason: networkAdmission.reason,
        runningCount: runningCount,
        queuedCount: queuedTasks.length,
        maxConcurrentDownloads: this.maxConcurrentDownloads,
        networkMessage: networkAdmission.message
      };
    }
    return {
      canStartNow: true,
      reason: 'start_now',
      runningCount: runningCount,
      queuedCount: queuedTasks.length,
      maxConcurrentDownloads: this.maxConcurrentDownloads,
      nextGuid: queuedTasks[0].guid
    };
  }

  private listStartableQueuedTasks(tasks: DownloadV2TaskEntity[]): DownloadV2TaskEntity[] {
    return tasks
      .filter((task: DownloadV2TaskEntity) => this.isStartableQueuedTask(task))
      .sort((left: DownloadV2TaskEntity, right: DownloadV2TaskEntity) => {
        const leftTime = left.timing.confirmedAt ?? left.timing.createdAt;
        const rightTime = right.timing.confirmedAt ?? right.timing.createdAt;
        if (leftTime !== rightTime) {
          return leftTime - rightTime;
        }
        return left.guid.localeCompare(right.guid);
      });
  }

  private isStartableQueuedTask(task: DownloadV2TaskEntity): boolean {
    return task.status === 'queued' &&
      (task.persistence.tempFilePath?.trim().length ?? 0) > 0 &&
      task.persistence.downloadDriver !== undefined;
  }

  private countRunningTasks(tasks: DownloadV2TaskEntity[]): number {
    return tasks.filter((task: DownloadV2TaskEntity) => task.status === 'running').length;
  }

  private countStartableQueuedTasks(tasks: DownloadV2TaskEntity[]): number {
    return this.listStartableQueuedTasks(tasks).length;
  }

  private normalizeMaxConcurrentDownloads(value?: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return DEFAULT_MAX_CONCURRENT_DOWNLOADS;
    }
    const rounded = Math.floor(value);
    if (rounded < 1) {
      return 1;
    }
    if (rounded > 8) {
      return 8;
    }
    return rounded;
  }
}

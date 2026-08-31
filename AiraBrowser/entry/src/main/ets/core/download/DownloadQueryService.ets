import {
  DownloadQueryGroup,
  DownloadTaskBoundary,
  getDownloadV2QueryGroup,
  matchesDownloadTaskBoundary
} from '../../domain/download/DownloadTypes';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';

export interface DownloadQueryInput {
  tasks: DownloadV2TaskEntity[];
  boundary?: DownloadTaskBoundary;
  group?: DownloadQueryGroup;
  limit?: number;
}

export interface DownloadStatusCounts {
  active: number;
  completed: number;
  failed: number;
  pending: number;
  paused: number;
  canceled: number;
  removed: number;
  other: number;
}

export class DownloadQueryService {
  listTasks(input: DownloadQueryInput): DownloadV2TaskEntity[] {
    const tasks = this.filterByBoundary(input.tasks, input.boundary);
    const groupedTasks = this.filterByGroup(tasks, input.group ?? 'all');
    const sortedTasks = this.sortByRecency(groupedTasks);
    if (input.limit === undefined || input.limit <= 0) {
      return sortedTasks;
    }
    return sortedTasks.slice(0, input.limit);
  }

  listRecentTasks(input: DownloadQueryInput): DownloadV2TaskEntity[] {
    const tasks = this.filterByBoundary(input.tasks, input.boundary);
    const groupedTasks = this.filterByGroup(tasks, input.group ?? 'all');
    const sortedTasks = this.sortByStableDisplayOrder(groupedTasks);
    if (input.limit === undefined || input.limit <= 0) {
      return sortedTasks;
    }
    return sortedTasks.slice(0, input.limit);
  }

  countByStatus(tasks: DownloadV2TaskEntity[], boundary?: DownloadTaskBoundary): DownloadStatusCounts {
    const filteredTasks = this.filterByBoundary(tasks, boundary);
    const counts: DownloadStatusCounts = {
      active: 0,
      completed: 0,
      failed: 0,
      pending: 0,
      paused: 0,
      canceled: 0,
      removed: 0,
      other: 0
    };
    filteredTasks.forEach((task: DownloadV2TaskEntity) => {
      const group = getDownloadV2QueryGroup(task.status);
      if (group === 'in_progress') {
        counts.active += 1;
        return;
      }
      if (group === 'completed') {
        counts.completed += 1;
        return;
      }
      if (group === 'failed') {
        counts.failed += 1;
        return;
      }
      if (group === 'pending') {
        counts.pending += 1;
        return;
      }
      if (group === 'paused') {
        counts.paused += 1;
        return;
      }
      if (group === 'canceled') {
        counts.canceled += 1;
        return;
      }
      if (group === 'removed') {
        counts.removed += 1;
        return;
      }
      counts.other += 1;
    });
    return counts;
  }

  private filterByBoundary(tasks: DownloadV2TaskEntity[], boundary?: DownloadTaskBoundary): DownloadV2TaskEntity[] {
    if (boundary === undefined) {
      return tasks.filter((task: DownloadV2TaskEntity) => task.dataScope === 'profile_persistent');
    }
    return tasks.filter((task: DownloadV2TaskEntity) => {
      return matchesDownloadTaskBoundary(
        {
          windowId: task.windowId,
          profileId: task.profileId,
          privacyMode: task.privacyMode,
          dataScope: task.dataScope
        },
        {
          windowId: boundary.windowId,
          profileId: boundary.profileId,
          privacyMode: boundary.privacyMode,
          dataScope: boundary.dataScope
        }
      );
    });
  }

  private filterByGroup(tasks: DownloadV2TaskEntity[], group: DownloadQueryGroup): DownloadV2TaskEntity[] {
    if (group === 'all') {
      return tasks.slice();
    }
    return tasks.filter((task: DownloadV2TaskEntity) => getDownloadV2QueryGroup(task.status) === group);
  }

  private sortByRecency(tasks: DownloadV2TaskEntity[]): DownloadV2TaskEntity[] {
    return tasks.slice().sort((left: DownloadV2TaskEntity, right: DownloadV2TaskEntity) => {
      const rightTimestamp = this.resolveSortTimestamp(right);
      const leftTimestamp = this.resolveSortTimestamp(left);
      if (rightTimestamp !== leftTimestamp) {
        return rightTimestamp - leftTimestamp;
      }
      return right.timing.createdAt - left.timing.createdAt;
    });
  }

  private sortByStableDisplayOrder(tasks: DownloadV2TaskEntity[]): DownloadV2TaskEntity[] {
    return tasks.slice().sort((left: DownloadV2TaskEntity, right: DownloadV2TaskEntity) => {
      if (right.timing.createdAt !== left.timing.createdAt) {
        return right.timing.createdAt - left.timing.createdAt;
      }
      if (right.id !== left.id) {
        return right.id.localeCompare(left.id);
      }
      return right.guid.localeCompare(left.guid);
    });
  }

  private resolveSortTimestamp(task: DownloadV2TaskEntity): number {
    return task.timing.updatedAt > 0 ? task.timing.updatedAt : task.timing.createdAt;
  }
}

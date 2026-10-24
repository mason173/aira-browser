import { DownloadTaskBoundary } from '../../domain/download/DownloadTypes';
import { DownloadRuntimeService } from '../../services/download/DownloadRuntimeService';
import { DownloadBatchAction, resolveDownloadBatchTaskAction } from './DownloadSelectionViewModel';

export interface DownloadBatchActionResult {
  succeededGuids: string[];
  failedGuids: string[];
  skippedGuids: string[];
}

export class DownloadBatchActionCoordinator {
  private readonly runtime: DownloadRuntimeService;

  constructor(runtime: DownloadRuntimeService) {
    this.runtime = runtime;
  }

  async execute(
    action: DownloadBatchAction,
    selectedGuids: string[],
    boundary: DownloadTaskBoundary
  ): Promise<DownloadBatchActionResult> {
    const result: DownloadBatchActionResult = { succeededGuids: [], failedGuids: [], skippedGuids: [] };
    const guids = Array.from(new Set<string>(selectedGuids));
    for (let index = 0; index < guids.length; index += 1) {
      const guid = guids[index];
      try {
        // A previous command may have drained the queue or a transfer may have finished.
        // Read again before every command, keeping the original window/privacy boundary.
        const task = this.runtime.listTasksSnapshot(boundary).find((candidate) => candidate.guid === guid);
        const taskAction = task === undefined ? undefined : resolveDownloadBatchTaskAction(
          action, task.status, this.runtime.listAllowedActionsForTask(task)
        );
        if (taskAction === undefined) {
          result.skippedGuids.push(guid);
          continue;
        }
        let succeeded = false;
        if (taskAction === 'pause') {
          succeeded = await this.runtime.pauseTaskForBoundary(guid, boundary);
        } else if (taskAction === 'resume') {
          succeeded = await this.runtime.resumeTaskForBoundary(guid, boundary);
        } else if (taskAction === 'retry') {
          succeeded = await this.runtime.retryTaskForBoundary(guid, boundary);
        } else if (taskAction === 'cancel') {
          succeeded = await this.runtime.cancelAndRemoveTaskForBoundary(guid, boundary);
        }
        if (succeeded) {
          result.succeededGuids.push(guid);
        } else {
          result.failedGuids.push(guid);
        }
      } catch (_error) {
        result.failedGuids.push(guid);
      }
    }
    return result;
  }
}

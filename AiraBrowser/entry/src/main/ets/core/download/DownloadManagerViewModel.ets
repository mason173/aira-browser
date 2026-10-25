import {
  resolveDownloadProgressPercent,
  resolveDownloadDisplayTotal,
  isDownloadTotalEstimated
} from '../../domain/downloadv2/DownloadV2Progress';
import { resolveAppResourceText } from '../resources/AppResourceText';
import { DownloadStatusCounts } from './DownloadQueryService';
import { canSelectDownloadTask } from './DownloadSelectionViewModel';
import { DownloadRuntimeService } from '../../services/download/DownloadRuntimeService';
import {
  DownloadQueryGroup,
  DownloadTaskBoundary,
  getDownloadV2QueryGroup
} from '../../domain/download/DownloadTypes';
import {
  canContinueDownloadV2Task,
  DownloadV2TaskEntity
} from '../../domain/downloadv2/DownloadV2TaskEntity';
import {
  DownloadV2ManagementAction,
  DownloadV2Status
} from '../../domain/downloadv2/DownloadV2Types';
import {
  DownloadFileType,
  resolveDownloadFileType
} from './DownloadFileTypeResolver';

export interface DownloadManagementListState {
  groups: DownloadManagementGroupState[];
}

export interface DownloadManagementGroupSelection {
  group: DownloadQueryGroup;
  initialContentResolved: boolean;
}

export interface DownloadManagementFilterChipView {
  group: DownloadQueryGroup;
  label: string;
  count: number;
}

export interface DownloadManagementGroupState extends DownloadManagementFilterChipView {
  rows: DownloadManagementRowState[];
}

export type DownloadManagementRowAction = DownloadV2ManagementAction | 'copy_link' | 'delete_task_and_file' |
  'enter_selection';

export const DOWNLOAD_ROW_ENTER_SELECTION_ACTION: DownloadManagementRowAction = 'enter_selection';
export const DOWNLOAD_ROW_ENTER_SELECTION_LABEL: string = resolveAppResourceText($r('app.string.ui_multi_select'));

export interface DownloadManagementRowMenuActionView {
  action: DownloadManagementRowAction;
  label: string;
}

interface DownloadV2TaskPresentation {
  fileName: string;
  statusText: string;
  progressValue: number;
  progressText: string;
  isWarning: boolean;
  allowedActions: DownloadV2ManagementAction[];
}

export interface DownloadManagementRowView {
  guid: string;
  status: DownloadV2Status;
  fileType: DownloadFileType;
  fileName: string;
  sourceText: string;
  statusText: string;
  detailText: string;
  trailingText: string;
  completionTimeText: string;
  completionSizeText: string;
  showProgress: boolean;
  progressValue: number;
  primaryAction?: DownloadV2ManagementAction;
  primaryActionLabel: string;
  primaryActionEmphasis: 'primary' | 'secondary';
  menuActions: DownloadManagementRowMenuActionView[];
}

@Observed
export class DownloadManagementRowState {
  guid: string;
  status: DownloadV2Status;
  fileType: DownloadFileType;
  fileName: string;
  sourceText: string;
  statusText: string;
  detailText: string;
  trailingText: string;
  completionTimeText: string;
  completionSizeText: string;
  showProgress: boolean;
  progressValue: number;
  primaryAction?: DownloadV2ManagementAction;
  primaryActionLabel: string;
  primaryActionEmphasis: 'primary' | 'secondary';
  menuActions: DownloadManagementRowMenuActionView[];

  constructor(view: DownloadManagementRowView) {
    this.guid = view.guid;
    this.status = view.status;
    this.fileType = view.fileType;
    this.fileName = view.fileName;
    this.sourceText = view.sourceText;
    this.statusText = view.statusText;
    this.detailText = view.detailText;
    this.trailingText = view.trailingText;
    this.completionTimeText = view.completionTimeText;
    this.completionSizeText = view.completionSizeText;
    this.showProgress = view.showProgress;
    this.progressValue = view.progressValue;
    this.primaryAction = view.primaryAction;
    this.primaryActionLabel = view.primaryActionLabel;
    this.primaryActionEmphasis = view.primaryActionEmphasis;
    this.menuActions = this.cloneMenuActions(view.menuActions);
  }

  syncFromRow(row: DownloadManagementRowState): void {
    this.status = row.status;
    this.fileType = row.fileType;
    this.fileName = row.fileName;
    this.sourceText = row.sourceText;
    this.statusText = row.statusText;
    this.detailText = row.detailText;
    this.trailingText = row.trailingText;
    this.completionTimeText = row.completionTimeText;
    this.completionSizeText = row.completionSizeText;
    this.showProgress = row.showProgress;
    this.progressValue = row.progressValue;
    this.primaryAction = row.primaryAction;
    this.primaryActionLabel = row.primaryActionLabel;
    this.primaryActionEmphasis = row.primaryActionEmphasis;
    this.menuActions = this.cloneMenuActions(row.menuActions);
  }

  private cloneMenuActions(actions: DownloadManagementRowMenuActionView[]): DownloadManagementRowMenuActionView[] {
    const nextActions: DownloadManagementRowMenuActionView[] = [];
    actions.forEach((action: DownloadManagementRowMenuActionView) => {
      const nextAction: DownloadManagementRowMenuActionView = {
        action: action.action,
        label: action.label
      };
      nextActions.push(nextAction);
    });
    return nextActions;
  }
}

const EMPTY_MANAGEMENT_LIST_STATE: DownloadManagementListState = {
  groups: []
};

export function createEmptyDownloadManagementListState(): DownloadManagementListState {
  return {
    groups: []
  };
}

export class DownloadManagerViewModel {
  buildManagementListStateSnapshot(
    downloadService: DownloadRuntimeService,
    boundary: DownloadTaskBoundary
  ): DownloadManagementListState {
    const tasks = downloadService.listStableTasksSnapshot(boundary);
    const counts = downloadService.getStatusCountsSnapshot(boundary);
    return this.buildManagementListStateFromTasks(downloadService, tasks, counts);
  }

  resolveManagementGroupSelection(
    state: DownloadManagementListState,
    currentGroup: DownloadQueryGroup,
    initialContentResolved: boolean
  ): DownloadManagementGroupSelection {
    const current = state.groups.find((group: DownloadManagementGroupState) => group.group === currentGroup);
    const hasContent = state.groups.some((group: DownloadManagementGroupState) => group.rows.length > 0);
    if (!initialContentResolved && hasContent) {
      if (current !== undefined && current.rows.length > 0) {
        return {
          group: currentGroup,
          initialContentResolved: true
        };
      }
      const preferredOrder: DownloadQueryGroup[] = ['in_progress', 'completed'];
      for (let index = 0; index < preferredOrder.length; index += 1) {
        const preferredGroup = state.groups.find((group: DownloadManagementGroupState) => {
          return group.group === preferredOrder[index] && group.rows.length > 0;
        });
        if (preferredGroup !== undefined) {
          return {
            group: preferredGroup.group,
            initialContentResolved: true
          };
        }
      }
    }
    if (current !== undefined) {
      return {
        group: currentGroup,
        initialContentResolved: initialContentResolved
      };
    }
    const fallbackGroup = state.groups[0]?.group ?? 'in_progress';
    return {
      group: fallbackGroup,
      initialContentResolved: initialContentResolved || hasContent
    };
  }

  shouldRetainOptimisticStatus(targetStatus: DownloadV2Status, sourceStatus: DownloadV2Status): boolean {
    if (targetStatus === 'paused') {
      return sourceStatus === 'created' || sourceStatus === 'awaiting_confirmation' ||
        sourceStatus === 'queued' || sourceStatus === 'running';
    }
    if (targetStatus === 'running') {
      return sourceStatus === 'paused' || sourceStatus === 'created' ||
        sourceStatus === 'awaiting_confirmation' || sourceStatus === 'queued';
    }
    return false;
  }

  applyOptimisticStatus(row: DownloadManagementRowState, targetStatus: DownloadV2Status): boolean {
    if (targetStatus === 'paused') {
      row.status = 'paused';
      row.statusText = resolveAppResourceText($r('app.string.download_status_paused'));
      row.trailingText = resolveAppResourceText($r('app.string.settings_sync_paused'));
      row.primaryAction = 'resume';
      row.primaryActionLabel = resolveAppResourceText($r('app.string.settings_pro_continue'));
      row.primaryActionEmphasis = 'primary';
      row.menuActions = this.buildOptimisticMenuActions('paused');
      return true;
    }
    if (targetStatus === 'running') {
      row.status = 'running';
      row.statusText = '';
      if (row.trailingText === resolveAppResourceText($r('app.string.settings_sync_paused'))) {
        row.trailingText = '--';
      }
      row.primaryAction = 'pause';
      row.primaryActionLabel = resolveAppResourceText($r('app.string.browser_ui_browser_video_assistant_player_overlay_013'));
      row.primaryActionEmphasis = 'secondary';
      row.menuActions = this.buildOptimisticMenuActions('running');
      return true;
    }
    return false;
  }

  private buildManagementListStateFromTasks(
    downloadService: DownloadRuntimeService,
    tasks: DownloadV2TaskEntity[],
    counts: DownloadStatusCounts
  ): DownloadManagementListState {
    const availableGroups = this.buildAvailableGroups(counts);
    return {
      groups: availableGroups.map((group: DownloadManagementFilterChipView): DownloadManagementGroupState => {
        const filteredTasks = this.filterTasksByGroup(tasks, group.group);
        return {
          group: group.group,
          label: group.label,
          count: group.count,
          rows: filteredTasks.map((task: DownloadV2TaskEntity) => this.buildManagementRowState(downloadService, task))
        };
      })
    };
  }

  private buildAvailableGroups(counts: DownloadStatusCounts): DownloadManagementFilterChipView[] {
    // Keep failed tasks visible in the main management flow so launch reconciliation
    // does not make paused/recoverable tasks appear to "disappear" after restart.
    const activeCount = counts.active + counts.pending + counts.paused + counts.failed;
    const groups: DownloadManagementFilterChipView[] = [
      { group: 'in_progress', label: resolveAppResourceText($r('app.string.download_status_downloading')), count: activeCount },
      { group: 'completed', label: resolveAppResourceText($r('app.string.download_status_completed')), count: counts.completed }
    ];
    return groups;
  }

  private filterTasksByGroup(tasks: DownloadV2TaskEntity[], selectedGroup: DownloadQueryGroup): DownloadV2TaskEntity[] {
    if (selectedGroup === 'in_progress') {
      return tasks.filter((task: DownloadV2TaskEntity) => this.isActiveGroup(getDownloadV2QueryGroup(task.status)));
    }
    return tasks.filter((task: DownloadV2TaskEntity) => getDownloadV2QueryGroup(task.status) === selectedGroup);
  }

  private buildManagementRowState(
    downloadService: DownloadRuntimeService,
    task: DownloadV2TaskEntity
  ): DownloadManagementRowState {
    const presentation = this.buildTaskPresentation(downloadService, task);
    const primaryAction = this.resolvePrimaryAction(presentation);
    return new DownloadManagementRowState({
      guid: task.guid,
      status: task.status,
      fileType: resolveDownloadFileType(task.suggestedFileName, task.request.mimeType),
      fileName: presentation.fileName,
      sourceText: this.buildSourceLine(task),
      statusText: this.buildManagementStatusText(task, presentation),
      detailText: this.buildManagementDetailText(task, presentation),
      trailingText: this.buildManagementTrailingText(task),
      completionTimeText: this.buildRecentCompletionTimeText(task),
      completionSizeText: this.buildCompletedSizeText(task),
      showProgress: task.status !== 'completed',
      progressValue: presentation.progressValue,
      primaryAction: primaryAction,
      primaryActionLabel: this.resolvePrimaryActionLabel(primaryAction),
      primaryActionEmphasis: primaryAction === 'pause' ? 'secondary' : 'primary',
      menuActions: this.buildRowMenuActions(presentation.allowedActions, task.status, primaryAction)
    });
  }

  private isActiveGroup(group: DownloadQueryGroup): boolean {
    return group === 'in_progress' || group === 'pending' || group === 'paused' || group === 'failed';
  }

  private buildTaskPresentation(
    downloadService: DownloadRuntimeService,
    task: DownloadV2TaskEntity
  ): DownloadV2TaskPresentation {
    return {
      fileName: task.suggestedFileName.length > 0 ? task.suggestedFileName : resolveAppResourceText($r('app.string.download_status_unnamed')),
      statusText: this.buildTaskStatusText(task),
      progressValue: this.buildTaskProgressValue(task),
      progressText: this.buildTaskProgressText(task),
      isWarning: task.status === 'failed' && !canContinueDownloadV2Task(task),
      allowedActions: downloadService.listAllowedActionsForTask(task)
    };
  }

  private buildTaskStatusText(task: DownloadV2TaskEntity): string {
    if (task.status === 'failed' && canContinueDownloadV2Task(task)) {
      return resolveAppResourceText($r('app.string.download_status_paused'));
    }
    switch (task.status) {
      case 'failed': {
        const errorCode = task.failure.sourceCode ?? 0;
        return errorCode !== 0
          ? resolveAppResourceText($r('app.string.download_status_failed_code', errorCode))
          : resolveAppResourceText($r('app.string.download_status_failed'));
      }
      case 'completed':
        return resolveAppResourceText($r('app.string.download_status_complete'));
      case 'running': {
        const speed = task.progress.speedBytesPerSecond;
        const speedText = speed > 0 ? `，${this.formatBytes(speed)}/s` : '';
        return resolveAppResourceText($r('app.string.download_status_running_speed', speedText));
      }
      case 'created':
      case 'awaiting_confirmation':
      case 'queued':
        return resolveAppResourceText($r('app.string.download_status_waiting'));
      case 'paused':
        return resolveAppResourceText($r('app.string.download_status_paused'));
      case 'canceled':
        return resolveAppResourceText($r('app.string.download_status_canceled'));
      default:
        return resolveAppResourceText($r('app.string.download_status_raw', task.status));
    }
  }

  private buildTaskProgressValue(task: DownloadV2TaskEntity): number {
    return resolveDownloadProgressPercent(task.progress, task.status);
  }

  private buildTaskProgressText(task: DownloadV2TaskEntity): string {
    const downloaded = this.formatBytes(task.progress.receivedBytes);
    const total = resolveDownloadDisplayTotal(task.progress);
    if (total <= 0) {
      return resolveAppResourceText($r('app.string.download_progress_unknown_size', downloaded));
    }
    const totalText = isDownloadTotalEstimated(task.progress)
      ? resolveAppResourceText($r('app.string.download_size_estimated', this.formatBytes(total)))
      : this.formatBytes(total);
    return `${downloaded} / ${totalText}`;
  }

  private buildManagementStatusText(task: DownloadV2TaskEntity, presentation: DownloadV2TaskPresentation): string {
    if (task.status === 'completed') {
      return '';
    }
    if (task.status === 'failed' || presentation.isWarning) {
      return presentation.statusText;
    }
    if (task.status === 'running') {
      return '';
    }
    if (task.status === 'canceled') {
      return resolveAppResourceText($r('app.string.download_status_canceled'));
    }
    return '';
  }

  private buildManagementDetailText(task: DownloadV2TaskEntity, presentation: DownloadV2TaskPresentation): string {
    if (task.status === 'completed') {
      return '';
    }
    const progressText = presentation.progressText.trim();
    return progressText;
  }

  private buildManagementTrailingText(task: DownloadV2TaskEntity): string {
    if (task.status === 'completed') {
      return '';
    }
    if (task.progress.speedBytesPerSecond > 0 && task.status === 'running') {
      return `${this.formatBytes(task.progress.speedBytesPerSecond)}/s`;
    }
    if (task.status === 'failed' && canContinueDownloadV2Task(task)) {
      return resolveAppResourceText($r('app.string.settings_sync_paused'));
    }
    if (task.status === 'failed') {
      return resolveAppResourceText($r('app.string.download_status_failed'));
    }
    if (task.status === 'paused') {
      return resolveAppResourceText($r('app.string.settings_sync_paused'));
    }
    if (task.status === 'created' || task.status === 'awaiting_confirmation' || task.status === 'queued') {
      return resolveAppResourceText($r('app.string.download_status_waiting_short'));
    }
    if (task.status === 'canceled') {
      return resolveAppResourceText($r('app.string.download_status_canceled_short'));
    }
    return '--';
  }

  private buildSourceLine(task: DownloadV2TaskEntity): string {
    const sourceHost = task.request.sourceHost?.trim() ?? '';
    if (sourceHost.length > 0) {
      return sourceHost;
    }
    if (task.request.url.length > 0) {
      return task.request.url;
    }
    return resolveAppResourceText($r('app.string.download_status_no_source'));
  }

  private buildRecentCompletionTimeText(task: DownloadV2TaskEntity): string {
    if (task.status !== 'completed') {
      return '';
    }
    const completedAt = task.timing.completedAt ?? task.timing.updatedAt;
    if (completedAt <= 0) {
      return resolveAppResourceText($r('app.string.download_status_time_unknown'));
    }
    return this.formatDateTime(completedAt);
  }

  private buildCompletedSizeText(task: DownloadV2TaskEntity): string {
    if (task.status !== 'completed') {
      return '';
    }
    const finalSize = task.progress.receivedBytes > 0 ? task.progress.receivedBytes : task.progress.totalBytes;
    if (finalSize <= 0) {
      return '';
    }
    return this.formatBytes(finalSize);
  }

  private formatDateTime(timestamp: number): string {
    const date = new Date(timestamp);
    const month = this.padTwoDigits(date.getMonth() + 1);
    const day = this.padTwoDigits(date.getDate());
    const hour = this.padTwoDigits(date.getHours());
    const minute = this.padTwoDigits(date.getMinutes());
    return `${month}-${day} ${hour}:${minute}`;
  }

  private padTwoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private getQuickActionLabel(action: DownloadManagementRowAction, status: DownloadV2Status): string {
    switch (action) {
      case 'open_file':
        return resolveAppResourceText($r('app.string.ui_open'));
      case 'open_location':
        return resolveAppResourceText($r('app.string.ui_share'));
      case 'save_to_system':
        return resolveAppResourceText($r('app.string.download_action_save_system'));
      case 'copy_link':
        return resolveAppResourceText($r('app.string.download_action_copy_link'));
      case 'pause':
        return resolveAppResourceText($r('app.string.browser_ui_browser_video_assistant_player_overlay_013'));
      case 'resume':
        return resolveAppResourceText($r('app.string.settings_pro_continue'));
      case 'retry':
        return resolveAppResourceText($r('app.string.novel_action_retry'));
      case 'cancel':
        return resolveAppResourceText($r('app.string.settings_account_cancel'));
      case 'remove_record':
        return status === 'completed'
          ? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_013'))
          : resolveAppResourceText($r('app.string.download_action_delete_task'));
      case 'enter_selection':
        return DOWNLOAD_ROW_ENTER_SELECTION_LABEL;
      default:
        return action;
    }
  }

  /** Keep the multi-select entry first for both active and completed downloads. */
  buildRowMenuActions(
    actions: DownloadV2ManagementAction[],
    status: DownloadV2Status,
    primaryAction?: DownloadV2ManagementAction
  ): DownloadManagementRowMenuActionView[] {
    const menuActions: DownloadManagementRowAction[] = actions.slice();
    if (menuActions.indexOf('copy_link') < 0) {
      menuActions.push('copy_link');
    }
    const views: DownloadManagementRowMenuActionView[] = [];
    if (canSelectDownloadTask(status)) {
      views.push({
        action: DOWNLOAD_ROW_ENTER_SELECTION_ACTION,
        label: DOWNLOAD_ROW_ENTER_SELECTION_LABEL
      });
    }
    menuActions.forEach((action: DownloadManagementRowAction) => {
      if (action === primaryAction) {
        return;
      }
      const menuAction: DownloadManagementRowMenuActionView = {
        action: action,
        label: this.getQuickActionLabel(action, status)
      };
      views.push(menuAction);
      if (action === 'remove_record' && status === 'completed') {
        views.push({
          action: 'delete_task_and_file',
          label: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_015'))
        });
      }
    });
    return views;
  }

  private buildOptimisticMenuActions(status: DownloadV2Status): DownloadManagementRowMenuActionView[] {
    if (status === 'paused' || status === 'running') {
      return [
        { action: DOWNLOAD_ROW_ENTER_SELECTION_ACTION, label: DOWNLOAD_ROW_ENTER_SELECTION_LABEL },
        { action: 'copy_link', label: resolveAppResourceText($r('app.string.download_action_copy_link')) },
        { action: 'cancel', label: resolveAppResourceText($r('app.string.settings_account_cancel')) }
      ];
    }
    return [];
  }

  private resolvePrimaryAction(presentation: DownloadV2TaskPresentation): DownloadV2ManagementAction | undefined {
    if (presentation.allowedActions.indexOf('pause') >= 0) {
      return 'pause';
    }
    if (presentation.allowedActions.indexOf('resume') >= 0) {
      return 'resume';
    }
    if (presentation.allowedActions.indexOf('open_file') >= 0) {
      return 'open_file';
    }
    if (presentation.allowedActions.indexOf('retry') >= 0) {
      return 'retry';
    }
    return undefined;
  }

  private resolvePrimaryActionLabel(action: DownloadV2ManagementAction | undefined): string {
    if (action === 'pause') {
      return resolveAppResourceText($r('app.string.browser_ui_browser_video_assistant_player_overlay_013'));
    }
    if (action === 'resume') {
      return resolveAppResourceText($r('app.string.settings_pro_continue'));
    }
    if (action === 'open_file') {
      return resolveAppResourceText($r('app.string.ui_open'));
    }
    if (action === 'retry') {
      return resolveAppResourceText($r('app.string.novel_action_retry'));
    }
    return '';
  }

  private formatBytes(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return `${Math.round(bytes)} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${Math.round(bytes / 102.4) / 10} KB`;
    }
    return `${Math.round(bytes / (1024 * 102.4)) / 10} MB`;
  }
}

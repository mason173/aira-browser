import { DownloadStatusCounts } from './DownloadQueryService';
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

export type DownloadManagementRowAction = DownloadV2ManagementAction | 'copy_link' | 'delete_task_and_file';

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
      row.statusText = '下载已暂停';
      row.trailingText = '已暂停';
      row.primaryAction = 'resume';
      row.primaryActionLabel = '继续';
      row.primaryActionEmphasis = 'primary';
      row.menuActions = this.buildOptimisticMenuActions('paused');
      return true;
    }
    if (targetStatus === 'running') {
      row.status = 'running';
      row.statusText = '';
      if (row.trailingText === '已暂停') {
        row.trailingText = '--';
      }
      row.primaryAction = 'pause';
      row.primaryActionLabel = '暂停';
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
      { group: 'in_progress', label: '下载中', count: activeCount },
      { group: 'completed', label: '已完成', count: counts.completed }
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
      menuActions: this.buildMenuActions(presentation.allowedActions, task.status, primaryAction)
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
      fileName: task.suggestedFileName.length > 0 ? task.suggestedFileName : '未命名下载',
      statusText: this.buildTaskStatusText(task),
      progressValue: this.buildTaskProgressValue(task),
      progressText: this.buildTaskProgressText(task),
      isWarning: task.status === 'failed' && !canContinueDownloadV2Task(task),
      allowedActions: downloadService.listAllowedActionsForTask(task)
    };
  }

  private buildTaskStatusText(task: DownloadV2TaskEntity): string {
    if (task.status === 'failed' && canContinueDownloadV2Task(task)) {
      return '下载已暂停';
    }
    switch (task.status) {
      case 'failed': {
        const errorCode = task.failure.sourceCode ?? 0;
        return errorCode !== 0 ? `下载失败，错误码 ${errorCode}` : '下载失败';
      }
      case 'completed':
        return '下载完成';
      case 'running': {
        const speed = task.progress.speedBytesPerSecond;
        const speedText = speed > 0 ? `，${this.formatBytes(speed)}/s` : '';
        return `正在下载${speedText}`;
      }
      case 'created':
      case 'awaiting_confirmation':
      case 'queued':
        return '等待下载';
      case 'paused':
        return '下载已暂停';
      case 'canceled':
        return '下载已取消';
      default:
        return `状态：${task.status}`;
    }
  }

  private buildTaskProgressValue(task: DownloadV2TaskEntity): number {
    const totalBytes = task.progress.totalBytes;
    if (totalBytes <= 0) {
      return task.status === 'completed' ? 100 : 0;
    }
    return Math.max(0, Math.min(100, Math.floor(task.progress.receivedBytes * 100 / totalBytes)));
  }

  private buildTaskProgressText(task: DownloadV2TaskEntity): string {
    const downloaded = this.formatBytes(task.progress.receivedBytes);
    if (task.progress.totalBytes <= 0) {
      return `${downloaded} / 未知大小`;
    }
    return `${downloaded} / ${this.formatBytes(task.progress.totalBytes)}`;
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
      return '下载已取消';
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
      return '已暂停';
    }
    if (task.status === 'failed') {
      return '下载失败';
    }
    if (task.status === 'paused') {
      return '已暂停';
    }
    if (task.status === 'created' || task.status === 'awaiting_confirmation' || task.status === 'queued') {
      return '等待中';
    }
    if (task.status === 'canceled') {
      return '已取消';
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
    return '当前没有可显示的来源信息';
  }

  private buildRecentCompletionTimeText(task: DownloadV2TaskEntity): string {
    if (task.status !== 'completed') {
      return '';
    }
    const completedAt = task.timing.completedAt ?? task.timing.updatedAt;
    if (completedAt <= 0) {
      return '完成时间未知';
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
        return '打开';
      case 'open_location':
        return '分享';
      case 'save_to_system':
        return '保存到系统下载';
      case 'copy_link':
        return '复制下载链接';
      case 'pause':
        return '暂停';
      case 'resume':
        return '继续';
      case 'retry':
        return '重试';
      case 'cancel':
        return '取消';
      case 'remove_record':
        return status === 'completed' ? '仅删除任务' : '删除任务';
      default:
        return action;
    }
  }

  private buildMenuActions(
    actions: DownloadV2ManagementAction[],
    status: DownloadV2Status,
    primaryAction?: DownloadV2ManagementAction
  ): DownloadManagementRowMenuActionView[] {
    const menuActions: DownloadManagementRowAction[] = actions.slice();
    if (menuActions.indexOf('copy_link') < 0) {
      menuActions.push('copy_link');
    }
    const views: DownloadManagementRowMenuActionView[] = [];
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
          label: '删除任务和文件'
        });
      }
    });
    return views;
  }

  private buildOptimisticMenuActions(status: DownloadV2Status): DownloadManagementRowMenuActionView[] {
    if (status === 'paused' || status === 'running') {
      return [
        { action: 'copy_link', label: '复制下载链接' },
        { action: 'cancel', label: '取消' }
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
      return '暂停';
    }
    if (action === 'resume') {
      return '继续';
    }
    if (action === 'open_file') {
      return '打开';
    }
    if (action === 'retry') {
      return '重试';
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

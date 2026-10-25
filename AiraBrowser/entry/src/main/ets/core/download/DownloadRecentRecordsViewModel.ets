import {
  resolveDownloadProgressFraction,
  resolveDownloadProgressPercent,
  resolveDownloadDisplayTotal,
  isDownloadTotalEstimated
} from '../../domain/downloadv2/DownloadV2Progress';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { DownloadV2Status } from '../../domain/downloadv2/DownloadV2Types';
import { DownloadFileType, resolveDownloadFileType } from './DownloadFileTypeResolver';
import { RecentlyClosedRecordTimeViewModel } from '../browser/RecentlyClosedRecordTimeViewModel';
import { resolveAppResourceText } from '../resources/AppResourceText';

/** Ceiling only. A short window shows fewer rows, and the popup hugs whatever is shown. */
export const DOWNLOAD_RECENT_POPUP_MAX_ROWS: number = 6;
export const DOWNLOAD_RECENT_POPUP_WIDTH_VP: number = 360;
export const DOWNLOAD_RECENT_IDLE_ROW_HEIGHT_VP: number = 52;
export const DOWNLOAD_RECENT_ACTIVE_ROW_HEIGHT_VP: number = 68;
export const DOWNLOAD_RECENT_HEADER_HEIGHT_VP: number = 48;
export const DOWNLOAD_RECENT_FOOTER_HEIGHT_VP: number = 44;
export const DOWNLOAD_RECENT_POPUP_BOTTOM_EDGE_VP: number = 16;
const DOWNLOAD_RECENT_FALLBACK_ROWS: number = 5;
const BYTE_UNIT: number = 1024;

export interface DownloadRecentPopupLayoutInput {
  viewportHeightVp: number;
  reservedTopVp: number;
  now: number;
}

export interface DownloadRecentRecordView {
  guid: string;
  fileName: string;
  fileType: DownloadFileType;
  subtitle: string;
  /** A canceled download stays in the list, with its name struck through. */
  struckThrough: boolean;
  showProgress: boolean;
  progressKnown: boolean;
  progressValue: number;
  canOpenFile: boolean;
  /** pause, resume, or open_location. Empty when this row has no leading hover control. */
  leadingHoverAction: string;
  /** cancel or open_file. Empty when this row has no trailing hover control. */
  trailingHoverAction: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  windowId: string;
}

export interface DownloadRecentPopupLayout {
  records: DownloadRecentRecordView[];
  heightVp: number;
}

/**
 * Recent-download popup for the desktop toolbar ring.
 * The height is the header, the footer, and only the rows that fit in the
 * window, never a fixed card size. Six rows is the most it will offer.
 */
export class DownloadRecentRecordsViewModel {
  private readonly timeViewModel: RecentlyClosedRecordTimeViewModel = new RecentlyClosedRecordTimeViewModel();

  resolve(tasks: DownloadV2TaskEntity[], input: DownloadRecentPopupLayoutInput): DownloadRecentPopupLayout {
    const ranked = this.rank(tasks);
    const availableHeight = this.resolveAvailableHeight(input);
    const records: DownloadRecentRecordView[] = [];
    let usedHeight = DOWNLOAD_RECENT_HEADER_HEIGHT_VP + DOWNLOAD_RECENT_FOOTER_HEIGHT_VP;
    const now = Number.isFinite(input.now) ? input.now : 0;
    for (let index = 0; index < ranked.length; index++) {
      if (records.length >= DOWNLOAD_RECENT_POPUP_MAX_ROWS) {
        break;
      }
      const task: DownloadV2TaskEntity | undefined = ranked[index];
      if (task === undefined) {
        break;
      }
      const rowHeight = this.rowHeight(task.status);
      if (records.length > 0 && usedHeight + rowHeight > availableHeight) {
        break;
      }
      records.push(this.buildRecord(task, now));
      usedHeight += rowHeight;
    }
    return {
      records: records,
      heightVp: usedHeight
    };
  }

  rowHeight(status: DownloadV2Status): number {
    return this.showsProgress(status) ?
      DOWNLOAD_RECENT_ACTIVE_ROW_HEIGHT_VP : DOWNLOAD_RECENT_IDLE_ROW_HEIGHT_VP;
  }

  private resolveAvailableHeight(input: DownloadRecentPopupLayoutInput): number {
    const chrome = DOWNLOAD_RECENT_HEADER_HEIGHT_VP + DOWNLOAD_RECENT_FOOTER_HEIGHT_VP;
    const fallback = chrome + DOWNLOAD_RECENT_ACTIVE_ROW_HEIGHT_VP * DOWNLOAD_RECENT_FALLBACK_ROWS;
    if (!Number.isFinite(input.viewportHeightVp) || input.viewportHeightVp <= 0) {
      return fallback;
    }
    const reservedTop = Number.isFinite(input.reservedTopVp) ? Math.max(0, input.reservedTopVp) : 0;
    return Math.max(
      chrome + DOWNLOAD_RECENT_ACTIVE_ROW_HEIGHT_VP,
      input.viewportHeightVp - reservedTop - DOWNLOAD_RECENT_POPUP_BOTTOM_EDGE_VP
    );
  }

  private rank(tasks: DownloadV2TaskEntity[]): DownloadV2TaskEntity[] {
    const listed: DownloadV2TaskEntity[] = [];
    tasks.forEach((task: DownloadV2TaskEntity): void => {
      if (this.isListed(task)) {
        listed.push(task);
      }
    });
    listed.sort((left: DownloadV2TaskEntity, right: DownloadV2TaskEntity): number => {
      return this.recency(right) - this.recency(left);
    });
    return listed;
  }

  private isListed(task: DownloadV2TaskEntity): boolean {
    if (task.status === 'removed') {
      return false;
    }
    return (task.timing.removedAt ?? 0) <= 0;
  }

  private recency(task: DownloadV2TaskEntity): number {
    if (task.status === 'completed' && (task.timing.completedAt ?? 0) > 0) {
      return task.timing.completedAt ?? 0;
    }
    if (task.timing.updatedAt > 0) {
      return task.timing.updatedAt;
    }
    return task.timing.createdAt;
  }

  private buildRecord(task: DownloadV2TaskEntity, now: number): DownloadRecentRecordView {
    const totalBytes = resolveDownloadDisplayTotal(task.progress);
    const receivedBytes = this.normalizeBytes(task.progress.receivedBytes);
    return {
      guid: task.guid,
      fileName: this.resolveFileName(task),
      fileType: resolveDownloadFileType(this.resolveFileName(task), task.request.mimeType),
      subtitle: this.buildSubtitle(task, receivedBytes, totalBytes, now),
      struckThrough: task.status === 'canceled',
      showProgress: this.showsProgress(task.status),
      progressKnown: resolveDownloadProgressFraction(task.progress) >= 0,
      progressValue: resolveDownloadProgressPercent(task.progress, task.status),
      canOpenFile: task.status === 'completed',
      leadingHoverAction: this.leadingHoverAction(task.status),
      trailingHoverAction: this.trailingHoverAction(task.status),
      profileId: task.profileId,
      privacyMode: task.privacyMode,
      dataScope: task.dataScope,
      windowId: task.windowId?.trim() ?? ''
    };
  }

  private leadingHoverAction(status: DownloadV2Status): string {
    if (status === 'running') {
      return 'pause';
    }
    if (status === 'paused') {
      return 'resume';
    }
    if (status === 'completed') {
      return 'open_location';
    }
    return '';
  }

  private trailingHoverAction(status: DownloadV2Status): string {
    if (status === 'running' || status === 'paused' || status === 'queued' ||
      status === 'awaiting_confirmation') {
      return 'cancel';
    }
    if (status === 'completed') {
      return 'open_file';
    }
    return '';
  }

  private showsProgress(status: DownloadV2Status): boolean {
    return status === 'running' || status === 'paused' || status === 'queued' ||
      status === 'created' || status === 'awaiting_confirmation';
  }

  private buildSubtitle(
    task: DownloadV2TaskEntity,
    receivedBytes: number,
    totalBytes: number,
    now: number
  ): string {
    if (task.status === 'canceled') {
      return resolveAppResourceText($r('app.string.download_status_canceled_short'));
    }
    if (task.status === 'completed') {
      const sizeText = this.formatBytes(receivedBytes > 0 ? receivedBytes : totalBytes);
      const timeText = this.timeViewModel.formatClosedTime(task.timing.completedAt ?? task.timing.updatedAt, now);
      return sizeText.length > 0 ? `${sizeText} · ${timeText}` : timeText;
    }
    const amountText = isDownloadTotalEstimated(task.progress)
      ? `${this.formatBytes(receivedBytes)} / ` +
        resolveAppResourceText($r('app.string.download_size_estimated', this.formatBytes(totalBytes)))
      : totalBytes > 0 ? this.formatBytePair(receivedBytes, totalBytes) : this.formatBytes(receivedBytes);
    const statusText = this.statusText(task.status);
    return amountText.length > 0 ? `${amountText} · ${statusText}` : statusText;
  }

  private statusText(status: DownloadV2Status): string {
    if (status === 'running') {
      return resolveAppResourceText($r('app.string.download_notification_downloading'));
    }
    if (status === 'paused') {
      return resolveAppResourceText($r('app.string.settings_sync_paused'));
    }
    if (status === 'failed') {
      return resolveAppResourceText($r('app.string.download_status_failed'));
    }
    return resolveAppResourceText($r('app.string.download_status_waiting'));
  }

  private resolveFileName(task: DownloadV2TaskEntity): string {
    const resolved = task.resolvedFileName?.trim() ?? '';
    if (resolved.length > 0) {
      return resolved;
    }
    const suggested = task.suggestedFileName.trim();
    return suggested.length > 0 ? suggested : resolveAppResourceText($r('app.string.download_status_unnamed'));
  }

  private formatBytePair(receivedBytes: number, totalBytes: number): string {
    const unit = this.chooseUnit(Math.max(receivedBytes, totalBytes));
    return `${this.formatInUnit(receivedBytes, unit)}/${this.formatInUnit(totalBytes, unit)} ${this.unitLabel(unit)}`;
  }

  private formatBytes(bytes: number): string {
    const normalized = this.normalizeBytes(bytes);
    if (normalized <= 0) {
      return '';
    }
    const unit = this.chooseUnit(normalized);
    return `${this.formatInUnit(normalized, unit)} ${this.unitLabel(unit)}`;
  }

  private chooseUnit(bytes: number): number {
    if (bytes >= BYTE_UNIT * BYTE_UNIT * BYTE_UNIT) {
      return BYTE_UNIT * BYTE_UNIT * BYTE_UNIT;
    }
    if (bytes >= BYTE_UNIT * BYTE_UNIT) {
      return BYTE_UNIT * BYTE_UNIT;
    }
    if (bytes >= BYTE_UNIT) {
      return BYTE_UNIT;
    }
    return 1;
  }

  private unitLabel(unit: number): string {
    if (unit >= BYTE_UNIT * BYTE_UNIT * BYTE_UNIT) {
      return 'GB';
    }
    if (unit >= BYTE_UNIT * BYTE_UNIT) {
      return 'MB';
    }
    if (unit >= BYTE_UNIT) {
      return 'KB';
    }
    return 'B';
  }

  private formatInUnit(bytes: number, unit: number): string {
    if (unit <= 1) {
      return `${Math.round(bytes)}`;
    }
    const scaled = Math.round((bytes / unit) * 10) / 10;
    if (Math.abs(scaled - Math.round(scaled)) < 0.05) {
      return `${Math.round(scaled)}`;
    }
    return `${scaled}`;
  }

  private normalizeBytes(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return value;
  }
}

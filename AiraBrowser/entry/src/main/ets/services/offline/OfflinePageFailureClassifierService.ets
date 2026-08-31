import { OfflinePageFailureReason } from '../../common/models/OfflinePageModels';

export class OfflinePageFailureClassifierService {
  classify(error: Object | undefined, fallback: OfflinePageFailureReason = 'file_write_failed'): OfflinePageFailureReason {
    const message = this.stringifyError(error).toLowerCase();
    if (this.isStorageFullLikeMessage(message)) {
      return 'storage_full';
    }
    if (message.includes('database') || message.includes('rdb') || message.includes('sqlite')) {
      return 'database_write_failed';
    }
    if (message.includes('controller')) {
      return 'controller_unavailable';
    }
    return fallback;
  }

  isStorageFullLikeError(error: Object | undefined): boolean {
    return this.isStorageFullLikeMessage(this.stringifyError(error).toLowerCase());
  }

  private isStorageFullLikeMessage(message: string): boolean {
    return message.includes('no space') ||
      message.includes('not enough space') ||
      message.includes('disk full') ||
      message.includes('database or disk is full') ||
      message.includes('enospc') ||
      message.includes('space is insufficient');
  }

  private stringifyError(error: Object | undefined): string {
    if (error === undefined || error === null) {
      return '';
    }
    try {
      return JSON.stringify(error);
    } catch (_jsonError) {
      return String(error);
    }
  }
}

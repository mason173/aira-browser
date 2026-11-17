import { DownloadFileNameService } from './DownloadFileNameService';

export type DownloadFilenameConflictAction =
  'use_original' |
  'uniquify' |
  'prompt' |
  'overwrite';

export interface DownloadFilenameConflictPlan {
  fileName: string;
  conflictAction: DownloadFilenameConflictAction;
  conflictIndex: number;
}

export class DownloadFilenameConflictService {
  private readonly fileNameService: DownloadFileNameService = new DownloadFileNameService();

  buildOriginalPlan(fileName: string): DownloadFilenameConflictPlan {
    return {
      fileName: this.fileNameService.sanitizeFileName(fileName),
      conflictAction: 'use_original',
      conflictIndex: 0
    };
  }

  buildUniquifyPlan(fileName: string, conflictIndex: number = 1): DownloadFilenameConflictPlan {
    const index = this.normalizeConflictIndex(conflictIndex);
    return {
      fileName: this.buildUniquifiedFileName(fileName, index),
      conflictAction: 'uniquify',
      conflictIndex: index
    };
  }

  buildUniquifiedFileName(fileName: string, conflictIndex: number = 1): string {
    const index = this.normalizeConflictIndex(conflictIndex);
    return this.fileNameService.buildConflictFileName(fileName, index);
  }

  private normalizeConflictIndex(conflictIndex: number): number {
    if (!Number.isFinite(conflictIndex) || conflictIndex < 1) {
      return 1;
    }
    return Math.floor(conflictIndex);
  }
}

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
  buildOriginalPlan(fileName: string): DownloadFilenameConflictPlan {
    return {
      fileName: fileName,
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
    const normalizedName = fileName.trim().length > 0 ? fileName.trim() : 'download.bin';
    const index = this.normalizeConflictIndex(conflictIndex);
    const extensionStart = this.resolveExtensionStart(normalizedName);
    if (extensionStart <= 0) {
      return `${normalizedName} (${index})`;
    }
    const baseName = normalizedName.substring(0, extensionStart);
    const extension = normalizedName.substring(extensionStart);
    return `${baseName} (${index})${extension}`;
  }

  private normalizeConflictIndex(conflictIndex: number): number {
    if (!Number.isFinite(conflictIndex) || conflictIndex < 1) {
      return 1;
    }
    return Math.floor(conflictIndex);
  }

  private resolveExtensionStart(fileName: string): number {
    const lowerName = fileName.toLowerCase();
    const compoundExtensions: string[] = ['.tar.gz', '.tar.bz2', '.tar.xz'];
    for (let index = 0; index < compoundExtensions.length; index += 1) {
      const extension = compoundExtensions[index];
      if (lowerName.endsWith(extension) && fileName.length > extension.length) {
        return fileName.length - extension.length;
      }
    }
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= fileName.length - 1) {
      return -1;
    }
    return dotIndex;
  }
}

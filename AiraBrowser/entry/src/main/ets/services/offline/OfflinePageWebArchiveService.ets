import { webview } from '@kit.ArkWeb';

export interface OfflinePageWebArchiveResult {
  ok: boolean;
  path: string;
  reason: 'none' | 'controller_unavailable' | 'archive_failed';
}

const WEB_ARCHIVE_FILE_NAME: string = 'snapshot.mht';

export class OfflinePageWebArchiveService {
  getFileName(): string {
    return WEB_ARCHIVE_FILE_NAME;
  }

  async capture(controller: webview.WebviewController | undefined, targetPath: string): Promise<OfflinePageWebArchiveResult> {
    if (controller === undefined) {
      return this.buildFailure('controller_unavailable');
    }
    const normalizedPath = targetPath.trim();
    if (normalizedPath.length === 0) {
      return this.buildFailure('archive_failed');
    }
    try {
      const storedPath = await controller.storeWebArchive(normalizedPath, false);
      const normalizedStoredPath = storedPath.trim();
      if (normalizedStoredPath.length <= 0) {
        return this.buildFailure('archive_failed');
      }
      return {
        ok: true,
        path: normalizedStoredPath,
        reason: 'none'
      };
    } catch (_error) {
      return this.buildFailure('archive_failed');
    }
  }

  private buildFailure(reason: 'controller_unavailable' | 'archive_failed'): OfflinePageWebArchiveResult {
    return {
      ok: false,
      path: '',
      reason: reason
    };
  }
}

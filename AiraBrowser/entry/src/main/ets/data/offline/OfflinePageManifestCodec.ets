import {
  OfflinePageContentKind,
  OfflinePageManifest,
  OfflinePageMediaManifestItem,
  OfflinePageResourceStatus
} from '../../common/models/OfflinePageModels';

interface OfflinePageManifestJson {
  id?: string;
  originalUrl?: string;
  title?: string;
  siteName?: string;
  savedAt?: number;
  snapshotFileName?: string;
  contentKind?: string;
  previewFileName?: string;
  faviconFileName?: string;
  resources?: Object[];
}

interface OfflinePageMediaManifestJson {
  originalUrl?: string;
  localFileName?: string;
  mimeType?: string;
  bytes?: number;
  status?: string;
}

interface OfflinePageMediaManifestEncodeJson {
  originalUrl: string;
  localFileName: string;
  mimeType: string;
  bytes: number;
  status: OfflinePageResourceStatus;
}

export class OfflinePageManifestCodec {
  encode(manifest: OfflinePageManifest): string {
    return JSON.stringify({
      id: manifest.id,
      originalUrl: manifest.originalUrl,
      title: manifest.title,
      siteName: manifest.siteName,
      savedAt: manifest.savedAt,
      snapshotFileName: manifest.snapshotFileName,
      contentKind: manifest.contentKind,
      previewFileName: manifest.previewFileName,
      faviconFileName: manifest.faviconFileName,
      resources: manifest.resources.map((resource: OfflinePageMediaManifestItem): OfflinePageMediaManifestEncodeJson => {
        return {
          originalUrl: resource.originalUrl,
          localFileName: resource.localFileName,
          mimeType: resource.mimeType,
          bytes: resource.bytes,
          status: resource.status
        };
      })
    });
  }

  decode(payload: string): OfflinePageManifest | undefined {
    try {
      const parsed = JSON.parse(payload) as OfflinePageManifestJson;
      const id = this.readString(parsed.id);
      const originalUrl = this.readString(parsed.originalUrl);
      const title = this.readString(parsed.title);
      const siteName = this.readString(parsed.siteName);
      const snapshotFileName = this.readString(parsed.snapshotFileName);
      if (id.length === 0 || originalUrl.length === 0 || snapshotFileName.length === 0) {
        return undefined;
      }
      return {
        id: id,
        originalUrl: originalUrl,
        title: title,
        siteName: siteName,
        savedAt: this.readNumber(parsed.savedAt),
        snapshotFileName: snapshotFileName,
        contentKind: this.normalizeContentKind(parsed.contentKind),
        previewFileName: this.readString(parsed.previewFileName),
        faviconFileName: this.readString(parsed.faviconFileName),
        resources: this.readResources(parsed.resources)
      };
    } catch (_error) {
      return undefined;
    }
  }

  private readResources(value?: Object[]): OfflinePageMediaManifestItem[] {
    if (!Array.isArray(value)) {
      return [];
    }
    return value
      .map((item: Object): OfflinePageMediaManifestItem | undefined => {
        const raw = item as OfflinePageMediaManifestJson;
        const originalUrl = this.readString(raw.originalUrl);
        const localFileName = this.readString(raw.localFileName);
        if (originalUrl.length === 0 && localFileName.length === 0) {
          return undefined;
        }
        return {
          originalUrl: originalUrl,
          localFileName: localFileName,
          mimeType: this.readString(raw.mimeType),
          bytes: this.readNumber(raw.bytes),
          status: this.normalizeStatus(raw.status)
        };
      })
      .filter((item: OfflinePageMediaManifestItem | undefined): boolean => item !== undefined)
      .map((item: OfflinePageMediaManifestItem | undefined): OfflinePageMediaManifestItem => {
        return item as OfflinePageMediaManifestItem;
      });
  }

  private normalizeStatus(value?: string): OfflinePageResourceStatus {
    if (value === 'saved' || value === 'failed' || value === 'skipped') {
      return value;
    }
    return 'skipped';
  }

  private normalizeContentKind(value?: string): OfflinePageContentKind {
    if (value === 'web_archive') {
      return 'web_archive';
    }
    return 'html';
  }

  private readString(value?: string): string {
    return typeof value === 'string' ? value : '';
  }

  private readNumber(value?: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
  }
}

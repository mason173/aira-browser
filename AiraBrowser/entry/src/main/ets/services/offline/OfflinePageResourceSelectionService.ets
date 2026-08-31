import {
  OfflinePageResourceSelectionResult,
  OfflinePageSelectedResource,
  OfflinePageSnapshotMetadata
} from '../../common/models/OfflinePageModels';

const MAX_FAVICON_COUNT: number = 2;
const MAX_IMAGE_COUNT: number = 24;
const MAX_STYLESHEET_COUNT: number = 12;

export class OfflinePageResourceSelectionService {
  select(metadata: OfflinePageSnapshotMetadata): OfflinePageResourceSelectionResult {
    const selected: OfflinePageSelectedResource[] = [];
    const seen: string[] = [];
    this.markSeen(seen, metadata.inlinedImageUrls);
    this.appendCandidates(selected, seen, metadata.faviconUrls, 'favicon', MAX_FAVICON_COUNT, 1000);
    this.appendCandidates(selected, seen, metadata.imageUrls, 'image', MAX_IMAGE_COUNT, 700);
    this.appendCandidates(
      selected,
      seen,
      this.selectStylesheetUrls(metadata.resourceUrls),
      'stylesheet',
      MAX_STYLESHEET_COUNT,
      400
    );
    const totalCandidateCount = metadata.faviconUrls.length + metadata.imageUrls.length +
      this.selectStylesheetUrls(metadata.resourceUrls).length;
    return {
      resources: selected,
      skippedCount: Math.max(0, totalCandidateCount - selected.length)
    };
  }

  estimateResourceBudgetBytes(selection: OfflinePageResourceSelectionResult): number {
    let total = 0;
    selection.resources.forEach((resource: OfflinePageSelectedResource) => {
      if (resource.kind === 'favicon') {
        total += 128 * 1024;
      } else if (resource.kind === 'stylesheet') {
        total += 256 * 1024;
      } else {
        total += 512 * 1024;
      }
    });
    return total;
  }

  private markSeen(seen: string[], urls: string[]): void {
    urls.forEach((url: string) => {
      const normalized = this.normalizeUrl(url);
      if (normalized.length > 0 && seen.indexOf(normalized) < 0) {
        seen.push(normalized);
      }
    });
  }

  private appendCandidates(
    selected: OfflinePageSelectedResource[],
    seen: string[],
    urls: string[],
    kind: 'image' | 'favicon' | 'stylesheet',
    limit: number,
    priorityBase: number
  ): void {
    let accepted = 0;
    for (let index = 0; index < urls.length; index += 1) {
      if (accepted >= limit) {
        return;
      }
      const url = this.normalizeUrl(urls[index]);
      if (!this.isNetworkUrl(url) || seen.indexOf(url) >= 0) {
        continue;
      }
      seen.push(url);
      selected.push({
        originalUrl: url,
        kind: kind,
        priority: priorityBase - accepted,
        localFileName: this.buildLocalFileName(kind, accepted, url)
      });
      accepted += 1;
    }
  }

  private selectStylesheetUrls(urls: string[]): string[] {
    return urls.filter((url: string): boolean => {
      const lower = url.trim().toLowerCase();
      return lower.endsWith('.css') || lower.includes('.css?') || lower.includes('/css/');
    });
  }

  private buildLocalFileName(kind: 'image' | 'favicon' | 'stylesheet', index: number, url: string): string {
    const extension = this.resolveExtension(kind, url);
    return `assets/${kind}-${index + 1}${extension}`;
  }

  private resolveExtension(kind: 'image' | 'favicon' | 'stylesheet', url: string): string {
    if (kind === 'stylesheet') {
      return '.css';
    }
    const path = this.readUrlPath(url).toLowerCase();
    const knownExtensions: string[] = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.svg', '.ico', '.avif'];
    for (let index = 0; index < knownExtensions.length; index += 1) {
      const extension = knownExtensions[index];
      if (path.endsWith(extension)) {
        return extension;
      }
    }
    return kind === 'favicon' ? '.ico' : '.img';
  }

  private readUrlPath(url: string): string {
    const protocolMarker = url.indexOf('://');
    const pathStart = protocolMarker >= 0 ? url.indexOf('/', protocolMarker + 3) : 0;
    const path = pathStart >= 0 ? url.substring(pathStart) : url;
    const queryIndex = path.indexOf('?');
    if (queryIndex >= 0) {
      return path.substring(0, queryIndex);
    }
    return path;
  }

  private normalizeUrl(url: string): string {
    return url.trim();
  }

  private isNetworkUrl(url: string): boolean {
    const lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}

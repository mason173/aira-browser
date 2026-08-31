import { MediaHlsManifestTarget } from '../../features/mediaDiscovery/MediaHlsProjectionModels';
import {
  MediaManifestSummary,
  MediaManifestVariant
} from '../../features/mediaDiscovery/MediaManifestModels';

export interface BrowserHlsTakeoverRequestContextLine {
  label: string;
  value: string;
}

export class BrowserHlsTakeoverViewModel {
  buildContextLines(target: MediaHlsManifestTarget | undefined): BrowserHlsTakeoverRequestContextLine[] {
    const lines: BrowserHlsTakeoverRequestContextLine[] = [];
    if (target === undefined) {
      return lines;
    }
    this.appendLine(lines, '页面', target.pageUrl);
    this.appendLine(lines, '来源', target.frameUrl);
    this.appendLine(lines, 'Referer', target.referer);
    this.appendLine(lines, 'Origin', target.originUrl);
    this.appendLine(lines, 'User-Agent', target.userAgent);
    const headers = target.requestHeaders ?? {};
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      this.appendLine(lines, key, headers[key]);
    }
    return lines;
  }

  buildCopyableRequestContext(target: MediaHlsManifestTarget | undefined): string {
    if (target === undefined) {
      return '';
    }
    const lines: string[] = [];
    this.appendCopyLine(lines, 'URL', target.url);
    this.appendCopyLine(lines, 'Page', target.pageUrl);
    this.appendCopyLine(lines, 'Frame', target.frameUrl);
    this.appendCopyLine(lines, 'Referer', target.referer);
    this.appendCopyLine(lines, 'Origin', target.originUrl);
    this.appendCopyLine(lines, 'User-Agent', target.userAgent);
    const headers = target.requestHeaders ?? {};
    const keys = Object.keys(headers);
    if (keys.length > 0) {
      lines.push('Headers:');
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const value = headers[key] ?? '';
        if (key.trim().length > 0 && value.trim().length > 0) {
          lines.push(key + ': ' + value);
        }
      }
    }
    return lines.join('\n');
  }

  buildSummaryTitle(summary: MediaManifestSummary | undefined): string {
    if (summary === undefined) {
      return '等待解析';
    }
    if (summary.kind === 'hls') {
      return summary.role === 'master' ? 'HLS Master 清单' : 'HLS Media 清单';
    }
    if (summary.kind === 'dash') {
      return 'DASH MPD 清单';
    }
    return '流媒体清单';
  }

  buildSummaryMetrics(summary: MediaManifestSummary | undefined): string {
    if (summary === undefined) {
      return '';
    }
    const parts: string[] = [];
    if (summary.sourceHost.length > 0) {
      parts.push(summary.sourceHost);
    }
    if (summary.variantCount > 0) {
      parts.push(summary.variantCount.toString() + ' 个清晰度');
    }
    if (summary.segmentCount > 0) {
      parts.push(summary.segmentCount.toString() + ' 个分片');
    }
    if (summary.durationSeconds > 0) {
      parts.push(this.formatDurationSeconds(summary.durationSeconds));
    }
    if (summary.targetDuration > 0) {
      parts.push('分片约 ' + summary.targetDuration.toString() + 's');
    }
    if (summary.keyCount > 0) {
      parts.push(summary.keyCount.toString() + ' 个 Key');
    }
    if (summary.encrypted) {
      parts.push('加密');
    }
    return parts.join(' · ');
  }

  buildVariantName(variant: MediaManifestVariant): string {
    if (variant.name.length > 0) {
      return variant.name;
    }
    if (variant.resolution.length > 0) {
      return variant.resolution;
    }
    if (variant.bandwidth > 0) {
      return Math.round(variant.bandwidth / 1000).toString() + ' kbps';
    }
    return '清晰度 ' + (variant.index + 1).toString();
  }

  buildVariantMeta(variant: MediaManifestVariant): string {
    const parts: string[] = [];
    if (variant.bandwidth > 0) {
      parts.push(Math.round(variant.bandwidth / 1000).toString() + ' kbps');
    }
    if (variant.segmentCount > 0) {
      parts.push(variant.segmentCount.toString() + ' 分片');
    }
    if (variant.targetDuration > 0) {
      parts.push(variant.targetDuration.toString() + 's');
    }
    if (variant.encrypted) {
      parts.push('加密');
    }
    return parts.join(' · ');
  }

  shortenUrl(url: string): string {
    if (url.length <= 76) {
      return url;
    }
    return url.substring(0, 44) + '...' + url.substring(url.length - 28);
  }

  private appendLine(lines: BrowserHlsTakeoverRequestContextLine[], label: string, value: string | undefined): void {
    const normalized = (value ?? '').trim();
    if (normalized.length <= 0) {
      return;
    }
    lines.push({ label: label, value: normalized });
  }

  private appendCopyLine(lines: string[], label: string, value: string | undefined): void {
    const normalized = (value ?? '').trim();
    if (normalized.length <= 0) {
      return;
    }
    lines.push(label + ': ' + normalized);
  }

  private formatDurationSeconds(seconds: number): string {
    const totalSeconds = Math.max(0, Math.floor(seconds));
    const minutes = Math.floor(totalSeconds / 60);
    const rest = totalSeconds % 60;
    return minutes.toString() + ':' + (rest < 10 ? '0' : '') + rest.toString();
  }
}

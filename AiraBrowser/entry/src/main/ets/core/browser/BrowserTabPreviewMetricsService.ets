import { BrowserTabPreviewCaptureSource } from '../../services/web/BrowserTabPreviewTypes';

export type BrowserTabPreviewTransitionImageKind = 'shared' | 'none';

export interface BrowserTabPreviewCaptureMetricInput {
  tabId: string;
  source: BrowserTabPreviewCaptureSource;
  success: boolean;
  failureReason: string;
  durationMs: number;
  sharedPersisted: boolean;
  sharedBytes?: number;
  stageLine?: string;
  createdAt?: number;
}

export interface BrowserTabPreviewCaptureMetricRecord extends BrowserTabPreviewCaptureMetricInput {
  createdAt: number;
}

export interface BrowserTabPreviewTransitionImageMetricInput {
  tabId: string;
  phase: string;
  kind: BrowserTabPreviewTransitionImageKind;
  transitionReady: boolean;
  source: string;
  createdAt?: number;
}

export interface BrowserTabPreviewTransitionImageMetricRecord extends BrowserTabPreviewTransitionImageMetricInput {
  createdAt: number;
}

export interface BrowserTabPreviewCacheMetricInput {
  totalFiles: number;
  sharedFiles: number;
  totalBytes: number;
  sharedBytes: number;
  createdAt?: number;
}

export interface BrowserTabPreviewCacheMetricRecord extends BrowserTabPreviewCacheMetricInput {
  createdAt: number;
}

export interface BrowserTabPreviewMetricsSummary {
  captureLine: string;
  transitionLine: string;
  cacheLine: string;
}

export class BrowserTabPreviewMetricsService {
  private readonly maxRecords: number;
  private captureRecords: BrowserTabPreviewCaptureMetricRecord[] = [];
  private transitionImageRecords: BrowserTabPreviewTransitionImageMetricRecord[] = [];
  private cacheRecords: BrowserTabPreviewCacheMetricRecord[] = [];

  constructor(maxRecords: number = 80) {
    this.maxRecords = maxRecords;
  }

  recordCapture(input: BrowserTabPreviewCaptureMetricInput): BrowserTabPreviewCaptureMetricRecord {
    const record: BrowserTabPreviewCaptureMetricRecord = {
      tabId: input.tabId,
      source: input.source,
      success: input.success,
      failureReason: input.failureReason,
      durationMs: this.normalizeNumber(input.durationMs),
      sharedPersisted: input.sharedPersisted,
      sharedBytes: this.normalizeNumber(input.sharedBytes ?? 0),
      stageLine: input.stageLine?.trim() ?? '',
      createdAt: input.createdAt ?? Date.now()
    };
    this.captureRecords = [record].concat(this.captureRecords).slice(0, this.maxRecords);
    return record;
  }

  recordTransitionImage(
    input: BrowserTabPreviewTransitionImageMetricInput
  ): BrowserTabPreviewTransitionImageMetricRecord {
    const record: BrowserTabPreviewTransitionImageMetricRecord = {
      tabId: input.tabId,
      phase: input.phase,
      kind: input.kind,
      transitionReady: input.transitionReady,
      source: input.source,
      createdAt: input.createdAt ?? Date.now()
    };
    this.transitionImageRecords = [record].concat(this.transitionImageRecords).slice(0, this.maxRecords);
    return record;
  }

  recordCacheSnapshot(input: BrowserTabPreviewCacheMetricInput): BrowserTabPreviewCacheMetricRecord {
    const record: BrowserTabPreviewCacheMetricRecord = {
      totalFiles: this.normalizeNumber(input.totalFiles),
      sharedFiles: this.normalizeNumber(input.sharedFiles),
      totalBytes: this.normalizeNumber(input.totalBytes),
      sharedBytes: this.normalizeNumber(input.sharedBytes),
      createdAt: input.createdAt ?? Date.now()
    };
    this.cacheRecords = [record].concat(this.cacheRecords).slice(0, this.maxRecords);
    return record;
  }

  buildSummary(): BrowserTabPreviewMetricsSummary {
    return {
      captureLine: this.buildCaptureSummaryLine(),
      transitionLine: this.buildTransitionSummaryLine(),
      cacheLine: this.buildCacheSummaryLine()
    };
  }

  buildDebugLines(limit: number = 6): string[] {
    const summary = this.buildSummary();
    const lines: string[] = [
      summary.captureLine,
      summary.transitionLine,
      summary.cacheLine
    ];
    this.captureRecords.slice(0, Math.max(0, limit)).forEach((record: BrowserTabPreviewCaptureMetricRecord) => {
      lines.push(this.buildCaptureLine(record));
    });
    this.transitionImageRecords
      .slice(0, Math.max(0, limit))
      .forEach((record: BrowserTabPreviewTransitionImageMetricRecord) => {
        lines.push(this.buildTransitionLine(record));
      });
    return lines;
  }

  clear(): void {
    this.captureRecords = [];
    this.transitionImageRecords = [];
    this.cacheRecords = [];
  }

  private buildCaptureSummaryLine(): string {
    const total = this.captureRecords.length;
    let success = 0;
    let sharedPersisted = 0;
    let durationTotal = 0;
    const sourceCounts: Record<string, number> = {};
    this.captureRecords.forEach((record: BrowserTabPreviewCaptureMetricRecord) => {
      if (record.success) {
        success += 1;
      }
      if (record.sharedPersisted) {
        sharedPersisted += 1;
      }
      durationTotal += record.durationMs;
      sourceCounts[record.source] = (sourceCounts[record.source] ?? 0) + 1;
    });
    return `tabPreviewCapture total=${total} success=${success} failed=${total - success} avgMs=${this.average(durationTotal, total)} sharedPersisted=${sharedPersisted} sources=${this.buildCountLine(sourceCounts)}`;
  }

  private buildTransitionSummaryLine(): string {
    const total = this.transitionImageRecords.length;
    const kindCounts: Record<string, number> = {};
    this.transitionImageRecords.forEach((record: BrowserTabPreviewTransitionImageMetricRecord) => {
      kindCounts[record.kind] = (kindCounts[record.kind] ?? 0) + 1;
    });
    return `tabPreviewTransition total=${total} kinds=${this.buildCountLine(kindCounts)}`;
  }

  private buildCacheSummaryLine(): string {
    const latest = this.cacheRecords[0];
    if (latest === undefined) {
      return 'tabPreviewCache files=0 shared=0 bytes=0 sharedBytes=0';
    }
    return `tabPreviewCache files=${latest.totalFiles} shared=${latest.sharedFiles} bytes=${latest.totalBytes} sharedBytes=${latest.sharedBytes}`;
  }

  private buildCaptureLine(record: BrowserTabPreviewCaptureMetricRecord): string {
    return `capture tab=${record.tabId} source=${record.source} success=${record.success} reason=${record.failureReason || 'none'} durationMs=${record.durationMs} shared=${record.sharedPersisted}/${record.sharedBytes ?? 0} stages=${record.stageLine || 'none'}`;
  }

  private buildTransitionLine(record: BrowserTabPreviewTransitionImageMetricRecord): string {
    return `transition tab=${record.tabId} phase=${record.phase} kind=${record.kind} ready=${record.transitionReady} source=${record.source || 'unknown'}`;
  }

  private buildCountLine(counts: Record<string, number>): string {
    const keys = Object.keys(counts).sort();
    if (keys.length <= 0) {
      return 'none';
    }
    return keys.map((key: string) => `${key}:${counts[key]}`).join(',');
  }

  private average(total: number, count: number): number {
    if (count <= 0) {
      return 0;
    }
    return Math.round(total / count);
  }

  private normalizeNumber(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }
}

export const sharedBrowserTabPreviewMetrics: BrowserTabPreviewMetricsService =
  new BrowserTabPreviewMetricsService();

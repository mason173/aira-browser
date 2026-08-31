import { systemDateTime } from '@kit.BasicServicesKit';

export interface AdBlockNativeAuthorityMetricsSnapshot {
  backendVersion: string;
  ready: boolean;
  ruleLineCount: number;
  buildCount: number;
  buildFailureCount: number;
  eligibleQueryCount: number;
  queryCount: number;
  queryFailureCount: number;
  blockedCount: number;
  allowedCount: number;
  redirectCount: number;
  queryP50Ms: number;
  queryP95Ms: number;
  queryP99Ms: number;
}

const MAX_QUERY_DURATION_SAMPLES: number = 256;
const NANOSECONDS_PER_MILLISECOND: number = 1000000;

export class AdBlockNativeAuthorityMetrics {
  private backendVersion: string = '';
  private ready: boolean = false;
  private ruleLineCount: number = 0;
  private buildCount: number = 0;
  private buildFailureCount: number = 0;
  private eligibleQueryCount: number = 0;
  private queryCount: number = 0;
  private queryFailureCount: number = 0;
  private blockedCount: number = 0;
  private allowedCount: number = 0;
  private redirectCount: number = 0;
  private queryDurationSamplesMs: number[] = [];
  private nextQueryDurationSampleIndex: number = 0;

  startQuery(): number {
    return this.nowNanoseconds();
  }

  recordBuild(backendVersion: string, ruleLineCount: number): void {
    this.ready = true;
    this.buildCount += 1;
    this.backendVersion = backendVersion;
    this.ruleLineCount = Math.max(0, Math.floor(ruleLineCount));
  }

  recordBuildFailure(): void {
    this.buildFailureCount += 1;
  }

  recordReleased(): void {
    this.ready = false;
    this.ruleLineCount = 0;
  }

  recordEligibleQuery(): void {
    this.eligibleQueryCount += 1;
  }

  recordQuery(startedAtNanoseconds: number, shouldBlock: boolean, redirected: boolean): void {
    this.queryCount += 1;
    if (shouldBlock) {
      this.blockedCount += 1;
    } else {
      this.allowedCount += 1;
    }
    if (shouldBlock && redirected) {
      this.redirectCount += 1;
    }
    this.appendQueryDuration(this.elapsedMilliseconds(startedAtNanoseconds));
  }

  recordQueryFailure(startedAtNanoseconds: number): void {
    this.queryCount += 1;
    this.queryFailureCount += 1;
    this.appendQueryDuration(this.elapsedMilliseconds(startedAtNanoseconds));
  }

  snapshot(): AdBlockNativeAuthorityMetricsSnapshot {
    const sortedDurations = this.queryDurationSamplesMs.slice()
      .sort((left: number, right: number): number => left - right);
    return {
      backendVersion: this.backendVersion,
      ready: this.ready,
      ruleLineCount: this.ruleLineCount,
      buildCount: this.buildCount,
      buildFailureCount: this.buildFailureCount,
      eligibleQueryCount: this.eligibleQueryCount,
      queryCount: this.queryCount,
      queryFailureCount: this.queryFailureCount,
      blockedCount: this.blockedCount,
      allowedCount: this.allowedCount,
      redirectCount: this.redirectCount,
      queryP50Ms: this.percentile(sortedDurations, 0.50),
      queryP95Ms: this.percentile(sortedDurations, 0.95),
      queryP99Ms: this.percentile(sortedDurations, 0.99)
    };
  }

  private nowNanoseconds(): number {
    try {
      return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true);
    } catch (_error) {
      return Date.now() * NANOSECONDS_PER_MILLISECOND;
    }
  }

  private elapsedMilliseconds(startedAtNanoseconds: number): number {
    const elapsedNanoseconds = this.nowNanoseconds() - startedAtNanoseconds;
    if (elapsedNanoseconds <= 0) {
      return 0;
    }
    return elapsedNanoseconds / NANOSECONDS_PER_MILLISECOND;
  }

  private appendQueryDuration(durationMs: number): void {
    const normalizedDuration = this.normalizeDuration(durationMs);
    if (this.queryDurationSamplesMs.length < MAX_QUERY_DURATION_SAMPLES) {
      this.queryDurationSamplesMs.push(normalizedDuration);
      return;
    }
    this.queryDurationSamplesMs[this.nextQueryDurationSampleIndex] = normalizedDuration;
    this.nextQueryDurationSampleIndex =
      (this.nextQueryDurationSampleIndex + 1) % MAX_QUERY_DURATION_SAMPLES;
  }

  private percentile(sortedValues: number[], percentile: number): number {
    if (sortedValues.length === 0) {
      return 0;
    }
    const index = Math.max(0, Math.min(
      sortedValues.length - 1,
      Math.ceil(sortedValues.length * percentile) - 1
    ));
    return sortedValues[index];
  }

  private normalizeDuration(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return value;
  }
}

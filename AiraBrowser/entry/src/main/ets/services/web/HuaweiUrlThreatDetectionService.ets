import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { safetyDetect } from '@kit.DeviceSecurityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import urlUtils from '@ohos.url';

export type BrowserUrlThreatVerdict = 'normal' | 'malware' | 'phishing' | 'other' | 'unknown';
export type BrowserUrlThreatCheckStatus = 'checked' | 'not_checked';
export type BrowserUrlThreatCheckReason =
  'app_gate_timeout' |
  'cloud_result' |
  'cloud_traffic_limit' |
  'cloud_unreachable' |
  'daily_guard_reached' |
  'empty_response' |
  'frequency_limit' |
  'ineligible_url' |
  'internal_error' |
  'invalid_parameters' |
  'memory_cache' |
  'network_unreachable' |
  'operation_timeout' |
  'parallel_limit' |
  'permission_denied' |
  'protection_disabled' |
  'queue_full' |
  'unexpected_error' |
  'unknown_error' |
  'unsupported';

export interface BrowserUrlThreatAssessment {
  status: BrowserUrlThreatCheckStatus;
  verdict: BrowserUrlThreatVerdict;
  checkedUrl: string;
  checkedAt: number;
  cacheHit: boolean;
  reason: BrowserUrlThreatCheckReason;
}

interface BrowserUrlThreatCacheEntry {
  assessment: BrowserUrlThreatAssessment;
  expiresAt: number;
}

interface BrowserUrlThreatQueuedCheck {
  checkedUrl: string;
  resolve: (assessment: BrowserUrlThreatAssessment) => void;
}

const URL_THREAT_LOG_DOMAIN: number = 0x0000;
const URL_THREAT_LOG_TAG: string = 'UrlThreatCheck';
const MAX_URL_BYTES: number = 4096;
const MAX_ACTIVE_CHECKS: number = 4;
const MAX_QUEUED_CHECKS: number = 32;
const MAX_CACHE_ENTRIES: number = 512;
const MAX_PROCESS_DAILY_CALLS: number = 9000;
const NORMAL_CACHE_TTL_MS: number = 15 * 60 * 1000;
const THREAT_CACHE_TTL_MS: number = 60 * 60 * 1000;

export class HuaweiUrlThreatDetectionService {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly cache: Map<string, BrowserUrlThreatCacheEntry> =
    new Map<string, BrowserUrlThreatCacheEntry>();
  private readonly inFlight: Map<string, Promise<BrowserUrlThreatAssessment>> =
    new Map<string, Promise<BrowserUrlThreatAssessment>>();
  private readonly queue: BrowserUrlThreatQueuedCheck[] = [];
  private activeCheckCount: number = 0;
  private dailyCallKey: string = '';
  private dailyCallCount: number = 0;

  canCheckUrl(url: string): boolean {
    return this.resolveCheckUrl(url).length > 0;
  }

  resolveCheckUrl(url: string): string {
    const candidate = url.trim();
    if (candidate.length <= 0) {
      return '';
    }
    try {
      const parsed = urlUtils.URL.parseURL(candidate);
      const scheme = parsed.protocol.trim().toLowerCase();
      if ((scheme !== 'http:' && scheme !== 'https:') || parsed.hostname.trim().length <= 0) {
        return '';
      }
      // Fragments and embedded credentials are not required for server-side URL reputation checks.
      parsed.hash = '';
      parsed.username = '';
      parsed.password = '';
      const checkedUrl = parsed.toString().trim();
      if (checkedUrl.length <= 0 || this.encoder.encodeInto(checkedUrl).byteLength > MAX_URL_BYTES) {
        return '';
      }
      return checkedUrl;
    } catch (_error) {
      return '';
    }
  }

  checkUrl(url: string): Promise<BrowserUrlThreatAssessment> {
    const checkedUrl = this.resolveCheckUrl(url);
    const now = Date.now();
    if (checkedUrl.length <= 0) {
      return Promise.resolve(this.buildNotChecked('', 'ineligible_url', now));
    }
    const cached = this.resolveCached(checkedUrl, now);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const pending = this.inFlight.get(checkedUrl);
    if (pending !== undefined) {
      return pending;
    }
    if (this.queue.length >= MAX_QUEUED_CHECKS) {
      return Promise.resolve(this.buildNotChecked(checkedUrl, 'queue_full', now));
    }
    const operation = new Promise<BrowserUrlThreatAssessment>(
      (resolve: (assessment: BrowserUrlThreatAssessment) => void): void => {
        this.queue.push({
          checkedUrl: checkedUrl,
          resolve: resolve
        });
        this.drainQueue();
      }
    );
    this.inFlight.set(checkedUrl, operation);
    return operation;
  }

  private drainQueue(): void {
    while (this.activeCheckCount < MAX_ACTIVE_CHECKS && this.queue.length > 0) {
      const queued = this.queue.shift();
      if (queued === undefined) {
        return;
      }
      this.activeCheckCount += 1;
      void this.performCloudCheck(queued.checkedUrl)
        .then((assessment: BrowserUrlThreatAssessment): void => {
          if (assessment.status === 'checked') {
            this.cacheAssessment(assessment);
          }
          queued.resolve(assessment);
        })
        .catch((_error: Error): void => {
          queued.resolve(this.buildNotChecked(queued.checkedUrl, 'unexpected_error', Date.now()));
        })
        .finally((): void => {
          this.activeCheckCount = Math.max(0, this.activeCheckCount - 1);
          this.inFlight.delete(queued.checkedUrl);
          this.drainQueue();
        });
    }
  }

  private async performCloudCheck(checkedUrl: string): Promise<BrowserUrlThreatAssessment> {
    const now = Date.now();
    if (!this.consumeDailyCall(now)) {
      return this.buildNotChecked(checkedUrl, 'daily_guard_reached', now);
    }
    try {
      const response = await safetyDetect.checkUrlThreat({ urls: [checkedUrl] });
      if (response.results.length <= 0) {
        return this.buildNotChecked(checkedUrl, 'empty_response', Date.now());
      }
      return {
        status: 'checked',
        verdict: this.resolveVerdict(response.results[0].threat),
        checkedUrl: checkedUrl,
        checkedAt: Date.now(),
        cacheHit: false,
        reason: 'cloud_result'
      };
    } catch (error) {
      const businessError = error as BusinessError;
      const errorCode = typeof businessError?.code === 'number' ? businessError.code : 0;
      hilog.warn(
        URL_THREAT_LOG_DOMAIN,
        URL_THREAT_LOG_TAG,
        'Huawei URL threat check failed code=%{public}d',
        errorCode
      );
      return this.buildNotChecked(checkedUrl, this.resolveErrorReason(errorCode), Date.now());
    }
  }

  private resolveVerdict(threat: safetyDetect.UrlThreatType): BrowserUrlThreatVerdict {
    if (threat === safetyDetect.UrlThreatType.MALWARE) {
      return 'malware';
    }
    if (threat === safetyDetect.UrlThreatType.PHISHING) {
      return 'phishing';
    }
    if (threat === safetyDetect.UrlThreatType.OTHERS) {
      return 'other';
    }
    return threat === safetyDetect.UrlThreatType.NORMAL ? 'normal' : 'unknown';
  }

  private resolveErrorReason(code: number): BrowserUrlThreatCheckReason {
    if (code === 201) return 'permission_denied';
    if (code === 401) return 'invalid_parameters';
    if (code === 801) return 'unsupported';
    if (code === 1010800002) return 'network_unreachable';
    if (code === 1010800003) return 'cloud_unreachable';
    if (code === 1010800005) return 'parallel_limit';
    if (code === 1010800006) return 'frequency_limit';
    if (code === 1010800007) return 'operation_timeout';
    if (code === 1010800008) return 'cloud_traffic_limit';
    return code === 1010800001 ? 'internal_error' : 'unknown_error';
  }

  private resolveCached(checkedUrl: string, now: number): BrowserUrlThreatAssessment | undefined {
    const entry = this.cache.get(checkedUrl);
    if (entry === undefined) {
      return undefined;
    }
    if (entry.expiresAt <= now) {
      this.cache.delete(checkedUrl);
      return undefined;
    }
    return {
      status: entry.assessment.status,
      verdict: entry.assessment.verdict,
      checkedUrl: entry.assessment.checkedUrl,
      checkedAt: entry.assessment.checkedAt,
      cacheHit: true,
      reason: 'memory_cache'
    };
  }

  private cacheAssessment(assessment: BrowserUrlThreatAssessment): void {
    this.pruneCache(assessment.checkedAt);
    const ttl = assessment.verdict === 'normal' ? NORMAL_CACHE_TTL_MS : THREAT_CACHE_TTL_MS;
    this.cache.set(assessment.checkedUrl, {
      assessment: assessment,
      expiresAt: assessment.checkedAt + ttl
    });
    this.pruneCache(assessment.checkedAt);
  }

  private pruneCache(now: number): void {
    this.cache.forEach((entry: BrowserUrlThreatCacheEntry, key: string): void => {
      if (entry.expiresAt <= now) {
        this.cache.delete(key);
      }
    });
    while (this.cache.size > MAX_CACHE_ENTRIES) {
      let oldestKey: string = '';
      let oldestCheckedAt: number = Number.MAX_SAFE_INTEGER;
      this.cache.forEach((entry: BrowserUrlThreatCacheEntry, key: string): void => {
        if (entry.assessment.checkedAt < oldestCheckedAt) {
          oldestCheckedAt = entry.assessment.checkedAt;
          oldestKey = key;
        }
      });
      if (oldestKey.length <= 0) {
        return;
      }
      this.cache.delete(oldestKey);
    }
  }

  private consumeDailyCall(now: number): boolean {
    const currentDayKey = this.resolveDayKey(now);
    if (currentDayKey !== this.dailyCallKey) {
      this.dailyCallKey = currentDayKey;
      this.dailyCallCount = 0;
    }
    if (this.dailyCallCount >= MAX_PROCESS_DAILY_CALLS) {
      return false;
    }
    this.dailyCallCount += 1;
    return true;
  }

  private resolveDayKey(now: number): string {
    const date = new Date(now);
    return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
  }

  private buildNotChecked(
    checkedUrl: string,
    reason: BrowserUrlThreatCheckReason,
    checkedAt: number
  ): BrowserUrlThreatAssessment {
    return {
      status: 'not_checked',
      verdict: 'unknown',
      checkedUrl: checkedUrl,
      checkedAt: checkedAt,
      cacheHit: false,
      reason: reason
    };
  }
}

export const sharedHuaweiUrlThreatDetectionService: HuaweiUrlThreatDetectionService =
  new HuaweiUrlThreatDetectionService();

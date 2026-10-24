import { AdBlockCustomRuleSource } from '../../common/models/BrowserModels';

const HOUR_MS: number = 60 * 60 * 1000;
const DEFAULT_UPDATE_INTERVAL_MS: number = 24 * HOUR_MS;
const MAX_UPDATE_INTERVAL_MS: number = 14 * 24 * HOUR_MS;

export class AdBlockSubscriptionPolicyService {
  // Matches the hour/day units used by adblock-rust's FilterListMetadata. Limits are
  // local download policy; foreground updates do not promise a background timer.
  readUpdateIntervalMs(text: string): number | undefined {
    const match = /^!\s*Expires:\s*(\d+)\s*(hours?|days?)\b/im.exec(text.slice(0, 4096));
    if (match === null) {
      return undefined;
    }
    const amount = Number(match[1]);
    if (!Number.isFinite(amount) || amount <= 0) {
      return undefined;
    }
    const interval = amount * HOUR_MS * (match[2].toLowerCase().startsWith('day') ? 24 : 1);
    return this.normalizeUpdateIntervalMs(interval);
  }

  normalizeUpdateIntervalMs(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value) || value <= 0) {
      return DEFAULT_UPDATE_INTERVAL_MS;
    }
    return Math.min(MAX_UPDATE_INTERVAL_MS, Math.max(HOUR_MS, Math.floor(value)));
  }

  isDue(source: AdBlockCustomRuleSource, now: number): boolean {
    if (source.lastError.trim().length > 0) {
      const lastAttemptAt = source.lastAttemptAt ?? source.updatedAt;
      return lastAttemptAt <= 0 || now - lastAttemptAt >= HOUR_MS;
    }
    // Older payloads were stored without include/condition preprocessing. Refresh
    // once after upgrading instead of keeping a partly loaded list for ten days.
    if (source.updateIntervalMs === undefined) {
      return true;
    }
    const lastUpdatedAt = source.lastUpdatedAt > 0 ? source.lastUpdatedAt : source.updatedAt;
    return lastUpdatedAt <= 0 || now - lastUpdatedAt >= this.normalizeUpdateIntervalMs(source.updateIntervalMs);
  }
}

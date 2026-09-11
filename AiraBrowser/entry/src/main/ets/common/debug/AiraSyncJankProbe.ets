import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'SyncJankProbe';

// Temporary cold-start sync jank probes. Grep [DEBUG-sync-jank-9f3c] to remove.
export class AiraSyncJankProbe {
  static mark(event: string): void {
    hilog.info(DOMAIN, TAG, '[DEBUG-sync-jank-9f3c] %{public}s', event);
  }

  static markExtra(event: string, extra: string): void {
    hilog.info(DOMAIN, TAG, '[DEBUG-sync-jank-9f3c] %{public}s extra=%{public}s', event, extra);
  }

  static end(event: string, startedAt: number): void {
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-sync-jank-9f3c] %{public}s durationMs=%{public}d',
      event,
      Date.now() - startedAt
    );
  }

  static endExtra(event: string, startedAt: number, extra: string): void {
    hilog.info(
      DOMAIN,
      TAG,
      '[DEBUG-sync-jank-9f3c] %{public}s durationMs=%{public}d extra=%{public}s',
      event,
      Date.now() - startedAt,
      extra
    );
  }
}

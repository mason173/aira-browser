import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_browser_security_report_metrics';
const GUARDIAN_STARTED_AT_KEY: string = 'guardian_started_at';
const DAY_MS: number = 24 * 60 * 60 * 1000;

export interface BrowserSecurityReportMetricsState {
  guardianStartedAt: number;
}

export class BrowserSecurityReportMetricsRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private state: BrowserSecurityReportMetricsState = {
    guardianStartedAt: 0
  };

  async initialize(): Promise<BrowserSecurityReportMetricsState> {
    const store = await this.getStore();
    this.state = {
      guardianStartedAt: this.normalizeTimestamp(store.getSync(GUARDIAN_STARTED_AT_KEY, 0))
    };
    return this.getState();
  }

  getState(): BrowserSecurityReportMetricsState {
    return {
      guardianStartedAt: this.state.guardianStartedAt
    };
  }

  getGuardianDays(now: number = Date.now()): number {
    return this.calculateGuardianDays(this.state.guardianStartedAt, now);
  }

  async ensureGuardianStarted(now: number = Date.now()): Promise<number> {
    if (this.state.guardianStartedAt > 0) {
      return this.getGuardianDays(now);
    }

    this.state = {
      guardianStartedAt: now
    };
    const store = await this.getStore();
    store.putSync(GUARDIAN_STARTED_AT_KEY, now);
    store.flushSync();
    return this.getGuardianDays(now);
  }

  private calculateGuardianDays(startedAt: number, now: number): number {
    if (startedAt <= 0 || now < startedAt) {
      return 0;
    }
    return Math.max(0, Math.floor((now - startedAt) / DAY_MS));
  }

  private normalizeTimestamp(value: preferences.ValueType): number {
    const timestamp = Number(value);
    return Number.isFinite(timestamp) && timestamp > 0 ? Math.round(timestamp) : 0;
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

import { SitePermissionKind } from '../../common/models/BrowserModels';

export interface SitePermissionPromptFrequencyState {
  isFrequent: boolean;
  promptCount: number;
  windowMs: number;
}

interface SitePermissionPromptRecord {
  key: string;
  createdAt: number;
}

const SITE_PERMISSION_PROMPT_WINDOW_MS: number = 30000;
const SITE_PERMISSION_PROMPT_FREQUENT_THRESHOLD: number = 2;
const SITE_PERMISSION_PROMPT_MAX_RECORDS: number = 80;

export class SitePermissionPromptThrottleService {
  private records: SitePermissionPromptRecord[] = [];

  registerPrompt(
    origin: string,
    kinds: SitePermissionKind[],
    nowMs: number = Date.now()
  ): SitePermissionPromptFrequencyState {
    const key = this.buildPromptKey(origin, kinds);
    this.records = this.records.filter((record: SitePermissionPromptRecord) => {
      return nowMs - record.createdAt <= SITE_PERMISSION_PROMPT_WINDOW_MS;
    });
    const promptCount = this.records.filter((record: SitePermissionPromptRecord) => record.key === key).length + 1;
    this.records = this.records.concat([{
      key: key,
      createdAt: nowMs
    }]);
    if (this.records.length > SITE_PERMISSION_PROMPT_MAX_RECORDS) {
      this.records = this.records.slice(this.records.length - SITE_PERMISSION_PROMPT_MAX_RECORDS);
    }
    return {
      isFrequent: promptCount >= SITE_PERMISSION_PROMPT_FREQUENT_THRESHOLD,
      promptCount: promptCount,
      windowMs: SITE_PERMISSION_PROMPT_WINDOW_MS
    };
  }

  private buildPromptKey(origin: string, kinds: SitePermissionKind[]): string {
    const normalizedKinds = kinds.slice().sort().join('+');
    return `${origin.trim().toLowerCase()}|${normalizedKinds}`;
  }
}

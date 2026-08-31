import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_browser_settings_notice_dismissals';
const DISMISSED_NOTICE_IDS_KEY: string = 'dismissed_notice_ids';

export const SETTINGS_NOTICE_ADBLOCK_RULES: string = 'adblock_rules_notice_v1';
export const SETTINGS_NOTICE_AIRA_PRO_ENTRY_CONFIRMATION: string = 'aira_pro_entry_confirmation_v7';
export const SETTINGS_NOTICE_SYNC_FIRST_ACTIVATION_PROMPT: string = 'sync_first_activation_prompt_v1';
export const SETTINGS_NOTICE_USER_SCRIPTS: string = 'user_scripts_notice_v1';
export const SETTINGS_NOTICE_USER_AGENT: string = 'user_agent_notice_v1';
export const SETTINGS_NOTICE_TRANSLATION: string = 'translation_notice_v1';

export class SettingsNoticeDismissalRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private dismissedNoticeIds: string[] = [];

  async initialize(): Promise<string[]> {
    const store = await this.getStore();
    this.dismissedNoticeIds = this.normalizeDismissedNoticeIds(
      store.getSync(DISMISSED_NOTICE_IDS_KEY, JSON.stringify([]))
    );
    return this.listDismissedNoticeIds();
  }

  listDismissedNoticeIds(): string[] {
    return this.dismissedNoticeIds.slice();
  }

  hasDismissed(noticeId: string): boolean {
    const normalizedId = noticeId.trim();
    return normalizedId.length > 0 && this.dismissedNoticeIds.indexOf(normalizedId) >= 0;
  }

  async dismiss(noticeId: string): Promise<string[]> {
    const normalizedId = noticeId.trim();
    if (normalizedId.length === 0 || this.hasDismissed(normalizedId)) {
      return this.listDismissedNoticeIds();
    }
    this.dismissedNoticeIds = this.dismissedNoticeIds.concat([normalizedId]);
    const store = await this.getStore();
    store.putSync(DISMISSED_NOTICE_IDS_KEY, JSON.stringify(this.dismissedNoticeIds));
    store.flushSync();
    return this.listDismissedNoticeIds();
  }

  private normalizeDismissedNoticeIds(value: preferences.ValueType): string[] {
    try {
      const parsed = JSON.parse(String(value)) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      parsed.forEach((item: string) => {
        const normalizedItem = `${item}`.trim();
        if (normalizedItem.length > 0 && result.indexOf(normalizedItem) < 0) {
          result.push(normalizedItem);
        }
      });
      return result;
    } catch (_error) {
      return [];
    }
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

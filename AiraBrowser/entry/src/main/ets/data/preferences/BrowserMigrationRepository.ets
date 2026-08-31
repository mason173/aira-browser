import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const PREFERENCES_NAME: string = 'aira_browser_migrations';
const COMPLETED_MIGRATION_IDS_KEY: string = 'completed_migration_ids';

export class BrowserMigrationRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private completedMigrationIds: string[] = [];

  async initialize(): Promise<string[]> {
    const store = await this.getStore();
    this.completedMigrationIds = this.normalizeMigrationIds(
      store.getSync(COMPLETED_MIGRATION_IDS_KEY, JSON.stringify([]))
    );
    return this.listCompletedMigrationIds();
  }

  listCompletedMigrationIds(): string[] {
    return this.completedMigrationIds.slice();
  }

  hasCompleted(migrationId: string): boolean {
    const normalizedId = migrationId.trim();
    return normalizedId.length > 0 && this.completedMigrationIds.indexOf(normalizedId) >= 0;
  }

  async markCompleted(migrationId: string): Promise<string[]> {
    const normalizedId = migrationId.trim();
    if (normalizedId.length === 0 || this.hasCompleted(normalizedId)) {
      return this.listCompletedMigrationIds();
    }
    this.completedMigrationIds = this.completedMigrationIds.concat([normalizedId]);
    const store = await this.getStore();
    store.putSync(COMPLETED_MIGRATION_IDS_KEY, JSON.stringify(this.completedMigrationIds));
    store.flushSync();
    return this.listCompletedMigrationIds();
  }

  private normalizeMigrationIds(value: preferences.ValueType): string[] {
    try {
      const parsed = JSON.parse(String(value)) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const result: string[] = [];
      for (let index = 0; index < parsed.length; index++) {
        const normalizedItem = `${parsed[index]}`.trim();
        if (normalizedItem.length > 0 && result.indexOf(normalizedItem) < 0) {
          result.push(normalizedItem);
        }
      }
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

export const SYNC_SETTINGS_REFRESH_REVISION_KEY: string = 'aira.sync.settings.refreshRevision';

export class SyncSettingsRefreshSignal {
  bump(): number {
    const nextRevision = (AppStorage.get<number>(SYNC_SETTINGS_REFRESH_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(SYNC_SETTINGS_REFRESH_REVISION_KEY, nextRevision);
    return nextRevision;
  }
}

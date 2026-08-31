export interface SettingsChangelogState {
  title: string;
}

export class SettingsChangelogViewModel {
  buildState(): SettingsChangelogState {
    return {
      title: '更新日志'
    };
  }
}

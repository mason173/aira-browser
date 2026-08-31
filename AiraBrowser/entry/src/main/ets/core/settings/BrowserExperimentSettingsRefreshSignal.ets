export const BROWSER_EXPERIMENT_SETTINGS_REFRESH_REVISION_KEY: string =
  'aira.browser.experiments.refreshRevision';

export class BrowserExperimentSettingsRefreshSignal {
  bump(): number {
    const nextRevision = (AppStorage.get<number>(BROWSER_EXPERIMENT_SETTINGS_REFRESH_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(BROWSER_EXPERIMENT_SETTINGS_REFRESH_REVISION_KEY, nextRevision);
    return nextRevision;
  }
}

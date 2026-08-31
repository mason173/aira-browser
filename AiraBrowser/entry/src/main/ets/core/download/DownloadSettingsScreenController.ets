export type DownloadSettingsBackHandler = () => boolean;

export class DownloadSettingsScreenController {
  private backHandler?: DownloadSettingsBackHandler;

  setBackHandler(handler?: DownloadSettingsBackHandler): void {
    this.backHandler = handler;
  }

  handleBackPress(): boolean {
    return this.backHandler?.() ?? false;
  }
}

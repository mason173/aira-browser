export const BROWSER_PRIVATE_FOREGROUND_REVISION_KEY: string = 'aira.browser.private.foregroundRevision';
export const BROWSER_PRIVATE_BACKGROUND_REVISION_KEY: string = 'aira.browser.private.backgroundRevision';

export class BrowserPrivateModeForegroundSignal {
  static markBackground(): number {
    const nextRevision = (AppStorage.get<number>(BROWSER_PRIVATE_BACKGROUND_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(BROWSER_PRIVATE_BACKGROUND_REVISION_KEY, nextRevision);
    return nextRevision;
  }

  static markForeground(): number {
    const nextRevision = (AppStorage.get<number>(BROWSER_PRIVATE_FOREGROUND_REVISION_KEY) ?? 0) + 1;
    AppStorage.setOrCreate(BROWSER_PRIVATE_FOREGROUND_REVISION_KEY, nextRevision);
    return nextRevision;
  }
}

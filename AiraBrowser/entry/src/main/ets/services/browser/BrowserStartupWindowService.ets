import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserShellFamily } from '../../core/browser/BrowserWindowPresentationProfile';

/** Applies the initial PC window size once, before the first page is loaded. */
export class BrowserStartupWindowService {
  async maximizeForDesktopStartup(
    mainWindow: window.Window,
    shellFamily: BrowserShellFamily | undefined
  ): Promise<boolean> {
    if (shellFamily !== 'large_screen') {
      return false;
    }
    try {
      // Only free floating windows need a default size. Preserve explicit
      // split-screen launches and windows that already fill the display.
      if (!mainWindow.isInFreeWindowMode() ||
        mainWindow.getWindowStatus() !== window.WindowStatusType.FLOATING) {
        return false;
      }
      // maximize() defaults to immersive fullscreen; EXIT_IMMERSIVE keeps
      // the normal system window controls and Dock available.
      await mainWindow.maximize(window.MaximizePresentation.EXIT_IMMERSIVE);
      return true;
    } catch (error) {
      hilog.warn(0x0000, 'AiraBrowser', 'Startup window maximization skipped: %{public}s', JSON.stringify(error));
      return false;
    }
  }
}

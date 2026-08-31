import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { resolveWindowTopSafeInsetVp } from '../../core/browser/BrowserWindowAvoidAreaCoordinator';

export class SettingsTopSafeInsetService {
  resolve(hostContext: common.UIAbilityContext): Promise<number> {
    return window.getLastWindow(hostContext)
      .then((mainWindow: window.Window) => {
        return resolveWindowTopSafeInsetVp(mainWindow);
      })
      .catch((_error: Error) => 0);
  }
}

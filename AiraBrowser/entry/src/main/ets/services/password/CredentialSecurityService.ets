import { window } from '@kit.ArkUI';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

export class CredentialSecurityService {
  async setPasswordWindowPrivacyMode(enabled: boolean): Promise<boolean> {
    try {
      if (!AppRuntimeContext.hasUIAbilityContext()) {
        return false;
      }
      const mainWindow = await window.getLastWindow(AppRuntimeContext.getUIAbilityContext());
      await mainWindow.setWindowPrivacyMode(enabled);
      return true;
    } catch (_error) {
      return false;
    }
  }
}

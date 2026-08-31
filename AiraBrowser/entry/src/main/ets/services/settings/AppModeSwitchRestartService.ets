import { Want } from '@kit.AbilityKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { APP_BUNDLE_NAME } from '../../common/constants/AppVersionInfo';

const APP_SETTINGS_RESTART_DELAY_MS: number = 500;

export class AppModeSwitchRestartService {
  private restartTimer?: number;

  scheduleRestart(): void {
    if (this.restartTimer !== undefined) {
      clearTimeout(this.restartTimer);
    }
    this.restartTimer = setTimeout((): void => {
      this.restartTimer = undefined;
      this.restartApp();
    }, APP_SETTINGS_RESTART_DELAY_MS);
  }

  scheduleRestartForModeSwitch(): void {
    this.scheduleRestart();
  }

  private restartApp(): void {
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: 'EntryAbility'
    };
    try {
      AppRuntimeContext.getApplicationContext().restartApp(want);
    } catch (_restartError) {
      try {
        AppRuntimeContext.getUIAbilityContext().terminateSelf();
      } catch (_terminateError) {
      }
    }
  }
}

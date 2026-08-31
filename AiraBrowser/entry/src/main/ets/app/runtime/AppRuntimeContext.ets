import { common } from '@kit.AbilityKit';

export class AppRuntimeContext {
  private static applicationContext?: common.ApplicationContext;
  private static uiAbilityContext?: common.UIAbilityContext;

  static setApplicationContext(applicationContext: common.ApplicationContext): void {
    AppRuntimeContext.applicationContext = applicationContext;
  }

  static hasApplicationContext(): boolean {
    return AppRuntimeContext.applicationContext !== undefined;
  }

  static getApplicationContext(): common.ApplicationContext {
    if (AppRuntimeContext.applicationContext === undefined) {
      throw new Error('Application context has not been initialized.');
    }

    return AppRuntimeContext.applicationContext;
  }

  static setUIAbilityContext(uiAbilityContext: common.UIAbilityContext): void {
    AppRuntimeContext.uiAbilityContext = uiAbilityContext;
  }

  static hasUIAbilityContext(): boolean {
    return AppRuntimeContext.uiAbilityContext !== undefined;
  }

  static getUIAbilityContext(): common.UIAbilityContext {
    if (AppRuntimeContext.uiAbilityContext === undefined) {
      throw new Error('UI ability context has not been initialized.');
    }

    return AppRuntimeContext.uiAbilityContext;
  }
}

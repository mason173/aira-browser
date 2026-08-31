import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export const BROWSER_STATUS_BAR_DARK_CONTENT_COLOR: string = '#FF000000';
export const BROWSER_STATUS_BAR_LIGHT_CONTENT_COLOR: string = '#FFFFFFFF';
const BROWSER_STATUS_BAR_TRANSPARENT_COLOR: string = '#00000000';
const NOVEL_READER_STATUS_BAR_SOURCE: string = 'novel-reader-setting';

export class BrowserStatusBarStyleService {
  private lightContentActive: boolean = false;
  private contentStyleInitialized: boolean = false;
  private applyTask: Promise<void> = Promise.resolve();

  applyLightContentStyle(
    context: common.UIAbilityContext,
    lightContentActive: boolean,
    forceApply: boolean = false
  ): void {
    if (!forceApply && this.contentStyleInitialized && this.lightContentActive === lightContentActive) {
      return;
    }
    this.contentStyleInitialized = true;
    this.lightContentActive = lightContentActive;
    const contentColor = lightContentActive
      ? BROWSER_STATUS_BAR_LIGHT_CONTENT_COLOR
      : BROWSER_STATUS_BAR_DARK_CONTENT_COLOR;
    this.applyTask = this.applyTask
      .catch((_error: Error) => {
      })
      .then(() => this.applyStatusBarContentColor(context, contentColor))
      .catch((_error: Error) => {
      });
  }

  restoreDefaultStyle(context: common.UIAbilityContext): void {
    this.applyLightContentStyle(context, false);
  }

  applyVisibility(
    context: common.UIAbilityContext,
    visible: boolean,
    source: string,
    shouldApply: () => boolean
  ): Promise<boolean> {
    return window.getLastWindow(context)
      .then((mainWindow: window.Window) => {
        if (!shouldApply()) {
          return false;
        }
        if (source !== NOVEL_READER_STATUS_BAR_SOURCE) {
          return mainWindow.setSpecificSystemBarEnabled('status', visible, true)
            .then((): boolean => true);
        }
        const enabledBars: Array<'status' | 'navigation'> = visible ? ['status'] : [];
        return mainWindow.setWindowSystemBarEnable(enabledBars)
          .then(() => {
            if (!shouldApply()) {
              return false;
            }
            return mainWindow.setSpecificSystemBarEnabled('navigationIndicator', true, false)
              .then(() => {
                if (!shouldApply()) {
                  return false;
                }
                return mainWindow.setSpecificSystemBarEnabled('status', visible, false)
                  .then((): boolean => true);
              });
          });
      });
  }

  private applyStatusBarContentColor(
    context: common.UIAbilityContext,
    contentColor: string
  ): Promise<void> {
    return window.getLastWindow(context)
      .then((mainWindow: window.Window) => {
        const properties: window.SystemBarProperties = {
          statusBarColor: BROWSER_STATUS_BAR_TRANSPARENT_COLOR,
          statusBarContentColor: contentColor,
          isStatusBarLightIcon: contentColor === BROWSER_STATUS_BAR_LIGHT_CONTENT_COLOR
        };
        return mainWindow.setWindowSystemBarProperties(properties).then(() => {
          const applied = mainWindow.getWindowSystemBarProperties();
          if (applied.statusBarContentColor !== contentColor) {
            return mainWindow.setWindowSystemBarProperties(properties);
          }
          return Promise.resolve();
        });
      });
  }
}

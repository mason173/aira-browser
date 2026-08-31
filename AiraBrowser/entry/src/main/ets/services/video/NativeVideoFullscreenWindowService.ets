import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';

export interface NativeVideoFullscreenOrientationReapplyHost {
  getContext: () => common.UIAbilityContext;
  isFullscreenActive: () => boolean;
}

const ORIENTATION_REAPPLY_FIRST_DELAY_MS: number = 120;
const ORIENTATION_REAPPLY_SECOND_DELAY_MS: number = 360;

export class NativeVideoFullscreenWindowService {
  private orientationReapplyFirstTimer: number = -1;
  private orientationReapplySecondTimer: number = -1;

  async resolveRestoreOrientation(
    context: common.UIAbilityContext,
    selectedOrientation: window.Orientation
  ): Promise<window.Orientation> {
    const followsSystem = selectedOrientation === window.Orientation.AUTO_ROTATION_RESTRICTED ||
      selectedOrientation === window.Orientation.AUTO_ROTATION_UNSPECIFIED;
    if (!followsSystem) {
      return selectedOrientation;
    }
    try {
      const mainWindow = await window.getLastWindow(context);
      const windowProperties = mainWindow.getWindowProperties();
      const currentDisplay = windowProperties.displayId === undefined ?
        display.getDefaultDisplaySync() :
        display.getDisplayByIdSync(windowProperties.displayId);
      return this.resolveSystemRestoreOrientation(currentDisplay.orientation);
    } catch (_error) {
      return window.Orientation.AUTO_ROTATION_UNSPECIFIED;
    }
  }

  scheduleOrientationReapply(
    orientation: window.Orientation,
    host: NativeVideoFullscreenOrientationReapplyHost
  ): void {
    this.cancelOrientationReapply();
    this.orientationReapplyFirstTimer = setTimeout(() => {
      this.orientationReapplyFirstTimer = -1;
      this.reapplyOrientation(orientation, host);
    }, ORIENTATION_REAPPLY_FIRST_DELAY_MS);
    this.orientationReapplySecondTimer = setTimeout(() => {
      this.orientationReapplySecondTimer = -1;
      this.reapplyOrientation(orientation, host);
    }, ORIENTATION_REAPPLY_SECOND_DELAY_MS);
  }

  cancelOrientationReapply(): void {
    if (this.orientationReapplyFirstTimer >= 0) {
      clearTimeout(this.orientationReapplyFirstTimer);
      this.orientationReapplyFirstTimer = -1;
    }
    if (this.orientationReapplySecondTimer >= 0) {
      clearTimeout(this.orientationReapplySecondTimer);
      this.orientationReapplySecondTimer = -1;
    }
  }

  async enterFullscreenWindow(
    context: common.UIAbilityContext,
    orientation: window.Orientation,
    restoreOrientation: window.Orientation
  ): Promise<boolean> {
    try {
      const mainWindow = await window.getLastWindow(context);
      await mainWindow.setWindowLayoutFullScreen(true);
      await mainWindow.setSpecificSystemBarEnabled('navigation', false, true);
      await mainWindow.setPreferredOrientation(orientation);
      return true;
    } catch (_error) {
      await this.restoreFullscreenWindow(context, restoreOrientation);
      return false;
    }
  }

  async restoreFullscreenWindow(
    context: common.UIAbilityContext,
    orientation: window.Orientation
  ): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(context);
      try {
        await mainWindow.setPreferredOrientation(orientation);
      } catch (_orientationError) {
      }
      try {
        await mainWindow.setSpecificSystemBarEnabled('navigation', true, true);
      } catch (_navigationError) {
      }
      try {
        await mainWindow.setWindowLayoutFullScreen(true);
      } catch (_layoutError) {
      }
    } catch (_windowError) {
    }
  }

  private reapplyOrientation(
    orientation: window.Orientation,
    host: NativeVideoFullscreenOrientationReapplyHost
  ): void {
    if (!host.isFullscreenActive()) {
      return;
    }
    window.getLastWindow(host.getContext())
      .then((mainWindow: window.Window) => {
        void mainWindow.setPreferredOrientation(orientation)
          .catch((_error: Error) => {
          });
      })
      .catch((_error: Error) => {
      });
  }

  private resolveSystemRestoreOrientation(
    orientation: display.Orientation
  ): window.Orientation {
    switch (orientation) {
      case display.Orientation.PORTRAIT:
      case display.Orientation.PORTRAIT_INVERTED:
        return window.Orientation.USER_ROTATION_PORTRAIT;
      case display.Orientation.LANDSCAPE:
      case display.Orientation.LANDSCAPE_INVERTED:
        return window.Orientation.AUTO_ROTATION_UNSPECIFIED;
      default:
        return window.Orientation.AUTO_ROTATION_UNSPECIFIED;
    }
  }
}

import {
  UserScriptInstallEntryMode,
  UserScriptInstallSheetContent
} from './UserScriptInstallSheetContent';
import { UserScriptPackageSuccessResult } from '../../../core/userscripts/UserScriptPackageLifecycleCoordinator';
import { CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct UserScriptInstallDialog {
  controller?: CustomDialogController;
  @Link installSourceUrl: string;
  entryMode: UserScriptInstallEntryMode = 'direct_web_install';
  dataScope: string = 'profile_persistent';
  privacyMode: string = 'regular';
  onRequestClose: () => void = () => {};
  onInstalled: (result: UserScriptPackageSuccessResult) => void = (_result: UserScriptPackageSuccessResult) => {};

  build() {
    Column() {
      UserScriptInstallSheetContent({
        initialSourceUrl: this.installSourceUrl,
        entryMode: this.entryMode,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        transparentSurface: true,
        onRequestClose: (): void => {
          this.onRequestClose();
        },
        onInstalled: (result: UserScriptPackageSuccessResult): void => {
          this.onInstalled(result);
        }
      })
        .width('100%')
        .height('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.onRequestClose();
    })
  }
}

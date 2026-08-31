import {
  HomeShortcutSelectionAction,
  HomeShortcutSelectionState
} from '../../../core/shortcuts/HomeShortcutSelectionCoordinator';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
import { HomeShortcutSelectionContent } from './HomeShortcutSelectionSheet';
import { CENTERED_DIALOG_TALL_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct HomeShortcutSelectionDialog {
  controller?: CustomDialogController;
  @Link state: HomeShortcutSelectionState;
  onAction: (action: HomeShortcutSelectionAction) => void = (_action: HomeShortcutSelectionAction) => {};
  onClose: () => void = () => {};
  onBack: () => void = () => {};

  build() {
    Column() {
      BrowserLargeScreenModalHeader({
        title: '添加至首页',
        dialogMode: true,
        onClose: this.onClose
      })

      HomeShortcutSelectionContent({
        state: this.state,
        layoutMode: 'large_screen',
        onAction: this.onAction
      })
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 20 })
    }
    .attributeModifier(CENTERED_DIALOG_TALL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], () => {
      this.onBack();
    })
  }
}

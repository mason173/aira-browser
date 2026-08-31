import { KeyboardAvoidMode, UIContext } from '@kit.ArkUI';

export class SettingsKeyboardAvoidModeCoordinator {
  private previousMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private sessionActive: boolean = false;

  activateCaretAwareResize(uiContext: UIContext): void {
    if (this.sessionActive) {
      return;
    }
    try {
      this.previousMode = uiContext.getKeyboardAvoidMode();
      uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE_WITH_CARET);
      this.sessionActive = true;
    } catch (_error) {
    }
  }

  restore(uiContext: UIContext): void {
    if (!this.sessionActive) {
      return;
    }
    const previousMode = this.previousMode;
    try {
      uiContext.setKeyboardAvoidMode(previousMode);
      this.sessionActive = false;
    } catch (_error) {
    }
  }
}

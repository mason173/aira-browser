import {
  BrowserHttpAuthDialogPresentation,
  BrowserSitePermissionDialogPresentation,
  BrowserWebCapabilityPromptApplicationEffect,
  BrowserWebCapabilityPromptEffectHandler,
  BrowserWebPromptDialogPresentation
} from './BrowserWebCapabilityPromptApplicationCoordinator';

export type BrowserWebCapabilityPromptMessageKind = 'helper' | 'error' | 'toast';

export interface BrowserWebCapabilityPromptEffectShell {
  applyMessage: (kind: BrowserWebCapabilityPromptMessageKind, message: string) => void;
  openJavaScriptPrompt: (presentation: BrowserWebPromptDialogPresentation) => void;
  closeJavaScriptPrompt: () => void;
  openHttpAuth: (presentation: BrowserHttpAuthDialogPresentation) => void;
  clearHttpAuth: () => void;
  closeHttpAuth: () => void;
  openSitePermission: (presentation: BrowserSitePermissionDialogPresentation) => void;
}

export class BrowserWebCapabilityPromptEffectApplication
  implements BrowserWebCapabilityPromptEffectHandler {
  private readonly presentAlertDialog: (effect: BrowserWebCapabilityPromptApplicationEffect) => void;
  private readonly shell: BrowserWebCapabilityPromptEffectShell;

  constructor(
    presentAlertDialog: (effect: BrowserWebCapabilityPromptApplicationEffect) => void,
    shell: BrowserWebCapabilityPromptEffectShell
  ) {
    this.presentAlertDialog = presentAlertDialog;
    this.shell = shell;
  }

  apply(effect: BrowserWebCapabilityPromptApplicationEffect): void {
    if (effect.type === 'message') {
      this.shell.applyMessage(effect.kind, effect.message);
      return;
    }
    this.applyDialog(effect);
  }

  private applyDialog(effect: BrowserWebCapabilityPromptApplicationEffect): void {
    if (effect.type !== 'dialog') {
      return;
    }
    const dialog = effect.dialog;
    if (dialog.action === 'open_javascript_prompt') {
      this.shell.openJavaScriptPrompt({
        title: dialog.presentation.title,
        message: dialog.presentation.message,
        defaultValue: dialog.presentation.defaultValue,
        inputValue: dialog.presentation.inputValue
      });
      return;
    }
    if (dialog.action === 'close_javascript_prompt') {
      this.shell.closeJavaScriptPrompt();
      return;
    }
    if (dialog.action === 'open_http_auth') {
      this.shell.openHttpAuth({
        host: dialog.presentation.host,
        realm: dialog.presentation.realm,
        username: dialog.presentation.username,
        password: dialog.presentation.password,
        usernameLocked: dialog.presentation.usernameLocked
      });
      return;
    }
    if (dialog.action === 'clear_http_auth') {
      this.shell.clearHttpAuth();
      return;
    }
    if (dialog.action === 'close_http_auth') {
      this.shell.closeHttpAuth();
      return;
    }
    if (dialog.action === 'open_site_permission') {
      this.shell.openSitePermission({
        title: dialog.presentation.title,
        message: dialog.presentation.message
      });
      return;
    }
    this.presentAlertDialog(effect);
  }
}

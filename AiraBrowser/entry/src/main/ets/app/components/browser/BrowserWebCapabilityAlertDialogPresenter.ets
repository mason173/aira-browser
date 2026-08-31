import {
  BrowserWebCapabilityPromptApplicationCoordinator,
  BrowserWebCapabilityPromptApplicationEffect
} from '../../../core/browser/BrowserWebCapabilityPromptApplicationCoordinator';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { WebSslWarningModel } from '../../../core/web/WebRuntimeBridge';

export class BrowserWebCapabilityAlertDialogPresenter {
  private readonly coordinator: BrowserWebCapabilityPromptApplicationCoordinator;

  constructor(coordinator: BrowserWebCapabilityPromptApplicationCoordinator) {
    this.coordinator = coordinator;
  }

  present(effect: BrowserWebCapabilityPromptApplicationEffect): void {
    if (effect.type !== 'dialog') {
      return;
    }
    const dialog = effect.dialog;
    if (dialog.action === 'open_javascript_confirm') {
      showCenteredAlertDialog({
        title: dialog.presentation.title,
        message: dialog.presentation.message,
        autoCancel: false,
        primaryButton: {
          value: '取消',
          action: () => {
            this.coordinator.cancelJavaScriptConfirm();
          }
        },
        secondaryButton: {
          value: '确定',
          action: () => {
            this.coordinator.confirmJavaScriptConfirm();
          }
        }
      });
      return;
    }
    if (dialog.action === 'open_javascript_alert') {
      showCenteredAlertDialog({
        title: dialog.presentation.title,
        message: dialog.presentation.message,
        autoCancel: false,
        primaryButton: {
          value: '知道了',
          action: () => {
            this.coordinator.confirmJavaScriptAlert();
          }
        }
      });
      return;
    }
    if (dialog.action === 'open_ssl_warning') {
      this.presentWarning(
        dialog.presentation,
        (): void => this.coordinator.cancelSslErrorWarning(dialog.tabId, true),
        (): void => this.coordinator.confirmSslErrorWarning(dialog.tabId)
      );
      return;
    }
    if (dialog.action === 'open_https_first_fallback_warning') {
      this.presentWarning(
        dialog.presentation,
        (): void => this.coordinator.cancelHttpsFirstFallbackWarning(dialog.tabId, dialog.attemptId),
        (): void => this.coordinator.confirmHttpsFirstFallbackWarning(dialog.tabId, dialog.attemptId)
      );
      return;
    }
    if (dialog.action !== 'open_system_permission_setting') {
      return;
    }
    showCenteredAlertDialog({
      title: dialog.title,
      message: dialog.message,
      autoCancel: false,
      primaryButton: {
        value: '取消',
        action: () => {
          this.coordinator.dismissPendingSystemPermissionSettingsPrompt();
        }
      },
      secondaryButton: {
        value: '去设置',
        action: () => {
          this.coordinator.requestPendingSystemPermissionSettings();
        }
      }
    });
  }

  private presentWarning(
    presentation: WebSslWarningModel,
    cancel: () => void,
    confirm: () => void
  ): void {
    showCenteredAlertDialog({
      title: presentation.title,
      message: presentation.message,
      autoCancel: false,
      primaryButton: {
        value: presentation.cancelLabel,
        action: cancel
      },
      secondaryButton: {
        value: presentation.confirmLabel,
        action: confirm
      }
    });
  }
}

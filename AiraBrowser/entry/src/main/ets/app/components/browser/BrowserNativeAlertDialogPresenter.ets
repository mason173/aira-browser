import {
  BrowserConfirmationRequest,
  BrowserConfirmationSink
} from '../../../core/browser/BrowserConfirmationSink';
import { configureCenteredAlertDialog } from '../common/CenteredDialogSurface';

export interface BrowserNativeAlertInformationPresentation {
  title: string;
  message: string;
  confirmLabel: string;
}

interface BrowserNativeAlertDialogButton {
  value: string;
  fontColor?: ResourceColor;
  action: () => void;
}

export class BrowserNativeAlertDialogPresenter implements BrowserConfirmationSink {
  confirm(presentation: BrowserConfirmationRequest): void {
    const cancel = (): void => {
      presentation.onCancel?.();
    };
    AlertDialog.show(configureCenteredAlertDialog({
      title: presentation.title,
      message: presentation.message,
      autoCancel: true,
      cancel: cancel,
      primaryButton: {
        value: presentation.cancelLabel,
        action: cancel
      },
      secondaryButton: this.buildConfirmButton(presentation)
    }));
  }

  inform(presentation: BrowserNativeAlertInformationPresentation): void {
    AlertDialog.show(configureCenteredAlertDialog({
      title: presentation.title,
      message: presentation.message,
      autoCancel: true,
      confirm: {
        value: presentation.confirmLabel,
        action: () => {
        }
      }
    }));
  }

  private buildConfirmButton(
    presentation: BrowserConfirmationRequest
  ): BrowserNativeAlertDialogButton {
    const button: BrowserNativeAlertDialogButton = {
      value: presentation.confirmLabel,
      action: presentation.onConfirm
    };
    if (presentation.confirmTone === 'warning') {
      button.fontColor = $r('sys.color.ohos_id_color_warning');
    } else if (presentation.confirmTone === 'alert') {
      button.fontColor = $r('sys.color.ohos_id_color_alert');
    }
    return button;
  }
}

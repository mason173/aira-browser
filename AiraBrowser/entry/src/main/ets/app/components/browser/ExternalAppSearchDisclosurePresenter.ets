import { ExternalAppSearchPrivateConfirmation } from '../../../services/search/ExternalAppSearchService';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';

export class ExternalAppSearchDisclosurePresenter {
  confirm(presentation: ExternalAppSearchPrivateConfirmation): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      showCenteredAlertDialog({
        title: presentation.title,
        message: presentation.message,
        autoCancel: false,
        primaryButton: {
          value: presentation.cancelLabel,
          action: () => {
            resolve(false);
          }
        },
        secondaryButton: {
          value: presentation.confirmLabel,
          action: () => {
            resolve(true);
          }
        }
      });
    });
  }
}

import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { sharedDesktopCardSearchEngineService } from '../features/desktopcard/DesktopCardSearchEngineService';

export default class AiraSearchFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    return sharedDesktopCardSearchEngineService.addForm(this.context, formId);
  }

  onCastToNormalForm(_formId: string): void {
  }

  onUpdateForm(formId: string): void {
    sharedDesktopCardSearchEngineService.refreshForm(this.context, formId);
  }

  onFormEvent(_formId: string, _message: string): void {
  }

  onRemoveForm(formId: string): void {
    sharedDesktopCardSearchEngineService.removeForm(this.context, formId);
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}

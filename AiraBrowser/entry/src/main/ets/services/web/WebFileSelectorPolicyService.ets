import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { WebFileSelectorPlan } from '../../core/web/WebRuntimeBridge';

export interface WebFileSelectionResult {
  uris: string[];
  helperMessage: string;
}

export class WebFileSelectorPolicyService {
  async pickUris(context: common.UIAbilityContext, plan: WebFileSelectorPlan): Promise<WebFileSelectionResult> {
    const documentPicker = new picker.DocumentViewPicker(context);
    if (plan.type === 'save') {
      const saveOptions = new picker.DocumentSaveOptions();
      if (plan.suggestedName.length > 0) {
        saveOptions.newFileNames = [plan.suggestedName];
      }
      if (plan.suffixFilters.length > 0) {
        saveOptions.fileSuffixChoices = plan.suffixFilters;
      }
      const uris = await documentPicker.save(saveOptions);
      return {
        uris: uris,
        helperMessage: uris.length === 0 ? '已取消选择文件' : '已选择文件'
      };
    }

    if (plan.type === 'folder_unsupported') {
      return {
        uris: [],
        helperMessage: '当前设备暂不支持网页文件夹上传。'
      };
    }

    const selectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = plan.maxSelectNumber;
    if (plan.suffixFilters.length > 0) {
      selectOptions.fileSuffixFilters = plan.suffixFilters;
    }
    const uris = await documentPicker.select(selectOptions);
    return {
      uris: uris,
      helperMessage: uris.length === 0 ? '已取消选择文件' : (uris.length > 1 ? `已选择 ${uris.length} 个文件` : '已选择文件')
    };
  }
}

import { BrowserHomepageBackdropAppearanceState } from '../../common/models/BackdropAppearanceModels';

type CustomHomepageRemoteWarmupStatus = 'saved' | 'partial' | 'failed';

export interface CustomHomepageRemoteWarmupTask {
  id: string;
  itemId: string;
  url: string;
}

export interface CustomHomepageRemoteWarmupResult {
  itemId: string;
  status: CustomHomepageRemoteWarmupStatus;
  previewUri: string;
  previewLightUri: string;
  previewDarkUri: string;
  previewLightAppearance?: BrowserHomepageBackdropAppearanceState;
  previewDarkAppearance?: BrowserHomepageBackdropAppearanceState;
  message: string;
}

export interface CustomHomepageRemoteWarmupResultInput {
  itemId: string;
  previewUri: string;
  previewLightUri: string;
  previewDarkUri: string;
  previewLightAppearance?: BrowserHomepageBackdropAppearanceState;
  previewDarkAppearance?: BrowserHomepageBackdropAppearanceState;
  failed: boolean;
}

export class CustomHomepageRemoteWarmupCoordinator {
  buildTask(itemId: string, url: string): CustomHomepageRemoteWarmupTask {
    const normalizedItemId = itemId.trim();
    const normalizedUrl = url.trim();
    return {
      id: `remote-homepage-warmup-${Date.now()}-${Math.floor(Math.random() * 1000000)}`,
      itemId: normalizedItemId,
      url: normalizedUrl
    };
  }

  buildResult(input: CustomHomepageRemoteWarmupResultInput): CustomHomepageRemoteWarmupResult {
    const previewLightUri = input.previewLightUri.trim();
    const previewDarkUri = input.previewDarkUri.trim();
    const previewUri = input.previewUri.trim().length > 0 ?
      input.previewUri.trim() :
      (previewLightUri.length > 0 ? previewLightUri : previewDarkUri);
    if (input.failed) {
      return {
        itemId: input.itemId.trim(),
        status: 'failed',
        previewUri: '',
        previewLightUri: '',
        previewDarkUri: '',
        previewLightAppearance: undefined,
        previewDarkAppearance: undefined,
        message: '主页已保存，暂时无法生成预览图'
      };
    }
    if (previewUri.length > 0) {
      return {
        itemId: input.itemId.trim(),
        status: 'saved',
        previewUri: previewUri,
        previewLightUri: previewLightUri,
        previewDarkUri: previewDarkUri,
        previewLightAppearance: input.previewLightAppearance,
        previewDarkAppearance: input.previewDarkAppearance,
        message: '主页已保存'
      };
    }
    return {
      itemId: input.itemId.trim(),
      status: 'partial',
      previewUri: previewUri,
      previewLightUri: previewLightUri,
      previewDarkUri: previewDarkUri,
      previewLightAppearance: input.previewLightAppearance,
      previewDarkAppearance: input.previewDarkAppearance,
      message: '主页已保存，预览图可稍后刷新'
    };
  }
}

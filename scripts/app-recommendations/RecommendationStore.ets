import { common } from '@kit.AbilityKit';

const APP_GALLERY_DETAIL: string = 'appgallery.huawei.com/app/detail';

export async function openRecommendedApp(context: common.UIAbilityContext, storeId: string): Promise<boolean> {
  const query = `id=${encodeURIComponent(storeId)}&channelId=SHARE&source=appshare`;
  try {
    await context.startAbility({
      action: 'ohos.want.action.appdetail',
      uri: `store://${APP_GALLERY_DETAIL}?${query}`
    });
    return true;
  } catch (_) {
    try {
      await context.openLink(`https://${APP_GALLERY_DETAIL}?${query}`);
      return true;
    } catch (_) {
      return false;
    }
  }
}

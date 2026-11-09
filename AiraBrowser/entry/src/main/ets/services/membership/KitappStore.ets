import { common } from '@kit.AbilityKit';
import { KITAPP_BUNDLE_NAME } from 'kitapp-membership';

/** Opens the public store listing without forwarding account or membership data. */
export async function openKitappStore(context: common.UIAbilityContext): Promise<boolean> {
  try {
    await context.startAbility({
      action: 'ohos.want.action.appdetail',
      uri: `store://appgallery.huawei.com/app/detail?id=${KITAPP_BUNDLE_NAME}`
    });
    return true;
  } catch (_error) {
    return false;
  }
}

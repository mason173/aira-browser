import { Want, common } from '@kit.AbilityKit';
import { commentManager } from '@kit.AppGalleryKit';
import { APP_BUNDLE_NAME } from '../../common/constants/AppVersionInfo';

export interface SystemSettingsLaunchResult {
  success: boolean;
  message: string;
}

const AIRA_APPGALLERY_REVIEW_URL: string =
  `https://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}&channelId=SHARE&source=appshare&action=write-review`;
const AIRA_APPGALLERY_REVIEW_URI: string =
  `store://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}&action=write-review`;
const AIRA_APPGALLERY_DETAIL_URI: string = `store://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}`;

export class SystemSettingsLaunchService {
  async openDefaultBrowserSettings(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const candidates: Want[] = [
      {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'default_browser_settings'
      },
      {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        moduleName: 'phone_settings'
      }
    ];

    for (let index = 0; index < candidates.length; index += 1) {
      try {
        await context.startAbility(candidates[index]);
        return {
          success: true,
          message: '已打开系统设置，请选择默认浏览器。'
        };
      } catch (_error) {
      }
    }

    return {
      success: false,
      message: '无法打开默认浏览器设置，请手动进入系统设置更改。'
    };
  }

  async openNetworkSettings(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const candidates: Want[] = [
      {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.ExternalWifiSettingsAbility',
        moduleName: 'phone_settings',
        action: 'action.settings.external_wifi'
      },
      {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        moduleName: 'phone_settings'
      }
    ];

    for (let index = 0; index < candidates.length; index += 1) {
      try {
        await context.startAbility(candidates[index]);
        return {
          success: true,
          message: '已打开系统设置，请进入 Wi-Fi 页面连接网络。'
        };
      } catch (_error) {
      }
    }

    return {
      success: false,
      message: '无法打开系统设置，请手动进入设置并连接 Wi-Fi。'
    };
  }

  async openAppPermissionSettings(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const candidates: Want[] = [
      {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        moduleName: 'phone_settings'
      }
    ];

    for (let index = 0; index < candidates.length; index += 1) {
      try {
        await context.startAbility(candidates[index]);
        return {
          success: true,
          message: '已打开系统设置，请进入 Aira 的应用权限。'
        };
      } catch (_error) {
      }
    }

    return {
      success: false,
      message: '无法打开系统设置，请手动进入设置并开启 Aira 权限。'
    };
  }

  async openExternalUrl(context: common.UIAbilityContext, url: string): Promise<SystemSettingsLaunchResult> {
    try {
      await context.openLink(url);
      return {
        success: true,
        message: '已交给系统打开。'
      };
    } catch (error) {
      return {
        success: false,
        message: `打开链接失败：${JSON.stringify(error)}`
      };
    }
  }

  async openAppReviewPage(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const reviewPageResult = await this.openAppGalleryDeepLink(context, AIRA_APPGALLERY_REVIEW_URI,
      '已打开应用市场评论页。');
    if (reviewPageResult.success) {
      return reviewPageResult;
    }

    const detailPageResult = await this.openAppGalleryDeepLink(context, AIRA_APPGALLERY_DETAIL_URI,
      '已打开应用市场详情页。');
    if (detailPageResult.success) {
      return detailPageResult;
    }

    const promptResult = await this.showAppReviewPrompt(context);
    if (promptResult.success) {
      return promptResult;
    }

    return this.openExternalUrl(context, AIRA_APPGALLERY_REVIEW_URL);
  }

  async openAppGalleryDetailPage(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const detailPageResult = await this.openAppGalleryDeepLink(
      context,
      AIRA_APPGALLERY_DETAIL_URI,
      '已打开应用市场，请升级 Aira。'
    );
    if (detailPageResult.success) {
      return detailPageResult;
    }
    return this.openExternalUrl(
      context,
      `https://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}`
    );
  }

  async showAppReviewPrompt(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    try {
      await commentManager.showCommentDialog(context);
      return {
        success: true,
        message: '已打开评分弹窗。'
      };
    } catch (_error) {
      return {
        success: false,
        message: '暂时无法打开评分弹窗。'
      };
    }
  }

  private async openAppGalleryDeepLink(
    context: common.UIAbilityContext,
    uri: string,
    successMessage: string
  ): Promise<SystemSettingsLaunchResult> {
    const want: Want = {
      action: 'ohos.want.action.appdetail',
      uri: uri
    };
    try {
      await context.startAbility(want);
      return {
        success: true,
        message: successMessage
      };
    } catch (_error) {
      return {
        success: false,
        message: '应用市场暂时无法打开。'
      };
    }
  }
}

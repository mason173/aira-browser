import { Want, common, defaultAppManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import { commentManager } from '@kit.AppGalleryKit';
import { APP_BUNDLE_NAME } from '../../common/constants/AppVersionInfo';
import { ChangelogContentService } from '../settings/ChangelogContentService';
import { sharedAppReviewPromptRepository } from '../../app/bootstrap/BrowserAppRuntime';

export interface SystemSettingsLaunchResult {
  success: boolean;
  message: string;
  errorCode?: number;
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
          message: launchText($r('app.string.settings_general_default_browser_opened'), '已打开系统设置，请选择默认浏览器。')
        };
      } catch (_error) {
      }
    }

    return {
      success: false,
      message: launchText($r('app.string.settings_general_default_browser_failed'), '无法打开默认浏览器设置，请手动进入系统设置更改。')
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
          message: resolveAppResourceText($r('app.string.settings_launch_wifi_opened'))
        };
      } catch (_error) {
      }
    }

    return {
      success: false,
      message: resolveAppResourceText($r('app.string.settings_launch_wifi_failed'))
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
          message: resolveAppResourceText($r('app.string.settings_launch_permission_opened'))
        };
      } catch (_error) {
      }
    }

    return {
      success: false,
      message: resolveAppResourceText($r('app.string.settings_launch_permission_failed'))
    };
  }

  isCurrentAppDefaultBrowser(): boolean {
    try {
      return defaultAppManager.isDefaultApplicationSync(defaultAppManager.ApplicationType.BROWSER);
    } catch (_error) {
      return false;
    }
  }

  async openExternalUrl(context: common.UIAbilityContext, url: string): Promise<SystemSettingsLaunchResult> {
    try {
      await context.openLink(url);
      return {
        success: true,
        message: resolveAppResourceText($r('app.string.external_nav_handed_to_system'))
      };
    } catch (error) {
      return {
        success: false,
        message: resolveAppResourceText($r('app.string.settings_launch_link_failed', JSON.stringify(error)))
      };
    }
  }

  async openAppReviewPage(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const result = await this.resolveAppReviewPageOpen(context);
    if (result.success) {
      sharedAppReviewPromptRepository.accept(this.resolveCurrentVersionName())
        .catch((_error: Error) => {});
    }
    return result;
  }

  async openAppGalleryDetailPage(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const detailPageResult = await this.openAppGalleryDeepLink(
      context,
      AIRA_APPGALLERY_DETAIL_URI,
      resolveAppResourceText($r('app.string.settings_launch_upgrade_opened'))
    );
    if (detailPageResult.success) {
      return detailPageResult;
    }
    return this.openExternalUrl(
      context,
      `https://appgallery.huawei.com/app/detail?id=${APP_BUNDLE_NAME}`
    );
  }

  /**
   * Opens another app's AppGallery detail page. Aira hands over a store page and
   * nothing else: it never installs anything, and it never reads whether that app
   * is already installed. The deep link is the one the store itself answers; the
   * https page is the fallback for a device whose store cannot answer it.
   */
  async openAppGalleryDetailPageForApp(
    context: common.UIAbilityContext,
    appId: string
  ): Promise<SystemSettingsLaunchResult> {
    const storeId = appId.trim();
    if (storeId.length === 0) {
      return {
        success: false,
        message: resolveAppResourceText($r('app.string.settings_launch_market_unavailable'))
      };
    }
    const detailPageResult = await this.openAppGalleryDeepLink(
      context,
      `store://appgallery.huawei.com/app/detail?id=${storeId}`,
      resolveAppResourceText($r('app.string.settings_launch_detail_opened'))
    );
    if (detailPageResult.success) {
      return detailPageResult;
    }
    return this.openExternalUrl(context, `https://appgallery.huawei.com/app/detail?id=${storeId}`);
  }

  async showAppReviewPrompt(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    try {
      await commentManager.showCommentDialog(context);
      return {
        success: true,
        message: resolveAppResourceText($r('app.string.settings_launch_rating_opened'))
      };
    } catch (error) {
      return {
        success: false,
        message: resolveAppResourceText($r('app.string.settings_launch_rating_failed')),
        errorCode: (error as BusinessError).code
      };
    }
  }

  private async resolveAppReviewPageOpen(context: common.UIAbilityContext): Promise<SystemSettingsLaunchResult> {
    const reviewPageResult = await this.openAppGalleryDeepLink(context, AIRA_APPGALLERY_REVIEW_URI,
      resolveAppResourceText($r('app.string.settings_launch_review_opened')));
    if (reviewPageResult.success) {
      return reviewPageResult;
    }

    const detailPageResult = await this.openAppGalleryDeepLink(context, AIRA_APPGALLERY_DETAIL_URI,
      resolveAppResourceText($r('app.string.settings_launch_detail_opened')));
    if (detailPageResult.success) {
      return detailPageResult;
    }

    const promptResult = await this.showAppReviewPrompt(context);
    if (promptResult.success) {
      return promptResult;
    }

    return this.openExternalUrl(context, AIRA_APPGALLERY_REVIEW_URL);
  }

  private resolveCurrentVersionName(): string {
    return new ChangelogContentService().resolveCurrentVersion().versionName;
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
        message: resolveAppResourceText($r('app.string.settings_launch_market_unavailable'))
      };
    }
  }
}

function launchText(resource: Resource, fallback: string): string {
  const resolved = resolveAppResourceText(resource);
  return resolved.length > 0 ? resolved : fallback;
}

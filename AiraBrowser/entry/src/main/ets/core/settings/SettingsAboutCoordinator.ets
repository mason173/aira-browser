import bundleManager from '@ohos.bundle.bundleManager';
import {
  APP_BUNDLE_NAME,
  APP_PREVIEW_VERSION_CODE,
  APP_PREVIEW_VERSION_NAME
} from '../../common/constants/AppVersionInfo';

export interface SettingsAboutAppIdentity {
  appName: string;
  bundleName: string;
  versionName: string;
  versionCode: string;
}

export class SettingsAboutCoordinator {
  buildAppIdentity(): SettingsAboutAppIdentity {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const bundleName = this.readText(bundleInfo.name, APP_BUNDLE_NAME);
      const versionName = this.readText(bundleInfo.versionName, APP_PREVIEW_VERSION_NAME);
      return {
        appName: 'Aira',
        bundleName,
        versionName,
        versionCode: `${bundleInfo.versionCode}`
      };
    } catch (_error) {
      return this.buildFallbackIdentity();
    }
  }

  private buildFallbackIdentity(): SettingsAboutAppIdentity {
    const fallbackBundleName = APP_BUNDLE_NAME;
    const fallbackVersionName = APP_PREVIEW_VERSION_NAME;
    return {
      appName: 'Aira',
      bundleName: fallbackBundleName,
      versionName: fallbackVersionName,
      versionCode: `${APP_PREVIEW_VERSION_CODE}`
    };
  }

  private readText(value: string, fallback: string): string {
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : fallback;
  }
}

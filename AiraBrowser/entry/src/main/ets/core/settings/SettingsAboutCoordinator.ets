import bundleManager from '@ohos.bundle.bundleManager';
import {
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
      // The installed bundle is authoritative; do not infer it from a build
      // distribution or package override.
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const bundleName = this.readText(bundleInfo.name, '');
      if (bundleName.length === 0) {
        throw new Error('BundleManager returned an empty bundle name.');
      }
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
    const fallbackVersionName = APP_PREVIEW_VERSION_NAME;
    return {
      appName: 'Aira',
      bundleName: '未知',
      versionName: fallbackVersionName,
      versionCode: `${APP_PREVIEW_VERSION_CODE}`
    };
  }

  private readText(value: string, fallback: string): string {
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : fallback;
  }
}

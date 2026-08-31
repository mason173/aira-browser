import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../theme/BrowserThemeStorageKeys';
import { ExternalAppSearchIconTargetId } from '../../common/models/BrowserModels';

export type AppChromeIconTone = 'light' | 'dark';

export class AppIconResources {
  static chromeStrokeColor(tone: AppChromeIconTone): string {
    return tone === 'dark' ? '#F7F8FA' : '#16181D';
  }

  static chromeOnStrokeColor(tone: AppChromeIconTone): string {
    return tone === 'dark' ? '#292929' : '#FFFFFF';
  }

  static chromeToneForResolvedThemeMode(resolvedMode: string): AppChromeIconTone {
    return resolvedMode === 'dark' ? 'dark' : 'light';
  }

  static currentChromeTone(): AppChromeIconTone {
    return AppIconResources.chromeToneForResolvedThemeMode(
      AppStorage.get<string>(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) ?? 'light'
    );
  }

  static externalAppSearch(targetId: ExternalAppSearchIconTargetId): Resource {
    switch (targetId) {
      case 'zhihu':
        return $r('app.media.app_external_search_zhihu');
      case 'bilibili':
        return $r('app.media.app_external_search_bilibili');
      case 'douyin':
        return $r('app.media.app_external_search_douyin');
      case 'xiaohongshu':
        return $r('app.media.app_external_search_xiaohongshu');
      case 'douban':
        return $r('app.media.app_external_search_douban');
      case 'quark':
        return $r('app.media.app_external_search_quark');
      case 'appgallery':
        return $r('app.media.app_external_search_appgallery');
      case 'jd':
        return $r('app.media.app_external_search_jd');
      case 'taobao':
        return $r('app.media.app_external_search_taobao');
      case 'pinduoduo':
        return $r('app.media.app_external_search_pinduoduo');
      case 'xianyu':
        return $r('app.media.app_external_search_xianyu');
      case 'meituan':
        return $r('app.media.app_external_search_meituan');
      case 'baidu_map':
        return $r('app.media.app_external_search_baidu_map');
      case 'qqmusic':
        return $r('app.media.app_external_search_qqmusic');
      case 'alipay':
        return $r('app.media.app_external_search_alipay');
      case 'youdao':
        return $r('app.media.app_external_search_youdao');
    }
  }
}

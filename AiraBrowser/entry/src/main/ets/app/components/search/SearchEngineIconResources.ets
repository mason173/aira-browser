import { SearchEngineId } from '../../../common/models/BrowserModels';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';

export class SearchEngineIconResources {
  static builtInIcon(engineId: SearchEngineId): Resource | undefined {
    switch (engineId) {
      case 'google':
        return $r('app.media.search_engine_google');
      case 'duckduckgo':
        return $r('app.media.search_engine_duckduckgo');
      case 'baidu':
        return $r('app.media.search_engine_baidu');
      case 'bing':
        return $r('app.media.search_engine_bing');
      case 'qihoo':
        return $r('app.media.search_engine_qihoo');
      case 'sogou':
        return $r('app.media.search_engine_sogou');
      case 'shenma':
        return $r('app.media.search_engine_shenma');
      case 'brave':
        return $r('app.media.search_engine_brave');
      case 'startpage':
        return $r('app.media.search_engine_startpage');
      case 'ecosia':
        return $r('app.media.search_engine_ecosia');
      case 'yandex':
        return $r('app.media.search_engine_yandex');
      default:
        return undefined;
    }
  }

  static menuIcon(engineId: SearchEngineId): Resource {
    return SearchEngineIconResources.builtInIcon(engineId) ?? $r('sys.symbol.magnifyingglass');
  }

  static searchEntryIcon(engineId: SearchEngineId, tone: AppChromeIconTone): Resource | undefined {
    const isDarkTone = tone === 'dark';
    switch (engineId) {
      case 'google':
        return isDarkTone ?
        $r('app.media.search_engine_search_google_chrome_dark') :
        $r('app.media.search_engine_search_google_chrome_light');
      case 'duckduckgo':
        return isDarkTone ?
        $r('app.media.search_engine_search_duckduckgo_chrome_dark') :
        $r('app.media.search_engine_search_duckduckgo_chrome_light');
      case 'baidu':
        return isDarkTone ?
        $r('app.media.search_engine_search_baidu_chrome_dark') :
        $r('app.media.search_engine_search_baidu_chrome_light');
      case 'bing':
        return isDarkTone ?
        $r('app.media.search_engine_search_bing_chrome_dark') :
        $r('app.media.search_engine_search_bing_chrome_light');
      case 'qihoo':
        return isDarkTone ?
        $r('app.media.search_engine_search_qihoo_chrome_dark') :
        $r('app.media.search_engine_search_qihoo_chrome_light');
      case 'sogou':
        return isDarkTone ?
        $r('app.media.search_engine_search_sogou_chrome_dark') :
        $r('app.media.search_engine_search_sogou_chrome_light');
      case 'shenma':
        return isDarkTone ?
        $r('app.media.search_engine_search_shenma_chrome_dark') :
        $r('app.media.search_engine_search_shenma_chrome_light');
      case 'brave':
        return isDarkTone ?
        $r('app.media.search_engine_search_brave_chrome_dark') :
        $r('app.media.search_engine_search_brave_chrome_light');
      case 'startpage':
        return isDarkTone ?
        $r('app.media.search_engine_search_startpage_chrome_dark') :
        $r('app.media.search_engine_search_startpage_chrome_light');
      case 'ecosia':
        return isDarkTone ?
        $r('app.media.search_engine_search_ecosia_chrome_dark') :
        $r('app.media.search_engine_search_ecosia_chrome_light');
      case 'yandex':
        return isDarkTone ?
        $r('app.media.search_engine_search_yandex_chrome_dark') :
        $r('app.media.search_engine_search_yandex_chrome_light');
      default:
        return undefined;
    }
  }
}

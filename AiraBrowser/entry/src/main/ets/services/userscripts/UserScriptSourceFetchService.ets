import { http } from '@kit.NetworkKit';
import urlUtils from '@ohos.url';
import { UserScriptInstallUrlService } from './UserScriptInstallUrlService';

export interface UserScriptSourceFetchResult {
  ok: boolean;
  source: string;
  errorMessage: string;
}

const USER_SCRIPT_SOURCE_FETCH_TIMEOUT_MS: number = 12000;
const MAX_USER_SCRIPT_SOURCE_BYTES: number = 5 * 1024 * 1024;
const XBEXT_BROKEN_AUTO_EXPAND_URL: string =
  'https://www.xbext.com/useful-user-scripts/automatic-expansion-of-full-text-to-read-more.user.js';
const AUTO_EXPAND_UPSTREAM_URL: string =
  'https://raw.githubusercontent.com/ViCrack/tempermonkey-script/master/' +
  '%E8%87%AA%E5%8A%A8%E5%B1%95%E5%BC%80%E5%85%A8%E6%96%87%E9%98%85%E8%AF%BB%E6%9B%B4%E5%A4%9A.user.js';
const XBEXT_MISSING_EAST_AUTO_PAGE_URL: string =
  'https://www.xbext.com/useful-user-scripts/east-auto-page-robot.user.js';
const PAGETUAL_UPSTREAM_URL: string = 'https://update.greasyfork.org/scripts/438684/Pagetual.user.js';
const SCRIPTCAT_PREVIEW_HOST: string = 'pre.scriptcat.org';
const SCRIPTCAT_STABLE_ORIGIN: string = 'https://scriptcat.org';

export class UserScriptSourceFetchService {
  private installUrlService: UserScriptInstallUrlService = new UserScriptInstallUrlService();

  async fetchSource(url: string, allowAnyHttpScriptUrl: boolean = false): Promise<UserScriptSourceFetchResult> {
    const trimmedUrl = url.trim();
    if (!this.isHttpUrl(trimmedUrl)) {
      return this.fail('请输入 http 或 https 链接。');
    }
    if (!allowAnyHttpScriptUrl && !this.installUrlService.canInstallFromUrl(trimmedUrl)) {
      return this.fail('不是可安装的 .user.js 链接。');
    }
    const sourceUrls = this.resolveCompatibleSourceUrls(trimmedUrl);
    for (let index = 0; index < sourceUrls.length; index++) {
      const result = await this.fetchExactSource(sourceUrls[index]);
      if (result.ok) {
        return result;
      }
    }
    return this.fail('下载脚本失败。');
  }

  private async fetchExactSource(url: string): Promise<UserScriptSourceFetchResult> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: USER_SCRIPT_SOURCE_FETCH_TIMEOUT_MS,
        readTimeout: USER_SCRIPT_SOURCE_FETCH_TIMEOUT_MS,
        usingCache: true,
        header: {
          'Accept': 'text/javascript,application/javascript,text/plain,*/*;q=0.8',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return this.fail('下载脚本失败。');
      }
      const source = response.result.trim();
      if (source.length === 0) {
        return this.fail('脚本内容为空。');
      }
      if (source.length > MAX_USER_SCRIPT_SOURCE_BYTES) {
        return this.fail('脚本超过 5 MB，暂不支持安装。');
      }
      return {
        ok: true,
        source: source,
        errorMessage: ''
      };
    } catch (_error) {
      return this.fail('下载脚本失败。');
    } finally {
      request.destroy();
    }
  }

  private resolveCompatibleSourceUrls(url: string): string[] {
    if (url === XBEXT_BROKEN_AUTO_EXPAND_URL) {
      return [AUTO_EXPAND_UPSTREAM_URL];
    }
    if (url === XBEXT_MISSING_EAST_AUTO_PAGE_URL) {
      return [PAGETUAL_UPSTREAM_URL];
    }
    const scriptCatStableUrl = this.resolveScriptCatStableSourceUrl(url);
    if (scriptCatStableUrl.length > 0) {
      return [url, scriptCatStableUrl];
    }
    return [url];
  }

  private resolveScriptCatStableSourceUrl(url: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(url);
      if (parsed.protocol !== 'https:' || parsed.hostname.toLowerCase() !== SCRIPTCAT_PREVIEW_HOST ||
        !/^\/scripts\/code\/\d+\/[^/]+\.user\.js$/i.test(parsed.pathname)) {
        return '';
      }
      return `${SCRIPTCAT_STABLE_ORIGIN}${parsed.pathname}${parsed.search}`;
    } catch (_error) {
      return '';
    }
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private fail(message: string): UserScriptSourceFetchResult {
    return {
      ok: false,
      source: '',
      errorMessage: message
    };
  }
}

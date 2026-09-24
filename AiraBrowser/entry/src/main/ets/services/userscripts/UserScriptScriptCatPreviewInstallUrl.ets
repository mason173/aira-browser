import urlUtils from '@ohos.url';
import { UserScriptInstallSourceAdapter } from './UserScriptInstallSourceAdapter';

const SCRIPTCAT_PREVIEW_HOST: string = 'pre.scriptcat.org';
const SCRIPTCAT_STABLE_ORIGIN: string = 'https://scriptcat.org';

export class UserScriptScriptCatPreviewInstallUrl implements UserScriptInstallSourceAdapter {
  resolveSourceUrls(url: string): string[] {
    const stableUrl = this.resolveStableSourceUrl(url.trim());
    if (stableUrl.length === 0) {
      return [];
    }
    return [url.trim(), stableUrl];
  }

  private resolveStableSourceUrl(url: string): string {
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
}

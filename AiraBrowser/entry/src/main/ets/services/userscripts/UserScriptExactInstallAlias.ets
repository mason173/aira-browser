import { UserScriptInstallSourceAdapter } from './UserScriptInstallSourceAdapter';

const XBEXT_BROKEN_AUTO_EXPAND_URL: string =
  'https://www.xbext.com/useful-user-scripts/automatic-expansion-of-full-text-to-read-more.user.js';
const AUTO_EXPAND_UPSTREAM_URL: string =
  'https://raw.githubusercontent.com/ViCrack/tempermonkey-script/master/' +
  '%E8%87%AA%E5%8A%A8%E5%B1%95%E5%BC%80%E5%85%A8%E6%96%87%E9%98%85%E8%AF%BB%E6%9B%B4%E5%A4%9A.user.js';
const XBEXT_MISSING_EAST_AUTO_PAGE_URL: string =
  'https://www.xbext.com/useful-user-scripts/east-auto-page-robot.user.js';
const PAGETUAL_UPSTREAM_URL: string = 'https://update.greasyfork.org/scripts/438684/Pagetual.user.js';

export class UserScriptExactInstallAlias implements UserScriptInstallSourceAdapter {
  resolveSourceUrls(url: string): string[] {
    const trimmed = url.trim();
    if (trimmed === XBEXT_BROKEN_AUTO_EXPAND_URL) {
      return [AUTO_EXPAND_UPSTREAM_URL];
    }
    if (trimmed === XBEXT_MISSING_EAST_AUTO_PAGE_URL) {
      return [PAGETUAL_UPSTREAM_URL];
    }
    return [];
  }
}

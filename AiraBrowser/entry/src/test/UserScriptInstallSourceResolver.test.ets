import { describe, expect, it } from '@ohos/hypium';
import { UserScriptInstallSourceResolver } from
  '../main/ets/services/userscripts/UserScriptInstallSourceResolver';

const PROXY_INSTALL_URL: string =
  'https://home.greasyfork.org.cn/zh-hans/l#/438656/%E8%87%AA%E5%8A%A8%E5%B1%95%E5%BC%80.user.js';
const DIRECT_SCRIPT_URL: string = 'https://update.greasyfork.org/scripts/438656.user.js';
const XBEXT_DEAD_URL: string =
  'https://www.xbext.com/useful-user-scripts/east-auto-page-robot.user.js';
const SCRIPTCAT_PREVIEW_URL: string = 'https://pre.scriptcat.org/scripts/code/1/demo.user.js?v=2';

export default function userScriptInstallSourceResolverTest(): void {
  describe('UserScript install source resolver', () => {
    it('keeps a direct script URL unchanged', 0, () => {
      const urls = new UserScriptInstallSourceResolver().resolveSourceUrls(DIRECT_SCRIPT_URL);

      expect(urls.length).assertEqual(1);
      expect(urls[0]).assertEqual(DIRECT_SCRIPT_URL);
    });

    it('lets the first matching adapter replace an install page', 0, () => {
      const urls = new UserScriptInstallSourceResolver().resolveSourceUrls(PROXY_INSTALL_URL);

      expect(urls.indexOf(PROXY_INSTALL_URL)).assertEqual(-1);
      expect(urls[urls.length - 1]).assertEqual('https://update.greasyfork.org/scripts/438656.user.js');
    });

    it('resolves an exact dead link without treating the whole host as special', 0, () => {
      const resolver = new UserScriptInstallSourceResolver();

      expect(resolver.resolveSourceUrls(XBEXT_DEAD_URL)[0]).assertEqual(
        'https://update.greasyfork.org/scripts/438684/Pagetual.user.js'
      );
      expect(resolver.resolveSourceUrls('https://www.xbext.com/other.user.js')[0]).assertEqual(
        'https://www.xbext.com/other.user.js'
      );
    });

    it('adds the stable ScriptCat origin only for a preview script URL', 0, () => {
      const resolver = new UserScriptInstallSourceResolver();
      const previewUrls = resolver.resolveSourceUrls(SCRIPTCAT_PREVIEW_URL);
      const stableUrl = 'https://scriptcat.org/scripts/1/demo.user.js';

      expect(previewUrls.length).assertEqual(2);
      expect(previewUrls[0]).assertEqual(SCRIPTCAT_PREVIEW_URL);
      expect(previewUrls[1]).assertEqual('https://scriptcat.org/scripts/code/1/demo.user.js?v=2');
      expect(resolver.resolveSourceUrls(stableUrl)[0]).assertEqual(stableUrl);
    });
  });
}

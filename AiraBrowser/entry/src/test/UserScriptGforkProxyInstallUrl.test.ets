import { describe, expect, it } from '@ohos/hypium';
import { UserScriptGforkProxyInstallUrl } from
  '../main/ets/services/userscripts/UserScriptGforkProxyInstallUrl';

const PROXY_INSTALL_URL: string =
  'https://home.greasyfork.org.cn/zh-hans/l#/438656/%E8%87%AA%E5%8A%A8%E5%B1%95%E5%BC%80.user.js';
const ENCODED_SCRIPT_PATH: string = '438656/%E8%87%AA%E5%8A%A8%E5%B1%95%E5%BC%80.user.js';
const FIRST_MIRROR_URL: string =
  'https://static-sg-apse1-primary-mirror-aws-s3-cloudfront-public-cdn.dahi.edu.eu.org/scripts/' +
  ENCODED_SCRIPT_PATH;
const OFFICIAL_NAMED_URL: string = `https://update.greasyfork.org/scripts/${ENCODED_SCRIPT_PATH}`;
const OFFICIAL_ID_URL: string = 'https://update.greasyfork.org/scripts/438656.user.js';

export default function userScriptGforkProxyInstallUrlTest(): void {
  describe('GFork proxy userscript install URL', () => {
    it('rewrites a hash install page to direct script URLs', 0, () => {
      const urls = new UserScriptGforkProxyInstallUrl().resolveSourceUrls(PROXY_INSTALL_URL);

      expect(urls.length).assertEqual(5);
      expect(urls[0]).assertEqual(FIRST_MIRROR_URL);
      expect(urls.indexOf(PROXY_INSTALL_URL)).assertEqual(-1);
      expect(urls.indexOf(OFFICIAL_NAMED_URL)).assertEqual(3);
      expect(urls[4]).assertEqual(OFFICIAL_ID_URL);
    });

    it('accepts the download page and an already decoded hash', 0, () => {
      const resolver = new UserScriptGforkProxyInstallUrl();
      const downloadUrl = 'https://home.greasyfork.org.cn/zh-hans/download#/438656/自动展开.user.js';
      const queryUrl = 'https://home.greasyfork.org.cn/en/download?path=438656/example.user.js';

      expect(resolver.resolveSourceUrls(downloadUrl)[0]).assertEqual(FIRST_MIRROR_URL);
      expect(resolver.resolveSourceUrls(queryUrl)[4]).assertEqual(
        'https://update.greasyfork.org/scripts/438656.user.js'
      );
    });

    it('does not rewrite an ordinary script URL or a non-script hash', 0, () => {
      const resolver = new UserScriptGforkProxyInstallUrl();

      expect(resolver.resolveSourceUrls('https://update.greasyfork.org/scripts/438656.user.js').length)
        .assertEqual(0);
      expect(resolver.resolveSourceUrls('https://home.greasyfork.org.cn/zh-hans/l').length).assertEqual(0);
      expect(resolver.resolveSourceUrls(
        'https://home.greasyfork.org.cn/zh-hans/l#/438656/../secret.user.js'
      ).length).assertEqual(0);
    });
  });
}

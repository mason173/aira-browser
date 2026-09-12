import { describe, expect, it } from '@ohos/hypium';
import { ExternalNavigationLaunchService } from
  '../main/ets/services/web/ExternalNavigationLaunchService';

export default function externalNavigationLaunchServiceTest(): void {
  describe('ExternalNavigationLaunchService', () => {
    it('classifies web and non-web schemes', 0, () => {
      const service = new ExternalNavigationLaunchService();

      expect(service.classifyUrl('https://wx.10086.cn/activity')).assertEqual('http_app_link');
      expect(service.classifyUrl('cn.10086.app://url=x')).assertEqual('deeplink');
      expect(service.classifyUrl('not a url')).assertEqual('unsupported');
    });

    it('rewrites the Android-only China Mobile scheme to the cross-platform client entry', 0, () => {
      const service = new ExternalNavigationLaunchService();

      expect(service.resolveCrossPlatformSchemeRewrite(
        'com.greenpoint://android.mc10086.activity?url=https%3A%2F%2Fh5.he.10086.cn%2Fapp'
      )).assertEqual('cn.10086.app://url=https%3A%2F%2Fh5.he.10086.cn%2Fapp');
    });

    it('leaves unrelated and already cross-platform schemes untouched', 0, () => {
      const service = new ExternalNavigationLaunchService();

      expect(service.resolveCrossPlatformSchemeRewrite('cn.10086.app://url=x')).assertEqual('');
      expect(service.resolveCrossPlatformSchemeRewrite(
        'com.greenpoint://android.mc10086.activity'
      )).assertEqual('');
      expect(service.resolveCrossPlatformSchemeRewrite('alipays://platformapi/startapp')).assertEqual('');
      expect(service.resolveCrossPlatformSchemeRewrite('')).assertEqual('');
    });
  });
}

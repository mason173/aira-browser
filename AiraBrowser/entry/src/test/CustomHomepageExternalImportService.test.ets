import { describe, expect, it } from '@ohos/hypium';
import { Want } from '@kit.AbilityKit';
import { CustomHomepageExternalImportService } from
  '../main/ets/services/customhome/CustomHomepageExternalImportService';

const LOCAL_ZIP_URI: string = 'file://com.tencent.wechat/data/storage/el2/base/cache/shared/downloads/theme.zip';
const REMOTE_ZIP_URL: string = 'https://download.example.com/releases/homepage.zip';

export default function customHomepageExternalImportServiceTest(): void {
  describe('Custom homepage external import', () => {
    it('opens a remote .zip download link in the browser instead of importing it', 0, () => {
      const service = new CustomHomepageExternalImportService();
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: REMOTE_ZIP_URL,
        type: 'general.zip-archive'
      };

      expect(service.isCandidate(want)).assertFalse();
    });

    it('does not claim a remote .zip link recognised only by its extension', 0, () => {
      const service = new CustomHomepageExternalImportService();
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: REMOTE_ZIP_URL
      };

      expect(service.isCandidate(want)).assertFalse();
    });

    it('still imports a local ZIP package open-with', 0, async () => {
      const service = new CustomHomepageExternalImportService();
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: LOCAL_ZIP_URI,
        type: 'general.zip-archive'
      };

      expect(service.isCandidate(want)).assertTrue();
      expect(await service.resolveSourceUri(want)).assertEqual(LOCAL_ZIP_URI);
    });
  });
}

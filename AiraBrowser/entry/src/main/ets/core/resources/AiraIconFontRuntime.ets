import { text } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AIRA_ICON_FONT_FAMILY,
  airaIconFontResource
} from './GeneratedAiraIconCatalog';

const DOMAIN = 0x0000;
const TAG = 'AiraIconFont';

export class AiraIconFontRuntime {
  private static fontRegistered: boolean = false;

  static registerBeforeContentLoad(): boolean {
    try {
      const fontCollection = text.FontCollection.getGlobalInstance();
      if (!AiraIconFontRuntime.fontRegistered) {
        fontCollection.loadFontSyncWithCheck(
          AIRA_ICON_FONT_FAMILY,
          airaIconFontResource()
        );
        AiraIconFontRuntime.fontRegistered = true;
      }
      hilog.info(DOMAIN, TAG, 'Loaded the Aira Operational Icon font before Window content.');
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load Aira icon fonts: %{public}s', JSON.stringify(error));
      return false;
    }
  }
}

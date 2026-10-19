import { describe, expect, it } from '@ohos/hypium';
import { ShortcutRecord } from '../main/ets/common/models/BrowserModels';
import {
  HomeShortcutOpenPlan,
  HomeShortcutOpenPolicyService,
  HomeShortcutStoreOpenPlan
} from '../main/ets/services/shortcuts/HomeShortcutOpenPolicyService';
import { resolveShortcutStoreHandoffId } from '../main/ets/services/shortcuts/ShortcutStoreHandoffCatalog';

const ACTIVE_TAB_ID: string = 'tab-1';
const RECOMMENDED_APP_STORE_URL: string = 'https://appgallery.huawei.com/app/detail?id=com.noctide.sleep';
const RECOMMENDED_APP_SHARED_STORE_URL: string =
  'https://appgallery.huawei.com/app/detail?id=com.noctide.sleep&channelId=SHARE&source=appshare';
const OTHER_APP_STORE_URL: string = 'https://appgallery.huawei.com/app/detail?id=com.example.other';
const ORDINARY_SITE_URL: string = 'https://www.example.com/';

function buildWebShortcut(id: string, url: string): ShortcutRecord {
  return {
    id: id,
    title: '格子',
    url: url,
    folderName: '',
    position: 0
  };
}

function buildSystemShortcut(id: string, url: string): ShortcutRecord {
  return {
    id: id,
    kind: 'system',
    title: '书签',
    url: url,
    folderName: '',
    position: 0
  };
}

export default function homeShortcutStoreHandoffTest() {
  const service = new HomeShortcutOpenPolicyService();

  describe('HomeShortcutOpenPolicyService', () => {
    it('hands the recommended app over to the store when the tile itself is opened', () => {
      const plan: HomeShortcutOpenPlan =
        service.buildOpenPlan(buildWebShortcut('shortcut-seed-zhihu', RECOMMENDED_APP_STORE_URL), ACTIVE_TAB_ID);
      expect(plan.kind).assertEqual('store');
      expect((plan as HomeShortcutStoreOpenPlan).storeId).assertEqual('com.noctide.sleep');
    });

    it('resolves the store page from its prefix, so a share link still hands over', () => {
      const plan: HomeShortcutOpenPlan = service.buildOpenPlan(
        buildWebShortcut('shortcut-seed-zhihu', RECOMMENDED_APP_SHARED_STORE_URL),
        ACTIVE_TAB_ID
      );
      expect(plan.kind).assertEqual('store');
    });

    it('still opens the page when the user asked for a tab', () => {
      const shortcut = buildWebShortcut('shortcut-seed-zhihu', RECOMMENDED_APP_STORE_URL);
      expect(service.buildOpenPlan(shortcut, ACTIVE_TAB_ID, 'new_tab').kind).assertEqual('web');
      expect(service.buildOpenPlan(shortcut, ACTIVE_TAB_ID, 'background_tab').kind).assertEqual('web');
    });

    it('leaves every other page on the Web path', () => {
      expect(service.buildOpenPlan(buildWebShortcut('shortcut-a', ORDINARY_SITE_URL), ACTIVE_TAB_ID).kind)
        .assertEqual('web');
      expect(service.buildOpenPlan(buildWebShortcut('shortcut-b', OTHER_APP_STORE_URL), ACTIVE_TAB_ID).kind)
        .assertEqual('web');
    });

    it('keeps an Aira entry on the System path', () => {
      const plan: HomeShortcutOpenPlan =
        service.buildOpenPlan(buildSystemShortcut('shortcut-seed-settings', 'aira://system/settings'), ACTIVE_TAB_ID);
      expect(plan.kind).assertEqual('system');
    });

    it('scopes the store page to the one app the catalog declares', () => {
      expect(resolveShortcutStoreHandoffId(RECOMMENDED_APP_STORE_URL)).assertEqual('com.noctide.sleep');
      expect(resolveShortcutStoreHandoffId(OTHER_APP_STORE_URL)).assertUndefined();
      expect(resolveShortcutStoreHandoffId(ORDINARY_SITE_URL)).assertUndefined();
      expect(resolveShortcutStoreHandoffId('   ')).assertUndefined();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  AIRA_CLIENT_UPDATE_POLICY_ENDPOINT,
  ClientUpdatePolicyHttpAdapter,
  ClientUpdatePolicyService
} from '../main/ets/services/update/ClientUpdatePolicyService';
import {
  createDefaultAiraSyncSettings
} from '../main/ets/services/sync/AiraSyncConfigStore';
import { AiraSyncSettings } from '../main/ets/common/models/AiraSyncModels';

class ClientUpdatePolicyFixtureAdapter implements ClientUpdatePolicyHttpAdapter {
  response: Object | string | null | undefined;
  lastUrl: string = '';
  lastBody?: Object;

  post(url: string, body: Object, _timeoutMs: number): Promise<Object | string | null | undefined> {
    this.lastUrl = url;
    this.lastBody = body;
    return Promise.resolve(this.response);
  }
}

function cloudSettings(): AiraSyncSettings {
  const settings = createDefaultAiraSyncSettings();
  settings.remoteKind = 'aira_cloud';
  settings.bookmarkSyncEnabled = true;
  settings.huaweiCloud.uid = 'fixture-user';
  return settings;
}

export default function clientUpdatePolicyServiceTest(): void {
  describe('ClientUpdatePolicyService', () => {
    it('requires an upgrade only for an explicit valid policy response', 0, async () => {
      const adapter = new ClientUpdatePolicyFixtureAdapter();
      adapter.response = {
        ok: true,
        policyId: 'bookmark-cutover',
        minimumVersionCode: 2147483647,
        minimumVersionName: '9.9.9',
        updateUrl: 'store://appgallery.huawei.com/app/detail?id=com.aira.browser'
      };
      const service = new ClientUpdatePolicyService(adapter);
      const state = await service.check(cloudSettings(), true);

      expect(adapter.lastUrl).assertEqual(AIRA_CLIENT_UPDATE_POLICY_ENDPOINT);
      expect((adapter.lastBody as Record<string, Object>).protocol).assertEqual('aira-cloud-bookmarks-v4');
      expect(state.required).assertTrue();
      expect(state.minimumVersionName).assertEqual('9.9.9');
      expect(state.updateUrl.startsWith('store://')).assertTrue();
    });

    it('fails open for unavailable policy responses and non-cloud providers', 0, async () => {
      const adapter = new ClientUpdatePolicyFixtureAdapter();
      adapter.response = { ok: false, code: 'temporarily_unavailable' };
      const service = new ClientUpdatePolicyService(adapter);
      const unavailable = await service.check(cloudSettings(), true);
      expect(unavailable.required).assertFalse();

      const webdavSettings = cloudSettings();
      webdavSettings.remoteKind = 'webdav';
      webdavSettings.bookmarkSyncEnabled = true;
      const webdav = await service.check(webdavSettings, true);
      expect(webdav.required).assertFalse();
    });

    it('suppresses a dismissed policy for the rest of the process', 0, async () => {
      const adapter = new ClientUpdatePolicyFixtureAdapter();
      adapter.response = {
        ok: true,
        policyId: 'bookmark-cutover',
        required: true,
        minimumVersionName: '9.9.9',
        minimumVersionCode: 2147483647
      };
      const service = new ClientUpdatePolicyService(adapter);
      const first = await service.check(cloudSettings(), true);
      expect(first.required).assertTrue();
      service.deferCurrentRequirement();
      const second = await service.check(cloudSettings(), true);
      expect(second.required).assertFalse();
    });
  });
}

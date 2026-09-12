import { describe, expect, it } from '@ohos/hypium';
import {
  StartupWelcomeIntroFacts,
  StartupWelcomeIntroViewModel
} from '../main/ets/core/onboarding/StartupWelcomeIntroViewModel';
import { hasStartupWelcomeIntroAccountOrSync } from
  '../main/ets/core/onboarding/StartupWelcomeIntroCompletionPolicy';
import { createDefaultAiraSyncSettings } from '../main/ets/services/sync/AiraSyncConfigStore';
import { AiraSyncSettings } from '../main/ets/common/models/AiraSyncModels';

export default function startupWelcomeIntroTest(): void {
  describe('StartupWelcomeIntroViewModel', () => {
    it('shows the inline Huawei button plus both self-owned providers when available', 0, () => {
      const facts: StartupWelcomeIntroFacts = {
        huaweiAccountAvailable: true,
        optionalServiceAvailable: true
      };
      const state = new StartupWelcomeIntroViewModel().buildState(facts);

      expect(state.showHuaweiLogin).assertTrue();
      expect(state.actions.length).assertEqual(2);
      expect(state.actions[0].id).assertEqual('personal_server');
      expect(state.actions[1].id).assertEqual('webdav');
      expect(state.skipActionLabel.length > 0).assertTrue();
    });

    it('hides the Huawei button on Community builds but keeps WebDAV and personal server', 0, () => {
      const state = new StartupWelcomeIntroViewModel().buildState({
        huaweiAccountAvailable: false,
        optionalServiceAvailable: true
      });

      expect(state.showHuaweiLogin).assertFalse();
      expect(state.actions.length).assertEqual(2);
      expect(state.actions[0].id).assertEqual('personal_server');
      expect(state.actions[1].id).assertEqual('webdav');
    });

    it('drops every sync entry in basic mode so no dead button is shown', 0, () => {
      const state = new StartupWelcomeIntroViewModel().buildState({
        huaweiAccountAvailable: true,
        optionalServiceAvailable: false
      });

      expect(state.showHuaweiLogin).assertFalse();
      expect(state.actions.length).assertEqual(0);
      expect(state.hero.title.length > 0).assertTrue();
    });
  });

  describe('hasStartupWelcomeIntroAccountOrSync', () => {
    it('treats a fresh install as unconfigured', 0, () => {
      expect(hasStartupWelcomeIntroAccountOrSync(createDefaultAiraSyncSettings())).assertFalse();
    });

    it('detects an active provider', 0, () => {
      const settings: AiraSyncSettings = createDefaultAiraSyncSettings();
      settings.remoteKind = 'self_hosted';
      expect(hasStartupWelcomeIntroAccountOrSync(settings)).assertTrue();
    });

    it('detects a saved WebDAV endpoint', 0, () => {
      const settings: AiraSyncSettings = createDefaultAiraSyncSettings();
      settings.webdav.endpoint = 'https://dav.example.com';
      expect(hasStartupWelcomeIntroAccountOrSync(settings)).assertTrue();
    });

    it('detects a paired personal server without an active provider', 0, () => {
      const settings: AiraSyncSettings = createDefaultAiraSyncSettings();
      settings.selfHosted = {
        baseUrl: 'https://server.example.com',
        instanceId: 'instance-1',
        protocolVersion: 1,
        credentialId: 'credential-1',
        deviceToken: 'token-1',
        deviceName: 'Aira HarmonyOS',
        remoteStatusCache: null
      };
      expect(hasStartupWelcomeIntroAccountOrSync(settings)).assertTrue();
    });

    it('detects a signed-in Huawei account', 0, () => {
      const settings: AiraSyncSettings = createDefaultAiraSyncSettings();
      settings.huaweiCloud.uid = 'huawei-uid';
      expect(hasStartupWelcomeIntroAccountOrSync(settings)).assertTrue();
    });
  });
}

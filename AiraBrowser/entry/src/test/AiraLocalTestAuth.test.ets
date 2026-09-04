import { describe, expect, it } from '@ohos/hypium';
import {
  AIRA_LOCAL_TEST_AUTH_TOKEN,
  AIRA_LOCAL_TEST_MODE,
  AIRA_LOCAL_TEST_UID,
  resolveAiraLocalTestIdentity
} from '../main/ets/common/config/AiraLocalTestAuth';

export default function airaLocalTestAuthTest(): void {
  describe('Aira local test identity', () => {
    it('keeps production defaults free of a simulated identity', 0, () => {
      if (!AIRA_LOCAL_TEST_MODE) {
        expect(resolveAiraLocalTestIdentity()).assertUndefined();
      }
    });

    it('uses the configured simulated identity when local test mode is packaged', 0, () => {
      if (AIRA_LOCAL_TEST_MODE) {
        const identity = resolveAiraLocalTestIdentity();
        expect(identity === undefined).assertFalse();
        expect(identity?.uid).assertEqual(AIRA_LOCAL_TEST_UID);
        expect(identity?.authToken).assertEqual(AIRA_LOCAL_TEST_AUTH_TOKEN);
      }
    });
  });
}

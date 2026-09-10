import { describe, expect, it } from '@ohos/hypium';
import { AiraMembershipState, buildDefaultMembershipState } from
  '../main/ets/common/models/MembershipModels';
import {
  AiraSyncProviderRuntimeState,
  AiraSyncSettings
} from '../main/ets/common/models/AiraSyncModels';
import { createDefaultAiraSyncSettings } from '../main/ets/services/sync/AiraSyncConfigStore';
import {
  AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID,
  AiraCloudBookmarkV4BootstrapRecord,
  shouldAcknowledgeNativeAiraCloudBookmarkV4Activation
} from '../main/ets/common/models/AiraCloudBookmarkV4BootstrapModels';
import {
  AiraCloudBookmarkV4BootstrapPolicyService
} from '../main/ets/core/sync/AiraCloudBookmarkV4BootstrapPolicyService';

const UID: string = 'member-uid';

function createEligibleSettings(): AiraSyncSettings {
  const settings = createDefaultAiraSyncSettings();
  settings.remoteKind = 'aira_cloud';
  settings.bookmarkSyncEnabled = true;
  settings.bookmarkGenerationInitializedAt = 100;
  settings.huaweiCloud.uid = UID;
  settings.huaweiCloud.lastAuthAt = 100;
  return settings;
}

function createProMembership(): AiraMembershipState {
  const state = buildDefaultMembershipState(100);
  state.userId = UID;
  state.plan = 'pro';
  state.subscriptionStatus = 'active';
  return state;
}

function createResolvedRecord(
  status: 'completed' | 'opted_out',
  cutoverId: string = AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID
): AiraCloudBookmarkV4BootstrapRecord {
  return {
    uid: UID,
    protocol: 'aira-cloud-bookmarks-v4',
    cutoverId: cutoverId,
    status: status,
    phase: status,
    backupId: '',
    backupSha256: '',
    remoteCommitId: '',
    errorMessage: '',
    updatedAt: 200,
    completedAt: 200
  };
}

export default function airaCloudBookmarkV4BootstrapPolicyTest(): void {
  describe('AiraCloudBookmarkV4BootstrapPolicyService', () => {
    const policy = new AiraCloudBookmarkV4BootstrapPolicyService();

    it('requires bootstrap for an established Pro Aira Cloud bookmark user', 0, () => {
      const result = policy.evaluate(createEligibleSettings(), createProMembership(), undefined);

      expect(result.required).assertTrue();
      expect(result.uid).assertEqual(UID);
      expect(result.reason).assertEqual('required');
    });

    it('does not gate a fresh V4 activation without an established generation', 0, () => {
      const settings = createEligibleSettings();
      settings.bookmarkGenerationInitializedAt = 0;

      const result = policy.evaluate(settings, createProMembership(), undefined);

      expect(result.required).assertFalse();
      expect(result.reason).assertEqual('not_legacy_initialized');
    });

    it('does not let a normal V4 bookmark sync marker skip the formal cutover', 0, () => {
      const settings = createEligibleSettings();
      const airaCloudState = settings.providerStates.find((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind === 'aira_cloud';
      });
      if (airaCloudState !== undefined) {
        airaCloudState.bookmark.providerIdentity = 'sync-provider-g4|aira_cloud|member-uid';
        airaCloudState.bookmark.lastSuccessAt = 150;
      }

      const result = policy.evaluate(settings, createProMembership(), undefined);

      expect(result.required).assertTrue();
      expect(result.reason).assertEqual('required');
    });

    it('resolves only after the current formal cutover is completed', 0, () => {
      const result = policy.evaluate(
        createEligibleSettings(),
        createProMembership(),
        createResolvedRecord('completed')
      );

      expect(result.required).assertFalse();
      expect(result.reason).assertEqual('completed');
    });

    it('requires migration again for an older or missing cutover batch', 0, () => {
      const oldBatch = policy.evaluate(
        createEligibleSettings(),
        createProMembership(),
        createResolvedRecord('completed', 'bookmarks-v4-cutover-20260903-old')
      );
      const missingBatch = policy.evaluate(
        createEligibleSettings(),
        createProMembership(),
        createResolvedRecord('completed', '')
      );

      expect(oldBatch.required).assertTrue();
      expect(oldBatch.reason).assertEqual('required');
      expect(missingBatch.required).assertTrue();
      expect(missingBatch.reason).assertEqual('required');
    });

    it('keeps an interrupted bootstrap required after the normal V4 marker was persisted', 0, () => {
      const settings = createEligibleSettings();
      const airaCloudState = settings.providerStates.find((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind === 'aira_cloud';
      });
      if (airaCloudState !== undefined) {
        airaCloudState.bookmark.providerIdentity = 'sync-provider-g4|aira_cloud|member-uid';
        airaCloudState.bookmark.lastSuccessAt = 150;
      }
      const record: AiraCloudBookmarkV4BootstrapRecord = {
        uid: UID,
        protocol: 'aira-cloud-bookmarks-v4',
        cutoverId: '',
        status: 'running',
        phase: 'reading_remote',
        backupId: 'backup-1',
        backupSha256: 'sha256',
        remoteCommitId: 'commit-7',
        errorMessage: '',
        updatedAt: 160,
        completedAt: 0
      };

      const result = policy.evaluate(settings, createProMembership(), record);

      expect(result.required).assertTrue();
      expect(result.reason).assertEqual('required');
    });

    it('does not interrupt an established user who is switching from another provider', 0, () => {
      const settings = createEligibleSettings();
      settings.pendingBookmarkProviderSwitchFrom = 'webdav';

      const result = policy.evaluate(settings, createProMembership(), undefined);

      expect(result.required).assertFalse();
      expect(result.reason).assertEqual('provider_switch_in_progress');
    });

    it('does not treat Huawei additional backup as a provider-switch activation', 0, () => {
      const settings = createEligibleSettings();
      const huaweiState = settings.providerStates.find((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind === 'huawei_space';
      });
      if (huaweiState !== undefined) {
        huaweiState.bookmarkBackup.lastSuccessAt = 180;
      }

      const result = policy.evaluate(settings, createProMembership(), undefined);

      expect(result.required).assertTrue();
      expect(result.reason).assertEqual('required');
    });

    it('does not force V4 cutover after switching from Huawei Space onto Aira Cloud', 0, () => {
      const settings = createEligibleSettings();
      const huaweiState = settings.providerStates.find((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind === 'huawei_space';
      });
      const airaCloudState = settings.providerStates.find((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind === 'aira_cloud';
      });
      if (huaweiState !== undefined) {
        huaweiState.bookmark.lastSuccessAt = 180;
      }
      if (airaCloudState !== undefined) {
        airaCloudState.bookmark.lastSuccessAt = 220;
      }

      const result = policy.evaluate(settings, createProMembership(), undefined);

      expect(result.required).assertFalse();
      expect(result.reason).assertEqual('provider_switch_activation');
    });

    it('keeps an interrupted formal cutover required even after another provider succeeded', 0, () => {
      const settings = createEligibleSettings();
      const huaweiState = settings.providerStates.find((state: AiraSyncProviderRuntimeState): boolean => {
        return state.remoteKind === 'huawei_space';
      });
      if (huaweiState !== undefined) {
        huaweiState.bookmark.lastSuccessAt = 180;
      }
      const record: AiraCloudBookmarkV4BootstrapRecord = {
        uid: UID,
        protocol: 'aira-cloud-bookmarks-v4',
        cutoverId: AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID,
        status: 'failed',
        phase: 'failed',
        backupId: 'backup-1',
        backupSha256: 'sha256',
        remoteCommitId: 'commit-7',
        errorMessage: 'apply-failed',
        updatedAt: 160,
        completedAt: 0
      };

      const result = policy.evaluate(settings, createProMembership(), record);

      expect(result.required).assertTrue();
      expect(result.reason).assertEqual('required');
    });

    it('acknowledges first Aira Cloud write while another provider is still active', 0, () => {
      expect(shouldAcknowledgeNativeAiraCloudBookmarkV4Activation(
        'aira_cloud',
        'huawei_space',
        100,
        true
      )).assertTrue();
      expect(shouldAcknowledgeNativeAiraCloudBookmarkV4Activation(
        'aira_cloud',
        'aira_cloud',
        100,
        true
      )).assertFalse();
      expect(shouldAcknowledgeNativeAiraCloudBookmarkV4Activation(
        'aira_cloud',
        'aira_cloud',
        0,
        true
      )).assertTrue();
      expect(shouldAcknowledgeNativeAiraCloudBookmarkV4Activation(
        'aira_cloud',
        'huawei_space',
        100,
        false
      )).assertFalse();
    });

    it('does not gate non-Pro users or another active provider', 0, () => {
      const membership = createProMembership();
      membership.plan = 'guest';
      const memberResult = policy.evaluate(createEligibleSettings(), membership, undefined);
      const settings = createEligibleSettings();
      settings.remoteKind = 'webdav';
      const providerResult = policy.evaluate(settings, createProMembership(), undefined);

      expect(memberResult.required).assertFalse();
      expect(memberResult.reason).assertEqual('not_entitled');
      expect(providerResult.required).assertFalse();
      expect(providerResult.reason).assertEqual('not_active_aira_cloud');
    });

    it('keeps completed and opted-out accounts resolved', 0, () => {
      const completed = policy.evaluate(
        createEligibleSettings(),
        createProMembership(),
        createResolvedRecord('completed')
      );
      const optedOut = policy.evaluate(
        createEligibleSettings(),
        createProMembership(),
        createResolvedRecord('opted_out')
      );

      expect(completed.required).assertFalse();
      expect(completed.reason).assertEqual('completed');
      expect(optedOut.required).assertFalse();
      expect(optedOut.reason).assertEqual('opted_out');
    });

    it('ignores a completion record belonging to another account', 0, () => {
      const record = createResolvedRecord('completed');
      record.uid = 'another-uid';

      const result = policy.evaluate(createEligibleSettings(), createProMembership(), record);

      expect(result.required).assertTrue();
      expect(result.reason).assertEqual('required');
    });

    it('does not treat a fresh or disabled Aira Cloud login as a cutover candidate', 0, () => {
      const settings = createEligibleSettings();
      settings.bookmarkSyncEnabled = false;
      settings.bookmarkGenerationInitializedAt = 0;

      const result = policy.evaluate(settings, createProMembership(), undefined);

      expect(result.required).assertFalse();
      expect(result.reason).assertEqual('not_active_aira_cloud');
    });
  });
}

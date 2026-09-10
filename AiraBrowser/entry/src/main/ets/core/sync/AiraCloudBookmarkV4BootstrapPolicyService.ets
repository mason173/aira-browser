import { AiraMembershipState } from '../../common/models/MembershipModels';
import {
  AiraSyncProviderRuntimeState,
  AiraSyncSettings
} from '../../common/models/AiraSyncModels';
import {
  AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID,
  AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
  AiraCloudBookmarkV4BootstrapEligibility,
  AiraCloudBookmarkV4BootstrapEligibilityReason,
  AiraCloudBookmarkV4BootstrapRecord
} from '../../common/models/AiraCloudBookmarkV4BootstrapModels';

export class AiraCloudBookmarkV4BootstrapPolicyService {
  evaluate(
    settings: AiraSyncSettings,
    membership: AiraMembershipState,
    record?: AiraCloudBookmarkV4BootstrapRecord
  ): AiraCloudBookmarkV4BootstrapEligibility {
    const uid = settings.huaweiCloud.uid.trim();
    if (settings.remoteKind !== 'aira_cloud') {
      return this.decision(false, uid, 'not_active_aira_cloud');
    }
    if (!settings.bookmarkSyncEnabled) {
      return this.decision(false, uid, 'not_active_aira_cloud');
    }
    if (membership.plan !== 'pro') {
      return this.decision(false, uid, 'not_entitled');
    }
    if (uid.length === 0 || membership.userId.trim() !== uid) {
      return this.decision(false, uid, 'account_mismatch');
    }
    if (settings.pendingBookmarkProviderSwitchFrom !== 'none') {
      return this.decision(false, uid, 'provider_switch_in_progress');
    }
    if ((settings.bookmarkGenerationInitializedAt ?? 0) <= 0) {
      return this.decision(false, uid, 'not_legacy_initialized');
    }
    if (record !== undefined && record.uid === uid &&
      record.protocol === AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL) {
      if (record.cutoverId === AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID && record.status === 'completed') {
        return this.decision(false, uid, 'completed');
      }
      if (record.cutoverId === AIRA_CLOUD_BOOKMARK_V4_CUTOVER_ID && record.status === 'opted_out') {
        return this.decision(false, uid, 'opted_out');
      }
    }
    if (this.hasEstablishedOtherBookmarkProvider(settings) &&
      !this.hasFormalCutoverRecoveryPoint(record)) {
      return this.decision(false, uid, 'provider_switch_activation');
    }
    return this.decision(true, uid, 'required');
  }

  private hasEstablishedOtherBookmarkProvider(settings: AiraSyncSettings): boolean {
    return settings.providerStates.some((state: AiraSyncProviderRuntimeState): boolean => {
      return state.remoteKind !== 'aira_cloud' && state.bookmark.lastSuccessAt > 0;
    });
  }

  private hasFormalCutoverRecoveryPoint(record?: AiraCloudBookmarkV4BootstrapRecord): boolean {
    return record !== undefined && record.backupId.trim().length > 0;
  }

  private decision(
    required: boolean,
    uid: string,
    reason: AiraCloudBookmarkV4BootstrapEligibilityReason
  ): AiraCloudBookmarkV4BootstrapEligibility {
    return {
      required: required,
      uid: uid,
      reason: reason
    };
  }
}

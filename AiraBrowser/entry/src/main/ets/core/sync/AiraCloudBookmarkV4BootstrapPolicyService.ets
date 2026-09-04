import { AiraMembershipState } from '../../common/models/MembershipModels';
import {
  AIRA_CLOUD_BOOKMARK_SYNC_GENERATION,
  AiraSyncDomainRuntimeState,
  AiraSyncSettings,
  resolveAiraSyncDomainRuntimeState
} from '../../common/models/AiraSyncModels';
import {
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
    if (settings.remoteKind !== 'aira_cloud' || !settings.bookmarkSyncEnabled) {
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
    if (this.hasCompletedCurrentV4Sync(settings, uid)) {
      return this.decision(false, uid, 'already_v4_initialized');
    }
    if (record !== undefined && record.uid === uid &&
      record.protocol === AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL) {
      if (record.status === 'completed') {
        return this.decision(false, uid, 'completed');
      }
      if (record.status === 'opted_out') {
        return this.decision(false, uid, 'opted_out');
      }
    }
    return this.decision(true, uid, 'required');
  }

  private hasCompletedCurrentV4Sync(settings: AiraSyncSettings, uid: string): boolean {
    const state: AiraSyncDomainRuntimeState = resolveAiraSyncDomainRuntimeState(
      settings,
      'aira_cloud',
      'bookmark'
    );
    const expectedIdentity = [
      `sync-provider-g${AIRA_CLOUD_BOOKMARK_SYNC_GENERATION}`,
      'aira_cloud',
      uid
    ].map((value: string): string => encodeURIComponent(value)).join('|');
    return state.providerIdentity === expectedIdentity && state.lastSuccessAt > 0;
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

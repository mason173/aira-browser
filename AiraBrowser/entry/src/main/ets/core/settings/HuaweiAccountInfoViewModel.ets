import {
  AiraSyncSettings,
  resolveAiraHuaweiAccountIdentity
} from '../../common/models/AiraSyncModels';
import {
  AiraActivityDailyAggregate,
  AiraActivityHeatmapViewState
} from '../../common/models/ActivityModels';
import {
  AiraAccountRecognitionBadgeKind,
  AiraMembershipState
} from '../../common/models/MembershipModels';
import { AccountActivityHeatmapViewModel } from './AccountActivityHeatmapViewModel';
import { MembershipPresentationService } from '../../services/membership/MembershipPresentationService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export interface HuaweiAccountInfoRowState {
  id: string;
  title: ResourceStr;
  value: ResourceStr;
}

export interface HuaweiAccountInfoViewState {
  uid?: string;
  title: ResourceStr;
  subtitle: ResourceStr;
  recognitionInfoText: ResourceStr;
  showRecognitionInfo: boolean;
  avatarUri: string;
  recognitionBadge: AiraAccountRecognitionBadgeKind;
  activity: AiraActivityHeatmapViewState;
  rows: HuaweiAccountInfoRowState[];
  canSignOut: boolean;
}

export class HuaweiAccountInfoViewModel {
  private activityHeatmapViewModel: AccountActivityHeatmapViewModel = new AccountActivityHeatmapViewModel();
  private membershipPresentationService: MembershipPresentationService = new MembershipPresentationService();

  buildState(
    settings: AiraSyncSettings,
    membership: AiraMembershipState,
    activityTotals: AiraActivityDailyAggregate[] = []
  ): HuaweiAccountInfoViewState {
    const identity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    const uid = identity.uid;
    const displayName = identity.displayName;
    const title = displayName.length > 0 ? displayName : this.resolveUidTitle(uid);
    const membershipLabel = AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()
      ? 'Community'
      : this.resolveMembershipLabel(membership);
    const recognitionBadge = this.membershipPresentationService.resolveRecognitionBadgeKind(membership);
    const showRecognitionInfo = uid.length > 0 &&
      this.membershipPresentationService.hasInsiderRecognition(membership);
    const rows: HuaweiAccountInfoRowState[] = [
      { id: 'membership', title: $r('app.string.settings_account_version'), value: membershipLabel }
    ];
    const membershipExpiryRow = AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()
      ? undefined
      : this.buildMembershipExpiryRow(membership);
    if (membershipExpiryRow !== undefined) {
      rows.push(membershipExpiryRow);
    }
    rows.push(
      {
        id: 'displayName',
        title: $r('app.string.settings_account_nickname'),
        value: uid.length > 0 ? title : $r('app.string.settings_account_signed_out')
      },
      {
        id: 'joinedAt',
        title: $r('app.string.settings_account_joined_at'),
        value: this.formatJoinedAt(uid, membership.accountFirstSeenAt)
      },
      {
        id: 'joinedDays',
        title: $r('app.string.settings_account_joined'),
        value: this.formatJoinedDays(uid, membership.accountFirstSeenAt)
      },
      {
        id: 'uid',
        title: $r('app.string.settings_account_id'),
        value: uid.length > 0 ? uid : $r('app.string.settings_account_signed_out')
      }
    );
    return {
      uid: uid,
      title: uid.length > 0 ? title : $r('app.string.settings_account_signed_out'),
      subtitle: uid.length > 0
        ? (showRecognitionInfo
          ? $r('app.string.settings_account_insider_subtitle')
          : $r('app.string.settings_account_signed_in'))
        : $r('app.string.settings_account_signed_out_note'),
      recognitionInfoText: showRecognitionInfo ? $r('app.string.settings_account_insider_info') : '',
      showRecognitionInfo: showRecognitionInfo,
      avatarUri: identity.photoUrl,
      recognitionBadge: uid.length > 0 ? recognitionBadge : 'none',
      activity: this.activityHeatmapViewModel.buildState(activityTotals),
      rows: rows,
      canSignOut: uid.length > 0
    };
  }

  private buildMembershipExpiryRow(membership: AiraMembershipState): HuaweiAccountInfoRowState | undefined {
    if (membership.plan !== 'pro') {
      return undefined;
    }
    return {
      id: 'membershipExpiry',
      title: $r('app.string.settings_account_membership_expiry'),
      value: this.membershipPresentationService.isLongTermMember(membership)
        ? $r('app.string.settings_account_long_term')
        : $r('app.string.settings_account_valid_until', this.formatMembershipDate(membership.planExpiresAt))
    };
  }

  private formatMembershipDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.pad2(date.getMonth() + 1);
    const day = this.pad2(date.getDate());
    return `${year}-${month}-${day}`;
  }

  private resolveUidTitle(uid: string): ResourceStr {
    if (uid.length <= 0) {
      return $r('app.string.settings_account_huawei');
    }
    const suffix = uid.length > 6 ? uid.slice(uid.length - 6) : uid;
    return $r('app.string.settings_account_huawei_suffix', suffix);
  }

  private resolveMembershipLabel(membership: AiraMembershipState): ResourceStr {
    if (this.membershipPresentationService.isLongTermMember(membership)) {
      return $r('app.string.settings_account_long_term_member');
    }
    if (membership.plan === 'pro') {
      return 'Aira Pro';
    }
    return 'Aira Club';
  }

  private formatJoinedAt(uid: string, timestamp: number): ResourceStr {
    if (uid.length <= 0) {
      return $r('app.string.settings_account_signed_out');
    }
    if (timestamp <= 0) {
      return $r('app.string.settings_account_pending_sync');
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.pad2(date.getMonth() + 1);
    const day = this.pad2(date.getDate());
    return `${year}-${month}-${day}`;
  }

  private formatJoinedDays(uid: string, timestamp: number): ResourceStr {
    if (uid.length <= 0) {
      return $r('app.string.settings_account_signed_out');
    }
    if (timestamp <= 0) {
      return $r('app.string.settings_account_pending_sync');
    }
    const elapsedMs = Math.max(0, Date.now() - timestamp);
    const days = Math.floor(elapsedMs / 86400000) + 1;
    return $r('app.string.settings_account_joined_days', days);
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

}

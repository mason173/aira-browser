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
  title: string;
  value: string;
}

export interface HuaweiAccountInfoViewState {
  title: string;
  subtitle: string;
  recognitionInfoText: string;
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
    const recognitionSubtitle = this.membershipPresentationService.resolveRecognitionSubtitle(membership);
    const recognitionInfoText = this.membershipPresentationService.resolveRecognitionInfoText(membership);
    const rows: HuaweiAccountInfoRowState[] = [
      { id: 'membership', title: '当前版本', value: membershipLabel }
    ];
    const membershipExpiryRow = AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()
      ? undefined
      : this.buildMembershipExpiryRow(membership);
    if (membershipExpiryRow !== undefined) {
      rows.push(membershipExpiryRow);
    }
    rows.push(
      { id: 'displayName', title: '账号昵称', value: uid.length > 0 ? title : '未登录' },
      { id: 'joinedAt', title: '加入 Aira 时间', value: this.formatJoinedAt(uid, membership.accountFirstSeenAt) },
      { id: 'joinedDays', title: '已加入 Aira', value: this.formatJoinedDays(uid, membership.accountFirstSeenAt) },
      { id: 'uid', title: '账号 ID', value: uid.length > 0 ? uid : '未登录' }
    );
    return {
      title: uid.length > 0 ? title : '未登录',
      subtitle: uid.length > 0
        ? (recognitionSubtitle.length > 0 ? recognitionSubtitle : '华为账号已登录')
        : '本地浏览功能已全部开启，登录后可使用账号与云服务',
      recognitionInfoText: uid.length > 0 ? recognitionInfoText : '',
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
      title: '会员有效期',
      value: this.membershipPresentationService.isLongTermMember(membership)
        ? '长期有效'
        : `有效至 ${this.formatMembershipDate(membership.planExpiresAt)}`
    };
  }

  private formatMembershipDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.pad2(date.getMonth() + 1);
    const day = this.pad2(date.getDate());
    return `${year}-${month}-${day}`;
  }

  private resolveUidTitle(uid: string): string {
    if (uid.length <= 0) {
      return '华为账号';
    }
    const suffix = uid.length > 6 ? uid.slice(uid.length - 6) : uid;
    return `华为账号 ${suffix}`;
  }

  private resolveMembershipLabel(membership: AiraMembershipState): string {
    return this.membershipPresentationService.resolveVersionLabel(membership);
  }

  private formatJoinedAt(uid: string, timestamp: number): string {
    if (uid.length <= 0) {
      return '未登录';
    }
    if (timestamp <= 0) {
      return '待同步';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.pad2(date.getMonth() + 1);
    const day = this.pad2(date.getDate());
    return `${year}-${month}-${day}`;
  }

  private formatJoinedDays(uid: string, timestamp: number): string {
    if (uid.length <= 0) {
      return '未登录';
    }
    if (timestamp <= 0) {
      return '待同步';
    }
    const elapsedMs = Math.max(0, Date.now() - timestamp);
    const days = Math.floor(elapsedMs / 86400000) + 1;
    return `${days} 天`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

}

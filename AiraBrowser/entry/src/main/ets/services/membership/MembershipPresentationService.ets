import {
  AiraAccountRecognitionBadgeKind,
  AiraMembershipBadgeKind,
  AiraMembershipState
} from '../../common/models/MembershipModels';

export class MembershipPresentationService {
  hasInsiderRecognition(membership: AiraMembershipState): boolean {
    return membership.accountRecognition === 'aira_insider';
  }

  resolveRecognitionBadgeKind(membership: AiraMembershipState): AiraAccountRecognitionBadgeKind {
    return this.hasInsiderRecognition(membership) ? 'insider' : 'none';
  }

  resolveRecognitionSubtitle(membership: AiraMembershipState): string {
    return this.hasInsiderRecognition(membership) ? '感谢你帮助测试和改进 Aira' : '';
  }

  resolveRecognitionInfoText(membership: AiraMembershipState): string {
    if (!this.hasInsiderRecognition(membership)) {
      return '';
    }
    return 'INSIDER 是 Aira 官方赠送的早期参与者纪念身份，仅授予在 Aira 1.0 发布前受邀参与产品测试和改进的用户，不开放申请、购买或兑换；之后的普通问题反馈或建议不作为授予条件。';
  }

  isLongTermMember(membership: AiraMembershipState): boolean {
    return membership.plan === 'pro' &&
      membership.planExpiresAt === 0;
  }

  resolveVersionLabel(membership: AiraMembershipState): string {
    if (this.isLongTermMember(membership)) {
      return 'Aira 长期会员';
    }
    if (membership.plan === 'pro') {
      return 'Aira Pro';
    }
    return 'Aira Club';
  }

  resolveBadgeKind(membership: AiraMembershipState): AiraMembershipBadgeKind {
    if (this.isLongTermMember(membership)) {
      return 'long_term';
    }
    if (membership.plan === 'pro') {
      return 'pro';
    }
    if (membership.plan === 'club') {
      return 'club';
    }
    return 'none';
  }

  resolveAccountSubtitle(membership: AiraMembershipState): string {
    if (this.isLongTermMember(membership)) {
      return 'Aira 长期会员权益有效';
    }
    if (membership.plan === 'pro') {
      return 'Aira Pro 权益有效';
    }
    return '华为账号已登录，当前为 Aira Club';
  }
}

import { AiraMembershipState } from '../../common/models/MembershipModels';
import {
  AIRA_PRO_IAP_PLANS,
  AIRA_PRO_ONE_TIME_PLAN,
  AIRA_PRO_ONE_TIME_PRODUCT_ID,
  HuaweiIapProductPlan,
  findAiraProIapPlanByProductId
} from '../../services/membership/HuaweiIapProductCatalog';
import { MembershipPresentationService } from '../../services/membership/MembershipPresentationService';
import {
  AiraProPlanPurchaseAction,
  AiraProPurchaseAvailability,
  AiraProPurchasePolicyService
} from '../../services/membership/AiraProPurchasePolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

const AIRA_PRO_SUBSCRIPTION_ACTION_TEXT: string = '立即订阅';
const AIRA_PRO_SUBSCRIPTION_CONSENT_ACTION_TEXT: string = '同意协议后立即订阅';
const AIRA_PRO_SUBSCRIPTION_FOOTER_TEXT: string =
  '订阅为自动续费服务，实际扣费与取消规则以华为支付页面为准。';

export type AiraProOverviewPlanAction = AiraProPlanPurchaseAction;

export interface AiraProOverviewBenefitState {
  id: string;
  title: string;
  description: string;
  tutorialText: string;
}

export interface AiraProOverviewViewState {
  title: string;
  subtitle: string;
  benefits: AiraProOverviewBenefitState[];
  plans: AiraProOverviewPlanState[];
  proValue: string;
  proActivatedActionText: string;
  proLegalPromptText: string;
  proLegalAgreementTitle: string;
  proLegalRenewalTitle: string;
  proActionsEnabled: boolean;
  proSubscribeEnabled: boolean;
  lifetimeUpgradePrompt: AiraProLifetimeUpgradePromptState;
}

export interface AiraProOverviewPlanState {
  id: string;
  purchaseKind: 'subscription' | 'one_time';
  title: string;
  priceText: string;
  originalPriceText: string;
  description: string;
  badgeText: string;
  actionText: string;
  consentActionText: string;
  footerText: string;
  action: AiraProOverviewPlanAction;
}

export interface AiraProLifetimeUpgradePromptState {
  title: string;
  message: string;
  cancelLabel: string;
  manageLabel: string;
}

export class AiraProOverviewViewModel {
  private membershipPresentationService: MembershipPresentationService = new MembershipPresentationService();
  private purchasePolicyService: AiraProPurchasePolicyService = new AiraProPurchasePolicyService();
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildState(
    membershipState: AiraMembershipState,
    dataScope: string,
    privacyMode: string
  ): AiraProOverviewViewState {
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
      return this.buildCommunityState();
    }
    const purchaseAllowed = this.isEffectAllowed('membership_purchase', dataScope, privacyMode);
    const restoreAllowed = this.isEffectAllowed('membership_restore_purchase', dataScope, privacyMode);
    const subscriptionManagementAllowed = this.isEffectAllowed(
      'membership_subscription_management',
      dataScope,
      privacyMode
    );
    const plans = this.membershipPresentationService.isLongTermMember(membershipState)
      ? []
      : [
        this.buildOneTimePlanState(membershipState, purchaseAllowed),
        ...AIRA_PRO_IAP_PLANS.map((plan: HuaweiIapProductPlan) =>
          this.buildSubscriptionPlanState(plan, membershipState, purchaseAllowed))
      ];
    return {
      title: this.resolveHeroTitle(membershipState),
      subtitle: this.resolveHeroSubtitle(membershipState),
      benefits: [
        {
          id: 'cross_system_bookmark_sync',
          title: 'Aira 云跨系统书签同步',
          description: '配合浏览器插件，在不同系统间同步书签',
          tutorialText: ''
        },
        {
          id: 'page_handoff',
          title: '网页接力',
          description: '推送当前网页至其他设备',
          tutorialText: '查看教程'
        },
        {
          id: 'cross_device_tabs',
          title: '跨设备标签页',
          description: '在手机和电脑之间查看并打开在线设备的标签页',
          tutorialText: '查看教程'
        },
        {
          id: 'aira_cloud_history',
          title: 'Aira 云历史同步',
          description: '在手机和电脑之间同步浏览历史',
          tutorialText: ''
        }
      ],
      plans: plans,
      proValue: this.resolveProValue(membershipState),
      proActivatedActionText: this.resolveActivatedActionText(membershipState),
      proLegalPromptText: '我已阅读并同意',
      proLegalAgreementTitle: '会员服务协议',
      proLegalRenewalTitle: '自动续费服务协议',
      proActionsEnabled: purchaseAllowed && restoreAllowed && subscriptionManagementAllowed,
      proSubscribeEnabled: plans.some((plan: AiraProOverviewPlanState) => plan.action !== 'unavailable'),
      lifetimeUpgradePrompt: this.buildLifetimeUpgradePrompt(membershipState)
    };
  }

  private buildCommunityState(): AiraProOverviewViewState {
    return {
      title: 'Aira Community',
      subtitle: '本地浏览能力全部免费，无需会员或登录。',
      benefits: [
        {
          id: 'offline_page_save',
          title: '离线页面',
          description: '将网页保存到本机，随时离线阅读',
          tutorialText: ''
        },
        {
          id: 'userscript_install',
          title: '用户脚本',
          description: '安装并运行你自己的浏览器脚本',
          tutorialText: ''
        },
        {
          id: 'manual_element_hide',
          title: '网页元素隐藏',
          description: '按需隐藏网页中的元素和干扰内容',
          tutorialText: ''
        },
        {
          id: 'local_theme_and_search',
          title: '主题与搜索',
          description: '主题配色和搜索设置保存在本机，全部开放使用',
          tutorialText: ''
        }
      ],
      plans: [],
      proValue: '本地功能已全部开启',
      proActivatedActionText: '无需会员',
      proLegalPromptText: '',
      proLegalAgreementTitle: '',
      proLegalRenewalTitle: '',
      proActionsEnabled: false,
      proSubscribeEnabled: false,
      lifetimeUpgradePrompt: {
        title: '',
        message: '',
        cancelLabel: '',
        manageLabel: ''
      }
    };
  }

  private resolveHeroTitle(state: AiraMembershipState): string {
    return this.membershipPresentationService.isLongTermMember(state) ? 'Aira Pro 已开通' : 'Aira Pro';
  }

  private resolveHeroSubtitle(state: AiraMembershipState): string {
    if (!this.membershipPresentationService.isLongTermMember(state)) {
      return 'Aira 的本地浏览功能保持免费。Pro 用于官方 Aira 云同步与跨设备服务。';
    }
    if (this.membershipPresentationService.hasInsiderRecognition(state)) {
      return 'INSIDER 长期会员权益已生效。感谢你帮助测试和改进 Aira。';
    }
    return '长期会员权益已生效，你可以永久使用全部 Aira Pro 云服务。感谢你对 Aira 的支持。';
  }

  private buildOneTimePlanState(
    state: AiraMembershipState,
    purchaseAllowed: boolean
  ): AiraProOverviewPlanState {
    const action = this.resolveOneTimePlanAction(state, this.resolvePurchaseAvailability(purchaseAllowed));
    return {
      id: AIRA_PRO_ONE_TIME_PLAN.planId,
      purchaseKind: 'one_time',
      title: AIRA_PRO_ONE_TIME_PLAN.title,
      priceText: AIRA_PRO_ONE_TIME_PLAN.displayPrice,
      originalPriceText: '',
      description: this.buildOneTimePlanDescription(state),
      badgeText: AIRA_PRO_ONE_TIME_PLAN.badgeText,
      actionText: action === 'manage_subscription'
        ? '前往关闭自动续费'
        : `${AIRA_PRO_ONE_TIME_PLAN.displayPrice} 立即购买`,
      consentActionText: action === 'manage_subscription' ? '前往关闭自动续费' : '同意协议后立即购买',
      footerText: this.buildOneTimePlanFooter(state),
      action: action
    };
  }

  private buildSubscriptionPlanState(
    plan: HuaweiIapProductPlan,
    state: AiraMembershipState,
    purchaseAllowed: boolean
  ): AiraProOverviewPlanState {
    const action = this.purchasePolicyService.resolveSubscriptionPlanAction(
      state,
      this.resolvePurchaseAvailability(purchaseAllowed)
    );
    return {
      id: plan.period,
      purchaseKind: 'subscription',
      title: plan.title,
      priceText: plan.displayPrice,
      originalPriceText: '',
      description: plan.description,
      badgeText: plan.badgeText,
      actionText: AIRA_PRO_SUBSCRIPTION_ACTION_TEXT,
      consentActionText: AIRA_PRO_SUBSCRIPTION_CONSENT_ACTION_TEXT,
      footerText: AIRA_PRO_SUBSCRIPTION_FOOTER_TEXT,
      action: action
    };
  }

  private resolveOneTimePlanAction(
    state: AiraMembershipState,
    availability: AiraProPurchaseAvailability
  ): AiraProOverviewPlanAction {
    return this.purchasePolicyService.resolveOneTimePlanAction(state, availability);
  }

  private resolvePurchaseAvailability(purchaseAllowed: boolean): AiraProPurchaseAvailability {
    return purchaseAllowed ? 'available' : 'privacy_restricted';
  }

  private isEffectAllowed(intent: BrowserPrivacyEffectIntent, dataScope: string, privacyMode: string): boolean {
    if ((dataScope !== 'profile_persistent' && dataScope !== 'session_ephemeral') ||
      (privacyMode !== 'regular' && privacyMode !== 'private')) {
      return false;
    }
    const requestingBoundary = this.profileBoundaryService.buildBoundary({
      dataScope: dataScope,
      privacyMode: privacyMode
    });
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: 'remote_account_sync_state',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildOneTimePlanDescription(state: AiraMembershipState): string {
    if (this.purchasePolicyService.resolveOneTimePlanAction(state) === 'manage_subscription') {
      return `升级前先关闭自动续费${this.buildCurrentPeriodSuffix(state)}`;
    }
    if (state.plan === 'pro' && state.subscriptionStatus === 'cancelled') {
      return `自动续费已关闭${this.buildCurrentPeriodSuffix(state)}`;
    }
    return AIRA_PRO_ONE_TIME_PLAN.description;
  }

  private buildOneTimePlanFooter(state: AiraMembershipState): string {
    if (this.purchasePolicyService.resolveOneTimePlanAction(state) === 'manage_subscription') {
      return '购买长期会员不会自动取消华为订阅。请先关闭自动续费，避免下个周期继续扣费。';
    }
    if (state.plan === 'pro' && state.subscriptionStatus === 'cancelled') {
      return '自动续费已关闭，可立即购买长期会员；当前订阅剩余时间不折现、不退款。';
    }
    return '一次购买，不自动续费；权益不设固定到期日。';
  }

  private buildLifetimeUpgradePrompt(state: AiraMembershipState): AiraProLifetimeUpgradePromptState {
    return {
      title: '升级长期会员',
      message: `购买长期会员不会自动取消当前华为订阅。请先关闭自动续费，避免下个周期继续扣费。取消后，当前已付款权益仍保留${this.buildCurrentPeriodPromptSuffix(state)}。`,
      cancelLabel: '暂不升级',
      manageLabel: '前往关闭自动续费'
    };
  }

  private buildCurrentPeriodSuffix(state: AiraMembershipState): string {
    return state.planExpiresAt > 0 ? ` · 权益至 ${this.formatDate(state.planExpiresAt)}` : '';
  }

  private buildCurrentPeriodPromptSuffix(state: AiraMembershipState): string {
    return state.planExpiresAt > 0 ? `至 ${this.formatDate(state.planExpiresAt)}` : '到当前周期结束';
  }

  private resolveProValue(state: AiraMembershipState): string {
    if (state.plan !== 'pro') {
      return '查看';
    }
    if (this.membershipPresentationService.isLongTermMember(state)) {
      return 'Aira 长期会员权益有效';
    }
    const productTitle = this.resolveIapProductTitle(state.subscriptionProductId);
    if (state.planExpiresAt > 0) {
      return productTitle.length > 0
        ? `${productTitle} · ${this.formatDate(state.planExpiresAt)} 到期`
        : `${this.formatDate(state.planExpiresAt)} 到期`;
    }
    return productTitle.length > 0 ? `${productTitle} · 长期有效` : '长期有效';
  }

  private resolveActivatedActionText(state: AiraMembershipState): string {
    return state.plan === 'pro'
      ? `已开通 ${this.membershipPresentationService.resolveVersionLabel(state)}`
      : '已开通 Aira Pro';
  }

  private resolveIapProductTitle(productId: string): string {
    const normalized = productId.trim();
    if (normalized === AIRA_PRO_ONE_TIME_PRODUCT_ID) {
      return AIRA_PRO_ONE_TIME_PLAN.title;
    }
    return findAiraProIapPlanByProductId(normalized)?.title ?? '';
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.padTwoDigits(date.getMonth() + 1);
    const day = this.padTwoDigits(date.getDate());
    return `${year}.${month}.${day}`;
  }

  private padTwoDigits(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}

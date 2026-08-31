import { AiraMembershipState } from '../../common/models/MembershipModels';
import { MembershipPresentationService } from './MembershipPresentationService';

export type AiraProPlanPurchaseAction = 'purchase' | 'manage_subscription' | 'unavailable';
export type AiraProPurchaseAvailability = 'available' | 'privacy_restricted';

export class AiraProPurchasePolicyService {
  private membershipPresentationService: MembershipPresentationService;

  constructor(
    membershipPresentationService: MembershipPresentationService = new MembershipPresentationService()
  ) {
    this.membershipPresentationService = membershipPresentationService;
  }

  resolveOneTimePlanAction(
    state: AiraMembershipState,
    availability: AiraProPurchaseAvailability = 'available'
  ): AiraProPlanPurchaseAction {
    if (availability === 'privacy_restricted' || this.membershipPresentationService.isLongTermMember(state)) {
      return 'unavailable';
    }
    if (this.mustConfirmAutomaticRenewalStopped(state)) {
      return 'manage_subscription';
    }
    return 'purchase';
  }

  isLongTermMember(state: AiraMembershipState): boolean {
    return this.membershipPresentationService.isLongTermMember(state);
  }

  resolveSubscriptionPlanAction(
    state: AiraMembershipState,
    availability: AiraProPurchaseAvailability = 'available'
  ): AiraProPlanPurchaseAction {
    if (availability === 'privacy_restricted' || this.membershipPresentationService.isLongTermMember(state)) {
      return 'unavailable';
    }
    return this.hasCurrentIapSubscription(state) ? 'unavailable' : 'purchase';
  }

  private mustConfirmAutomaticRenewalStopped(state: AiraMembershipState): boolean {
    return state.subscriptionStatus === 'active' ||
      state.subscriptionStatus === 'grace_period' ||
      state.subscriptionStatus === 'unknown';
  }

  private hasCurrentIapSubscription(state: AiraMembershipState): boolean {
    if (state.plan !== 'pro') {
      return false;
    }
    return state.subscriptionStatus === 'active' ||
      state.subscriptionStatus === 'grace_period' ||
      state.subscriptionStatus === 'cancelled' ||
      state.subscriptionStatus === 'unknown';
  }
}

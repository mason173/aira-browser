import { JuMembershipFeature, JuMembershipOffer, JuSettingItem } from 'design';
import { createKitappAppOffer } from 'kitapp-membership';
import { AiraProOverviewViewState, AiraProOverviewPlanState, AiraProOverviewBenefitState } from './AiraProOverviewViewModel';
import { AIRA_PRO_ONE_TIME_PLAN } from '../../services/membership/HuaweiIapProductCatalog';
import { resolveAppResourceText } from '../resources/AppResourceText';

/** Adapts the existing purchase policy and live store price to the shared page. */
export function createAiraProMembershipOffer(state: AiraProOverviewViewState): JuMembershipOffer {
  const offer = createKitappAppOffer();
  const lifetime = state.plans.find((plan: AiraProOverviewPlanState): boolean => plan.id === 'one_time');
  offer.name = 'Aira Pro';
  offer.icon = $r('app.media.foreground');
  offer.summary = resolveAppResourceText(state.subtitle);
  offer.planTitle = resolveAppResourceText($r('app.string.settings_pro_status_lifetime'));
  offer.price = lifetime?.amountText ?? AIRA_PRO_ONE_TIME_PLAN.amountText;
  offer.originalPrice = lifetime ? resolveAppResourceText(lifetime.originalPriceText) : '';
  offer.period = resolveAppResourceText($r('app.string.settings_pro_shared_lifetime_period'));
  offer.features = state.benefits.map((benefit: AiraProOverviewBenefitState): JuMembershipFeature => ({
    key: benefit.id,
    title: resolveAppResourceText(benefit.title),
    icon: benefit.id === 'page_handoff' ? $r('app.media.link_01') :
      benefit.id === 'cross_device_tabs' ? $r('app.media.grid_view') :
        benefit.id === 'aira_cloud_history' ? $r('app.media.ic_clock') : $r('app.media.calendar_sync')
  }));
  offer.reviewTitle = resolveAppResourceText($r('app.string.settings_pro_review_title'));
  offer.reviews = [
    {
      key: 'bookmarks',
      author: resolveAppResourceText($r('app.string.settings_pro_review_bookmarks_author')),
      title: resolveAppResourceText($r('app.string.settings_pro_review_bookmarks_title')),
      message: resolveAppResourceText($r('app.string.settings_pro_review_bookmarks_message')),
      rating: 5
    },
    {
      key: 'tabs',
      author: resolveAppResourceText($r('app.string.settings_pro_review_tabs_author')),
      title: resolveAppResourceText($r('app.string.settings_pro_review_tabs_title')),
      message: resolveAppResourceText($r('app.string.settings_pro_review_tabs_message')),
      rating: 5
    },
    {
      key: 'reader',
      author: resolveAppResourceText($r('app.string.settings_pro_review_reader_author')),
      title: resolveAppResourceText($r('app.string.settings_pro_review_reader_title')),
      message: resolveAppResourceText($r('app.string.settings_pro_review_reader_message')),
      rating: 5
    },
    {
      key: 'filtering',
      author: resolveAppResourceText($r('app.string.settings_pro_review_filtering_author')),
      title: resolveAppResourceText($r('app.string.settings_pro_review_filtering_title')),
      message: resolveAppResourceText($r('app.string.settings_pro_review_filtering_message')),
      rating: 5
    },
    {
      key: 'offline',
      author: resolveAppResourceText($r('app.string.settings_pro_review_offline_author')),
      title: resolveAppResourceText($r('app.string.settings_pro_review_offline_title')),
      message: resolveAppResourceText($r('app.string.settings_pro_review_offline_message')),
      rating: 5
    }
  ];
  offer.purchaseNote = resolveAppResourceText($r('app.string.settings_pro_shared_purchase_note'));
  offer.priceNote = state.showMembershipStatus ? resolveAppResourceText(state.membershipStatusDetail) : '';
  offer.actionLabel = lifetime ? resolveAppResourceText(lifetime.actionText) :
    resolveAppResourceText(state.proActivatedActionText);
  offer.actionEnabled = state.proActionsEnabled && lifetime !== undefined && lifetime.action !== 'unavailable';
  return offer;
}

/** Auxiliary actions stay on the Aira tab; the suite catalog remains upstream-owned. */
export function createAiraProMembershipActions(state: AiraProOverviewViewState): JuSettingItem[] {
  const actions: JuSettingItem[] = [];
  for (const plan of state.plans) {
    if (plan.purchaseKind === 'subscription') {
      const row = new JuSettingItem('plan:' + plan.id, resolveAppResourceText(plan.title));
      row.value = plan.priceText;
      row.description = resolveAppResourceText(plan.description);
      row.enabled = state.proActionsEnabled && plan.action !== 'unavailable';
      actions.push(row);
    }
  }
  if (state.showManageSubscription) {
    actions.push(new JuSettingItem('manage_subscription',
      resolveAppResourceText($r('app.string.settings_pro_manage_subscription'))));
  }
  if (state.showMembershipRedeem) {
    actions.push(new JuSettingItem('redeem', resolveAppResourceText($r('app.string.settings_pro_redeem'))));
  }
  if (state.complimentaryClaim.entryVisible) {
    actions.push(new JuSettingItem('claim', resolveAppResourceText(state.complimentaryClaim.entryTitle)));
  }
  actions.push(new JuSettingItem('membership_terms', resolveAppResourceText(state.proLegalAgreementTitle)));
  actions.push(new JuSettingItem('auto_renewal_terms', resolveAppResourceText(state.proLegalRenewalTitle)));
  actions.push(new JuSettingItem('self_hosting', resolveAppResourceText($r('app.string.settings_pro_self_hosting_guide'))));
  for (const action of actions) {
    action.chevron = true;
    action.enabled = action.enabled && state.proActionsEnabled;
  }
  return actions;
}

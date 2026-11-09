import { KitappPurchaseConsentRequest } from 'kitapp-membership';
import { AiraAccountUnionLinkFunctionService } from '../../services/account/AiraAccountUnionLinkFunctionService';
import { AIRA_SUITE_LIFETIME_PLAN_ID, AIRA_SUITE_LIFETIME_PRODUCT_ID } from '../../services/membership/HuaweiIapProductCatalog';
import { resolveAiraLegalDocumentLink } from '../../services/legal/AiraLegalDocuments';
import { AIRA_PRO_ONE_TIME_PLAN, resolveAiraProIapPlan } from '../../services/membership/HuaweiIapProductCatalog';
import { readCachedAiraProLifetimeStorePrice, resolveAiraProLifetimePricePresentation } from '../../services/membership/AiraProStorePricePolicy';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AIRA_ENABLE_DEVELOPMENT_DIAGNOSTICS } from '../../common/config/BuildVariantFlags';
import {
  HuaweiIapProductView,
  HuaweiIapOperationResult,
  HuaweiIapPurchaseService
} from '../../services/membership/HuaweiIapPurchaseService';
import {
  HuaweiIapVerificationFunctionService,
  HuaweiIapVerificationResponseBody
} from '../../services/membership/HuaweiIapVerificationFunctionService';
import {
  isAiraProLifetimeProductId,
  isAiraProIapPlanId,
  isAiraProSellablePlanId
} from '../../services/membership/HuaweiIapProductCatalog';
import {
  AiraProPlanPurchaseAction,
  AiraProPurchasePolicyService
} from '../../services/membership/AiraProPurchasePolicyService';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { resolveAppResourceText } from '../resources/AppResourceText';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import {
  HuaweiPaymentLaunchGate,
  HuaweiPaymentLaunchHost
} from './HuaweiPaymentLaunchGate';

const HUAWEI_IAP_ALREADY_OWNS_PRODUCT_ERROR_CODE: number = 1001860051;

class PurchaseFlowHuaweiPaymentLaunchHost implements HuaweiPaymentLaunchHost {
  private host: AiraProPurchaseFlowHost;

  constructor(host: AiraProPurchaseFlowHost) {
    this.host = host;
  }

  onLaunchVisibilityChanged(visible: boolean): void {
    this.host.onHuaweiPaymentLaunchChanged(visible);
  }

  onLaunchTimedOut(): void {
    this.host.showMessage($r('app.string.membership_iap_launch_timeout'));
  }
}
const AIRA_IAP_SUBSCRIPTION_EXPIRED_CODE: string = 'subscription_expired';
const AIRA_PRO_ONE_TIME_PLAN_ID: string = 'one_time';
const LIFETIME_UPGRADE_REFRESH_DELAYS_MS: number[] = [0, 800, 1600];

export interface AiraProPurchaseFlowHost {
  onMembershipStateChanged(): void;
  onLoginRequired(): void;
  showMessage(message: ResourceStr): void;
  onHuaweiPaymentLaunchChanged(visible: boolean): void;
}

export class AiraProPurchaseFlowHostAdapter implements AiraProPurchaseFlowHost {
  private membershipStateChangedHandler: () => void;
  private loginRequiredHandler: () => void;
  private messageHandler: (message: ResourceStr) => void;
  private huaweiPaymentLaunchChangedHandler?: (visible: boolean) => void;

  constructor(
    membershipStateChangedHandler: () => void,
    loginRequiredHandler: () => void,
    messageHandler: (message: ResourceStr) => void,
    huaweiPaymentLaunchChangedHandler?: (visible: boolean) => void
  ) {
    this.membershipStateChangedHandler = membershipStateChangedHandler;
    this.loginRequiredHandler = loginRequiredHandler;
    this.messageHandler = messageHandler;
    this.huaweiPaymentLaunchChangedHandler = huaweiPaymentLaunchChangedHandler;
  }

  onMembershipStateChanged(): void {
    this.membershipStateChangedHandler();
  }

  onLoginRequired(): void {
    this.loginRequiredHandler();
  }

  showMessage(message: ResourceStr): void {
    this.messageHandler(message);
  }

  onHuaweiPaymentLaunchChanged(visible: boolean): void {
    if (this.huaweiPaymentLaunchChangedHandler !== undefined) {
      this.huaweiPaymentLaunchChangedHandler(visible);
    }
  }
}

export interface AiraProPurchaseIapAdapter {
  startProPurchase(context: common.UIAbilityContext, period?: string, uid?: string, mayLaunch?: () => boolean): Promise<HuaweiIapOperationResult>;
  queryProProducts(context: common.UIAbilityContext): Promise<HuaweiIapProductView[]>;
  restorePurchases(context: common.UIAbilityContext, suiteOnly?: boolean): Promise<HuaweiIapOperationResult>;
  finishPurchase(
    context: common.UIAbilityContext,
    purchaseData: string,
    verifiedProductType?: string
  ): Promise<void>;
  openSubscriptionManagement(context: common.UIAbilityContext): Promise<HuaweiIapOperationResult>;
}

interface VerifiedPurchaseSubmission {
  verification: HuaweiIapVerificationResponseBody;
  purchaseData: string;
}

export class AiraProPurchaseCoordinator {
  private membershipFeature?: MembershipFeature;
  private iapService: AiraProPurchaseIapAdapter;
  private verificationService: HuaweiIapVerificationFunctionService;
  private showDiagnosticMessages: boolean;
  private purchasePolicyService: AiraProPurchasePolicyService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private awaitingSubscriptionManagementReturn: boolean = false;
  private subscriptionManagementRefreshPromise?: Promise<void>;
  private purchaseLaunchInFlight: boolean = false;
  private accountUnionLinkService: AiraAccountUnionLinkFunctionService = new AiraAccountUnionLinkFunctionService();
  private purchaseConsent: KitappPurchaseConsentRequest | undefined = undefined;
  private purchaseConsentGeneration: number = 0;
  private launchGate: HuaweiPaymentLaunchGate = new HuaweiPaymentLaunchGate();
  private launchWindow?: window.Window;
  private launchWindowEventHandler?: (event: window.WindowEventType) => void;
  private launchWindowBindGeneration: number = 0;

  constructor(
    membershipFeature?: MembershipFeature,
    iapService: AiraProPurchaseIapAdapter = new HuaweiIapPurchaseService(),
    verificationService: HuaweiIapVerificationFunctionService = new HuaweiIapVerificationFunctionService(),
    showDiagnosticMessages: boolean = AIRA_ENABLE_DEVELOPMENT_DIAGNOSTICS,
    purchasePolicyService: AiraProPurchasePolicyService = new AiraProPurchasePolicyService(),
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.membershipFeature = membershipFeature;
    this.iapService = iapService;
    this.verificationService = verificationService;
    this.showDiagnosticMessages = showDiagnosticMessages;
    this.purchasePolicyService = purchasePolicyService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  async startPurchaseFlow(
    context: common.UIAbilityContext,
    period: string,
    uid: string,
    host: AiraProPurchaseFlowHost,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<void> {
    if (!this.isEffectAllowed('membership_purchase', boundaryInput)) {
      host.showMessage($r('app.string.settings_pro_purchase_private'));
      return;
    }
    if (this.purchaseLaunchInFlight) {
      return;
    }
    this.purchaseLaunchInFlight = true;
    const consentGeneration = this.purchaseConsentGeneration;
    const accountUid = this.resolveAccountUid(uid);
    const accountCurrent = this.membershipFeature?.capturePurchaseSessionGuard(accountUid) ?? ((): boolean => false);
    let launchStarted: boolean = false;
    try {
      if (period === AIRA_SUITE_LIFETIME_PLAN_ID) {
        if (!this.isBoundAccountUid(accountUid)) { host.onLoginRequired(); return; }
        // Link before reading ownership: a newly linked Huawei account may
        // already own the suite through another app.
        if (!await this.accountUnionLinkService.linkUnionId(accountUid)) {
          if (accountCurrent() && consentGeneration === this.purchaseConsentGeneration) {
            host.showMessage($r('app.string.membership_suite_link_required'));
          }
          return;
        }
      }
      if (period === AIRA_SUITE_LIFETIME_PLAN_ID &&
        (!accountCurrent() || consentGeneration !== this.purchaseConsentGeneration)) { return; }
      if (!await this.canStartPlanPurchase(period, host)) { return; }
      if (!await this.confirmPurchase(context, period, accountUid, host, boundaryInput, consentGeneration)) { return; }
      if (!accountCurrent() || consentGeneration !== this.purchaseConsentGeneration) { return; }
      this.beginHuaweiPaymentLaunch(context, host);
      launchStarted = true;
      if (this.launchGate.hasTimedOut()) { return; }
      const result = await this.startProPurchase(context, period, accountUid,
        (): boolean => accountCurrent() && consentGeneration === this.purchaseConsentGeneration);
      this.endHuaweiPaymentLaunch();
      if (!accountCurrent()) { return; }
      if (result.verificationCode === 'login_required') {
        host.onLoginRequired();
        return;
      }
      if (!(this.launchGate.hasTimedOut() && !result.ok)) {
        this.showOperationResult(host, result);
      }
      if (result.ok) {
        await this.refreshMembershipAfterPurchaseResult(
          result.verifiedProductId,
          result.verifiedExpiresAt,
          host
        );
      }
    } catch (_error) {
      if (!launchStarted || !this.launchGate.hasTimedOut()) {
        host.showMessage($r('app.string.settings_pro_purchase_unavailable'));
      }
    } finally {
      this.endHuaweiPaymentLaunch();
      this.purchaseLaunchInFlight = false;
    }
  }

  async restorePurchaseFlow(
    context: common.UIAbilityContext,
    uid: string,
    period: string,
    host: AiraProPurchaseFlowHost,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<void> {
    try {
      if (!this.isEffectAllowed('membership_restore_purchase', boundaryInput)) {
        host.showMessage($r('app.string.settings_pro_restore_private'));
        return;
      }
      const accountUid = this.resolveAccountUid(uid);
      const current = this.membershipFeature?.capturePurchaseSessionGuard(accountUid) ?? ((): boolean => false);
      if (!accountUid) { host.onLoginRequired(); return; }
      if (period === AIRA_SUITE_LIFETIME_PLAN_ID) {
        // Recovery does not charge. A failed best-effort re-link must not block
        // an existing immutable link or server-owned cross-app entitlement.
        await this.accountUnionLinkService.linkUnionId(accountUid);
      }
      if (!current()) { if (!accountUid) { host.onLoginRequired(); } return; }
      const result = await this.restorePurchase(context, accountUid, period);
      if (!current()) { return; }
      if (result.verificationCode === 'login_required') {
        host.onLoginRequired();
        return;
      }
      this.showOperationResult(host, result);
      if (result.ok || period === AIRA_SUITE_LIFETIME_PLAN_ID) {
        await this.refreshMembershipAfterPurchaseResult(
          result.verifiedProductId,
          result.verifiedExpiresAt,
          host
        );
      }
    } catch (_error) {
      host.showMessage($r('app.string.settings_pro_restore_unavailable'));
    }
  }

  async openLifetimeUpgradeSubscriptionManagement(
    context: common.UIAbilityContext,
    host: AiraProPurchaseFlowHost,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<void> {
    if (!this.isEffectAllowed('membership_subscription_management', boundaryInput)) {
      host.showMessage($r('app.string.settings_pro_manage_private'));
      return;
    }
    this.awaitingSubscriptionManagementReturn = true;
    host.showMessage($r('app.string.settings_pro_manage_hint'));
    try {
      const result = await this.manageSubscription(context);
      if (!result.ok) {
        this.awaitingSubscriptionManagementReturn = false;
        this.showOperationResult(host, result);
        return;
      }
      if (this.awaitingSubscriptionManagementReturn) {
        await this.refreshAfterSubscriptionManagement(host);
      }
    } catch (_error) {
      this.awaitingSubscriptionManagementReturn = false;
      host.showMessage($r('app.string.settings_pro_manage_unavailable'));
    }
  }

  handlePageShow(
    host: AiraProPurchaseFlowHost,
    boundaryInput: BrowserDataBoundaryInput
  ): void {
    if (!this.awaitingSubscriptionManagementReturn) {
      return;
    }
    if (!this.isEffectAllowed('membership_subscription_management', boundaryInput)) {
      this.awaitingSubscriptionManagementReturn = false;
      host.showMessage($r('app.string.settings_pro_manage_private'));
      return;
    }
    this.refreshAfterSubscriptionManagement(host).catch((_error: Error) => {
      host.showMessage($r('app.string.settings_pro_subscription_check_failed'));
    });
  }

  private async startProPurchase(
    context: common.UIAbilityContext,
    period: string = 'monthly',
    uid: string = '',
    mayLaunch: () => boolean = (): boolean => true
  ): Promise<HuaweiIapOperationResult> {
    // Monthly, yearly, and the long-term plan are all sold from the renewal
    // sheet. Permanent membership is the non-consumable aira_pro_lifetime purchase.
    if (!isAiraProSellablePlanId(period) && period.trim().toLowerCase() !== 'one_time' && period !== AIRA_SUITE_LIFETIME_PLAN_ID) {
      return this.buildUnsupportedPlanResult(period, 'purchase_pro_monthly');
    }
    if (!this.isBoundAccountUid(uid)) {
      return this.buildLoginRequiredResult(
        period.trim().toLowerCase() === 'one_time' ? 'purchase_pro_one_time' : 'purchase_pro_monthly'
      );
    }
    const current = this.membershipFeature?.capturePurchaseSessionGuard(uid) ?? ((): boolean => false);
    if (!current()) { return this.buildLoginRequiredResult('purchase_pro_one_time'); }
    this.launchGate.armCashierDetection();
    const result = await this.iapService.startProPurchase(context, period, uid, mayLaunch);
    // The cashier has returned. Drop the launch sheet before receipt verification,
    // which can take a moment and is no longer "opening Huawei payment".
    this.launchGate.finish();
    if (!current()) { return this.buildStalePurchaseResult(result); }
    if (!result.ok && result.errorCode === HUAWEI_IAP_ALREADY_OWNS_PRODUCT_ERROR_CODE) {
      const restoreResult = await this.iapService.restorePurchases(context, period === AIRA_SUITE_LIFETIME_PLAN_ID);
      const restoredResult = await this.submitPurchaseDataIfNeeded(context, restoreResult, uid, 'restore', current);
      if (!restoredResult.ok && restoredResult.verificationCode === AIRA_IAP_SUBSCRIPTION_EXPIRED_CODE) {
        return this.buildAlreadyOwnsExpiredRestoreResult(result, restoredResult);
      }
      return restoredResult;
    }
    return this.submitPurchaseDataIfNeeded(context, result, uid, 'purchase', current);
  }

  private beginHuaweiPaymentLaunch(context: common.UIAbilityContext, host: AiraProPurchaseFlowHost): void {
    this.launchGate.begin(new PurchaseFlowHuaweiPaymentLaunchHost(host));
    this.bindLaunchWindow(context);
  }

  private endHuaweiPaymentLaunch(): void {
    this.unbindLaunchWindow();
    this.launchGate.finish();
  }

  private bindLaunchWindow(context: common.UIAbilityContext): void {
    const generation = ++this.launchWindowBindGeneration;
    try {
      window.getLastWindow(context).then((mainWindow: window.Window) => {
        if (generation !== this.launchWindowBindGeneration || !this.launchGate.isActive()) {
          return;
        }
        const handler = (event: window.WindowEventType): void => {
          this.handleLaunchWindowEvent(event);
        };
        this.launchWindow = mainWindow;
        this.launchWindowEventHandler = handler;
        mainWindow.on('windowEvent', handler);
      }).catch((_error: Error) => {
      });
    } catch (_error) {
    }
  }

  private unbindLaunchWindow(): void {
    this.launchWindowBindGeneration++;
    const mainWindow = this.launchWindow;
    const handler = this.launchWindowEventHandler;
    this.launchWindow = undefined;
    this.launchWindowEventHandler = undefined;
    if (mainWindow === undefined || handler === undefined) {
      return;
    }
    try {
      mainWindow.off('windowEvent', handler);
    } catch (_error) {
    }
  }

  private handleLaunchWindowEvent(event: window.WindowEventType): void {
    if (event === window.WindowEventType.WINDOW_INACTIVE || event === window.WindowEventType.WINDOW_HIDDEN) {
      this.launchGate.noteWindowInactive();
      return;
    }
    if (event === window.WindowEventType.WINDOW_ACTIVE || event === window.WindowEventType.WINDOW_SHOWN) {
      this.launchGate.noteWindowActive();
    }
  }

  queryProProducts(context: common.UIAbilityContext): Promise<HuaweiIapProductView[]> {
    return this.iapService.queryProProducts(context);
  }

  private async restorePurchase(
    context: common.UIAbilityContext,
    uid: string = '',
    period: string = 'monthly'
  ): Promise<HuaweiIapOperationResult> {
    if (!isAiraProIapPlanId(period)) {
      return this.buildUnsupportedPlanResult(period, 'restore_purchase');
    }
    if (!this.isBoundAccountUid(uid)) {
      return this.buildLoginRequiredResult('restore_purchase');
    }
    const current = this.membershipFeature?.capturePurchaseSessionGuard(uid) ?? ((): boolean => false);
    if (!current()) { return this.buildLoginRequiredResult('restore_purchase'); }
    const result = await this.iapService.restorePurchases(context, period === AIRA_SUITE_LIFETIME_PLAN_ID);
    return this.submitPurchaseDataIfNeeded(context, result, uid, 'restore', current);
  }

  private manageSubscription(context: common.UIAbilityContext): Promise<HuaweiIapOperationResult> {
    return this.iapService.openSubscriptionManagement(context);
  }

  private isEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    boundaryInput: BrowserDataBoundaryInput
  ): boolean {
    const requestingBoundary = this.profileBoundaryService.buildBoundary(boundaryInput);
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: 'remote_account_sync_state',
      targetIsClear: true
    }).outcome === 'allow';
  }

  cancelPurchaseConsent(): void {
    this.purchaseConsentGeneration += 1;
    this.purchaseConsent?.cancel();
  }

  private async confirmPurchase(context: common.UIAbilityContext, period: string, uid: string,
    host: AiraProPurchaseFlowHost, boundary: BrowserDataBoundaryInput, generation: number): Promise<boolean> {
    if (uid.length === 0) { host.onLoginRequired(); return false; }
    if (this.membershipFeature === undefined || !isAiraProIapPlanId(period)) { return false; }
    const accountCurrent = this.membershipFeature.capturePurchaseSessionGuard(uid);
    const valid = (): boolean => generation === this.purchaseConsentGeneration && accountCurrent() &&
      this.isEffectAllowed('membership_purchase', boundary);
    const lastWindow = await window.getLastWindow(context);
    if (!valid()) { return false; }
    const suite = period === AIRA_SUITE_LIFETIME_PLAN_ID;
    const recurring = period !== AIRA_PRO_ONE_TIME_PLAN_ID && !suite;
    const plan = resolveAiraProIapPlan(period);
    const lifetimePrice = resolveAiraProLifetimePricePresentation(readCachedAiraProLifetimeStorePrice(),
      AIRA_PRO_ONE_TIME_PLAN.amountText, AIRA_PRO_ONE_TIME_PLAN.periodText,
      AIRA_PRO_ONE_TIME_PLAN.displayPrice, AIRA_PRO_ONE_TIME_PLAN.originalPriceText, Date.now());
    this.purchaseConsent = new KitappPurchaseConsentRequest(lastWindow.getUIContext(), {
      appName: 'Aira Pro · ' + (recurring ? plan.title : AIRA_PRO_ONE_TIME_PLAN.title),
      appPrice: recurring ? plan.amountText + ' ' + plan.periodText : lifetimePrice.amountText,
      appIcon: $r('app.media.foreground'),
      description: recurring ? plan.description : AIRA_PRO_ONE_TIME_PLAN.description,
      membershipTitle: suite ? '《Kitapp One 会员服务协议》' : undefined,
      suite, recurring, isCurrent: valid
    });
    const decision = await this.purchaseConsent.result;
    this.purchaseConsent = undefined;
    if (!valid()) { return false; }
    if (decision.link) {
      const id = decision.link === 'privacy' ? 'privacy_statement' : decision.link === 'renewal' ?
        'pro_auto_renewal_service_agreement' : suite ? 'suite_membership_service_agreement' : 'pro_membership_service_agreement';
      await context.openLink(resolveAiraLegalDocumentLink(id).url);
      return false;
    }
    return decision.accepted;
  }

  private async canStartPlanPurchase(period: string, host: AiraProPurchaseFlowHost): Promise<boolean> {
    if (this.membershipFeature === undefined) {
      host.showMessage($r('app.string.settings_pro_status_check_failed'));
      return false;
    }
    const previousSuiteRevision = period === AIRA_SUITE_LIFETIME_PLAN_ID ? this.membershipFeature.getAppSuiteState().revision : 0;
    const state = await this.membershipFeature.refreshState({ force: true });
    host.onMembershipStateChanged();
    if (period === AIRA_SUITE_LIFETIME_PLAN_ID) {
      if (!this.isBoundAccountUid(state.userId)) { host.onLoginRequired(); return false; }
      const suite = this.membershipFeature.getAppSuiteState();
      if (!suite.checked || suite.revision === previousSuiteRevision) {
        host.showMessage($r('app.string.settings_pro_status_check_failed')); return false;
      }
      if (suite.owned) { host.showMessage($r('app.string.membership_suite_already_owned')); return false; }
      return true;
    }
    const oneTimeSelected = period.trim().toLowerCase() === AIRA_PRO_ONE_TIME_PLAN_ID;
    const action = oneTimeSelected
      ? this.purchasePolicyService.resolveOneTimePlanAction(state)
      : this.purchasePolicyService.resolveSubscriptionPlanAction(state);
    if (action === 'purchase') {
      return true;
    }
    if (action === 'manage_subscription') {
      host.showMessage($r('app.string.settings_pro_renewal_still_on'));
      return false;
    }
    host.showMessage(this.purchasePolicyService.isLongTermMember(state)
      ? $r('app.string.settings_pro_already_lifetime')
      : $r('app.string.settings_pro_already_subscribed'));
    return false;
  }

  private async refreshAfterSubscriptionManagement(host: AiraProPurchaseFlowHost): Promise<void> {
    if (this.subscriptionManagementRefreshPromise !== undefined) {
      return this.subscriptionManagementRefreshPromise;
    }
    this.awaitingSubscriptionManagementReturn = false;
    const refreshPromise = this.pollLifetimeUpgradeAvailability(host)
      .finally(() => {
        if (this.subscriptionManagementRefreshPromise === refreshPromise) {
          this.subscriptionManagementRefreshPromise = undefined;
        }
      });
    this.subscriptionManagementRefreshPromise = refreshPromise;
    return refreshPromise;
  }

  private async pollLifetimeUpgradeAvailability(host: AiraProPurchaseFlowHost): Promise<void> {
    if (this.membershipFeature === undefined) {
      host.showMessage($r('app.string.settings_pro_status_check_failed'));
      return;
    }
    let action: AiraProPlanPurchaseAction = 'manage_subscription';
    for (const delayMs of LIFETIME_UPGRADE_REFRESH_DELAYS_MS) {
      if (delayMs > 0) {
        await this.delay(delayMs);
      }
      const state = await this.membershipFeature.refreshState({ force: true });
      host.onMembershipStateChanged();
      action = this.purchasePolicyService.resolveOneTimePlanAction(state);
      if (action !== 'manage_subscription') {
        break;
      }
    }
    if (action === 'purchase') {
      host.showMessage($r('app.string.settings_pro_renewal_off_ready'));
      return;
    }
    if (action === 'unavailable') {
      host.showMessage($r('app.string.settings_pro_already_lifetime_short'));
      return;
    }
    host.showMessage($r('app.string.settings_pro_renewal_syncing'));
  }

  private delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, delayMs);
    });
  }

  private showOperationResult(host: AiraProPurchaseFlowHost, result: HuaweiIapOperationResult): void {
    if (result.silent === true || !this.hasVisibleMessage(result.message)) {
      return;
    }
    host.showMessage(result.message);
  }

  private async refreshMembershipAfterPurchaseResult(
    productId: string | undefined,
    expiresAt: number | undefined,
    host: AiraProPurchaseFlowHost
  ): Promise<void> {
    if (this.membershipFeature === undefined) {
      return;
    }
    if (productId !== AIRA_SUITE_LIFETIME_PRODUCT_ID && productId !== undefined && productId.trim().length > 0 && expiresAt !== undefined && expiresAt >= 0) {
      await this.membershipFeature.applyVerifiedIapGrant(productId, expiresAt);
    }
    await this.membershipFeature.refreshState({ force: true });
    host.onMembershipStateChanged();
  }

  private async submitPurchaseDataIfNeeded(
    context: common.UIAbilityContext,
    result: HuaweiIapOperationResult,
    uid: string,
    source: string,
    current: () => boolean = (): boolean => true
  ): Promise<HuaweiIapOperationResult> {
    if (!current()) { return this.buildStalePurchaseResult(result); }
    const purchaseDataList = this.resolvePurchaseDataList(result);
    if (!result.ok || purchaseDataList.length <= 0) {
      return result;
    }
    const submission = await this.submitFirstVerifiablePurchaseData(uid, purchaseDataList, source);
    if (!current()) { return this.buildStalePurchaseResult(result); }
    const verification = submission.verification;
    const finishPurchaseMessage = verification.ok === true
      ? await this.finishVerifiedPurchaseData(context, result, submission.purchaseData, verification)
      : '';
    return {
      ok: result.ok && verification.ok === true,
      title: verification.ok === true ? this.buildSuccessTitle(verification) : result.title,
      message: this.buildVerificationMessage(result, verification, finishPurchaseMessage),
      action: result.action,
      purchaseData: result.purchaseData,
      purchaseDataList: result.purchaseDataList,
      purchaseCount: result.purchaseCount,
      verifiedProductId: verification.ok === true ? verification.productId : undefined,
      verifiedExpiresAt: verification.ok === true ? verification.expiresAt : undefined,
      verificationCode: verification.ok === true ? undefined : verification.code,
      errorCode: result.errorCode
    };
  }

  private resolvePurchaseDataList(result: HuaweiIapOperationResult): string[] {
    const purchaseDataList = result.purchaseDataList ?? [result.purchaseData ?? ''];
    return purchaseDataList
      .map((item: string) => item.trim())
      .filter((item: string) => item.length > 0);
  }

  private async submitFirstVerifiablePurchaseData(
    uid: string,
    purchaseDataList: string[],
    source: string
  ): Promise<VerifiedPurchaseSubmission> {
    let lastVerification: HuaweiIapVerificationResponseBody = {
      ok: false,
      code: 'missing_purchase_data',
      message: ''
    };
    let lastPurchaseData = '';
    for (const purchaseData of purchaseDataList) {
      lastPurchaseData = purchaseData;
      lastVerification = await this.verificationService.submitPurchaseData(uid, purchaseData, source);
      if (lastVerification.ok === true) {
        return {
          verification: lastVerification,
          purchaseData
        };
      }
    }
    return {
      verification: lastVerification,
      purchaseData: lastPurchaseData
    };
  }

  private buildVerificationMessage(
    result: HuaweiIapOperationResult,
    verification: HuaweiIapVerificationResponseBody,
    finishPurchaseMessage: ResourceStr = ''
  ): ResourceStr {
    if (verification.ok === true) {
      if (this.hasVisibleMessage(finishPurchaseMessage)) {
        return finishPurchaseMessage;
      }
      if (this.showDiagnosticMessages) {
        return this.buildDiagnosticVerificationMessage(verification);
      }
      return this.buildUserVerificationMessage(result, verification);
    }
    if (verification.code === 'missing_purchase_data') {
      return $r('app.string.settings_pro_iap_missing_purchase');
    }
    const verificationMessage = verification.message ?? '';
    return verificationMessage.length > 0 ? verificationMessage : result.message;
  }

  private hasVisibleMessage(message: ResourceStr): boolean {
    return typeof message !== 'string' || message.trim().length > 0;
  }

  private buildDiagnosticVerificationMessage(verification: HuaweiIapVerificationResponseBody): string {
    const membershipName = this.isLongTermPurchase(verification)
      ? resolveAppResourceText($r('app.string.settings_account_long_term_member'))
      : 'Aira Pro';
    const productId = verification.productId ?? '';
    const expiresAt = verification.expiresAt ?? 0;
    if (productId.length > 0 && expiresAt > 0) {
      return resolveAppResourceText($r('app.string.membership_purchase_diagnostic_product_until',
        membershipName, productId, this.formatDate(expiresAt)));
    }
    if (productId.length > 0) {
      return resolveAppResourceText($r('app.string.membership_purchase_diagnostic_product',
        membershipName, productId));
    }
    if (expiresAt > 0) {
      return resolveAppResourceText($r('app.string.membership_purchase_diagnostic_until',
        membershipName, this.formatDate(expiresAt)));
    }
    return resolveAppResourceText($r('app.string.membership_purchase_diagnostic_opened', membershipName));
  }

  private buildUserVerificationMessage(
    result: HuaweiIapOperationResult,
    verification: HuaweiIapVerificationResponseBody
  ): ResourceStr {
    const restored = result.action === 'restore_purchase';
    if (verification.productId === AIRA_SUITE_LIFETIME_PRODUCT_ID) {
      return restored ? $r('app.string.membership_suite_restored') : $r('app.string.membership_suite_purchased');
    }
    const until = this.formatExpiresDate(verification.expiresAt);
    if (this.isLongTermPurchase(verification)) {
      return restored
        ? $r('app.string.settings_pro_restored_lifetime')
        : $r('app.string.settings_pro_opened_lifetime_done');
    }
    if (until.length > 0) {
      return restored
        ? $r('app.string.settings_pro_restored_until', until)
        : $r('app.string.settings_pro_opened_until', until);
    }
    return restored
      ? $r('app.string.settings_pro_restored')
      : $r('app.string.settings_pro_opened');
  }

  private buildSuccessTitle(verification: HuaweiIapVerificationResponseBody): ResourceStr {
    return this.isLongTermPurchase(verification)
      ? $r('app.string.settings_pro_lifetime_active_title')
      : $r('app.string.membership_purchase_subscription_opened');
  }

  private isLongTermPurchase(verification: HuaweiIapVerificationResponseBody): boolean {
    return verification.productId === AIRA_SUITE_LIFETIME_PRODUCT_ID || isAiraProLifetimeProductId(verification.productId ?? '');
  }

  private formatExpiresDate(expiresAt?: number): string {
    if (expiresAt === undefined || expiresAt <= 0) {
      return '';
    }
    return this.formatDate(expiresAt);
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}.${this.pad2(date.getMonth() + 1)}.${this.pad2(date.getDate())}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private async finishVerifiedPurchaseData(
    context: common.UIAbilityContext,
    result: HuaweiIapOperationResult,
    purchaseData: string,
    verification: HuaweiIapVerificationResponseBody
  ): Promise<ResourceStr> {
    try {
      await this.iapService.finishPurchase(context, purchaseData, verification.productType);
      return '';
    } catch (_error) {
      const restored = result.action === 'restore_purchase';
      if (this.isLongTermPurchase(verification)) {
        return restored
          ? $r('app.string.settings_pro_finish_failed_lifetime_restore')
          : $r('app.string.settings_pro_finish_failed_lifetime_open');
      }
      return restored
        ? $r('app.string.settings_pro_finish_failed_restore')
        : $r('app.string.settings_pro_finish_failed_open');
    }
  }

  private buildAlreadyOwnsExpiredRestoreResult(
    purchaseResult: HuaweiIapOperationResult,
    restoreResult: HuaweiIapOperationResult
  ): HuaweiIapOperationResult {
    const diagnosticText = this.showDiagnosticMessages
      ? ` ${purchaseResult.message} ${restoreResult.message}`
      : '';
    return {
      ok: false,
      title: $r('app.string.settings_pro_purchase_unavailable'),
      message: this.showDiagnosticMessages
        ? resolveAppResourceText($r('app.string.settings_pro_purchase_blocked')) + diagnosticText
        : $r('app.string.settings_pro_purchase_blocked'),
      action: purchaseResult.action,
      purchaseData: restoreResult.purchaseData,
      purchaseDataList: restoreResult.purchaseDataList,
      purchaseCount: restoreResult.purchaseCount,
      verificationCode: restoreResult.verificationCode,
      errorCode: purchaseResult.errorCode
    };
  }

  private resolveAccountUid(requestedUid: string): string {
    const requested = requestedUid.trim();
    if (this.isBoundAccountUid(requested)) {
      return requested;
    }
    if (this.membershipFeature === undefined) {
      return '';
    }
    const refreshed = this.membershipFeature.getState().userId.trim();
    if (this.isBoundAccountUid(refreshed)) {
      return refreshed;
    }
    return '';
  }

  private isBoundAccountUid(uid: string): boolean {
    const normalized = uid.trim();
    return normalized.length > 0 && normalized !== 'local';
  }

  private buildStalePurchaseResult(result: HuaweiIapOperationResult): HuaweiIapOperationResult {
    return { ok: false, title: result.title, message: '', action: result.action, silent: true };
  }

  private buildLoginRequiredResult(
    action: 'purchase_pro_monthly' | 'purchase_pro_one_time' | 'restore_purchase'
  ): HuaweiIapOperationResult {
    return {
      ok: false,
      title: $r('app.string.settings_pro_sign_in_title'),
      message: $r('app.string.settings_pro_login_required'),
      action: action,
      verificationCode: 'login_required'
    };
  }

  private buildUnsupportedPlanResult(
    period: string,
    action: 'purchase_pro_monthly' | 'restore_purchase'
  ): HuaweiIapOperationResult {
    return {
      ok: false,
      title: $r('app.string.settings_pro_plan_unavailable'),
      message: $r('app.string.settings_pro_plan_unavailable'),
      action: action,
      verificationCode: 'unsupported_plan'
    };
  }
}

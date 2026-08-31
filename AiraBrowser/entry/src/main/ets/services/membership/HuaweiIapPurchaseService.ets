import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';
import {
  AIRA_PRO_IAP_PLANS,
  AIRA_PRO_ONE_TIME_PRODUCT_ID,
  HuaweiIapPlanId,
  HuaweiIapProductPlan,
  resolveAiraProProductId,
  resolveAiraProIapPlan
} from './HuaweiIapProductCatalog';
import { HuaweiIapAccountBindingService } from './HuaweiIapAccountBindingService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

const IAP_SYSTEM_CAPABILITY: string = 'SystemCapability.Payment.IAP';
const IAP_SUBSCRIPTION_PRODUCT_IDS: string[] = AIRA_PRO_IAP_PLANS.map((plan: HuaweiIapProductPlan) => plan.productId);
const IAP_PURCHASE_ALREADY_FINISHED_ERROR_CODE: number = 1001860053;

interface HuaweiIapPurchaseOrderPayload {
  productType?: number;
  purchaseToken?: string;
  purchaseOrderId?: string;
}

interface HuaweiIapSubscriptionStatusPayload {
  purchaseToken?: string;
  lastPurchaseOrder?: HuaweiIapPurchaseOrderPayload;
  recentPurchaseOrderList?: HuaweiIapPurchaseOrderPayload[];
}

interface HuaweiIapRawPurchaseData extends HuaweiIapSubscriptionStatusPayload {
  jwsSubscriptionStatus?: string;
  lastSubscriptionStatus?: HuaweiIapSubscriptionStatusPayload;
  purchaseToken?: string;
  purchaseOrderId?: string;
  productType?: number;
}

interface HuaweiIapJwsSubscriptionPayload {
  lastSubscriptionStatus?: HuaweiIapSubscriptionStatusPayload;
  historySubscriptionStatusList?: HuaweiIapSubscriptionStatusPayload[];
}

export type HuaweiIapAction =
  'query_products' |
  'purchase_pro_monthly' |
  'purchase_pro_one_time' |
  'restore_purchase' |
  'manage_subscription';

export interface HuaweiIapOperationResult {
  ok: boolean;
  title: string;
  message: string;
  action: HuaweiIapAction;
  silent?: boolean;
  purchaseData?: string;
  purchaseDataList?: string[];
  purchaseCount?: number;
  verifiedProductId?: string;
  verifiedExpiresAt?: number;
  verificationCode?: string;
  errorCode?: number;
}

export interface HuaweiIapProductView {
  productId: string;
  period: string;
  name: string;
  description: string;
  priceText: string;
  rawProductJson: string;
  promotionalOfferId: string;
}

export class HuaweiIapPurchaseService {
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private accountBindingService: HuaweiIapAccountBindingService = new HuaweiIapAccountBindingService();

  async queryProProducts(context: common.UIAbilityContext): Promise<HuaweiIapProductView[]> {
    if (!this.isIapAvailable()) {
      throw new Error(this.buildIapUnavailableMessage());
    }
    const subscriptionProductType = iap.ProductType.AUTORENEWABLE;
    const oneTimeProductType = iap.ProductType.NONCONSUMABLE;
    let subscriptionProducts: iap.Product[] = [];
    let oneTimeProducts: iap.Product[] = [];
    let subscriptionError: BusinessError | undefined;
    let oneTimeError: BusinessError | undefined;
    try {
      subscriptionProducts = await iap.queryProducts(context, {
        productType: subscriptionProductType,
        productIds: IAP_SUBSCRIPTION_PRODUCT_IDS
      });
    } catch (error) {
      subscriptionError = error as BusinessError;
    }
    try {
      oneTimeProducts = await iap.queryProducts(context, {
        productType: oneTimeProductType,
        productIds: [AIRA_PRO_ONE_TIME_PRODUCT_ID]
      });
    } catch (error) {
      oneTimeError = error as BusinessError;
    }
    if (subscriptionError !== undefined && oneTimeError !== undefined) {
      throw new Error(this.resolveFailureMessage('query_products', subscriptionError));
    }
    return subscriptionProducts.map((product) => this.buildProductView(product, this.resolvePlanForProduct(product.id).period))
      .concat(oneTimeProducts.map((product) => this.buildProductView(product, 'one_time')));
  }

  async startProPurchase(
    context: common.UIAbilityContext,
    period: string = 'monthly',
    uid: string = ''
  ): Promise<HuaweiIapOperationResult> {
    const normalizedPlanId = period.trim().toLowerCase();
    const oneTimeSelected = normalizedPlanId === 'one_time';
    const productId = resolveAiraProProductId(normalizedPlanId);
    const action: HuaweiIapAction = oneTimeSelected ? 'purchase_pro_one_time' : 'purchase_pro_monthly';
    if (!this.isIapAvailable()) {
      return this.buildIapUnavailableResult(action, oneTimeSelected ? '一次购暂不可用' : '订阅暂不可用');
    }
    const purchaseParameter: iap.PurchaseParameter = {
      productType: oneTimeSelected ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE,
      productId: productId,
      developerPayload: `${productId}_${Date.now()}`,
      applicationUserName: this.accountBindingService.buildApplicationUserName(uid)
    };
    try {
      const result = await iap.createPurchase(context, purchaseParameter);
      return {
        ok: true,
        title: oneTimeSelected ? '一次购支付完成' : '订阅购买完成',
        message: oneTimeSelected
          ? '已收到华为 IAP 一次购结果，正在进行服务端验单。'
          : '已收到华为 IAP 订阅购买结果，正在进行服务端验签。',
        action: action,
        purchaseData: result.purchaseData,
        purchaseDataList: result.purchaseData === undefined || result.purchaseData.length <= 0
          ? []
          : [result.purchaseData]
      };
    } catch (error) {
      return this.buildFailureResult(action, oneTimeSelected ? '一次购支付失败' : '订阅购买失败', error);
    }
  }

  async restorePurchases(context: common.UIAbilityContext): Promise<HuaweiIapOperationResult> {
    if (!this.isIapAvailable()) {
      return this.buildIapUnavailableResult('restore_purchase', '恢复购买暂不可用');
    }
    let subscriptionDataList: string[] = [];
    let oneTimeDataList: string[] = [];
    let subscriptionError: BusinessError | undefined;
    let oneTimeError: BusinessError | undefined;
    try {
      const subscriptionResult = await iap.queryPurchases(context, {
        productType: iap.ProductType.AUTORENEWABLE,
        queryType: iap.PurchaseQueryType.ALL
      });
      subscriptionDataList = subscriptionResult.purchaseDataList;
    } catch (error) {
      subscriptionError = error as BusinessError;
    }
    try {
      const oneTimeResult = await iap.queryPurchases(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      });
      oneTimeDataList = oneTimeResult.purchaseDataList;
    } catch (error) {
      oneTimeError = error as BusinessError;
    }
    if (subscriptionError !== undefined && oneTimeError !== undefined) {
      return this.buildFailureResult('restore_purchase', '恢复购买失败', subscriptionError);
    }
    const purchaseDataList = oneTimeDataList.concat(subscriptionDataList);
    return {
      ok: true,
      title: purchaseDataList.length > 0 ? '已找到购买记录' : '没有找到购买记录',
      message: purchaseDataList.length > 0
        ? '已读取华为 IAP 购买记录，正在进行服务端校验。'
        : '当前华为账号没有返回 Aira Pro 购买记录。',
      action: 'restore_purchase',
      purchaseCount: purchaseDataList.length,
      purchaseData: purchaseDataList[0] ?? '',
      purchaseDataList: purchaseDataList
    };
  }

  async openSubscriptionManagement(context: common.UIAbilityContext): Promise<HuaweiIapOperationResult> {
    if (!this.isIapAvailable()) {
      return this.buildIapUnavailableResult('manage_subscription', '订阅管理暂不可用');
    }
    try {
      await iap.showManagedSubscriptions(context, {
        windowScreenMode: iap.WindowScreenMode.FULLSCREEN
      });
      return {
        ok: true,
        title: '已打开订阅管理',
        message: '已进入华为订阅管理页面。',
        action: 'manage_subscription'
      };
    } catch (error) {
      return this.buildFailureResult('manage_subscription', '订阅管理打开失败', error);
    }
  }

  async finishPurchase(
    context: common.UIAbilityContext,
    purchaseData: string,
    verifiedProductType: string = ''
  ): Promise<void> {
    if (!this.isIapAvailable()) {
      throw new Error(this.buildIapUnavailableMessage());
    }
    const order = this.resolveFinishPurchaseOrder(purchaseData);
    try {
      await iap.finishPurchase(context, {
        productType: this.resolveProductType(order.productType, verifiedProductType),
        purchaseToken: order.purchaseToken ?? '',
        purchaseOrderId: order.purchaseOrderId ?? ''
      });
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === IAP_PURCHASE_ALREADY_FINISHED_ERROR_CODE) {
        return;
      }
      throw new Error(this.formatErrorDetails(businessError));
    }
  }

  private buildProductView(product: iap.Product, period: HuaweiIapPlanId): HuaweiIapProductView {
    let priceText = product.localPrice ?? product.price;
    let promotionalOfferId = '';
    if (period !== 'one_time') {
      const promotionalOffer = product.promotionalOffers?.[0];
      priceText = promotionalOffer?.localPrice ?? priceText;
      promotionalOfferId = promotionalOffer?.offerId ?? '';
    }
    return {
      productId: product.id,
      period: period,
      name: product.name,
      description: product.description,
      priceText: priceText,
      rawProductJson: product.jsonRepresentation ?? JSON.stringify(product),
      promotionalOfferId: promotionalOfferId
    };
  }

  private resolveProductType(productType?: number, verifiedProductType: string = ''): iap.ProductType {
    return productType === iap.ProductType.NONCONSUMABLE ||
      verifiedProductType.trim().toLowerCase() === 'nonconsumable'
      ? iap.ProductType.NONCONSUMABLE
      : iap.ProductType.AUTORENEWABLE;
  }

  private isIapAvailable(): boolean {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_iap') && canIUse(IAP_SYSTEM_CAPABILITY);
  }

  private buildIapUnavailableMessage(): string {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_iap')) {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_iap');
    }
    return '当前设备暂不支持华为应用内支付，已有会员权益不受影响。';
  }

  private buildIapUnavailableResult(action: HuaweiIapAction, title: string): HuaweiIapOperationResult {
    return {
      ok: false,
      title: title,
      message: this.buildIapUnavailableMessage(),
      action: action
    };
  }

  private resolveFinishPurchaseOrder(purchaseData: string): HuaweiIapPurchaseOrderPayload {
    const purchase = this.parsePurchaseData(purchaseData);
    const decoded = this.decodeJwsSubscriptionStatus(purchase.jwsSubscriptionStatus);
    const decodedStatus = decoded.lastSubscriptionStatus ?? decoded.historySubscriptionStatusList?.[0];
    const purchaseStatus = purchase.lastSubscriptionStatus ?? purchase;
    const order = decodedStatus?.lastPurchaseOrder ??
      decodedStatus?.recentPurchaseOrderList?.[0] ??
      purchaseStatus.lastPurchaseOrder ??
      purchaseStatus.recentPurchaseOrderList?.[0] ??
      purchase;
    const purchaseToken = this.normalizeString(order.purchaseToken ?? decodedStatus?.purchaseToken ?? purchase.purchaseToken);
    const purchaseOrderId = this.normalizeString(order.purchaseOrderId ?? purchase.purchaseOrderId);
    if (purchaseToken.length <= 0 || purchaseOrderId.length <= 0) {
      throw new Error('华为 IAP 购买数据缺少完成发货所需的 purchaseToken 或 purchaseOrderId。');
    }
    return {
      productType: order.productType ?? purchase.productType,
      purchaseToken,
      purchaseOrderId
    };
  }

  private parsePurchaseData(purchaseData: string): HuaweiIapRawPurchaseData {
    try {
      return JSON.parse(purchaseData) as HuaweiIapRawPurchaseData;
    } catch (_error) {
      throw new Error('华为 IAP 购买数据不是有效 JSON，无法确认发货。');
    }
  }

  private decodeJwsSubscriptionStatus(jwsSubscriptionStatus?: string): HuaweiIapJwsSubscriptionPayload {
    const parts = this.normalizeString(jwsSubscriptionStatus).split('.');
    if (parts.length < 2 || parts[1].length <= 0) {
      return {};
    }
    try {
      const payload = this.textDecoder.decodeToString(this.base64Helper.decodeSync(this.toBase64(parts[1])));
      return JSON.parse(payload) as HuaweiIapJwsSubscriptionPayload;
    } catch (_error) {
      return {};
    }
  }

  private toBase64(value: string): string {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
    const padding = normalized.length % 4;
    return padding === 0 ? normalized : normalized + '='.repeat(4 - padding);
  }

  private buildFailureResult(
    action: HuaweiIapAction,
    title: string,
    error: Error | BusinessError | Object
  ): HuaweiIapOperationResult {
    const businessError = error as BusinessError;
    if (this.isUserCancelledError(businessError)) {
      return {
        ok: false,
        title: '已取消操作',
        message: '',
        action: action,
        silent: true,
        errorCode: businessError.code
      };
    }
    return {
      ok: false,
      title: title,
      message: this.resolveFailureMessage(action, businessError),
      action: action,
      errorCode: businessError.code
    };
  }

  private isUserCancelledError(error: BusinessError): boolean {
    return error.code === 1001860000;
  }

  private resolveFailureMessage(action: HuaweiIapAction, error: BusinessError): string {
    const details = this.formatErrorDetails(error);
    if (error.code === 1001860057) {
      return `当前安装包签名不满足 IAP 测试环境要求。${details}`;
    }
    if (error.code === 1001860058) {
      return `当前华为账号不具备 IAP 测试资格，添加测试账号后等待 30 分钟到 1 小时再试。${details}`;
    }
    if (error.code === 1001860050) {
      return `当前设备未登录华为账号，请先登录后再购买。${details}`;
    }
    if (error.code === 1001860051) {
      return `当前华为账号已经拥有这个商品，请点“恢复购买”同步 Aira Pro 权益。${details}`;
    }
    if (error.code === 1001860003) {
      return `AGC 中未找到 Aira Pro 商品，请确认 ${IAP_SUBSCRIPTION_PRODUCT_IDS.concat([AIRA_PRO_ONE_TIME_PRODUCT_ID]).join('、')} 的商品 ID、商品类型和上架状态。${details}`;
    }
    if (error.code === 1001860002) {
      return `当前应用未被授权访问 IAP。请确认 AGC 当前 HarmonyOS 应用已开启应用内购买服务，商品建在同一个应用下，并已登记当前安装包真实签名指纹。${details}`;
    }
    if (action === 'purchase_pro_one_time') {
      return `无法拉起 Aira 长期会员一次购。${details}`;
    }
    if (action === 'purchase_pro_monthly') {
      return `无法拉起 Aira Pro 订阅购买。${details}`;
    }
    if (action === 'query_products') {
      return `无法查询 Aira Pro 商品。${details}`;
    }
    if (action === 'restore_purchase') {
      return `无法读取华为 IAP 购买记录。${details}`;
    }
    if (action === 'manage_subscription') {
      return `无法打开华为订阅管理。${details}`;
    }
    return `无法完成 IAP 操作。${details}`;
  }

  private resolvePlanForProduct(productId: string): HuaweiIapProductPlan {
    const plan = AIRA_PRO_IAP_PLANS.find((item: HuaweiIapProductPlan) => item.productId === productId);
    return plan ?? resolveAiraProIapPlan('monthly');
  }

  private formatErrorDetails(error: BusinessError): string {
    const codeText = error.code === undefined ? '' : `错误码 ${error.code}`;
    const messageText = error.message === undefined || error.message.length === 0 ? '' : error.message;
    if (codeText.length > 0 && messageText.length > 0) {
      return `${codeText}：${messageText}`;
    }
    if (codeText.length > 0) {
      return codeText;
    }
    if (messageText.length > 0) {
      return messageText;
    }
    return '未返回详细错误信息。';
  }

  private normalizeString(value: string | undefined): string {
    return value === undefined ? '' : value.trim();
  }
}

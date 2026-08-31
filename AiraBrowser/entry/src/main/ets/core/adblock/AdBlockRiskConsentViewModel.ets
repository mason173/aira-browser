export interface AdBlockRiskConsentSheetState {
  title: string;
  intro: string;
  riskItems: string[];
  confirmation: string;
  primaryActionLabel: string;
  secondaryActionLabel: string;
}

export class AdBlockRiskConsentViewModel {
  buildState(): AdBlockRiskConsentSheetState {
    return {
      title: '开启网页内容过滤？',
      intro: '网页内容过滤会按你启用的规则在本机处理网页请求或页面元素。Aira 不预装第三方规则内容，也不保证第三方规则的适用性。',
      riskItems: [
        '请遵守网站条款与法律法规。',
        '不合适的规则可能导致网页显示异常、功能不可用或误过滤。',
        '如果网页行为异常，请停用网页内容过滤或调整相关规则。'
      ],
      confirmation: '继续开启表示你理解上述风险，并愿意自行管理规则来源和使用后果。',
      primaryActionLabel: '知晓并开启',
      secondaryActionLabel: '取消'
    };
  }
}

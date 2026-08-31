export interface SettingsLegalDocumentSectionState {
  id: string;
  title: string;
  paragraphs: string[];
  items: string[];
}

export interface SettingsLegalDocumentState {
  title: string;
  updatedAt: string;
  lead: string;
  sections: SettingsLegalDocumentSectionState[];
}

export class SettingsLegalDocumentViewModel {
  buildAutoRenewalNoticeState(): SettingsLegalDocumentState {
    return {
      title: '自动续费说明',
      updatedAt: '更新日期：2026-05-20',
      lead: '本说明用于帮助你理解 Aira Pro 订阅的续费、扣款、取消和权益变化规则。实际价格、周期、优惠和支付结果以华为支付或订阅管理页面展示为准。',
      sections: [
        {
          id: 'subscription',
          title: '订阅与续费',
          paragraphs: [
            'Aira Pro 可能提供月度、季度、年度等订阅周期。你选择并确认支付后，对应 Pro 权益会在订阅有效期内生效。',
            '如果你在支付页面开通连续订阅，系统会在每个订阅周期到期前按照平台规则自动续费。'
          ],
          items: []
        },
        {
          id: 'billing',
          title: '扣款与价格',
          paragraphs: [
            '订阅价格、优惠、试用、税费、扣款时间和扣款方式以华为支付页面或订阅管理页面展示的信息为准。',
            '如果支付失败、账号状态异常或平台未能确认订阅状态，Pro 权益可能无法立即生效。你可以稍后返回会员页恢复购买。'
          ],
          items: []
        },
        {
          id: 'cancel',
          title: '取消续费',
          paragraphs: [
            '你可以通过华为官方订阅管理页面取消自动续费。取消后，已购买周期内的 Pro 权益通常会保留到当前周期结束。',
            '为避免下个周期继续扣款，请在平台要求的时间前完成取消操作。具体取消路径、截止时间和生效规则以华为订阅管理页面为准。'
          ],
          items: []
        },
        {
          id: 'changes',
          title: '权益变化',
          paragraphs: [
            '如果订阅到期、取消、退款或支付状态异常，Aira Pro 权益可能会停止或回到当前账号可用的基础权益。',
            '会员权益、订阅周期和价格如有调整，我们会在应用内或支付页面以适当方式提示。'
          ],
          items: []
        }
      ]
    };
  }
}

export interface AiraProEntryConfirmationViewState {
  title: string;
  message: string;
  freeTitle: string;
  freeMessage: string;
  optionalTitle: string;
  optionalMessage: string;
  developerTitle: string;
  developerMessage: string;
  confirmActionTitle: string;
  cancelActionTitle: string;
}

export class AiraProEntryConfirmationViewModel {
  buildState(): AiraProEntryConfirmationViewState {
    return {
      title: 'Pro 是自愿的',
      message: '基础浏览会继续免费。看到这个入口，不代表你必须付费；不接受付费增强能力，可以直接返回继续用免费版。',
      freeTitle: '我知道：不买 Pro 也能继续用 Aira',
      freeMessage: '基础浏览、常规设置、已有免费能力不会因为 Pro 出现就被拿走。',
      optionalTitle: '我知道：Pro 完全自愿，不订阅也能用',
      optionalMessage: '想支持长期维护就订阅；不想付费就继续用免费版，或者选择不用。',
      developerTitle: '我认可：增强能力收费是正常的',
      developerMessage: 'Aira Pro 用于支持官方云同步、网页接力和跨设备服务的开发与服务器成本。',
      confirmActionTitle: '查看Pro能力',
      cancelActionTitle: '不接受，返回免费版'
    };
  }
}

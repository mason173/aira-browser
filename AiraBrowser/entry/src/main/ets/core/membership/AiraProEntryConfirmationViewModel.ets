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
      title: 'Aira Pro 只用于官方云服务',
      message: '本地功能和使用自有服务的功能保持免费。只有使用 Aira 官方托管云服务时才需要 Pro。',
      freeTitle: '本地功能全部免费',
      freeMessage: '本地浏览、常规设置和设备内功能无需登录，也不需要会员。',
      optionalTitle: '自有服务不需要 Pro',
      optionalMessage: 'WebDAV 和个人服务器由你自行提供，相关客户端功能免费使用。',
      developerTitle: 'Pro 支付官方托管成本',
      developerMessage: 'Aira Pro 用于承担 Aira 云同步、网页接力和跨设备服务的服务器与维护成本。',
      confirmActionTitle: '查看 Pro 云服务',
      cancelActionTitle: '返回免费功能'
    };
  }
}

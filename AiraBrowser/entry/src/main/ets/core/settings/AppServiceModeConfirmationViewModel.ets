import { BrowserAppServiceMode } from '../../common/models/BrowserModels';

export interface AppServiceModeConfirmationPrompt {
  title: string;
  message: string;
  cancelLabel: string;
  confirmLabel: string;
  confirmIsDestructive: boolean;
}

export class AppServiceModeConfirmationViewModel {
  buildPrompt(
    currentMode: BrowserAppServiceMode,
    targetMode: BrowserAppServiceMode
  ): AppServiceModeConfirmationPrompt | undefined {
    if (currentMode === targetMode || targetMode !== 'basic') {
      return undefined;
    }
    return {
      title: '切换到基本模式？',
      message: '基本模式会关闭账号登录、同步、会员、翻译、脚本、网页内容过滤、壁纸、远程建议和实验功能。大部分增强能力将不可用，App 会重启以应用更改；已保存的数据不会删除。',
      cancelLabel: '取消',
      confirmLabel: '切换到基本模式',
      confirmIsDestructive: true
    };
  }
}

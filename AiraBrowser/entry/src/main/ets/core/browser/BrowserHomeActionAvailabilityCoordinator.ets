import {
  BrowserBottomPanelActionCatalog,
  BrowserBottomPanelActionId
} from './BrowserBottomPanelActionCatalog';

export interface BrowserHomeActionAvailabilityResult {
  available: boolean;
  message: string;
}

export class BrowserHomeActionAvailabilityCoordinator {
  resolve(actionId: BrowserBottomPanelActionId): BrowserHomeActionAvailabilityResult {
    if (this.isAvailableOnHome(actionId)) {
      return {
        available: true,
        message: ''
      };
    }
    return {
      available: false,
      message: this.resolveUnavailableMessage(actionId)
    };
  }

  private isAvailableOnHome(actionId: BrowserBottomPanelActionId): boolean {
    return BrowserBottomPanelActionCatalog.entry(actionId).surfaces.includes('home');
  }

  private resolveUnavailableMessage(actionId: BrowserBottomPanelActionId): string {
    switch (actionId) {
      case 'video':
        return '主页没有可嗅探的页面资源。';
      case 'bookmark':
        return '主页无法添加为书签。';
      case 'copyLink':
        return '主页没有可复制的网页链接。';
      case 'share':
        return '主页没有可分享的网页。';
      case 'sendToDesktop':
        return '主页没有可推送的网页。';
      case 'print':
        return '主页没有可打印的网页。';
      case 'find':
        return '主页暂不支持页内查找。';
      case 'reader':
        return '主页暂不支持阅读模式。';
      case 'translate':
        return '主页没有可翻译的网页。';
      case 'offline':
        return '主页没有可保存的离线网页。';
      case 'siteInfo':
        return '主页没有站点信息。';
      case 'addToDesktop':
        return '主页不能安装为应用。';
      case 'manualElementHide':
        return '主页暂不支持标记广告。';
      case 'textZoom':
        return '请先打开网页后调整文字大小。';
      default:
        return '请先打开网页后再使用该工具。';
    }
  }
}

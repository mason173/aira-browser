export interface WebLoadErrorPresentationInput {
  url: string;
  pendingUrl: string;
  title: string;
  errorMessage: string;
  runtimeDegradedMessage: string;
  crashed: boolean;
  context?: 'web_page' | 'custom_homepage';
}

export interface WebLoadErrorPresentation {
  title: string;
  summary: string;
  host: string;
  primaryActionLabel: string;
  secondaryActionLabel: string;
  tertiaryActionLabel: string;
  detailLabel: string;
  detailText: string;
  hints: string[];
}

export class WebLoadErrorPresentationService {
  build(input: WebLoadErrorPresentationInput): WebLoadErrorPresentation {
    const targetUrl = this.resolveTargetUrl(input.url, input.pendingUrl);
    const host = this.extractHost(targetUrl);
    const normalizedError = this.normalizeErrorMessage(input.errorMessage);
    const isCustomHomepage = input.context === 'custom_homepage';
    const title = input.crashed ? '标签页暂时无法恢复' : this.resolveTitle(normalizedError, isCustomHomepage);
    const summary = this.resolveSummary(targetUrl, host, input.crashed, isCustomHomepage);
    const detailParts: string[] = [];
    if (input.runtimeDegradedMessage.trim().length > 0) {
      detailParts.push(input.runtimeDegradedMessage.trim());
    }

    return {
      title: title,
      summary: summary,
      host: host.length > 0 ? host : '当前网页',
      primaryActionLabel: '再试一次',
      secondaryActionLabel: isCustomHomepage ? '编辑主页' : '转到系统设置',
      tertiaryActionLabel: isCustomHomepage ? '' : '复制详情',
      detailLabel: '错误详情',
      detailText: detailParts.join('\n'),
      hints: this.resolveHints(normalizedError, input.crashed, isCustomHomepage)
    };
  }

  private resolveTitle(errorMessage: string, isCustomHomepage: boolean): string {
    if (isCustomHomepage) {
      return '主页无法打开';
    }
    const normalized = errorMessage.toLowerCase();
    if (normalized.indexOf('ssl') >= 0 || normalized.indexOf('certificate') >= 0 || normalized.indexOf('证书') >= 0) {
      return '连接安全性需要确认';
    }
    if (normalized.indexOf('dns') >= 0 || normalized.indexOf('name_not_resolved') >= 0) {
      return '找不到这个网站';
    }
    return '网站暂时无法打开';
  }

  private resolveSummary(targetUrl: string, host: string, crashed: boolean, isCustomHomepage: boolean): string {
    if (crashed) {
      return '当前标签页运行时异常，可以重新加载页面或回到首页。';
    }
    if (isCustomHomepage) {
      return host.length > 0 ? host : '当前自定义主页不可用';
    }
    const normalizedTargetUrl = targetUrl.trim();
    if (normalizedTargetUrl.length > 0) {
      return normalizedTargetUrl;
    }
    return host.length > 0 ? host : '当前网页';
  }

  private resolveHints(errorMessage: string, crashed: boolean, isCustomHomepage: boolean): string[] {
    if (crashed) {
      return ['重新加载页面', '如果仍然失败，先回到首页再打开网站', '复制错误详情用于诊断'];
    }
    if (isCustomHomepage) {
      return [];
    }
    const normalized = errorMessage.toLowerCase();
    if (normalized.indexOf('ssl') >= 0 || normalized.indexOf('certificate') >= 0 || normalized.indexOf('证书') >= 0) {
      return ['确认设备时间是否正确', '谨慎处理证书异常的网站', '复制错误详情用于诊断'];
    }
    return ['检查 Wi-Fi 或移动网络', '确认网址没有输入错误', '如果使用了 VPN 或代理，可以稍后再试'];
  }

  private resolveTargetUrl(url: string, pendingUrl: string): string {
    const normalizedPendingUrl = pendingUrl.trim();
    if (normalizedPendingUrl.length > 0) {
      return normalizedPendingUrl;
    }
    return url.trim();
  }

  private normalizeErrorMessage(errorMessage: string): string {
    return errorMessage.trim();
  }

  private extractHost(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const withoutScheme = trimmed.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
    const slashIndex = withoutScheme.indexOf('/');
    const hostWithPort = slashIndex >= 0 ? withoutScheme.substring(0, slashIndex) : withoutScheme;
    const atIndex = hostWithPort.lastIndexOf('@');
    return (atIndex >= 0 ? hostWithPort.substring(atIndex + 1) : hostWithPort).trim();
  }
}

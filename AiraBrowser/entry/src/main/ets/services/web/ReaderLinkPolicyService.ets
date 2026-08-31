export type ReaderLinkOpenKind = 'app_web' | 'external' | 'blocked';

export interface ReaderLinkOpenDecision {
  kind: ReaderLinkOpenKind;
  url: string;
  message: string;
}

export class ReaderLinkPolicyService {
  resolve(url: string): ReaderLinkOpenDecision {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length <= 0) {
      return {
        kind: 'blocked',
        url: '',
        message: '链接为空。'
      };
    }
    const scheme = this.getUrlScheme(normalizedUrl);
    if (scheme === 'http' || scheme === 'https') {
      return {
        kind: 'app_web',
        url: normalizedUrl,
        message: '正在打开链接。'
      };
    }
    if (scheme === 'mailto' || scheme === 'tel' || scheme === 'sms' || scheme === 'geo') {
      return {
        kind: 'external',
        url: normalizedUrl,
        message: '正在交给系统打开。'
      };
    }
    if (scheme.length > 0) {
      return {
        kind: 'external',
        url: normalizedUrl,
        message: '正在交给外部应用打开。'
      };
    }
    return {
      kind: 'blocked',
      url: normalizedUrl,
      message: '暂不支持打开这个链接。'
    };
  }

  private getUrlScheme(url: string): string {
    const match = url.match(/^([a-z][a-z0-9+.-]*):/i);
    return match === null ? '' : match[1].toLowerCase();
  }
}

export interface WebAppInstallIconRule {
  domains: string[];
  mediaName: string;
}

export interface WebAppInstallIconMatch {
  domain: string;
  mediaName: string;
}

const BUILT_IN_WEBAPP_ICON_RULES: WebAppInstallIconRule[] = [
  { domains: ['threads.net'], mediaName: 'webapp_icon_threads' },
  { domains: ['instagram.com'], mediaName: 'webapp_icon_instagram' },
  { domains: ['x.com', 'twitter.com'], mediaName: 'webapp_icon_x' },
  { domains: ['discord.com', 'discord.gg'], mediaName: 'webapp_icon_discord' },
  { domains: ['reddit.com'], mediaName: 'webapp_icon_reddit' },
  { domains: ['youtube.com', 'youtu.be'], mediaName: 'webapp_icon_youtube' },
  { domains: ['facebook.com', 'fb.com'], mediaName: 'webapp_icon_facebook' },
  { domains: ['telegram.org', 't.me', 'telegram.me'], mediaName: 'webapp_icon_telegram' },
  { domains: ['bilibili.com', 'bilibili.tv', 'b23.tv', 'bili2233.cn', 'acg.tv'], mediaName: 'webapp_icon_bilibili' },
  { domains: ['ithome.com', 'ithome.cn'], mediaName: 'webapp_icon_ithome' },
  { domains: ['taptap.cn', 'taptap.io'], mediaName: 'webapp_icon_taptap' },
  { domains: ['weibo.com', 'weibo.cn', 'weibo.com.cn', 't.cn'], mediaName: 'webapp_icon_weibo' },
  { domains: ['zhihu.com', 'zhida.ai'], mediaName: 'webapp_icon_zhihu' },
  { domains: ['flomoapp.com', 'flomo.im'], mediaName: 'webapp_icon_flomo' },
  { domains: ['baidu.com'], mediaName: 'webapp_icon_baidu_index' },
  { domains: ['soutushenqi.com'], mediaName: 'webapp_icon_soutushenqi' },
  { domains: ['tiktok.com', 'tiktokv.com', 'vm.tiktok.com', 'vt.tiktok.com'], mediaName: 'webapp_icon_tiktok' },
  { domains: ['figma.com', 'figma.design'], mediaName: 'webapp_icon_figma' },
  { domains: ['github.com', 'github.dev'], mediaName: 'webapp_icon_github' },
  { domains: ['smzdm.com'], mediaName: 'webapp_icon_smzdm' },
  { domains: ['v2ex.com'], mediaName: 'webapp_icon_v2ex' },
  { domains: ['drive.google.com'], mediaName: 'webapp_icon_google_drive' },
  { domains: ['calendar.google.com'], mediaName: 'webapp_icon_google_calendar' },
  { domains: ['mail.google.com', 'gmail.com', 'googlemail.com'], mediaName: 'webapp_icon_gmail' },
  { domains: ['deepseek.com'], mediaName: 'webapp_icon_deepseek' }
];

export class WebAppInstallIconRuleService {
  resolveBuiltInIcon(url: string): WebAppInstallIconMatch | undefined {
    const host = this.extractHost(url);
    if (host.length === 0) {
      return undefined;
    }

    for (let ruleIndex = 0; ruleIndex < BUILT_IN_WEBAPP_ICON_RULES.length; ruleIndex += 1) {
      const rule = BUILT_IN_WEBAPP_ICON_RULES[ruleIndex];
      for (let domainIndex = 0; domainIndex < rule.domains.length; domainIndex += 1) {
        const domain = rule.domains[domainIndex];
        if (this.matchesDomain(host, domain)) {
          return {
            domain: domain,
            mediaName: rule.mediaName
          };
        }
      }
    }
    return undefined;
  }

  private matchesDomain(host: string, domain: string): boolean {
    const normalizedHost = this.normalizeHost(host);
    const normalizedDomain = this.normalizeHost(domain);
    return normalizedHost === normalizedDomain || normalizedHost.endsWith(`.${normalizedDomain}`);
  }

  private extractHost(url: string): string {
    const normalizedUrl = this.normalizeUrl(url);
    const match = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(normalizedUrl);
    if (match === null) {
      return '';
    }
    let host = match[1].trim();
    const atIndex = host.lastIndexOf('@');
    if (atIndex >= 0) {
      host = host.substring(atIndex + 1);
    }
    if (host.startsWith('[')) {
      const closingIndex = host.indexOf(']');
      return closingIndex > 0 ? host.substring(1, closingIndex).toLowerCase() : '';
    }
    const portIndex = host.lastIndexOf(':');
    if (portIndex >= 0) {
      host = host.substring(0, portIndex);
    }
    return this.normalizeHost(host);
  }

  private normalizeUrl(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('//')) {
      return `https:${trimmed}`;
    }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed)) {
      return trimmed;
    }
    return `https://${trimmed}`;
  }

  private normalizeHost(host: string): string {
    return host.trim().toLowerCase().replace(/\.$/, '');
  }
}

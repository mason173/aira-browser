import { looksLikeUrl, normalizeUrl } from '../../common/utils/UrlUtils';

export interface CustomHomepageUrlValidationResult {
  valid: boolean;
  normalizedUrl: string;
  errorMessage: string;
}

const IPV4_HOST_RE: RegExp = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
const DOMAIN_LABEL_RE: RegExp = /^[a-z0-9-]+$/i;

export class CustomHomepageUrlService {
  buildRemoteHomepageUrl(rawValue: string): string {
    const result = this.validateRemoteHomepageUrl(rawValue);
    if (!result.valid) {
      throw new Error(result.errorMessage);
    }
    return result.normalizedUrl;
  }

  validateRemoteHomepageUrl(rawValue: string): CustomHomepageUrlValidationResult {
    const normalizedInput = rawValue.trim();
    if (normalizedInput.length === 0) {
      return this.buildInvalidResult('请输入主页网址。');
    }
    if (this.hasWhitespace(normalizedInput)) {
      return this.buildInvalidResult('网址中不能包含空格。');
    }
    if (!looksLikeUrl(normalizedInput)) {
      return this.buildInvalidResult('请输入有效的网址。');
    }
    const normalizedUrl = normalizeUrl(normalizedInput).trim();
    const lowerUrl = normalizedUrl.toLowerCase();
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      return this.buildInvalidResult('主页网址仅支持 http 或 https。');
    }
    if (!this.hasValidHttpHost(normalizedUrl)) {
      return this.buildInvalidResult('请输入有效的网址。');
    }
    return {
      valid: true,
      normalizedUrl: normalizedUrl,
      errorMessage: ''
    };
  }

  buildRemoteHomepageTitle(url: string): string {
    const host = this.extractHost(url);
    return host.length > 0 ? host : url;
  }

  private extractHost(url: string): string {
    const normalizedUrl = url.trim();
    const schemeIndex = normalizedUrl.indexOf('://');
    if (schemeIndex < 0) {
      return '';
    }
    const hostStart = schemeIndex + 3;
    const slashIndex = normalizedUrl.indexOf('/', hostStart);
    const hostWithPort = slashIndex >= 0 ? normalizedUrl.substring(hostStart, slashIndex) : normalizedUrl.substring(hostStart);
    const host = hostWithPort.split('@').pop()?.split(':')[0] ?? '';
    return host.trim();
  }

  private hasValidHttpHost(url: string): boolean {
    const host = this.extractHost(url).toLowerCase();
    if (host.length === 0) {
      return false;
    }
    if (host === 'localhost' || host.endsWith('.local')) {
      return true;
    }
    if (this.isValidIpv4Host(host)) {
      return true;
    }
    if (host.includes(':')) {
      return true;
    }
    return this.isValidDomainHost(host);
  }

  private isValidIpv4Host(host: string): boolean {
    const match = host.match(IPV4_HOST_RE);
    if (match === null) {
      return false;
    }
    for (let index = 1; index <= 4; index += 1) {
      const octet = Number(match[index]);
      if (!Number.isInteger(octet) || octet < 0 || octet > 255) {
        return false;
      }
    }
    return true;
  }

  private isValidDomainHost(host: string): boolean {
    const normalized = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    const labels = normalized.split('.');
    if (labels.length < 2) {
      return false;
    }
    return labels.every((label: string): boolean => {
      return label.length > 0 &&
        label.length <= 63 &&
        DOMAIN_LABEL_RE.test(label) &&
        !label.startsWith('-') &&
        !label.endsWith('-');
    });
  }

  private hasWhitespace(value: string): boolean {
    return /\s/.test(value);
  }

  private buildInvalidResult(errorMessage: string): CustomHomepageUrlValidationResult {
    return {
      valid: false,
      normalizedUrl: '',
      errorMessage: errorMessage
    };
  }
}

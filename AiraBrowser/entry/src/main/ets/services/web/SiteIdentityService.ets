import urlUtils from '@ohos.url';
import {
  HostRuleTarget,
  SiteSettingTarget
} from '../../common/models/SiteSettingModels';

export interface BrowserSiteIdentity {
  siteKey: string;
  displayHost: string;
  primaryOrigin: string;
  target?: SiteSettingTarget;
}

interface ParsedAuthority {
  host: string;
  displayHost: string;
  port: number;
}

const DEFAULT_HTTP_PORT: number = 80;
const DEFAULT_HTTPS_PORT: number = 443;

export class SiteIdentityService {
  resolve(value: string, fallbackHost: string = ''): BrowserSiteIdentity {
    const target = this.resolveSiteSettingTarget(value) ?? this.resolveSiteSettingTarget(
      fallbackHost.length > 0 ? `https://${fallbackHost}` : ''
    );
    if (target === undefined) {
      return {
        siteKey: '',
        displayHost: '',
        primaryOrigin: ''
      };
    }
    return {
      siteKey: target.displayHost,
      displayHost: target.displayHost,
      primaryOrigin: target.canonicalOrigin,
      target: target
    };
  }

  /** Resolve one current-page URL to the exact persisted setting target. */
  resolveSiteSettingTarget(value: string): SiteSettingTarget | undefined {
    const trimmed = value.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    const candidate = /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed)
      ? trimmed
      : `https://${trimmed}`;
    let protocol: string = '';
    let hostname: string = '';
    let port: string = '';
    try {
      const parsed = urlUtils.URL.parseURL(candidate);
      protocol = parsed.protocol;
      hostname = parsed.hostname;
      port = parsed.port;
    } catch (_error) {
      return undefined;
    }
    const scheme = protocol.toLowerCase().replace(':', '');
    if (scheme !== 'http' && scheme !== 'https') {
      return undefined;
    }
    const authority = this.resolveAuthority(hostname, port, scheme);
    if (authority === undefined) {
      return undefined;
    }
    const hostForOrigin = this.formatOriginHost(authority.host);
    const defaultPort = scheme === 'http' ? DEFAULT_HTTP_PORT : DEFAULT_HTTPS_PORT;
    const portSuffix = authority.port === defaultPort ? '' : `:${authority.port}`;
    const canonicalOrigin = `${scheme}://${hostForOrigin}${portSuffix}`;
    return {
      scheme: scheme as 'http' | 'https',
      host: authority.host,
      effectivePort: authority.port,
      canonicalOrigin: canonicalOrigin,
      displayOrigin: canonicalOrigin,
      displayHost: authority.displayHost
    };
  }

  resolveHostRuleTarget(value: string): HostRuleTarget | undefined {
    const target = this.resolveSiteSettingTarget(value);
    if (target !== undefined) {
      return { host: target.displayHost };
    }
    const host = this.normalizeHost(value);
    return host.length > 0 ? { host: host } : undefined;
  }

  extractHost(value: string): string {
    const target = this.resolveSiteSettingTarget(value);
    if (target !== undefined) {
      return target.displayHost;
    }
    return this.normalizeHost(value);
  }

  /** Legacy broad comparison retained for host-scoped callers. */
  matchesSite(first: string, second: string, includeSubdomains: boolean = false): boolean {
    const firstIdentity = this.resolve(first);
    const secondIdentity = this.resolve(second);
    if (firstIdentity.primaryOrigin.length > 0 && firstIdentity.primaryOrigin === secondIdentity.primaryOrigin) {
      return true;
    }
    if (firstIdentity.displayHost.length > 0 && firstIdentity.displayHost === secondIdentity.displayHost) {
      return true;
    }
    if (includeSubdomains) {
      return this.hostMatches(firstIdentity.displayHost, secondIdentity.displayHost, true) ||
        this.hostMatches(secondIdentity.displayHost, firstIdentity.displayHost, true);
    }
    return false;
  }

  matchesSiteSettingTarget(value: string, target: SiteSettingTarget): boolean {
    const resolved = this.resolveSiteSettingTarget(value);
    return resolved !== undefined && resolved.canonicalOrigin === target.canonicalOrigin;
  }

  hostMatches(actualHost: string, ruleHost: string, includeSubdomains: boolean): boolean {
    const normalizedActualHost = this.normalizeHost(actualHost);
    const normalizedRuleHost = this.normalizeHost(ruleHost);
    if (normalizedActualHost.length <= 0 || normalizedRuleHost.length <= 0) {
      return false;
    }
    if (normalizedActualHost === normalizedRuleHost) {
      return true;
    }
    return includeSubdomains && normalizedActualHost.endsWith(`.${normalizedRuleHost}`);
  }

  private resolveAuthority(hostname: string, port: string, scheme: string): ParsedAuthority | undefined {
    const normalizedHost = this.normalizeHost(hostname);
    if (normalizedHost.length <= 0) {
      return undefined;
    }
    const parsedPort = port.trim().length > 0 ? Number(port) : scheme === 'http'
      ? DEFAULT_HTTP_PORT
      : DEFAULT_HTTPS_PORT;
    if (!Number.isInteger(parsedPort) || parsedPort < 1 || parsedPort > 65535) {
      return undefined;
    }
    return {
      host: normalizedHost,
      displayHost: this.formatDisplayHost(normalizedHost),
      port: parsedPort
    };
  }

  private formatOriginHost(host: string): string {
    return host.indexOf(':') >= 0 ? `[${host}]` : host;
  }

  private formatDisplayHost(host: string): string {
    return host.indexOf(':') >= 0 ? `[${host}]` : host;
  }

  private normalizeHost(value: string): string {
    let normalized = value.trim().toLowerCase();
    if (normalized.length <= 0) {
      return '';
    }
    normalized = normalized.replace(/^[a-z][a-z0-9+.-]*:\/\//, '');
    normalized = normalized.substring(normalized.lastIndexOf('@') + 1);
    if (normalized.startsWith('[')) {
      const endBracketIndex = normalized.indexOf(']');
      if (endBracketIndex < 0) {
        return '';
      }
      return normalized.substring(1, endBracketIndex).replace(/\.+$/g, '');
    }
    const authorityEnd = normalized.search(/[/:?#]/);
    const host = authorityEnd >= 0 ? normalized.substring(0, authorityEnd) : normalized;
    return host.replace(/^\.+|\.+$/g, '');
  }
}

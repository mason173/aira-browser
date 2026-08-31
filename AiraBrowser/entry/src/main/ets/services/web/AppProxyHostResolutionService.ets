import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AppProxyHostDns';
const MAX_RESOLVED_ADDRESSES = 12;

export class AppProxyHostResolutionService {
  private host: string = '';
  private addresses: string[] = [];
  private resolveGeneration: number = 0;

  refresh(hostValue: string): void {
    const host = this.normalizeComparableHost(hostValue);
    this.resolveGeneration += 1;
    const generation = this.resolveGeneration;
    this.host = host;
    this.addresses = [];

    if (host.length <= 0 || this.isIpLiteral(host)) {
      return;
    }

    connection.getAddressesByName(host)
      .then((addresses: connection.NetAddress[]) => {
        if (generation !== this.resolveGeneration || host !== this.host) {
          return;
        }
        this.addresses = this.normalizeResolvedAddresses(addresses);
        hilog.info(
          DOMAIN,
          TAG,
          'proxy host resolved host=%{public}s count=%{public}d',
          host,
          this.addresses.length
        );
      })
      .catch((error: BusinessError) => {
        if (generation !== this.resolveGeneration || host !== this.host) {
          return;
        }
        hilog.warn(
          DOMAIN,
          TAG,
          'proxy host resolve failed host=%{public}s code=%{public}s message=%{public}s',
          host,
          String(error.code),
          error.message
        );
      });
  }

  matchesConfiguredProxyHost(requestHostValue: string, configuredHostValue: string): boolean {
    const requestHost = this.normalizeComparableHost(requestHostValue);
    const configuredHost = this.normalizeComparableHost(configuredHostValue);
    if (requestHost.length <= 0 || configuredHost.length <= 0) {
      return false;
    }
    if (requestHost === configuredHost) {
      return true;
    }
    if (configuredHost !== this.host) {
      return false;
    }
    return this.addresses.includes(requestHost);
  }

  normalizeComparableHost(value: string): string {
    const trimmed = value.trim().toLowerCase();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.startsWith('[')) {
      const closingIndex = trimmed.indexOf(']');
      if (closingIndex > 0) {
        return trimmed.substring(1, closingIndex);
      }
      return trimmed;
    }
    const schemeSeparatorIndex = trimmed.indexOf('://');
    const authority = schemeSeparatorIndex >= 0
      ? trimmed.substring(schemeSeparatorIndex + 3)
      : trimmed;
    const pathIndex = this.findFirstAuthorityBoundary(authority);
    const hostPort = pathIndex >= 0 ? authority.substring(0, pathIndex) : authority;
    const userInfoIndex = hostPort.lastIndexOf('@');
    const hostOnly = userInfoIndex >= 0 ? hostPort.substring(userInfoIndex + 1) : hostPort;
    const colonIndex = hostOnly.lastIndexOf(':');
    if (colonIndex > 0 && hostOnly.indexOf(':') === colonIndex) {
      return hostOnly.substring(0, colonIndex);
    }
    return hostOnly;
  }

  private normalizeResolvedAddresses(addresses: connection.NetAddress[]): string[] {
    const result: string[] = [];
    for (let index = 0; index < addresses.length; index += 1) {
      const address = this.normalizeComparableHost(addresses[index].address);
      if (address.length > 0 && !result.includes(address)) {
        result.push(address);
      }
      if (result.length >= MAX_RESOLVED_ADDRESSES) {
        break;
      }
    }
    return result;
  }

  private findFirstAuthorityBoundary(value: string): number {
    const slashIndex = value.indexOf('/');
    const queryIndex = value.indexOf('?');
    const fragmentIndex = value.indexOf('#');
    let boundary = -1;
    [slashIndex, queryIndex, fragmentIndex].forEach((index: number) => {
      if (index >= 0 && (boundary < 0 || index < boundary)) {
        boundary = index;
      }
    });
    return boundary;
  }

  private isIpLiteral(host: string): boolean {
    if (/^[0-9.]+$/.test(host)) {
      return true;
    }
    return host.indexOf(':') >= 0;
  }
}

export const sharedAppProxyHostResolutionService: AppProxyHostResolutionService =
  new AppProxyHostResolutionService();

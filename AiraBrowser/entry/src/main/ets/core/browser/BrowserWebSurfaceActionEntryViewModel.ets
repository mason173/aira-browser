import { BrowserTabState } from '../tabs/TabManager';
import { resolveCurrentSiteHost } from './AddressDisplayFormatter';

export interface BrowserWebSurfaceActionEntryInput {
  activeTabIsWebPage: boolean;
  webPageVisible: boolean;
  tabsSheetVisible: boolean;
  targetUrls?: string[];
}

export interface BrowserWebSurfaceActionTargetInput {
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  activeTab?: BrowserTabState;
}

export interface BrowserWebSurfaceActionTarget {
  url: string;
  host: string;
  networkUrlAvailable: boolean;
  urls: string[];
}

export class BrowserWebSurfaceActionEntryViewModel {
  canShowWebPageAction(input: BrowserWebSurfaceActionEntryInput): boolean {
    return !input.tabsSheetVisible &&
      (input.activeTabIsWebPage || input.webPageVisible || this.hasNetworkTargetUrl(input.targetUrls ?? []));
  }

  resolveDisabledMessage(input: BrowserWebSurfaceActionEntryInput): string {
    return this.canShowWebPageAction(input) ? '' : '请先打开网页';
  }

  resolveTarget(input: BrowserWebSurfaceActionTargetInput): BrowserWebSurfaceActionTarget {
    const urls = this.buildTargetUrls(input);
    const url = this.resolvePreferredUrl(urls);
    return {
      url: url,
      host: resolveCurrentSiteHost(url, ''),
      networkUrlAvailable: this.isNetworkUrl(url),
      urls: urls
    };
  }

  buildTargetUrls(input: BrowserWebSurfaceActionTargetInput): string[] {
    return [
      input.currentUrl,
      input.pendingWebUrl,
      input.addressInput,
      input.activeTab?.lastRestorableUrl ?? '',
      input.activeTab?.lastGoodUrl ?? '',
      input.activeTab?.pendingUrl ?? '',
      input.activeTab?.url ?? ''
    ];
  }

  private hasNetworkTargetUrl(urls: string[]): boolean {
    for (let index = 0; index < urls.length; index += 1) {
      if (this.isNetworkUrl(urls[index])) {
        return true;
      }
    }
    return false;
  }

  private resolvePreferredUrl(urls: string[]): string {
    for (let index = 0; index < urls.length; index += 1) {
      const value = urls[index].trim();
      if (this.isNetworkUrl(value)) {
        return value;
      }
    }
    for (let index = 0; index < urls.length; index += 1) {
      const value = urls[index].trim();
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private isNetworkUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}

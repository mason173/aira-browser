import { BrowserTabState } from '../tabs/TabManager';
import {
  OfflinePageSaveBlockedReason,
  OfflinePageSaveEligibility
} from '../../common/models/OfflinePageModels';

export interface OfflinePageSaveEligibilityInput {
  tab?: BrowserTabState;
  hasAttachedController: boolean;
  hasDocumentSnapshot?: boolean;
  currentUrl?: string;
  currentTitle?: string;
}

const CANNOT_SAVE_MESSAGE = '当前页面无法保存';
const INTERNAL_SCHEME_PREFIXES: string[] = [
  'aira:',
  'about:',
  'data:',
  'blob:',
  'file:',
  'resource:',
  'internal:'
];
const DOWNLOAD_PATH_TOKENS: string[] = [
  '/download',
  '/downloads',
  'aira://downloads'
];

export class OfflinePageSaveViewModel {
  buildEligibility(input: OfflinePageSaveEligibilityInput): OfflinePageSaveEligibility {
    const tab = input.tab;
    const targetUrl = this.resolveTargetUrl(input);
    const title = this.resolveTitle(input);
    const reason = this.resolveBlockedReason(tab, targetUrl);
    return {
      canSave: reason === 'none',
      reason: reason,
      targetUrl: targetUrl,
      title: title,
      message: this.resolveMessage(reason)
    };
  }

  resolveMessage(reason: OfflinePageSaveBlockedReason): string {
    if (reason === 'none') {
      return '';
    }
    return CANNOT_SAVE_MESSAGE;
  }

  private resolveBlockedReason(
    tab: BrowserTabState | undefined,
    targetUrl: string
  ): OfflinePageSaveBlockedReason {
    if (tab === undefined) {
      return 'invalid_page';
    }
    if (tab.isHome) {
      return 'home_page';
    }
    if (targetUrl.length === 0) {
      return 'empty_url';
    }
    if (this.isInternalUrl(targetUrl)) {
      return 'internal_page';
    }
    if (this.isDownloadUrl(targetUrl)) {
      return 'download_page';
    }
    if (!this.isHttpUrl(targetUrl)) {
      return 'unsupported_scheme';
    }
    return 'none';
  }

  private resolveTargetUrl(input: OfflinePageSaveEligibilityInput): string {
    const candidates: string[] = [
      input.currentUrl ?? '',
      input.tab?.lastRestorableUrl ?? '',
      input.tab?.lastGoodUrl ?? '',
      input.tab?.pendingUrl ?? '',
      input.tab?.url ?? ''
    ];
    let firstNonEmpty = '';
    for (let index = 0; index < candidates.length; index += 1) {
      const value = candidates[index].trim();
      if (firstNonEmpty.length === 0 && value.length > 0) {
        firstNonEmpty = value;
      }
      if (this.isSaveCandidateUrl(value)) {
        return value;
      }
    }
    return firstNonEmpty;
  }

  private resolveTitle(input: OfflinePageSaveEligibilityInput): string {
    const title = (input.currentTitle ?? '').trim();
    if (title.length > 0) {
      return title;
    }
    return input.tab?.title.trim() ?? '';
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private isInternalUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return INTERNAL_SCHEME_PREFIXES.some((prefix: string): boolean => lower.startsWith(prefix));
  }

  private isDownloadUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return DOWNLOAD_PATH_TOKENS.some((token: string): boolean => lower.includes(token));
  }

  private isSaveCandidateUrl(url: string): boolean {
    return this.isHttpUrl(url) && !this.isInternalUrl(url) && !this.isDownloadUrl(url);
  }
}

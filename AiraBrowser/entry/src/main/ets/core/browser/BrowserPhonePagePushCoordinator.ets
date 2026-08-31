import { webview } from '@kit.ArkWeb';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';
import { AIRA_FEATURE_PHONE_PAGE_PUSH } from '../../common/constants/MembershipFeatureKeys';
import { EntitlementContext } from '../../services/membership/EntitlementService';
import {
  AiraPhonePagePushFunctionService,
  AiraPhonePagePushResponseBody
} from '../../services/push/AiraPhonePagePushFunctionService';
import { FeatureGateCoordinator } from '../membership/FeatureGateCoordinator';

interface BrowserPhonePageCanonicalProbePayload {
  matchesOriginal?: boolean;
  canonicalUrl?: string;
}

export interface BrowserPhonePagePushRequest {
  uid: string;
  url: string;
  desktopUrl: string;
  title: string;
}

export interface BrowserPhonePagePushSnapshot {
  entitlementContext: EntitlementContext;
  uid: string;
  url: string;
  title: string;
  controller: webview.WebviewController | undefined;
}

export interface BrowserPhonePagePushHost {
  resolveSnapshot: () => BrowserPhonePagePushSnapshot;
  showToast: (message: string) => void;
}

export class BrowserPhonePagePushCoordinator {
  private readonly featureGateCoordinator: FeatureGateCoordinator;
  private service: AiraPhonePagePushFunctionService;

  constructor(
    featureGateCoordinator: FeatureGateCoordinator,
    service: AiraPhonePagePushFunctionService = new AiraPhonePagePushFunctionService()
  ) {
    this.featureGateCoordinator = featureGateCoordinator;
    this.service = service;
  }

  async sendCurrentPageFromHost(host: BrowserPhonePagePushHost): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      host.showToast(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud'));
      return;
    }
    const accessSnapshot = host.resolveSnapshot();
    if (!await this.featureGateCoordinator.ensureAccess(
      AIRA_FEATURE_PHONE_PAGE_PUSH,
      accessSnapshot.entitlementContext
    )) {
      return;
    }
    const snapshot = host.resolveSnapshot();
    const url = snapshot.url.trim();
    const desktopUrl = await this.resolveDesktopUrl(snapshot.controller, url);
    const request: BrowserPhonePagePushRequest = {
      uid: snapshot.uid.trim(),
      url: url,
      desktopUrl: desktopUrl,
      title: this.resolveTitle(snapshot.title, url)
    };
    await this.enqueueCurrentPage(request, host);
  }

  private async enqueueCurrentPage(request: BrowserPhonePagePushRequest, host: BrowserPhonePagePushHost): Promise<void> {
    const url = request.url.trim();
    if (url.length <= 0) {
      host.showToast('当前没有可推送的网址。');
      return;
    }
    host.showToast('正在推送到电脑...');
    try {
      const result = await this.service.enqueue(
        request.uid.trim(),
        url,
        request.title.trim(),
        request.desktopUrl.trim()
      );
      if (result.ok === true) {
        host.showToast(this.resolveSuccessMessage(result));
        return;
      }
      host.showToast(this.resolveFailureMessage(result));
    } catch (_error) {
      host.showToast('推送失败，请稍后重试。');
    }
  }

  private async resolveDesktopUrl(
    controller: webview.WebviewController | undefined,
    originalUrl: string
  ): Promise<string> {
    const normalizedOriginalUrl = originalUrl.trim();
    if (controller === undefined || !this.isHttpUrl(normalizedOriginalUrl)) {
      return '';
    }
    try {
      const raw = await controller.runJavaScript(this.buildCanonicalUrlProbeScript(normalizedOriginalUrl));
      const probe = this.parseCanonicalProbe(raw ?? '');
      if (probe === undefined || probe.matchesOriginal !== true) {
        return '';
      }
      const candidate = probe.canonicalUrl?.trim() ?? '';
      if (!this.isHttpUrl(candidate) || candidate === normalizedOriginalUrl) {
        return '';
      }
      return candidate;
    } catch (_error) {
      return '';
    }
  }

  private buildCanonicalUrlProbeScript(originalUrl: string): string {
    const encodedOriginalUrl = JSON.stringify(originalUrl);
    return `
(() => {
  var result = { matchesOriginal: false, canonicalUrl: '' };
  try {
    var currentUrl = new URL(window.location.href).href;
    var expectedUrl = new URL(${encodedOriginalUrl}, window.location.href).href;
    if (currentUrl !== expectedUrl) {
      return JSON.stringify(result);
    }
    result.matchesOriginal = true;
    var links = document.querySelectorAll('link[rel][href]');
    var normalizeLeadingSiteHost = function(hostname) {
      var labels = String(hostname || '').trim().toLowerCase().split('.');
      if (labels.length > 0 && ['www', 'm', 'mobile', 'wap', 'touch'].indexOf(labels[0]) >= 0) {
        labels.shift();
      }
      return labels.join('.');
    };
    var hasRegistrableShape = function(hostname) {
      var labels = String(hostname || '').split('.');
      if (labels.length < 2) {
        return false;
      }
      var countrySecondLevel = ['ac', 'co', 'com', 'edu', 'gov', 'net', 'org'];
      var lastLabel = labels[labels.length - 1];
      var previousLabel = labels[labels.length - 2];
      return lastLabel.length !== 2 || countrySecondLevel.indexOf(previousLabel) < 0 || labels.length >= 3;
    };
    var trustedInternalMobilePairs = {
      'item.m.jd.com>item.jd.com': true,
      'item.jd.com>item.m.jd.com': true
    };
    var currentHost = new URL(currentUrl).hostname.toLowerCase();
    for (var index = 0; index < links.length; index += 1) {
      var link = links[index];
      var rel = String(link.getAttribute('rel') || '').toLowerCase().split(/\\s+/);
      if (rel.indexOf('canonical') < 0) {
        continue;
      }
      var href = String(link.getAttribute('href') || '').trim();
      if (!href) {
        continue;
      }
      var candidateUrl = new URL(href, document.baseURI || currentUrl);
      var candidateHost = candidateUrl.hostname.toLowerCase();
      var normalizedCurrentHost = normalizeLeadingSiteHost(currentHost);
      var normalizedCandidateHost = normalizeLeadingSiteHost(candidateHost);
      var sameHost = candidateHost === currentHost;
      var trustedLeadingVariant = normalizedCandidateHost === normalizedCurrentHost &&
        hasRegistrableShape(normalizedCurrentHost);
      var trustedInternalVariant = trustedInternalMobilePairs[currentHost + '>' + candidateHost] === true;
      if (!sameHost && !trustedLeadingVariant && !trustedInternalVariant) {
        continue;
      }
      result.canonicalUrl = candidateUrl.href;
      break;
    }
  } catch (_error) {
  }
  return JSON.stringify(result);
})()
`;
  }

  private parseCanonicalProbe(raw: string): BrowserPhonePageCanonicalProbePayload | undefined {
    const normalized = this.unwrapJavaScriptString(raw).trim();
    if (normalized.length <= 0) {
      return undefined;
    }
    try {
      return JSON.parse(normalized) as BrowserPhonePageCanonicalProbePayload;
    } catch (_error) {
      return undefined;
    }
  }

  private unwrapJavaScriptString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded = JSON.parse(raw) as string;
        return typeof decoded === 'string' ? decoded : raw;
      } catch (_error) {
      }
    }
    return raw;
  }

  private resolveTitle(title: string, fallbackUrl: string): string {
    const normalizedTitle = title.trim();
    return normalizedTitle.length > 0 ? normalizedTitle : fallbackUrl;
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private resolveSuccessMessage(result: AiraPhonePagePushResponseBody): string {
    switch (result.code) {
      case 'phone_page_push_duplicate_pending':
        return '这页已经在电脑待打开队列里。';
      case 'phone_page_push_duplicate_recent':
        return '这页刚刚已经在电脑打开过。';
      default:
        return '已推送到电脑。';
    }
  }

  private resolveFailureMessage(result: AiraPhonePagePushResponseBody): string {
    switch (result.code) {
      case 'pro_required':
        return '网页推送仅 Aira Pro 可用。';
      case 'phone_page_push_rate_limited':
        return '推送太频繁了，请稍后再试。';
      case 'phone_page_push_queue_full':
        return '电脑待打开的网页太多了，请先处理一部分。';
      case 'missing_uid':
      case 'auth_token_required':
      case 'auth_token_expired':
        return '请重新登录华为账号后再推送。';
      case 'invalid_url':
        return '当前页面不能推送到电脑。';
      case 'distribution_unavailable':
        return result.message?.trim() || AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('aira_cloud');
      default:
        return result.message?.trim() || '推送失败，请稍后重试。';
    }
  }
}

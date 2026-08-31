import { webview } from '@kit.ArkWeb';
import { WebAppManifest } from '../../features/webapps/WebAppManifestParser';
import { BrowserRuntimeLifecyclePort } from '../web/BrowserRuntimeLifecyclePort';
import { WebAppManifestDiscoveryService, WebAppManifestDiscoveryResult } from './WebAppManifestDiscoveryService';
import { WebAppManifestService, WebAppManifestFetchResult } from './WebAppManifestService';

const WEB_APP_MANIFEST_FETCH_WAIT_MS: number = 1500;

export interface WebAppManifestDiscoverer {
  discover(controller: webview.WebviewController | undefined): Promise<WebAppManifestDiscoveryResult>;
}

export interface WebAppManifestFetcher {
  fetchAndParse(manifestUrl: string, documentUrl: string): Promise<WebAppManifestFetchResult>;
}

export interface WebAppInstallDraft {
  defaultTitle: string;
  launchUrl: string;
  origin: string;
  scope: string;
  display: string;
  themeColor: string;
  backgroundColor: string;
  manifestUrl: string;
  iconUrl: string;
  manifestDiagnostics: string;
}

export class WebAppInstallPolicyService {
  private discoveryService: WebAppManifestDiscoverer;
  private manifestService: WebAppManifestFetcher;
  private manifestFetchWaitMs: number;

  constructor(
    discoveryService: WebAppManifestDiscoverer = new WebAppManifestDiscoveryService(),
    manifestService: WebAppManifestFetcher = new WebAppManifestService(),
    manifestFetchWaitMs: number = WEB_APP_MANIFEST_FETCH_WAIT_MS
  ) {
    this.discoveryService = discoveryService;
    this.manifestService = manifestService;
    this.manifestFetchWaitMs = Math.max(0, Math.floor(manifestFetchWaitMs));
  }

  buildDefaultDraft(currentUrl: string, currentTitle: string): WebAppInstallDraft {
    return {
      defaultTitle: currentTitle.trim().length > 0 ? currentTitle.trim() : currentUrl.trim(),
      launchUrl: currentUrl.trim(),
      origin: this.extractOrigin(currentUrl),
      scope: '',
      display: '',
      themeColor: '',
      backgroundColor: '',
      manifestUrl: '',
      iconUrl: '',
      manifestDiagnostics: 'no_manifest'
    };
  }

  async buildDraftForCurrentPage(
    controller: webview.WebviewController | undefined,
    currentUrl: string,
    currentTitle: string
  ): Promise<WebAppInstallDraft> {
    const fallback = this.buildDefaultDraft(currentUrl, currentTitle);
    if (controller === undefined) {
      return fallback;
    }
    const discovery = await this.discoveryService.discover(controller);
    if (!discovery.ok || discovery.manifestUrl.length === 0) {
      return this.applyDiscoveryFallback(fallback, discovery);
    }
    const fetchResult = await this.withTimeout<WebAppManifestFetchResult>(
      this.manifestService.fetchAndParse(
        discovery.manifestUrl,
        discovery.documentUrl.length > 0 ? discovery.documentUrl : currentUrl
      ),
      this.manifestFetchWaitMs,
      {
        ok: false,
        reason: 'manifest_fetch_timeout',
        rawJson: '',
        status: 0
      }
    );
    if (!fetchResult.ok || fetchResult.parse?.manifest === undefined) {
      return this.applyDiscoveryFallback(fallback, discovery, fetchResult.reason);
    }
    return this.buildManifestDraft(fetchResult.parse.manifest, discovery, fallback);
  }

  async buildDraftForCurrentPageFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    tabId: string,
    currentUrl: string,
    currentTitle: string
  ): Promise<WebAppInstallDraft> {
    return await this.buildDraftForCurrentPage(
      runtimeLifecyclePort.resolveController(tabId),
      currentUrl,
      currentTitle
    );
  }

  private applyDiscoveryFallback(
    fallback: WebAppInstallDraft,
    discovery: WebAppManifestDiscoveryResult,
    additionalReason: string = ''
  ): WebAppInstallDraft {
    return {
      defaultTitle: discovery.documentTitle.length > 0 ? discovery.documentTitle : fallback.defaultTitle,
      launchUrl: discovery.documentUrl.length > 0 ? discovery.documentUrl : fallback.launchUrl,
      origin: this.extractOrigin(discovery.documentUrl.length > 0 ? discovery.documentUrl : fallback.launchUrl),
      scope: '',
      display: '',
      themeColor: discovery.themeColor,
      backgroundColor: '',
      manifestUrl: discovery.manifestUrl,
      iconUrl: discovery.appleTouchIconUrl,
      manifestDiagnostics: this.combineDiagnostics(discovery.reason, additionalReason)
    };
  }

  private buildManifestDraft(
    manifest: WebAppManifest,
    discovery: WebAppManifestDiscoveryResult,
    fallback: WebAppInstallDraft
  ): WebAppInstallDraft {
    const title = manifest.name.length > 0
      ? manifest.name
      : (manifest.shortName.length > 0 ? manifest.shortName : fallback.defaultTitle);
    const iconUrl = manifest.bestIconUrl.length > 0
      ? manifest.bestIconUrl
      : discovery.appleTouchIconUrl;
    return {
      defaultTitle: title,
      launchUrl: manifest.startUrl.length > 0 ? manifest.startUrl : fallback.launchUrl,
      origin: this.extractOrigin(manifest.startUrl.length > 0 ? manifest.startUrl : fallback.launchUrl),
      scope: manifest.scope,
      display: manifest.display,
      themeColor: manifest.themeColor.length > 0 ? manifest.themeColor : discovery.themeColor,
      backgroundColor: manifest.backgroundColor,
      manifestUrl: manifest.manifestUrl,
      iconUrl: iconUrl,
      manifestDiagnostics: 'manifest_metadata'
    };
  }

  extractOrigin(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const match = /^([a-z]+:\/\/[^/?#]+)/i.exec(trimmed);
    if (match === null) {
      return '';
    }
    return match[1];
  }

  private combineDiagnostics(reason: string, additionalReason: string): string {
    if (additionalReason.length === 0) {
      return reason;
    }
    return `${reason};${additionalReason}`;
  }

  private async withTimeout<T>(promise: Promise<T>, timeoutMs: number, fallback: T): Promise<T> {
    let timer = 0;
    const timeoutPromise = new Promise<T>((resolve) => {
      timer = setTimeout(() => resolve(fallback), timeoutMs);
    });
    const result = await Promise.race([promise, timeoutPromise]);
    if (timer !== 0) {
      clearTimeout(timer);
    }
    return result;
  }
}

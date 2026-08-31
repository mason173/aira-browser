import { image } from '@kit.ImageKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  SiteIconCurrentPageCollectionResult,
  SiteIconCurrentPageDiscoveryService
} from '../../services/siteicons/SiteIconCurrentPageDiscoveryService';
import { SiteIconService } from '../../services/siteicons/SiteIconService';
import { TabLaunchContext } from '../../common/models/BrowserModels';
import { SiteIconResult } from '../../common/models/SiteIconModels';
import { HomeShortcutIconAssociationUpdateCenter } from
  '../../services/shortcuts/HomeShortcutIconAssociationUpdateCenter';

const FAVICON_LOG_DOMAIN: number = 0x0000;
const FAVICON_LOG_TAG: string = 'BrowserFavicon';
const PAGE_COLLECTION_DEDUP_MS: number = 2 * 60 * 1000;
const MAX_RECENT_PAGE_COLLECTIONS: number = 128;
const MAX_ARKWEB_FAVICON_RECEIPTS: number = 128;

interface BrowserFaviconAssociationInput {
  documentUrl: string;
  privateMode: boolean;
  launchContext?: TabLaunchContext;
}

export interface BrowserFaviconApplyInput extends BrowserFaviconAssociationInput {
  tabId: string;
  favicon: image.PixelMap;
}

export interface BrowserFaviconApplyHost {
  updatePreviewFavicon: (tabId: string, favicon: image.PixelMap) => boolean;
  notifyPreviewChanged: () => void;
}

export interface BrowserFaviconCurrentPageInput extends BrowserFaviconAssociationInput {
  tabId: string;
  controller: webview.WebviewController | undefined;
  navigationIndex: number;
}

interface BrowserFaviconPageCollectionEntry {
  key: string;
  collectedAt: number;
}

interface BrowserFaviconArkWebReceiptEntry {
  tabId: string;
  documentUrl: string;
  edge: number;
  updatedAt: number;
}

export class BrowserFaviconCoordinator {
  private readonly siteIconService: SiteIconService;
  private readonly currentPageDiscoveryService: SiteIconCurrentPageDiscoveryService;
  private activePageCollectionKeys: string[] = [];
  private recentPageCollections: BrowserFaviconPageCollectionEntry[] = [];
  private arkWebReceipts: BrowserFaviconArkWebReceiptEntry[] = [];

  constructor(
    siteIconService: SiteIconService = new SiteIconService(),
    currentPageDiscoveryService?: SiteIconCurrentPageDiscoveryService
  ) {
    this.siteIconService = siteIconService;
    this.currentPageDiscoveryService = currentPageDiscoveryService ??
      new SiteIconCurrentPageDiscoveryService(this.siteIconService);
  }

  handleFaviconReceived(input: BrowserFaviconApplyInput, host: BrowserFaviconApplyHost): boolean {
    if (!this.shouldAcceptArkWebFavicon(input)) {
      return false;
    }
    if (host.updatePreviewFavicon(input.tabId, input.favicon)) {
      host.notifyPreviewChanged();
    }
    this.persistFaviconAndPublishIfAllowed(input);
    return true;
  }

  handleCurrentPageReady(input: BrowserFaviconCurrentPageInput): void {
    const documentUrl = input.documentUrl.trim();
    const tabId = input.tabId.trim();
    if (input.privateMode || input.controller === undefined || tabId.length === 0 ||
      !this.siteIconService.canCollect(documentUrl)) {
      return;
    }
    const now = Date.now();
    this.recentPageCollections = this.recentPageCollections
      .filter((entry: BrowserFaviconPageCollectionEntry) => now - entry.collectedAt < PAGE_COLLECTION_DEDUP_MS);
    const key = `${tabId}|${input.navigationIndex}|${this.resolveCollectionKeyUrl(documentUrl)}`;
    if (this.activePageCollectionKeys.indexOf(key) >= 0 ||
      this.recentPageCollections.some((entry: BrowserFaviconPageCollectionEntry) => entry.key === key)) {
      return;
    }
    this.activePageCollectionKeys = this.activePageCollectionKeys.concat([key]);
    this.recentPageCollections = this.recentPageCollections.concat([{
      key: key,
      collectedAt: now
    }]).slice(Math.max(0, this.recentPageCollections.length + 1 - MAX_RECENT_PAGE_COLLECTIONS));
    void this.currentPageDiscoveryService.collect(input.controller, documentUrl)
      .then((result: SiteIconCurrentPageCollectionResult | undefined): void => {
        if (result === undefined) {
          return;
        }
        this.publishHomeShortcutIconAssociation(input, result.resolved);
      })
      .catch((error: Error) => {
        hilog.warn(
          FAVICON_LOG_DOMAIN,
          FAVICON_LOG_TAG,
          'page_candidates result=failed tab=%{public}s error=%{public}s',
          tabId,
          JSON.stringify(error)
        );
      })
      .finally(() => {
        this.activePageCollectionKeys = this.activePageCollectionKeys.filter((entry: string) => entry !== key);
      });
  }

  private persistFaviconAndPublishIfAllowed(input: BrowserFaviconApplyInput): void {
    if (input.privateMode) {
      return;
    }
    const faviconUrl = input.documentUrl.trim();
    if (faviconUrl.length <= 0) {
      return;
    }
    void this.siteIconService.ingestArkWebFavicon(faviconUrl, input.favicon)
      .then((result: SiteIconResult | undefined): void => {
        this.publishHomeShortcutIconAssociation(input, result);
      });
  }

  private shouldAcceptArkWebFavicon(input: BrowserFaviconApplyInput): boolean {
    const tabId = input.tabId.trim();
    const documentUrl = input.documentUrl.trim();
    const edge = this.resolvePixelMapEdge(input.favicon);
    if (tabId.length === 0 || edge <= 0) {
      return false;
    }
    const existing = this.arkWebReceipts.find((entry: BrowserFaviconArkWebReceiptEntry) => entry.tabId === tabId);
    if (existing !== undefined && existing.documentUrl === documentUrl && existing.edge >= edge) {
      existing.updatedAt = Date.now();
      return false;
    }
    const nextEntry: BrowserFaviconArkWebReceiptEntry = {
      tabId: tabId,
      documentUrl: documentUrl,
      edge: edge,
      updatedAt: Date.now()
    };
    const nextEntries = this.arkWebReceipts
      .filter((entry: BrowserFaviconArkWebReceiptEntry) => entry.tabId !== tabId)
      .concat([nextEntry])
      .sort((left: BrowserFaviconArkWebReceiptEntry, right: BrowserFaviconArkWebReceiptEntry) => (
        left.updatedAt - right.updatedAt
      ));
    this.arkWebReceipts = nextEntries.slice(Math.max(0, nextEntries.length - MAX_ARKWEB_FAVICON_RECEIPTS));
    return true;
  }

  private resolvePixelMapEdge(favicon: image.PixelMap): number {
    try {
      const info = favicon.getImageInfoSync();
      return Math.min(Math.max(0, Math.floor(info.size.width)), Math.max(0, Math.floor(info.size.height)));
    } catch (_error) {
      return 0;
    }
  }

  private resolveCollectionKeyUrl(documentUrl: string): string {
    const fragmentIndex = documentUrl.indexOf('#');
    return fragmentIndex >= 0 ? documentUrl.substring(0, fragmentIndex) : documentUrl;
  }

  private publishHomeShortcutIconAssociation(
    input: BrowserFaviconAssociationInput,
    result: SiteIconResult | undefined
  ): void {
    const launchContext = input.launchContext;
    if (input.privateMode || result === undefined || launchContext?.sourceType !== 'home_shortcut') {
      return;
    }
    HomeShortcutIconAssociationUpdateCenter.publishForLaunch(launchContext, {
      documentUrl: input.documentUrl,
      iconUri: result.uri,
      source: result.source,
      qualityScore: result.qualityScore,
      width: result.width,
      height: result.height
    });
  }
}

export const sharedBrowserFaviconCoordinator: BrowserFaviconCoordinator = new BrowserFaviconCoordinator();

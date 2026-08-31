import { BrowserTabState } from '../tabs/TabManager';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserNewWindowPolicyService } from '../../services/web/BrowserNewWindowPolicyService';
import {
  BrowserRuntimeTransactionSignal,
  BrowserRuntimeTransactionSignalService
} from './BrowserRuntimeTransactionSignalService';

export const BROWSER_CONTINUATION_WANT_KEY: string = 'aira.continuation.payload';

const BROWSER_CONTINUATION_VERSION: number = 1;
const MAX_CONTINUATION_URL_LENGTH: number = 8192;
const MAX_CONTINUATION_TITLE_LENGTH: number = 512;
const MAX_TRANSFER_ID_LENGTH: number = 160;
const MAX_REMEMBERED_TRANSFER_IDS: number = 32;
const MAX_SCROLL_OFFSET_Y: number = 100000000;

export interface BrowserContinuationPayload {
  version: number;
  transferId: string;
  url: string;
  title: string;
  scrollOffsetY: number;
  sourceTimestamp: number;
}

export interface BrowserContinuationEligibilityConnection {
  disconnect(): void;
}

type BrowserContinuationEligibilityListener = (eligible: boolean) => void;

interface BrowserContinuationSourceSnapshot {
  tabId: string;
  url: string;
  title: string;
  scrollOffsetY: number;
  baseEligible: boolean;
  eligible: boolean;
}

interface BrowserPendingContinuationScroll {
  transferId: string;
  tabId: string;
  expectedUrl: string;
  readyUrl: string;
  scrollOffsetY: number;
  applying: boolean;
}

class BrowserContinuationEligibilityConnectionImplementation implements BrowserContinuationEligibilityConnection {
  private disconnected: boolean = false;
  private readonly disconnectAction: () => void;

  constructor(disconnectAction: () => void) {
    this.disconnectAction = disconnectAction;
  }

  disconnect(): void {
    if (this.disconnected) {
      return;
    }
    this.disconnected = true;
    this.disconnectAction();
  }
}

/** Owns Aira's URL-plus-progress continuation contract across Ability, tab, and Web adapters. */
export class BrowserContinuationCoordinator {
  private readonly sourceSnapshotsByWindowId: Record<string, BrowserContinuationSourceSnapshot | undefined> = {};
  private readonly eligibilityListenersByWindowId: Record<string, BrowserContinuationEligibilityListener | undefined> = {};
  private readonly lastPublishedEligibilityByWindowId: Record<string, boolean | undefined> = {};
  private readonly pendingScrollByTabId: Record<string, BrowserPendingContinuationScroll | undefined> = {};
  private readonly transientFlowBlockersByTabId: Record<string, Record<string, boolean> | undefined> = {};
  private readonly rememberedTransferIds: string[] = [];
  private readonly newWindowPolicyService: BrowserNewWindowPolicyService = new BrowserNewWindowPolicyService();
  private readonly runtimeTransactionSignalService: BrowserRuntimeTransactionSignalService =
    new BrowserRuntimeTransactionSignalService();

  connectEligibility(
    windowId: string,
    listener: BrowserContinuationEligibilityListener
  ): BrowserContinuationEligibilityConnection {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    this.eligibilityListenersByWindowId[normalizedWindowId] = listener;
    const eligible = this.sourceSnapshotsByWindowId[normalizedWindowId]?.eligible === true;
    this.lastPublishedEligibilityByWindowId[normalizedWindowId] = eligible;
    this.notifyListener(listener, eligible);
    return new BrowserContinuationEligibilityConnectionImplementation((): void => {
      if (this.eligibilityListenersByWindowId[normalizedWindowId] === listener) {
        this.eligibilityListenersByWindowId[normalizedWindowId] = undefined;
      }
    });
  }

  publishActiveTab(windowId: string, tab: BrowserTabState | undefined): void {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    const previous = this.sourceSnapshotsByWindowId[normalizedWindowId];
    const normalizedUrl = tab?.url.trim() ?? '';
    const sameActiveTab = previous !== undefined && previous.tabId === (tab?.id ?? '');
    const scrollOffsetY = sameActiveTab
      ? previous.scrollOffsetY
      : this.normalizeScrollOffset(tab?.scrollOffsetY ?? 0);
    const baseEligible = this.isTabEligible(tab, normalizedUrl);
    const snapshot: BrowserContinuationSourceSnapshot = {
      tabId: tab?.id ?? '',
      url: normalizedUrl,
      title: this.truncate(tab?.title.trim() ?? '', MAX_CONTINUATION_TITLE_LENGTH),
      scrollOffsetY: scrollOffsetY,
      baseEligible: baseEligible,
      eligible: baseEligible && !this.isTabTransientFlowBlocked(tab?.id ?? '')
    };
    this.sourceSnapshotsByWindowId[normalizedWindowId] = snapshot;
    this.publishEligibilityIfChanged(normalizedWindowId, snapshot.eligible);
  }

  updateActiveTabScroll(tabId: string, scrollOffsetY: number): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    Object.keys(this.sourceSnapshotsByWindowId).forEach((windowId: string): void => {
      const snapshot = this.sourceSnapshotsByWindowId[windowId];
      if (snapshot === undefined || snapshot.tabId !== normalizedTabId) {
        return;
      }
      snapshot.scrollOffsetY = this.normalizeScrollOffset(scrollOffsetY);
    });
  }

  setTransientFlowBlocked(tabId: string, blocker: string, blocked: boolean): void {
    const normalizedTabId = tabId.trim();
    const normalizedBlocker = blocker.trim();
    if (normalizedTabId.length === 0 || normalizedBlocker.length === 0) {
      return;
    }
    const blockers = this.transientFlowBlockersByTabId[normalizedTabId] ?? {};
    if (blocked) {
      blockers[normalizedBlocker] = true;
      this.transientFlowBlockersByTabId[normalizedTabId] = blockers;
    } else {
      blockers[normalizedBlocker] = false;
      if (!Object.keys(blockers).some((key: string): boolean => blockers[key] === true)) {
        this.transientFlowBlockersByTabId[normalizedTabId] = undefined;
      }
    }
    this.refreshEligibilityForTab(normalizedTabId);
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    this.pendingScrollByTabId[normalizedTabId] = undefined;
    this.transientFlowBlockersByTabId[normalizedTabId] = undefined;
    Object.keys(this.sourceSnapshotsByWindowId).forEach((windowId: string): void => {
      const snapshot = this.sourceSnapshotsByWindowId[windowId];
      if (snapshot?.tabId !== normalizedTabId) {
        return;
      }
      snapshot.baseEligible = false;
      snapshot.eligible = false;
      this.publishEligibilityIfChanged(windowId, false);
    });
  }

  clearWindow(windowId: string): void {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    this.sourceSnapshotsByWindowId[normalizedWindowId] = undefined;
    this.lastPublishedEligibilityByWindowId[normalizedWindowId] = undefined;
  }

  isWindowEligible(windowId: string): boolean {
    return this.sourceSnapshotsByWindowId[this.normalizeWindowId(windowId)]?.eligible === true;
  }

  buildOutgoingPayload(windowId: string): BrowserContinuationPayload | undefined {
    const snapshot = this.sourceSnapshotsByWindowId[this.normalizeWindowId(windowId)];
    if (snapshot === undefined || !snapshot.eligible) {
      return undefined;
    }
    return {
      version: BROWSER_CONTINUATION_VERSION,
      transferId: this.createTransferId(),
      url: snapshot.url,
      title: snapshot.title,
      scrollOffsetY: snapshot.scrollOffsetY,
      sourceTimestamp: Date.now()
    };
  }

  serializePayload(payload: BrowserContinuationPayload): string {
    return JSON.stringify(payload);
  }

  parseIncomingPayload(parameters: Record<string, Object> | undefined): BrowserContinuationPayload | undefined {
    const serialized = String(parameters?.[BROWSER_CONTINUATION_WANT_KEY] ?? '').trim();
    if (serialized.length === 0) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(serialized) as Record<string, Object>;
      const payload: BrowserContinuationPayload = {
        version: Number(parsed['version'] ?? 0),
        transferId: String(parsed['transferId'] ?? '').trim(),
        url: String(parsed['url'] ?? '').trim(),
        title: this.truncate(String(parsed['title'] ?? '').trim(), MAX_CONTINUATION_TITLE_LENGTH),
        scrollOffsetY: this.normalizeScrollOffset(Number(parsed['scrollOffsetY'] ?? 0)),
        sourceTimestamp: Number(parsed['sourceTimestamp'] ?? 0)
      };
      return this.isPayloadValid(payload) ? payload : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  copyPayload(payload: BrowserContinuationPayload | undefined): BrowserContinuationPayload | undefined {
    if (payload === undefined) {
      return undefined;
    }
    return {
      version: payload.version,
      transferId: payload.transferId,
      url: payload.url,
      title: payload.title,
      scrollOffsetY: payload.scrollOffsetY,
      sourceTimestamp: payload.sourceTimestamp
    };
  }

  claimIncomingPayload(payload: BrowserContinuationPayload): boolean {
    if (!this.isPayloadValid(payload) || this.rememberedTransferIds.indexOf(payload.transferId) >= 0) {
      return false;
    }
    this.rememberedTransferIds.push(payload.transferId);
    if (this.rememberedTransferIds.length > MAX_REMEMBERED_TRANSFER_IDS) {
      this.rememberedTransferIds.splice(0, this.rememberedTransferIds.length - MAX_REMEMBERED_TRANSFER_IDS);
    }
    return true;
  }

  releaseIncomingPayload(transferId: string): void {
    const index = this.rememberedTransferIds.indexOf(transferId.trim());
    if (index >= 0) {
      this.rememberedTransferIds.splice(index, 1);
    }
  }

  isIncomingPayloadAlreadyApplied(payload: BrowserContinuationPayload, tabs: BrowserTabState[]): boolean {
    return tabs.some((tab: BrowserTabState): boolean => {
      return tab.launchContext.sourceType === 'app_continuation' &&
        tab.launchContext.key === payload.transferId;
    });
  }

  bindIncomingTab(payload: BrowserContinuationPayload, tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0 || payload.scrollOffsetY <= 0) {
      return;
    }
    this.pendingScrollByTabId[normalizedTabId] = {
      transferId: payload.transferId,
      tabId: normalizedTabId,
      expectedUrl: payload.url,
      readyUrl: '',
      scrollOffsetY: payload.scrollOffsetY,
      applying: false
    };
  }

  async applyPendingScrollAfterLoad(
    tabId: string,
    finalUrl: string,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): Promise<boolean> {
    const normalizedTabId = tabId.trim();
    const pending = this.pendingScrollByTabId[normalizedTabId];
    if (pending === undefined) {
      return false;
    }
    pending.readyUrl = finalUrl.trim();
    return await this.applyPendingScroll(normalizedTabId, runtimeLifecyclePort);
  }

  async applyPendingScrollAfterRuntimeReady(
    tabId: string,
    currentUrl: string,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): Promise<boolean> {
    const normalizedTabId = tabId.trim();
    const pending = this.pendingScrollByTabId[normalizedTabId];
    if (pending === undefined) {
      return false;
    }
    pending.readyUrl = currentUrl.trim();
    return await this.applyPendingScroll(normalizedTabId, runtimeLifecyclePort);
  }

  private async applyPendingScroll(
    tabId: string,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): Promise<boolean> {
    const pending = this.pendingScrollByTabId[tabId];
    if (pending === undefined || pending.applying || pending.readyUrl.length === 0) {
      return false;
    }
    if (!this.urlsMatch(pending.expectedUrl, pending.readyUrl)) {
      this.pendingScrollByTabId[tabId] = undefined;
      return false;
    }
    pending.applying = true;
    const scrollY = this.normalizeScrollOffset(pending.scrollOffsetY);
    const script = `window.scrollTo(0, ${scrollY}); String(window.scrollY || 0);`;
    try {
      await runtimeLifecyclePort.runJavaScriptOnLiveRuntime(
        tabId,
        script,
        'continuation_runtime_not_ready'
      );
      this.pendingScrollByTabId[tabId] = undefined;
      return true;
    } catch (_error) {
      pending.applying = false;
      return false;
    }
  }

  private isTabEligible(tab: BrowserTabState | undefined, url: string): boolean {
    if (tab === undefined || tab.id.trim().length === 0 || tab.isHome || tab.privacyMode !== 'regular' ||
      tab.dataScope !== 'profile_persistent' || tab.runtimeState !== 'active' || tab.lastLoadedAt <= 0) {
      return false;
    }
    if (!this.isHttpUrl(url) || url.length > MAX_CONTINUATION_URL_LENGTH) {
      return false;
    }
    if (this.newWindowPolicyService.isPopupAuthNavigationTarget(url)) {
      return false;
    }
    const transactionSignal: BrowserRuntimeTransactionSignal | undefined =
      this.runtimeTransactionSignalService.resolveSignal(tab);
    return transactionSignal?.kind !== 'auth' && transactionSignal?.kind !== 'payment';
  }

  private isPayloadValid(payload: BrowserContinuationPayload): boolean {
    return payload.version === BROWSER_CONTINUATION_VERSION &&
      payload.transferId.length > 0 && payload.transferId.length <= MAX_TRANSFER_ID_LENGTH &&
      this.isHttpUrl(payload.url) && payload.url.length <= MAX_CONTINUATION_URL_LENGTH &&
      payload.title.length <= MAX_CONTINUATION_TITLE_LENGTH &&
      Number.isFinite(payload.scrollOffsetY) && payload.scrollOffsetY >= 0 &&
      Number.isFinite(payload.sourceTimestamp) && payload.sourceTimestamp > 0;
  }

  private publishEligibilityIfChanged(windowId: string, eligible: boolean): void {
    if (this.lastPublishedEligibilityByWindowId[windowId] === eligible) {
      return;
    }
    this.lastPublishedEligibilityByWindowId[windowId] = eligible;
    const listener = this.eligibilityListenersByWindowId[windowId];
    if (listener !== undefined) {
      this.notifyListener(listener, eligible);
    }
  }

  private refreshEligibilityForTab(tabId: string): void {
    Object.keys(this.sourceSnapshotsByWindowId).forEach((windowId: string): void => {
      const snapshot = this.sourceSnapshotsByWindowId[windowId];
      if (snapshot === undefined || snapshot.tabId !== tabId) {
        return;
      }
      snapshot.eligible = snapshot.baseEligible && !this.isTabTransientFlowBlocked(tabId);
      this.publishEligibilityIfChanged(windowId, snapshot.eligible);
    });
  }

  private isTabTransientFlowBlocked(tabId: string): boolean {
    const blockers = this.transientFlowBlockersByTabId[tabId.trim()];
    return blockers !== undefined &&
      Object.keys(blockers).some((key: string): boolean => blockers[key] === true);
  }

  private notifyListener(listener: BrowserContinuationEligibilityListener, eligible: boolean): void {
    try {
      listener(eligible);
    } catch (_error) {
    }
  }

  private urlsMatch(expectedUrl: string, finalUrl: string): boolean {
    return expectedUrl.trim() === finalUrl.trim();
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('https://') || normalized.startsWith('http://');
  }

  private normalizeScrollOffset(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.min(MAX_SCROLL_OFFSET_Y, Math.round(value));
  }

  private normalizeWindowId(windowId: string): string {
    const normalized = windowId.trim();
    return normalized.length > 0 ? normalized : 'window-main';
  }

  private truncate(value: string, maxLength: number): string {
    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  private createTransferId(): string {
    const randomPart = Math.floor(Math.random() * 0xFFFFFF).toString(36);
    return `continuation-${Date.now().toString(36)}-${randomPart}`;
  }
}

export const sharedBrowserContinuationCoordinator: BrowserContinuationCoordinator =
  new BrowserContinuationCoordinator();

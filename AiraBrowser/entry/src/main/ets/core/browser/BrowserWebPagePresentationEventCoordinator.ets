import { image } from '@kit.ImageKit';
import { BrowserTabManagerPort } from '../tabs/TabManager';
import { WebEventRouter, WebTitleEventRoute } from '../web/WebEventRouter';
import {
  BrowserWebEventCommitCoordinator,
  BrowserWebFollowupEventHost
} from './BrowserWebEventCommitCoordinator';
import {
  BrowserFaviconApplyHost,
  BrowserFaviconCoordinator,
  sharedBrowserFaviconCoordinator
} from './BrowserFaviconCoordinator';
import { BrowserBackgroundTabPreviewRuntimeCoordinator } from './BrowserBackgroundTabPreviewRuntimeCoordinator';
import {
  BrowserPrivateProfileCookieLifecycleHost,
  BrowserPrivateProfileLifecycleCoordinator
} from './BrowserPrivateProfileLifecycleCoordinator';
import { BrowserWebLoadRuntimeCoordinator } from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import { BrowserWebNavigationStateSyncCoordinator } from '../../services/web/BrowserWebNavigationStateSyncCoordinator';
import { BrowserBackgroundOpenPromptCoordinator } from './BrowserBackgroundOpenPromptCoordinator';
import { BrowserWebPageLifecycleApplicationHost } from './BrowserWebPageLifecycleModels';

export interface BrowserWebPagePresentationEventDependencies {
  tabManager: BrowserTabManagerPort;
  webEventRouter: WebEventRouter;
  commitCoordinator: BrowserWebEventCommitCoordinator;
  followupHost: BrowserWebFollowupEventHost;
  faviconCoordinator?: BrowserFaviconCoordinator;
  faviconHost: BrowserFaviconApplyHost;
  webLoadRuntimeCoordinator: BrowserWebLoadRuntimeCoordinator;
  navigationStateSyncCoordinator: BrowserWebNavigationStateSyncCoordinator;
  backgroundTabPreviewRuntimeCoordinator: BrowserBackgroundTabPreviewRuntimeCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  privateProfileCookieLifecycleHost: BrowserPrivateProfileCookieLifecycleHost;
  isActivePageLoadCompleted: () => boolean;
  getLastAppliedPageProgress: () => number;
  metadataVisualUpdateDelayMs: number;
}

export class BrowserWebPagePresentationEventCoordinator {
  private readonly dependencies: BrowserWebPagePresentationEventDependencies;
  private readonly faviconCoordinator: BrowserFaviconCoordinator;
  private pendingScrollDeferredTitleByTabId: Record<string, string | undefined> = {};
  private pendingScrollDeferredTitleUrlByTabId: Record<string, string | undefined> = {};
  private pendingScrollDeferredTitleTimerByTabId: Record<string, number | undefined> = {};
  private pendingScrollDeferredFaviconByTabId: Record<string, image.PixelMap | undefined> = {};
  private pendingScrollDeferredFaviconTimerByTabId: Record<string, number | undefined> = {};

  constructor(dependencies: BrowserWebPagePresentationEventDependencies) {
    this.dependencies = dependencies;
    this.faviconCoordinator = dependencies.faviconCoordinator ?? sharedBrowserFaviconCoordinator;
  }

  handleProgressChange(
    tabId: string,
    progress: number,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.dependencies.backgroundOpenPromptCoordinator.updateTab(tabId, {
      progress: progress,
      isLoading: progress < 100
    });
    const backgroundPreviewRuntimeCoordinator = this.dependencies.backgroundTabPreviewRuntimeCoordinator;
    if (backgroundPreviewRuntimeCoordinator.shouldTreatProgressAsPageReady(progress)) {
      backgroundPreviewRuntimeCoordinator.schedulePageReadyCapture(tabId, 'progress_100');
    }
    if (progress >= 100) {
      this.dependencies.privateProfileLifecycleCoordinator.savePreservedCookiesForTabIfNeeded(
        tabId,
        this.dependencies.privateProfileCookieLifecycleHost
      );
    }
    if (!this.shouldApplyProgressUpdate(tabId, progress, host)) {
      return;
    }
    this.applyProgressCommit(
      progress,
      this.resolveFollowupRouteShouldHandleActiveTab(tabId, host)
    );
  }

  clearDeferredPageMetadata(tabId: string): void {
    const titleTimer = this.pendingScrollDeferredTitleTimerByTabId[tabId] ?? -1;
    if (titleTimer >= 0) {
      clearTimeout(titleTimer);
    }
    this.pendingScrollDeferredTitleTimerByTabId[tabId] = -1;
    this.pendingScrollDeferredTitleByTabId[tabId] = undefined;
    this.pendingScrollDeferredTitleUrlByTabId[tabId] = undefined;
    const faviconTimer = this.pendingScrollDeferredFaviconTimerByTabId[tabId] ?? -1;
    if (faviconTimer >= 0) {
      clearTimeout(faviconTimer);
    }
    this.pendingScrollDeferredFaviconTimerByTabId[tabId] = -1;
    this.pendingScrollDeferredFaviconByTabId[tabId] = undefined;
  }

  flushDeferredPageMetadata(
    tabId: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    if (tabId.trim().length <= 0) {
      return;
    }
    const titleTimer = this.pendingScrollDeferredTitleTimerByTabId[tabId] ?? -1;
    if (titleTimer >= 0) {
      clearTimeout(titleTimer);
      this.pendingScrollDeferredTitleTimerByTabId[tabId] = -1;
    }
    const pendingTitle = this.pendingScrollDeferredTitleByTabId[tabId];
    this.pendingScrollDeferredTitleByTabId[tabId] = undefined;
    const pendingTitleUrl = this.pendingScrollDeferredTitleUrlByTabId[tabId] ?? '';
    this.pendingScrollDeferredTitleUrlByTabId[tabId] = undefined;
    if (pendingTitle !== undefined) {
      this.applyDeferredTitle(tabId, pendingTitle, pendingTitleUrl, host);
    }
    const faviconTimer = this.pendingScrollDeferredFaviconTimerByTabId[tabId] ?? -1;
    if (faviconTimer >= 0) {
      clearTimeout(faviconTimer);
      this.pendingScrollDeferredFaviconTimerByTabId[tabId] = -1;
    }
    const pendingFavicon = this.pendingScrollDeferredFaviconByTabId[tabId];
    this.pendingScrollDeferredFaviconByTabId[tabId] = undefined;
    if (pendingFavicon !== undefined) {
      this.applyDeferredFavicon(tabId, pendingFavicon, host);
    }
  }

  handleTitleReceive(
    tabId: string,
    title: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    const titleUrl = this.dependencies.navigationStateSyncCoordinator.resolveCurrentDocumentUrlForTitle(tabId);
    if (host.shouldDeferTitleVisualUpdate(tabId)) {
      this.scheduleDeferredTitleReceive(tabId, title, titleUrl, host);
      return;
    }
    this.applyTitle(tabId, title, titleUrl, host);
  }

  private applyDeferredTitle(
    tabId: string,
    title: string,
    titleUrl: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.applyTitle(tabId, title, titleUrl, host);
  }

  handleFaviconReceived(
    tabId: string,
    event: OnFaviconReceivedEvent,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    const favicon = event.favicon;
    if (host.shouldDeferFaviconVisualUpdate(tabId)) {
      this.scheduleDeferredFaviconReceive(tabId, favicon, host);
      return;
    }
    this.applyFavicon(tabId, favicon, host);
  }

  private applyDeferredFavicon(
    tabId: string,
    favicon: image.PixelMap,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.applyFavicon(tabId, favicon, host);
  }

  private applyTitle(
    tabId: string,
    title: string,
    titleUrl: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    const navigationStateSyncCoordinator = this.dependencies.navigationStateSyncCoordinator;
    const normalizedTitleUrl = titleUrl.trim().length > 0 ?
      titleUrl.trim() :
      navigationStateSyncCoordinator.resolveCurrentDocumentUrlForTitle(tabId);
    if (!navigationStateSyncCoordinator.isTitleUrlCurrentForTab(tabId, normalizedTitleUrl)) {
      return;
    }
    navigationStateSyncCoordinator.recordReceivedTitle(tabId, normalizedTitleUrl, title);
    const route = this.resolveTitleRoute(tabId, host);
    this.dependencies.commitCoordinator.applyTitleReceive(
      tabId,
      title,
      route.shouldUpdateTabTitle,
      route.shouldUpdateActiveTitle,
      this.dependencies.followupHost
    );
    this.dependencies.backgroundOpenPromptCoordinator.updateTab(tabId, { title: title });
  }

  private resolveFollowupRouteShouldHandleActiveTab(
    tabId: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): boolean {
    return this.dependencies.webEventRouter.resolveFollowupRoute(
      tabId,
      host.resolveShellFacts().activeTabId,
      host.resolveShellFacts().webPageVisible
    ).shouldHandleActiveTab;
  }

  private resolveTitleRoute(
    tabId: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): WebTitleEventRoute {
    return this.dependencies.webEventRouter.resolveTitleRoute(
      tabId,
      host.resolveShellFacts().activeTabId,
      host.resolveShellFacts().webPageVisible
    );
  }

  private applyFavicon(
    tabId: string,
    favicon: image.PixelMap,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    const tab = this.dependencies.tabManager.getTab(host.resolveShellFacts().tabs, tabId);
    const faviconAccepted = this.faviconCoordinator.handleFaviconReceived({
      tabId: tabId,
      favicon: favicon,
      documentUrl: this.dependencies.navigationStateSyncCoordinator.resolveCurrentDocumentUrlForTitle(tabId),
      privateMode: tab !== undefined && this.dependencies.privateProfileLifecycleCoordinator.isSessionEphemeralTab({
        profileId: tab.profileId,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope,
        sessionId: tab.id
      }),
      launchContext: tab?.launchContext
    }, this.dependencies.faviconHost);
    if (faviconAccepted) {
      this.dependencies.backgroundOpenPromptCoordinator.updateTab(tabId, { favicon: favicon });
    }
  }

  private applyProgressCommit(progress: number, shouldHandleActiveTab: boolean): void {
    const commit = this.dependencies.commitCoordinator.buildProgressCommit(shouldHandleActiveTab, progress);
    this.dependencies.commitCoordinator.applyProgressCommit(commit, this.dependencies.followupHost);
  }

  private shouldApplyProgressUpdate(
    tabId: string,
    progress: number,
    host: BrowserWebPageLifecycleApplicationHost
  ): boolean {
    const facts = host.resolveShellFacts();
    if (tabId !== facts.activeTabId || !facts.webPageVisible) {
      return false;
    }
    const clampedProgress = Math.max(0, Math.min(100, Math.round(progress)));
    if (this.dependencies.isActivePageLoadCompleted() && clampedProgress < 100) {
      return false;
    }
    const lastAppliedPageProgress = this.dependencies.getLastAppliedPageProgress();
    return clampedProgress !== lastAppliedPageProgress;
  }

  private scheduleDeferredTitleReceive(
    tabId: string,
    title: string,
    titleUrl: string,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.pendingScrollDeferredTitleByTabId[tabId] = title;
    this.pendingScrollDeferredTitleUrlByTabId[tabId] = titleUrl.length > 0 ?
      titleUrl :
      this.dependencies.navigationStateSyncCoordinator.resolveCurrentDocumentUrlForTitle(tabId);
    const existingTimer = this.pendingScrollDeferredTitleTimerByTabId[tabId] ?? -1;
    if (existingTimer >= 0) {
      clearTimeout(existingTimer);
    }
    this.pendingScrollDeferredTitleTimerByTabId[tabId] = setTimeout(() => {
      this.pendingScrollDeferredTitleTimerByTabId[tabId] = -1;
      const pendingTitle = this.pendingScrollDeferredTitleByTabId[tabId];
      const pendingTitleUrl = this.pendingScrollDeferredTitleUrlByTabId[tabId] ?? '';
      this.pendingScrollDeferredTitleByTabId[tabId] = undefined;
      this.pendingScrollDeferredTitleUrlByTabId[tabId] = undefined;
      if (pendingTitle !== undefined) {
        this.applyDeferredTitle(tabId, pendingTitle, pendingTitleUrl, host);
      }
    }, host.resolveDeferredPresentationDelayMs(this.dependencies.metadataVisualUpdateDelayMs));
  }

  private scheduleDeferredFaviconReceive(
    tabId: string,
    favicon: image.PixelMap,
    host: BrowserWebPageLifecycleApplicationHost
  ): void {
    this.pendingScrollDeferredFaviconByTabId[tabId] = favicon;
    const existingTimer = this.pendingScrollDeferredFaviconTimerByTabId[tabId] ?? -1;
    if (existingTimer >= 0) {
      clearTimeout(existingTimer);
    }
    this.pendingScrollDeferredFaviconTimerByTabId[tabId] = setTimeout(() => {
      this.pendingScrollDeferredFaviconTimerByTabId[tabId] = -1;
      const pendingFavicon = this.pendingScrollDeferredFaviconByTabId[tabId];
      this.pendingScrollDeferredFaviconByTabId[tabId] = undefined;
      if (pendingFavicon !== undefined) {
        this.applyDeferredFavicon(tabId, pendingFavicon, host);
      }
    }, host.resolveDeferredPresentationDelayMs(this.dependencies.metadataVisualUpdateDelayMs));
  }
}

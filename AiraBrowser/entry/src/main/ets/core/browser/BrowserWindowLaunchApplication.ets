import {
  BrowserDataScope,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  BrowserLaunchPayload,
  BrowserWindowRuntime
} from '../../app/runtime/BrowserWindowRuntime';
import { resolveBrowserNewWindowTestTitle } from '../../app/debug/BrowserNewWindowTestPage';
import { WebAppSessionCoordinator, WebAppSessionSnapshot } from '../webapps/WebAppSessionCoordinator';
import {
  BrowserCreateTabOptions,
  BrowserTabRuntimePatch,
  BrowserTabState
} from '../tabs/TabManager';
import { BrowserAppShortcutActionCoordinator } from './BrowserAppShortcutActionCoordinator';
import { BrowserAppUrlOpenCoordinator } from './BrowserAppUrlOpenCoordinator';
import { BrowserForegroundTabCreationCoordinator } from './BrowserForegroundTabCreationCoordinator';
import {
  BrowserPrivateBoundaryNavigationService,
  BrowserPrivateBoundaryRouteParams
} from './BrowserPrivateBoundaryNavigationService';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserWindowLaunchApplication } from './BrowserWindowContextCoordinator';
import {
  BrowserContinuationPayload,
  sharedBrowserContinuationCoordinator
} from './BrowserContinuationCoordinator';

export interface BrowserWindowLaunchApplicationFacts {
  currentWindowId: string;
  tabs: BrowserTabState[];
  activeTabId: string;
  showHomePage: boolean;
}

export interface BrowserWindowLaunchApplicationShell {
  readFacts: () => BrowserWindowLaunchApplicationFacts;
  applyWebAppSessionSnapshot: (snapshot: WebAppSessionSnapshot, source: string) => void;
  scanQr: () => void;
  openRoutedAppShortcut: (
    payload: BrowserLaunchPayload,
    boundary: BrowserPrivateBoundaryRouteParams
  ) => void;
  showToast: (message: string) => void;
  publishHelper: (message: string) => void;
}

interface BrowserWindowFixedLaunchDependencies {
  appShortcutActionCoordinator: BrowserAppShortcutActionCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator;
  privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService;
  tabHomeCoordinator: BrowserTabHomeCoordinator;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  webAppSessionCoordinator: WebAppSessionCoordinator;
}

export class BrowserWindowFixedLaunchApplication implements BrowserWindowLaunchApplication {
  private readonly dependencies: BrowserWindowFixedLaunchDependencies;
  private readonly shell: BrowserWindowLaunchApplicationShell;

  constructor(
    dependencies: BrowserWindowFixedLaunchDependencies,
    shell: BrowserWindowLaunchApplicationShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  apply(payload: BrowserLaunchPayload): void {
    void this.applyAsync(payload);
  }

  private async applyAsync(payload: BrowserLaunchPayload): Promise<void> {
    if (payload.continuation !== undefined) {
      await this.openContinuation(payload.continuation);
      return;
    }
    if (payload.tabMoveRequestId.length > 0) {
      await this.openTabWindowMove(payload);
      return;
    }
    if (payload.privateWindowInstanceId.length > 0) {
      this.openPrivateWindowLaunch(payload);
      return;
    }
    if (payload.appShortcut.length > 0) {
      this.openAppShortcut(payload);
      return;
    }
    if (payload.shortcut !== undefined) {
      await this.openDesktopWebEntry(payload);
      return;
    }
    this.openExternalUrl(payload);
  }

  private async openContinuation(payload: BrowserContinuationPayload): Promise<void> {
    if (sharedBrowserContinuationCoordinator.isIncomingPayloadAlreadyApplied(
      payload,
      this.shell.readFacts().tabs
    )) {
      return;
    }
    if (!sharedBrowserContinuationCoordinator.claimIncomingPayload(payload)) {
      return;
    }
    try {
      const targetTabId = await this.dependencies.foregroundTabCreationCoordinator.createNewTab({
        initialUrl: payload.url,
        initialTitle: payload.title.length > 0 ? payload.title : payload.url,
        options: {
          profileId: DEFAULT_BROWSER_PROFILE_ID,
          privacyMode: 'regular',
          dataScope: 'profile_persistent',
          openSource: 'external',
          launchContext: {
            sourceType: 'app_continuation',
            sourceId: payload.transferId,
            sourceUrl: payload.url,
            key: payload.transferId
          }
        },
        runtimeOptions: {
          skipCurrentTabPreviewForForegroundOpen: true
        },
        homePresentationMode: 'direct'
      });
      if (targetTabId.length === 0) {
        throw new Error('Continuation target tab was not created.');
      }
      sharedBrowserContinuationCoordinator.bindIncomingTab(payload, targetTabId);
    } catch (_error) {
      sharedBrowserContinuationCoordinator.releaseIncomingPayload(payload.transferId);
      this.shell.showToast('无法接续此页面');
    }
  }

  private async openTabWindowMove(payload: BrowserLaunchPayload): Promise<void> {
    const moveRequest = BrowserWindowRuntime.claimTabWindowMove(payload.tabMoveRequestId);
    if (moveRequest === undefined) {
      return;
    }
    const targetWindowId = this.shell.readFacts().currentWindowId;
    try {
      const sourceTab = moveRequest.tab;
      const targetUrl = this.resolveMovedTabTargetUrl(sourceTab);
      this.dependencies.tabHomeCoordinator.applyBoundary(
        sourceTab.profileId,
        sourceTab.privacyMode,
        sourceTab.dataScope
      );
      const targetTabId = await this.dependencies.foregroundTabCreationCoordinator.createNewTabFromWindowMove({
        initialUrl: targetUrl,
        initialTitle: sourceTab.title.trim().length > 0 ? sourceTab.title : targetUrl,
        options: {
          profileId: sourceTab.profileId,
          privacyMode: sourceTab.privacyMode,
          dataScope: sourceTab.dataScope,
          launchContext: sourceTab.launchContext,
          openSource: sourceTab.openSource
        },
        runtimeOptions: {
          skipCurrentTabPreviewForForegroundOpen: true
        },
        homePresentationMode: 'direct'
      }, this.buildMovedTabPatch(sourceTab, targetUrl));
      BrowserWindowRuntime.acknowledgeTabWindowMove({
        requestId: moveRequest.requestId,
        accepted: true,
        targetWindowId: targetWindowId,
        targetTabId: targetTabId,
        message: '新窗口已接收标签页。'
      });
    } catch (_error) {
      BrowserWindowRuntime.acknowledgeTabWindowMove({
        requestId: moveRequest.requestId,
        accepted: false,
        targetWindowId: targetWindowId,
        targetTabId: '',
        message: '新窗口无法保存这个标签页。'
      });
    }
  }

  private buildMovedTabPatch(sourceTab: BrowserTabState, targetUrl: string): BrowserTabRuntimePatch {
    const navigationHistory = this.resolveMovedTabHistory(sourceTab, targetUrl);
    const navigationIndex = this.resolveMovedTabHistoryIndex(sourceTab, navigationHistory, targetUrl);
    return {
      profileId: sourceTab.profileId,
      title: sourceTab.title.trim().length > 0 ? sourceTab.title : targetUrl,
      url: sourceTab.isHome ? sourceTab.url : targetUrl,
      isHome: sourceTab.isHome,
      lastActiveAt: Date.now(),
      pendingUrl: sourceTab.isHome ? '' : targetUrl,
      navigationHistory: navigationHistory,
      navigationIndex: navigationIndex,
      runtimeState: 'active',
      lastError: '',
      lastRestoreReason: sourceTab.isHome ? '' : 'external_launch',
      lastDiscardReason: '',
      lastCrashReason: '',
      lastLoadedAt: 0,
      webStatePath: '',
      webStateUpdatedAt: 0,
      scrollOffsetY: 0,
      lastGoodUrl: sourceTab.lastGoodUrl,
      lastGoodTitle: sourceTab.lastGoodTitle,
      lastRestorableUrl: sourceTab.lastRestorableUrl,
      lastRestorableTitle: sourceTab.lastRestorableTitle,
      lastRestoreType: sourceTab.isHome ? 'none' : 'reload',
      privacyMode: sourceTab.privacyMode,
      dataScope: sourceTab.dataScope,
      launchContext: sourceTab.launchContext,
      openerTabId: '',
      openSource: sourceTab.openSource,
      openedByNewWindow: false
    };
  }

  private resolveMovedTabTargetUrl(tab: BrowserTabState): string {
    const historyUrl = tab.navigationIndex >= 0 ? tab.navigationHistory[tab.navigationIndex] ?? '' : '';
    const candidates = [historyUrl, tab.pendingUrl, tab.url, tab.lastGoodUrl, tab.lastRestorableUrl];
    return candidates.find((candidate: string): boolean => candidate.trim().length > 0)?.trim() ?? 'aira://home';
  }

  private resolveMovedTabHistory(tab: BrowserTabState, targetUrl: string): string[] {
    if (tab.navigationHistory.length > 0) {
      return tab.navigationHistory.slice();
    }
    return [targetUrl];
  }

  private resolveMovedTabHistoryIndex(
    tab: BrowserTabState,
    navigationHistory: string[],
    targetUrl: string
  ): number {
    if (tab.navigationIndex >= 0 && tab.navigationIndex < navigationHistory.length) {
      return tab.navigationIndex;
    }
    const targetIndex = navigationHistory.lastIndexOf(targetUrl);
    return targetIndex >= 0 ? targetIndex : navigationHistory.length - 1;
  }

  private openPrivateWindowLaunch(payload: BrowserLaunchPayload): void {
    const options: BrowserCreateTabOptions = {
      profileId: payload.profileId,
      privacyMode: payload.privacyMode,
      dataScope: payload.dataScope
    };
    const facts = this.shell.readFacts();
    const targetUrl = payload.uri.trim();
    if (targetUrl.length > 0) {
      this.dependencies.tabHomeCoordinator.applyBoundary(payload.profileId, payload.privacyMode, payload.dataScope);
      this.dependencies.foregroundTabCreationCoordinator.createNewTabNow({
        initialUrl: targetUrl,
        initialTitle: targetUrl,
        options: options,
        runtimeOptions: {
          skipCurrentTabPreviewForForegroundOpen: true
        }
      });
      this.shell.publishHelper('已在新的隐私窗口中打开链接。');
      return;
    }
    if (facts.tabs.length === 0) {
      this.dependencies.foregroundTabCreationCoordinator.createNewTabNow({
        initialUrl: 'aira://home',
        initialTitle: '隐私标签页',
        options: options,
        homePresentationMode: 'direct',
        runtimeOptions: {
          skipCurrentTabPreviewForForegroundOpen: true
        }
      });
      this.dependencies.tabHomeCoordinator.showHomeSurface('已打开隐私窗口', options);
      return;
    }
    this.dependencies.tabHomeCoordinator.showHomeSurface('已打开隐私窗口', options);
  }

  private openAppShortcut(payload: BrowserLaunchPayload): void {
    const plan = this.dependencies.appShortcutActionCoordinator.buildPlan(payload.appShortcut);
    if (plan.inlineAction === 'scan_qr') {
      this.shell.scanQr();
      return;
    }
    if (plan.inlineAction === 'focus_search') {
      // UIAbility ingress already accepted this Search Invocation. Payload
      // consumption must not reinforce the same desktop request again.
      return;
    }
    if (plan.shouldRoute) {
      this.shell.openRoutedAppShortcut(
        payload,
        this.dependencies.privateBoundaryNavigationService.buildRouteParams(
          payload.dataScope,
          payload.privacyMode
        )
      );
    }
  }

  private async openDesktopWebEntry(payload: BrowserLaunchPayload): Promise<void> {
    const initialFacts = this.shell.readFacts();
    const preparation = await this.dependencies.webAppSessionCoordinator.prepareLaunch(
      payload,
      initialFacts.currentWindowId,
      initialFacts.tabs,
      initialFacts.activeTabId
    );
    const currentFacts = this.shell.readFacts();
    if (!preparation.accepted || preparation.snapshot.windowId !== currentFacts.currentWindowId) {
      return;
    }
    this.shell.applyWebAppSessionSnapshot(preparation.snapshot, 'webapp-launch');
    const plan = preparation.plan;
    if (plan.action === 'invalid') {
      this.shell.showToast(plan.message);
      return;
    }
    if (plan.action === 'activate_existing_tab') {
      await this.dependencies.tabSwitchCoordinator.switchToTab(plan.tabId);
      return;
    }
    const executionFacts = this.shell.readFacts();
    if (executionFacts.showHomePage && executionFacts.activeTabId.length === 0) {
      const privacyMode = normalizeBrowserSessionPrivacyMode(plan.options.privacyMode);
      this.dependencies.tabHomeCoordinator.applyBoundary(
        plan.options.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
        privacyMode,
        normalizeBrowserDataScope(plan.options.dataScope, privacyMode)
      );
      await this.dependencies.foregroundTabCreationCoordinator.createNewTab({
        initialUrl: plan.targetUrl,
        initialTitle: resolveBrowserNewWindowTestTitle(plan.targetUrl, plan.targetUrl),
        options: plan.options,
        runtimeOptions: {
          skipCurrentTabPreviewForForegroundOpen: true
        }
      });
      this.shell.publishHelper(plan.message);
      return;
    }
    await this.dependencies.foregroundTabCreationCoordinator.createNewTab({
      initialUrl: plan.targetUrl,
      initialTitle: plan.targetUrl,
      options: plan.options,
      runtimeOptions: {}
    });
  }

  private openExternalUrl(payload: BrowserLaunchPayload): void {
    const targetUrl = payload.uri.trim();
    if (targetUrl.length === 0) {
      return;
    }
    const facts = this.shell.readFacts();
    const privacyMode: BrowserSessionPrivacyMode = payload.privacyMode;
    const dataScope: BrowserDataScope = payload.dataScope;
    const createOptions: BrowserCreateTabOptions = {
      profileId: payload.profileId,
      privacyMode: privacyMode,
      dataScope: dataScope
    };
    if (facts.showHomePage && facts.activeTabId.length === 0) {
      this.dependencies.tabHomeCoordinator.applyBoundary(payload.profileId, privacyMode, dataScope);
      this.dependencies.appUrlOpenCoordinator.open({
        url: targetUrl,
        title: targetUrl,
        intent: 'current_tab',
        source: 'external_url',
        helperMessage: payload.action.length > 0 ? '系统已交给Aira打开链接' : '正在打开外部链接',
        profileId: payload.profileId,
        privacyMode: privacyMode,
        dataScope: dataScope,
        createOptions: createOptions
      });
      return;
    }
    this.dependencies.appUrlOpenCoordinator.open({
      url: targetUrl,
      title: targetUrl,
      intent: 'new_tab',
      source: 'external_url',
      profileId: payload.profileId,
      privacyMode: privacyMode,
      dataScope: dataScope,
      createOptions: createOptions
    });
  }
}

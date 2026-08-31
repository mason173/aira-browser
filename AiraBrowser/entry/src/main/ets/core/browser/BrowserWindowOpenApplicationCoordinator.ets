import { BrowserCreateTabOptions, BrowserTabState, TabManager } from '../tabs/TabManager';
import { WebRuntimeBridge } from '../web/WebRuntimeBridge';
import { BrowserWindowOpenCoordinator } from './BrowserWindowOpenCoordinator';
import { BrowserNewWindowPlan } from './BrowserNewWindowCoordinator';
import { BrowserDeviceFormFactorInputService } from '../../services/browser/BrowserDeviceFormFactorInputService';

export interface BrowserWindowOpenApplicationHost {
  getWebRuntimeBridge: () => WebRuntimeBridge;
  findTabById: (tabId: string) => BrowserTabState | undefined;
  buildCreateOptions: (tabId: string) => BrowserCreateTabOptions;
  hasRecentAction: (now: number) => boolean;
  setHelperMessage: (message: string) => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  showManualDownloadConfirmSheet: (tabId: string, url: string) => void;
  getTabs: () => BrowserTabState[];
  setTabs: (tabs: BrowserTabState[]) => void;
  getTabSequence: () => number;
  setTabSequence: (tabSequence: number) => void;
  getHomeUrl: () => string;
  getActiveTabId: () => string;
  setActiveTabId: (tabId: string) => void;
  captureOpenerPreviewBeforeManagedTabOpen: (
    openerTabId: string,
    targetTabId: string,
    source: 'window_open'
  ) => Promise<void>;
  retainWindowOpenOpener: (openerTabId: string, targetTabId: string) => void;
  switchToTab: (tabId: string) => Promise<void>;
  closeTab: (tabId: string) => Promise<void>;
  closeActiveTabBackToLastTabOrHome: (reason: string) => Promise<void>;
  syncTabPreviewCacheWithTabs: () => void;
  requestCloseTabsOverview: () => void;
  syncActiveTabToView: () => void;
  recordRecentCreate: (now: number) => void;
  persistTabs: () => void;
  syncPrivateModeLockForCurrentBoundary: () => void;
}

export class BrowserWindowOpenApplicationCoordinator {
  private readonly tabManager: TabManager;
  private readonly host: BrowserWindowOpenApplicationHost;
  private readonly deviceFormFactorInputService: BrowserDeviceFormFactorInputService;
  private windowOpenCoordinator: BrowserWindowOpenCoordinator;

  constructor(
    tabManager: TabManager,
    host: BrowserWindowOpenApplicationHost,
    windowOpenCoordinator: BrowserWindowOpenCoordinator = new BrowserWindowOpenCoordinator(),
    deviceFormFactorInputService: BrowserDeviceFormFactorInputService = new BrowserDeviceFormFactorInputService()
  ) {
    this.tabManager = tabManager;
    this.host = host;
    this.windowOpenCoordinator = windowOpenCoordinator;
    this.deviceFormFactorInputService = deviceFormFactorInputService;
  }

  takeStoredEventForPageController(tabId: string): OnWindowNewEvent | undefined {
    return this.windowOpenCoordinator.takeStoredEvent(tabId);
  }

  hasStoredEventForPageController(tabId: string): boolean {
    return this.windowOpenCoordinator.hasStoredEvent(tabId);
  }

  rejectImmediateEvent(event: OnWindowNewEvent): boolean {
    return this.windowOpenCoordinator.rejectImmediateEvent(event);
  }

  async handle(tabId: string, event: OnWindowNewEvent): Promise<void> {
    const host = this.host;
    try {
      host.recordRuntimeEvent(
        'window_new_received',
        `target=${event.targetUrl} userTrigger=${event.isUserTrigger} isAlert=${event.isAlert}`,
        tabId
      );
      const now = Date.now();
      const deviceFormFactorInput = await this.deviceFormFactorInputService.resolveWindowOpenInput();
      const plan = this.windowOpenCoordinator.buildPlan({
        openerTab: host.findTabById(tabId),
        targetUrl: event.targetUrl,
        isAlert: event.isAlert,
        isUserTrigger: event.isUserTrigger,
        hasRecentAction: host.hasRecentAction(now),
        createOptions: host.buildCreateOptions(tabId),
        deviceFormFactorInput: deviceFormFactorInput
      }, host.getWebRuntimeBridge());
      host.recordRuntimeEvent(
        'window_open_policy',
        `type=${plan.type} target=${plan.targetUrl} userTrigger=${event.isUserTrigger} ` +
          `form=${plan.deviceFormFactor} ui=${plan.deviceUiMode} surface=${plan.windowOpenSurface} ` +
          plan.deviceFormFactorSummary,
        tabId
      );
      await this.applyPlan(tabId, event, plan, host);
    } catch (error) {
      host.recordRuntimeEvent('window_open_handler_failed', `新窗口处理异常 ${JSON.stringify(error)}`, tabId);
      this.windowOpenCoordinator.rejectImmediateEvent(event);
    }
  }

  handleChildExit(tabId: string): void {
    const host = this.host;
    const tab = host.findTabById(tabId);
    if (tab === undefined) {
      return;
    }
    host.recordRuntimeEvent('window_open_child_exit', `tab=${tabId}`, tabId);
    if (tabId === host.getActiveTabId() && tab.openedByNewWindow && tab.openerTabId.length > 0) {
      void host.closeActiveTabBackToLastTabOrHome('window_open_child_exit');
      return;
    }
    void host.closeTab(tabId);
  }

  handleChildActivate(tabId: string): void {
    const host = this.host;
    if (host.findTabById(tabId) === undefined) {
      return;
    }
    host.recordRuntimeEvent('window_open_child_activate', `tab=${tabId}`, tabId);
    void host.switchToTab(tabId);
  }

  handleActiveChildTerminalBack(reason: string): boolean {
    const host = this.host;
    const activeTabId = host.getActiveTabId();
    const tab = host.findTabById(activeTabId);
    if (tab === undefined || !tab.openedByNewWindow || tab.openerTabId.length <= 0) {
      return false;
    }
    host.recordRuntimeEvent(
      'window_open_child_terminal_back',
      `tab=${activeTabId} opener=${tab.openerTabId} reason=${reason}`,
      activeTabId
    );
    void host.closeActiveTabBackToLastTabOrHome(`window_open_child_terminal_back:${reason}`);
    return true;
  }

  private async applyPlan(
    openerTabId: string,
    event: OnWindowNewEvent,
    plan: BrowserNewWindowPlan,
    host: BrowserWindowOpenApplicationHost
  ): Promise<void> {
    host.recordRuntimeEvent(plan.runtimeEventType, plan.runtimeEventMessage, openerTabId);
    if (plan.type === 'ignore' || plan.type === 'blocked_popup') {
      host.setHelperMessage(plan.helperMessage);
      this.windowOpenCoordinator.rejectImmediateEvent(event);
      return;
    }
    if (plan.type === 'download') {
      host.setHelperMessage(plan.helperMessage);
      host.showManualDownloadConfirmSheet(openerTabId, plan.targetUrl);
      this.windowOpenCoordinator.rejectImmediateEvent(event);
      return;
    }
    host.setHelperMessage(plan.helperMessage);
    await this.openManagedTab(openerTabId, event, plan, host);
  }

  private async openManagedTab(
    openerTabId: string,
    event: OnWindowNewEvent,
    plan: BrowserNewWindowPlan,
    host: BrowserWindowOpenApplicationHost
  ): Promise<void> {
    try {
      const openPlan = this.windowOpenCoordinator.openManagedTab({
        tabManager: this.tabManager,
        tabs: host.getTabs(),
        tabSequence: host.getTabSequence(),
        openerTabId: openerTabId,
        event: event,
        plan: plan,
        homeUrl: host.getHomeUrl()
      });
      const transition = openPlan.transition;
      const targetTabId = openPlan.targetTabId;
      host.recordRuntimeEvent(
        'target_tab_created',
        `targetTab=${targetTabId} opener=${openerTabId} target=${plan.targetUrl}`,
        targetTabId
      );

      if (openPlan.eventDisposition === 'failed') {
        host.recordRuntimeEvent(
          'window_open_event_completion_failed',
          `targetTab=${openPlan.eventTargetTabId} target=${plan.targetUrl} plan=${plan.type}`,
          openerTabId
        );
        this.windowOpenCoordinator.rejectImmediateEvent(event);
        return;
      }
      host.recordRuntimeEvent(
        'window_new_event_stored',
        `targetTab=${targetTabId} target=${plan.targetUrl} plan=${plan.type}`,
        targetTabId
      );
      await host.captureOpenerPreviewBeforeManagedTabOpen(openerTabId, targetTabId, 'window_open');
      host.retainWindowOpenOpener(openerTabId, targetTabId);
      host.setTabs(transition.tabs);
      host.syncTabPreviewCacheWithTabs();
      host.setActiveTabId(targetTabId);
      host.setTabSequence(transition.tabSequence);
      host.requestCloseTabsOverview();
      const targetTab = host.findTabById(targetTabId);
      if (targetTab === undefined) {
        this.windowOpenCoordinator.rejectStoredEvent(targetTabId, 'target_tab_missing_after_transition');
        return;
      }

      host.syncActiveTabToView();
      host.recordRuntimeEvent(
        'normal_runtime_controller_created_or_resolved',
        `targetTab=${targetTabId} source=sync_active_tab_to_view`,
        targetTabId
      );
      host.recordRecentCreate(Date.now());
      host.persistTabs();
      host.setHelperMessage(transition.helperMessage);
      host.recordRuntimeEvent('window_open_managed_tab_created',
        `target=${plan.targetUrl} opener=${openerTabId}`, targetTabId);
      host.recordRuntimeEvent(
        'window_open_controller_handoff_pending',
        `targetTab=${targetTabId} reason=managed_${plan.type} target=${plan.targetUrl}`,
        openerTabId
      );
      host.syncPrivateModeLockForCurrentBoundary();
    } catch (error) {
      host.recordRuntimeEvent('window_open_managed_tab_failed',
        `新窗口 managed tab 创建失败 ${JSON.stringify(error)}`, openerTabId);
      this.windowOpenCoordinator.rejectImmediateEvent(event);
    }
  }
}

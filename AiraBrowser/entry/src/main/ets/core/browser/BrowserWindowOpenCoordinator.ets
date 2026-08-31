import { BrowserCreateTabOptions, BrowserTabState, BrowserTabManagerPort } from '../tabs/TabManager';
import { WebRuntimeBridge } from '../web/WebRuntimeBridge';
import {
  BrowserAttachedWindowTabCoordinator,
  BrowserAttachedWindowTabOpenPlan
} from './BrowserAttachedWindowTabCoordinator';
import {
  BrowserNewWindowCoordinator,
  BrowserNewWindowPlan
} from './BrowserNewWindowCoordinator';
import { BrowserWindowNewEventManager } from './BrowserWindowNewEventManager';
import { BrowserDeviceFormFactorInput } from './BrowserDeviceFormFactorCoordinator';

export interface BrowserWindowOpenRequest {
  openerTab: BrowserTabState | undefined;
  targetUrl: string;
  isAlert: boolean;
  isUserTrigger: boolean;
  hasRecentAction: boolean;
  createOptions: BrowserCreateTabOptions;
  deviceFormFactorInput?: BrowserDeviceFormFactorInput;
}

export interface BrowserWindowOpenStoredEventResult {
  stored: boolean;
  targetTabId: string;
}

export interface BrowserWindowOpenManagedTabRequest {
  tabManager: BrowserTabManagerPort;
  tabs: BrowserTabState[];
  tabSequence: number;
  openerTabId: string;
  event: OnWindowNewEvent;
  plan: BrowserNewWindowPlan;
  homeUrl: string;
}

export interface BrowserWindowOpenManagedTabPlan extends BrowserAttachedWindowTabOpenPlan {
  eventDisposition: BrowserWindowOpenManagedTabEventDisposition;
  eventTargetTabId: string;
}

export type BrowserWindowOpenManagedTabEventDisposition =
  'stored_for_controller_handoff' |
  'failed';

interface BrowserWindowOpenManagedTabEventCompletion {
  disposition: BrowserWindowOpenManagedTabEventDisposition;
  targetTabId: string;
}

export class BrowserWindowOpenCoordinator {
  private readonly newWindowCoordinator: BrowserNewWindowCoordinator;
  private readonly attachedWindowTabCoordinator: BrowserAttachedWindowTabCoordinator;
  private readonly eventManager: BrowserWindowNewEventManager;

  constructor(
    newWindowCoordinator: BrowserNewWindowCoordinator = new BrowserNewWindowCoordinator(),
    attachedWindowTabCoordinator: BrowserAttachedWindowTabCoordinator = new BrowserAttachedWindowTabCoordinator(),
    eventManager: BrowserWindowNewEventManager = new BrowserWindowNewEventManager()
  ) {
    this.newWindowCoordinator = newWindowCoordinator;
    this.attachedWindowTabCoordinator = attachedWindowTabCoordinator;
    this.eventManager = eventManager;
  }

  buildPlan(request: BrowserWindowOpenRequest, webRuntimeBridge: WebRuntimeBridge): BrowserNewWindowPlan {
    return this.newWindowCoordinator.buildPlan({
      openerTab: request.openerTab,
      targetUrl: request.targetUrl,
      isAlert: request.isAlert,
      isUserTrigger: request.isUserTrigger,
      hasRecentAction: request.hasRecentAction,
      createOptions: request.createOptions,
      deviceFormFactorInput: request.deviceFormFactorInput
    }, webRuntimeBridge);
  }

  openManagedTab(request: BrowserWindowOpenManagedTabRequest): BrowserWindowOpenManagedTabPlan {
    const openPlan = this.attachedWindowTabCoordinator.buildOpenPlan({
      tabManager: request.tabManager,
      tabs: request.tabs,
      tabSequence: request.tabSequence,
      openerTabId: request.openerTabId,
      targetUrl: request.plan.targetUrl,
      title: request.plan.title,
      homeUrl: request.homeUrl,
      createOptions: request.plan.createOptions
    });
    const eventCompletion = this.completeManagedTabWindowOpenEvent(openPlan.targetTabId, request);
    return {
      transition: openPlan.transition,
      targetTabId: openPlan.targetTabId,
      eventDisposition: eventCompletion.disposition,
      eventTargetTabId: eventCompletion.targetTabId
    };
  }

  private completeManagedTabWindowOpenEvent(
    targetTabId: string,
    request: BrowserWindowOpenManagedTabRequest
  ): BrowserWindowOpenManagedTabEventCompletion {
    const stored = this.storeEventForTab(targetTabId, request.event);
    return {
      disposition: stored.stored ? 'stored_for_controller_handoff' : 'failed',
      targetTabId: stored.targetTabId
    };
  }

  storeEventForTab(tabId: string, event: OnWindowNewEvent): BrowserWindowOpenStoredEventResult {
    const targetTabId = tabId.trim();
    return {
      stored: this.eventManager.addEvent(targetTabId, event),
      targetTabId: targetTabId
    };
  }

  takeStoredEvent(tabId: string): OnWindowNewEvent | undefined {
    return this.eventManager.takeEvent(tabId);
  }

  rejectStoredEvent(tabId: string, reason: string): boolean {
    return this.eventManager.rejectEvent(tabId, reason);
  }

  rejectImmediateEvent(event: OnWindowNewEvent): boolean {
    return this.eventManager.addEvent('__immediate_reject__', event) &&
      this.eventManager.rejectEvent('__immediate_reject__', 'immediate_reject');
  }

  hasStoredEvent(tabId: string): boolean {
    return this.eventManager.hasEvent(tabId);
  }
}

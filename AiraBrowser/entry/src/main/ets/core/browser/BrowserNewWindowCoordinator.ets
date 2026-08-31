import { BrowserCreateTabOptions, BrowserTabState } from '../tabs/TabManager';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { WebRuntimeBridge } from '../web/WebRuntimeBridge';
import {
  BrowserNewWindowPolicyDecision,
  BrowserNewWindowPolicyService
} from '../../services/web/BrowserNewWindowPolicyService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import {
  BrowserDeviceFormFactor,
  BrowserDeviceFormFactorCoordinator,
  BrowserDeviceFormFactorInput,
  BrowserDeviceUiMode,
  BrowserWindowOpenSurface
} from './BrowserDeviceFormFactorCoordinator';

export type BrowserNewWindowPlanType =
  'ignore' |
  'download' |
  'new_tab' |
  'attached_window_tab' |
  'blocked_popup';

export interface BrowserNewWindowRequest {
  openerTab: BrowserTabState | undefined;
  targetUrl: string;
  isAlert: boolean;
  isUserTrigger: boolean;
  hasRecentAction: boolean;
  createOptions: BrowserCreateTabOptions;
  deviceFormFactorInput?: BrowserDeviceFormFactorInput;
}

export interface BrowserNewWindowPlan {
  type: BrowserNewWindowPlanType;
  targetUrl: string;
  title: string;
  helperMessage: string;
  createOptions: BrowserCreateTabOptions;
  runtimeEventType: string;
  runtimeEventMessage: string;
  deviceFormFactor: BrowserDeviceFormFactor;
  deviceUiMode: BrowserDeviceUiMode;
  windowOpenSurface: BrowserWindowOpenSurface;
  deviceFormFactorSummary: string;
}

export class BrowserNewWindowCoordinator {
  private policyService: BrowserNewWindowPolicyService = new BrowserNewWindowPolicyService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private deviceFormFactorCoordinator: BrowserDeviceFormFactorCoordinator = new BrowserDeviceFormFactorCoordinator();

  buildPlan(request: BrowserNewWindowRequest, webRuntimeBridge: WebRuntimeBridge): BrowserNewWindowPlan {
    const deviceFormFactorProfile = this.deviceFormFactorCoordinator.resolveWindowOpenProfile(
      request.deviceFormFactorInput
    );
    const decision = this.policyService.buildDecision({
      targetUrl: request.targetUrl,
      isAlert: request.isAlert,
      isUserTriggered: request.isUserTrigger ||
        request.hasRecentAction ||
        this.isTrustedGoogleIdentityPopupContinuation(request),
      deviceFormFactorProfile: deviceFormFactorProfile
    }, webRuntimeBridge);
    return this.toPlan(request, decision);
  }

  private isTrustedGoogleIdentityPopupContinuation(request: BrowserNewWindowRequest): boolean {
    const openerTab = request.openerTab;
    if (openerTab === undefined || !openerTab.openedByNewWindow || openerTab.openerTabId.length === 0) {
      return false;
    }
    return this.policyService.isPopupAuthNavigationTarget(request.targetUrl);
  }

  private toPlan(
    request: BrowserNewWindowRequest,
    decision: BrowserNewWindowPolicyDecision
  ): BrowserNewWindowPlan {
    const openerTabId = request.openerTab?.id ?? '';
    const boundary = this.profileBoundaryService.inheritFromBoundaryInputs(
      this.buildTabBoundaryInput(request.openerTab),
      request.openerTab === undefined ? this.buildCreateTabBoundaryInput(request.createOptions) : {}
    );
    const createOptions: BrowserCreateTabOptions = {
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      launchContext: request.createOptions.launchContext,
      openerTabId: decision.openedByNewWindow ? openerTabId : '',
      openSource: decision.openedByNewWindow ? 'window_open' : '',
      openedByNewWindow: decision.openedByNewWindow,
      insertAfterTabId: decision.openedByNewWindow ? openerTabId : undefined
    };
    return {
      type: decision.type,
      targetUrl: decision.targetUrl,
      title: decision.title,
      helperMessage: decision.helperMessage,
      createOptions: createOptions,
      runtimeEventType: this.resolveRuntimeEventType(decision.type),
      runtimeEventMessage: decision.helperMessage,
      deviceFormFactor: decision.deviceFormFactorProfile.effectiveFormFactor,
      deviceUiMode: decision.deviceFormFactorProfile.uiMode,
      windowOpenSurface: decision.windowOpenSurface,
      deviceFormFactorSummary: decision.deviceFormFactorProfile.summaryLine
    };
  }

  private resolveRuntimeEventType(type: BrowserNewWindowPlanType): string {
    if (type === 'new_tab') {
      return 'window_open_new_tab';
    }
    if (type === 'attached_window_tab') {
      return 'window_open_attached_tab';
    }
    if (type === 'download') {
      return 'window_open_download';
    }
    if (type === 'blocked_popup') {
      return 'window_open_blocked_popup';
    }
    return 'window_open_ignored';
  }

  private buildCreateTabBoundaryInput(options: BrowserCreateTabOptions): BrowserDataBoundaryInput {
    return {
      profileId: options.profileId,
      privacyMode: options.privacyMode,
      dataScope: options.dataScope
    };
  }

  private buildTabBoundaryInput(tab: BrowserTabState | undefined): BrowserDataBoundaryInput | undefined {
    if (tab === undefined) {
      return undefined;
    }
    return {
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    };
  }
}

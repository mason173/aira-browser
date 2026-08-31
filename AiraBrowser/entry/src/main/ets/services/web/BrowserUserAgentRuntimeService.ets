import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserProfileId } from '../../common/models/BrowserModels';
import {
  BrowserUserAgentClientHintsMetadata,
  BrowserUserAgentProfile
} from './BrowserUserAgentService';
import { BrowserUserAgentClientHintsService } from './BrowserUserAgentClientHintsService';
import {
  BrowserBrowsingIdentityDecision,
  BrowserBrowsingIdentityDecisionEvidence,
  buildBrowserBrowsingIdentityExecutionFingerprint
} from './BrowserBrowsingIdentityDecisionService';
import {
  BrowserHostedRuntimeReleaseSink,
  BrowserRuntimeControllerResolver
} from './BrowserRuntimeLifecyclePort';

const BROWSING_IDENTITY_RUNTIME_LOG_DOMAIN: number = 0x0000;
const BROWSING_IDENTITY_RUNTIME_LOG_TAG: string = 'BrowsingIdentity';
const BROWSING_IDENTITY_RUNTIME_DIAGNOSTIC_PREFIX: string = '[BROWSING-IDENTITY-DIAG]';

export type BrowserUserAgentControllerIdentityKind = 'native' | 'custom';
export type BrowserUserAgentNavigationKind =
  'app_load' |
  'web_main_frame' |
  'history_back' |
  'history_forward' |
  'runtime_attach';
export type BrowserUserAgentApplicationStatus =
  'native_untouched' |
  'custom_applied' |
  'unchanged' |
  'identity_transition_required' |
  'failed';

export interface BrowserUserAgentNavigationPlan {
  tabId: string;
  targetUrl: string;
  navigationKind: BrowserUserAgentNavigationKind;
  transactionId: number;
  resolution: BrowserBrowsingIdentityDecision;
  applicationStatus: BrowserUserAgentApplicationStatus;
  preparedAt: number;
}

export interface BrowserUserAgentNavigationPreparation {
  allowed: boolean;
  applicationStatus: BrowserUserAgentApplicationStatus;
  transitionNoticeRequired: boolean;
}

export interface BrowserUserAgentNativeHistorySnapshot {
  currentIndex: number;
  size: number;
}

export interface BrowserUserAgentRuntimePlatformAdapter {
  resolveController(
    runtimeControllerResolver: BrowserRuntimeControllerResolver,
    tabId: string
  ): webview.WebviewController | undefined;
  applyCustomUserAgent(controller: webview.WebviewController, userAgent: string): void;
  readHistorySnapshot(
    controller: webview.WebviewController
  ): BrowserUserAgentNativeHistorySnapshot | undefined;
  applyClientHints(
    controller: webview.WebviewController,
    resolution: BrowserBrowsingIdentityDecision
  ): void;
  releaseController(controller: webview.WebviewController): void;
}

class ArkWebUserAgentRuntimePlatformAdapter implements BrowserUserAgentRuntimePlatformAdapter {
  private readonly clientHintsService: BrowserUserAgentClientHintsService;

  constructor(clientHintsService: BrowserUserAgentClientHintsService) {
    this.clientHintsService = clientHintsService;
  }

  resolveController(
    runtimeControllerResolver: BrowserRuntimeControllerResolver,
    tabId: string
  ): webview.WebviewController | undefined {
    return runtimeControllerResolver.resolveController(tabId);
  }

  applyCustomUserAgent(controller: webview.WebviewController, userAgent: string): void {
    controller.setCustomUserAgent(userAgent);
  }

  readHistorySnapshot(
    controller: webview.WebviewController
  ): BrowserUserAgentNativeHistorySnapshot | undefined {
    const entries = controller.getBackForwardEntries();
    return {
      currentIndex: entries.currentIndex,
      size: entries.size
    };
  }

  applyClientHints(
    controller: webview.WebviewController,
    resolution: BrowserBrowsingIdentityDecision
  ): void {
    this.clientHintsService.applyToController(controller, resolution);
  }

  releaseController(controller: webview.WebviewController): void {
    this.clientHintsService.releaseController(controller);
  }
}

export interface BrowserBrowsingIdentityRuntimeContext {
  tabId: string;
  profileId: BrowserProfileId;
  currentOrigin: string;
  observedOrigins: string[];
}

export type BrowserBrowsingIdentityDecisionResolver = (targetOrigin: string) => BrowserBrowsingIdentityDecision;

interface BrowserUserAgentControllerBinding {
  kind: BrowserUserAgentControllerIdentityKind;
  resolution: BrowserBrowsingIdentityDecision;
}

interface BrowserUserAgentCommittedEntryPlan {
  historyIndex: number;
  url: string;
  resolution: BrowserBrowsingIdentityDecision;
}

interface BrowserBrowsingIdentityRuntimeAffinity {
  profileId: BrowserProfileId;
  targetOrigin: string;
  identityId: string;
  observedOrigins: string[];
  resolution: BrowserBrowsingIdentityDecision;
  mayExtendRecoveryOrigin: boolean;
}

export class BrowserUserAgentRuntimeService implements BrowserHostedRuntimeReleaseSink {
  private readonly platformAdapter: BrowserUserAgentRuntimePlatformAdapter;
  private readonly controllerBindings: WeakMap<webview.WebviewController, BrowserUserAgentControllerBinding> =
    new WeakMap<webview.WebviewController, BrowserUserAgentControllerBinding>();
  private bindingByTabId: Record<string, BrowserUserAgentControllerBinding | undefined> = {};
  private activeNavigationPlanByTabId: Record<string, BrowserUserAgentNavigationPlan | undefined> = {};
  private committedEntryPlansByTabId:
    Record<string, Record<string, BrowserUserAgentCommittedEntryPlan | undefined> | undefined> = {};
  private affinityByTabId: Record<string, BrowserBrowsingIdentityRuntimeAffinity | undefined> = {};
  private transitionNoticeSignatureByTabId: Record<string, string | undefined> = {};
  private nextTransactionId: number = 0;

  constructor(
    clientHintsService: BrowserUserAgentClientHintsService,
    platformAdapter?: BrowserUserAgentRuntimePlatformAdapter
  ) {
    this.platformAdapter = platformAdapter ?? new ArkWebUserAgentRuntimePlatformAdapter(clientHintsService);
  }

  prepareNavigation(
    runtimeLifecyclePort: BrowserRuntimeControllerResolver,
    tabId: string,
    targetUrl: string,
    resolution: BrowserBrowsingIdentityDecision,
    navigationKind: BrowserUserAgentNavigationKind = 'app_load'
  ): BrowserUserAgentNavigationPreparation {
    const controller = this.platformAdapter.resolveController(runtimeLifecyclePort, tabId);
    return this.startNavigation(tabId, targetUrl, navigationKind, controller, resolution, true);
  }

  prepareWebMainFrameNavigation(
    runtimeLifecyclePort: BrowserRuntimeControllerResolver,
    tabId: string,
    targetUrl: string,
    resolution: BrowserBrowsingIdentityDecision,
    startsNewTransaction: boolean = false
  ): BrowserUserAgentNavigationPreparation {
    const activePlan = this.activeNavigationPlanByTabId[tabId];
    if (activePlan !== undefined && !startsNewTransaction) {
      // Load interception also observes redirect hops. The first plan remains
      // authoritative until the main-frame entry commits.
      this.logRuntimeDecision('redirect-reuse', activePlan, activePlan.applicationStatus);
      return {
        allowed: activePlan.applicationStatus !== 'failed',
        applicationStatus: activePlan.applicationStatus,
        transitionNoticeRequired: false
      };
    }
    return this.startNavigation(
      tabId,
      targetUrl,
      'web_main_frame',
      this.platformAdapter.resolveController(runtimeLifecyclePort, tabId),
      resolution,
      true
    );
  }

  prepareHistoryNavigation(
    runtimeLifecyclePort: BrowserRuntimeControllerResolver,
    tabId: string,
    targetUrl: string,
    targetHistoryIndex: number,
    direction: 'back' | 'forward',
    fallbackResolution: BrowserBrowsingIdentityDecision
  ): BrowserUserAgentNavigationPreparation {
    const storedEntry = this.committedEntryPlansByTabId[tabId]?.[`${targetHistoryIndex}`];
    const resolution = storedEntry !== undefined && storedEntry.url === targetUrl
      ? storedEntry.resolution
      : fallbackResolution;
    return this.startNavigation(
      tabId,
      targetUrl,
      direction === 'back' ? 'history_back' : 'history_forward',
      this.platformAdapter.resolveController(runtimeLifecyclePort, tabId),
      resolution,
      false
    );
  }

  applyToControllerForTab(
    tabId: string,
    controller: webview.WebviewController | undefined,
    resolution: BrowserBrowsingIdentityDecision
  ): boolean {
    if (controller === undefined) {
      return false;
    }
    const activePlan = this.activeNavigationPlanByTabId[tabId];
    const binding = this.controllerBindings.get(controller);
    if (activePlan !== undefined && binding !== undefined) {
      // The immutable navigation plan already prepared this attached runtime.
      // A later load-sync callback must not re-resolve mutable settings and
      // overwrite it with the previous/current URL's identity.
      return activePlan.applicationStatus !== 'failed';
    }
    if (activePlan !== undefined) {
      return this.startNavigation(
        tabId,
        activePlan.targetUrl,
        activePlan.navigationKind,
        controller,
        activePlan.resolution,
        true
      ).allowed;
    }
    const applicationStatus = this.applyToController(tabId, controller, resolution, binding === undefined);
    return applicationStatus !== 'failed';
  }

  isControllerIdentitySynchronized(
    tabId: string,
    controller: webview.WebviewController | undefined
  ): boolean {
    if (controller === undefined || this.activeNavigationPlanByTabId[tabId] !== undefined) {
      return false;
    }
    return this.controllerBindings.get(controller) !== undefined;
  }

  resolveForContext(
    context: BrowserBrowsingIdentityRuntimeContext,
    directResolution: BrowserBrowsingIdentityDecision,
    allowRedirectAffinityExtension: boolean,
    resolveAffinityTarget: BrowserBrowsingIdentityDecisionResolver
  ): BrowserBrowsingIdentityDecision {
    let resolution = directResolution;
    if (directResolution.source === 'system_default') {
      const affinity = this.affinityByTabId[context.tabId];
      if (affinity === undefined || affinity.profileId !== context.profileId ||
        !this.isAffinityStillSaved(affinity, resolveAffinityTarget)) {
        this.affinityByTabId[context.tabId] = undefined;
      } else if (affinity.observedOrigins.includes(context.currentOrigin)) {
        resolution = affinity.resolution;
      } else if (allowRedirectAffinityExtension && affinity.mayExtendRecoveryOrigin &&
        context.currentOrigin.length > 0) {
        affinity.mayExtendRecoveryOrigin = false;
        affinity.observedOrigins = affinity.observedOrigins.concat([context.currentOrigin]);
        resolution = affinity.resolution;
      }
    }
    if (allowRedirectAffinityExtension && resolution.source === 'site_setting') {
      this.rememberAffinity(context, resolution);
    }
    return resolution;
  }

  clearAffinityForExplicitNavigation(tabId: string, targetOrigin: string): void {
    const affinity = this.affinityByTabId[tabId];
    if (affinity === undefined) {
      return;
    }
    const normalizedTargetOrigin = targetOrigin.trim();
    if (normalizedTargetOrigin.length <= 0 || affinity.observedOrigins.includes(normalizedTargetOrigin)) {
      return;
    }
    this.affinityByTabId[tabId] = undefined;
  }

  commitNavigation(
    tabId: string,
    controller: webview.WebviewController | undefined,
    committedUrl: string
  ): void {
    if (controller === undefined) {
      this.logCommitSkipped(tabId, 'controller_missing');
      this.activeNavigationPlanByTabId[tabId] = undefined;
      return;
    }
    const historyIndex = this.readHistoryIndex(controller);
    if (historyIndex < 0) {
      this.logCommitSkipped(tabId, 'history_unavailable');
      this.activeNavigationPlanByTabId[tabId] = undefined;
      return;
    }
    const activePlan = this.activeNavigationPlanByTabId[tabId];
    const binding = this.controllerBindings.get(controller);
    // The native history ledger records the identity that actually owns the
    // Controller. A transition-required request is intent, not applied state.
    const resolution = binding?.resolution ?? activePlan?.resolution;
    if (resolution !== undefined) {
      const plans = this.committedEntryPlansByTabId[tabId] ?? {};
      plans[`${historyIndex}`] = {
        historyIndex: historyIndex,
        url: committedUrl.trim(),
        resolution: this.cloneResolution(resolution)
      };
      this.committedEntryPlansByTabId[tabId] = this.retainLiveHistoryEntries(controller, plans);
      hilog.info(
        BROWSING_IDENTITY_RUNTIME_LOG_DOMAIN,
        BROWSING_IDENTITY_RUNTIME_LOG_TAG,
        `${BROWSING_IDENTITY_RUNTIME_DIAGNOSTIC_PREFIX} commit tab=%{public}s tx=%{public}d ` +
          'history=%{public}d identity=%{public}s presentation=%{public}s binding=%{public}s',
        tabId,
        activePlan?.transactionId ?? 0,
        historyIndex,
        resolution.profile.identityId,
        resolution.profile.presentationMode,
        binding?.kind ?? 'plan_only'
      );
    } else {
      this.logCommitSkipped(tabId, 'resolution_missing');
    }
    this.activeNavigationPlanByTabId[tabId] = undefined;
  }

  releaseTab(tabId: string, controller: webview.WebviewController | undefined): void {
    this.activeNavigationPlanByTabId[tabId] = undefined;
    this.committedEntryPlansByTabId[tabId] = undefined;
    this.affinityByTabId[tabId] = undefined;
    this.bindingByTabId[tabId] = undefined;
    this.transitionNoticeSignatureByTabId[tabId] = undefined;
    if (controller !== undefined) {
      this.releaseController(controller);
    }
  }

  releaseControllerBinding(tabId: string, controller: webview.WebviewController | undefined): void {
    this.activeNavigationPlanByTabId[tabId] = undefined;
    this.bindingByTabId[tabId] = undefined;
    this.transitionNoticeSignatureByTabId[tabId] = undefined;
    if (controller !== undefined) {
      this.releaseController(controller);
    }
  }

  releaseControllerBindings(tabIds: string[]): void {
    tabIds.forEach((tabId: string): void => {
      this.releaseControllerBinding(tabId, undefined);
    });
  }

  cancelNavigation(tabId: string): void {
    this.activeNavigationPlanByTabId[tabId] = undefined;
  }

  requiresControllerTransition(tabId: string, resolution: BrowserBrowsingIdentityDecision): boolean {
    const binding = this.bindingByTabId[tabId];
    return binding?.kind === 'custom' && resolution.profile.uaStringMode === 'system_untouched';
  }

  hasEffectiveIdentityChange(tabId: string, resolution: BrowserBrowsingIdentityDecision): boolean {
    const current = this.bindingByTabId[tabId]?.resolution;
    if (current === undefined) {
      return true;
    }
    return buildBrowserBrowsingIdentityExecutionFingerprint(current) !== resolution.executionFingerprint;
  }

  private startNavigation(
    tabId: string,
    targetUrl: string,
    navigationKind: BrowserUserAgentNavigationKind,
    controller: webview.WebviewController | undefined,
    resolution: BrowserBrowsingIdentityDecision,
    allowControllerMutation: boolean
  ): BrowserUserAgentNavigationPreparation {
    if (controller === undefined) {
      return {
        allowed: false,
        applicationStatus: 'failed',
        transitionNoticeRequired: false
      };
    }
    const applicationStatus = this.applyToController(tabId, controller, resolution, allowControllerMutation);
    if (applicationStatus === 'failed') {
      this.activeNavigationPlanByTabId[tabId] = undefined;
      return {
        allowed: false,
        applicationStatus: applicationStatus,
        transitionNoticeRequired: false
      };
    }
    this.nextTransactionId += 1;
    this.activeNavigationPlanByTabId[tabId] = {
      tabId: tabId,
      targetUrl: targetUrl.trim(),
      navigationKind: navigationKind,
      transactionId: this.nextTransactionId,
      resolution: this.cloneResolution(resolution),
      applicationStatus: applicationStatus,
      preparedAt: Date.now()
    };
    const activePlan = this.activeNavigationPlanByTabId[tabId];
    if (activePlan !== undefined) {
      this.logRuntimeDecision('prepare', activePlan, applicationStatus);
    }
    const transitionNoticeRequired = this.updateTransitionNoticeState(
      tabId,
      applicationStatus,
      resolution
    );
    // A transition-required plan deliberately preserves native history under
    // the current Controller identity. Only a platform mutation failure blocks
    // a navigation from being issued.
    return {
      allowed: true,
      applicationStatus: applicationStatus,
      transitionNoticeRequired: transitionNoticeRequired
    };
  }

  private applyToController(
    tabId: string,
    controller: webview.WebviewController,
    resolution: BrowserBrowsingIdentityDecision,
    allowControllerMutation: boolean
  ): BrowserUserAgentApplicationStatus {
    const targetUserAgent = resolution.profile.uaString.trim();
    const binding = this.controllerBindings.get(controller);
    if (binding !== undefined) {
      this.bindingByTabId[tabId] = {
        kind: binding.kind,
        resolution: this.cloneResolution(binding.resolution)
      };
    }
    const requestsNativeIdentity = resolution.profile.uaStringMode === 'system_untouched';
    if (requestsNativeIdentity) {
      if (binding !== undefined && binding.kind === 'custom') {
        // ArkWeb exposes no clear-to-native operation. Writing the default text
        // would remain a custom override, so keep the current runtime honest.
        return 'identity_transition_required';
      }
      this.controllerBindings.set(controller, {
        kind: 'native',
        resolution: this.cloneResolution(resolution)
      });
      this.bindingByTabId[tabId] = {
        kind: 'native',
        resolution: this.cloneResolution(resolution)
      };
      this.platformAdapter.applyClientHints(controller, resolution);
      return binding === undefined ? 'native_untouched' : 'unchanged';
    }
    if (targetUserAgent.length <= 0) {
      return 'failed';
    }
    if (binding !== undefined && binding.kind === 'custom' &&
      binding.resolution.profile.uaString === targetUserAgent) {
      this.controllerBindings.set(controller, {
        kind: 'custom',
        resolution: this.cloneResolution(resolution)
      });
      this.bindingByTabId[tabId] = {
        kind: 'custom',
        resolution: this.cloneResolution(resolution)
      };
      this.platformAdapter.applyClientHints(controller, resolution);
      return 'unchanged';
    }
    if (!allowControllerMutation) {
      return 'identity_transition_required';
    }
    try {
      this.platformAdapter.applyCustomUserAgent(controller, targetUserAgent);
      this.controllerBindings.set(controller, {
        kind: 'custom',
        resolution: this.cloneResolution(resolution)
      });
      this.bindingByTabId[tabId] = {
        kind: 'custom',
        resolution: this.cloneResolution(resolution)
      };
      this.platformAdapter.applyClientHints(controller, resolution);
      return 'custom_applied';
    } catch (_error) {
      return 'failed';
    }
  }

  private releaseController(controller: webview.WebviewController): void {
    this.controllerBindings.delete(controller);
    this.platformAdapter.releaseController(controller);
  }

  private updateTransitionNoticeState(
    tabId: string,
    applicationStatus: BrowserUserAgentApplicationStatus,
    resolution: BrowserBrowsingIdentityDecision
  ): boolean {
    if (applicationStatus !== 'identity_transition_required') {
      this.transitionNoticeSignatureByTabId[tabId] = undefined;
      return false;
    }
    const currentIdentityId = this.bindingByTabId[tabId]?.resolution.profile.identityId ?? 'custom';
    const signature = `${currentIdentityId}->${resolution.profile.identityId}`;
    const noticeRequired = this.transitionNoticeSignatureByTabId[tabId] !== signature;
    this.transitionNoticeSignatureByTabId[tabId] = signature;
    return noticeRequired;
  }

  private logRuntimeDecision(
    event: string,
    plan: BrowserUserAgentNavigationPlan,
    applicationStatus: BrowserUserAgentApplicationStatus
  ): void {
    hilog.info(
      BROWSING_IDENTITY_RUNTIME_LOG_DOMAIN,
      BROWSING_IDENTITY_RUNTIME_LOG_TAG,
      `${BROWSING_IDENTITY_RUNTIME_DIAGNOSTIC_PREFIX} %{public}s tab=%{public}s tx=%{public}d kind=%{public}s ` +
        'winner=%{public}s identity=%{public}s presentation=%{public}s status=%{public}s',
      event,
      plan.tabId,
      plan.transactionId,
      plan.navigationKind,
      plan.resolution.winningSource,
      plan.resolution.profile.identityId,
      plan.resolution.profile.presentationMode,
      applicationStatus
    );
  }

  private logCommitSkipped(tabId: string, reason: string): void {
    hilog.warn(
      BROWSING_IDENTITY_RUNTIME_LOG_DOMAIN,
      BROWSING_IDENTITY_RUNTIME_LOG_TAG,
      `${BROWSING_IDENTITY_RUNTIME_DIAGNOSTIC_PREFIX} commit-skipped tab=%{public}s reason=%{public}s`,
      tabId,
      reason
    );
  }

  private rememberAffinity(
    context: BrowserBrowsingIdentityRuntimeContext,
    resolution: BrowserBrowsingIdentityDecision
  ): void {
    const targetOrigin = resolution.targetOrigin?.trim() ?? '';
    const identityId = resolution.identityId?.trim() ?? '';
    if (targetOrigin.length <= 0 || identityId.length <= 0) {
      return;
    }
    const previous = this.affinityByTabId[context.tabId];
    const observedOrigins = this.uniqueOrigins(
      (previous?.identityId === identityId ? previous.observedOrigins : [])
        .concat(context.observedOrigins)
        .concat([targetOrigin])
    );
    this.affinityByTabId[context.tabId] = {
      profileId: context.profileId,
      targetOrigin: targetOrigin,
      identityId: identityId,
      observedOrigins: observedOrigins,
      resolution: this.cloneResolution(resolution),
      mayExtendRecoveryOrigin: previous?.identityId === identityId ?
        previous.mayExtendRecoveryOrigin : false
    };
  }

  private isAffinityStillSaved(
    affinity: BrowserBrowsingIdentityRuntimeAffinity,
    resolveAffinityTarget: BrowserBrowsingIdentityDecisionResolver
  ): boolean {
    const savedResolution = resolveAffinityTarget(affinity.targetOrigin);
    return savedResolution.source === 'site_setting' &&
      savedResolution.identityId === affinity.identityId &&
      savedResolution.executionFingerprint === affinity.resolution.executionFingerprint;
  }

  private uniqueOrigins(origins: string[]): string[] {
    const unique: string[] = [];
    origins.forEach((origin: string): void => {
      const normalized = origin.trim();
      if (normalized.length > 0 && !unique.includes(normalized)) {
        unique.push(normalized);
      }
    });
    return unique;
  }

  private readHistoryIndex(controller: webview.WebviewController): number {
    try {
      return this.platformAdapter.readHistorySnapshot(controller)?.currentIndex ?? -1;
    } catch (_error) {
      return -1;
    }
  }

  private retainLiveHistoryEntries(
    controller: webview.WebviewController,
    plans: Record<string, BrowserUserAgentCommittedEntryPlan | undefined>
  ): Record<string, BrowserUserAgentCommittedEntryPlan | undefined> {
    try {
      const snapshot = this.platformAdapter.readHistorySnapshot(controller);
      if (snapshot === undefined) {
        return plans;
      }
      const size = snapshot.size;
      const retained: Record<string, BrowserUserAgentCommittedEntryPlan | undefined> = {};
      Object.keys(plans).forEach((key: string): void => {
        const index = Number(key);
        if (Number.isInteger(index) && index >= 0 && index < size) {
          retained[key] = plans[key];
        }
      });
      return retained;
    } catch (_error) {
      return plans;
    }
  }

  private cloneResolution(resolution: BrowserBrowsingIdentityDecision): BrowserBrowsingIdentityDecision {
    return {
      userAgent: resolution.userAgent,
      mode: resolution.mode,
      source: resolution.source,
      reason: resolution.reason,
      matchedHost: resolution.matchedHost,
      identityId: resolution.identityId,
      targetOrigin: resolution.targetOrigin,
      profile: this.cloneProfile(resolution.profile),
      winningSource: resolution.winningSource,
      policySnapshotKey: resolution.policySnapshotKey,
      explanation: this.cloneExplanation(resolution.explanation),
      executionFingerprint: resolution.executionFingerprint
    };
  }

  private cloneExplanation(
    explanation: BrowserBrowsingIdentityDecisionEvidence[]
  ): BrowserBrowsingIdentityDecisionEvidence[] {
    return explanation.map((evidence: BrowserBrowsingIdentityDecisionEvidence): BrowserBrowsingIdentityDecisionEvidence => ({
      source: evidence.source,
      identityId: evidence.identityId,
      status: evidence.status,
      reason: evidence.reason
    }));
  }

  private cloneProfile(profile: BrowserUserAgentProfile): BrowserUserAgentProfile {
    return {
      identityId: profile.identityId,
      uaStringMode: profile.uaStringMode,
      uaString: profile.uaString,
      clientHintsMode: profile.clientHintsMode,
      metadata: this.cloneMetadata(profile.metadata),
      presentationMode: profile.presentationMode,
      scopeCapability: profile.scopeCapability,
      compatibilityNotice: profile.compatibilityNotice
    };
  }

  private cloneMetadata(
    metadata: BrowserUserAgentClientHintsMetadata | undefined
  ): BrowserUserAgentClientHintsMetadata | undefined {
    if (metadata === undefined) {
      return undefined;
    }
    return {
      brand: metadata.brand,
      majorVersion: metadata.majorVersion,
      fullVersion: metadata.fullVersion,
      platform: metadata.platform,
      platformVersion: metadata.platformVersion,
      mobile: metadata.mobile,
      architecture: metadata.architecture,
      bitness: metadata.bitness,
      model: metadata.model,
      wow64: metadata.wow64
    };
  }
}

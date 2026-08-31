import {
  MediaDetectionPolicy,
  MediaDetectionPolicyCatalog,
  sharedMediaDetectionPolicyCatalog
} from './MediaDetectionPolicyCatalog';

export interface MediaProbePolicyContext {
  fullAppServiceMode: boolean;
  webVideoTakeoverEnabled: boolean;
  mediaResourcesPanelOpen?: boolean;
  pageUrl?: string;
  pageTitle?: string;
  privateMode?: boolean;
  tabActive?: boolean;
  webPageVisible?: boolean;
  userIntent?: MediaProbeUserIntent;
  visibleVideoMediaCount?: number;
  videoMediaCount?: number;
}

export type MediaProbeUserIntent =
  'none' |
  'page_end' |
  'scheduled_page_end' |
  'resource_panel' |
  'userscript' |
  'takeover_launch';

export interface MediaProbeDecision {
  enabled: boolean;
  reason: string;
}

export interface MediaProbeBudget {
  maxDeepProbeRunsPerNavigation: number;
  maxInFlightDeepProbes: number;
}

export interface MediaDeepProbePlan {
  enabled: boolean;
  delayMsList: number[];
  budget: MediaProbeBudget;
}

export class MediaProbePolicyService {
  private readonly detectionPolicyCatalog: MediaDetectionPolicyCatalog;

  constructor(detectionPolicyCatalog: MediaDetectionPolicyCatalog = sharedMediaDetectionPolicyCatalog) {
    this.detectionPolicyCatalog = detectionPolicyCatalog;
  }

  decideVideoRequestObservation(context: MediaProbePolicyContext): MediaProbeDecision {
    return this.requireFullVideoTakeover(context, 'video_request_observation');
  }

  shouldObserveVideoRequest(context: MediaProbePolicyContext): boolean {
    return this.decideVideoRequestObservation(context).enabled;
  }

  decideVideoPageEndProbes(context: MediaProbePolicyContext): MediaProbeDecision {
    return this.requireFullVideoTakeover(context, 'page_end_video_probe');
  }

  shouldRunVideoPageEndProbes(context: MediaProbePolicyContext): boolean {
    return this.decideVideoPageEndProbes(context).enabled;
  }

  buildVideoPageEndDeepProbePlan(context: MediaProbePolicyContext): MediaDeepProbePlan {
    const policy: MediaDetectionPolicy = this.detectionPolicyCatalog.currentPolicy();
    const baseDecision = this.requireFullVideoTakeover(context, 'page_end_deep_probe');
    if (!baseDecision.enabled) {
      return this.disabledDeepProbePlan(policy);
    }
    if (context.tabActive === false) {
      return this.disabledDeepProbePlan(policy);
    }
    if (context.webPageVisible === false) {
      return this.disabledDeepProbePlan(policy);
    }
    return this.enabledDeepProbePlan(policy);
  }

  shouldRunSpaRouteReprobe(context: MediaProbePolicyContext): boolean {
    return this.requireFullVideoTakeover(context, 'spa_route_reprobe').enabled &&
      this.detectionPolicyCatalog.currentPolicy().spaRouteReprobeEnabled;
  }

  decideGenericResourceRequestObservation(context: MediaProbePolicyContext): MediaProbeDecision {
    const fullDecision = this.requireFullMode(context, 'resource_request_observation');
    if (!fullDecision.enabled) {
      return fullDecision;
    }
    if (context.mediaResourcesPanelOpen === true) {
      return this.enabledDecision('resource_panel_open');
    }
    if (context.webVideoTakeoverEnabled) {
      return this.enabledDecision('takeover_resource_observation');
    }
    return this.disabledDecision('disabled_resource_panel_closed');
  }

  shouldObserveGenericResourceRequest(context: MediaProbePolicyContext): boolean {
    return this.decideGenericResourceRequestObservation(context).enabled;
  }

  decideManualMediaVideoProbe(context: MediaProbePolicyContext): MediaProbeDecision {
    const privateDecision = this.requireThirdPartyUserScriptAllowed(context);
    if (!privateDecision.enabled) {
      return privateDecision;
    }
    return this.requireFullVideoTakeover(context, 'manual_video_probe');
  }

  shouldRunManualMediaVideoProbe(context: MediaProbePolicyContext): boolean {
    return this.decideManualMediaVideoProbe(context).enabled;
  }

  decideManualMediaResourceProbe(context: MediaProbePolicyContext): MediaProbeDecision {
    const privateDecision = this.requireThirdPartyUserScriptAllowed(context);
    if (!privateDecision.enabled) {
      return privateDecision;
    }
    const fullDecision = this.requireFullMode(context, 'manual_resource_probe');
    if (!fullDecision.enabled) {
      return fullDecision;
    }
    if (context.mediaResourcesPanelOpen !== true) {
      return this.disabledDecision('disabled_resource_panel_closed');
    }
    return this.enabledDecision('userscript_manual_request');
  }

  shouldRunManualMediaResourceProbe(context: MediaProbePolicyContext): boolean {
    return this.decideManualMediaResourceProbe(context).enabled;
  }

  decideExplicitResourceScan(context: MediaProbePolicyContext): MediaProbeDecision {
    return this.requireFullMode(context, 'resource_panel_manual_scan');
  }

  shouldRunExplicitResourceScan(context: MediaProbePolicyContext): boolean {
    return this.decideExplicitResourceScan(context).enabled;
  }

  private requireFullMode(context: MediaProbePolicyContext, enabledReason: string): MediaProbeDecision {
    if (!context.fullAppServiceMode) {
      return this.disabledDecision('disabled_basic_mode');
    }
    return this.enabledDecision(enabledReason);
  }

  private requireFullVideoTakeover(context: MediaProbePolicyContext, enabledReason: string): MediaProbeDecision {
    const fullDecision = this.requireFullMode(context, enabledReason);
    if (!fullDecision.enabled) {
      return fullDecision;
    }
    if (!context.webVideoTakeoverEnabled) {
      return this.disabledDecision('disabled_takeover_off');
    }
    return this.enabledDecision(enabledReason);
  }

  private requireThirdPartyUserScriptAllowed(context: MediaProbePolicyContext): MediaProbeDecision {
    if (context.userIntent === 'userscript' && context.privateMode === true) {
      return this.disabledDecision('disabled_private_tab_userscript');
    }
    return this.enabledDecision('userscript_allowed');
  }

  private enabledDecision(reason: string): MediaProbeDecision {
    return {
      enabled: true,
      reason: reason
    };
  }

  private disabledDecision(reason: string): MediaProbeDecision {
    return {
      enabled: false,
      reason: reason
    };
  }

  private enabledDeepProbePlan(policy: MediaDetectionPolicy): MediaDeepProbePlan {
    return {
      enabled: true,
      delayMsList: policy.deepProbeDelaysMs.slice(),
      budget: this.buildDeepProbeBudget(policy)
    };
  }

  private disabledDeepProbePlan(policy: MediaDetectionPolicy): MediaDeepProbePlan {
    return {
      enabled: false,
      delayMsList: [],
      budget: this.buildDeepProbeBudget(policy)
    };
  }

  private buildDeepProbeBudget(policy: MediaDetectionPolicy): MediaProbeBudget {
    return {
      maxDeepProbeRunsPerNavigation: policy.maxDeepProbeRunsPerNavigation,
      maxInFlightDeepProbes: policy.maxInFlightDeepProbes
    };
  }
}

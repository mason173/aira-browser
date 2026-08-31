export type NovelDetectionStrategyId = 'dom_evidence_v1';

export interface NovelDetectionPolicy {
  retryDelaysMs: number[];
  maxProbeRunsPerNavigation: number;
  spaRouteReprobeEnabled: boolean;
  strategyIds: NovelDetectionStrategyId[];
}

export const DEFAULT_NOVEL_DETECTION_POLICY: NovelDetectionPolicy = {
  retryDelaysMs: [600, 1800, 3600, 8000],
  maxProbeRunsPerNavigation: 5,
  spaRouteReprobeEnabled: true,
  strategyIds: ['dom_evidence_v1']
};

/** Package-owned bounds for generic Novel page detection. */
export class NovelDetectionPolicyCatalog {
  currentPolicy(): NovelDetectionPolicy {
    return {
      retryDelaysMs: DEFAULT_NOVEL_DETECTION_POLICY.retryDelaysMs.slice(),
      maxProbeRunsPerNavigation: DEFAULT_NOVEL_DETECTION_POLICY.maxProbeRunsPerNavigation,
      spaRouteReprobeEnabled: DEFAULT_NOVEL_DETECTION_POLICY.spaRouteReprobeEnabled,
      strategyIds: DEFAULT_NOVEL_DETECTION_POLICY.strategyIds.slice()
    };
  }
}

export const sharedNovelDetectionPolicyCatalog: NovelDetectionPolicyCatalog =
  new NovelDetectionPolicyCatalog();

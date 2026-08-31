import { AdBlockResourceType } from '../../common/models/BrowserModels';

export interface AdBlockRequestEvaluationInput {
  url: string;
  pageUrl: string;
  method: string;
  isMainFrame: boolean;
  enabled: boolean;
  includeResponseEvaluation: boolean;
  resourceType?: AdBlockResourceType;
}

export interface AdBlockRequestDecision {
  shouldBlock: boolean;
  redirectDataUrl: string;
  rewrittenUrl: string;
}

export interface AdBlockResponseDecision {
  cspDirectives: string[];
}

export interface AdBlockRequestEvaluation {
  network: AdBlockRequestDecision;
  response: AdBlockResponseDecision;
}

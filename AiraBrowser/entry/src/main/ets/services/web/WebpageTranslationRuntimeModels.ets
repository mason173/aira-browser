export interface WebpageTranslationTextItem {
  id: string;
  text: string;
  cachedTranslatedText?: string;
  charLength?: number;
  order?: number;
  score?: number;
  nearViewport?: boolean;
  top?: number;
}

export interface WebpageTranslationExtractionResult {
  url: string;
  lang: string;
  title: string;
  items: WebpageTranslationTextItem[];
  diagnostics?: WebpageTranslationExtractionDiagnostics;
}

export interface WebpageTranslationExtractionDiagnostics {
  mode?: string;
  totalTextNodes?: number;
  acceptedTextNodes?: number;
  rejectedByElement?: number;
  rejectedByText?: number;
  rejectedByViewport?: number;
  rejectedByScore?: number;
  skippedTranslated?: number;
  cachedHitCount?: number;
  candidateCount?: number;
  strongCandidateCount?: number;
  scoreFloor?: number;
  selectedCount?: number;
  selectedChars?: number;
  limitNodes?: number;
  limitChars?: number;
  maxItemChars?: number;
  pendingCount?: number;
  viewportHeight?: number;
  scrollHeight?: number;
  pageScrollable?: boolean;
}

export interface WebpageTranslationApplyItem {
  id: string;
  translatedText: string;
}

export interface WebpageTranslationApplyResult {
  appliedCount: number;
  appliedIds: string[];
  requestedCount: number;
  missingNodeCount: number;
  invalidTextCount: number;
  changedTextCount: number;
  unchangedTextCount: number;
}

export interface WebpageTranslationRuntimeMutationResult {
  requestedCount: number;
  markedCount: number;
  clearedCount: number;
  failedCount: number;
  missingNodeCount: number;
  skippedCount: number;
  changedTextCount: number;
}

export type AdBlockCosmeticExecutionAction =
  'hide' |
  'remove' |
  'style' |
  'remove-attr' |
  'remove-class';

export interface AdBlockCosmeticExecutionRule {
  selector: string;
  action: AdBlockCosmeticExecutionAction;
  value: string;
  procedural: boolean;
}

export interface AdBlockCosmeticExecutionPlan {
  rules: AdBlockCosmeticExecutionRule[];
  cssSelectors: string[];
  truncatedCssSelectorCount: number;
  skipped: boolean;
  reason: string;
}

export interface AdBlockCosmeticSelectorCandidates {
  classes: string[];
  ids: string[];
}

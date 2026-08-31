import { AdBlockNativeCosmeticResources } from './AdBlockNativeAuthorityEngineService';
import {
  AdBlockCosmeticExecutionAction,
  AdBlockCosmeticExecutionPlan,
  AdBlockCosmeticExecutionRule
} from './AdBlockCosmeticExecutionModels';

interface AdBlockRustCosmeticOperatorPayload {
  type: string;
  arg?: string;
}

interface AdBlockRustCosmeticActionPayload {
  type: string;
  arg?: string;
}

interface AdBlockRustProceduralFilterPayload {
  selector: AdBlockRustCosmeticOperatorPayload[];
  action?: AdBlockRustCosmeticActionPayload;
}

interface AdBlockRustCosmeticResolvedAction {
  action: AdBlockCosmeticExecutionAction;
  value: string;
}

interface AdBlockRustNormalizedSelectors {
  selectors: string[];
  truncatedCount: number;
}

const MAX_COSMETIC_RUNTIME_RULES_PER_PAGE: number = 300;
const MAX_COSMETIC_CSS_SELECTORS_PER_PAGE: number = 4096;
const MAX_COSMETIC_CSS_TEXT_LENGTH: number = 384 * 1024;
const COSMETIC_HIDE_RULE_OVERHEAD_LENGTH: number = 54;

export class AdBlockRustCosmeticResourceAdapterService {
  buildExecutionPlan(resources: AdBlockNativeCosmeticResources): AdBlockCosmeticExecutionPlan {
    const cssSelectors = this.normalizeCssSelectors(this.parseStringArray(resources.hideSelectorsJson));
    const rules: AdBlockCosmeticExecutionRule[] = [];
    this.parseStringArray(resources.proceduralActionsJson).some((encodedFilter: string): boolean => {
      if (rules.length >= MAX_COSMETIC_RUNTIME_RULES_PER_PAGE) {
        return true;
      }
      const rule = this.parseExecutionRule(encodedFilter);
      if (rule !== undefined) {
        rules.push(rule);
      }
      return false;
    });
    return {
      rules: rules,
      cssSelectors: cssSelectors.selectors,
      truncatedCssSelectorCount: cssSelectors.truncatedCount,
      skipped: rules.length <= 0 && cssSelectors.selectors.length <= 0,
      reason: rules.length <= 0 && cssSelectors.selectors.length <= 0 ? 'no_matching_rules' : ''
    };
  }

  private parseExecutionRule(encodedFilter: string): AdBlockCosmeticExecutionRule | undefined {
    try {
      const payload = JSON.parse(encodedFilter) as AdBlockRustProceduralFilterPayload;
      if (!Array.isArray(payload.selector) || payload.selector.length <= 0) {
        return undefined;
      }
      let selector = '';
      let procedural = payload.selector.length > 1;
      for (let index = 0; index < payload.selector.length; index += 1) {
        const operator = payload.selector[index];
        const fragment = this.buildSelectorFragment(operator);
        if (fragment.length <= 0) {
          return undefined;
        }
        selector += fragment;
        if (operator.type !== 'css-selector') {
          procedural = true;
        }
      }
      const action = this.resolveAction(payload.action);
      if (action === undefined || selector.trim().length <= 0) {
        return undefined;
      }
      return {
        selector: selector,
        action: action.action,
        value: action.value,
        procedural: procedural
      };
    } catch (_error) {
      return undefined;
    }
  }

  private buildSelectorFragment(operator: AdBlockRustCosmeticOperatorPayload): string {
    const type = String(operator.type ?? '').trim();
    const argument = String(operator.arg ?? '');
    if (type === 'css-selector') {
      return argument;
    }
    if (type === 'has-text') {
      return `:contains(${argument})`;
    }
    if (type === 'matches-css-before') {
      return `:matches-css(before,${this.normalizeMatchesCssArgument(argument)})`;
    }
    if (type === 'matches-css-after') {
      return `:matches-css(after,${this.normalizeMatchesCssArgument(argument)})`;
    }
    if (type === 'matches-attr' || type === 'matches-css' || type === 'matches-path' ||
      type === 'min-text-length' || type === 'upward' || type === 'xpath') {
      return `:${type}(${argument})`;
    }
    return '';
  }

  private normalizeMatchesCssArgument(argument: string): string {
    const trimmed = argument.trim();
    return trimmed.startsWith('before,') || trimmed.startsWith('after,')
      ? trimmed.substring(trimmed.indexOf(',') + 1)
      : trimmed;
  }

  private resolveAction(
    payload: AdBlockRustCosmeticActionPayload | undefined
  ): AdBlockRustCosmeticResolvedAction | undefined {
    if (payload === undefined) {
      return { action: 'hide', value: '' };
    }
    const type = String(payload.type ?? '').trim();
    if (type === 'remove') {
      return { action: 'remove', value: '' };
    }
    if (type === 'style' || type === 'remove-attr' || type === 'remove-class') {
      return {
        action: type as AdBlockCosmeticExecutionAction,
        value: String(payload.arg ?? '')
      };
    }
    return undefined;
  }

  private normalizeCssSelectors(values: string[]): AdBlockRustNormalizedSelectors {
    const selectors: string[] = [];
    let cssLength = 0;
    let truncatedCount = 0;
    values.forEach((value: string): void => {
      const selector = value.trim();
      if (selector.length <= 0 || selectors.includes(selector)) {
        return;
      }
      const nextLength = cssLength + selector.length + COSMETIC_HIDE_RULE_OVERHEAD_LENGTH;
      if (selectors.length >= MAX_COSMETIC_CSS_SELECTORS_PER_PAGE ||
        nextLength > MAX_COSMETIC_CSS_TEXT_LENGTH) {
        truncatedCount += 1;
        return;
      }
      selectors.push(selector);
      cssLength = nextLength;
    });
    return { selectors: selectors, truncatedCount: truncatedCount };
  }

  private parseStringArray(raw: string): string[] {
    try {
      const values = JSON.parse(raw) as string[];
      if (!Array.isArray(values)) {
        return [];
      }
      return values.map((value: string): string => String(value ?? ''));
    } catch (_error) {
      return [];
    }
  }
}

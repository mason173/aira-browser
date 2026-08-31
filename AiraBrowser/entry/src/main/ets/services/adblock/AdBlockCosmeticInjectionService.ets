import { webview } from '@kit.ArkWeb';
import {
  AdBlockCosmeticExecutionPlan,
  AdBlockCosmeticExecutionRule,
  AdBlockCosmeticSelectorCandidates
} from './AdBlockCosmeticExecutionModels';
import { AdBlockCosmeticRuntimeScriptService } from './AdBlockCosmeticRuntimeScriptService';

export interface AdBlockCosmeticInjectionSummary {
  injectedSelectorCount: number;
  hiddenElementCount: number;
  placeholderCollapsedCount: number;
  totalActionCount: number;
  hiddenClickRectCount: number;
  guardListenerCount: number;
  selectors: string[];
  skipped: boolean;
  reason: string;
}

export class AdBlockCosmeticInjectionService {
  private runtimeScriptService: AdBlockCosmeticRuntimeScriptService = new AdBlockCosmeticRuntimeScriptService();

  async collectSelectorCandidates(
    controller: webview.WebviewController | undefined
  ): Promise<AdBlockCosmeticSelectorCandidates> {
    if (controller === undefined) {
      return { classes: [], ids: [] };
    }
    try {
      const rawResult = await controller.runJavaScript(
        this.runtimeScriptService.buildSelectorCandidateCollectionScript()
      );
      return this.runtimeScriptService.parseSelectorCandidates(rawResult);
    } catch (_error) {
      return { classes: [], ids: [] };
    }
  }

  async executeInjectedScript(
    controller: webview.WebviewController | undefined,
    injectedScript: string
  ): Promise<void> {
    if (controller === undefined || injectedScript.trim().length <= 0) {
      return;
    }
    try {
      await controller.runJavaScript(
        this.runtimeScriptService.buildInjectedScriptExecutionScript(injectedScript)
      );
    } catch (_error) {
    }
  }

  async injectForPage(
    controller: webview.WebviewController | undefined,
    pageUrl: string,
    plan: AdBlockCosmeticExecutionPlan,
    enabledForPage: boolean
  ): Promise<AdBlockCosmeticInjectionSummary> {
    if (controller === undefined) {
      return this.skipped('missing_controller');
    }
    if (!enabledForPage) {
      await this.clearForPage(controller);
      return this.skipped('disabled');
    }
    if (plan.skipped) {
      await this.clearForPage(controller);
      return this.skipped(plan.reason);
    }
    let rawResult = '';
    const script = this.runtimeScriptService.buildInjectionScript(plan.rules, plan.cssSelectors, pageUrl);
    try {
      rawResult = await controller.runJavaScript(script);
    } catch (_error) {
      return this.skipped('injection_failed');
    }
    const runtimeResult = this.runtimeScriptService.parseRuntimeResult(rawResult);
    return {
      injectedSelectorCount: plan.cssSelectors.length,
      hiddenElementCount: runtimeResult.hiddenElementCount,
      placeholderCollapsedCount: runtimeResult.placeholderCollapsedCount,
      totalActionCount: runtimeResult.totalActionCount,
      hiddenClickRectCount: runtimeResult.hiddenClickRectCount,
      guardListenerCount: runtimeResult.guardListenerCount,
      selectors: plan.rules.map((rule: AdBlockCosmeticExecutionRule) => this.describeRule(rule)),
      skipped: false,
      reason: ''
    };
  }

  async clearForPage(controller: webview.WebviewController | undefined): Promise<void> {
    if (controller === undefined) {
      return;
    }
    try {
      await controller.runJavaScript(this.runtimeScriptService.buildClearScript());
    } catch (_error) {
    }
  }

  private describeRule(rule: AdBlockCosmeticExecutionRule): string {
    if (rule.action === 'remove') {
      return `${rule.selector}:remove()`;
    }
    if (rule.action === 'style') {
      return `${rule.selector}:style(${rule.value})`;
    }
    if (rule.action === 'remove-attr') {
      return `${rule.selector}:remove-attr(${rule.value})`;
    }
    if (rule.action === 'remove-class') {
      return `${rule.selector}:remove-class(${rule.value})`;
    }
    return rule.selector;
  }

  private skipped(reason: string): AdBlockCosmeticInjectionSummary {
    return {
      injectedSelectorCount: 0,
      hiddenElementCount: 0,
      placeholderCollapsedCount: 0,
      totalActionCount: 0,
      hiddenClickRectCount: 0,
      guardListenerCount: 0,
      selectors: [],
      skipped: true,
      reason: reason
    };
  }
}

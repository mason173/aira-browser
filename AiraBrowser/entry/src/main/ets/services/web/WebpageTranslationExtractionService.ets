import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebpageTranslationRuntimeScriptService } from './WebpageTranslationRuntimeScriptService';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationApplyResult,
  WebpageTranslationExtractionDiagnostics,
  WebpageTranslationExtractionResult,
  WebpageTranslationRuntimeMutationResult,
  WebpageTranslationTextItem
} from './WebpageTranslationRuntimeModels';

const WEBPAGE_TRANSLATION_LOG_DOMAIN: number = 0x0000;
const WEBPAGE_TRANSLATION_LOG_TAG: string = 'QFWebTranslate';
const WEBPAGE_TRANSLATION_APPLY_TIMEOUT_MS: number = 3000;

interface RawWebpageTranslationApplyResult {
  appliedCount?: number;
  applied?: number;
  appliedIds?: string[];
  requestedCount?: number;
  missingNodeCount?: number;
  invalidTextCount?: number;
  changedTextCount?: number;
  unchangedTextCount?: number;
}

interface RawWebpageTranslationRuntimeMutationResult {
  requestedCount?: number;
  markedCount?: number;
  clearedCount?: number;
  failedCount?: number;
  missingNodeCount?: number;
  skippedCount?: number;
  changedTextCount?: number;
}

export class WebpageTranslationExtractionService {
  private runtimeScriptService: WebpageTranslationRuntimeScriptService = new WebpageTranslationRuntimeScriptService();

  async install(controller: webview.WebviewController): Promise<void> {
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildInstallScript());
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'runtime install result=%{public}s',
      result
    );
  }

  async extractVisibleBatch(
    controller: webview.WebviewController,
    limitNodes: number = 80,
    limitChars: number = 6000
  ): Promise<WebpageTranslationExtractionResult> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(
      this.runtimeScriptService.buildExtractVisibleBatchScript(limitNodes, limitChars)
    );
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'extract raw length=%{public}d head=%{public}s',
      result.length,
      result.substring(0, 96)
    );
    const extraction = this.parseExtractionResult(result);
    this.logExtractionDiagnostics('visible', extraction);
    return extraction;
  }

  async extractPageQueue(
    controller: webview.WebviewController,
    limitNodes: number = 240,
    limitChars: number = 24000,
    maxItemChars: number = 900
  ): Promise<WebpageTranslationExtractionResult> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(
      this.runtimeScriptService.buildExtractPageQueueScript(limitNodes, limitChars, maxItemChars)
    );
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'extract queue raw length=%{public}d head=%{public}s',
      result.length,
      result.substring(0, 96)
    );
    const extraction = this.parseExtractionResult(result);
    this.logExtractionDiagnostics('queue', extraction);
    return extraction;
  }

  async configureCache(
    controller: webview.WebviewController,
    namespace: string
  ): Promise<void> {
    await this.install(controller);
    await controller.runJavaScript(this.runtimeScriptService.buildConfigureCacheScript(namespace));
  }

  async extractPendingBatch(
    controller: webview.WebviewController,
    limitNodes: number = 40,
    limitChars: number = 3000
  ): Promise<WebpageTranslationExtractionResult> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(
      this.runtimeScriptService.buildExtractPendingBatchScript(limitNodes, limitChars)
    );
    const extraction = this.parseExtractionResult(this.normalizeJavaScriptResult(rawResult));
    this.logExtractionDiagnostics('pending', extraction);
    return extraction;
  }

  async applyTranslations(
    controller: webview.WebviewController,
    items: WebpageTranslationApplyItem[]
  ): Promise<WebpageTranslationApplyResult> {
    if (items.length === 0) {
      return {
        appliedCount: 0,
        appliedIds: [],
        requestedCount: 0,
        missingNodeCount: 0,
        invalidTextCount: 0,
        changedTextCount: 0,
        unchangedTextCount: 0
      };
    }
    const payload = JSON.stringify({ items: items });
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'apply start items=%{public}d payloadLength=%{public}d',
      items.length,
      payload.length
    );
    const rawResult = await this.runJavaScriptWithTimeout(
      controller,
      this.runtimeScriptService.buildApplyTranslationsScript(payload),
      WEBPAGE_TRANSLATION_APPLY_TIMEOUT_MS
    );
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'apply raw result=%{public}s items=%{public}d',
      result,
      items.length
    );
    return this.parseApplyResult(result);
  }

  async markLoading(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    runId: number
  ): Promise<WebpageTranslationRuntimeMutationResult> {
    if (items.length === 0) {
      return this.createEmptyMutationResult();
    }
    await this.install(controller);
    const payload = JSON.stringify({ runId: runId, items: this.buildRuntimeItemsPayload(items) });
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildMarkLoadingScript(payload));
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'mark loading result=%{public}s items=%{public}d',
      result,
      items.length
    );
    return this.parseMutationResult(result);
  }

  async clearLoading(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    runId?: number
  ): Promise<WebpageTranslationRuntimeMutationResult> {
    if (items.length === 0) {
      return this.createEmptyMutationResult();
    }
    await this.install(controller);
    const payload = JSON.stringify({
      runId: runId === undefined ? '' : runId,
      items: this.buildRuntimeItemsPayload(items)
    });
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildClearLoadingScript(payload));
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'clear loading result=%{public}s items=%{public}d',
      result,
      items.length
    );
    return this.parseMutationResult(result);
  }

  async markFailed(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    message: string,
    runId?: number
  ): Promise<WebpageTranslationRuntimeMutationResult> {
    if (items.length === 0) {
      return this.createEmptyMutationResult();
    }
    await this.install(controller);
    const payload = JSON.stringify({
      runId: runId === undefined ? '' : runId,
      message: message,
      items: this.buildRuntimeItemsPayload(items)
    });
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildMarkFailedScript(payload));
    const result = this.normalizeJavaScriptResult(rawResult);
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'mark failed result=%{public}s items=%{public}d',
      result,
      items.length
    );
    return this.parseMutationResult(result);
  }

  async clearTransientStates(controller: webview.WebviewController): Promise<number> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildClearTransientStatesScript());
    const cleared = Number(this.normalizeJavaScriptResult(rawResult));
    return Number.isFinite(cleared) && cleared > 0 ? Math.floor(cleared) : 0;
  }

  async restoreOriginals(controller: webview.WebviewController): Promise<number> {
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildRestoreOriginalsScript());
    const restored = Number(this.normalizeJavaScriptResult(rawResult));
    return Number.isFinite(restored) && restored > 0 ? Math.floor(restored) : 0;
  }

  async showBilingualTranslations(controller: webview.WebviewController): Promise<number> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildShowBilingualTranslationsScript());
    const shown = Number(this.normalizeJavaScriptResult(rawResult));
    return Number.isFinite(shown) && shown > 0 ? Math.floor(shown) : 0;
  }

  async showTranslationOnly(controller: webview.WebviewController): Promise<number> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildShowTranslationOnlyScript());
    const shown = Number(this.normalizeJavaScriptResult(rawResult));
    return Number.isFinite(shown) && shown > 0 ? Math.floor(shown) : 0;
  }

  async clear(controller: webview.WebviewController): Promise<void> {
    await controller.runJavaScript(this.runtimeScriptService.buildClearScript());
  }

  async startDynamicTracking(controller: webview.WebviewController, debounceMs: number = 800): Promise<void> {
    await this.install(controller);
    await controller.runJavaScript(this.runtimeScriptService.buildInstallSpaHooksScript());
    await controller.runJavaScript(this.runtimeScriptService.buildStartObserverScript(debounceMs));
  }

  async stopDynamicTracking(controller: webview.WebviewController): Promise<void> {
    await controller.runJavaScript(this.runtimeScriptService.buildStopObserverScript());
  }

  async getPageSignalVersion(controller: webview.WebviewController): Promise<string> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildGetPageSignalVersionScript());
    return this.normalizeJavaScriptResult(rawResult);
  }

  async getRouteSignalVersion(controller: webview.WebviewController): Promise<string> {
    await this.install(controller);
    const rawResult = await controller.runJavaScript(this.runtimeScriptService.buildGetRouteSignalVersionScript());
    return this.normalizeJavaScriptResult(rawResult);
  }

  private normalizeJavaScriptResult(rawResult: Object | string | number | boolean | undefined): string {
    const value = String(rawResult ?? '');
    const trimmed = value.trim();
    if (trimmed.length < 2 || !trimmed.startsWith('"') || !trimmed.endsWith('"')) {
      return value;
    }
    try {
      const parsed = JSON.parse(trimmed) as string;
      return typeof parsed === 'string' ? parsed : value;
    } catch (_error) {
      return value;
    }
  }

  private parseExtractionResult(rawResult: string): WebpageTranslationExtractionResult {
    const fallback: WebpageTranslationExtractionResult = {
      url: '',
      lang: '',
      title: '',
      items: [],
      diagnostics: undefined
    };
    if (rawResult.trim().length === 0) {
      return fallback;
    }
    try {
      const parsed = JSON.parse(rawResult) as WebpageTranslationExtractionResult;
      return {
        url: (parsed.url ?? '').trim(),
        lang: (parsed.lang ?? '').trim(),
        title: (parsed.title ?? '').trim(),
        items: this.normalizeItems(parsed.items ?? []),
        diagnostics: this.normalizeDiagnostics(parsed.diagnostics)
      };
    } catch (_error) {
      return fallback;
    }
  }

  private normalizeDiagnostics(
    diagnostics: WebpageTranslationExtractionDiagnostics | undefined
  ): WebpageTranslationExtractionDiagnostics | undefined {
    if (diagnostics === undefined) {
      return undefined;
    }
    return {
      mode: (diagnostics.mode ?? '').trim(),
      totalTextNodes: this.normalizeOptionalNumber(diagnostics.totalTextNodes),
      acceptedTextNodes: this.normalizeOptionalNumber(diagnostics.acceptedTextNodes),
      rejectedByElement: this.normalizeOptionalNumber(diagnostics.rejectedByElement),
      rejectedByText: this.normalizeOptionalNumber(diagnostics.rejectedByText),
      rejectedByViewport: this.normalizeOptionalNumber(diagnostics.rejectedByViewport),
      rejectedByScore: this.normalizeOptionalNumber(diagnostics.rejectedByScore),
      skippedTranslated: this.normalizeOptionalNumber(diagnostics.skippedTranslated),
      cachedHitCount: this.normalizeOptionalNumber(diagnostics.cachedHitCount),
      candidateCount: this.normalizeOptionalNumber(diagnostics.candidateCount),
      strongCandidateCount: this.normalizeOptionalNumber(diagnostics.strongCandidateCount),
      scoreFloor: this.normalizeOptionalNumber(diagnostics.scoreFloor),
      selectedCount: this.normalizeOptionalNumber(diagnostics.selectedCount),
      selectedChars: this.normalizeOptionalNumber(diagnostics.selectedChars),
      limitNodes: this.normalizeOptionalNumber(diagnostics.limitNodes),
      limitChars: this.normalizeOptionalNumber(diagnostics.limitChars),
      maxItemChars: this.normalizeOptionalNumber(diagnostics.maxItemChars),
      pendingCount: this.normalizeOptionalNumber(diagnostics.pendingCount),
      viewportHeight: this.normalizeOptionalNumber(diagnostics.viewportHeight),
      scrollHeight: this.normalizeOptionalNumber(diagnostics.scrollHeight),
      pageScrollable: diagnostics.pageScrollable === true
    };
  }

  private logExtractionDiagnostics(label: string, extraction: WebpageTranslationExtractionResult): void {
    const diagnostics = extraction.diagnostics;
    if (diagnostics === undefined) {
      hilog.info(
        WEBPAGE_TRANSLATION_LOG_DOMAIN,
        WEBPAGE_TRANSLATION_LOG_TAG,
        'extract diagnostics label=%{public}s unavailable items=%{public}d chars=%{public}d sample=%{public}s',
        label,
        extraction.items.length,
        this.countItemChars(extraction.items),
        this.buildItemSample(extraction.items)
      );
      return;
    }
    hilog.info(
      WEBPAGE_TRANSLATION_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LOG_TAG,
      'extract diagnostics label=%{public}s mode=%{public}s totalText=%{public}d accepted=%{public}d candidates=%{public}d selected=%{public}d selectedChars=%{public}d cached=%{public}d strong=%{public}d scoreFloor=%{public}d skippedTranslated=%{public}d rejectedElement=%{public}d rejectedText=%{public}d rejectedViewport=%{public}d rejectedScore=%{public}d pending=%{public}d limits=%{public}d/%{public}d/%{public}d viewport=%{public}d scrollHeight=%{public}d pageScrollable=%{public}s sample=%{public}s',
      label,
      diagnostics.mode ?? '',
      diagnostics.totalTextNodes ?? 0,
      diagnostics.acceptedTextNodes ?? 0,
      diagnostics.candidateCount ?? 0,
      diagnostics.selectedCount ?? extraction.items.length,
      diagnostics.selectedChars ?? this.countItemChars(extraction.items),
      diagnostics.cachedHitCount ?? 0,
      diagnostics.strongCandidateCount ?? 0,
      diagnostics.scoreFloor ?? 0,
      diagnostics.skippedTranslated ?? 0,
      diagnostics.rejectedByElement ?? 0,
      diagnostics.rejectedByText ?? 0,
      diagnostics.rejectedByViewport ?? 0,
      diagnostics.rejectedByScore ?? 0,
      diagnostics.pendingCount ?? 0,
      diagnostics.limitNodes ?? 0,
      diagnostics.limitChars ?? 0,
      diagnostics.maxItemChars ?? 0,
      diagnostics.viewportHeight ?? 0,
      diagnostics.scrollHeight ?? 0,
      diagnostics.pageScrollable === true ? 'true' : 'false',
      this.buildItemSample(extraction.items)
    );
  }

  private countItemChars(items: WebpageTranslationTextItem[]): number {
    let total = 0;
    items.forEach((item: WebpageTranslationTextItem) => {
      total += item.charLength !== undefined && item.charLength > 0 ? item.charLength : item.text.length;
    });
    return total;
  }

  private buildItemSample(items: WebpageTranslationTextItem[]): string {
    return items.slice(0, 3).map((item: WebpageTranslationTextItem): string => {
      return `${item.id}:${item.text.length}:s${item.score ?? 0}:top${item.top ?? 0}:${this.sanitizeLogText(item.text)}`;
    }).join(' | ');
  }

  private sanitizeLogText(value: string): string {
    return value
      .replace(/\s+/g, ' ')
      .replace(/%/g, '%%')
      .substring(0, 48);
  }

  private normalizeItems(items: WebpageTranslationTextItem[]): WebpageTranslationTextItem[] {
    const results: WebpageTranslationTextItem[] = [];
    items.forEach((item: WebpageTranslationTextItem) => {
      const id = (item.id ?? '').trim();
      const text = (item.text ?? '').trim();
      if (id.length > 0 && text.length > 0) {
        results.push({
          id: id,
          text: text,
          cachedTranslatedText: typeof item.cachedTranslatedText === 'string'
            ? item.cachedTranslatedText.trim()
            : undefined,
          charLength: this.normalizeOptionalNumber(item.charLength),
          order: this.normalizeOptionalNumber(item.order),
          score: this.normalizeOptionalNumber(item.score),
          nearViewport: item.nearViewport === true,
          top: this.normalizeOptionalNumber(item.top)
        });
      }
    });
    return results;
  }

  private buildRuntimeItemsPayload(items: WebpageTranslationTextItem[]): WebpageTranslationTextItem[] {
    return items.map((item: WebpageTranslationTextItem): WebpageTranslationTextItem => {
      return {
        id: item.id,
        text: item.text
      };
    });
  }

  private parseApplyResult(rawResult: string): WebpageTranslationApplyResult {
    const fallbackNumber = Number(rawResult);
    if (Number.isFinite(fallbackNumber) && fallbackNumber > 0) {
      return {
        appliedCount: Math.floor(fallbackNumber),
        appliedIds: [],
        requestedCount: Math.floor(fallbackNumber),
        missingNodeCount: 0,
        invalidTextCount: 0,
        changedTextCount: 0,
        unchangedTextCount: 0
      };
    }
    try {
      const parsed = JSON.parse(rawResult) as RawWebpageTranslationApplyResult;
      const appliedCount = Number(parsed.appliedCount ?? parsed.applied ?? 0);
      const requestedCount = Number(parsed.requestedCount ?? 0);
      const missingNodeCount = Number(parsed.missingNodeCount ?? 0);
      const invalidTextCount = Number(parsed.invalidTextCount ?? 0);
      const changedTextCount = Number(parsed.changedTextCount ?? 0);
      const unchangedTextCount = Number(parsed.unchangedTextCount ?? 0);
      const rawIds: string[] = Array.isArray(parsed.appliedIds) ? parsed.appliedIds : [];
      return {
        appliedCount: Number.isFinite(appliedCount) && appliedCount > 0 ? Math.floor(appliedCount) : 0,
        appliedIds: rawIds
          .map((id: string): string => id.trim())
          .filter((id: string): boolean => id.length > 0),
        requestedCount: Number.isFinite(requestedCount) && requestedCount > 0 ? Math.floor(requestedCount) : 0,
        missingNodeCount: Number.isFinite(missingNodeCount) && missingNodeCount > 0 ? Math.floor(missingNodeCount) : 0,
        invalidTextCount: Number.isFinite(invalidTextCount) && invalidTextCount > 0 ? Math.floor(invalidTextCount) : 0,
        changedTextCount: Number.isFinite(changedTextCount) && changedTextCount > 0 ? Math.floor(changedTextCount) : 0,
        unchangedTextCount: Number.isFinite(unchangedTextCount) && unchangedTextCount > 0 ? Math.floor(unchangedTextCount) : 0
      };
    } catch (_error) {
      return {
        appliedCount: 0,
        appliedIds: [],
        requestedCount: 0,
        missingNodeCount: 0,
        invalidTextCount: 0,
        changedTextCount: 0,
        unchangedTextCount: 0
      };
    }
  }

  private parseMutationResult(rawResult: string): WebpageTranslationRuntimeMutationResult {
    try {
      const parsed = JSON.parse(rawResult) as RawWebpageTranslationRuntimeMutationResult;
      return {
        requestedCount: this.normalizeCount(parsed.requestedCount),
        markedCount: this.normalizeCount(parsed.markedCount),
        clearedCount: this.normalizeCount(parsed.clearedCount),
        failedCount: this.normalizeCount(parsed.failedCount),
        missingNodeCount: this.normalizeCount(parsed.missingNodeCount),
        skippedCount: this.normalizeCount(parsed.skippedCount),
        changedTextCount: this.normalizeCount(parsed.changedTextCount)
      };
    } catch (_error) {
      return this.createEmptyMutationResult();
    }
  }

  private createEmptyMutationResult(): WebpageTranslationRuntimeMutationResult {
    return {
      requestedCount: 0,
      markedCount: 0,
      clearedCount: 0,
      failedCount: 0,
      missingNodeCount: 0,
      skippedCount: 0,
      changedTextCount: 0
    };
  }

  private normalizeCount(value: number | undefined): number {
    const normalized = Number(value ?? 0);
    return Number.isFinite(normalized) && normalized > 0 ? Math.floor(normalized) : 0;
  }

  private async runJavaScriptWithTimeout(
    controller: webview.WebviewController,
    script: string,
    timeoutMs: number
  ): Promise<Object | string | number | boolean | undefined> {
    let timer = 0;
    const timeoutPromise = new Promise<string>((resolve) => {
      timer = setTimeout(() => {
        hilog.error(
          WEBPAGE_TRANSLATION_LOG_DOMAIN,
          WEBPAGE_TRANSLATION_LOG_TAG,
          'apply timeout timeoutMs=%{public}d',
          timeoutMs
        );
        resolve('apply_timeout');
      }, timeoutMs);
    });
    const result = await Promise.race([
      controller.runJavaScript(script),
      timeoutPromise
    ]);
    if (timer !== 0) {
      clearTimeout(timer);
    }
    return result;
  }

  private normalizeOptionalNumber(value: number | undefined): number | undefined {
    if (value === undefined || !Number.isFinite(value)) {
      return undefined;
    }
    return Math.floor(value);
  }
}

import { webview } from '@kit.ArkWeb';
import {
  WebpageTranslationApplyItem,
  WebpageTranslationApplyResult,
  WebpageTranslationExtractionResult,
  WebpageTranslationRuntimeMutationResult,
  WebpageTranslationTextItem
} from './WebpageTranslationRuntimeModels';
import { WebpageTranslationExtractionService } from './WebpageTranslationExtractionService';

export class WebpageTranslationRuntimeBridge {
  private executor: WebpageTranslationExtractionService = new WebpageTranslationExtractionService();

  async configureCache(controller: webview.WebviewController, namespace: string): Promise<void> {
    await this.executor.configureCache(controller, namespace);
  }

  async extractVisibleBatch(
    controller: webview.WebviewController,
    limitNodes: number,
    limitChars: number
  ): Promise<WebpageTranslationExtractionResult> {
    return this.executor.extractVisibleBatch(controller, limitNodes, limitChars);
  }

  async extractPageQueue(
    controller: webview.WebviewController,
    limitNodes: number,
    limitChars: number,
    maxItemChars: number
  ): Promise<WebpageTranslationExtractionResult> {
    return this.executor.extractPageQueue(controller, limitNodes, limitChars, maxItemChars);
  }

  async extractPendingBatch(
    controller: webview.WebviewController,
    limitNodes: number,
    limitChars: number
  ): Promise<WebpageTranslationExtractionResult> {
    return this.executor.extractPendingBatch(controller, limitNodes, limitChars);
  }

  async applyTranslations(
    controller: webview.WebviewController,
    items: WebpageTranslationApplyItem[]
  ): Promise<WebpageTranslationApplyResult> {
    return this.executor.applyTranslations(controller, items);
  }

  async markLoading(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    runId: number
  ): Promise<WebpageTranslationRuntimeMutationResult> {
    return this.executor.markLoading(controller, items, runId);
  }

  async clearLoading(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    runId?: number
  ): Promise<WebpageTranslationRuntimeMutationResult> {
    return this.executor.clearLoading(controller, items, runId);
  }

  async markFailed(
    controller: webview.WebviewController,
    items: WebpageTranslationTextItem[],
    message: string,
    runId?: number
  ): Promise<WebpageTranslationRuntimeMutationResult> {
    return this.executor.markFailed(controller, items, message, runId);
  }

  async clearTransientStates(controller: webview.WebviewController): Promise<number> {
    return this.executor.clearTransientStates(controller);
  }

  async restoreOriginals(controller: webview.WebviewController): Promise<number> {
    return this.executor.restoreOriginals(controller);
  }

  async showBilingualTranslations(controller: webview.WebviewController): Promise<number> {
    return this.executor.showBilingualTranslations(controller);
  }

  async showTranslationOnly(controller: webview.WebviewController): Promise<number> {
    return this.executor.showTranslationOnly(controller);
  }

  async clear(controller: webview.WebviewController): Promise<void> {
    await this.executor.clear(controller);
  }

  async startDynamicTracking(controller: webview.WebviewController): Promise<void> {
    await this.executor.startDynamicTracking(controller);
  }

  async stopDynamicTracking(controller: webview.WebviewController): Promise<void> {
    await this.executor.stopDynamicTracking(controller);
  }

  async getPageSignalVersion(controller: webview.WebviewController): Promise<string> {
    return this.executor.getPageSignalVersion(controller);
  }

  async getRouteSignalVersion(controller: webview.WebviewController): Promise<string> {
    return this.executor.getRouteSignalVersion(controller);
  }
}

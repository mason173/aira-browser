import { webview } from '@kit.ArkWeb';
import { ManualElementHideRepository } from '../../data/adblock/ManualElementHideRepository';
import {
  ManualElementHideNavigationRuntimeResult,
  ManualElementHideRuntimeScriptService,
  ManualElementHideSelectionRuntimeState,
  ManualElementHideSessionSnapshot
} from './ManualElementHideRuntimeScriptService';
import { BrowserRuntimeLifecyclePort } from '../web/BrowserRuntimeLifecyclePort';

export interface ManualElementHideApplyResult {
  appliedSelectorCount: number;
  hiddenElementCount: number;
  skipped: boolean;
  reason: string;
}

export interface ManualElementHideFinishResult {
  savedSelectorCount: number;
  totalRuleCount: number;
}

export interface ManualElementHideNavigationResult {
  selectedCount: number;
  selectedElementSelector: string;
  changed: boolean;
  reason: string;
}

export interface ManualElementHideSelectionState {
  selectedCount: number;
  selectedElementSelector: string;
}

export interface ManualElementHideRuntimeHost {
  resolveActiveController: () => webview.WebviewController | undefined;
  resolveController: (tabId: string) => webview.WebviewController | undefined;
}

export class ManualElementHideService {
  private repository: ManualElementHideRepository;
  private runtimeScriptService: ManualElementHideRuntimeScriptService;

  constructor(
    repository: ManualElementHideRepository,
    runtimeScriptService: ManualElementHideRuntimeScriptService = new ManualElementHideRuntimeScriptService()
  ) {
    this.repository = repository;
    this.runtimeScriptService = runtimeScriptService;
  }

  async ensureRepositoryReady(): Promise<void> {
    await this.repository.ensureInitialized();
  }

  isRepositoryReady(): boolean {
    return this.repository.isInitialized();
  }

  async applyForPage(
    controller: webview.WebviewController | undefined,
    host: string,
    pageUrl: string = ''
  ): Promise<ManualElementHideApplyResult> {
    if (controller === undefined) {
      return this.skipped('missing_controller');
    }
    const normalizedHost = this.normalizeHost(host);
    if (normalizedHost.length === 0) {
      return this.skipped('unsupported_page');
    }
    const selectors = this.repository.getEnabledSelectorsForHost(normalizedHost);
    if (selectors.length === 0) {
      return this.skipped('no_rules');
    }
    let rawResult = '';
    try {
      rawResult = await controller.runJavaScript(this.runtimeScriptService.buildApplyRulesScript(selectors, pageUrl));
    } catch (_error) {
      return this.skipped('apply_failed');
    }
    const runtimeResult = this.runtimeScriptService.parseApplyRuntimeResult(String(rawResult ?? ''));
    return {
      appliedSelectorCount: runtimeResult.selectorCount > 0 ? runtimeResult.selectorCount : selectors.length,
      hiddenElementCount: runtimeResult.hiddenElementCount,
      skipped: false,
      reason: ''
    };
  }

  async applyForPageFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    tabId: string,
    host: string,
    pageUrl: string = ''
  ): Promise<ManualElementHideApplyResult> {
    return await this.applyForPage(runtimeLifecyclePort.resolveController(tabId), host, pageUrl);
  }

  async applyForPageFromHost(
    runtimeHost: ManualElementHideRuntimeHost,
    tabId: string,
    host: string,
    pageUrl: string = ''
  ): Promise<ManualElementHideApplyResult> {
    return await this.applyForPage(runtimeHost.resolveController(tabId), host, pageUrl);
  }

  hasActiveControllerFromLifecyclePort(runtimeLifecyclePort: BrowserRuntimeLifecyclePort): boolean {
    return runtimeLifecyclePort.resolveActiveController() !== undefined;
  }

  async startSelectionFromLifecyclePort(runtimeLifecyclePort: BrowserRuntimeLifecyclePort): Promise<boolean> {
    return await this.startSelection(runtimeLifecyclePort.resolveActiveController());
  }

  async startSelection(controller: webview.WebviewController | undefined): Promise<boolean> {
    if (controller === undefined) {
      return false;
    }
    const rawResult = await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildStartSelectionScript()
    );
    return rawResult !== undefined;
  }

  async undoSelectionFromLifecyclePort(runtimeLifecyclePort: BrowserRuntimeLifecyclePort): Promise<number> {
    return await this.undoSelection(runtimeLifecyclePort.resolveActiveController());
  }

  async undoSelection(controller: webview.WebviewController | undefined): Promise<number> {
    if (controller === undefined) {
      return 0;
    }
    const rawResult = await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildUndoSelectionScript()
    );
    return this.parseCount(rawResult);
  }

  async navigateSelectionFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    direction: 'parent' | 'child'
  ): Promise<ManualElementHideNavigationResult> {
    return await this.navigateSelection(runtimeLifecyclePort.resolveActiveController(), direction);
  }

  async navigateSelection(
    controller: webview.WebviewController | undefined,
    direction: 'parent' | 'child'
  ): Promise<ManualElementHideNavigationResult> {
    if (controller === undefined) {
      return this.emptyNavigationResult();
    }
    const rawResult = await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildNavigateSelectionScript(direction)
    );
    if (rawResult === undefined) {
      return this.emptyNavigationResult();
    }
    const rawText = `${rawResult ?? ''}`;
    const runtimeResult: ManualElementHideNavigationRuntimeResult =
      this.runtimeScriptService.parseNavigationRuntimeResult(rawText);
    const selectedCount = typeof runtimeResult.selectedCount === 'number'
      ? Math.max(0, Math.floor(runtimeResult.selectedCount))
      : 0;
    const selectedElementSelector = `${runtimeResult.selectedElementSelector ?? ''}`.trim();
    const reason = `${runtimeResult.reason ?? 'runtime_unavailable'}`;
    return {
      selectedCount: selectedCount,
      selectedElementSelector: selectedElementSelector,
      changed: runtimeResult.changed,
      reason: reason
    };
  }

  async readSelectionStateFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): Promise<ManualElementHideSelectionState> {
    return await this.readSelectionState(runtimeLifecyclePort.resolveActiveController());
  }

  async readSelectionState(
    controller: webview.WebviewController | undefined
  ): Promise<ManualElementHideSelectionState> {
    if (controller === undefined) {
      return this.emptySelectionState();
    }
    const rawResult = await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildSelectionStateScript()
    );
    if (rawResult === undefined) {
      return this.emptySelectionState();
    }
    const rawText = `${rawResult ?? ''}`;
    const runtimeState: ManualElementHideSelectionRuntimeState =
      this.runtimeScriptService.parseSelectionRuntimeState(rawText);
    const selectedCount = typeof runtimeState.selectedCount === 'number'
      ? Math.max(0, Math.floor(runtimeState.selectedCount))
      : 0;
    const selectedElementSelector = `${runtimeState.selectedElementSelector ?? ''}`.trim();
    return {
      selectedCount: selectedCount,
      selectedElementSelector: selectedElementSelector
    };
  }

  async cancelSelectionFromLifecyclePort(runtimeLifecyclePort: BrowserRuntimeLifecyclePort): Promise<void> {
    await this.cancelSelection(runtimeLifecyclePort.resolveActiveController());
  }

  async cancelSelection(controller: webview.WebviewController | undefined): Promise<void> {
    if (controller === undefined) {
      return;
    }
    await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildStopSelectionScript(true)
    );
  }

  async finishSelectionFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    host: string,
    pageUrl: string,
    selectorLimit: number = -1
  ): Promise<ManualElementHideFinishResult> {
    return await this.finishSelection(runtimeLifecyclePort.resolveActiveController(), host, pageUrl, selectorLimit);
  }

  async finishSelection(
    controller: webview.WebviewController | undefined,
    host: string,
    pageUrl: string,
    selectorLimit: number = -1
  ): Promise<ManualElementHideFinishResult> {
    await this.ensureRepositoryReady();
    if (controller === undefined) {
      return {
        savedSelectorCount: 0,
        totalRuleCount: this.repository.getRuleCountForHost(host)
      };
    }
    const rawSnapshot = await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildSnapshotSelectionScript()
    );
    if (rawSnapshot === undefined) {
      return {
        savedSelectorCount: 0,
        totalRuleCount: this.repository.getRuleCountForHost(host)
      };
    }
    const snapshot: ManualElementHideSessionSnapshot =
      this.runtimeScriptService.parseSessionSnapshot(String(rawSnapshot ?? ''));
    if (selectorLimit >= 0 && snapshot.selectors.length > selectorLimit) {
      await this.runJavaScriptSafely(
        controller,
        this.runtimeScriptService.buildStopSelectionScript(true)
      );
      throw new Error(`当前版本最多还能保存 ${selectorLimit} 条隐藏规则。`);
    }
    await this.runJavaScriptSafely(
      controller,
      this.runtimeScriptService.buildStopSelectionScript(false)
    );
    const site = await this.repository.addSelectorsForHost(host, snapshot.selectors, pageUrl);
    if (site !== undefined && site.enabled) {
      await this.applyForPage(controller, host, pageUrl);
    }
    return {
      savedSelectorCount: snapshot.selectors.length,
      totalRuleCount: site?.rules.length ?? this.repository.getRuleCountForHost(host)
    };
  }

  getRuleCountForHost(host: string): number {
    return this.repository.getRuleCountForHost(host);
  }

  getTotalRuleCount(): number {
    return this.repository.getSettings().sites.reduce((total: number, site) => {
      return total + site.rules.length;
    }, 0);
  }

  private parseCount(value: string | undefined): number {
    const normalized = this.runtimeScriptService.unwrapJsonString(String(value ?? '0'));
    const parsed = Number.parseInt(normalized, 10);
    if (Number.isNaN(parsed)) {
      return 0;
    }
    return Math.max(0, parsed);
  }

  private async runJavaScriptSafely(
    controller: webview.WebviewController,
    script: string
  ): Promise<string | undefined> {
    try {
      return await controller.runJavaScript(script);
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeHost(value: string): string {
    let host = (value ?? '').trim().toLowerCase();
    if (host.startsWith('http://')) {
      host = host.substring(7);
    } else if (host.startsWith('https://')) {
      host = host.substring(8);
    }
    const pathStart = host.indexOf('/');
    if (pathStart >= 0) {
      host = host.substring(0, pathStart);
    }
    const portStart = host.indexOf(':');
    if (portStart >= 0) {
      host = host.substring(0, portStart);
    }
    return host;
  }

  private skipped(reason: string): ManualElementHideApplyResult {
    return {
      appliedSelectorCount: 0,
      hiddenElementCount: 0,
      skipped: true,
      reason: reason
    };
  }

  private emptyNavigationResult(): ManualElementHideNavigationResult {
    return {
      selectedCount: 0,
      selectedElementSelector: '',
      changed: false,
      reason: 'runtime_unavailable'
    };
  }

  private emptySelectionState(): ManualElementHideSelectionState {
    return {
      selectedCount: 0,
      selectedElementSelector: ''
    };
  }
}

import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BrowserTabState } from '../tabs/TabManager';
import {
  createHostedWebNodeController,
  HostedWebNodeCallbacks,
  HostedWebNodeConfig,
  HostedWebNodeController,
  HostedWebVideoControllerBridge
} from '../web/HostedWebNode';
import { resolveWebAppearancePolicy, WebAppearancePolicy } from '../web/WebAppearancePolicy';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';
import {
  BrowserHostedWebNodeDisposeAllReason,
  BrowserHostedWebNodeDisposeReason
} from './BrowserRuntimeActionReason';
import {
  buildBrowserTabPreviewComponentSnapshotId,
  buildBrowserTabWebComponentSnapshotId
} from '../../services/web/BrowserTabPreviewCaptureService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import {
  BrowserHostedWebDocumentScriptProvider,
  BrowserHostedWebDocumentScripts
} from '../web/BrowserHostedWebDocumentStartScriptCoordinator';
import { buildGenerationBoundHostedWebNodeCallbacks } from './BrowserHostedWebNodeGenerationCallbacks';
import { BrowserWebRuntimeSecurityPolicy } from '../../common/models/BrowserWebSecurityModels';
import {
  sharedBrowserWebRuntimeSecurityPolicyService
} from '../../services/web/BrowserWebRuntimeSecurityPolicyService';

export interface BrowserWebHostSyncInput {
  uiContext: UIContext;
  activeTab?: BrowserTabState;
  runtime?: WebTabRuntimeRecord;
  showHomePage?: boolean;
  suspendActiveWebSurface?: boolean;
  appearancePolicy?: WebAppearancePolicy;
  documentStartScripts?: ScriptItem[];
  documentEndScripts?: ScriptItem[];
  userScriptNativeBridge?: Object;
  webVideoControllerBridge?: HostedWebVideoControllerBridge;
  forceEnableWebZoom?: boolean;
  textZoomRatio?: number;
  pullRefreshNestedScrollEnabled?: boolean;
  callbacks: HostedWebNodeCallbacks;
}

export interface BrowserWebHostConfigUpdateInput {
  uiContext: UIContext;
  activeTab?: BrowserTabState;
  controller?: webview.WebviewController;
  showHomePage?: boolean;
  appearancePolicy?: WebAppearancePolicy;
  documentStartScripts?: ScriptItem[];
  documentEndScripts?: ScriptItem[];
  userScriptNativeBridge?: Object;
  forceEnableWebZoom?: boolean;
  textZoomRatio?: number;
  pullRefreshNestedScrollEnabled?: boolean;
  callbacks: HostedWebNodeCallbacks;
}

export interface BrowserWebHostSyncResult {
  activeHostedTabId: string;
  activeHostedRenderKey: string;
  controller?: HostedWebNodeController;
  attached: boolean;
  rebuilt: boolean;
  disposeReason?: BrowserHostedWebNodeDisposeReason | BrowserHostedWebNodeDisposeAllReason;
}

export interface BrowserPreviewWebHostSyncResult {
  previewHostedTabId: string;
  previewHostedRenderKey: string;
  controller?: HostedWebNodeController;
  attached: boolean;
  rebuilt: boolean;
  disposeReason?: BrowserHostedWebNodeDisposeReason | BrowserHostedWebNodeDisposeAllReason;
}

export interface BrowserWebHostAttachState {
  attached: boolean;
  webControllerAttached: boolean;
}

interface BrowserWebHostEnsureResult {
  controller: HostedWebNodeController;
  created: boolean;
}

interface BrowserWebHostAttachResult {
  controller: HostedWebNodeController;
  attached: boolean;
  rebuilt: boolean;
  renderRequired: boolean;
}

export class BrowserWebHostCoordinator {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private readonly documentScriptProvider: BrowserHostedWebDocumentScriptProvider;
  private readonly fixedWebVideoControllerBridge?: HostedWebVideoControllerBridge;
  private hostedWebNodeControllers: Record<string, HostedWebNodeController | undefined> = {};
  private hostedWebNodeGenerationByTabId: Record<string, number | undefined> = {};
  private activeHostedWebNodeTabId: string = '';
  private activeHostedRenderVersion: number = 0;
  private previewHostedWebNodeTabId: string = '';
  private previewHostedRenderVersion: number = 0;
  private previewPromotionTabId: string = '';

  constructor(
    documentScriptProvider: BrowserHostedWebDocumentScriptProvider,
    fixedWebVideoControllerBridge?: HostedWebVideoControllerBridge
  ) {
    this.documentScriptProvider = documentScriptProvider;
    this.fixedWebVideoControllerBridge = fixedWebVideoControllerBridge;
  }

  getActiveHostedTabId(): string {
    return this.activeHostedWebNodeTabId;
  }

  getActiveHostedRenderKey(): string {
    return this.buildActiveHostedRenderKey();
  }

  getController(tabId: string): HostedWebNodeController | undefined {
    if (tabId.length === 0) {
      return undefined;
    }
    return this.hostedWebNodeControllers[tabId];
  }

  getHostedNodeGeneration(tabId: string): number {
    if (tabId.length === 0) {
      return 0;
    }
    return this.resolveNodeGeneration(tabId);
  }

  getPreviewHostedTabId(): string {
    return this.previewHostedWebNodeTabId;
  }

  shouldRefreshActiveRenderForPreviewPromotion(tabId: string): boolean {
    return this.consumePreviewPromotion(tabId.trim());
  }

  promotePreviewToActive(tabId: string): BrowserPreviewWebHostSyncResult {
    const targetTabId = tabId.trim();
    if (targetTabId.length === 0 || this.previewHostedWebNodeTabId !== targetTabId) {
      return this.buildPreviewSyncResult(undefined, false);
    }
    this.detachController(targetTabId);
    this.previewPromotionTabId = targetTabId;
    this.previewHostedWebNodeTabId = '';
    this.bumpPreviewHostedRenderVersion();
    return this.buildPreviewSyncResult(undefined, false);
  }

  syncActive(input: BrowserWebHostSyncInput): BrowserWebHostSyncResult {
    const activeTab = input.activeTab;
    const runtime = input.runtime;
    const appearancePolicy = resolveWebAppearancePolicy(input.appearancePolicy);
    if (
      input.showHomePage === true ||
      input.suspendActiveWebSurface === true ||
      activeTab === undefined ||
      activeTab.isHome ||
      runtime === undefined
    ) {
      this.detachActive();
      return this.buildSyncResult(undefined, false);
    }

    const previousHostedTabId = this.activeHostedWebNodeTabId;
    if (this.activeHostedWebNodeTabId.length > 0 && this.activeHostedWebNodeTabId !== activeTab.id) {
      this.detachController(this.activeHostedWebNodeTabId);
      this.activeHostedWebNodeTabId = '';
    }
    const documentScripts = this.resolveDocumentScripts(
      activeTab,
      input.documentStartScripts,
      input.documentEndScripts
    );
    const webVideoControllerBridge = this.resolveWebVideoControllerBridge(input.webVideoControllerBridge);
    const ensureResult = this.ensureController(
      input.uiContext,
      activeTab,
      runtime,
      appearancePolicy,
      documentScripts.documentStartScripts,
      documentScripts.documentStartScriptKey,
      documentScripts.documentEndScripts,
      documentScripts.documentEndScriptKey,
      input.userScriptNativeBridge,
      webVideoControllerBridge,
      input.forceEnableWebZoom,
      input.textZoomRatio,
      input.pullRefreshNestedScrollEnabled,
      input.callbacks
    );
    const attachResult = this.attachController(
      input.uiContext,
      activeTab,
      runtime,
      appearancePolicy,
      documentScripts.documentStartScripts,
      documentScripts.documentStartScriptKey,
      documentScripts.documentEndScripts,
      documentScripts.documentEndScriptKey,
      input.userScriptNativeBridge,
      webVideoControllerBridge,
      input.forceEnableWebZoom,
      input.textZoomRatio,
      input.pullRefreshNestedScrollEnabled,
      input.callbacks,
      ensureResult
    );
    if (ensureResult.created || attachResult.renderRequired || attachResult.rebuilt) {
      attachResult.controller.rebuild();
    }
    this.activeHostedWebNodeTabId = activeTab.id;
    if (
      previousHostedTabId !== activeTab.id ||
      ensureResult.created ||
      attachResult.rebuilt ||
      attachResult.renderRequired ||
      this.shouldRefreshActiveRenderForPreviewPromotion(activeTab.id)
    ) {
      this.bumpActiveHostedRenderVersion();
    }
    return this.buildSyncResult(attachResult.controller, attachResult.attached, attachResult.rebuilt);
  }

  syncPreview(input: BrowserWebHostSyncInput): BrowserPreviewWebHostSyncResult {
    const previewTab = input.activeTab;
    const runtime = input.runtime;
    const appearancePolicy = resolveWebAppearancePolicy(input.appearancePolicy);
    if (
      previewTab === undefined ||
      previewTab.isHome ||
      runtime === undefined ||
      input.suspendActiveWebSurface === true
    ) {
      this.detachPreview();
      return this.buildPreviewSyncResult(undefined, false);
    }

    const previousPreviewHostedTabId = this.previewHostedWebNodeTabId;
    const documentScripts = this.resolveDocumentScripts(
      previewTab,
      input.documentStartScripts,
      input.documentEndScripts
    );
    const webVideoControllerBridge = this.resolveWebVideoControllerBridge(input.webVideoControllerBridge);
    const ensureResult = this.ensureController(
      input.uiContext,
      previewTab,
      runtime,
      appearancePolicy,
      documentScripts.documentStartScripts,
      documentScripts.documentStartScriptKey,
      documentScripts.documentEndScripts,
      documentScripts.documentEndScriptKey,
      input.userScriptNativeBridge,
      webVideoControllerBridge,
      input.forceEnableWebZoom,
      input.textZoomRatio,
      false,
      input.callbacks
    );
    const attachResult = this.attachController(
      input.uiContext,
      previewTab,
      runtime,
      appearancePolicy,
      documentScripts.documentStartScripts,
      documentScripts.documentStartScriptKey,
      documentScripts.documentEndScripts,
      documentScripts.documentEndScriptKey,
      input.userScriptNativeBridge,
      webVideoControllerBridge,
      input.forceEnableWebZoom,
      input.textZoomRatio,
      false,
      input.callbacks,
      ensureResult
    );
    if (ensureResult.created || attachResult.renderRequired || attachResult.rebuilt) {
      attachResult.controller.rebuild();
    }
    this.previewHostedWebNodeTabId = previewTab.id;
    if (
      previousPreviewHostedTabId !== previewTab.id ||
      ensureResult.created ||
      attachResult.rebuilt ||
      attachResult.renderRequired
    ) {
      this.bumpPreviewHostedRenderVersion();
    }
    return this.buildPreviewSyncResult(attachResult.controller, attachResult.attached, attachResult.rebuilt);
  }

  updateExisting(input: BrowserWebHostConfigUpdateInput): boolean {
    const activeTab = input.activeTab;
    const controller = input.controller;
    if (
      input.showHomePage === true ||
      activeTab === undefined ||
      activeTab.isHome ||
      controller === undefined
    ) {
      return false;
    }
    const existingController = this.hostedWebNodeControllers[activeTab.id];
    if (existingController === undefined) {
      return false;
    }
    const runtimeSecurityPolicy = this.resolveRuntimeSecurityPolicy(activeTab);
    const documentScripts = this.resolveDocumentScripts(
      activeTab,
      input.documentStartScripts,
      input.documentEndScripts
    );
    existingController.update({
      tabId: activeTab.id,
      componentSnapshotId: buildBrowserTabPreviewComponentSnapshotId(activeTab.id),
      webComponentSnapshotId: buildBrowserTabWebComponentSnapshotId(activeTab.id),
      controller: controller,
      uiContext: input.uiContext,
      pageUrl: activeTab.url,
      pageTitle: activeTab.title,
      appearancePolicy: input.appearancePolicy,
      runtimeSecurityPolicy: runtimeSecurityPolicy,
      documentStartScripts: documentScripts.documentStartScripts,
      documentStartScriptKey: documentScripts.documentStartScriptKey,
      documentEndScripts: documentScripts.documentEndScripts,
      documentEndScriptKey: documentScripts.documentEndScriptKey,
      userScriptNativeBridge: input.userScriptNativeBridge,
      webVideoControllerBridge: this.resolveWebVideoControllerBridge(undefined),
      forceEnableWebZoom: input.forceEnableWebZoom,
      textZoomRatio: input.textZoomRatio,
      pullRefreshNestedScrollEnabled: input.pullRefreshNestedScrollEnabled === true,
      callbacks: this.bindCallbacksToCurrentNodeGeneration(activeTab.id, input.callbacks)
    });
    return true;
  }

  detachActive(): BrowserWebHostSyncResult {
    if (this.activeHostedWebNodeTabId.length === 0) {
      return this.buildSyncResult(undefined, false);
    }
    this.detachController(this.activeHostedWebNodeTabId);
    this.activeHostedWebNodeTabId = '';
    this.bumpActiveHostedRenderVersion();
    return this.buildSyncResult(undefined, false);
  }

  parkActive(): BrowserWebHostSyncResult {
    if (this.activeHostedWebNodeTabId.length === 0) {
      return this.buildSyncResult(undefined, false);
    }
    this.activeHostedWebNodeTabId = '';
    this.bumpActiveHostedRenderVersion();
    return this.buildSyncResult(undefined, false);
  }

  detachPreview(tabId: string = ''): BrowserPreviewWebHostSyncResult {
    const targetTabId = tabId.length > 0 ? tabId : this.previewHostedWebNodeTabId;
    if (targetTabId.length === 0 || this.hostedWebNodeControllers[targetTabId] === undefined) {
      return this.buildPreviewSyncResult(undefined, false);
    }
    this.detachController(targetTabId);
    if (this.previewHostedWebNodeTabId === targetTabId) {
      this.previewHostedWebNodeTabId = '';
    }
    this.bumpPreviewHostedRenderVersion();
    return this.buildPreviewSyncResult(undefined, false);
  }

  dispose(tabId: string, reason: BrowserHostedWebNodeDisposeReason): BrowserWebHostSyncResult {
    if (tabId.length === 0) {
      return this.buildSyncResult(undefined, false, false, reason);
    }
    if (this.hostedWebNodeControllers[tabId] === undefined) {
      return this.buildSyncResult(undefined, false, false, reason);
    }
    this.disposeController(tabId);
    if (this.activeHostedWebNodeTabId === tabId) {
      this.activeHostedWebNodeTabId = '';
    }
    if (this.previewHostedWebNodeTabId === tabId) {
      this.previewHostedWebNodeTabId = '';
    }
    this.bumpActiveHostedRenderVersion();
    this.bumpPreviewHostedRenderVersion();
    return this.buildSyncResult(undefined, false, false, reason);
  }

  disposeAll(reason: BrowserHostedWebNodeDisposeAllReason): BrowserWebHostSyncResult {
    Object.keys(this.hostedWebNodeControllers).forEach((tabId: string) => {
      this.disposeController(tabId);
    });
    this.activeHostedWebNodeTabId = '';
    this.previewHostedWebNodeTabId = '';
    this.bumpActiveHostedRenderVersion();
    this.bumpPreviewHostedRenderVersion();
    return this.buildSyncResult(undefined, false, false, reason);
  }

  private resolveDocumentScripts(
    tab: BrowserTabState,
    explicitStartScripts: ScriptItem[] | undefined,
    explicitEndScripts: ScriptItem[] | undefined
  ): BrowserHostedWebDocumentScripts {
    const providedScripts = this.documentScriptProvider.buildForTab(tab);
    return {
      documentStartScripts: explicitStartScripts ?? providedScripts.documentStartScripts,
      documentStartScriptKey: explicitStartScripts === undefined ? providedScripts.documentStartScriptKey : undefined,
      documentEndScripts: explicitEndScripts ?? providedScripts.documentEndScripts,
      documentEndScriptKey: explicitEndScripts === undefined ? providedScripts.documentEndScriptKey : undefined
    };
  }

  private resolveWebVideoControllerBridge(
    explicitBridge: HostedWebVideoControllerBridge | undefined
  ): HostedWebVideoControllerBridge | undefined {
    return explicitBridge ?? this.fixedWebVideoControllerBridge;
  }

  private ensureController(
    uiContext: UIContext,
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord,
    appearancePolicy: WebAppearancePolicy,
    documentStartScripts: ScriptItem[] | undefined,
    documentStartScriptKey: string | undefined,
    documentEndScripts: ScriptItem[] | undefined,
    documentEndScriptKey: string | undefined,
    userScriptNativeBridge: Object | undefined,
    webVideoControllerBridge: HostedWebVideoControllerBridge | undefined,
    forceEnableWebZoom: boolean | undefined,
    textZoomRatio: number | undefined,
    pullRefreshNestedScrollEnabled: boolean | undefined,
    callbacks: HostedWebNodeCallbacks
  ): BrowserWebHostEnsureResult {
    const runtimeSecurityPolicy = this.resolveRuntimeSecurityPolicy(tab);
    const config: HostedWebNodeConfig = {
      tabId: tab.id,
      componentSnapshotId: buildBrowserTabPreviewComponentSnapshotId(tab.id),
      webComponentSnapshotId: buildBrowserTabWebComponentSnapshotId(tab.id),
      controller: runtime.controller,
      uiContext: uiContext,
      pageUrl: tab.url,
      pageTitle: tab.title,
      incognitoMode: this.profileBoundaryService.resolveWebIncognitoMode({
        profileId: tab.profileId,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope,
        sessionId: tab.id
      }),
      appearancePolicy: appearancePolicy,
      runtimeSecurityPolicy: runtimeSecurityPolicy,
      documentStartScripts: documentStartScripts,
      documentStartScriptKey: documentStartScriptKey,
      documentEndScripts: documentEndScripts,
      documentEndScriptKey: documentEndScriptKey,
      userScriptNativeBridge: userScriptNativeBridge,
      webVideoControllerBridge: webVideoControllerBridge,
      forceEnableWebZoom: forceEnableWebZoom,
      textZoomRatio: textZoomRatio,
      pullRefreshNestedScrollEnabled: pullRefreshNestedScrollEnabled === true,
      callbacks: callbacks
    };
    const existingController = this.hostedWebNodeControllers[tab.id];
    if (existingController !== undefined) {
      const documentStartScriptsChanged = existingController.needsDocumentStartScriptRebuild(config);
      if (documentStartScriptsChanged && !existingController.isWebControllerAttached()) {
        existingController.dispose();
        this.invalidateNodeGeneration(tab.id);
        config.callbacks = this.bindCallbacksToNewNodeGeneration(tab.id, callbacks);
        const rebuiltController = createHostedWebNodeController(uiContext, config);
        this.hostedWebNodeControllers[tab.id] = rebuiltController;
        return {
          controller: rebuiltController,
          created: true
        };
      }
      config.callbacks = this.bindCallbacksToCurrentNodeGeneration(tab.id, callbacks);
      existingController.update(config);
      return {
        controller: existingController,
        created: false
      };
    }
    config.callbacks = this.bindCallbacksToNewNodeGeneration(tab.id, callbacks);
    const hostedController = createHostedWebNodeController(uiContext, config);
    this.hostedWebNodeControllers[tab.id] = hostedController;
    return {
      controller: hostedController,
      created: true
    };
  }

  private attachController(
    uiContext: UIContext,
    tab: BrowserTabState,
    runtime: WebTabRuntimeRecord,
    appearancePolicy: WebAppearancePolicy,
    documentStartScripts: ScriptItem[] | undefined,
    documentStartScriptKey: string | undefined,
    documentEndScripts: ScriptItem[] | undefined,
    documentEndScriptKey: string | undefined,
    userScriptNativeBridge: Object | undefined,
    webVideoControllerBridge: HostedWebVideoControllerBridge | undefined,
    forceEnableWebZoom: boolean | undefined,
    textZoomRatio: number | undefined,
    pullRefreshNestedScrollEnabled: boolean | undefined,
    callbacks: HostedWebNodeCallbacks,
    ensureResult: BrowserWebHostEnsureResult
  ): BrowserWebHostAttachResult {
    if (ensureResult.controller.attachWeb()) {
      return {
        controller: ensureResult.controller,
        attached: true,
        rebuilt: false,
        renderRequired: true
      };
    }
    if (ensureResult.controller.isAttached()) {
      return {
        controller: ensureResult.controller,
        attached: true,
        rebuilt: false,
        renderRequired: false
      };
    }
    if (ensureResult.created) {
      return {
        controller: ensureResult.controller,
        attached: false,
        rebuilt: false,
        renderRequired: true
      };
    }

    ensureResult.controller.dispose();
    this.invalidateNodeGeneration(tab.id);
    const generationBoundCallbacks = this.bindCallbacksToNewNodeGeneration(tab.id, callbacks);
    const runtimeSecurityPolicy = this.resolveRuntimeSecurityPolicy(tab);
    const rebuiltController = createHostedWebNodeController(uiContext, {
      tabId: tab.id,
      componentSnapshotId: buildBrowserTabPreviewComponentSnapshotId(tab.id),
      webComponentSnapshotId: buildBrowserTabWebComponentSnapshotId(tab.id),
      controller: runtime.controller,
      uiContext: uiContext,
      pageUrl: tab.url,
      pageTitle: tab.title,
      incognitoMode: this.profileBoundaryService.resolveWebIncognitoMode({
        profileId: tab.profileId,
        privacyMode: tab.privacyMode,
        dataScope: tab.dataScope,
        sessionId: tab.id
      }),
      appearancePolicy: appearancePolicy,
      runtimeSecurityPolicy: runtimeSecurityPolicy,
      documentStartScripts: documentStartScripts,
      documentStartScriptKey: documentStartScriptKey,
      documentEndScripts: documentEndScripts,
      documentEndScriptKey: documentEndScriptKey,
      userScriptNativeBridge: userScriptNativeBridge,
      webVideoControllerBridge: webVideoControllerBridge,
      forceEnableWebZoom: forceEnableWebZoom,
      textZoomRatio: textZoomRatio,
      pullRefreshNestedScrollEnabled: pullRefreshNestedScrollEnabled === true,
      callbacks: generationBoundCallbacks
    });
    this.hostedWebNodeControllers[tab.id] = rebuiltController;
    return {
      controller: rebuiltController,
      attached: rebuiltController.attachWeb(),
      rebuilt: true,
      renderRequired: true
    };
  }

  private detachController(tabId: string): void {
    const controller = this.hostedWebNodeControllers[tabId];
    controller?.detachWeb();
    controller?.rebuild();
  }

  private disposeController(tabId: string): void {
    this.hostedWebNodeControllers[tabId]?.dispose();
    this.hostedWebNodeControllers[tabId] = undefined;
    this.invalidateNodeGeneration(tabId);
  }

  private resolveRuntimeSecurityPolicy(tab: BrowserTabState): BrowserWebRuntimeSecurityPolicy {
    const pendingUrl = tab.pendingUrl.trim();
    return sharedBrowserWebRuntimeSecurityPolicyService.resolve(
      pendingUrl.length > 0 ? pendingUrl : tab.url.trim(),
      tab.profileId
    );
  }

  private bindCallbacksToNewNodeGeneration(
    tabId: string,
    callbacks: HostedWebNodeCallbacks
  ): HostedWebNodeCallbacks {
    const generation = this.resolveNodeGeneration(tabId) + 1;
    this.hostedWebNodeGenerationByTabId[tabId] = generation;
    return this.bindCallbacksToNodeGeneration(tabId, generation, callbacks);
  }

  private bindCallbacksToCurrentNodeGeneration(
    tabId: string,
    callbacks: HostedWebNodeCallbacks
  ): HostedWebNodeCallbacks {
    let generation = this.resolveNodeGeneration(tabId);
    if (generation <= 0) {
      generation = 1;
      this.hostedWebNodeGenerationByTabId[tabId] = generation;
    }
    return this.bindCallbacksToNodeGeneration(tabId, generation, callbacks);
  }

  private bindCallbacksToNodeGeneration(
    tabId: string,
    generation: number,
    callbacks: HostedWebNodeCallbacks
  ): HostedWebNodeCallbacks {
    return buildGenerationBoundHostedWebNodeCallbacks(
      tabId,
      generation,
      callbacks,
      (eventTabId: string, eventGeneration: number): boolean => {
        return eventTabId === tabId && eventGeneration === this.resolveNodeGeneration(tabId);
      }
    );
  }

  private invalidateNodeGeneration(tabId: string): void {
    if (tabId.length <= 0) {
      return;
    }
    this.hostedWebNodeGenerationByTabId[tabId] = this.resolveNodeGeneration(tabId) + 1;
  }

  private resolveNodeGeneration(tabId: string): number {
    return this.hostedWebNodeGenerationByTabId[tabId] ?? 0;
  }

  private bumpActiveHostedRenderVersion(): void {
    this.activeHostedRenderVersion += 1;
  }

  private bumpPreviewHostedRenderVersion(): void {
    this.previewHostedRenderVersion += 1;
  }

  private consumePreviewPromotion(tabId: string): boolean {
    if (this.previewPromotionTabId !== tabId) {
      return false;
    }
    this.previewPromotionTabId = '';
    return true;
  }

  private buildActiveHostedRenderKey(): string {
    if (this.activeHostedWebNodeTabId.length === 0) {
      return '';
    }
    return `${this.activeHostedWebNodeTabId}:${this.activeHostedRenderVersion}`;
  }

  private buildPreviewHostedRenderKey(): string {
    if (this.previewHostedWebNodeTabId.length === 0) {
      return '';
    }
    return `${this.previewHostedWebNodeTabId}:preview:${this.previewHostedRenderVersion}`;
  }

  private buildSyncResult(
    controller: HostedWebNodeController | undefined,
    attached: boolean,
    rebuilt: boolean = false,
    disposeReason?: BrowserHostedWebNodeDisposeReason | BrowserHostedWebNodeDisposeAllReason
  ): BrowserWebHostSyncResult {
    return {
      activeHostedTabId: this.activeHostedWebNodeTabId,
      activeHostedRenderKey: this.buildActiveHostedRenderKey(),
      controller: controller,
      attached: attached,
      rebuilt: rebuilt,
      disposeReason: disposeReason
    };
  }

  private buildPreviewSyncResult(
    controller: HostedWebNodeController | undefined,
    attached: boolean,
    rebuilt: boolean = false,
    disposeReason?: BrowserHostedWebNodeDisposeReason | BrowserHostedWebNodeDisposeAllReason
  ): BrowserPreviewWebHostSyncResult {
    return {
      previewHostedTabId: this.previewHostedWebNodeTabId,
      previewHostedRenderKey: this.buildPreviewHostedRenderKey(),
      controller: controller,
      attached: attached,
      rebuilt: rebuilt,
      disposeReason: disposeReason
    };
  }
}

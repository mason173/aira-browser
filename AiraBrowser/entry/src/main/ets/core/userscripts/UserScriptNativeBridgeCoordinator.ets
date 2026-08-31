import { webview } from '@kit.ArkWeb';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UserScriptRuntimeStateRepository } from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import {
  RawUserScriptNativeBridgePayload,
  UserScriptNativeBridgeRoute,
  UserScriptNativeDownloadTaskUpdate,
  UserScriptNativeBridgeTokenRecord
} from '../../features/userscripts/UserScriptNativeBridgeModels';
import {
  UserScriptValueCommitResult,
  UserScriptValueMutation,
  UserScriptValueStateError
} from '../../features/userscripts/UserScriptValueModels';
import { UserScriptCapabilityContractService } from '../../services/userscripts/UserScriptCapabilityContractService';
import { ManualDownloadRequestInput } from '../../services/download/DownloadRuntimeService';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { UserScriptNativeClipboardService } from '../../services/userscripts/UserScriptNativeClipboardService';
import { UserScriptNativeDownloadService } from '../../services/userscripts/UserScriptNativeDownloadService';
import { UserScriptNativeXmlHttpRequestService } from '../../services/userscripts/UserScriptNativeXmlHttpRequestService';
import { UserScriptNativeBridgePermissionCoordinator } from './UserScriptNativeBridgePermissionCoordinator';
import { UserScriptRuntimeReadinessCoordinator } from './UserScriptRuntimeReadinessCoordinator';
import { UserScriptTabStorageService } from './UserScriptTabStorageService';

export interface UserScriptNativeBridgeHost {
  openInTab: (openerTabId: string, url: string, active: boolean) => void;
  requestDownload: (request: ManualDownloadRequestInput) => string;
  showMessage: (message: string) => void;
  runMediaSniff: (tabId: string, sourcePageUrl: string) => void;
}

export type UserScriptAutomaticDocumentSignalPhase = 'document_start' | 'document_end' | 'post_paint';

export interface UserScriptAutomaticDocumentSignal {
  tabId: string;
  documentToken: string;
  pageUrl: string;
  phase: UserScriptAutomaticDocumentSignalPhase;
}

const USER_SCRIPT_NATIVE_BRIDGE_LOG_DOMAIN: number = 0x0000;
const USER_SCRIPT_PERF_DIAGNOSTIC_TAG: string = 'UserScriptPerfDiag';

export class UserScriptNativeBridge {
  private coordinator: UserScriptNativeBridgeCoordinator;
  private controller: webview.WebviewController;
  private tabId: string;
  private resolveCurrentUrl: () => string;

  constructor(
    coordinator: UserScriptNativeBridgeCoordinator,
    controller: webview.WebviewController,
    tabId: string,
    resolveCurrentUrl: () => string
  ) {
    this.coordinator = coordinator;
    this.controller = controller;
    this.tabId = tabId;
    this.resolveCurrentUrl = resolveCurrentUrl;
  }

  request(payloadJson: string): void {
    this.coordinator.handleRequest(String(payloadJson ?? ''), this.controller, this.tabId, this.resolveCurrentUrl());
  }

  readValue(payloadJson: string): string {
    return this.coordinator.handleSynchronousValueRead(
      String(payloadJson ?? ''),
      this.resolveCurrentUrl(),
      this.tabId
    );
  }

  openInTab(payloadJson: string): void {
    this.coordinator.handleOpenInTab(String(payloadJson ?? ''), this.tabId, this.resolveCurrentUrl());
  }

  abort(payloadJson: string): void {
    this.coordinator.handleAbort(String(payloadJson ?? ''), this.resolveCurrentUrl());
  }
}

export class UserScriptNativeBridgeCoordinator {
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private clipboardService: UserScriptNativeClipboardService = new UserScriptNativeClipboardService();
  private downloadService: UserScriptNativeDownloadService = new UserScriptNativeDownloadService();
  private tabStorageService: UserScriptTabStorageService = new UserScriptTabStorageService();
  private xmlHttpRequestService: UserScriptNativeXmlHttpRequestService = new UserScriptNativeXmlHttpRequestService();
  private permissionCoordinator: UserScriptNativeBridgePermissionCoordinator;
  private valueStore: UserScriptValueStateStore;
  private readonly host: UserScriptNativeBridgeHost;
  private downloadControllersByGuid: Record<string, webview.WebviewController | undefined> = {};
  private downloadRequestIdsByGuid: Record<string, string | undefined> = {};
  private tokenRecords: Record<string, UserScriptNativeBridgeTokenRecord | undefined> = {};
  private activeTokenByScriptId: Record<string, string | undefined> = {};
  private automaticDocumentSignalSecret: string = '';
  private automaticDocumentSignalListener?: (signal: UserScriptAutomaticDocumentSignal) => void;
  private warnedValueIncidentId: number = 0;

  constructor(
    valueStore: UserScriptValueStateStore,
    runtimeStateRepository: UserScriptRuntimeStateRepository,
    readinessCoordinator: UserScriptRuntimeReadinessCoordinator,
    host: UserScriptNativeBridgeHost
  ) {
    this.permissionCoordinator = new UserScriptNativeBridgePermissionCoordinator(
      runtimeStateRepository,
      readinessCoordinator
    );
    this.valueStore = valueStore;
    this.host = host;
  }

  createBridge(controller: webview.WebviewController, tabId: string, resolveCurrentUrl: () => string): UserScriptNativeBridge {
    return new UserScriptNativeBridge(this, controller, tabId, resolveCurrentUrl);
  }

  setAutomaticDocumentSignalListener(listener: (signal: UserScriptAutomaticDocumentSignal) => void): void {
    this.automaticDocumentSignalListener = listener;
  }

  resolveAutomaticDocumentSignalSecret(): string {
    if (this.automaticDocumentSignalSecret.length === 0) {
      this.automaticDocumentSignalSecret = this.createTokenSecret();
    }
    return this.automaticDocumentSignalSecret;
  }

  handleSynchronousValueRead(payloadJson: string, currentUrl: string, tabId: string = ''): string {
    const payload = this.parsePayload(payloadJson);
    if (String(payload.kind ?? '').trim() === '__aira_internal_document_start_loader_result') {
      return this.recordDocumentStartLoaderResult(payload, tabId);
    }
    const route = this.resolveRoute(payload);
    if (route === undefined || (route.executor !== 'value_read' && route.executor !== 'value_list')) {
      return JSON.stringify({
        success: false,
        error: 'unsupported-value-read'
      });
    }
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      return JSON.stringify({
        success: false,
        error: validation.message
      });
    }
    try {
      if (route.executor === 'value_list') {
        return JSON.stringify({
          success: true,
          found: true,
          valueJson: JSON.stringify(this.valueStore.readCommittedKeys(validation.scriptId))
        });
      }
      const key = String(payload.key ?? '').trim();
      if (key.length === 0) {
        return JSON.stringify({
          success: false,
          error: 'missing-key'
        });
      }
      const valueJson = this.valueStore.readCommittedValueJson(validation.scriptId, key);
      return JSON.stringify({
        success: true,
        found: valueJson !== undefined,
        valueJson: valueJson ?? ''
      });
    } catch (error) {
      return JSON.stringify({
        success: false,
        error: String((error as Error)?.message ?? error ?? 'value-read-failed')
      });
    }
  }

  private recordDocumentStartLoaderResult(payload: RawUserScriptNativeBridgePayload, tabId: string): string {
    const expectedSecret = this.resolveAutomaticDocumentSignalSecret();
    if (expectedSecret.length === 0 || String(payload.capability ?? '') !== expectedSecret) {
      return '[]';
    }
    const frame = String(payload.frame ?? '') === 'main' ? 'main' : 'sub';
    const rawErrorCategory = String(payload.errorCategory ?? '').trim();
    const allowedErrorCategories = ['none', 'source_read', 'EvalError', 'SyntaxError', 'TypeError', 'Error', 'other'];
    const errorCategory = allowedErrorCategories.includes(rawErrorCategory) ? rawErrorCategory : 'other';
    hilog.info(
      USER_SCRIPT_NATIVE_BRIDGE_LOG_DOMAIN,
      USER_SCRIPT_PERF_DIAGNOSTIC_TAG,
      '[DIAG-userscript-perf-20260828] phase=document_start_loader_result tab=%{public}s frame=%{public}s requested=%{public}d evaluated=%{public}d reports=%{public}d missingReports=%{public}d errors=%{public}d errorCategory=%{public}s',
      tabId,
      frame,
      this.normalizeDocumentStartDiagnosticCount(payload.requestedCount),
      this.normalizeDocumentStartDiagnosticCount(payload.evaluatedCount),
      this.normalizeDocumentStartDiagnosticCount(payload.reportCount),
      this.normalizeDocumentStartDiagnosticCount(payload.missingReportCount),
      this.normalizeDocumentStartDiagnosticCount(payload.errorCount),
      errorCategory
    );
    return '[]';
  }

  private normalizeDocumentStartDiagnosticCount(value: number | undefined): number {
    const normalized = Number(value ?? 0);
    if (!Number.isFinite(normalized)) {
      return 0;
    }
    return Math.max(0, Math.min(9999, Math.floor(normalized)));
  }

  private handleDownloadTaskUpdate(update: UserScriptNativeDownloadTaskUpdate): void {
    const guid = update.guid.trim();
    const requestId = this.downloadRequestIdsByGuid[guid];
    const controller = this.downloadControllersByGuid[guid];
    if (requestId === undefined || controller === undefined) {
      return;
    }
    if (update.status === 'completed') {
      this.dispatchDownloadEvent(controller, requestId, 'load', update.statusText, update);
      this.clearDownloadTracking(guid);
      return;
    }
    if (update.status === 'failed' || update.status === 'canceled' || update.status === 'removed') {
      this.dispatchDownloadEvent(controller, requestId, 'error', update.statusText, update);
      this.clearDownloadTracking(guid);
      return;
    }
    this.dispatchDownloadEvent(controller, requestId, 'progress', update.statusText, update);
  }

  handleDownloadTaskSnapshots(tasks: DownloadV2TaskEntity[]): void {
    tasks.forEach((task: DownloadV2TaskEntity) => {
      this.handleDownloadTaskUpdate({
        guid: task.guid,
        status: task.status,
        downloadedSize: task.progress.receivedBytes,
        totalSize: task.progress.totalBytes,
        statusText: task.failure.code === 'none' ? task.status : task.failure.code
      });
    });
  }

  registerScriptToken(scriptId: string): string {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0) {
      return '';
    }
    const existingToken = this.activeTokenByScriptId[normalizedScriptId];
    if (existingToken !== undefined) {
      const existingRecord = this.tokenRecords[existingToken];
      if (existingRecord !== undefined) {
        return existingToken;
      }
      this.activeTokenByScriptId[normalizedScriptId] = undefined;
    }
    const tokenSecret = this.createTokenSecret();
    if (tokenSecret.length === 0) {
      return '';
    }
    const token = `${normalizedScriptId}-${Date.now()}-${tokenSecret}`;
    this.tokenRecords[token] = {
      scriptId: normalizedScriptId,
      token: token
    };
    this.activeTokenByScriptId[normalizedScriptId] = token;
    return token;
  }

  handleRequest(payloadJson: string, controller: webview.WebviewController, tabId: string, currentUrl: string): void {
    const payload = this.parsePayload(payloadJson);
    if (this.handleAutomaticDocumentSignal(payload, tabId, currentUrl)) {
      return;
    }
    const route = this.resolveRoute(payload);
    if (route === undefined) {
      return;
    }
    if (route.executor === 'xml_http_request') {
      this.handleXmlHttpRequest(payload, payloadJson, controller, currentUrl, route);
    } else if (route.executor === 'download') {
      this.handleDownload(payload, controller, currentUrl, route);
    } else if (route.executor === 'notification') {
      this.handleNotification(payload, controller, currentUrl, route);
    } else if (route.executor === 'media_sniff') {
      this.handleSniffMedia(payload, tabId, currentUrl, route);
    } else if (route.executor === 'tab_get' || route.executor === 'tab_save' || route.executor === 'tabs_get') {
      this.handleTabStorage(payload, controller, tabId, currentUrl, route);
    } else if (route.executor === 'value_read') {
      void this.handleValueRead(payload, controller, currentUrl, route);
    } else if (route.executor === 'value_list') {
      void this.handleValueList(payload, controller, currentUrl, route);
    } else if (route.executor === 'value_set') {
      this.handleValueMutation(payload, controller, currentUrl, route, 'set');
    } else if (route.executor === 'value_delete') {
      this.handleValueMutation(payload, controller, currentUrl, route, 'delete');
    } else if (route.executor === 'values_delete') {
      this.handleDeleteValues(payload, controller, currentUrl, route);
    } else if (route.executor === 'clipboard') {
      this.handleSetClipboard(payload, currentUrl, route);
    }
  }

  handleOpenInTab(payloadJson: string, tabId: string, currentUrl: string): void {
    const payload = this.parsePayload(payloadJson);
    const route = this.resolveRoute(payload);
    if (route === undefined || route.executor !== 'open_in_tab') {
      return;
    }
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      return;
    }
    const targetUrl = String(payload.url ?? '').trim();
    if (targetUrl.length === 0) {
      return;
    }
    const openAfterPendingCommit = (): void => {
      this.host.openInTab(tabId, targetUrl, payload.active !== false);
    };
    this.valueStore.synchronizeCommands(validation.scriptId)
      .then(() => openAfterPendingCommit())
      .catch((_error: Error) => openAfterPendingCommit());
  }

  handleAbort(payloadJson: string, currentUrl: string): void {
    const payload = this.parsePayload(payloadJson);
    const route = this.resolveRoute(payload);
    if (route === undefined || route.executor !== 'xml_http_request') {
      return;
    }
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok) {
      return;
    }
    this.xmlHttpRequestService.abort(String(payload.id ?? '').trim());
  }

  private handleXmlHttpRequest(
    payload: RawUserScriptNativeBridgePayload,
    payloadJson: string,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchXmlHttpFailure(controller, payload, validation.message);
      return;
    }
    this.xmlHttpRequestService.request(payloadJson, controller);
  }

  private handleDownload(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchDownloadPayloadEvent(controller, payload, 'error', validation.message);
      return;
    }
    const request = this.downloadService.buildRequest(payload, currentUrl);
    const downloadRequest: ManualDownloadRequestInput | undefined = request === undefined ? undefined : {
      url: request.url,
      suggestedFileName: request.name.length > 0 ? request.name : undefined,
      totalBytes: 0,
      referer: request.sourcePageUrl,
      headers: request.headers
    };
    const guid = downloadRequest === undefined ? '' : this.host.requestDownload(downloadRequest);
    if (request === undefined || guid.length <= 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        'download-request-failed',
        validation.scriptId
      );
      this.dispatchDownloadPayloadEvent(controller, payload, 'error', 'download-request-failed');
      return;
    }
    this.trackDownloadRequest(guid, String(payload.id ?? '').trim(), controller);
  }

  private handleTabStorage(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    tabId: string,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchTabStorageEvent(controller, payload, false, this.createEmptyTabStorageResult(), validation.message);
      return;
    }
    if (route.executor === 'tab_save') {
      this.tabStorageService.saveTab(validation.scriptId, tabId, payload.tab);
      this.dispatchTabStorageEvent(controller, payload, true, this.createEmptyTabStorageResult());
      return;
    }
    if (route.executor === 'tabs_get') {
      this.dispatchTabStorageEvent(controller, payload, true, this.tabStorageService.getTabs(validation.scriptId));
      return;
    }
    this.dispatchTabStorageEvent(controller, payload, true, this.tabStorageService.getTab(validation.scriptId, tabId));
  }

  private handleNotification(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchNotificationDone(controller, payload);
      return;
    }
    const title = String(payload.title ?? '').trim();
    const text = String(payload.text ?? '').trim();
    const message = title.length > 0 && text.length > 0 ? `${title}：${text}` : (text.length > 0 ? text : title);
    if (message.length > 0) {
      this.host.showMessage(message);
    }
    this.dispatchNotificationDone(controller, payload);
  }

  private handleSniffMedia(
    payload: RawUserScriptNativeBridgePayload,
    tabId: string,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      return;
    }
    this.host.runMediaSniff(tabId, currentUrl);
  }

  private async handleValueRead(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): Promise<void> {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchValueEvent(controller, payload, false, validation.message);
      return;
    }
    const key = String(payload.key ?? '').trim();
    if (key.length === 0) {
      this.dispatchValueEvent(controller, payload, false, 'missing-key');
      return;
    }
    try {
      const valueJson = this.valueStore.readCommittedValueJson(validation.scriptId, key);
      this.dispatchValueEvent(controller, payload, true, '', valueJson !== undefined, valueJson ?? '');
    } catch (error) {
      this.dispatchValueEvent(
        controller,
        payload,
        false,
        String((error as Error)?.message ?? error ?? 'value-read-failed')
      );
    }
  }

  private async handleValueList(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): Promise<void> {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchValueEvent(controller, payload, false, validation.message);
      return;
    }
    try {
      const keys = this.valueStore.readCommittedKeys(validation.scriptId);
      this.dispatchValueEvent(controller, payload, true, '', true, JSON.stringify(keys));
    } catch (error) {
      this.dispatchValueEvent(
        controller,
        payload,
        false,
        String((error as Error)?.message ?? error ?? 'value-list-failed')
      );
    }
  }

  private handleValueMutation(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute,
    operation: 'set' | 'delete'
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchValueEvent(controller, payload, false, validation.message);
      return;
    }
    const key = String(payload.key ?? '').trim();
    if (key.length === 0) {
      this.dispatchValueEvent(controller, payload, false, 'missing-key');
      return;
    }
    const mutation: UserScriptValueMutation = {
      operation: operation,
      key: key,
      valueJson: operation === 'set' ? this.resolveValuePayloadJson(payload) : ''
    };
    this.commitValueMutations(validation.scriptId, [mutation], controller, payload);
  }

  private handleDeleteValues(
    payload: RawUserScriptNativeBridgePayload,
    controller: webview.WebviewController,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      this.dispatchValueEvent(controller, payload, false, validation.message);
      return;
    }
    const mutations = this.normalizeInlineMutations(payload.mutations)
      .filter((mutation: UserScriptValueMutation) => mutation.operation === 'delete');
    if (mutations.length === 0) {
      this.dispatchValueEvent(controller, payload, true);
      return;
    }
    this.commitValueMutations(validation.scriptId, mutations, controller, payload);
  }

  private commitValueMutations(
    scriptId: string,
    mutations: UserScriptValueMutation[],
    controller: webview.WebviewController,
    payload: RawUserScriptNativeBridgePayload
  ): void {
    void this.valueStore.commitMutations(scriptId, mutations)
      .then((result: UserScriptValueCommitResult): void => {
        this.dispatchValueEvent(controller, payload, true, '', false, '', result);
      })
      .catch((error: Error) => {
        this.presentValueIncidentIfNeeded(error);
        this.dispatchValueEvent(controller, payload, false, this.resolveValuePublicError(error));
      });
  }

  private handleSetClipboard(
    payload: RawUserScriptNativeBridgePayload,
    currentUrl: string,
    route: UserScriptNativeBridgeRoute
  ): void {
    const validation = this.permissionCoordinator.validate(payload, currentUrl, route, this.tokenRecords);
    if (!validation.ok || validation.scriptId.length === 0) {
      this.permissionCoordinator.recordBridgeRejected(
        payload,
        currentUrl,
        route.capability,
        validation.message,
        validation.scriptId
      );
      return;
    }
    const text = String(payload.text ?? '');
    this.clipboardService.setText(text)
      .catch((_error: Error) => {
        this.permissionCoordinator.recordBridgeRejected(
          payload,
          currentUrl,
          route.capability,
          'clipboard-write-failed',
          validation.scriptId
        );
      });
  }

  private normalizeInlineMutations(mutations: UserScriptValueMutation[] | undefined): UserScriptValueMutation[] {
    if (!Array.isArray(mutations)) {
      return [];
    }
    const results: UserScriptValueMutation[] = [];
    mutations.forEach((mutation: UserScriptValueMutation) => {
      const operation = mutation.operation === 'delete' ? 'delete' : 'set';
      const key = String(mutation.key ?? '').trim();
      const valueJson = String(mutation.valueJson ?? '');
      if (key.length <= 0) {
        return;
      }
      results.push({
        operation: operation,
        key: key,
        valueJson: valueJson
      });
    });
    return results;
  }

  private resolveValuePayloadJson(payload: RawUserScriptNativeBridgePayload): string {
    if (payload.valueJson !== undefined) {
      return String(payload.valueJson ?? '');
    }
    if (payload.val !== undefined) {
      return JSON.stringify(payload.val);
    }
    return '';
  }

  private dispatchXmlHttpFailure(
    controller: webview.WebviewController,
    payload: RawUserScriptNativeBridgePayload,
    message: string
  ): void {
    this.xmlHttpRequestService.dispatchFailure(
      controller,
      String(payload.id ?? '').trim(),
      String(payload.url ?? '').trim(),
      String(payload.responseType ?? '').trim(),
      message
    );
  }

  private dispatchDownloadPayloadEvent(
    controller: webview.WebviewController,
    payload: RawUserScriptNativeBridgePayload,
    type: 'load' | 'error' | 'progress',
    message: string = ''
  ): void {
    const requestId = String(payload.id ?? '').trim();
    this.dispatchDownloadEvent(controller, requestId, type, message);
  }

  private dispatchDownloadEvent(
    controller: webview.WebviewController,
    requestId: string,
    type: 'load' | 'error' | 'progress',
    message: string = '',
    update?: UserScriptNativeDownloadTaskUpdate
  ): void {
    if (requestId.length === 0) {
      return;
    }
    void controller.runJavaScript(this.downloadService.buildDispatchScript(requestId, type, message, update));
  }

  private trackDownloadRequest(guid: string, requestId: string, controller: webview.WebviewController): void {
    const normalizedGuid = guid.trim();
    const normalizedRequestId = requestId.trim();
    if (normalizedGuid.length === 0 || normalizedRequestId.length === 0) {
      return;
    }
    this.downloadRequestIdsByGuid[normalizedGuid] = normalizedRequestId;
    this.downloadControllersByGuid[normalizedGuid] = controller;
  }

  private clearDownloadTracking(guid: string): void {
    const normalizedGuid = guid.trim();
    if (normalizedGuid.length === 0) {
      return;
    }
    this.downloadRequestIdsByGuid[normalizedGuid] = undefined;
    this.downloadControllersByGuid[normalizedGuid] = undefined;
  }

  private dispatchTabStorageEvent(
    controller: webview.WebviewController,
    payload: RawUserScriptNativeBridgePayload,
    success: boolean,
    value: Object,
    message: string = ''
  ): void {
    const requestId = String(payload.id ?? '').trim();
    if (requestId.length === 0) {
      return;
    }
    const eventLiteral = JSON.stringify({
      id: requestId,
      success: success,
      value: value,
      error: message
    });
    const source = `
;(function airaUserScriptTabStorageDispatch() {
  if (typeof window.__airaUserScriptTabStorageDispatch === 'function') {
    window.__airaUserScriptTabStorageDispatch(${eventLiteral});
  }
})();
`;
    void controller.runJavaScript(source);
  }

  private dispatchNotificationDone(controller: webview.WebviewController, payload: RawUserScriptNativeBridgePayload): void {
    const requestId = String(payload.id ?? '').trim();
    if (requestId.length === 0) {
      return;
    }
    const eventLiteral = JSON.stringify({
      id: requestId
    });
    const source = `
;(function airaUserScriptNotificationDispatch() {
  if (typeof window.__airaUserScriptNotificationDispatch === 'function') {
    window.__airaUserScriptNotificationDispatch(${eventLiteral});
  }
})();
`;
    void controller.runJavaScript(source);
  }

  private dispatchValueEvent(
    controller: webview.WebviewController,
    payload: RawUserScriptNativeBridgePayload,
    success: boolean,
    message: string = '',
    found: boolean = false,
    valueJson: string = '',
    commit?: UserScriptValueCommitResult
  ): void {
    const requestId = String(payload.id ?? '').trim();
    if (requestId.length === 0) {
      return;
    }
    const eventLiteral = JSON.stringify({
      id: requestId,
      success: success,
      error: message,
      found: found,
      valueJson: valueJson,
      commit: commit
    });
    const source = `
;(function airaUserScriptValueDispatch() {
  if (typeof window.__airaUserScriptValueDispatch === 'function') {
    window.__airaUserScriptValueDispatch(${eventLiteral});
  }
})();
`;
    void controller.runJavaScript(source);
  }

  private presentValueIncidentIfNeeded(error: Error): void {
    if (!(error instanceof UserScriptValueStateError) || error.incidentId <= 0 ||
      this.warnedValueIncidentId === error.incidentId) {
      return;
    }
    this.warnedValueIncidentId = error.incidentId;
    this.host.showMessage('用户脚本数据暂时未保存，可前往用户脚本管理查看状态。');
  }

  private resolveValuePublicError(error: Error): string {
    if (error instanceof UserScriptValueStateError) {
      return error.publicCode;
    }
    return 'userscript-value-persist-failed';
  }

  private createEmptyTabStorageResult(): Record<string, Object | string | number | boolean | null> {
    const result: Record<string, Object | string | number | boolean | null> = {};
    return result;
  }

  private resolveRoute(payload: RawUserScriptNativeBridgePayload): UserScriptNativeBridgeRoute | undefined {
    return this.capabilityContract.resolveNativeRoute(
      String(payload.kind ?? '').trim(),
      String(payload.capability ?? '').trim()
    );
  }

  private handleAutomaticDocumentSignal(
    payload: RawUserScriptNativeBridgePayload,
    tabId: string,
    currentUrl: string
  ): boolean {
    if (String(payload.kind ?? '').trim() !== '__aira_internal_document_lifecycle') {
      return false;
    }
    const expectedSecret = this.resolveAutomaticDocumentSignalSecret();
    if (expectedSecret.length === 0 || String(payload.capability ?? '') !== expectedSecret) {
      return true;
    }
    const documentToken = String(payload.token ?? '').trim();
    const phase = String(payload.name ?? '').trim();
    if (documentToken.length === 0 ||
      (phase !== 'document_start' && phase !== 'document_end' && phase !== 'post_paint')) {
      return true;
    }
    const pageUrl = String(payload.url ?? '').trim();
    this.automaticDocumentSignalListener?.({
      tabId: tabId,
      documentToken: documentToken,
      pageUrl: pageUrl.length > 0 ? pageUrl : currentUrl,
      phase: phase as UserScriptAutomaticDocumentSignalPhase
    });
    return true;
  }

  private parsePayload(payloadJson: string): RawUserScriptNativeBridgePayload {
    try {
      return JSON.parse(payloadJson) as RawUserScriptNativeBridgePayload;
    } catch (_error) {
      return {
        kind: '',
        id: '',
        scriptId: '',
        token: '',
        capability: '',
        url: '',
        responseType: '',
        key: '',
        valueJson: ''
      };
    }
  }


  private createTokenSecret(): string {
    try {
      return this.toHex(this.readBlobData(cryptoFramework.createRandom().generateRandomSync(24)));
    } catch (_error) {
      return '';
    }
  }

  private toHex(bytes: Uint8Array): string {
    let result = '';
    for (let index = 0; index < bytes.length; index += 1) {
      result += bytes[index].toString(16).padStart(2, '0');
    }
    return result;
  }

  private readBlobData(blob: Object | null): Uint8Array {
    if (blob === null || blob === undefined) {
      return new Uint8Array();
    }
    const data = (blob as cryptoFramework.DataBlob).data;
    return data === null || data === undefined ? new Uint8Array() : data;
  }
}

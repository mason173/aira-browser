import {
  BrowserDataScope,
  BrowserResolvedThemeMode,
  SearchEngineId,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import {
  CUSTOM_HOMEPAGE_SETTINGS_ROUTE,
  DOWNLOAD_SETTINGS_ROUTE,
  GENERAL_HISTORY_RETENTION_SETTINGS_ROUTE,
  GENERAL_PRIVATE_TABS_SETTINGS_ROUTE,
  GENERAL_STARTUP_SETTINGS_ROUTE,
  KEYBOARD_SHORTCUTS_SETTINGS_ROUTE,
  PASSWORD_SETTINGS_ROUTE,
  SITE_CONTROLS_MANAGEMENT_ROUTE,
  THEME_PALETTE_SETTINGS_ROUTE,
  USER_AGENT_SETTINGS_ROUTE,
  WEBPAGE_TRANSLATION_SETTINGS_ROUTE
} from '../../app/router/AppRoutes';
import { BrowserShellRouteCoordinator } from '../browser/BrowserShellRouteCoordinator';
import { SearchEngineRoutingMode } from '../../services/search/SearchEngineRoutingService';
import {
  SEARCH_ENGINE_NOT_AVAILABLE_ERROR,
  SearchEngineSelectionCoordinator,
  SearchEngineSelectionSnapshot
} from '../search/SearchEngineSelectionCoordinator';
import {
  CustomHomepageBridgeService,
  CustomHomepagePrivacyState,
  CustomHomepageShortcutIconItem,
  CustomHomepageSearchRequest,
  CustomHomepageSearchEngineRequest,
  CustomHomepageSearchEngineRequestResult,
  CustomHomepageSearchEngineState,
  CustomHomepageHoldingHandStatus,
  CustomHomepageStorageOperation,
  CustomHomepageStorageRequest,
  CustomHomepageStorageRequestResult,
  CustomHomepageThemeState
} from '../../services/customhome/CustomHomepageBridgeService';
import {
  CustomHomepageValueRepository,
  sharedCustomHomepageValueRepository
} from '../../data/customhome/CustomHomepageValueRepository';
import {
  isHomeSystemShortcut,
  resolveHomeSystemShortcutTargetValue
} from '../../services/shortcuts/HomeSystemShortcutCatalog';
import { HomeShortcutStateCoordinator } from '../shortcuts/HomeShortcutStateCoordinator';
import { HomeShortcutActionDispatchResult } from '../../features/newtab/HomeShortcutTypes';
import {
  CustomHomepageSystemEntryTarget,
  resolveCustomHomepageDirectSystemAction,
  resolveCustomHomepageSystemEntry
} from '../../services/customhome/CustomHomepageSystemEntryCatalog';
import { hilog } from '@kit.PerformanceAnalysisKit';

const FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN: number = 0x0000;
const FAVICON_COLDSTART_DIAGNOSTIC_TAG: string = 'CustomHomeFaviconDiag';

export type CustomHomepageBridgeSyncKind =
  'document_ready' |
  'shortcuts' |
  'theme' |
  'privacy' |
  'holding_hand' |
  'search_engines';

export interface CustomHomepageBridgeSyncSnapshot {
  shouldSync: boolean;
  documentGeneration: number;
  dataScope: BrowserDataScope;
  shortcuts: ShortcutRecord[];
  icons: CustomHomepageShortcutIconItem[];
  theme: CustomHomepageThemeState;
  privacy: CustomHomepagePrivacyState;
  motionAllowed: boolean;
  holdingHandStatus: CustomHomepageHoldingHandStatus;
}

interface CustomHomepageApplySearchEngineSnapshotAction {
  type: 'apply_search_engine_snapshot';
  snapshot: SearchEngineSelectionSnapshot;
}

interface CustomHomepageExecuteScriptAction {
  type: 'execute_script';
  script: string;
  documentGeneration: number;
}

interface CustomHomepageOpenTabsOverviewAction {
  type: 'open_tabs_overview';
}

interface CustomHomepageOpenSearchAction {
  type: 'open_search';
  documentGeneration: number;
}

interface CustomHomepageOpenToolbarAction {
  type: 'open_toolbar';
  documentGeneration: number;
}

interface CustomHomepageOpenNovelBookshelfAction {
  type: 'open_novel_bookshelf';
  documentGeneration: number;
}

interface CustomHomepageTogglePrivateModeAction {
  type: 'toggle_private_mode';
  documentGeneration: number;
}

interface CustomHomepageScanQrAction {
  type: 'scan_qr';
}

interface CustomHomepageSyncThemeAction {
  type: 'sync_theme';
  documentGeneration: number;
}

interface CustomHomepageSyncPrivacyAction {
  type: 'sync_privacy';
  documentGeneration: number;
}

interface CustomHomepageSetBackHandlerActiveAction {
  type: 'set_back_handler_active';
  active: boolean;
}

interface CustomHomepageOpenUrlAction {
  type: 'open_url';
  url: string;
}

interface CustomHomepageSubmitSearchAction {
  type: 'submit_search';
  rawInput: string;
  searchEngineId: SearchEngineId;
  routingMode: SearchEngineRoutingMode;
}

interface CustomHomepageSyncShortcutsAction {
  type: 'sync_shortcuts';
  documentGeneration: number;
}

interface CustomHomepageOpenShortcutPickerAction {
  type: 'open_shortcut_picker';
}

interface CustomHomepageShowMessageAction {
  type: 'show_message';
  message: string;
}

export type CustomHomepageBridgeShellAction =
  CustomHomepageApplySearchEngineSnapshotAction |
  CustomHomepageExecuteScriptAction |
  CustomHomepageOpenTabsOverviewAction |
  CustomHomepageOpenSearchAction |
  CustomHomepageOpenToolbarAction |
  CustomHomepageOpenNovelBookshelfAction |
  CustomHomepageTogglePrivateModeAction |
  CustomHomepageScanQrAction |
  CustomHomepageSyncThemeAction |
  CustomHomepageSyncPrivacyAction |
  CustomHomepageSetBackHandlerActiveAction |
  CustomHomepageOpenUrlAction |
  CustomHomepageSubmitSearchAction |
  CustomHomepageSyncShortcutsAction |
  CustomHomepageOpenShortcutPickerAction |
  CustomHomepageShowMessageAction;

export interface CustomHomepageBridgeShellExecutor {
  execute: (action: CustomHomepageBridgeShellAction) => void;
}

interface CustomHomepageBridgeCoordinatorOptions {
  selectionCoordinator: SearchEngineSelectionCoordinator;
  bridgeService: CustomHomepageBridgeService;
  routeCoordinator: BrowserShellRouteCoordinator;
  shortcutStateCoordinator: HomeShortcutStateCoordinator;
  shellExecutor: CustomHomepageBridgeShellExecutor;
  valueRepository?: CustomHomepageValueRepository;
}

interface CustomHomepageBridgeRequestInput {
  documentGeneration: number;
  action: string;
  value: string;
  dataScope: BrowserDataScope;
  bridgeAuthorityActive: boolean;
  installedHomepageId: string;
  shortcuts: ShortcutRecord[];
}

export class CustomHomepageBridgeCoordinator {
  private selectionCoordinator: SearchEngineSelectionCoordinator;
  private bridgeService: CustomHomepageBridgeService;
  private routeCoordinator: BrowserShellRouteCoordinator;
  private shortcutStateCoordinator: HomeShortcutStateCoordinator;
  private shellExecutor: CustomHomepageBridgeShellExecutor;
  private valueRepository: CustomHomepageValueRepository;
  private shortcutIconItems: CustomHomepageShortcutIconItem[] = [];
  private shortcutSyncGeneration: number = 0;

  constructor(options: CustomHomepageBridgeCoordinatorOptions) {
    this.selectionCoordinator = options.selectionCoordinator;
    this.bridgeService = options.bridgeService;
    this.routeCoordinator = options.routeCoordinator;
    this.shortcutStateCoordinator = options.shortcutStateCoordinator;
    this.shellExecutor = options.shellExecutor;
    this.valueRepository = options.valueRepository ?? sharedCustomHomepageValueRepository;
  }

  sync(kind: CustomHomepageBridgeSyncKind, snapshot: CustomHomepageBridgeSyncSnapshot): void {
    if (!snapshot.shouldSync || snapshot.documentGeneration <= 0) {
      hilog.info(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] bridge_sync_skipped kind=%{public}s shouldSync=%{public}s documentGeneration=%{public}d',
        kind,
        `${snapshot.shouldSync}`,
        snapshot.documentGeneration
      );
      return;
    }
    hilog.info(
      FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
      FAVICON_COLDSTART_DIAGNOSTIC_TAG,
      '[DEBUG-FAVICON-COLDSTART] bridge_sync_start kind=%{public}s documentGeneration=%{public}d shortcuts=%{public}d icons=%{public}d',
      kind,
      snapshot.documentGeneration,
      snapshot.shortcuts.length,
      snapshot.icons.length
    );
    switch (kind) {
      case 'document_ready':
        this.syncPrivacyToWeb(snapshot);
        this.syncThemeToWeb(snapshot);
        this.syncSearchEnginesToWeb(snapshot.dataScope, snapshot.documentGeneration);
        this.syncHoldingHandToWeb(snapshot);
        return;
      case 'shortcuts':
        this.syncShortcutsToWeb(
          snapshot.shortcuts,
          snapshot.icons,
          snapshot.theme.effectiveMode,
          snapshot.documentGeneration
        );
        return;
      case 'theme':
        this.syncThemeToWeb(snapshot);
        return;
      case 'privacy':
        this.syncPrivacyToWeb(snapshot);
        return;
      case 'holding_hand':
        this.syncHoldingHandToWeb(snapshot);
        return;
      case 'search_engines':
        this.syncSearchEnginesToWeb(snapshot.dataScope, snapshot.documentGeneration);
        return;
    }
  }

  handleRequest(input: CustomHomepageBridgeRequestInput): string {
    const action = input.action.trim().toLowerCase();
    const value = input.value.trim();
    if (!input.bridgeAuthorityActive) {
      return '';
    }
    if (action === 'iconfont') {
      return this.bridgeService.resolveOperationalIconFontBase64();
    }
    const storageOperation = this.resolveStorageOperation(action);
    if (storageOperation !== undefined) {
      return this.handleStorageRequest(
        storageOperation,
        value,
        input.installedHomepageId,
        input.documentGeneration
      );
    }
    if (this.openDirectSystemAction(action, input.documentGeneration)) {
      return 'ok';
    }
    if (action === 'opentoolbar') {
      this.shellExecutor.execute({
        type: 'open_toolbar',
        documentGeneration: input.documentGeneration
      });
      return 'ok';
    }
    if (action === 'opennovelbookshelf') {
      this.shellExecutor.execute({
        type: 'open_novel_bookshelf',
        documentGeneration: input.documentGeneration
      });
      return 'ok';
    }
    if (action === 'toggleprivatemode') {
      this.shellExecutor.execute({
        type: 'toggle_private_mode',
        documentGeneration: input.documentGeneration
      });
      return 'ok';
    }
    if (action === 'scanqr') {
      this.shellExecutor.execute({ type: 'scan_qr' });
      return 'ok';
    }
    if (action === 'systementry') {
      return this.openSystemEntry(value) ? 'ok' : '';
    }
    if (action === 'reordershortcuts') {
      return this.handleReorderShortcutsRequest(value, input.documentGeneration);
    }
    if (this.handleShortcutRequest(action, value, input.shortcuts, input.documentGeneration)) {
      return 'ok';
    }
    if (action === 'theme') {
      this.shellExecutor.execute({
        type: 'sync_theme',
        documentGeneration: input.documentGeneration
      });
      return 'ok';
    }
    if (action === 'privacy') {
      this.shellExecutor.execute({
        type: 'sync_privacy',
        documentGeneration: input.documentGeneration
      });
      return 'ok';
    }
    if (action === 'searchengines') {
      this.syncSearchEnginesToWeb(input.dataScope, input.documentGeneration);
      return 'ok';
    }
    if (action === 'setsearchengine') {
      return this.handleSetSearchEngineRequest(value, input.dataScope, input.documentGeneration);
    }
    if (action === 'backhandler') {
      this.shellExecutor.execute({ type: 'set_back_handler_active', active: value === '1' });
      return 'ok';
    }
    if (action === 'search') {
      this.submitSearch(value, input.dataScope);
      return 'ok';
    }
    if (action === 'open') {
      this.shellExecutor.execute({ type: 'open_url', url: value });
      return 'ok';
    }
    return '';
  }

  private syncShortcutsToWeb(
    shortcuts: ShortcutRecord[],
    icons: CustomHomepageShortcutIconItem[],
    effectiveMode: BrowserResolvedThemeMode,
    documentGeneration: number
  ): void {
    const startedAt = Date.now();
    this.shortcutIconItems = this.bridgeService.buildShortcutIconItemsSnapshot(
      shortcuts,
      icons,
      this.shortcutIconItems
    );
    const generation = this.shortcutSyncGeneration + 1;
    this.shortcutSyncGeneration = generation;
    void this.bridgeService.buildShortcutsUpdateScript(
      shortcuts,
      this.shortcutIconItems,
      effectiveMode
    ).then((script: string): void => {
      if (generation !== this.shortcutSyncGeneration) {
        hilog.info(
          FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
          FAVICON_COLDSTART_DIAGNOSTIC_TAG,
          '[DEBUG-FAVICON-COLDSTART] bridge_shortcuts_script_stale syncGeneration=%{public}d durationMs=%{public}d',
          generation,
          Date.now() - startedAt
        );
        return;
      }
      hilog.info(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] bridge_shortcuts_script_ready syncGeneration=%{public}d documentGeneration=%{public}d scriptChars=%{public}d durationMs=%{public}d',
        generation,
        documentGeneration,
        script.length,
        Date.now() - startedAt
      );
      this.shellExecutor.execute({
        type: 'execute_script',
        script: script,
        documentGeneration: documentGeneration
      });
      hilog.info(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] bridge_shortcuts_script_dispatched syncGeneration=%{public}d documentGeneration=%{public}d',
        generation,
        documentGeneration
      );
    }).catch((_error: Error): void => {
      hilog.warn(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] bridge_shortcuts_script_failed syncGeneration=%{public}d durationMs=%{public}d',
        generation,
        Date.now() - startedAt
      );
    });
  }

  private syncThemeToWeb(snapshot: CustomHomepageBridgeSyncSnapshot): void {
    this.shellExecutor.execute({
      type: 'execute_script',
      script: this.bridgeService.buildThemeUpdateScript(snapshot.theme),
      documentGeneration: snapshot.documentGeneration
    });
    this.syncShortcutsToWeb(
      snapshot.shortcuts,
      snapshot.icons,
      snapshot.theme.effectiveMode,
      snapshot.documentGeneration
    );
  }

  private syncPrivacyToWeb(snapshot: CustomHomepageBridgeSyncSnapshot): void {
    this.shellExecutor.execute({
      type: 'execute_script',
      script: this.bridgeService.buildPrivacyUpdateScript(snapshot.privacy),
      documentGeneration: snapshot.documentGeneration
    });
  }

  private syncHoldingHandToWeb(snapshot: CustomHomepageBridgeSyncSnapshot): void {
    if (!snapshot.motionAllowed) {
      return;
    }
    this.shellExecutor.execute({
      type: 'execute_script',
      script: this.bridgeService.buildHoldingHandUpdateScript(snapshot.holdingHandStatus),
      documentGeneration: snapshot.documentGeneration
    });
  }

  private handleShortcutRequest(
    rawAction: string,
    rawValue: string,
    shortcuts: ShortcutRecord[],
    documentGeneration: number
  ): boolean {
    const action = rawAction.trim().toLowerCase();
    const shortcutId = rawValue.trim();
    if (action === 'shortcuts') {
      this.requestShortcutSync(documentGeneration);
      return true;
    }
    if (action === 'openshortcutpicker') {
      this.shellExecutor.execute({ type: 'open_shortcut_picker' });
      return true;
    }
    if (!this.isShortcutItemAction(action)) {
      return false;
    }
    const shortcut = shortcuts.find((item: ShortcutRecord): boolean => item.id === shortcutId);
    if (shortcut === undefined) {
      this.requestShortcutSync(documentGeneration);
      this.showMessage('未找到这个快捷方式。');
      return true;
    }
    if (isHomeSystemShortcut(shortcut) && !this.isAllowedSystemShortcutAction(action)) {
      this.showMessage('系统入口只能打开、移动或从主页移除。');
      return true;
    }
    switch (action) {
      case 'removeshortcut':
      case 'deleteshortcut':
        this.dispatchShortcutAction(
          this.shortcutStateCoordinator.handleUserAction({
            type: 'shortcut_action',
            shortcutId: shortcut.id,
            actionId: 'remove'
          }),
          documentGeneration
        );
        return true;
      case 'openshortcut':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'open'
        });
        return true;
      case 'copyshortcuturl':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'copy_link'
        });
        return true;
      case 'editshortcut':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'edit'
        });
        return true;
      case 'moveshortcutup':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'move_up'
        });
        return true;
      case 'moveshortcutdown':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'move_down'
        });
        return true;
      case 'moveshortcuttotop':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'move_top'
        });
        return true;
      case 'moveshortcuttobottom':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'move_bottom'
        });
        return true;
      case 'confirmdeleteshortcut':
        this.shortcutStateCoordinator.handleUserAction({
          type: 'shortcut_action',
          shortcutId: shortcut.id,
          actionId: 'delete'
        });
        return true;
      default:
        return false;
    }
  }

  private handleReorderShortcutsRequest(
    value: string,
    documentGeneration: number
  ): HomeShortcutActionDispatchResult {
    const orderedShortcutIds = this.bridgeService.parseShortcutReorderRequest(value);
    if (orderedShortcutIds === undefined) {
      return 'invalid_request';
    }
    const result = this.shortcutStateCoordinator.handleUserAction({
      type: 'reorder_shortcuts',
      orderedShortcutIds: orderedShortcutIds
    });
    this.dispatchShortcutAction(result, documentGeneration);
    return result;
  }

  private dispatchShortcutAction(
    result: HomeShortcutActionDispatchResult,
    documentGeneration: number
  ): void {
    if (result === 'invalid_request' || result === 'not_allowed' || result === 'not_found') {
      this.requestShortcutSync(documentGeneration);
    }
  }

  private requestShortcutSync(documentGeneration: number): void {
    this.shellExecutor.execute({ type: 'sync_shortcuts', documentGeneration: documentGeneration });
  }

  private showMessage(message: string): void {
    this.shellExecutor.execute({ type: 'show_message', message: message });
  }

  private syncSearchEnginesToWeb(dataScope: BrowserDataScope, documentGeneration: number): void {
    const snapshot = this.selectionCoordinator.getSnapshot(dataScope);
    this.shellExecutor.execute({ type: 'apply_search_engine_snapshot', snapshot: snapshot });
    void this.buildState(snapshot).then((state: CustomHomepageSearchEngineState): void => {
      this.shellExecutor.execute({
        type: 'execute_script',
        script: this.bridgeService.buildSearchEngineUpdateScript(state),
        documentGeneration: documentGeneration
      });
    });
  }

  private handleSetSearchEngineRequest(
    payloadJson: string,
    dataScope: BrowserDataScope,
    documentGeneration: number
  ): string {
    const request = this.bridgeService.parseSearchEngineRequest(payloadJson);
    if (request === undefined) {
      return 'invalid_request';
    }
    void this.selectionCoordinator.select(request.engineId, dataScope)
      .then((snapshot: SearchEngineSelectionSnapshot): Promise<CustomHomepageSearchEngineState> => {
        this.shellExecutor.execute({ type: 'apply_search_engine_snapshot', snapshot: snapshot });
        return this.buildState(snapshot);
      })
      .then((state: CustomHomepageSearchEngineState): void => {
        this.shellExecutor.execute({
          type: 'execute_script',
          script: this.bridgeService.buildSearchEngineRequestResultScript(this.buildSuccessResult(request, state)),
          documentGeneration: documentGeneration
        });
      })
      .catch((error: Error): void => {
        const snapshot = this.selectionCoordinator.getSnapshot(dataScope);
        this.shellExecutor.execute({ type: 'apply_search_engine_snapshot', snapshot: snapshot });
        void this.buildState(snapshot).then((state: CustomHomepageSearchEngineState): void => {
          this.shellExecutor.execute({
            type: 'execute_script',
            script: this.bridgeService.buildSearchEngineRequestResultScript(
              this.buildFailureResult(request, state, error)
            ),
            documentGeneration: documentGeneration
          });
        });
      });
    return 'accepted';
  }

  private resolveStorageOperation(action: string): CustomHomepageStorageOperation | undefined {
    switch (action) {
      case 'storageget':
        return 'get';
      case 'storageset':
        return 'set';
      case 'storageremove':
        return 'remove';
      case 'storageclear':
        return 'clear';
      default:
        return undefined;
    }
  }

  private handleStorageRequest(
    operation: CustomHomepageStorageOperation,
    payloadJson: string,
    installedHomepageId: string,
    documentGeneration: number
  ): string {
    const request = this.bridgeService.parseStorageRequest(payloadJson, operation);
    const normalizedInstalledId = installedHomepageId.trim();
    if (request === undefined || normalizedInstalledId.length === 0) {
      return 'invalid_request';
    }
    void this.executeStorageRequest(operation, request, normalizedInstalledId)
      .then((result: CustomHomepageStorageRequestResult): void => {
        this.shellExecutor.execute({
          type: 'execute_script',
          script: this.bridgeService.buildStorageRequestResultScript(result),
          documentGeneration: documentGeneration
        });
      })
      .catch((error: Error): void => {
        this.shellExecutor.execute({
          type: 'execute_script',
          script: this.bridgeService.buildStorageRequestResultScript({
            requestId: request.requestId,
            ok: false,
            found: false,
            valueJson: '',
            code: this.resolveStorageErrorCode(error, operation),
            message: operation === 'get' ?
              '主页配置读取失败，请稍后重试。' :
              '主页配置保存失败，请稍后重试。'
          }),
          documentGeneration: documentGeneration
        });
      });
    return 'accepted';
  }

  private async executeStorageRequest(
    operation: CustomHomepageStorageOperation,
    request: CustomHomepageStorageRequest,
    installedHomepageId: string
  ): Promise<CustomHomepageStorageRequestResult> {
    if (operation === 'get') {
      const valueJson = await this.valueRepository.getValueJson(installedHomepageId, request.key);
      return {
        requestId: request.requestId,
        ok: true,
        found: valueJson !== undefined,
        valueJson: valueJson ?? '',
        code: '',
        message: ''
      };
    }
    if (operation === 'set') {
      await this.valueRepository.setValueJson(installedHomepageId, request.key, request.valueJson);
    } else if (operation === 'remove') {
      await this.valueRepository.removeValue(installedHomepageId, request.key);
    } else {
      await this.valueRepository.clearValues(installedHomepageId);
    }
    return {
      requestId: request.requestId,
      ok: true,
      found: false,
      valueJson: '',
      code: '',
      message: ''
    };
  }

  private resolveStorageErrorCode(error: Error, operation: CustomHomepageStorageOperation): string {
    if (error.message.includes('quota') || error.message.includes('too-large') ||
      error.message.includes('too-many-keys')) {
      return 'STORAGE_QUOTA_EXCEEDED';
    }
    if (operation === 'get') {
      return 'STORAGE_READ_FAILED';
    }
    if (error.message.includes('invalid')) {
      return 'INVALID_STORAGE_VALUE';
    }
    return 'STORAGE_WRITE_FAILED';
  }

  private submitSearch(payloadJson: string, dataScope: BrowserDataScope): void {
    const request: CustomHomepageSearchRequest | undefined = this.bridgeService.parseSearchRequest(payloadJson);
    if (request === undefined) {
      return;
    }
    const snapshot = this.selectionCoordinator.getSnapshot(dataScope);
    this.shellExecutor.execute({ type: 'apply_search_engine_snapshot', snapshot: snapshot });
    if (request.engineId.length <= 0) {
      this.shellExecutor.execute({
        type: 'submit_search',
        rawInput: request.query,
        searchEngineId: snapshot.selectedSearchEngineId,
        routingMode: 'configured'
      });
      return;
    }
    const explicitEngineAvailable = snapshot.availableSearchEngines.some((engine): boolean => {
      return engine.id === request.engineId;
    });
    if (!explicitEngineAvailable) {
      return;
    }
    this.shellExecutor.execute({
      type: 'submit_search',
      rawInput: request.query,
      searchEngineId: request.engineId,
      routingMode: 'exact'
    });
  }

  private openDirectSystemAction(rawAction: string, documentGeneration: number): boolean {
    const action = rawAction.trim().toLowerCase();
    const directSystemEntry = resolveCustomHomepageDirectSystemAction(action);
    if (directSystemEntry !== undefined) {
      return this.openResolvedSystemEntry(directSystemEntry);
    }
    switch (action) {
      case 'opensearch':
        this.shellExecutor.execute({
          type: 'open_search',
          documentGeneration: documentGeneration
        });
        return true;
      case 'tabs':
        this.shellExecutor.execute({ type: 'open_tabs_overview' });
        return true;
      default:
        return false;
    }
  }

  private openSystemEntry(rawEntry: string): boolean {
    const entry = resolveCustomHomepageSystemEntry(rawEntry);
    if (entry === undefined) {
      return false;
    }
    return this.openResolvedSystemEntry(entry);
  }

  private openResolvedSystemEntry(entry: CustomHomepageSystemEntryTarget): boolean {
    const routeCoordinator = this.routeCoordinator;
    const homeSystemTarget = resolveHomeSystemShortcutTargetValue(entry);
    if (homeSystemTarget !== undefined) {
      return routeCoordinator.openHomeSystemEntry(homeSystemTarget);
    }
    switch (entry) {
      case 'sync':
        routeCoordinator.openSyncSettingsPage();
        return true;
      case 'aira_pro':
        routeCoordinator.openAiraProPage();
        return true;
      case 'search_settings':
        routeCoordinator.openSearchSettingsPage();
        return true;
      case 'ad_block_settings':
        routeCoordinator.openAdBlockSettingsPage();
        return true;
      case 'site_settings':
        routeCoordinator.openSimpleRoute(SITE_CONTROLS_MANAGEMENT_ROUTE, '打开站点设置失败');
        return true;
      case 'webpage_translation_settings':
        routeCoordinator.openSimpleRoute(WEBPAGE_TRANSLATION_SETTINGS_ROUTE, '打开网页翻译设置失败');
        return true;
      case 'password_settings':
        routeCoordinator.openSimpleRoute(PASSWORD_SETTINGS_ROUTE, '打开密码设置失败');
        return true;
      case 'user_agent_settings':
        routeCoordinator.openSimpleRoute(USER_AGENT_SETTINGS_ROUTE, '打开网页标识设置失败');
        return true;
      case 'download_settings':
        routeCoordinator.openSimpleRoute(DOWNLOAD_SETTINGS_ROUTE, '打开下载设置失败');
        return true;
      case 'custom_homepage_settings':
        routeCoordinator.openSimpleRoute(CUSTOM_HOMEPAGE_SETTINGS_ROUTE, '打开自定义主页设置失败');
        return true;
      case 'general_settings':
        routeCoordinator.openSettingsDetailPage('general');
        return true;
      case 'appearance_settings':
        routeCoordinator.openSettingsDetailPage('appearance_toolbar');
        return true;
      case 'privacy_security_settings':
        routeCoordinator.openSettingsDetailPage('privacy_security');
        return true;
      case 'experiments_settings':
        routeCoordinator.openSettingsDetailPage('experiments');
        return true;
      case 'about_settings':
        routeCoordinator.openSettingsDetailPage('about');
        return true;
      case 'startup_settings':
        routeCoordinator.openSimpleRoute(GENERAL_STARTUP_SETTINGS_ROUTE, '打开启动设置失败');
        return true;
      case 'private_tabs_settings':
        routeCoordinator.openSimpleRoute(GENERAL_PRIVATE_TABS_SETTINGS_ROUTE, '打开隐私标签设置失败');
        return true;
      case 'history_retention_settings':
        routeCoordinator.openSimpleRoute(GENERAL_HISTORY_RETENTION_SETTINGS_ROUTE, '打开历史保留设置失败');
        return true;
      case 'theme_palette_settings':
        routeCoordinator.openSimpleRoute(THEME_PALETTE_SETTINGS_ROUTE, '打开主题配色设置失败');
        return true;
      case 'keyboard_shortcuts_settings':
        routeCoordinator.openSimpleRoute(KEYBOARD_SHORTCUTS_SETTINGS_ROUTE, '打开键盘快捷键设置失败');
        return true;
      case 'app_proxy_settings':
        routeCoordinator.openAppProxySettingsPage();
        return true;
      default:
        return false;
    }
  }

  private async buildState(snapshot: SearchEngineSelectionSnapshot): Promise<CustomHomepageSearchEngineState> {
    return this.bridgeService.buildSearchEngineState(
      snapshot.selectedSearchEngineId,
      snapshot.selectionScope,
      snapshot.availableSearchEngines
    );
  }

  private isShortcutItemAction(action: string): boolean {
    switch (action) {
      case 'removeshortcut':
      case 'deleteshortcut':
      case 'openshortcut':
      case 'copyshortcuturl':
      case 'editshortcut':
      case 'moveshortcutup':
      case 'moveshortcutdown':
      case 'moveshortcuttotop':
      case 'moveshortcuttobottom':
      case 'confirmdeleteshortcut':
        return true;
      default:
        return false;
    }
  }

  private isAllowedSystemShortcutAction(action: string): boolean {
    return action === 'openshortcut' || action === 'removeshortcut' || action === 'deleteshortcut' ||
      action === 'confirmdeleteshortcut' || action === 'moveshortcutup' || action === 'moveshortcutdown' ||
      action === 'moveshortcuttotop' || action === 'moveshortcuttobottom';
  }

  private buildSuccessResult(
    request: CustomHomepageSearchEngineRequest,
    state: CustomHomepageSearchEngineState
  ): CustomHomepageSearchEngineRequestResult {
    return {
      requestId: request.requestId,
      ok: true,
      state: state,
      code: '',
      message: ''
    };
  }

  private buildFailureResult(
    request: CustomHomepageSearchEngineRequest,
    state: CustomHomepageSearchEngineState,
    error: Error
  ): CustomHomepageSearchEngineRequestResult {
    const unavailable = error.message === SEARCH_ENGINE_NOT_AVAILABLE_ERROR;
    return {
      requestId: request.requestId,
      ok: false,
      state: state,
      code: unavailable ? SEARCH_ENGINE_NOT_AVAILABLE_ERROR : 'SEARCH_ENGINE_UPDATE_FAILED',
      message: unavailable ? '这个搜索引擎当前不可用。' : '搜索引擎保存失败，请稍后重试。'
    };
  }
}

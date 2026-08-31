import { webview } from '@kit.ArkWeb';
import {
  TabCrashReason,
  TabDiscardReason,
  TabRestoreReason,
  TabRuntimeState
} from '../../common/models/BrowserModels';

export interface CreateWebTabRuntimeOptions {
  tabId: string;
  windowId: string;
  initialUrl: string;
  initialTitle: string;
  state: TabRuntimeState;
  lastActiveAt?: number;
  pendingUrl?: string;
  snapshotPath?: string;
  snapshotUpdatedAt?: number;
  lastRestoreReason?: TabRestoreReason | '';
  lastDiscardReason?: TabDiscardReason | '';
  lastCrashReason?: TabCrashReason | '';
}

export interface WebTabRuntimeRecord {
  tabId: string;
  windowId: string;
  state: TabRuntimeState;
  controller: webview.WebviewController;
  currentUrl: string;
  pendingUrl: string;
  title: string;
  lastKnownUrl: string;
  lastActiveAt: number;
  snapshotPath: string;
  snapshotUpdatedAt: number;
  hasLiveController: boolean;
  degradedReason: string;
  lastRestoreReason: TabRestoreReason | '';
  lastDiscardReason: TabDiscardReason | '';
  lastCrashReason: TabCrashReason | '';
  windowOpenHandoffPending: boolean;
}

export interface WebTabRuntimePatch {
  state?: TabRuntimeState;
  controller?: webview.WebviewController;
  currentUrl?: string;
  pendingUrl?: string;
  title?: string;
  lastKnownUrl?: string;
  lastActiveAt?: number;
  snapshotPath?: string;
  snapshotUpdatedAt?: number;
  hasLiveController?: boolean;
  degradedReason?: string;
  lastRestoreReason?: TabRestoreReason | '';
  lastDiscardReason?: TabDiscardReason | '';
  lastCrashReason?: TabCrashReason | '';
  windowOpenHandoffPending?: boolean;
}

export type WebTabRuntimeControllerFactory = () => webview.WebviewController;

export class WebTabRuntimeFactory {
  private readonly createController: WebTabRuntimeControllerFactory;

  constructor(createController: WebTabRuntimeControllerFactory = (): webview.WebviewController => {
    return new webview.WebviewController();
  }) {
    this.createController = createController;
  }

  createRuntime(options: CreateWebTabRuntimeOptions): WebTabRuntimeRecord {
    const runtime: WebTabRuntimeRecord = {
      tabId: options.tabId,
      windowId: options.windowId,
      state: options.state,
      controller: this.createController(),
      currentUrl: options.initialUrl,
      pendingUrl: options.pendingUrl ?? options.initialUrl,
      title: options.initialTitle,
      lastKnownUrl: options.initialUrl,
      lastActiveAt: options.lastActiveAt ?? Date.now(),
      snapshotPath: options.snapshotPath ?? '',
      snapshotUpdatedAt: options.snapshotUpdatedAt ?? 0,
      hasLiveController: false,
      degradedReason: '',
      lastRestoreReason: options.lastRestoreReason ?? '',
      lastDiscardReason: options.lastDiscardReason ?? '',
      lastCrashReason: options.lastCrashReason ?? '',
      windowOpenHandoffPending: false
    };
    return runtime;
  }

  patchRuntime(runtime: WebTabRuntimeRecord, patch: WebTabRuntimePatch): WebTabRuntimeRecord {
    const nextRuntime: WebTabRuntimeRecord = {
      tabId: runtime.tabId,
      windowId: runtime.windowId,
      state: patch.state ?? runtime.state,
      controller: patch.controller ?? runtime.controller,
      currentUrl: patch.currentUrl ?? runtime.currentUrl,
      pendingUrl: patch.pendingUrl ?? runtime.pendingUrl,
      title: patch.title ?? runtime.title,
      lastKnownUrl: patch.lastKnownUrl ?? runtime.lastKnownUrl,
      lastActiveAt: patch.lastActiveAt ?? runtime.lastActiveAt,
      snapshotPath: patch.snapshotPath ?? runtime.snapshotPath,
      snapshotUpdatedAt: patch.snapshotUpdatedAt ?? runtime.snapshotUpdatedAt,
      hasLiveController: patch.hasLiveController ?? runtime.hasLiveController,
      degradedReason: patch.degradedReason ?? runtime.degradedReason,
      lastRestoreReason: patch.lastRestoreReason ?? runtime.lastRestoreReason,
      lastDiscardReason: patch.lastDiscardReason ?? runtime.lastDiscardReason,
      lastCrashReason: patch.lastCrashReason ?? runtime.lastCrashReason,
      windowOpenHandoffPending: patch.windowOpenHandoffPending ?? runtime.windowOpenHandoffPending
    };
    return nextRuntime;
  }
}

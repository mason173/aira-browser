import { webview } from '@kit.ArkWeb';
import { TabCrashReason, TabRuntimeState } from '../../common/models/BrowserModels';
import {
  CreateWebTabRuntimeOptions,
  WebTabRuntimeControllerFactory,
  WebTabRuntimeFactory,
  WebTabRuntimePatch,
  WebTabRuntimeRecord
} from '../web/WebTabRuntime';

export interface EnsureTabRuntimeResult {
  runtime: WebTabRuntimeRecord;
  created: boolean;
}

export interface ActivateTabRuntimeResult {
  activeRuntime: WebTabRuntimeRecord;
  backgroundRuntimeIds: string[];
}

export class TabRuntimeRegistry {
  private runtimeFactory: WebTabRuntimeFactory;
  private runtimes: Record<string, WebTabRuntimeRecord> = {};

  constructor(createController?: WebTabRuntimeControllerFactory) {
    this.runtimeFactory = new WebTabRuntimeFactory(createController);
  }

  ensureRuntime(options: CreateWebTabRuntimeOptions): EnsureTabRuntimeResult {
    const existing = this.runtimes[options.tabId];
    if (existing !== undefined) {
      const currentUrl = existing.hasLiveController ? existing.currentUrl : options.initialUrl;
      const pendingUrl = existing.hasLiveController
        ? existing.pendingUrl
        : options.pendingUrl ?? options.initialUrl;
      const refreshed = this.runtimeFactory.patchRuntime(existing, {
        currentUrl: currentUrl,
        pendingUrl: pendingUrl,
        title: options.initialTitle,
        state: options.state,
        lastActiveAt: options.lastActiveAt ?? existing.lastActiveAt,
        snapshotPath: options.snapshotPath ?? existing.snapshotPath,
        snapshotUpdatedAt: options.snapshotUpdatedAt ?? existing.snapshotUpdatedAt,
        lastRestoreReason: options.lastRestoreReason ?? existing.lastRestoreReason,
        lastDiscardReason: options.lastDiscardReason ?? existing.lastDiscardReason,
        lastCrashReason: options.lastCrashReason ?? existing.lastCrashReason
      });
      this.runtimes[options.tabId] = refreshed;
      const result: EnsureTabRuntimeResult = {
        runtime: refreshed,
        created: false
      };
      return result;
    }

    const runtime = this.runtimeFactory.createRuntime(options);
    this.runtimes[options.tabId] = runtime;
    const result: EnsureTabRuntimeResult = {
      runtime: runtime,
      created: true
    };
    return result;
  }

  getRuntime(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimes[tabId];
  }

  listRuntimes(): WebTabRuntimeRecord[] {
    return Object.keys(this.runtimes).map((tabId: string) => this.runtimes[tabId]);
  }

  patchRuntime(tabId: string, patch: WebTabRuntimePatch): WebTabRuntimeRecord | undefined {
    const runtime = this.runtimes[tabId];
    if (runtime === undefined) {
      return undefined;
    }
    const nextRuntime = this.runtimeFactory.patchRuntime(runtime, patch);
    this.runtimes[tabId] = nextRuntime;
    return nextRuntime;
  }

  attachController(tabId: string, controller: webview.WebviewController): WebTabRuntimeRecord | undefined {
    return this.patchRuntime(tabId, {
      controller: controller,
      hasLiveController: true
    });
  }

  replaceControllerForProxyRefresh(
    tabId: string,
    controller: webview.WebviewController
  ): WebTabRuntimeRecord | undefined {
    return this.patchRuntime(tabId, {
      controller: controller,
      hasLiveController: false,
      state: 'restoring',
      degradedReason: ''
    });
  }

  detachController(tabId: string, keepRuntimeRecord: boolean = true): WebTabRuntimeRecord | undefined {
    if (!keepRuntimeRecord) {
      return this.removeRuntime(tabId);
    }
    return this.patchRuntime(tabId, {
      hasLiveController: false,
      state: 'cold',
      lastDiscardReason: 'controller_detached'
    });
  }

  markControllerAttached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.patchRuntime(tabId, {
      hasLiveController: true
    });
  }

  markWindowOpenHandoffPending(tabId: string): WebTabRuntimeRecord | undefined {
    return this.patchRuntime(tabId, {
      windowOpenHandoffPending: true
    });
  }

  consumeWindowOpenHandoffPending(tabId: string): boolean {
    const runtime = this.runtimes[tabId];
    if (runtime === undefined || !runtime.windowOpenHandoffPending) {
      return false;
    }
    this.runtimes[tabId] = this.runtimeFactory.patchRuntime(runtime, {
      windowOpenHandoffPending: false
    });
    return true;
  }

  markRuntimeCrashed(
    tabId: string,
    degradedReason: string = '',
    crashReason: TabCrashReason = 'unknown'
  ): WebTabRuntimeRecord | undefined {
    return this.patchRuntime(tabId, {
      state: 'crashed',
      hasLiveController: false,
      degradedReason: degradedReason,
      lastCrashReason: crashReason
    });
  }

  rememberLastKnownUrl(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    const trimmedUrl = url.trim();
    if (trimmedUrl.length === 0) {
      return this.getRuntime(tabId);
    }
    return this.patchRuntime(tabId, {
      currentUrl: trimmedUrl,
      pendingUrl: trimmedUrl,
      lastKnownUrl: trimmedUrl
    });
  }

  rememberProvisionalUrl(tabId: string, url: string): WebTabRuntimeRecord | undefined {
    const trimmedUrl = url.trim();
    if (trimmedUrl.length === 0) {
      return this.getRuntime(tabId);
    }
    return this.patchRuntime(tabId, {
      pendingUrl: trimmedUrl
    });
  }

  activateRuntime(tabId: string, lastActiveAt: number = Date.now()): ActivateTabRuntimeResult | undefined {
    const activeRuntime = this.runtimes[tabId];
    if (activeRuntime === undefined) {
      return undefined;
    }

    const backgroundRuntimeIds: string[] = [];
    Object.keys(this.runtimes).forEach((runtimeTabId: string) => {
      const runtime = this.runtimes[runtimeTabId];
      if (runtimeTabId === tabId) {
        this.runtimes[runtimeTabId] = this.runtimeFactory.patchRuntime(runtime, {
          state: 'active',
          lastActiveAt: lastActiveAt
        });
        return;
      }

      const nextState: TabRuntimeState = runtime.hasLiveController ? 'background-hot' : 'cold';
      this.runtimes[runtimeTabId] = this.runtimeFactory.patchRuntime(runtime, {
        state: nextState
      });
      backgroundRuntimeIds.push(runtimeTabId);
    });

    const result: ActivateTabRuntimeResult = {
      activeRuntime: this.runtimes[tabId],
      backgroundRuntimeIds: backgroundRuntimeIds
    };
    return result;
  }

  removeRuntime(tabId: string): WebTabRuntimeRecord | undefined {
    const runtime = this.runtimes[tabId];
    if (runtime === undefined) {
      return undefined;
    }
    const nextRuntimes: Record<string, WebTabRuntimeRecord> = {};
    Object.keys(this.runtimes).forEach((runtimeTabId: string) => {
      if (runtimeTabId !== tabId) {
        nextRuntimes[runtimeTabId] = this.runtimes[runtimeTabId];
      }
    });
    this.runtimes = nextRuntimes;
    return runtime;
  }

  pruneWindowRuntimes(windowId: string, allowedTabIds: string[]): void {
    const allowed = allowedTabIds.slice();
    const nextRuntimes: Record<string, WebTabRuntimeRecord> = {};
    Object.keys(this.runtimes).forEach((tabId: string) => {
      const runtime = this.runtimes[tabId];
      const shouldKeep = runtime.windowId !== windowId || allowed.includes(tabId);
      if (shouldKeep) {
        nextRuntimes[tabId] = runtime;
      }
    });
    this.runtimes = nextRuntimes;
  }

  listWindowRuntimes(windowId: string): WebTabRuntimeRecord[] {
    return Object.keys(this.runtimes)
      .map((tabId: string) => this.runtimes[tabId])
      .filter((runtime: WebTabRuntimeRecord) => runtime.windowId === windowId);
  }
}

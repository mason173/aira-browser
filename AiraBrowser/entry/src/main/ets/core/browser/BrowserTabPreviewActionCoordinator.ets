import {
  BrowserTabPreviewCaptureRequest,
  BrowserTabPreviewCoordinator
} from './BrowserTabPreviewCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserTabPreviewCaptureSource } from '../../services/web/BrowserTabPreviewTypes';

export interface BrowserTabPreviewActionPort {
  buildRequest: (
    tabId: string,
    force: boolean,
    requireSharedSnapshot: boolean,
    options?: BrowserTabPreviewActionRequestOptions
  ) => BrowserTabPreviewCaptureRequest | undefined;
  previewCoordinator: BrowserTabPreviewCoordinator;
  notifyChanged: () => void;
  recordRuntimeEvent: (event: string, details: string, tabId?: string) => void;
}

export interface BrowserTabPreviewActionRequestOptions {
  componentSnapshotOnly?: boolean;
  captureVisibleTabSurface?: boolean;
}

export interface BrowserTabPreviewExplicitCaptureInput {
  tabId: string;
  force: boolean;
  requireSharedSnapshot: boolean;
  componentSnapshotOnly?: boolean;
  captureVisibleTabSurface?: boolean;
  notifyOnChanged?: boolean;
}

export interface BrowserTabPreviewActiveCaptureInput {
  activeTabId: string;
  showHomePage: boolean;
  force: boolean;
  requireSharedSnapshot: boolean;
  captureVisibleTabSurface?: boolean;
  notifyOnChanged?: boolean;
}

export interface BrowserTabPreviewLifecycleCaptureInput {
  activeTabId: string;
  showHomePage: boolean;
  source: string;
}

export type BrowserTabPreviewOpenerBeforeSwitchSource = 'background_prompt' | 'window_open';

export interface BrowserTabPreviewOpenerBeforeSwitchInput {
  openerTabId: string;
  activeTabId: string;
  showHomePage: boolean;
  targetTabId: string;
  waitMs: number;
  source: BrowserTabPreviewOpenerBeforeSwitchSource;
  // Large-screen shells pass true so the opener thumbnail includes the top
  // chrome; phone shells keep the bare page capture (their existing look).
  captureVisibleTabSurface?: boolean;
}

export interface BrowserTabPreviewSeedFromTabInput {
  sourceTab?: BrowserTabState;
  targetTab?: BrowserTabState;
  source: BrowserTabPreviewCaptureSource;
  reason: string;
  notifyOnChanged?: boolean;
}

export interface BrowserTabPreviewForegroundSeedSourceCaptureInput {
  sourceTabId: string;
  activeTabId: string;
  showHomePage: boolean;
  reason: string;
}

export class BrowserTabPreviewActionCoordinator {
  async captureExplicit(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewExplicitCaptureInput
  ): Promise<boolean> {
    const request = port.buildRequest(input.tabId, input.force, input.requireSharedSnapshot, {
      componentSnapshotOnly: input.componentSnapshotOnly,
      captureVisibleTabSurface: input.captureVisibleTabSurface
    });
    const notifyOnChanged = input.notifyOnChanged ?? true;
    if (request === undefined) {
      port.previewCoordinator.recordMissingCaptureRequest(input.tabId);
      if (notifyOnChanged) {
        port.notifyChanged();
      }
      return false;
    }
    if (!await port.previewCoordinator.capturePreview(request)) {
      return false;
    }
    if (notifyOnChanged) {
      port.notifyChanged();
    }
    return true;
  }

  async captureActiveWeb(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewActiveCaptureInput
  ): Promise<boolean> {
    if (input.showHomePage || input.activeTabId.trim().length <= 0) {
      return false;
    }
    return await this.captureExplicit(port, {
      tabId: input.activeTabId,
      force: input.force,
      requireSharedSnapshot: input.requireSharedSnapshot,
      componentSnapshotOnly: true,
      captureVisibleTabSurface: input.captureVisibleTabSurface,
      notifyOnChanged: input.notifyOnChanged
    });
  }

  captureActiveWebAsync(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewActiveCaptureInput
  ): void {
    void this.captureActiveWeb(port, input);
  }

  async captureForegroundSeedSource(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewForegroundSeedSourceCaptureInput
  ): Promise<boolean> {
    const sourceTabId = input.sourceTabId.trim();
    if (sourceTabId.length <= 0 || sourceTabId !== input.activeTabId || input.showHomePage) {
      port.recordRuntimeEvent(
        'tab_preview_foreground_seed_source_skipped',
        `reason=${input.reason} source=${sourceTabId} active=${input.activeTabId} home=${input.showHomePage}`,
        sourceTabId
      );
      return false;
    }
    const captured = await this.captureActiveWeb(port, {
      activeTabId: input.activeTabId,
      showHomePage: input.showHomePage,
      force: true,
      requireSharedSnapshot: true,
      notifyOnChanged: false
    });
    port.recordRuntimeEvent(
      captured ? 'tab_preview_foreground_seed_source_captured' : 'tab_preview_foreground_seed_source_failed',
      `reason=${input.reason}`,
      sourceTabId
    );
    return captured;
  }

  captureLifecycleExit(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewLifecycleCaptureInput
  ): void {
    const tabId = input.activeTabId;
    if (input.showHomePage || tabId.trim().length <= 0) {
      return;
    }
    void this.captureExplicit(port, {
      tabId: tabId,
      force: true,
      requireSharedSnapshot: true
    })
      .then((captured: boolean) => {
        port.recordRuntimeEvent(
          captured ? 'tab_preview_lifecycle_capture_succeeded' : 'tab_preview_lifecycle_capture_failed',
          `source=${input.source}`,
          tabId
        );
      })
      .catch((error: Error) => {
        port.recordRuntimeEvent(
          'tab_preview_lifecycle_capture_failed',
          `source=${input.source} error=${JSON.stringify(error)}`,
          tabId
        );
      });
  }

  async captureOpenerBeforeSwitch(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewOpenerBeforeSwitchInput
  ): Promise<void> {
    const normalizedOpenerTabId = input.openerTabId.trim();
    if (normalizedOpenerTabId.length <= 0 || normalizedOpenerTabId !== input.activeTabId || input.showHomePage) {
      return;
    }
    let completed = false;
    const captureTask = this.captureExplicit(port, {
      tabId: normalizedOpenerTabId,
      force: true,
      requireSharedSnapshot: true,
      // Large screen only: the opener is still the visible foreground tab, so
      // capture the full shell surface (page + top chrome) to match the
      // open-overview capture. Phone keeps its original bare-page capture.
      captureVisibleTabSurface: input.captureVisibleTabSurface
    })
      .then((captured: boolean) => {
        completed = true;
        port.recordRuntimeEvent(
          captured ? 'tab_preview_opener_before_switch_captured' : 'tab_preview_opener_before_switch_failed',
          `source=${input.source} target=${input.targetTabId}`,
          normalizedOpenerTabId
        );
      })
      .catch((error: Error) => {
        completed = true;
        port.recordRuntimeEvent(
          'tab_preview_opener_before_switch_failed',
          `source=${input.source} target=${input.targetTabId} error=${JSON.stringify(error)}`,
          normalizedOpenerTabId
        );
      });
    await Promise.race([
      captureTask,
      new Promise<void>((resolve) => {
        setTimeout(() => {
          resolve();
        }, input.waitMs);
      })
    ]);
    if (!completed) {
      port.recordRuntimeEvent(
        'tab_preview_opener_before_switch_timeout',
        `source=${input.source} target=${input.targetTabId}`,
        normalizedOpenerTabId
      );
      void captureTask;
    }
  }

  async seedFromTab(
    port: BrowserTabPreviewActionPort,
    input: BrowserTabPreviewSeedFromTabInput
  ): Promise<boolean> {
    const seeded = await port.previewCoordinator.seedSharedSnapshotFromTab(
      input.sourceTab,
      input.targetTab,
      input.source
    );
    port.recordRuntimeEvent(
      seeded ? 'tab_preview_seed_from_tab_succeeded' : 'tab_preview_seed_from_tab_failed',
      `reason=${input.reason} source=${input.sourceTab?.id ?? ''} target=${input.targetTab?.id ?? ''}`,
      input.targetTab?.id ?? input.sourceTab?.id
    );
    if (seeded && (input.notifyOnChanged ?? true)) {
      port.notifyChanged();
    }
    return seeded;
  }
}

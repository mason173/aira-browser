import {
  BrowserTabAppLifecycleState,
  BrowserTabBackgroundTrigger,
  BrowserTabWindowState,
  BrowserTabWindowVisibility
} from './BrowserTabBackgroundTypes';

export interface BrowserTabBackgroundWindowTransitionResult {
  state: BrowserTabWindowState;
  trigger: BrowserTabBackgroundTrigger;
  changed: boolean;
}

export class BrowserTabBackgroundWindowStateCoordinator {
  private appLifecycle: BrowserTabAppLifecycleState = 'foreground';
  private currentWindowId: string = '';
  private visibilityByWindowId: Record<string, BrowserTabWindowVisibility> = {};

  markAppForeground(windowId: string): BrowserTabBackgroundWindowTransitionResult {
    const previous = this.buildWindowState(windowId);
    this.appLifecycle = 'foreground';
    this.currentWindowId = windowId;
    this.visibilityByWindowId[windowId] = 'active';
    return this.buildTransitionResult(previous, this.buildWindowState(windowId), 'app_foreground');
  }

  markAppBackground(windowId: string): BrowserTabBackgroundWindowTransitionResult {
    const previous = this.buildWindowState(windowId);
    this.appLifecycle = 'background';
    this.currentWindowId = windowId;
    this.visibilityByWindowId[windowId] = 'hidden';
    return this.buildTransitionResult(previous, this.buildWindowState(windowId), 'app_background');
  }

  markWindowActive(windowId: string): BrowserTabBackgroundWindowTransitionResult {
    const previous = this.buildWindowState(windowId);
    this.appLifecycle = 'foreground';
    this.currentWindowId = windowId;
    this.visibilityByWindowId[windowId] = 'active';
    return this.buildTransitionResult(previous, this.buildWindowState(windowId), 'window_active');
  }

  markWindowVisible(windowId: string): BrowserTabBackgroundWindowTransitionResult {
    const previous = this.buildWindowState(windowId);
    this.appLifecycle = 'foreground';
    this.currentWindowId = windowId;
    this.visibilityByWindowId[windowId] = 'visible';
    return this.buildTransitionResult(previous, this.buildWindowState(windowId), 'window_active');
  }

  markWindowShowing(windowId: string): BrowserTabBackgroundWindowTransitionResult {
    const previous = this.buildWindowState(windowId);
    this.appLifecycle = 'foreground';
    this.currentWindowId = windowId;
    this.visibilityByWindowId[windowId] = 'showing';
    return this.buildTransitionResult(previous, this.buildWindowState(windowId), 'window_active');
  }

  markWindowHidden(windowId: string): BrowserTabBackgroundWindowTransitionResult {
    const previous = this.buildWindowState(windowId);
    this.visibilityByWindowId[windowId] = 'hidden';
    return this.buildTransitionResult(previous, this.buildWindowState(windowId), 'window_hidden');
  }

  buildWindowState(windowId: string): BrowserTabWindowState {
    const normalizedWindowId = windowId.length > 0 ? windowId : this.currentWindowId;
    const visibility = this.visibilityByWindowId[normalizedWindowId] ??
      (this.appLifecycle === 'background' ? 'hidden' : 'active');
    return {
      windowId: normalizedWindowId,
      visibility: visibility,
      isCurrentWindow: normalizedWindowId === this.currentWindowId || this.currentWindowId.length === 0,
      appLifecycle: this.appLifecycle
    };
  }

  private buildTransitionResult(
    previous: BrowserTabWindowState,
    next: BrowserTabWindowState,
    trigger: BrowserTabBackgroundTrigger
  ): BrowserTabBackgroundWindowTransitionResult {
    return {
      state: next,
      trigger: trigger,
      changed: previous.windowId !== next.windowId ||
        previous.visibility !== next.visibility ||
        previous.isCurrentWindow !== next.isCurrentWindow ||
        previous.appLifecycle !== next.appLifecycle
    };
  }
}

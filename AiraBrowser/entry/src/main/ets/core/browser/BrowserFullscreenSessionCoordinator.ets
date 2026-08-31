import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BrowserScreenOrientationService } from '../../services/browser/BrowserScreenOrientationService';
import { NativeVideoFullscreenWindowService } from '../../services/video/NativeVideoFullscreenWindowService';
import {
  BrowserScreenOrientationMode,
  BrowserScreenOrientationOptionState,
  BrowserScreenOrientationViewModel
} from './BrowserScreenOrientationViewModel';
import {
  BrowserWebFullscreenPresentationCoordinator,
  BrowserWebFullscreenState
} from './BrowserWebFullscreenPresentationCoordinator';
import { BrowserWebPageToolsCoordinator } from './BrowserWebPageToolsCoordinator';

export interface BrowserFullscreenSurfaceFacts {
  context: common.UIAbilityContext;
  activeTabId: string;
  webPageVisible: boolean;
  homePageVisible: boolean;
  tabsSheetVisible: boolean;
  assistantVideoTakeoverActive: boolean;
}

export interface BrowserFullscreenSessionPresentation {
  fullScreenModeEnabled: boolean;
  fullScreenModeActionVersion: number;
  webFullscreenState: BrowserWebFullscreenState;
  screenOrientationMode: BrowserScreenOrientationMode;
  screenOrientationOptions: BrowserScreenOrientationOptionState[];
  screenOrientationActionVersion: number;
}

export type BrowserFullscreenSessionEffectType =
  'capture_restore_insets' |
  'fullscreen_chrome_entered' |
  'fullscreen_chrome_exited' |
  'toast';

export interface BrowserFullscreenSessionEffect {
  type: BrowserFullscreenSessionEffectType;
  source: string;
  message: string;
  restoreInsets: boolean;
}

export interface BrowserFullscreenSessionSink {
  resolveSurfaceFacts: () => BrowserFullscreenSurfaceFacts;
  publishPresentation: (presentation: BrowserFullscreenSessionPresentation) => void;
  applyEffect: (effect: BrowserFullscreenSessionEffect) => void;
}

export interface BrowserVideoAssistantFullscreenRequest {
  tabId: string;
  videoWidth: number;
  videoHeight: number;
}

export type BrowserTemporaryMediaOrientation = 'portrait' | 'landscape';

export class BrowserFullscreenSessionCoordinator {
  private readonly sink: BrowserFullscreenSessionSink;
  private readonly pageToolsCoordinator: BrowserWebPageToolsCoordinator;
  private readonly windowService: NativeVideoFullscreenWindowService;
  private readonly webPresentationCoordinator: BrowserWebFullscreenPresentationCoordinator;
  private readonly orientationService: BrowserScreenOrientationService;
  private readonly orientationViewModel: BrowserScreenOrientationViewModel;
  private presentation: BrowserFullscreenSessionPresentation;
  private transitionGeneration: number = 0;
  private webFullScreenExitHandler: FullScreenExitHandler | undefined = undefined;
  private pendingVideoWebFullscreenTabId: string = '';
  private pendingVideoWebFullscreenRestoreOrientation: window.Orientation | undefined = undefined;
  private pendingVideoWebFullscreenRestorePromise: Promise<window.Orientation> | undefined = undefined;

  constructor(
    sink: BrowserFullscreenSessionSink,
    pageToolsCoordinator: BrowserWebPageToolsCoordinator,
    windowService: NativeVideoFullscreenWindowService = new NativeVideoFullscreenWindowService(),
    webPresentationCoordinator: BrowserWebFullscreenPresentationCoordinator =
      new BrowserWebFullscreenPresentationCoordinator(),
    orientationService: BrowserScreenOrientationService = new BrowserScreenOrientationService(),
    orientationViewModel: BrowserScreenOrientationViewModel = new BrowserScreenOrientationViewModel()
  ) {
    this.sink = sink;
    this.pageToolsCoordinator = pageToolsCoordinator;
    this.windowService = windowService;
    this.webPresentationCoordinator = webPresentationCoordinator;
    this.orientationService = orientationService;
    this.orientationViewModel = orientationViewModel;
    this.presentation = {
      fullScreenModeEnabled: false,
      fullScreenModeActionVersion: 0,
      webFullscreenState: this.webPresentationCoordinator.createInactiveState(),
      screenOrientationMode: 'system',
      screenOrientationOptions: this.orientationViewModel.buildOptions('system'),
      screenOrientationActionVersion: 0
    };
  }

  snapshot(): BrowserFullscreenSessionPresentation {
    return this.presentation;
  }

  cancelOrientationReapply(): void {
    this.windowService.cancelOrientationReapply();
  }

  toggleManualFullscreen(): void {
    if (this.presentation.fullScreenModeEnabled) {
      void this.disableFullscreen(true);
      return;
    }
    const facts = this.sink.resolveSurfaceFacts();
    if (!facts.webPageVisible || facts.tabsSheetVisible || facts.homePageVisible) {
      this.emitEffect('toast', '', '打开网页后可进入全屏模式。');
      return;
    }
    this.transitionGeneration += 1;
    this.publishFullscreenState(true, this.presentation.webFullscreenState);
    this.emitEffect('fullscreen_chrome_entered');
    this.emitEffect('toast', '', '已进入全屏模式，按系统返回键可退出。');
  }

  async disableFullscreen(showToast: boolean): Promise<void> {
    const fullscreenState = this.presentation.webFullscreenState;
    if (this.webPresentationCoordinator.isActiveForSource(fullscreenState, 'web_content')) {
      await this.exitWebContentFullscreen(fullscreenState.tabId, true);
      return;
    }
    if (this.webPresentationCoordinator.isActiveForSource(fullscreenState, 'video_web_fullscreen')) {
      await this.exitVideoAssistantFullscreen(showToast, false);
      return;
    }
    if (this.webPresentationCoordinator.isActiveForSource(fullscreenState, 'video_takeover') ||
      this.sink.resolveSurfaceFacts().assistantVideoTakeoverActive) {
      await this.exitVideoAssistantFullscreen(showToast, false);
      return;
    }
    if (!this.presentation.fullScreenModeEnabled) {
      return;
    }
    this.transitionGeneration += 1;
    this.publishFullscreenState(false, fullscreenState);
    this.emitEffect('fullscreen_chrome_exited', 'fullscreen-mode-exit');
    if (showToast) {
      this.emitEffect('toast', '', '已退出全屏模式。');
    }
  }

  async enterVideoAssistantFullscreen(request: BrowserVideoAssistantFullscreenRequest): Promise<boolean> {
    const generation = ++this.transitionGeneration;
    const initialFacts = this.sink.resolveSurfaceFacts();
    this.emitEffect('capture_restore_insets');
    const restoreOrientation = await this.windowService.resolveRestoreOrientation(
      initialFacts.context,
      this.resolveSelectedWindowOrientation()
    );
    const decision = this.webPresentationCoordinator.enter(
      this.presentation.webFullscreenState,
      {
        tabId: request.tabId,
        activeTabId: initialFacts.activeTabId,
        webPageVisible: initialFacts.webPageVisible,
        homePageVisible: initialFacts.homePageVisible,
        tabsSheetVisible: initialFacts.tabsSheetVisible,
        source: 'video_takeover',
        restoreOrientation: restoreOrientation,
        payloadJson: this.buildVideoOrientationPayload(request.videoWidth, request.videoHeight)
      }
    );
    if (!decision.accepted) {
      return false;
    }
    const windowEntered = await this.windowService.enterFullscreenWindow(
      initialFacts.context,
      decision.orientation,
      decision.state.restoreOrientation
    );
    if (!windowEntered) {
      return false;
    }
    const currentFacts = this.sink.resolveSurfaceFacts();
    if (!this.isEntryStillValid(generation, request.tabId, currentFacts)) {
      await this.windowService.restoreFullscreenWindow(currentFacts.context, decision.state.restoreOrientation);
      return false;
    }
    this.publishFullscreenState(true, decision.state);
    this.emitEffect('fullscreen_chrome_entered');
    this.scheduleOrientationReapply(decision.orientation, currentFacts.context);
    return true;
  }

  async prepareVideoWebFullscreen(tabId: string): Promise<void> {
    const normalizedTabId = tabId.trim();
    this.pendingVideoWebFullscreenTabId = normalizedTabId;
    this.pendingVideoWebFullscreenRestoreOrientation = undefined;
    const facts = this.sink.resolveSurfaceFacts();
    const restorePromise = this.windowService.resolveRestoreOrientation(
      facts.context,
      this.resolveSelectedWindowOrientation()
    );
    this.pendingVideoWebFullscreenRestorePromise = restorePromise;
    const restoreOrientation = await restorePromise;
    if (this.pendingVideoWebFullscreenTabId === normalizedTabId &&
      this.pendingVideoWebFullscreenRestorePromise === restorePromise) {
      this.pendingVideoWebFullscreenRestoreOrientation = restoreOrientation;
    }
  }

  cancelVideoWebFullscreenPreparation(tabId: string): void {
    if (this.pendingVideoWebFullscreenTabId === tabId.trim()) {
      this.pendingVideoWebFullscreenTabId = '';
      this.pendingVideoWebFullscreenRestoreOrientation = undefined;
      this.pendingVideoWebFullscreenRestorePromise = undefined;
    }
  }

  async enterVideoWebFullscreen(request: BrowserVideoAssistantFullscreenRequest): Promise<boolean> {
    const normalizedTabId = request.tabId.trim();
    const currentState = this.presentation.webFullscreenState;
    if (currentState.active && currentState.source === 'video_web_fullscreen' &&
      currentState.tabId === normalizedTabId) {
      return true;
    }
    const generation = ++this.transitionGeneration;
    const initialFacts = this.sink.resolveSurfaceFacts();
    let restoreOrientation = this.pendingVideoWebFullscreenRestoreOrientation;
    if (restoreOrientation === undefined && this.pendingVideoWebFullscreenTabId === normalizedTabId &&
      this.pendingVideoWebFullscreenRestorePromise !== undefined) {
      restoreOrientation = await this.pendingVideoWebFullscreenRestorePromise;
    }
    if (restoreOrientation === undefined) {
      restoreOrientation = await this.windowService.resolveRestoreOrientation(
        initialFacts.context,
        this.resolveSelectedWindowOrientation()
      );
    }
    const decision = this.webPresentationCoordinator.enter(
      currentState,
      {
        tabId: normalizedTabId,
        activeTabId: initialFacts.activeTabId,
        webPageVisible: initialFacts.webPageVisible,
        homePageVisible: initialFacts.homePageVisible,
        tabsSheetVisible: initialFacts.tabsSheetVisible,
        source: 'video_web_fullscreen',
        restoreOrientation: restoreOrientation,
        payloadJson: this.buildVideoOrientationPayload(request.videoWidth, request.videoHeight)
      }
    );
    if (!decision.accepted) {
      return false;
    }
    const currentFacts = this.sink.resolveSurfaceFacts();
    if (!this.isEntryStillValid(generation, normalizedTabId, currentFacts)) {
      return false;
    }
    if (currentState.active && currentState.source === 'web_content') {
      await this.windowService.restoreFullscreenWindow(
        currentFacts.context,
        currentState.restoreOrientation
      );
    }
    this.emitEffect('capture_restore_insets');
    const windowEntered = await this.windowService.enterFullscreenWindow(
      initialFacts.context,
      decision.orientation,
      decision.state.restoreOrientation
    );
    if (!windowEntered) {
      this.webFullScreenExitHandler = undefined;
      return false;
    }
    this.publishFullscreenState(true, decision.state);
    this.emitEffect('fullscreen_chrome_entered');
    this.scheduleOrientationReapply(decision.orientation, currentFacts.context);
    this.cancelVideoWebFullscreenPreparation(normalizedTabId);
    return true;
  }

  async exitVideoAssistantFullscreen(showToast: boolean, notifyWebFullscreenExit: boolean): Promise<void> {
    if (this.webPresentationCoordinator.isActiveForSource(
      this.presentation.webFullscreenState,
      'video_web_fullscreen'
    )) {
      await this.exitVideoWebFullscreen(showToast, true);
      return;
    }
    this.transitionGeneration += 1;
    this.windowService.cancelOrientationReapply();
    if (notifyWebFullscreenExit) {
      this.notifyWebFullscreenExit();
    }
    const facts = this.sink.resolveSurfaceFacts();
    const decision = this.webPresentationCoordinator.exit(
      this.presentation.webFullscreenState,
      {
        tabId: this.presentation.webFullscreenState.tabId,
        activeTabId: facts.activeTabId,
        source: 'video_takeover'
      }
    );
    await this.windowService.restoreFullscreenWindow(facts.context, decision.restoreOrientation);
    if (decision.restoreChrome || this.presentation.fullScreenModeEnabled) {
      this.publishFullscreenState(false, decision.state);
      this.emitEffect('fullscreen_chrome_exited', 'video-assistant-fullscreen-exit', '', true);
    } else if (decision.state !== this.presentation.webFullscreenState) {
      this.publishFullscreenState(this.presentation.fullScreenModeEnabled, decision.state, false);
    }
    if (showToast) {
      this.emitEffect('toast', '', '已退出全屏模式。');
    }
  }

  async enterWebContentFullscreen(tabId: string, event: FullScreenEnterEvent): Promise<void> {
    if (this.pendingVideoWebFullscreenTabId === tabId.trim() ||
      this.webPresentationCoordinator.isActiveForSource(
        this.presentation.webFullscreenState,
        'video_web_fullscreen'
      )) {
      this.webFullScreenExitHandler = event.handler;
      if (!this.webPresentationCoordinator.isActiveForSource(
        this.presentation.webFullscreenState,
        'video_web_fullscreen'
      )) {
        const entered = await this.enterVideoWebFullscreen({
          tabId: tabId,
          videoWidth: event.videoWidth ?? 0,
          videoHeight: event.videoHeight ?? 0
        });
        if (!entered) {
          this.webFullScreenExitHandler = undefined;
          try {
            event.handler.exitFullScreen();
          } catch (_exitRejectedFullscreenError) {
          }
        }
      }
      return;
    }
    if (this.webPresentationCoordinator.isActiveForSource(
      this.presentation.webFullscreenState,
      'video_takeover'
    )) {
      this.webFullScreenExitHandler = event.handler;
      return;
    }
    this.webFullScreenExitHandler = event.handler;
    const generation = ++this.transitionGeneration;
    const initialFacts = this.sink.resolveSurfaceFacts();
    const restoreOrientation = await this.windowService.resolveRestoreOrientation(
      initialFacts.context,
      this.resolveSelectedWindowOrientation()
    );
    const decision = this.webPresentationCoordinator.enter(
      this.presentation.webFullscreenState,
      {
        tabId: tabId,
        activeTabId: initialFacts.activeTabId,
        webPageVisible: initialFacts.webPageVisible,
        homePageVisible: initialFacts.homePageVisible,
        tabsSheetVisible: initialFacts.tabsSheetVisible,
        source: 'web_content',
        restoreOrientation: restoreOrientation,
        videoWidth: event.videoWidth,
        videoHeight: event.videoHeight
      }
    );
    if (!decision.accepted) {
      return;
    }
    this.emitEffect('capture_restore_insets');
    const windowEntered = await this.windowService.enterFullscreenWindow(
      initialFacts.context,
      decision.orientation,
      decision.state.restoreOrientation
    );
    if (!windowEntered) {
      this.emitEffect('toast', '', '网页全屏失败。');
      return;
    }
    const currentFacts = this.sink.resolveSurfaceFacts();
    if (!this.isEntryStillValid(generation, tabId, currentFacts)) {
      await this.windowService.restoreFullscreenWindow(currentFacts.context, decision.state.restoreOrientation);
      return;
    }
    this.publishFullscreenState(true, decision.state);
    this.emitEffect('fullscreen_chrome_entered');
    this.scheduleOrientationReapply(decision.orientation, currentFacts.context);
  }

  async exitWebContentFullscreen(tabId: string, notifyWeb: boolean): Promise<void> {
    this.transitionGeneration += 1;
    const facts = this.sink.resolveSurfaceFacts();
    const decision = this.webPresentationCoordinator.exit(
      this.presentation.webFullscreenState,
      {
        tabId: tabId,
        activeTabId: facts.activeTabId,
        source: 'web_content'
      }
    );
    if (!decision.accepted) {
      return;
    }
    if (notifyWeb) {
      this.notifyWebFullscreenExit();
    }
    this.webFullScreenExitHandler = undefined;
    this.windowService.cancelOrientationReapply();
    this.publishFullscreenState(false, decision.state);
    this.emitEffect('fullscreen_chrome_exited', 'web-content-fullscreen-exit', '', true);
    await this.windowService.restoreFullscreenWindow(facts.context, decision.restoreOrientation);
    if (notifyWeb) {
      this.emitEffect('toast', '', '已退出全屏模式。');
    }
  }

  handleWebContentFullscreenExit(tabId: string): void {
    if (this.webPresentationCoordinator.isActiveForSource(
      this.presentation.webFullscreenState,
      'video_web_fullscreen'
    )) {
      void this.exitVideoWebFullscreen(false, false);
      return;
    }
    if (!this.webPresentationCoordinator.isActiveForSource(
      this.presentation.webFullscreenState,
      'web_content'
    )) {
      return;
    }
    void this.exitWebContentFullscreen(tabId, false);
  }

  openScreenOrientationSheet(): void {
    this.publishOrientationState(this.presentation.screenOrientationMode, false);
    this.pageToolsCoordinator.open('screenOrientation');
  }

  async applyScreenOrientationMode(mode: BrowserScreenOrientationMode): Promise<void> {
    const previousMode = this.presentation.screenOrientationMode;
    this.publishOrientationState(mode);
    this.pageToolsCoordinator.reset();
    try {
      const result = await this.orientationService.applyMode(
        this.sink.resolveSurfaceFacts().context,
        mode
      );
      this.publishOrientationState(result.mode);
      this.emitEffect('toast', '', result.message);
    } catch (_error) {
      this.publishOrientationState(previousMode);
      this.emitEffect('toast', '', '屏幕方向切换失败。');
    }
  }

  async applyTemporaryMediaOrientation(mode: BrowserTemporaryMediaOrientation): Promise<void> {
    await this.orientationService.applyMode(this.sink.resolveSurfaceFacts().context, mode);
  }

  private publishFullscreenState(
    enabled: boolean,
    webFullscreenState: BrowserWebFullscreenState,
    bumpActionVersion: boolean = true
  ): void {
    this.presentation = {
      fullScreenModeEnabled: enabled,
      fullScreenModeActionVersion: this.presentation.fullScreenModeActionVersion +
        (bumpActionVersion ? 1 : 0),
      webFullscreenState: webFullscreenState,
      screenOrientationMode: this.presentation.screenOrientationMode,
      screenOrientationOptions: this.presentation.screenOrientationOptions,
      screenOrientationActionVersion: this.presentation.screenOrientationActionVersion
    };
    this.sink.publishPresentation(this.presentation);
  }

  private publishOrientationState(mode: BrowserScreenOrientationMode, bumpActionVersion: boolean = true): void {
    this.presentation = {
      fullScreenModeEnabled: this.presentation.fullScreenModeEnabled,
      fullScreenModeActionVersion: this.presentation.fullScreenModeActionVersion,
      webFullscreenState: this.presentation.webFullscreenState,
      screenOrientationMode: mode,
      screenOrientationOptions: this.orientationViewModel.buildOptions(mode),
      screenOrientationActionVersion: this.presentation.screenOrientationActionVersion +
        (bumpActionVersion ? 1 : 0)
    };
    this.sink.publishPresentation(this.presentation);
  }

  private resolveSelectedWindowOrientation(): window.Orientation {
    return this.orientationService.resolveWindowOrientation(this.presentation.screenOrientationMode);
  }

  private isEntryStillValid(
    generation: number,
    tabId: string,
    facts: BrowserFullscreenSurfaceFacts
  ): boolean {
    return generation === this.transitionGeneration && tabId === facts.activeTabId && facts.webPageVisible &&
      !facts.homePageVisible && !facts.tabsSheetVisible;
  }

  private scheduleOrientationReapply(orientation: window.Orientation, context: common.UIAbilityContext): void {
    this.windowService.scheduleOrientationReapply(orientation, {
      getContext: (): common.UIAbilityContext => context,
      isFullscreenActive: (): boolean => this.presentation.webFullscreenState.active
    });
  }

  private notifyWebFullscreenExit(): void {
    if (this.webFullScreenExitHandler !== undefined) {
      try {
        this.webFullScreenExitHandler.exitFullScreen();
      } catch (_error) {
      }
    }
    this.webFullScreenExitHandler = undefined;
  }

  private async exitVideoWebFullscreen(showToast: boolean, notifyWeb: boolean): Promise<void> {
    this.transitionGeneration += 1;
    this.windowService.cancelOrientationReapply();
    if (notifyWeb) {
      this.notifyWebFullscreenExit();
    } else {
      this.webFullScreenExitHandler = undefined;
    }
    this.pendingVideoWebFullscreenTabId = '';
    const facts = this.sink.resolveSurfaceFacts();
    const decision = this.webPresentationCoordinator.exit(
      this.presentation.webFullscreenState,
      {
        tabId: this.presentation.webFullscreenState.tabId,
        activeTabId: facts.activeTabId,
        source: 'video_web_fullscreen'
      }
    );
    if (!decision.accepted) {
      return;
    }
    await this.windowService.restoreFullscreenWindow(facts.context, decision.restoreOrientation);
    this.publishFullscreenState(false, decision.state);
    this.emitEffect('fullscreen_chrome_exited', 'video-web-fullscreen-exit', '', true);
    if (showToast) {
      this.emitEffect('toast', '', '已退出全屏模式。');
    }
  }

  private buildVideoOrientationPayload(width: number, height: number): string {
    return '{"sourceWidth":' + Math.max(0, Math.floor(width)) +
      ',"sourceHeight":' + Math.max(0, Math.floor(height)) + '}';
  }

  private emitEffect(
    type: BrowserFullscreenSessionEffectType,
    source: string = '',
    message: string = '',
    restoreInsets: boolean = false
  ): void {
    this.sink.applyEffect({
      type: type,
      source: source,
      message: message,
      restoreInsets: restoreInsets
    });
  }
}

import { describe, expect, it } from '@ohos/hypium';
import { webview } from '@kit.ArkWeb';
import {
  BrowserArkWebMediaCastMediaResolution,
  BrowserArkWebMediaAssistantPlayerHost,
  BrowserArkWebMediaLaunchHost,
  BrowserArkWebMediaPlaybackEvidence,
  BrowserArkWebMediaReachabilityEvidence,
  BrowserArkWebMediaRuntimeEvidence,
  BrowserArkWebMediaTakeoverCoordinator
} from '../main/ets/core/browser/media/BrowserArkWebMediaTakeoverCoordinator';
import {
  ImmutableMediaSessionResolutionSnapshot,
  MediaResolvedPlaybackState,
  MediaResolvedVideoAssistantSession,
  MediaSessionResolutionSnapshot
} from '../main/ets/features/mediaDiscovery/MediaSessionResolutionModels';
import { TabManager } from '../main/ets/core/tabs/TabManager';
import { BrowserRuntimeLifecyclePort } from '../main/ets/services/web/BrowserRuntimeLifecyclePort';
import {
  WebVideoLiveCommand,
  WebVideoLiveCommandResult,
  WebVideoLiveSessionTarget,
  WebVideoPresentationService
} from '../main/ets/services/video/WebVideoPresentationService';

function missingCastMedia(): BrowserArkWebMediaCastMediaResolution {
  return {
    reason: 'missing_target',
    mediaFormat: '',
    requestHeaderCount: 0
  };
}

class TakeoverRecoveryRuntimePort extends BrowserRuntimeLifecyclePort {
  private readonly controller: webview.WebviewController = new webview.WebviewController();

  constructor() {
    super(
      new TabManager(),
      {
        getTabs: () => [],
        getWindowScopeId: () => 'window-test',
        getActiveTabId: () => 'tab-video-1',
        isHomeVisible: () => false,
        applyTabRuntimePatch: () => {},
        recordRuntimeEvent: () => {}
      },
      () => new webview.WebviewController(),
      {
        persistMountedRuntimeSnapshot: () => {}
      }
    );
  }

  resolveController(_tabId: string): webview.WebviewController | undefined {
    return this.controller;
  }

  isActiveWebTab(tabId: string): boolean {
    return tabId === 'tab-video-1';
  }
}

class TakeoverRecoveryPresentationService extends WebVideoPresentationService {
  enterAttemptCount: number = 0;
  restoreAttemptCount: number = 0;

  probeLiveTarget(
    _controller: webview.WebviewController | undefined,
    _target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    return Promise.resolve(this.success('probe_ok'));
  }

  executeLiveCommand(
    _controller: webview.WebviewController | undefined,
    _target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): Promise<WebVideoLiveCommandResult> {
    if (command.action === 'enter_live_presentation') {
      this.enterAttemptCount += 1;
      return Promise.resolve(this.failure('injected_enter_failure'));
    }
    if (command.action === 'restore_presentation') {
      this.restoreAttemptCount += 1;
      return Promise.resolve(this.success('restore_ok'));
    }
    return Promise.resolve(this.success('command_ok'));
  }

  private success(reason: string): WebVideoLiveCommandResult {
    return {
      ok: true,
      reason: reason,
      userVisibleMessage: '',
      currentTime: 12,
      duration: 120,
      paused: false,
      ended: false,
      seeking: false,
      readyState: 4,
      networkState: 1,
      errorCode: 0,
      playbackRate: 1,
      fullscreenActive: false
    };
  }

  private failure(reason: string): WebVideoLiveCommandResult {
    return {
      ok: false,
      reason: reason,
      userVisibleMessage: '接管失败',
      currentTime: 12,
      duration: 120,
      paused: false,
      ended: false,
      seeking: false,
      readyState: 4,
      networkState: 1,
      errorCode: 0,
      playbackRate: 1,
      fullscreenActive: false
    };
  }
}

class TakeoverDeferredProbePresentationService extends WebVideoPresentationService {
  private probeResolver?: (result: WebVideoLiveCommandResult) => void = undefined;
  enterAttemptCount: number = 0;

  probeLiveTarget(
    _controller: webview.WebviewController | undefined,
    _target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    return new Promise<WebVideoLiveCommandResult>((resolve: (result: WebVideoLiveCommandResult) => void): void => {
      this.probeResolver = resolve;
    });
  }

  completeProbe(): void {
    this.probeResolver?.({
      ok: true,
      reason: 'probe_ok',
      userVisibleMessage: '',
      currentTime: 12,
      duration: 120,
      paused: false,
      ended: false,
      seeking: false,
      readyState: 4,
      networkState: 1,
      errorCode: 0,
      playbackRate: 1,
      fullscreenActive: false
    });
  }

  executeLiveCommand(
    _controller: webview.WebviewController | undefined,
    _target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): Promise<WebVideoLiveCommandResult> {
    if (command.action === 'enter_live_presentation') {
      this.enterAttemptCount += 1;
    }
    const result: WebVideoLiveCommandResult = {
      ok: true,
      reason: 'command_ok',
      userVisibleMessage: '',
      currentTime: 12,
      duration: 120,
      paused: false,
      ended: false,
      seeking: false,
      readyState: 4,
      networkState: 1,
      errorCode: 0,
      playbackRate: 1,
      fullscreenActive: true
    };
    return Promise.resolve(result);
  }
}

class TakeoverDeferredCommandPresentationService extends WebVideoPresentationService {
  private commandResolver?: (result: WebVideoLiveCommandResult) => void = undefined;
  toggleAttemptCount: number = 0;

  probeLiveTarget(
    _controller: webview.WebviewController | undefined,
    _target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    return Promise.resolve(this.success('probe_ok', false));
  }

  executeLiveCommand(
    _controller: webview.WebviewController | undefined,
    _target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): Promise<WebVideoLiveCommandResult> {
    if (command.action !== 'toggle') {
      return Promise.resolve(this.success('command_ok', false));
    }
    this.toggleAttemptCount += 1;
    return new Promise<WebVideoLiveCommandResult>((resolve: (result: WebVideoLiveCommandResult) => void): void => {
      this.commandResolver = resolve;
    });
  }

  completePauseCommand(): void {
    this.commandResolver?.(this.success('pause_applied', true));
  }

  completePlayCommand(): void {
    this.commandResolver?.(this.success('play_requested', false));
  }

  private success(reason: string, paused: boolean): WebVideoLiveCommandResult {
    return {
      ok: true,
      reason: reason,
      userVisibleMessage: '',
      currentTime: 48,
      duration: 120,
      paused: paused,
      ended: false,
      seeking: false,
      readyState: 4,
      networkState: 1,
      errorCode: 0,
      playbackRate: 1,
      fullscreenActive: true
    };
  }
}

function videoMediaInfo(): webview.MediaInfo {
  return {
    embedID: 'video-main',
    mediaType: webview.MediaType.VIDEO,
    mediaSrcList: [{
      type: webview.SourceType.URL,
      source: 'https://media.example/video.mp4',
      format: 'video/mp4'
    }],
    surfaceInfo: {
      id: 'surface-main',
      rect: {
        x: 0,
        y: 0,
        width: 1280,
        height: 720
      }
    },
    controlsShown: true,
    controlList: [],
    muted: false,
    posterUrl: '',
    preload: webview.Preload.AUTO,
    headers: {},
    attributes: {}
  };
}

function resolvedSnapshot(
  reachability: 'unknown' | 'reachable' | 'unreachable' | 'expired',
  expiresAt: number = 0,
  playbackState: MediaResolvedPlaybackState = 'playing',
  revision: number = 7
): MediaSessionResolutionSnapshot {
  const session: MediaResolvedVideoAssistantSession = {
    sessionId: 'video-session:g1:target-main',
    playbackTargetId: 'target-main',
    targetKey: 'dom:runtime-main',
    playbackState: playbackState,
    webLiveReachability: reachability,
    webLiveReachabilityObservedAt: 1000,
    webLiveReachabilityExpiresAt: expiresAt,
    evidenceQuality: 'direct',
    observedAt: 1000,
    currentTimeSeconds: 12,
    durationSeconds: 120,
    playbackTargetBinding: {
      transport: 'document_direct',
      runtimeId: 'runtime-main',
      frameRuntimeId: '',
      elementId: 'video-main'
    },
    geometry: {
      x: 0,
      y: 0,
      width: 1280,
      height: 720,
      viewportWidth: 1280,
      viewportHeight: 720,
      visible: true,
      videoWidth: 1280,
      videoHeight: 720
    },
    muted: false
  };
  const active = playbackState === 'playing' ? session.sessionId : undefined;
  return new ImmutableMediaSessionResolutionSnapshot(
    { tabId: 'tab-video-1', generationId: 'g1', routeEpochId: 'r1' },
    revision,
    1000,
    active === undefined ? 'inactive' : 'active',
    [session],
    active,
    active === undefined ? ['no_current_playing_session'] : ['single_authoritative_playing_session']
  );
}

function resolvedFrameSnapshot(
  playbackState: MediaResolvedPlaybackState = 'playing',
  reachability: 'unknown' | 'reachable' | 'unreachable' | 'expired' = 'unknown',
  expiresAt: number = 0
): MediaSessionResolutionSnapshot {
  const session: MediaResolvedVideoAssistantSession = {
    sessionId: 'video-session:g1:target-frame',
    playbackTargetId: 'target-frame',
    targetKey: 'frame:frame-main:video:runtime-main',
    playbackState: playbackState,
    webLiveReachability: reachability,
    webLiveReachabilityObservedAt: 0,
    webLiveReachabilityExpiresAt: expiresAt,
    evidenceQuality: 'direct',
    observedAt: 1000,
    currentTimeSeconds: 12,
    durationSeconds: 120,
    playbackTargetBinding: {
      transport: 'frame_proxy',
      runtimeId: 'runtime-main',
      frameRuntimeId: 'frame-main',
      elementId: 'video-main'
    },
    geometry: {
      x: 0,
      y: 0,
      width: 1280,
      height: 720,
      viewportWidth: 1280,
      viewportHeight: 720,
      visible: true,
      videoWidth: 1280,
      videoHeight: 720
    },
    muted: false
  };
  const activeSessionId = playbackState === 'playing' ? session.sessionId : undefined;
  return new ImmutableMediaSessionResolutionSnapshot(
    { tabId: 'tab-video-1', generationId: 'g1', routeEpochId: 'r1' },
    7,
    1000,
    activeSessionId === undefined ? 'inactive' : 'active',
    [session],
    activeSessionId,
    activeSessionId === undefined ? ['no_current_playing_session'] : ['single_authoritative_playing_session']
  );
}

function resolvedCompetingSnapshot(
  outcome: 'active' | 'ambiguous',
  activeSessionId: string | undefined
): MediaSessionResolutionSnapshot {
  const first = resolvedSnapshot('reachable', Date.now() + 20000).getSessions()[0];
  const second: MediaResolvedVideoAssistantSession = {
    sessionId: 'video-session:g1:target-second',
    playbackTargetId: 'target-second',
    targetKey: 'dom:runtime-second',
    playbackState: 'playing',
    webLiveReachability: 'reachable',
    webLiveReachabilityObservedAt: 1000,
    webLiveReachabilityExpiresAt: Date.now() + 20000,
    evidenceQuality: 'direct',
    observedAt: 1000,
    currentTimeSeconds: 4,
    durationSeconds: 90,
    playbackTargetBinding: {
      transport: 'document_direct',
      runtimeId: 'runtime-second',
      frameRuntimeId: '',
      elementId: 'video-second'
    },
    geometry: {
      x: 0,
      y: 0,
      width: 640,
      height: 360,
      viewportWidth: 1280,
      viewportHeight: 720,
      visible: true,
      videoWidth: 640,
      videoHeight: 360
    },
    muted: false
  };
  return new ImmutableMediaSessionResolutionSnapshot(
    { tabId: 'tab-video-1', generationId: 'g1', routeEpochId: 'r1' },
    9,
    1100,
    outcome,
    [first, second],
    activeSessionId,
    outcome === 'ambiguous' ? ['equally_authoritative_playing_sessions'] :
      ['strongest_playing_session']
  );
}

export default function browserArkWebMediaTakeoverRecoveryCharacterizationTest(): void {
  describe('BrowserArkWebMediaTakeoverCoordinator recovery characterization', () => {
    it('restores the original Web presentation and does not silently activate another route', 0, async () => {
      const runtimePort = new TakeoverRecoveryRuntimePort();
      const presentationService = new TakeoverRecoveryPresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(runtimePort, presentationService);
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedSnapshot('unknown');
      const publishedReachability: BrowserArkWebMediaReachabilityEvidence[] = [];
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({
          isCurrent: (): boolean => true,
          commit: (evidence: BrowserArkWebMediaRuntimeEvidence): boolean => {
            if (evidence.kind === 'web_live_reachability') {
              publishedReachability.push(evidence);
              snapshot = resolvedSnapshot(
                evidence.state,
                evidence.expiresAt,
                'playing',
                (snapshot?.evidenceRevision ?? 7) + 1
              );
            }
            return true;
          }
        }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      coordinator.observe({
        tabId: 'tab-video-1',
        pageUrl: 'https://page.example/watch',
        pageTitle: 'Video',
        suppressDiagnostics: false,
        mediaInfo: videoMediaInfo()
      });
      const reachabilityStartedAt = Date.now();
      const reachability = await coordinator.verifyDocumentDirectReachability(
        'tab-video-1',
        'video-session:g1:target-main',
        'runtime-main'
      );
      if (reachability.reachabilityEvidence !== undefined) {
        snapshot = resolvedSnapshot(
          reachability.reachabilityEvidence.state,
          reachability.reachabilityEvidence.expiresAt,
          'playing',
          8
        );
      }
      let startedCount = 0;
      const host: BrowserArkWebMediaLaunchHost = {
        showToast: () => {},
        invalidatePresentation: () => {},
        enterWebLiveFullscreen: () => Promise.resolve(true),
        exitWebLiveFullscreen: () => {},
        onStarted: () => {
          startedCount += 1;
        }
      };

      const result = await coordinator.launch({
        activeTabId: 'tab-video-1',
        webLiveRouteEnabled: true
      }, host);
      const nextPlan = coordinator.beginLaunch('tab-video-1', true);

      expect(result.started).assertFalse();
      expect(presentationService.enterAttemptCount).assertEqual(1);
      expect(presentationService.restoreAttemptCount).assertEqual(1);
      expect(reachability.reachabilityEvidence?.targetKey).assertEqual('dom:runtime-main');
      expect(reachability.reachabilityEvidence?.state).assertEqual('reachable');
      expect((reachability.reachabilityEvidence?.expiresAt ?? 0) > reachabilityStartedAt).assertTrue();
      expect(publishedReachability.length).assertEqual(2);
      expect(publishedReachability[0].state).assertEqual('reachable');
      expect(publishedReachability[1].state).assertEqual('unreachable');
      expect(publishedReachability[1].targetKey).assertEqual('dom:runtime-main');
      expect(startedCount).assertEqual(0);
      expect(coordinator.isWebLiveAssistantActive()).assertFalse();
      expect(nextPlan.accepted).assertFalse();
      expect(nextPlan.reason).assertEqual('web_live_unavailable');
    });

    it('does not publish reachability from a probe completed after top-level navigation', 0, async () => {
      const presentationService = new TakeoverDeferredProbePresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(
        new TakeoverRecoveryRuntimePort(),
        presentationService
      );
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedSnapshot('unknown');
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({
          isCurrent: (): boolean => snapshot !== undefined,
          commit: (): boolean => snapshot !== undefined
        }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      const pendingProbe = coordinator.verifyDocumentDirectReachability(
        'tab-video-1',
        'video-session:g1:target-main',
        'runtime-main'
      );

      snapshot = undefined;
      coordinator.beginNavigation('tab-video-1');
      presentationService.completeProbe();
      const result = await pendingProbe;

      expect(result.accepted).assertFalse();
      expect(result.reason).assertEqual('direct_target_stale');
      expect(result.reachabilityEvidence).assertUndefined();
    });

    it('rejects a child-frame probe completed after its resolved session disappears', 0, async () => {
      const presentationService = new TakeoverDeferredProbePresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(
        new TakeoverRecoveryRuntimePort(),
        presentationService
      );
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedFrameSnapshot();
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({
          isCurrent: (): boolean => snapshot !== undefined,
          commit: (): boolean => snapshot !== undefined
        }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      const pendingProbe = coordinator.observeFramePlaybackSignal({
        tabId: 'tab-video-1',
        frameType: 'child_document',
        frameRuntimeId: 'frame-main',
        targetKey: 'frame:frame-main:video:runtime-main',
        eventName: 'playing',
        runtimeId: 'runtime-main',
        elementId: 'video-main',
        source: 'https://frame.example/video.m3u8',
        muted: false,
        paused: false,
        ended: false,
        readyState: 4,
        networkState: 1,
        visible: true,
        rect: { x: 0, y: 0, width: 1280, height: 720 },
        viewportWidth: 1280,
        viewportHeight: 720,
        videoWidth: 1280,
        videoHeight: 720,
        currentTime: 12,
        duration: 120,
        observedAt: 1000
      });

      snapshot = undefined;
      presentationService.completeProbe();
      const result = await pendingProbe;

      expect(result.accepted).assertFalse();
      expect(result.reason).assertEqual('frame_target_stale');
      expect(result.reachabilityEvidence).assertUndefined();
      expect(presentationService.enterAttemptCount).assertEqual(0);
    });

    it('restores an active child-frame takeover when the resolved target ends', 0, async () => {
      const presentationService = new TakeoverDeferredCommandPresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(
        new TakeoverRecoveryRuntimePort(),
        presentationService
      );
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedFrameSnapshot(
        'playing',
        'reachable',
        Date.now() + 20000
      );
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({
          isCurrent: (): boolean => true,
          commit: (): boolean => true
        }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      let exitCount = 0;
      const launchResult = await coordinator.launch({
        activeTabId: 'tab-video-1',
        webLiveRouteEnabled: true
      }, {
        showToast: () => {},
        invalidatePresentation: () => {},
        enterWebLiveFullscreen: () => Promise.resolve(true),
        exitWebLiveFullscreen: () => {
          exitCount += 1;
        },
        onStarted: () => {}
      });
      snapshot = resolvedFrameSnapshot('ended', 'reachable', Date.now() + 20000);

      const result = await coordinator.observeFramePlaybackSignal({
        tabId: 'tab-video-1',
        frameType: 'child_document',
        frameRuntimeId: 'frame-main',
        targetKey: 'frame:frame-main:video:runtime-main',
        eventName: 'ended',
        runtimeId: 'runtime-main',
        elementId: 'video-main',
        source: 'https://frame.example/video.m3u8',
        muted: false,
        paused: true,
        ended: true,
        readyState: 4,
        networkState: 1,
        visible: true,
        rect: { x: 0, y: 0, width: 1280, height: 720 },
        viewportWidth: 1280,
        viewportHeight: 720,
        videoWidth: 1280,
        videoHeight: 720,
        currentTime: 120,
        duration: 120,
        observedAt: 2000
      });

      expect(launchResult.started).assertTrue();
      expect(result.accepted).assertTrue();
      expect(result.reachabilityEvidence?.state).assertEqual('unreachable');
      expect(coordinator.isWebLiveAssistantActive()).assertFalse();
      expect(exitCount).assertEqual(1);
    });

    it('does not enter presentation when the active session changes during launch probe', 0, async () => {
      const presentationService = new TakeoverDeferredProbePresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(
        new TakeoverRecoveryRuntimePort(),
        presentationService
      );
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedSnapshot(
        'reachable',
        Date.now() + 20000
      );
      let commitCount = 0;
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({
          isCurrent: (): boolean => true,
          commit: (): boolean => {
            commitCount += 1;
            return true;
          }
        }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      coordinator.observe({
        tabId: 'tab-video-1',
        pageUrl: 'https://page.example/watch',
        pageTitle: 'Video',
        suppressDiagnostics: false,
        mediaInfo: videoMediaInfo()
      });
      const pendingLaunch = coordinator.launch({
        activeTabId: 'tab-video-1',
        webLiveRouteEnabled: true
      }, {
        showToast: () => {},
        invalidatePresentation: () => {},
        enterWebLiveFullscreen: () => Promise.resolve(true),
        exitWebLiveFullscreen: () => {},
        onStarted: () => {}
      });

      snapshot = undefined;
      presentationService.completeProbe();
      const result = await pendingLaunch;

      expect(result.started).assertFalse();
      expect(commitCount).assertEqual(0);
      expect(presentationService.enterAttemptCount).assertEqual(0);
    });

    it('rejects a command result when its captured route scope or evidence commit is rejected', 0, async () => {
      const presentationService = new TakeoverDeferredCommandPresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(
        new TakeoverRecoveryRuntimePort(),
        presentationService
      );
      let captureCurrent = true;
      let commitAccepted = true;
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedSnapshot(
        'reachable',
        Date.now() + 20000
      );
      const publishedPlayback: BrowserArkWebMediaPlaybackEvidence[] = [];
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({
          isCurrent: (): boolean => captureCurrent,
          commit: (evidence: BrowserArkWebMediaRuntimeEvidence): boolean => {
            if (captureCurrent && commitAccepted && evidence.kind === 'playback') {
              publishedPlayback.push(evidence);
              const playbackState: MediaResolvedPlaybackState = evidence.event === 'paused' ? 'paused' :
                evidence.event === 'ended' ? 'ended' : 'playing';
              snapshot = resolvedSnapshot(
                'reachable',
                Date.now() + 20000,
                playbackState,
                (snapshot?.evidenceRevision ?? 7) + 1
              );
            }
            return captureCurrent && commitAccepted;
          }
        }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      coordinator.observe({
        tabId: 'tab-video-1',
        pageUrl: 'https://page.example/watch',
        pageTitle: 'Video',
        suppressDiagnostics: false,
        mediaInfo: videoMediaInfo()
      });
      const launchHost: BrowserArkWebMediaLaunchHost = {
        showToast: () => {},
        invalidatePresentation: () => {},
        enterWebLiveFullscreen: () => Promise.resolve(true),
        exitWebLiveFullscreen: () => {},
        onStarted: () => {}
      };
      const launchResult = await coordinator.launch({
        activeTabId: 'tab-video-1',
        webLiveRouteEnabled: true
      }, launchHost);
      const assistantHost: BrowserArkWebMediaAssistantPlayerHost = {
        applyOrientation: () => Promise.resolve(undefined),
        exitWebLiveFullscreen: () => Promise.resolve(undefined),
        invalidatePresentation: () => {},
        requestDownload: () => Promise.resolve(undefined),
        showToast: () => {}
      };

      coordinator.handleAssistantPlayerAction({
        type: 'web_live_command',
        command: { action: 'toggle' }
      }, assistantHost);
      captureCurrent = false;
      snapshot = resolvedSnapshot('reachable', Date.now() + 20000);
      presentationService.completePauseCommand();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });

      expect(launchResult.started).assertTrue();
      expect(coordinator.getAssistantPlayerState().playbackStatus).assertEqual('playing');
      expect(publishedPlayback.length).assertEqual(0);

      captureCurrent = true;
      commitAccepted = false;
      coordinator.handleAssistantPlayerAction({
        type: 'web_live_command',
        command: { action: 'toggle' }
      }, assistantHost);
      presentationService.completePauseCommand();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });

      expect(coordinator.getAssistantPlayerState().playbackStatus).assertEqual('playing');
      expect(publishedPlayback.length).assertEqual(0);

      commitAccepted = true;
      coordinator.handleAssistantPlayerAction({
        type: 'web_live_command',
        command: { action: 'toggle' }
      }, assistantHost);
      presentationService.completePauseCommand();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });

      expect(coordinator.isWebLiveAssistantActive()).assertTrue();
      expect(coordinator.getAssistantPlayerState().playbackStatus).assertEqual('paused');

      coordinator.handleAssistantPlayerAction({
        type: 'web_live_command',
        command: { action: 'toggle' }
      }, assistantHost);
      presentationService.completePlayCommand();
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });

      expect(coordinator.getAssistantPlayerState().playbackStatus).assertEqual('playing');
      expect(publishedPlayback.length).assertEqual(2);
    });

    it('does not keep controlling a pinned session after authority selects another or becomes ambiguous', 0, async () => {
      const presentationService = new TakeoverDeferredCommandPresentationService();
      const coordinator = new BrowserArkWebMediaTakeoverCoordinator(
        new TakeoverRecoveryRuntimePort(),
        presentationService
      );
      let snapshot: MediaSessionResolutionSnapshot | undefined = resolvedSnapshot(
        'reachable',
        Date.now() + 20000
      );
      coordinator.bindRuntimeEvidencePublisher({
        capture: () => ({ isCurrent: (): boolean => true, commit: (): boolean => true }),
        resolveSnapshot: () => snapshot,
        resolveCastMedia: () => missingCastMedia()
      });
      let exitCount = 0;
      const launchResult = await coordinator.launch({
        activeTabId: 'tab-video-1',
        webLiveRouteEnabled: true
      }, {
        showToast: () => {},
        invalidatePresentation: () => {},
        enterWebLiveFullscreen: () => Promise.resolve(true),
        exitWebLiveFullscreen: () => {
          exitCount += 1;
        },
        onStarted: () => {}
      });
      const assistantHost: BrowserArkWebMediaAssistantPlayerHost = {
        applyOrientation: () => Promise.resolve(undefined),
        exitWebLiveFullscreen: () => Promise.resolve(undefined),
        invalidatePresentation: () => {},
        requestDownload: () => Promise.resolve(undefined),
        showToast: () => {}
      };

      snapshot = resolvedCompetingSnapshot('active', 'video-session:g1:target-second');
      coordinator.handleAssistantPlayerAction({
        type: 'web_live_command',
        command: { action: 'toggle' }
      }, assistantHost);
      expect(coordinator.isWebLiveAssistantActive()).assertFalse();
      expect(presentationService.toggleAttemptCount).assertEqual(0);

      snapshot = resolvedCompetingSnapshot('ambiguous', undefined);
      expect(coordinator.isWebLiveAssistantActive()).assertFalse();
      expect(coordinator.handleSessionResolutionChanged('tab-video-1')).assertTrue();
      expect(exitCount).assertEqual(1);
      expect(launchResult.started).assertTrue();
    });
  });
}

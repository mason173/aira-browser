import { webview } from '@kit.ArkWeb';
import {
  WEB_VIDEO_ACTION_TOOLBAR_PROTOCOL,
  WEB_VIDEO_CONTROLS_HIDDEN_MARKER_ATTRIBUTE,
  WEB_VIDEO_CONTROLS_OBSERVER_PROPERTY,
  WEB_VIDEO_CONTROLS_STYLE_ELEMENT_ID,
  WEB_VIDEO_LIVE_PRESENTATION_PROPERTY,
  WEB_VIDEO_ORIGINAL_CONTROLS_PROPERTY,
  WEB_VIDEO_ORIGINAL_CONTROLS_HIDDEN_MARKER_PROPERTY,
  WEB_VIDEO_ORIGINAL_OBJECT_FIT_PRIORITY_PROPERTY,
  WEB_VIDEO_ORIGINAL_OBJECT_FIT_PROPERTY,
  WEB_VIDEO_RUNTIME_ID_PROPERTY,
  WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT
} from './WebVideoRuntimeProtocol';
import {
  WEB_VIDEO_FRAME_HOST_BRIDGE_PROPERTY,
  WEB_VIDEO_FRAME_HOST_PROTOCOL,
  WebVideoFrameCommandTransport
} from './WebVideoFrameCommandTransport';

export type WebVideoLiveTargetTransport = 'document_direct' | 'frame_proxy';
export type WebVideoLivePresentationMode = 'viewport_promoted' | 'preserve_surface';

export interface WebVideoLiveSessionTarget {
  runtimeId: string;
  elementId: string;
  source: string;
  tabId?: string;
  frameRuntimeId?: string;
  transport?: WebVideoLiveTargetTransport;
  presentationMode?: WebVideoLivePresentationMode;
}

export type WebVideoLiveCommandAction =
  | 'read_state'
  | 'toggle'
  | 'seek'
  | 'rate'
  | 'scale'
  | 'picture_in_picture'
  | 'install_action_toolbar'
  | 'picture_in_picture_status'
  | 'enter_live_presentation'
  | 'suppress_native_controls'
  | 'restore_presentation';

export interface WebVideoLiveCommand {
  action: WebVideoLiveCommandAction;
  value?: number;
}

export interface WebVideoLiveCommandResult {
  ok: boolean;
  reason: string;
  userVisibleMessage: string;
  currentTime: number;
  duration: number;
  paused: boolean;
  ended: boolean;
  seeking: boolean;
  readyState: number;
  networkState: number;
  errorCode: number;
  playbackRate: number;
  fullscreenActive: boolean;
  diagnostic?: string;
}

type WebVideoFrameHostCommandAction =
  | 'probe_frame_host'
  | 'enter_frame_host_presentation'
  | 'restore_frame_host_presentation';

interface WebVideoFrameHostCommandResult {
  ok: boolean;
  reason: string;
  detail?: string;
}

const WEB_VIDEO_PIP_REQUEST_STATE_PROPERTY: string = '__airaWebVideoPiPRequestState';
const WEB_VIDEO_PIP_CONFIRM_ATTEMPTS: number = 10;
const WEB_VIDEO_PIP_CONFIRM_INTERVAL_MS: number = 160;
const MAX_WEB_VIDEO_COMMAND_RESULT_LENGTH: number = 16384;
const MAX_WEB_VIDEO_COMMAND_REASON_LENGTH: number = 128;
const MAX_WEB_VIDEO_COMMAND_MESSAGE_LENGTH: number = 512;
const MAX_WEB_VIDEO_COMMAND_DIAGNOSTIC_LENGTH: number = 1536;
const MAX_WEB_VIDEO_FRAME_HOST_RESULT_LENGTH: number = 1024;
const MAX_WEB_VIDEO_FRAME_HOST_REASON_LENGTH: number = 128;
const MAX_WEB_VIDEO_FRAME_HOST_DETAIL_LENGTH: number = 512;
export class WebVideoPresentationService {
  private readonly frameCommandTransport?: WebVideoFrameCommandTransport;

  constructor(frameCommandTransport?: WebVideoFrameCommandTransport) {
    this.frameCommandTransport = frameCommandTransport;
  }

  async probeLiveTarget(
    controller: webview.WebviewController | undefined,
    target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    return this.executeLiveCommand(controller, target, { action: 'read_state' });
  }

  async executeLiveCommand(
    controller: webview.WebviewController | undefined,
    target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): Promise<WebVideoLiveCommandResult> {
    if (controller === undefined) {
      return this.buildFailedLiveCommandResult('no_controller', '当前网页不可用，无法控制视频。');
    }
    const initialResult = (target.transport ?? 'document_direct') === 'frame_proxy' ?
      await this.runFrameProxyLiveCommand(controller, target, command) :
      await this.runLiveCommand(controller, target, command);
    if (command.action !== 'picture_in_picture' || !initialResult.ok ||
      initialResult.reason !== 'picture_in_picture_pending') {
      return initialResult;
    }
    return this.confirmWebPictureInPicture(controller, target, initialResult);
  }

  async installActionToolbar(
    controller: webview.WebviewController | undefined,
    target: WebVideoLiveSessionTarget
  ): Promise<WebVideoLiveCommandResult> {
    return this.executeLiveCommand(controller, target, {
      action: 'install_action_toolbar'
    });
  }

  private async runFrameProxyLiveCommand(
    controller: webview.WebviewController,
    target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): Promise<WebVideoLiveCommandResult> {
    if (command.action === 'read_state') {
      const targetResult = await this.runLiveCommand(controller, target, command);
      if (!targetResult.ok) {
        return targetResult;
      }
      const hostResult = await this.runFrameHostCommand(controller, target, 'probe_frame_host');
      if (!hostResult.ok) {
        return this.buildFailedLiveCommandResult(hostResult.reason, '当前网页视频会话已经变化。');
      }
      return targetResult;
    }
    if (command.action === 'enter_live_presentation') {
      const hostResult = await this.runFrameHostCommand(
        controller,
        target,
        'enter_frame_host_presentation'
      );
      if (!hostResult.ok) {
        return this.buildFailedLiveCommandResult(hostResult.reason, '网页视频画面接管失败，原网页将继续播放。');
      }
      // The host must snapshot the iframe before the child video changes it. Otherwise
      // restore would write the takeover's pointer-events/z-index styles back into the
      // page and leave the visible toolbar inside a non-interactive frame.
      const targetResult = await this.runLiveCommand(controller, target, command);
      if (targetResult.ok) {
        return targetResult;
      }
      await this.runLiveCommand(controller, target, { action: 'restore_presentation' });
      await this.runFrameHostCommand(
        controller,
        target,
        'restore_frame_host_presentation'
      );
      return targetResult;
    }
    if (command.action === 'restore_presentation') {
      const targetResult = await this.runLiveCommand(controller, target, command);
      const hostResult = await this.runFrameHostCommand(
        controller,
        target,
        'restore_frame_host_presentation'
      );
      if (!hostResult.ok) {
        return this.buildFailedLiveCommandResult(hostResult.reason, '网页视频画面恢复失败。');
      }
      return targetResult;
    }
    return this.runLiveCommand(controller, target, command);
  }

  private async runFrameHostCommand(
    controller: webview.WebviewController,
    target: WebVideoLiveSessionTarget,
    action: WebVideoFrameHostCommandAction
  ): Promise<WebVideoFrameHostCommandResult> {
    const frameRuntimeId = target.frameRuntimeId?.trim() ?? '';
    if (frameRuntimeId.length <= 0) {
      return this.buildFailedFrameHostCommandResult('frame_host_target_missing');
    }
    try {
      const raw = await controller.runJavaScript(this.buildFrameHostCommandScript(frameRuntimeId, action));
      const result = this.parseFrameHostCommandResult(this.unwrapJsonString(String(raw ?? '')), action);
      return result;
    } catch (error) {
      return this.buildFailedFrameHostCommandResult(
        (error as Error)?.message ?? 'frame_host_command_failed'
      );
    }
  }

  private async runLiveCommand(
    controller: webview.WebviewController,
    target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): Promise<WebVideoLiveCommandResult> {
    try {
      const script = this.buildExecuteLiveCommandScript(target, command);
      let raw: string;
      if ((target.transport ?? 'document_direct') === 'frame_proxy') {
        const tabId = target.tabId?.trim() ?? '';
        const frameRuntimeId = target.frameRuntimeId?.trim() ?? '';
        if (this.frameCommandTransport === undefined || tabId.length <= 0 || frameRuntimeId.length <= 0) {
          return this.buildFailedLiveCommandResult(
            'frame_transport_unavailable',
            '当前网页视频会话已经变化。'
          );
        }
        raw = await this.frameCommandTransport.executeFrameCommand({
          tabId: tabId,
          frameRuntimeId: frameRuntimeId,
          action: command.action,
          script: script
        });
      } else {
        raw = await controller.runJavaScript(script);
      }
      const result = this.parseLiveCommandResult(this.unwrapJsonString(String(raw ?? '')), command);
      return result;
    } catch (error) {
      const message = (error as Error)?.message ?? 'run_javascript_failed';
      return this.buildFailedLiveCommandResult(message, '网页视频控制失败。');
    }
  }

  private async confirmWebPictureInPicture(
    controller: webview.WebviewController,
    target: WebVideoLiveSessionTarget,
    initialResult: WebVideoLiveCommandResult
  ): Promise<WebVideoLiveCommandResult> {
    let latestResult = initialResult;
    for (let attempt = 0; attempt < WEB_VIDEO_PIP_CONFIRM_ATTEMPTS; attempt += 1) {
      await this.delay(WEB_VIDEO_PIP_CONFIRM_INTERVAL_MS);
      latestResult = await this.runLiveCommand(controller, target, { action: 'picture_in_picture_status' });
      if (!latestResult.ok || latestResult.reason !== 'picture_in_picture_pending') {
        return latestResult;
      }
    }
    return this.buildFailedLiveCommandResult(
      'picture_in_picture_confirmation_timeout',
      '当前视频暂不支持小窗播放。'
    );
  }

  private parseLiveCommandResult(raw: string, command: WebVideoLiveCommand): WebVideoLiveCommandResult {
    if (raw.length <= 0 || raw.length > MAX_WEB_VIDEO_COMMAND_RESULT_LENGTH) {
      return this.buildFailedLiveCommandResult('invalid_result_length', '网页视频控制失败。');
    }
    try {
      const value = JSON.parse(raw) as WebVideoLiveCommandResult;
      const reason = typeof value.reason === 'string' ? value.reason : '';
      const userVisibleMessage = typeof value.userVisibleMessage === 'string' ? value.userVisibleMessage : '';
      const currentTime = typeof value.currentTime === 'number' ? value.currentTime : Number.NaN;
      const duration = typeof value.duration === 'number' ? value.duration : Number.NaN;
      const readyState = typeof value.readyState === 'number' ? value.readyState : Number.NaN;
      const networkState = typeof value.networkState === 'number' ? value.networkState : Number.NaN;
      const errorCode = typeof value.errorCode === 'number' ? value.errorCode : Number.NaN;
      const playbackRate = typeof value.playbackRate === 'number' ? value.playbackRate : Number.NaN;
      const diagnostic = typeof value.diagnostic === 'string' ? value.diagnostic : '';
      const validShape = typeof value.ok === 'boolean' && typeof value.paused === 'boolean' &&
        typeof value.ended === 'boolean' && typeof value.seeking === 'boolean' &&
        typeof value.fullscreenActive === 'boolean' &&
        reason.length <= MAX_WEB_VIDEO_COMMAND_REASON_LENGTH &&
        userVisibleMessage.length <= MAX_WEB_VIDEO_COMMAND_MESSAGE_LENGTH &&
        diagnostic.length <= MAX_WEB_VIDEO_COMMAND_DIAGNOSTIC_LENGTH &&
        Number.isFinite(currentTime) && currentTime >= 0 && Number.isFinite(duration) && duration >= 0 &&
        Number.isFinite(readyState) && readyState >= 0 && readyState <= 4 &&
        Number.isFinite(networkState) && networkState >= 0 && networkState <= 3 &&
        Number.isFinite(errorCode) && errorCode >= 0 && errorCode <= 4 &&
        Number.isFinite(playbackRate) && playbackRate >= 0.1 && playbackRate <= 16;
      if (validShape && (!value.ok || this.isExpectedSuccessReason(command.action, reason))) {
        return {
          ok: value.ok,
          reason: reason,
          userVisibleMessage: userVisibleMessage,
          currentTime: currentTime,
          duration: duration,
          paused: value.paused,
          ended: value.ended,
          seeking: value.seeking,
          readyState: readyState,
          networkState: networkState,
          errorCode: errorCode,
          playbackRate: playbackRate,
          fullscreenActive: value.fullscreenActive,
          diagnostic: diagnostic
        };
      }
    } catch (_error) {
    }
    return this.buildFailedLiveCommandResult('invalid_result', '网页视频控制失败。');
  }

  private parseFrameHostCommandResult(
    raw: string,
    action: WebVideoFrameHostCommandAction
  ): WebVideoFrameHostCommandResult {
    if (raw.length <= 0 || raw.length > MAX_WEB_VIDEO_FRAME_HOST_RESULT_LENGTH) {
      return this.buildFailedFrameHostCommandResult('invalid_frame_host_result_length');
    }
    try {
      const value = JSON.parse(raw) as WebVideoFrameHostCommandResult;
      const reason = typeof value.reason === 'string' ? value.reason : '';
      const detail = typeof value.detail === 'string' ? value.detail : '';
      if (typeof value.ok === 'boolean' && reason.length <= MAX_WEB_VIDEO_FRAME_HOST_REASON_LENGTH &&
        detail.length <= MAX_WEB_VIDEO_FRAME_HOST_DETAIL_LENGTH &&
        (!value.ok || this.isExpectedFrameHostSuccessReason(action, reason))) {
        return {
          ok: value.ok,
          reason: reason,
          detail: detail
        };
      }
    } catch (_error) {
    }
    return this.buildFailedFrameHostCommandResult('invalid_frame_host_result');
  }

  private isExpectedFrameHostSuccessReason(action: WebVideoFrameHostCommandAction, reason: string): boolean {
    if (action === 'probe_frame_host') {
      return reason === 'frame_host_reachable';
    }
    if (action === 'enter_frame_host_presentation') {
      return reason === 'frame_host_presentation_entered';
    }
    return reason === 'frame_host_presentation_restored';
  }

  private isExpectedSuccessReason(action: WebVideoLiveCommandAction, reason: string): boolean {
    if (action === 'read_state') {
      return reason === 'live_target_reachable';
    }
    if (action === 'toggle') {
      return reason === 'pause_applied' || reason === 'play_requested';
    }
    if (action === 'seek') {
      return reason === 'seek_applied';
    }
    if (action === 'rate') {
      return reason === 'rate_applied';
    }
    if (action === 'scale') {
      return reason === 'scale_applied';
    }
    if (action === 'picture_in_picture') {
      return reason === 'picture_in_picture_already_active' ||
        reason === 'picture_in_picture_pending' || reason === 'picture_in_picture_started' ||
        reason === 'webkit_picture_in_picture_requested';
    }
    if (action === 'install_action_toolbar') {
      return reason === 'action_toolbar_installed';
    }
    if (action === 'picture_in_picture_status') {
      return reason === 'picture_in_picture_pending' || reason === 'picture_in_picture_started';
    }
    if (action === 'enter_live_presentation') {
      return reason === 'live_presentation_entered';
    }
    if (action === 'suppress_native_controls') {
      return reason === 'native_controls_suppressed';
    }
    if (action === 'restore_presentation') {
      return reason === 'presentation_restored';
    }
    return false;
  }

  private buildFailedLiveCommandResult(reason: string, message: string): WebVideoLiveCommandResult {
    return {
      ok: false,
      reason: reason,
      userVisibleMessage: message,
      currentTime: 0,
      duration: 0,
      paused: true,
      ended: false,
      seeking: false,
      readyState: 0,
      networkState: 0,
      errorCode: 0,
      playbackRate: 1,
      fullscreenActive: false,
      diagnostic: ''
    };
  }

  private buildFailedFrameHostCommandResult(reason: string): WebVideoFrameHostCommandResult {
    return {
      ok: false,
      reason: reason
    };
  }

  private delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, Math.max(0, delayMs));
    });
  }

  private unwrapJsonString(raw: string): string {
    if (raw.length >= 2 && raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') {
      try {
        const decoded = JSON.parse(raw) as string;
        if (typeof decoded === 'string') {
          return decoded;
        }
      } catch (_error) {
      }
    }
    return raw;
  }

  private buildFrameHostCommandScript(
    frameRuntimeId: string,
    action: WebVideoFrameHostCommandAction
  ): string {
    const bridgeProperty = JSON.stringify(WEB_VIDEO_FRAME_HOST_BRIDGE_PROPERTY);
    const protocol = JSON.stringify(WEB_VIDEO_FRAME_HOST_PROTOCOL);
    const runtimeId = JSON.stringify(frameRuntimeId);
    const commandAction = JSON.stringify(action);
    return `
(function () {
  var bridge = window[${bridgeProperty}];
  if (!bridge || bridge.protocol !== ${protocol} || typeof bridge.execute !== 'function') {
    return JSON.stringify({ ok: false, reason: 'frame_host_bridge_unavailable' });
  }
  try {
  return bridge.execute(JSON.stringify({
      protocol: ${protocol},
      action: ${commandAction},
      frameRuntimeId: ${runtimeId}
    }));
  } catch (_error) {
    return JSON.stringify({ ok: false, reason: 'frame_host_command_failed' });
  }
})();`;
  }

  private buildExecuteLiveCommandScript(
    target: WebVideoLiveSessionTarget,
    command: WebVideoLiveCommand
  ): string {
    const runtimeId = JSON.stringify(target.runtimeId.trim());
    const source = JSON.stringify(target.source.trim());
    const elementId = JSON.stringify(target.elementId.trim());
    const runtimeIdProperty = JSON.stringify(WEB_VIDEO_RUNTIME_ID_PROPERTY);
    const originalObjectFitProperty = JSON.stringify(WEB_VIDEO_ORIGINAL_OBJECT_FIT_PROPERTY);
    const originalObjectFitPriorityProperty = JSON.stringify(WEB_VIDEO_ORIGINAL_OBJECT_FIT_PRIORITY_PROPERTY);
    const originalControlsProperty = JSON.stringify(WEB_VIDEO_ORIGINAL_CONTROLS_PROPERTY);
    const controlsObserverProperty = JSON.stringify(WEB_VIDEO_CONTROLS_OBSERVER_PROPERTY);
    const controlsHiddenMarkerAttribute = JSON.stringify(WEB_VIDEO_CONTROLS_HIDDEN_MARKER_ATTRIBUTE);
    const originalControlsHiddenMarkerProperty =
      JSON.stringify(WEB_VIDEO_ORIGINAL_CONTROLS_HIDDEN_MARKER_PROPERTY);
    const controlsStyleElementId = JSON.stringify(WEB_VIDEO_CONTROLS_STYLE_ELEMENT_ID);
    const livePresentationProperty = JSON.stringify(WEB_VIDEO_LIVE_PRESENTATION_PROPERTY);
    const pipRequestStateProperty = JSON.stringify(WEB_VIDEO_PIP_REQUEST_STATE_PROPERTY);
    const actionToolbarProtocol = JSON.stringify(WEB_VIDEO_ACTION_TOOLBAR_PROTOCOL);
    const fullscreenRequestResultEvent = JSON.stringify(WEB_VIDEO_FULLSCREEN_REQUEST_RESULT_EVENT);
    const frameRuntimeId = JSON.stringify(target.frameRuntimeId?.trim() ?? '');
    const presentationMode = JSON.stringify(target.presentationMode ?? 'viewport_promoted');
    const action = JSON.stringify(command.action);
    const value = Number.isFinite(command.value ?? 0) ? command.value ?? 0 : 0;
  return `
(function () {
  function describeVideoDiagnostics(targetVideo) {
    if (!targetVideo) {
      return 'video=missing';
    }
    try {
      var ownerDocument = targetVideo.ownerDocument || document;
      var ownerWindow = ownerDocument && ownerDocument.defaultView ? ownerDocument.defaultView : window;
      var rect = typeof targetVideo.getBoundingClientRect === 'function' ?
        targetVideo.getBoundingClientRect() : null;
      var visualViewport = null;
      try {
        visualViewport = ownerWindow && ownerWindow.visualViewport ? ownerWindow.visualViewport : null;
      } catch (_diagnosticViewportError) {
        visualViewport = null;
      }
      var style = ownerWindow && typeof ownerWindow.getComputedStyle === 'function' ?
        ownerWindow.getComputedStyle(targetVideo) : null;
      var parent = targetVideo.parentElement || null;
      var parentStyle = parent && ownerWindow && typeof ownerWindow.getComputedStyle === 'function' ?
        ownerWindow.getComputedStyle(parent) : null;
      var fullscreenElement = ownerDocument ?
        (ownerDocument.fullscreenElement || ownerDocument.webkitFullscreenElement || null) : null;
      return 'connected=' + (targetVideo.isConnected === false ? 'no' : 'yes') +
        ',rect=' + String(Math.round(Number(rect && rect.left || 0))) + 'x' +
        String(Math.round(Number(rect && rect.top || 0))) + '+' +
        String(Math.round(Number(rect && rect.width || 0))) + 'x' +
        String(Math.round(Number(rect && rect.height || 0))) +
        ',viewport=' + String(Math.round(Number(ownerWindow && ownerWindow.innerWidth || 0))) + 'x' +
        String(Math.round(Number(ownerWindow && ownerWindow.innerHeight || 0))) +
        ',visual=' + String(Math.round(Number(visualViewport && visualViewport.width || 0))) + 'x' +
        String(Math.round(Number(visualViewport && visualViewport.height || 0))) +
        ',style=' + String(style && style.position || '') + '/' + String(style && style.display || '') + '/' +
        String(style && style.visibility || '') + '/' + String(style && style.opacity || '') +
        ',fit=' + String(style && style.objectFit || '') +
        ',parent=' + String(parentStyle && parentStyle.overflow || '') + '/' +
        String(parentStyle && parentStyle.transform || '') +
        ',media=' + String(Number(targetVideo.videoWidth || 0)) + 'x' +
        String(Number(targetVideo.videoHeight || 0)) +
        ',ready=' + String(Number(targetVideo.readyState || 0)) +
        ',network=' + String(Number(targetVideo.networkState || 0)) +
        ',paused=' + (targetVideo.paused === true ? 'yes' : 'no') +
        ',time=' + String(Math.round(Number(targetVideo.currentTime || 0) * 10) / 10) +
        ',error=' + String(Number(targetVideo.error && targetVideo.error.code || 0)) +
        ',docHidden=' + (ownerDocument.hidden === true ? 'yes' : 'no') +
        ',docFs=' + (fullscreenElement === targetVideo ? 'yes' : 'no');
    } catch (_diagnosticError) {
      return 'video=diagnostic_error';
    }
  }
  function result(ok, reason, message, video) {
    var ownerDocument = video && (video.ownerDocument || document);
    var fullscreenElement = ownerDocument ?
      (ownerDocument.fullscreenElement || ownerDocument.webkitFullscreenElement || null) : null;
    var fullscreenActive = false;
    if (video) {
      fullscreenActive = fullscreenElement === video || video.webkitDisplayingFullscreen === true;
      if (!fullscreenActive && fullscreenElement && typeof fullscreenElement.contains === 'function') {
        try {
          fullscreenActive = fullscreenElement.contains(video);
        } catch (_fullscreenContainsError) {
        }
      }
    }
    return JSON.stringify({
      ok: ok === true,
      reason: reason || '',
      userVisibleMessage: message || '',
      currentTime: video && Number.isFinite(Number(video.currentTime)) ? Number(video.currentTime) : 0,
      duration: video && Number.isFinite(Number(video.duration)) ? Number(video.duration) : 0,
      paused: !video || video.paused !== false,
      ended: !!video && video.ended === true,
      seeking: !!video && video.seeking === true,
      readyState: video && Number.isFinite(Number(video.readyState)) ? Number(video.readyState) : 0,
      networkState: video && Number.isFinite(Number(video.networkState)) ? Number(video.networkState) : 0,
      errorCode: video && video.error && Number.isFinite(Number(video.error.code)) ? Number(video.error.code) : 0,
      playbackRate: video && Number.isFinite(Number(video.playbackRate)) ? Number(video.playbackRate) : 1,
      fullscreenActive: fullscreenActive,
      diagnostic: describeVideoDiagnostics(video)
    });
  }
  function collectVideos(root, output) {
    try {
      var videos = root.querySelectorAll ? root.querySelectorAll('video') : [];
      for (var index = 0; index < videos.length; index += 1) {
        output.push(videos[index]);
      }
      var frames = root.querySelectorAll ? root.querySelectorAll('iframe,frame') : [];
      for (var frameIndex = 0; frameIndex < frames.length; frameIndex += 1) {
        try {
          var doc = frames[frameIndex].contentDocument;
          if (doc) {
            collectVideos(doc, output);
          }
        } catch (_frameError) {
        }
      }
    } catch (_error) {
    }
  }
  var expectedRuntimeId = ${runtimeId};
  var expectedSource = ${source};
  var expectedElementId = ${elementId};
  var runtimeIdProperty = ${runtimeIdProperty};
  var commandAction = ${action};
  var commandValue = ${value};
  var requestedPresentationMode = ${presentationMode};
  var liveWatchdogIntervalMs = 180;
  var liveWatchdogRecoveryLimit = 40;
  var livePresentationRegistryProperty = '__airaVideoAssistantLivePresentationRegistry';
  var videos = [];
  collectVideos(document, videos);
  var matches = videos.filter(function (video) {
    if (String(video[runtimeIdProperty] || '') !== expectedRuntimeId) {
      return false;
    }
    if (commandAction === 'read_state' && expectedElementId.length > 0 &&
      String(video.id || '') !== expectedElementId) {
      return false;
    }
    if (commandAction === 'read_state' && expectedSource.length > 0 &&
      String(video.currentSrc || video.src || '') !== expectedSource) {
      return false;
    }
    return true;
  });
  if (matches.length > 1) {
    return result(false, 'runtime_identity_ambiguous',
      '当前网页视频会话已经变化。', null);
  }
  if (commandAction === 'read_state') {
    var readableVideo = matches.length === 1 ? matches[0] : null;
    if (!readableVideo) {
      return result(false, 'runtime_identity_missing', '当前网页视频会话已经变化。', null);
    }
    return result(true, 'live_target_reachable', '', readableVideo);
  }
  var livePresentationRegistry = window[livePresentationRegistryProperty];
  if (!livePresentationRegistry || typeof livePresentationRegistry !== 'object') {
    livePresentationRegistry = Object.create(null);
    window[livePresentationRegistryProperty] = livePresentationRegistry;
  }
  var registeredPresentationState = livePresentationRegistry[expectedRuntimeId];
  var video = matches.length === 1 ? matches[0] :
    (registeredPresentationState && registeredPresentationState.targetVideo ?
      registeredPresentationState.targetVideo : null);
  if (!video) {
    return result(false, 'runtime_identity_missing', '当前网页视频会话已经变化。', null);
  }
  var originalObjectFitProperty = ${originalObjectFitProperty};
  var originalObjectFitPriorityProperty = ${originalObjectFitPriorityProperty};
  var originalControlsProperty = ${originalControlsProperty};
  var controlsObserverProperty = ${controlsObserverProperty};
  var controlsHiddenMarkerAttribute = ${controlsHiddenMarkerAttribute};
  var originalControlsHiddenMarkerProperty = ${originalControlsHiddenMarkerProperty};
  var controlsStyleElementId = ${controlsStyleElementId};
  var livePresentationProperty = ${livePresentationProperty};
  var pipRequestStateProperty = ${pipRequestStateProperty};
  var actionToolbarProtocol = ${actionToolbarProtocol};
  var fullscreenRequestResultEvent = ${fullscreenRequestResultEvent};
  var expectedFrameRuntimeId = ${frameRuntimeId};
  // Distance kept between the action toolbar and the video's bottom edge, so the buttons sit
  // clear of the picture, plus the margin kept from the viewport edge when clamping.
  var actionToolbarVideoGap = 28;
  var actionToolbarViewportEdgeGap = 8;
  var actionToolbarDragStartDistance = 4;
  var lastPresentationFailureReason = '';
  var lastPresentationVerificationDetail = '';
  function rememberObjectFit(targetVideo) {
    var media = targetVideo || video;
    if (typeof media[originalObjectFitProperty] === 'string') {
      return;
    }
    media[originalObjectFitProperty] = String(media.style.getPropertyValue('object-fit') || '');
    media[originalObjectFitPriorityProperty] = String(media.style.getPropertyPriority('object-fit') || '');
  }
  function restoreObjectFit(targetVideo) {
    var media = targetVideo || video;
    if (typeof media[originalObjectFitProperty] !== 'string') {
      return;
    }
    var originalValue = String(media[originalObjectFitProperty] || '');
    var originalPriority = String(media[originalObjectFitPriorityProperty] || '');
    if (originalValue.length > 0) {
      media.style.setProperty('object-fit', originalValue, originalPriority);
    } else {
      media.style.removeProperty('object-fit');
    }
    try {
      delete media[originalObjectFitProperty];
      delete media[originalObjectFitPriorityProperty];
    } catch (_deleteError) {
      media[originalObjectFitProperty] = undefined;
      media[originalObjectFitPriorityProperty] = undefined;
    }
  }
  function rememberNativeControls(targetVideo) {
    var media = targetVideo || video;
    if (typeof media[originalControlsProperty] === 'boolean') {
      return;
    }
    media[originalControlsProperty] = media.controls === true;
  }
  function rememberControlsHiddenMarker(targetVideo) {
    var media = targetVideo || video;
    if (media[originalControlsHiddenMarkerProperty] &&
        media[originalControlsHiddenMarkerProperty].remembered === true) {
      return;
    }
    media[originalControlsHiddenMarkerProperty] = {
      remembered: true,
      present: media.hasAttribute(controlsHiddenMarkerAttribute),
      value: String(media.getAttribute(controlsHiddenMarkerAttribute) || '')
    };
  }
  function ensureNativeControlsStyle(targetVideo) {
    var media = targetVideo || video;
    try {
      var ownerDocument = media.ownerDocument || document;
      var styleElement = ownerDocument.getElementById(controlsStyleElementId);
      if (!styleElement) {
        styleElement = ownerDocument.createElement('style');
        styleElement.id = controlsStyleElementId;
        var selectorPrefix = 'video[' + controlsHiddenMarkerAttribute + ']';
        styleElement.textContent = [
          selectorPrefix + '::-webkit-media-controls',
          selectorPrefix + '::-webkit-media-controls-enclosure',
          selectorPrefix + '::-webkit-media-controls-overlay-enclosure',
          selectorPrefix + '::-webkit-media-controls-panel',
          selectorPrefix + '::-webkit-media-controls-play-button',
          selectorPrefix + '::-webkit-media-controls-overlay-play-button',
          selectorPrefix + '::-webkit-media-controls-start-playback-button',
          selectorPrefix + '::-webkit-media-controls-timeline',
          selectorPrefix + '::-webkit-media-controls-current-time-display',
          selectorPrefix + '::-webkit-media-controls-time-remaining-display',
          selectorPrefix + '::-webkit-media-controls-mute-button',
          selectorPrefix + '::-webkit-media-controls-volume-slider',
          selectorPrefix + '::-webkit-media-controls-fullscreen-button'
        ].join(',') +
          '{-webkit-appearance:none!important;display:none!important;visibility:hidden!important;' +
          'opacity:0!important;pointer-events:none!important;}';
        var styleHost = ownerDocument.head || ownerDocument.documentElement;
        if (!styleHost) {
          return false;
        }
        styleHost.appendChild(styleElement);
      }
      return true;
    } catch (_styleError) {
      return false;
    }
  }
  function enforceNativeControlsHidden(targetVideo) {
    var media = targetVideo || video;
    try {
      media.controls = false;
      media.removeAttribute('controls');
      if (media.getAttribute(controlsHiddenMarkerAttribute) !== 'true') {
        media.setAttribute(controlsHiddenMarkerAttribute, 'true');
      }
    } catch (_controlsError) {
    }
  }
  function suppressNativeControls(targetVideo) {
    var media = targetVideo || video;
    rememberNativeControls(media);
    rememberControlsHiddenMarker(media);
    var styleReady = ensureNativeControlsStyle(media);
    enforceNativeControlsHidden(media);
    if (!media[controlsObserverProperty]) {
      try {
        var ownerWindow = media.ownerDocument && media.ownerDocument.defaultView ?
          media.ownerDocument.defaultView : window;
        var Observer = ownerWindow && typeof ownerWindow.MutationObserver === 'function' ?
          ownerWindow.MutationObserver : null;
        if (Observer) {
          var observer = new Observer(function () {
            if (media.controls === true || media.hasAttribute('controls') ||
                media.getAttribute(controlsHiddenMarkerAttribute) !== 'true') {
              enforceNativeControlsHidden(media);
            }
          });
          observer.observe(media, {
            attributes: true,
            attributeFilter: ['controls', controlsHiddenMarkerAttribute]
          });
          media[controlsObserverProperty] = observer;
        }
      } catch (_observerError) {
      }
    }
    return styleReady && media.controls === false && !media.hasAttribute('controls') &&
      media.getAttribute(controlsHiddenMarkerAttribute) === 'true';
  }
  function restoreNativeControls(targetVideo) {
    var media = targetVideo || video;
    var observer = media[controlsObserverProperty];
    if (observer && typeof observer.disconnect === 'function') {
      try {
        observer.disconnect();
      } catch (_disconnectError) {
      }
    }
    try {
      delete media[controlsObserverProperty];
    } catch (_deleteObserverError) {
      media[controlsObserverProperty] = undefined;
    }
    var originalMarker = media[originalControlsHiddenMarkerProperty];
    if (originalMarker && originalMarker.remembered === true) {
      try {
        if (originalMarker.present === true) {
          media.setAttribute(controlsHiddenMarkerAttribute, String(originalMarker.value || ''));
        } else {
          media.removeAttribute(controlsHiddenMarkerAttribute);
        }
      } catch (_restoreMarkerError) {
      }
      try {
        delete media[originalControlsHiddenMarkerProperty];
      } catch (_deleteMarkerError) {
        media[originalControlsHiddenMarkerProperty] = undefined;
      }
    }
    if (typeof media[originalControlsProperty] !== 'boolean') {
      return;
    }
    var originalControls = media[originalControlsProperty] === true;
    try {
      media.controls = originalControls;
      if (originalControls) {
        media.setAttribute('controls', '');
      } else {
        media.removeAttribute('controls');
      }
    } catch (_restoreControlsError) {
    }
    try {
      delete media[originalControlsProperty];
    } catch (_deleteControlsError) {
      media[originalControlsProperty] = undefined;
    }
  }
  function rememberStyle(element, propertyNames, snapshots) {
    if (!element || !element.style) {
      return;
    }
    for (var existingIndex = 0; existingIndex < snapshots.length; existingIndex += 1) {
      if (snapshots[existingIndex].element === element) {
        return;
      }
    }
    var properties = [];
    for (var propertyIndex = 0; propertyIndex < propertyNames.length; propertyIndex += 1) {
      var propertyName = propertyNames[propertyIndex];
      properties.push({
        name: propertyName,
        value: String(element.style.getPropertyValue(propertyName) || ''),
        priority: String(element.style.getPropertyPriority(propertyName) || '')
      });
    }
    snapshots.push({ element: element, properties: properties });
  }
  function applyImportantStyles(element, values) {
    if (!element || !element.style) {
      return;
    }
    for (var propertyName in values) {
      if (Object.prototype.hasOwnProperty.call(values, propertyName)) {
        element.style.setProperty(propertyName, String(values[propertyName]), 'important');
      }
    }
  }
  function resolveLiveViewportGeometry(ownerDocument) {
    var ownerWindow = ownerDocument && ownerDocument.defaultView ? ownerDocument.defaultView : window;
    var documentElement = ownerDocument && ownerDocument.documentElement ? ownerDocument.documentElement : null;
    var viewport = null;
    try {
      viewport = ownerWindow.visualViewport || null;
    } catch (_viewportError) {
      viewport = null;
    }
    var layoutWidth = Math.max(
      0,
      Number(ownerWindow.innerWidth || 0),
      Number(documentElement && documentElement.clientWidth || 0)
    );
    var layoutHeight = Math.max(
      0,
      Number(ownerWindow.innerHeight || 0),
      Number(documentElement && documentElement.clientHeight || 0)
    );
    var visualWidth = Number(viewport && viewport.width || 0);
    var visualHeight = Number(viewport && viewport.height || 0);
    var visualLeft = Number(viewport && viewport.offsetLeft || 0);
    var visualTop = Number(viewport && viewport.offsetTop || 0);
    if (!Number.isFinite(visualWidth) || visualWidth <= 0) {
      visualWidth = layoutWidth;
    }
    if (!Number.isFinite(visualHeight) || visualHeight <= 0) {
      visualHeight = layoutHeight;
    }
    if (!Number.isFinite(visualLeft)) {
      visualLeft = 0;
    }
    if (!Number.isFinite(visualTop)) {
      visualTop = 0;
    }
    // ArkWeb on large screens can keep the pre-fullscreen safe-area offset on
    // visualViewport even after the Web component has expanded to the window.
    // A fixed takeover surface must use the layout viewport's origin whenever
    // the visual viewport already covers that layout dimension; retaining the
    // stale offset pushes the native video surface outside the window.
    if (visualWidth >= layoutWidth - 1) {
      visualLeft = 0;
    }
    if (visualHeight >= layoutHeight - 1) {
      visualTop = 0;
    }
    var left = Math.min(0, visualLeft);
    var top = Math.min(0, visualTop);
    var right = Math.max(layoutWidth, visualLeft + visualWidth);
    var bottom = Math.max(layoutHeight, visualTop + visualHeight);
    return {
      left: Math.round(left * 1000) / 1000,
      top: Math.round(top * 1000) / 1000,
      width: Math.max(1, Math.round((right - left) * 1000) / 1000),
      height: Math.max(1, Math.round((bottom - top) * 1000) / 1000)
    };
  }
  function applyLiveViewportGeometry(element) {
    if (!element || !element.style) {
      return;
    }
    var geometry = resolveLiveViewportGeometry(element.ownerDocument || document);
    applyImportantStyles(element, {
      top: geometry.top + 'px',
      right: 'auto',
      bottom: 'auto',
      left: geometry.left + 'px',
      width: geometry.width + 'px',
      height: geometry.height + 'px'
    });
  }
  function resolveLiveVideoGeometry(videoElement, state) {
    var viewport = resolveLiveViewportGeometry(videoElement.ownerDocument || document);
    var scaleMode = state && typeof state.scaleMode === 'string' ? state.scaleMode : 'contain';
    var videoWidth = Number(videoElement.videoWidth || state && state.videoWidth || 0);
    var videoHeight = Number(videoElement.videoHeight || state && state.videoHeight || 0);
    if (scaleMode !== 'contain' || videoWidth <= 0 || videoHeight <= 0) {
      return viewport;
    }
    var scale = Math.min(viewport.width / videoWidth, viewport.height / videoHeight);
    var width = Math.max(1, videoWidth * scale);
    var height = Math.max(1, videoHeight * scale);
    return {
      left: viewport.left + (viewport.width - width) / 2,
      top: viewport.top + (viewport.height - height) / 2,
      width: width,
      height: height
    };
  }
  function applyLiveVideoGeometry(videoElement, state) {
    if (!videoElement || !videoElement.style) {
      return;
    }
    var geometry = resolveLiveVideoGeometry(videoElement, state);
    applyImportantStyles(videoElement, {
      top: geometry.top + 'px',
      right: 'auto',
      bottom: 'auto',
      left: geometry.left + 'px',
      width: geometry.width + 'px',
      height: geometry.height + 'px'
    });
  }
  function refreshLivePresentationGeometry(videoElement, state) {
    if (state && state.presentationMode === 'preserve_surface') {
      return;
    }
    applyLiveVideoGeometry(videoElement, state);
    var currentDocument = videoElement && (videoElement.ownerDocument || document);
    while (currentDocument) {
      var frameElement = null;
      try {
        frameElement = currentDocument.defaultView && currentDocument.defaultView.frameElement ?
          currentDocument.defaultView.frameElement : null;
      } catch (_frameLookupError) {
        frameElement = null;
      }
      if (!frameElement) {
        break;
      }
      applyLiveViewportGeometry(frameElement);
      currentDocument = frameElement.ownerDocument;
    }
  }
  function resolveTopLiveDocument(videoElement) {
    var currentDocument = videoElement && (videoElement.ownerDocument || document);
    var lastDocument = currentDocument || document;
    while (currentDocument) {
      lastDocument = currentDocument;
      var frameElement = null;
      try {
        frameElement = currentDocument.defaultView && currentDocument.defaultView.frameElement ?
          currentDocument.defaultView.frameElement : null;
      } catch (_frameLookupError) {
        frameElement = null;
      }
      if (!frameElement) {
        break;
      }
      currentDocument = frameElement.ownerDocument;
    }
    return lastDocument || document;
  }
  function ensureLiveBackdrop(state) {
    if (!state || state.active !== true) {
      return false;
    }
    if (state.presentationMode === 'preserve_surface') {
      return true;
    }
    try {
      var targetVideo = state.targetVideo;
      var ownerDocument = resolveTopLiveDocument(targetVideo);
      var backdrop = state.backdrop;
      if (!backdrop || backdrop.ownerDocument !== ownerDocument) {
        backdrop = ownerDocument.createElement('div');
        backdrop.setAttribute('data-aira-video-assistant-backdrop', String(state.runtimeId || 'active'));
        state.backdrop = backdrop;
      }
      applyImportantStyles(backdrop, {
        position: 'fixed', top: '0', right: '0', bottom: '0', left: '0', width: '100%', height: '100%',
        margin: '0', padding: '0', display: 'block', visibility: 'visible',
        opacity: '1', transform: 'none', filter: 'none', perspective: 'none', clip: 'auto',
        'clip-path': 'none', contain: 'none', isolation: 'isolate', overflow: 'hidden',
        'overflow-x': 'hidden', 'overflow-y': 'hidden', 'pointer-events': 'none',
        'box-sizing': 'border-box', 'background-color': '#000', 'z-index': '2147483646'
      });
      applyLiveViewportGeometry(backdrop);
      if (backdrop.isConnected === false) {
        var host = ownerDocument.body || ownerDocument.documentElement;
        if (!host) {
          return false;
        }
        host.appendChild(backdrop);
      }
      return backdrop.isConnected !== false;
    } catch (_backdropError) {
      return false;
    }
  }
  function removeLiveBackdrop(state) {
    var backdrop = state && state.backdrop ? state.backdrop : null;
    if (backdrop && backdrop.parentNode) {
      try {
        backdrop.parentNode.removeChild(backdrop);
      } catch (_removeBackdropError) {
      }
    }
    if (state) {
      state.backdrop = null;
    }
  }
  function rememberLiveControlTarget(state, targetVideo) {
    if (!state || !targetVideo) {
      return;
    }
    var targets = state.controlTargets || [];
    if (targets.indexOf(targetVideo) < 0) {
      targets.push(targetVideo);
    }
    state.controlTargets = targets;
  }
  function restoreLiveControlTargets(state) {
    var targets = state && state.controlTargets ? state.controlTargets : [];
    for (var index = targets.length - 1; index >= 0; index -= 1) {
      restoreObjectFit(targets[index]);
      restoreNativeControls(targets[index]);
    }
    if (state) {
      state.controlTargets = [];
    }
  }
  function disconnectLiveStyleObservers(state) {
    var observers = state && state.styleObservers ? state.styleObservers : [];
    for (var index = observers.length - 1; index >= 0; index -= 1) {
      var observer = observers[index] && observers[index].observer ? observers[index].observer : null;
      if (observer && typeof observer.disconnect === 'function') {
        try {
          observer.disconnect();
        } catch (_disconnectStyleObserverError) {
        }
      }
    }
    if (state) {
      state.styleObservers = [];
    }
  }
  function ensureLiveStyleObservers(videoElement, state) {
    if (!videoElement || !state || state.active !== true) {
      return;
    }
    var tracked = state.styleObservers || [];
    var targets = [];
    var currentElement = videoElement;
    while (currentElement) {
      targets.push(currentElement);
      if (currentElement === currentElement.ownerDocument.documentElement) {
        break;
      }
      currentElement = currentElement.parentElement;
    }
    for (var targetIndex = 0; targetIndex < targets.length; targetIndex += 1) {
      var target = targets[targetIndex];
      var exists = false;
      for (var trackedIndex = 0; trackedIndex < tracked.length; trackedIndex += 1) {
        if (tracked[trackedIndex].target === target) {
          exists = true;
          break;
        }
      }
      if (exists) {
        continue;
      }
      try {
        var ownerWindow = target.ownerDocument && target.ownerDocument.defaultView ?
          target.ownerDocument.defaultView : window;
        var Observer = ownerWindow && typeof ownerWindow.MutationObserver === 'function' ?
          ownerWindow.MutationObserver : null;
        if (!Observer) {
          continue;
        }
        var observer = new Observer(function () {
          if (state.active !== true || !state.targetVideo || state.targetVideo.isConnected === false) {
            return;
          }
          if (!verifyLivePresentation(state.targetVideo, state)) {
            applyLivePresentationStyles(state.targetVideo, state);
            refreshLivePresentationGeometry(state.targetVideo, state);
          }
        });
        observer.observe(target, {
          attributes: true,
          attributeFilter: ['style', 'class', 'hidden']
        });
        tracked.push({ target: target, observer: observer });
      } catch (_styleObserverError) {
      }
    }
    state.styleObservers = tracked;
  }
  function applyLivePresentationStyles(videoElement, state) {
    if (!videoElement || !state || !state.surfaceProperties || !state.ancestorProperties ||
        !state.documentProperties) {
      return false;
    }
    try {
      if (state.presentationMode === 'preserve_surface') {
        rememberLiveControlTarget(state, videoElement);
        return suppressNativeControls(videoElement);
      }
      rememberStyle(videoElement, state.surfaceProperties, state.snapshots);
      var ownerDocument = videoElement.ownerDocument || document;
      var currentDocument = ownerDocument;
      var currentElement = videoElement;
      while (currentDocument) {
        var documentElement = currentDocument.documentElement;
        var body = currentDocument.body;
        rememberStyle(documentElement, state.documentProperties, state.snapshots);
        rememberStyle(body, state.documentProperties, state.snapshots);
        applyImportantStyles(documentElement, {
          width: '100%', margin: '0', padding: '0', overflow: 'hidden',
          'overflow-x': 'hidden', 'overflow-y': 'hidden', 'background-color': '#000'
        });
        applyImportantStyles(body, {
          width: '100%', margin: '0', padding: '0', overflow: 'hidden',
          'overflow-x': 'hidden', 'overflow-y': 'hidden', 'background-color': '#000'
        });
        var ancestor = currentElement.parentElement;
        while (ancestor) {
          if (ancestor !== body && ancestor !== documentElement) {
            rememberStyle(ancestor, state.ancestorProperties, state.snapshots);
            applyImportantStyles(ancestor, {
              position: 'relative', 'z-index': 'auto', visibility: 'visible', opacity: '1',
              transform: 'none', filter: 'none', perspective: 'none', clip: 'auto', 'clip-path': 'none',
              contain: 'none', isolation: 'auto', overflow: 'visible', 'overflow-x': 'visible',
              'overflow-y': 'visible'
            });
          }
          if (ancestor === documentElement) {
            break;
          }
          ancestor = ancestor.parentElement;
        }
        var frameElement = null;
        try {
          frameElement = currentDocument.defaultView && currentDocument.defaultView.frameElement ?
            currentDocument.defaultView.frameElement : null;
        } catch (_frameLookupError) {
          frameElement = null;
        }
        if (!frameElement) {
          break;
        }
        rememberStyle(frameElement, state.surfaceProperties, state.snapshots);
        applyImportantStyles(frameElement, {
          position: 'fixed',
          'min-width': '0', 'min-height': '0', 'max-width': 'none', 'max-height': 'none', margin: '0',
          padding: '0', 'z-index': '2147483647', display: 'block', visibility: 'visible', opacity: '1',
          transform: 'none', filter: 'none', perspective: 'none', clip: 'auto', 'clip-path': 'none',
          contain: 'none', isolation: 'auto', overflow: 'visible', 'overflow-x': 'visible',
          'overflow-y': 'visible', 'pointer-events': 'none', 'box-sizing': 'border-box',
          'background-color': '#000'
        });
        applyLiveViewportGeometry(frameElement);
        currentElement = frameElement;
        currentDocument = frameElement.ownerDocument;
      }
      applyImportantStyles(videoElement, {
        position: 'fixed',
        'min-width': '0', 'min-height': '0', 'max-width': 'none', 'max-height': 'none', margin: '0',
        padding: '0', 'z-index': '2147483647', display: 'block', visibility: 'visible', opacity: '1',
        transform: 'none', filter: 'none', perspective: 'none', clip: 'auto', 'clip-path': 'none',
        contain: 'none', isolation: 'auto', overflow: 'hidden', 'overflow-x': 'hidden',
        'overflow-y': 'hidden', 'pointer-events': 'none', 'box-sizing': 'border-box',
        'object-fit': state.scaleMode || 'contain', 'object-position': 'center center',
        'background-color': '#000'
      });
      applyLiveVideoGeometry(videoElement, state);
      rememberLiveControlTarget(state, videoElement);
      var backdropReady = ensureLiveBackdrop(state);
      var controlsHidden = suppressNativeControls(videoElement);
      ensureLiveStyleObservers(videoElement, state);
      return backdropReady && controlsHidden;
    } catch (_applyPresentationError) {
      return false;
    }
  }
  function verifyLivePresentation(videoElement, state) {
    if (!videoElement || !state || state.active !== true || videoElement.isConnected === false ||
        videoElement.ownerDocument === null) {
      lastPresentationVerificationDetail = 'target_unusable';
      return false;
    }
    try {
      if (state.presentationMode === 'preserve_surface') {
        var preservedRect = videoElement.getBoundingClientRect();
        var preservedWindow = videoElement.ownerDocument.defaultView || window;
        var preservedStyle = typeof preservedWindow.getComputedStyle === 'function' ?
          preservedWindow.getComputedStyle(videoElement) : null;
        var preservedViewportWidth = Math.max(0, Number(preservedWindow.innerWidth || 0));
        var preservedViewportHeight = Math.max(0, Number(preservedWindow.innerHeight || 0));
        var preservedValid = (!preservedStyle || (preservedStyle.display !== 'none' &&
          preservedStyle.visibility !== 'hidden' && Number.parseFloat(preservedStyle.opacity || '1') > 0.02)) &&
          videoElement.controls === false && !videoElement.hasAttribute('controls') &&
          videoElement.getAttribute(controlsHiddenMarkerAttribute) === 'true' &&
          Number(preservedRect.width || 0) >= 8 && Number(preservedRect.height || 0) >= 8 &&
          Number(preservedRect.right || 0) > 0 && Number(preservedRect.bottom || 0) > 0 &&
          Number(preservedRect.left || 0) < preservedViewportWidth &&
          Number(preservedRect.top || 0) < preservedViewportHeight;
        if (!preservedValid) {
          lastPresentationVerificationDetail = 'preserve_rect=' + String(Math.round(Number(preservedRect.width || 0))) + 'x' +
            String(Math.round(Number(preservedRect.height || 0))) + ',viewport=' +
            String(Math.round(preservedViewportWidth)) + 'x' + String(Math.round(preservedViewportHeight)) +
            ',controls=' + (videoElement.controls === false ? 'off' : 'on') +
            ',marker=' + (videoElement.getAttribute(controlsHiddenMarkerAttribute) === 'true' ? 'yes' : 'no');
        }
        return preservedValid;
      }
      if (!state.backdrop || state.backdrop.isConnected === false) {
        lastPresentationVerificationDetail = 'backdrop_missing';
        return false;
      }
      var geometry = resolveLiveVideoGeometry(videoElement, state);
      var rect = videoElement.getBoundingClientRect();
      var widthTolerance = Math.max(6, geometry.width * 0.08);
      var heightTolerance = Math.max(6, geometry.height * 0.08);
      var ownerWindow = videoElement.ownerDocument && videoElement.ownerDocument.defaultView ?
        videoElement.ownerDocument.defaultView : window;
      var style = ownerWindow && typeof ownerWindow.getComputedStyle === 'function' ?
        ownerWindow.getComputedStyle(videoElement) : null;
      var styleValid = !style || (style.position === 'fixed' && style.display !== 'none' &&
        style.visibility !== 'hidden' && Number.parseFloat(style.opacity || '1') > 0.02);
      var controlsValid = videoElement.controls === false && !videoElement.hasAttribute('controls') &&
        videoElement.getAttribute(controlsHiddenMarkerAttribute) === 'true';
      var geometryValid =
        Math.abs(Number(rect.left || 0) - geometry.left) <= widthTolerance &&
        Math.abs(Number(rect.top || 0) - geometry.top) <= heightTolerance &&
        Math.abs(Number(rect.width || 0) - geometry.width) <= widthTolerance &&
        Math.abs(Number(rect.height || 0) - geometry.height) <= heightTolerance;
      var valid = styleValid && controlsValid && geometryValid;
      if (!valid) {
        lastPresentationVerificationDetail = 'geometry=' + (geometryValid ? 'ok' : 'bad') +
          ',style=' + (styleValid ? 'ok' : 'bad') + ',controls=' + (controlsValid ? 'ok' : 'bad') +
          ',rect=' + String(Math.round(Number(rect.width || 0))) + 'x' + String(Math.round(Number(rect.height || 0))) +
          ',expected=' + String(Math.round(geometry.width)) + 'x' + String(Math.round(geometry.height)) +
          ',viewport=' + String(Math.round(Number(ownerWindow.innerWidth || 0))) + 'x' +
          String(Math.round(Number(ownerWindow.innerHeight || 0)));
      }
      return valid;
    } catch (_verifyPresentationError) {
      lastPresentationVerificationDetail = 'verification_exception';
      return false;
    }
  }
  function updateLiveVideoIdentity(videoElement, state) {
    if (!videoElement || !state) {
      return;
    }
    var source = String(videoElement.currentSrc || videoElement.src || '');
    var poster = String(videoElement.poster || videoElement.getAttribute('poster') || '');
    var width = Number(videoElement.videoWidth || 0);
    var height = Number(videoElement.videoHeight || 0);
    var duration = Number(videoElement.duration || 0);
    if (source.length > 0) {
      state.source = source;
    }
    if (poster.length > 0) {
      state.poster = poster;
    }
    if (width > 0 && height > 0) {
      state.videoWidth = width;
      state.videoHeight = height;
    }
    if (Number.isFinite(duration) && duration > 0) {
      state.duration = duration;
    }
  }
  function updateLiveVideoSignature(videoElement, state) {
    if (!videoElement || !state) {
      return;
    }
    updateLiveVideoIdentity(videoElement, state);
    var currentTime = Number(videoElement.currentTime || 0);
    var playbackRate = Number(videoElement.playbackRate || 1);
    if (Number.isFinite(currentTime) && currentTime >= 0 && videoElement.paused === false) {
      state.resumeTime = currentTime;
      state.playbackIntent = 'playing';
    }
    if (Number.isFinite(playbackRate) && playbackRate > 0) {
      state.playbackRate = playbackRate;
    }
  }
  function isLiveVideoIdentityUsable(videoElement) {
    if (!videoElement || videoElement.isConnected === false) {
      return false;
    }
    try {
      var source = String(videoElement.currentSrc || videoElement.src || '');
      return source.length > 0 && Number(videoElement.readyState || 0) >= 1 &&
        Number(videoElement.videoWidth || 0) > 0 && Number(videoElement.videoHeight || 0) > 0;
    } catch (_videoIdentityError) {
      return false;
    }
  }
  function scoreLiveReplacement(videoElement, state) {
    if (!videoElement || videoElement === state.targetVideo || videoElement.isConnected === false) {
      return -1;
    }
    try {
      var rect = videoElement.getBoundingClientRect();
      if (Number(rect.width || 0) < 8 || Number(rect.height || 0) < 8) {
        return -1;
      }
      var score = 0;
      var source = String(videoElement.currentSrc || videoElement.src || '');
      var poster = String(videoElement.poster || videoElement.getAttribute('poster') || '');
      var readyState = Number(videoElement.readyState || 0);
      var videoWidth = Number(videoElement.videoWidth || 0);
      var videoHeight = Number(videoElement.videoHeight || 0);
      var duration = Number(videoElement.duration || 0);
      if (source.length <= 0 || readyState < 2 || videoWidth <= 0 || videoHeight <= 0) {
        return -1;
      }
      var identityScore = 0;
      if (videoElement.paused === false && videoElement.ended !== true) {
        score += 1000;
      }
      if (state.source && source && state.source === source) {
        identityScore += 800;
      }
      if (state.poster && poster && state.poster === poster) {
        identityScore += 360;
      }
      var dimensionsMatch = state.videoWidth > 0 && state.videoHeight > 0 &&
          Math.abs(videoWidth - state.videoWidth) <= 2 &&
          Math.abs(videoHeight - state.videoHeight) <= 2;
      if (dimensionsMatch) {
        identityScore += 240;
      }
      var durationMatches = Number(state.duration || 0) > 0 && Number.isFinite(duration) && duration > 0 &&
        Math.abs(duration - Number(state.duration || 0)) <= 0.75;
      if (durationMatches) {
        identityScore += 220;
      }
      if (identityScore < 360 && !(dimensionsMatch && durationMatches)) {
        return -1;
      }
      score += identityScore;
      score += 100;
      return score;
    } catch (_replacementScoreError) {
      return -1;
    }
  }
  function findLiveReplacement(state) {
    var candidates = [];
    collectVideos(document, candidates);
    var selected = null;
    var selectedScore = -1;
    var ambiguous = false;
    for (var index = 0; index < candidates.length; index += 1) {
      var candidate = candidates[index];
      var score = scoreLiveReplacement(candidate, state);
      if (score > selectedScore) {
        selected = candidate;
        selectedScore = score;
        ambiguous = false;
      } else if (score >= 0 && score === selectedScore) {
        ambiguous = true;
      }
    }
    return selected && selectedScore >= 300 && !ambiguous ? selected : null;
  }
  function restoreLivePlaybackIntent(videoElement, state) {
    if (!videoElement || !state || videoElement.isConnected === false) {
      return;
    }
    try {
      var playbackRate = Number(state.playbackRate || 1);
      if (Number.isFinite(playbackRate) && playbackRate > 0 &&
          Math.abs(Number(videoElement.playbackRate || 1) - playbackRate) > 0.01) {
        videoElement.playbackRate = playbackRate;
      }
    } catch (_restoreRateError) {
    }
    try {
      var resumeTime = Number(state.resumeTime || 0);
      var duration = Number(videoElement.duration || 0);
      if (resumeTime > 0 && Number(videoElement.readyState || 0) >= 2 &&
          Math.abs(Number(videoElement.currentTime || 0) - resumeTime) > 0.75) {
        videoElement.currentTime = Number.isFinite(duration) && duration > 0 ?
          Math.min(duration, resumeTime) : resumeTime;
      }
    } catch (_restoreTimeError) {
    }
    if (state.playbackIntent !== 'playing' || videoElement.ended === true ||
        videoElement.paused !== true || Number(videoElement.readyState || 0) < 2 ||
        state.playAttemptInFlight === true || Number(state.resumeAttempts || 0) >= 8) {
      return;
    }
    try {
      state.playAttemptInFlight = true;
      state.resumeAttempts = Number(state.resumeAttempts || 0) + 1;
      var pending = videoElement.play();
      if (pending && typeof pending.then === 'function') {
        pending.then(function () {
          state.playAttemptInFlight = false;
          state.resumeAttempts = 0;
        }).catch(function () {
          state.playAttemptInFlight = false;
        });
      } else {
        state.playAttemptInFlight = false;
        if (videoElement.paused === false) {
          state.resumeAttempts = 0;
        }
      }
    } catch (_playError) {
      state.playAttemptInFlight = false;
    }
  }
  function adoptLiveReplacement(state) {
    var replacement = findLiveReplacement(state);
    if (!replacement) {
      return false;
    }
    var previous = state.targetVideo;
    try {
      if (previous && previous[livePresentationProperty] === state) {
        delete previous[livePresentationProperty];
      }
    } catch (_deletePreviousPresentationError) {
    }
    try {
      if (previous && String(previous[runtimeIdProperty] || '') === state.runtimeId) {
        delete previous[runtimeIdProperty];
      }
    } catch (_deletePreviousRuntimeIdError) {
      if (previous) {
        previous[runtimeIdProperty] = undefined;
      }
    }
    disconnectLiveStyleObservers(state);
    unbindLivePresentationViewport(state);
    replacement[runtimeIdProperty] = state.runtimeId;
    replacement[livePresentationProperty] = state;
    state.targetVideo = replacement;
    state.resumeAttempts = 0;
    state.playAttemptInFlight = false;
    updateLiveVideoIdentity(replacement, state);
    if (!applyLivePresentationStyles(replacement, state)) {
      scheduleLivePresentationWatchdog(state);
      return false;
    }
    bindLivePresentationViewport(replacement, state);
    refreshLivePresentationGeometry(replacement, state);
    var adopted = verifyLivePresentation(replacement, state);
    if (adopted) {
      state.watchdogRecoveryFailures = 0;
      restoreLivePlaybackIntent(replacement, state);
      scheduleLivePresentationWatchdog(state);
    }
    return adopted;
  }
  function ensureLivePresentationStable(state) {
    if (!state || state.active !== true) {
      return false;
    }
    var targetVideo = state.targetVideo;
    if (!isLiveVideoIdentityUsable(targetVideo)) {
      ensureLiveBackdrop(state);
      return adoptLiveReplacement(state);
    }
    ensureLiveBackdrop(state);
    if (!verifyLivePresentation(targetVideo, state)) {
      applyLivePresentationStyles(targetVideo, state);
      refreshLivePresentationGeometry(targetVideo, state);
    }
    updateLiveVideoSignature(targetVideo, state);
    restoreLivePlaybackIntent(targetVideo, state);
    var stable = verifyLivePresentation(targetVideo, state);
    if (stable) {
      state.watchdogRecoveryFailures = 0;
    }
    return stable;
  }
  function scheduleLivePresentationWatchdog(state, resetRecoveryFailures) {
    if (!state || state.active !== true) {
      return;
    }
    if (resetRecoveryFailures === true) {
      state.watchdogRecoveryFailures = 0;
    }
    if (Number(state.watchdogTimer || -1) >= 0 ||
        Number(state.watchdogRecoveryFailures || 0) >= liveWatchdogRecoveryLimit) {
      return;
    }
    var ownerWindow = state.targetVideo && state.targetVideo.ownerDocument &&
      state.targetVideo.ownerDocument.defaultView ? state.targetVideo.ownerDocument.defaultView : window;
    state.watchdogWindow = ownerWindow;
    var tick = function () {
      state.watchdogTimer = -1;
      state.watchdogWindow = null;
      if (state.active !== true) {
        return;
      }
      if (ensureLivePresentationStable(state)) {
        state.watchdogRecoveryFailures = 0;
      } else {
        state.watchdogRecoveryFailures = Number(state.watchdogRecoveryFailures || 0) + 1;
      }
      scheduleLivePresentationWatchdog(state);
    };
    state.watchdogTimer = ownerWindow.setTimeout(tick, liveWatchdogIntervalMs);
  }
  function addLiveViewportBinding(target, eventName, listener, bindings) {
    if (!target || typeof target.addEventListener !== 'function') {
      return;
    }
    try {
      target.addEventListener(eventName, listener, false);
      bindings.push({ target: target, eventName: eventName, listener: listener });
    } catch (_bindingError) {
    }
  }
  function isLivePresentationTargetConnected(videoElement, state) {
    if (!videoElement || !state || state.active !== true || videoElement[livePresentationProperty] !== state ||
      videoElement.isConnected === false || videoElement.ownerDocument !== state.boundVideoDocument) {
      return false;
    }
    var frameChain = state.boundFrameChain || [];
    if (frameChain.length <= 0) {
      return state.boundVideoDocument === document;
    }
    for (var frameIndex = 0; frameIndex < frameChain.length; frameIndex += 1) {
      var link = frameChain[frameIndex];
      if (!link || !link.frameElement || link.frameElement.isConnected === false) {
        return false;
      }
      try {
        if (link.frameElement.contentDocument !== link.childDocument) {
          return false;
        }
      } catch (_frameDocumentError) {
        return false;
      }
    }
    return frameChain[frameChain.length - 1].frameElement.ownerDocument === document;
  }
  function cleanupDisconnectedLivePresentation(videoElement, state) {
    if (isLivePresentationTargetConnected(videoElement, state)) {
      return false;
    }
    ensureLiveBackdrop(state);
    return adoptLiveReplacement(state) ? false : true;
  }
  function addLiveDetachObserver(ownerDocument, listener, observers) {
    if (!ownerDocument || !ownerDocument.documentElement) {
      return;
    }
    try {
      var ownerWindow = ownerDocument.defaultView || window;
      var ObserverConstructor = ownerWindow.MutationObserver || null;
      if (typeof ObserverConstructor !== 'function') {
        return;
      }
      var observer = new ObserverConstructor(listener);
      observer.observe(ownerDocument.documentElement, { childList: true, subtree: true });
      observers.push(observer);
    } catch (_observerError) {
    }
  }
  function bindLivePresentationViewport(videoElement, state) {
    var bindings = [];
    var detachObservers = [];
    var frameChain = [];
    var registeredTargets = [];
    var refresh = function () {
      if (cleanupDisconnectedLivePresentation(videoElement, state)) {
        return;
      }
      refreshLivePresentationGeometry(videoElement, state);
    };
    var observeDetach = function () {
      cleanupDisconnectedLivePresentation(videoElement, state);
    };
    var currentDocument = videoElement && (videoElement.ownerDocument || document);
    while (currentDocument) {
      addLiveDetachObserver(currentDocument, observeDetach, detachObservers);
      var ownerWindow = currentDocument.defaultView || null;
      if (ownerWindow && registeredTargets.indexOf(ownerWindow) < 0) {
        registeredTargets.push(ownerWindow);
        addLiveViewportBinding(ownerWindow, 'resize', refresh, bindings);
        addLiveViewportBinding(ownerWindow, 'orientationchange', refresh, bindings);
        var viewport = null;
        try {
          viewport = ownerWindow.visualViewport || null;
        } catch (_viewportError) {
          viewport = null;
        }
        if (viewport && registeredTargets.indexOf(viewport) < 0) {
          registeredTargets.push(viewport);
          addLiveViewportBinding(viewport, 'resize', refresh, bindings);
          addLiveViewportBinding(viewport, 'scroll', refresh, bindings);
        }
      }
      var frameElement = null;
      try {
        frameElement = ownerWindow && ownerWindow.frameElement ? ownerWindow.frameElement : null;
      } catch (_frameLookupError) {
        frameElement = null;
      }
      if (!frameElement) {
        break;
      }
      addLiveViewportBinding(frameElement, 'load', observeDetach, bindings);
      frameChain.push({ frameElement: frameElement, childDocument: currentDocument });
      currentDocument = frameElement.ownerDocument;
    }
    state.boundVideoDocument = videoElement ? videoElement.ownerDocument : null;
    state.boundFrameChain = frameChain;
    state.viewportBindings = bindings;
    state.detachObservers = detachObservers;
    state.targetVideo = videoElement;
    scheduleLivePresentationWatchdog(state);
  }
  function unbindLivePresentationViewport(state) {
    var watchdogTimer = state && Number(state.watchdogTimer || -1);
    if (watchdogTimer >= 0) {
      try {
        var ownerWindow = state.watchdogWindow || window;
        ownerWindow.clearTimeout(watchdogTimer);
      } catch (_clearWatchdogError) {
      }
    }
    var bindings = state && state.viewportBindings ? state.viewportBindings : [];
    for (var bindingIndex = bindings.length - 1; bindingIndex >= 0; bindingIndex -= 1) {
      var binding = bindings[bindingIndex];
      try {
        binding.target.removeEventListener(binding.eventName, binding.listener, false);
      } catch (_unbindError) {
      }
    }
    var detachObservers = state && state.detachObservers ? state.detachObservers : [];
    for (var observerIndex = detachObservers.length - 1; observerIndex >= 0; observerIndex -= 1) {
      try {
        detachObservers[observerIndex].disconnect();
      } catch (_disconnectError) {
      }
    }
    if (state) {
      state.boundVideoDocument = null;
      state.boundFrameChain = [];
      state.viewportBindings = [];
      state.detachObservers = [];
      state.watchdogTimer = -1;
      state.watchdogWindow = null;
    }
  }
  function restoreStyleSnapshots(snapshots) {
    for (var snapshotIndex = snapshots.length - 1; snapshotIndex >= 0; snapshotIndex -= 1) {
      var snapshot = snapshots[snapshotIndex];
      if (!snapshot || !snapshot.element || !snapshot.element.style) {
        continue;
      }
      for (var propertyIndex = 0; propertyIndex < snapshot.properties.length; propertyIndex += 1) {
        var property = snapshot.properties[propertyIndex];
        if (property.value.length > 0) {
          snapshot.element.style.setProperty(property.name, property.value, property.priority);
        } else {
          snapshot.element.style.removeProperty(property.name);
        }
      }
    }
  }
  function resolveActionToolbar(videoElement) {
    try {
      var ownerDocument = videoElement && videoElement.ownerDocument ? videoElement.ownerDocument : document;
      var toolbar = ownerDocument.getElementById('__aira_video_action_toolbar');
      return toolbar && String(toolbar.getAttribute('data-aira-video-runtime-id') || '') === expectedRuntimeId ?
        toolbar : null;
    } catch (_toolbarLookupError) {
      return null;
    }
  }
  function refreshActionToolbarAfterPresentation(videoElement) {
    var toolbar = resolveActionToolbar(videoElement);
    if (!toolbar) {
      return;
    }
    toolbar.__airaFullscreenRequestPending = false;
    try {
      if (typeof toolbar.__airaResetInteractionState === 'function') {
        toolbar.__airaResetInteractionState();
      }
      if (typeof toolbar.__airaRefresh === 'function') {
        toolbar.__airaRefresh();
      }
    } catch (_toolbarRefreshError) {
    }
  }
  function enterLivePresentation() {
    var currentState = video[livePresentationProperty] || livePresentationRegistry[expectedRuntimeId];
    var presentationAlreadyActive = !!(currentState && currentState.active === true && currentState.snapshots);
    var snapshots = presentationAlreadyActive ? currentState.snapshots : [];
    var presentationState = presentationAlreadyActive ? currentState : {
      active: true,
      snapshots: snapshots,
      boundVideoDocument: null,
      boundFrameChain: [],
      viewportBindings: [],
      detachObservers: [],
      watchdogTimer: -1,
      watchdogWindow: null,
      watchdogRecoveryFailures: 0,
      backdrop: null,
      controlTargets: [],
      styleObservers: [],
      presentationMode: requestedPresentationMode,
      scaleMode: 'contain',
      playbackIntent: video.paused === false && video.ended !== true ? 'playing' : 'paused',
      resumeTime: Number(video.currentTime || 0),
      playbackRate: Number(video.playbackRate || 1),
      resumeAttempts: 0,
      playAttemptInFlight: false
    };
    var surfaceProperties = [
      'position', 'top', 'right', 'bottom', 'left', 'width', 'height', 'min-width', 'min-height',
      'max-width', 'max-height', 'margin', 'padding', 'z-index', 'display', 'visibility', 'opacity',
      'transform', 'filter', 'perspective', 'clip', 'clip-path', 'contain', 'isolation', 'overflow',
      'overflow-x', 'overflow-y', 'pointer-events', 'box-sizing', 'object-fit', 'object-position',
      'background-color'
    ];
    var ancestorProperties = [
      'position', 'z-index', 'visibility', 'opacity', 'transform', 'filter', 'perspective', 'clip',
      'clip-path', 'contain', 'isolation', 'overflow', 'overflow-x', 'overflow-y'
    ];
    var documentProperties = [
      'width', 'height', 'margin', 'padding', 'overflow', 'overflow-x', 'overflow-y', 'background-color'
    ];
    try {
      presentationState.active = true;
      presentationState.snapshots = snapshots;
      presentationState.runtimeId = expectedRuntimeId;
      presentationState.targetVideo = video;
      presentationState.surfaceProperties = surfaceProperties;
      presentationState.ancestorProperties = ancestorProperties;
      presentationState.documentProperties = documentProperties;
      presentationState.presentationMode = requestedPresentationMode;
      var actionToolbar = resolveActionToolbar(video);
      if (actionToolbar) {
        actionToolbar.__airaFullscreenRequestPending = false;
        actionToolbar.style.visibility = 'hidden';
      }
      if (typeof presentationState.scaleMode !== 'string') {
        presentationState.scaleMode = 'contain';
      }
      if (typeof presentationState.playbackIntent !== 'string') {
        presentationState.playbackIntent = video.paused === false && video.ended !== true ? 'playing' : 'paused';
      }
      video[livePresentationProperty] = presentationState;
      livePresentationRegistry[expectedRuntimeId] = presentationState;
      updateLiveVideoSignature(video, presentationState);
      unbindLivePresentationViewport(presentationState);
      if (!applyLivePresentationStyles(video, presentationState)) {
        throw new Error('live_presentation_style_failed');
      }
      bindLivePresentationViewport(video, presentationState);
      refreshLivePresentationGeometry(video, presentationState);
      if (!ensureLivePresentationStable(presentationState)) {
        // Large-screen ArkWeb can publish its post-style layout one frame later.
        // Keep the takeover when the structural prerequisites are already ready;
        // the bound watchdog will reapply geometry after the viewport settles.
        var ownerDocument = video.ownerDocument || document;
        var ownerWindow = ownerDocument.defaultView || window;
        var computedStyle = ownerWindow && typeof ownerWindow.getComputedStyle === 'function' ?
          ownerWindow.getComputedStyle(video) : null;
        var structureReady = video.isConnected !== false && video.ownerDocument !== null &&
          presentationState.backdrop && presentationState.backdrop.isConnected !== false &&
          video.controls === false && !video.hasAttribute('controls') &&
          video.getAttribute(controlsHiddenMarkerAttribute) === 'true' &&
          (!computedStyle || (computedStyle.position === 'fixed' && computedStyle.display !== 'none' &&
            computedStyle.visibility !== 'hidden' && Number.parseFloat(computedStyle.opacity || '1') > 0.02));
        if (!structureReady) {
          throw new Error('live_presentation_verification_failed');
        }
        scheduleLivePresentationWatchdog(presentationState, true);
      }
      return true;
    } catch (presentationError) {
      lastPresentationFailureReason = String(presentationError && presentationError.message ||
        presentationError || 'presentation_failed');
      if (lastPresentationFailureReason === 'live_presentation_verification_failed' &&
          lastPresentationVerificationDetail.length > 0) {
        lastPresentationFailureReason += '_' + lastPresentationVerificationDetail;
      }
      lastPresentationFailureReason = lastPresentationFailureReason.slice(0, 96);
      if (!presentationAlreadyActive) {
        presentationState.active = false;
        unbindLivePresentationViewport(presentationState);
        disconnectLiveStyleObservers(presentationState);
        removeLiveBackdrop(presentationState);
        restoreLiveControlTargets(presentationState);
        restoreStyleSnapshots(snapshots);
        delete livePresentationRegistry[expectedRuntimeId];
        try {
          delete video[livePresentationProperty];
        } catch (_deletePresentationError) {
          video[livePresentationProperty] = undefined;
        }
        refreshActionToolbarAfterPresentation(video);
      }
      return false;
    }
  }
  function restoreLivePresentation() {
    var state = video[livePresentationProperty] || livePresentationRegistry[expectedRuntimeId];
    if (!state || state.active !== true || !state.snapshots) {
      refreshActionToolbarAfterPresentation(video);
      return;
    }
    state.active = false;
    unbindLivePresentationViewport(state);
    disconnectLiveStyleObservers(state);
    removeLiveBackdrop(state);
    restoreLiveControlTargets(state);
    restoreStyleSnapshots(state.snapshots);
    delete livePresentationRegistry[expectedRuntimeId];
    try {
      if (state.targetVideo && state.targetVideo[livePresentationProperty] === state) {
        delete state.targetVideo[livePresentationProperty];
      }
      if (video[livePresentationProperty] === state) {
        delete video[livePresentationProperty];
      }
    } catch (_deletePresentationError) {
      video[livePresentationProperty] = undefined;
    }
    refreshActionToolbarAfterPresentation(state.targetVideo || video);
  }
  function ensurePictureInPictureState() {
    var state = video[pipRequestStateProperty];
    if (!state || typeof state !== 'object') {
      state = {
        status: 'idle',
        reason: '',
        wasPlaying: false,
        everStarted: false,
        listenersBound: false,
        transitionToken: 0
      };
      video[pipRequestStateProperty] = state;
    }
    if (typeof state.wasPlaying !== 'boolean') {
      state.wasPlaying = false;
    }
    if (typeof state.everStarted !== 'boolean') {
      state.everStarted = false;
    }
    if (typeof state.listenersBound !== 'boolean') {
      state.listenersBound = false;
    }
    if (!Number.isFinite(Number(state.transitionToken))) {
      state.transitionToken = 0;
    }
    return state;
  }
  function resumePictureInPicturePlayback(state) {
    if (!state || state.wasPlaying !== true || video.ended === true) {
      return;
    }
    state.transitionToken = Number(state.transitionToken || 0) + 1;
    var transitionToken = state.transitionToken;
    var resumeIfNeeded = function () {
      var currentState = video[pipRequestStateProperty];
      if (currentState !== state || currentState.wasPlaying !== true ||
          currentState.transitionToken !== transitionToken || video.ended === true || video.paused !== true) {
        return;
      }
      try {
        var playRequest = video.play();
        if (playRequest && typeof playRequest.catch === 'function') {
          playRequest.catch(function () {});
        }
      } catch (_playError) {
      }
    };
    resumeIfNeeded();
    try {
      var ownerWindow = video.ownerDocument && video.ownerDocument.defaultView ?
        video.ownerDocument.defaultView : window;
      if (ownerWindow && typeof ownerWindow.setTimeout === 'function') {
        ownerWindow.setTimeout(resumeIfNeeded, 80);
        ownerWindow.setTimeout(resumeIfNeeded, 220);
      }
    } catch (_resumeTimerError) {
    }
  }
  function markPictureInPictureStarted(state) {
    state.status = 'started';
    state.reason = '';
    state.everStarted = true;
    resumePictureInPicturePlayback(state);
  }
  function markPictureInPictureExited(state) {
    state.status = 'idle';
    state.reason = '';
    resumePictureInPicturePlayback(state);
  }
  function ensurePictureInPictureLifecycle(state) {
    if (state.listenersBound === true || typeof video.addEventListener !== 'function') {
      return;
    }
    try {
      video.addEventListener('enterpictureinpicture', function () {
        markPictureInPictureStarted(ensurePictureInPictureState());
      });
      video.addEventListener('leavepictureinpicture', function () {
        markPictureInPictureExited(ensurePictureInPictureState());
      });
      video.addEventListener('webkitpresentationmodechanged', function () {
        var currentState = ensurePictureInPictureState();
        if (video.webkitPresentationMode === 'picture-in-picture') {
          markPictureInPictureStarted(currentState);
        } else if (currentState.everStarted === true) {
          markPictureInPictureExited(currentState);
        }
      });
      state.listenersBound = true;
    } catch (_lifecycleError) {
    }
  }
  function installActionToolbar() {
    var ownerDocument = video.ownerDocument || document;
    var ownerWindow = ownerDocument.defaultView || window;
    var toolbarId = '__aira_video_action_toolbar';
    var existingToolbar = ownerDocument.getElementById(toolbarId);
    if (existingToolbar &&
        String(existingToolbar.getAttribute('data-aira-video-runtime-id') || '') !== expectedRuntimeId) {
      try {
        if (typeof existingToolbar.__airaCleanup === 'function') {
          existingToolbar.__airaCleanup();
        }
        if (existingToolbar.parentNode) {
          existingToolbar.parentNode.removeChild(existingToolbar);
        }
      } catch (_removeStaleToolbarError) {
      }
      existingToolbar = null;
    }
    if (existingToolbar) {
      try {
        existingToolbar.__airaFullscreenRequestPending = false;
        if (typeof existingToolbar.__airaResetInteractionState === 'function') {
          existingToolbar.__airaResetInteractionState();
        }
        if (typeof existingToolbar.__airaRefresh === 'function') {
          existingToolbar.__airaRefresh();
        }
      } catch (_refreshToolbarError) {
      }
      return true;
    }
    var toolbarHost = ownerDocument.body || ownerDocument.documentElement;
    if (!toolbarHost) {
      return false;
    }
    var toolbar = ownerDocument.createElement('div');
    toolbar.id = toolbarId;
    toolbar.setAttribute('data-aira-video-runtime-id', expectedRuntimeId);
    toolbar.setAttribute('role', 'toolbar');
    toolbar.setAttribute('aria-label', 'Aira 视频操作');
    toolbar.style.cssText = [
      'position:fixed', 'left:8px', 'top:8px', 'z-index:2147483647',
      'display:flex', 'align-items:center', 'gap:8px', 'box-sizing:border-box',
      'color:#fff', 'pointer-events:auto', 'touch-action:none', 'user-select:none',
      'visibility:hidden'
    ].join(';');
    var svgNamespace = 'http://www.w3.org/2000/svg';
    var castIconPaths = [
      'M3.75 23.75H3.7625',
      'M8.75 23.75C8.75 22.4239 8.22322 21.1521 7.28553 20.2145C6.34785 19.2768 5.07608 18.75 3.75 18.75',
      'M13.75 23.75C13.75 21.0978 12.6964 18.5543 10.8211 16.6789C8.9457 14.8036 6.40216 13.75 3.75 13.75',
      'M18.75 23.75H22.5C23.4946 23.75 24.4484 23.3549 25.1516 22.6517C25.8549 21.9484 26.25 20.9946 26.25 20V10C26.25 9.00544 25.8549 8.05161 25.1516 7.34835C24.4484 6.64509 23.4946 6.25 22.5 6.25H7.5C6.7306 6.2573 5.98207 6.5011 5.35595 6.94833C4.72983 7.39556 4.25644 8.02456 4 8.75'
    ];
    var pictureInPictureIconPaths = [
      'M13.75 23.75H6.25C5.58696 23.75 4.95107 23.4866 4.48223 23.0178C4.01339 22.5489 3.75 21.913 3.75 21.25V8.75C3.75 8.08696 4.01339 7.45107 4.48223 6.98223C4.95107 6.51339 5.58696 6.25 6.25 6.25H23.75C24.413 6.25 25.0489 6.51339 25.5178 6.98223C25.9866 7.45107 26.25 8.08696 26.25 8.75V13.75',
      'M17.5 18.75C17.5 18.4185 17.6317 18.1005 17.8661 17.8661C18.1005 17.6317 18.4185 17.5 18.75 17.5H25C25.3315 17.5 25.6495 17.6317 25.8839 17.8661C26.1183 18.1005 26.25 18.4185 26.25 18.75V22.5C26.25 22.8315 26.1183 23.1495 25.8839 23.3839C25.6495 23.6183 25.3315 23.75 25 23.75H18.75C18.4185 23.75 18.1005 23.6183 17.8661 23.3839C17.6317 23.1495 17.5 22.8315 17.5 22.5V18.75Z'
    ];
    var fullscreenIconPaths = [
      'M5 10V7.5C5 6.83696 5.26339 6.20107 5.73223 5.73223C6.20107 5.26339 6.83696 5 7.5 5H10',
      'M5 20V22.5C5 23.163 5.26339 23.7989 5.73223 24.2678C6.20107 24.7366 6.83696 25 7.5 25H10',
      'M20 5H22.5C23.163 5 23.7989 5.26339 24.2678 5.73223C24.7366 6.20107 25 6.83696 25 7.5V10',
      'M20 25H22.5C23.163 25 23.7989 24.7366 24.2678 24.2678C24.7366 23.7989 25 23.163 25 22.5V20'
    ];
    var createIcon = function (iconPaths) {
      var icon = ownerDocument.createElementNS(svgNamespace, 'svg');
      icon.setAttribute('viewBox', '0 0 30 30');
      icon.setAttribute('fill', 'none');
      icon.setAttribute('stroke', 'currentColor');
      icon.setAttribute('stroke-width', '2.3');
      icon.setAttribute('stroke-linecap', 'round');
      icon.setAttribute('stroke-linejoin', 'round');
      icon.setAttribute('aria-hidden', 'true');
      icon.setAttribute('focusable', 'false');
      icon.style.cssText = 'width:24px;height:24px;display:block;pointer-events:none';
      for (var pathIndex = 0; pathIndex < iconPaths.length; pathIndex += 1) {
        var path = ownerDocument.createElementNS(svgNamespace, 'path');
        path.setAttribute('d', iconPaths[pathIndex]);
        icon.appendChild(path);
      }
      return icon;
    };
    var createButton = function (iconPaths, accessibilityLabel) {
      var button = ownerDocument.createElement('button');
      button.type = 'button';
      button.setAttribute('aria-label', accessibilityLabel);
      button.style.cssText = [
        'width:40px', 'height:40px', 'box-sizing:border-box', 'padding:0', 'margin:0',
        'display:inline-flex', 'align-items:center', 'justify-content:center',
        'border:1px solid rgba(255,255,255,.28)', 'border-radius:50%',
        'background:rgba(255,255,255,.16)', 'color:#fff', 'cursor:pointer',
        'touch-action:none', '-webkit-tap-highlight-color:transparent',
        '-webkit-backdrop-filter:blur(24px) saturate(1.45)', 'backdrop-filter:blur(24px) saturate(1.45)',
        'box-shadow:0 3px 16px rgba(0,0,0,.28)'
      ].join(';');
      button.appendChild(createIcon(iconPaths));
      button.addEventListener('pointerdown', function (event) {
        event.stopPropagation();
      }, true);
      toolbar.appendChild(button);
      return button;
    };
    var setButtonState = function (button, state, title) {
      button.setAttribute('data-state', state);
      button.title = title;
      button.style.opacity = state === 'unavailable' ? '0.48' : '1';
      button.style.background = state === 'busy' ? 'rgba(10,89,247,.92)' : 'rgba(255,255,255,.16)';
    };
    var castButton = createButton(castIconPaths, '投屏');
    var pipButton = createButton(pictureInPictureIconPaths, '小窗播放');
    var fullscreenButton = createButton(fullscreenIconPaths, '使用 Aira 全屏播放');
    var resetToolbarInteractionState = function () {
      setButtonState(castButton, 'idle', '投屏');
      setButtonState(pipButton, 'idle', '小窗播放');
      setButtonState(fullscreenButton, 'idle', '使用 Aira 全屏播放');
    };
    castButton.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      try {
        var remoteController = video.remote;
        if (remoteController && typeof remoteController.prompt === 'function') {
          if (String(remoteController.state || '').toLowerCase() === 'unavailable') {
            setButtonState(castButton, 'unavailable', '当前网页不支持投屏');
            return;
          }
          setButtonState(castButton, 'busy', '请在系统窗口选择设备');
          var remotePrompt = remoteController.prompt();
          if (remotePrompt && typeof remotePrompt.then === 'function') {
            remotePrompt.then(function () {
              setButtonState(castButton, 'idle', '投屏');
            }).catch(function () {
              setButtonState(castButton, 'idle', '投屏');
            });
          } else {
            setButtonState(castButton, 'idle', '投屏');
          }
          return;
        }
        if (typeof video.webkitShowPlaybackTargetPicker === 'function') {
          video.webkitShowPlaybackTargetPicker();
          return;
        }
        setButtonState(castButton, 'unavailable', '当前网页不支持投屏');
      } catch (_castToolbarError) {
        setButtonState(castButton, 'unavailable', '当前网页不支持投屏');
      }
    });
    pipButton.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      try {
        if (video.disablePictureInPicture === true || video.hasAttribute('disablepictureinpicture')) {
          setButtonState(pipButton, 'unavailable', '当前网页不支持小窗播放');
          return;
        }
        if (typeof video.requestPictureInPicture === 'function') {
          setButtonState(pipButton, 'busy', '正在打开小窗');
          var pipRequest = video.requestPictureInPicture();
          if (pipRequest && typeof pipRequest.then === 'function') {
            pipRequest.then(function () {
              setButtonState(pipButton, 'idle', '小窗播放');
            }).catch(function () {
              setButtonState(pipButton, 'unavailable', '当前网页不支持小窗播放');
            });
          } else {
            setButtonState(pipButton, 'idle', '小窗播放');
          }
          return;
        }
        if (typeof video.webkitSetPresentationMode === 'function') {
          video.webkitSetPresentationMode('picture-in-picture');
          return;
        }
        setButtonState(pipButton, 'unavailable', '当前网页不支持小窗播放');
      } catch (_pipToolbarError) {
        setButtonState(pipButton, 'unavailable', '当前网页不支持小窗播放');
      }
    });
    var emitFullscreenRequestResult = function (attemptId, status, reason) {
      try {
        var event;
        var ownerWindow = video.ownerDocument && video.ownerDocument.defaultView ?
          video.ownerDocument.defaultView : window;
        var detail = {
          attemptId: Number(attemptId || 0),
          status: String(status || ''),
          reason: String(reason || '')
        };
        if (ownerWindow && typeof ownerWindow.CustomEvent === 'function') {
          event = new ownerWindow.CustomEvent(fullscreenRequestResultEvent, { detail: detail });
        } else {
          event = (video.ownerDocument || document).createEvent('CustomEvent');
          event.initCustomEvent(fullscreenRequestResultEvent, false, false, detail);
        }
        video.dispatchEvent(event);
      } catch (_fullscreenEventError) {
      }
    };
    var resolveWebFullscreenTarget = function (videoElement) {
      var current = videoElement;
      for (var depth = 0; current && depth < 8; depth += 1) {
        try {
          var tagName = String(current.tagName || '').toLowerCase();
          var className = String(current.className || '').toLowerCase();
          var dataPlayer = String(current.getAttribute && current.getAttribute('data-player') || '').toLowerCase();
          if (tagName !== 'video' &&
              (/art-video-player|artplayer|dplayer|video-js|jwplayer|plyr|xgplayer|video-container/.test(className) ||
               dataPlayer.length > 0)) {
            return current;
          }
          current = current.parentElement;
        } catch (_fullscreenTargetError) {
          break;
        }
      }
      return videoElement;
    };
    var requestWebFullscreen = function (videoElement, attemptId) {
      var targetElement = resolveWebFullscreenTarget(videoElement);
      var requestMethod = null;
      try {
        if (targetElement && typeof targetElement.requestFullscreen === 'function') {
          requestMethod = targetElement.requestFullscreen;
        } else if (targetElement && typeof targetElement.webkitRequestFullscreen === 'function') {
          requestMethod = targetElement.webkitRequestFullscreen;
        } else if (targetElement && typeof targetElement.webkitRequestFullScreen === 'function') {
          requestMethod = targetElement.webkitRequestFullScreen;
        }
        if (requestMethod) {
          var requestResult = requestMethod.call(targetElement);
          emitFullscreenRequestResult(attemptId, 'requested', 'standard');
          if (requestResult && typeof requestResult.then === 'function') {
            requestResult.then(function () {
              emitFullscreenRequestResult(attemptId, 'resolved', 'standard');
            }).catch(function (error) {
              emitFullscreenRequestResult(attemptId, 'rejected', String(error && (error.name || error.message) || error || 'rejected'));
            });
          }
          return true;
        }
        if (videoElement && typeof videoElement.webkitEnterFullscreen === 'function') {
          videoElement.webkitEnterFullscreen();
          emitFullscreenRequestResult(attemptId, 'requested', 'webkit');
          return true;
        }
        if (videoElement && typeof videoElement.webkitEnterFullScreen === 'function') {
          videoElement.webkitEnterFullScreen();
          emitFullscreenRequestResult(attemptId, 'requested', 'webkit');
          return true;
        }
      } catch (error) {
        emitFullscreenRequestResult(attemptId, 'rejected', String(error && (error.name || error.message) || error || 'rejected'));
      }
      return false;
    };
    var requestNativeFullscreen = function (bridgeWindow, payload) {
      try {
        var nativeBridge = bridgeWindow.__airaWebVideoControllerBridge;
        if (nativeBridge && typeof nativeBridge.enterFullscreen === 'function') {
          nativeBridge.enterFullscreen(payload);
          return true;
        }
        var registeredBridge = bridgeWindow.__airaUserScriptNativeBridge;
        if (registeredBridge && typeof registeredBridge.webVideoEnterFullscreen === 'function') {
          registeredBridge.webVideoEnterFullscreen(payload);
          return true;
        }
      } catch (_nativeFullscreenBridgeError) {
      }
      return false;
    };
    fullscreenButton.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      try {
        toolbar.__airaFullscreenRequestPending = true;
        toolbar.style.visibility = 'hidden';
        setButtonState(fullscreenButton, 'busy', '正在进入 Aira 全屏');
        var fullscreenAttemptId = Date.now();
        var fullscreenPayload = JSON.stringify({
          protocol: actionToolbarProtocol,
          action: 'fullscreen',
          runtimeId: expectedRuntimeId,
          frameRuntimeId: expectedFrameRuntimeId,
          fullscreenAttemptId: fullscreenAttemptId
        });
        // Establish the native pending marker before ArkWeb can deliver onFullScreenEnter.
        var requested = requestNativeFullscreen(ownerWindow, fullscreenPayload);
        if (!requested) {
          try {
            if (ownerWindow.top && ownerWindow.top !== ownerWindow) {
              requested = requestNativeFullscreen(ownerWindow.top, fullscreenPayload);
            }
          } catch (_topWindowBridgeError) {
          }
        }
        if (!requested) {
          toolbar.__airaFullscreenRequestPending = false;
          setButtonState(fullscreenButton, 'unavailable', '当前页面不能进入 Aira 全屏');
          scheduleToolbarRefresh();
          return;
        }
        requestWebFullscreen(video, fullscreenAttemptId);
        if (ownerWindow && typeof ownerWindow.setTimeout === 'function') {
          ownerWindow.setTimeout(function () {
            var presentationState = video[livePresentationProperty] || livePresentationRegistry[expectedRuntimeId];
            if (toolbar.__airaFullscreenRequestPending === true &&
                (!presentationState || presentationState.active !== true)) {
              toolbar.__airaFullscreenRequestPending = false;
              setButtonState(fullscreenButton, 'idle', '使用 Aira 全屏播放');
              scheduleToolbarRefresh();
            }
          }, 5000);
        }
      } catch (_fullscreenToolbarError) {
        toolbar.__airaFullscreenRequestPending = false;
        setButtonState(fullscreenButton, 'unavailable', '当前页面不能进入 Aira 全屏');
        scheduleToolbarRefresh();
      }
    });
    // The user may drag the whole button group to any spot. The offset is kept relative to the
    // computed anchor below, so the group keeps following the video while remembering the drag.
    // A fresh page or a new video installs a new toolbar, which starts back at the default anchor.
    var actionToolbarDragOffsetX = 0;
    var actionToolbarDragOffsetY = 0;
    var actionToolbarDragActive = false;
    var actionToolbarTouchActive = false;
    var actionToolbarDragMoved = false;
    var actionToolbarDragStartX = 0;
    var actionToolbarDragStartY = 0;
    var actionToolbarDragStartOffsetX = 0;
    var actionToolbarDragStartOffsetY = 0;
    var actionToolbarSuppressClick = false;
    var actionToolbarSuppressClickTimer = -1;
    // Prefer touch events for touch input: many video players cancel pointer events from their own
    // vertical swipe gestures, which would otherwise leave only horizontal drags working.
    var actionToolbarSupportsTouchEvents = ('ontouchstart' in ownerWindow) ||
      Number((ownerWindow.navigator && ownerWindow.navigator.maxTouchPoints) || 0) > 0;
    var armActionToolbarClickSuppression = function () {
      actionToolbarSuppressClick = true;
      if (actionToolbarSuppressClickTimer >= 0) {
        clearTimeout(actionToolbarSuppressClickTimer);
      }
      // The click that follows a drag lands on the same task turn; drop the flag afterwards so a
      // drag that produced no click cannot swallow the next genuine tap.
      actionToolbarSuppressClickTimer = setTimeout(function () {
        actionToolbarSuppressClickTimer = -1;
        actionToolbarSuppressClick = false;
      }, 0);
    };
    var applyActionToolbarPosition = function () {
      var rect = video.getBoundingClientRect();
      var viewportWidth = Math.max(1, Number(ownerWindow.innerWidth || ownerDocument.documentElement.clientWidth || 1));
      var viewportHeight = Math.max(1, Number(ownerWindow.innerHeight || ownerDocument.documentElement.clientHeight || 1));
      var toolbarWidth = Math.max(136, Number(toolbar.offsetWidth || 136));
      var toolbarHeight = Math.max(40, Number(toolbar.offsetHeight || 40));
      var maxLeft = Math.max(actionToolbarViewportEdgeGap, viewportWidth - toolbarWidth - actionToolbarViewportEdgeGap);
      var maxTop = Math.max(actionToolbarViewportEdgeGap, viewportHeight - toolbarHeight - actionToolbarViewportEdgeGap);
      // Default anchor: below the video's bottom-right corner, offset by a clear gap, so the buttons
      // never cover the picture; clamped into the viewport for full-bleed players.
      var anchorLeft = Math.max(actionToolbarViewportEdgeGap, Math.min(maxLeft, rect.right - toolbarWidth));
      var anchorTop = Math.max(actionToolbarViewportEdgeGap, Math.min(maxTop, rect.bottom + actionToolbarVideoGap));
      var left = Math.max(actionToolbarViewportEdgeGap, Math.min(maxLeft, anchorLeft + actionToolbarDragOffsetX));
      var top = Math.max(actionToolbarViewportEdgeGap, Math.min(maxTop, anchorTop + actionToolbarDragOffsetY));
      toolbar.style.left = String(Math.round(left)) + 'px';
      toolbar.style.top = String(Math.round(top)) + 'px';
    };
    var actionToolbarFinite = function (value) {
      var numeric = Number(value);
      return Number.isFinite(numeric) ? numeric : 0;
    };
    var beginActionToolbarDrag = function (clientX, clientY) {
      actionToolbarDragActive = true;
      actionToolbarDragMoved = false;
      actionToolbarDragStartX = actionToolbarFinite(clientX);
      actionToolbarDragStartY = actionToolbarFinite(clientY);
      actionToolbarDragStartOffsetX = actionToolbarDragOffsetX;
      actionToolbarDragStartOffsetY = actionToolbarDragOffsetY;
    };
    var moveActionToolbarDrag = function (clientX, clientY) {
      if (!actionToolbarDragActive) {
        return;
      }
      var deltaX = actionToolbarFinite(clientX) - actionToolbarDragStartX;
      var deltaY = actionToolbarFinite(clientY) - actionToolbarDragStartY;
      if (!actionToolbarDragMoved) {
        if (Math.abs(deltaX) < actionToolbarDragStartDistance &&
            Math.abs(deltaY) < actionToolbarDragStartDistance) {
          return;
        }
        actionToolbarDragMoved = true;
      }
      actionToolbarDragOffsetX = actionToolbarDragStartOffsetX + deltaX;
      actionToolbarDragOffsetY = actionToolbarDragStartOffsetY + deltaY;
      applyActionToolbarPosition();
    };
    var endActionToolbarDrag = function () {
      if (!actionToolbarDragActive) {
        return;
      }
      actionToolbarDragActive = false;
      if (actionToolbarDragMoved) {
        armActionToolbarClickSuppression();
      }
      actionToolbarDragMoved = false;
    };
    var isActionToolbarDragging = function () {
      return actionToolbarDragActive || actionToolbarTouchActive;
    };
    var handleActionToolbarPointerDown = function (event) {
      if (!event || event.isPrimary === false) {
        return;
      }
      if (actionToolbarSupportsTouchEvents && event.pointerType === 'touch') {
        return;
      }
      if (typeof event.button === 'number' && event.button !== 0) {
        return;
      }
      beginActionToolbarDrag(event.clientX, event.clientY);
    };
    var handleActionToolbarPointerMove = function (event) {
      if (!actionToolbarDragActive || !event) {
        return;
      }
      if (actionToolbarSupportsTouchEvents && event.pointerType === 'touch') {
        return;
      }
      if (event.cancelable === true && typeof event.preventDefault === 'function') {
        event.preventDefault();
      }
      moveActionToolbarDrag(event.clientX, event.clientY);
    };
    var handleActionToolbarPointerEnd = function (event) {
      if (!actionToolbarDragActive) {
        return;
      }
      if (actionToolbarSupportsTouchEvents && event && event.pointerType === 'touch') {
        return;
      }
      endActionToolbarDrag();
    };
    // Touch drives its own path so a page-level swipe gesture cannot cancel a vertical drag.
    var handleActionToolbarTouchStart = function (event) {
      if (!event || !event.touches || event.touches.length !== 1) {
        return;
      }
      var touch = event.touches[0];
      actionToolbarTouchActive = true;
      beginActionToolbarDrag(touch.clientX, touch.clientY);
      if (typeof event.stopPropagation === 'function') {
        event.stopPropagation();
      }
    };
    var handleActionToolbarTouchMove = function (event) {
      if (!actionToolbarTouchActive || !event || !event.touches || event.touches.length <= 0) {
        return;
      }
      if (event.cancelable === true && typeof event.preventDefault === 'function') {
        event.preventDefault();
      }
      if (typeof event.stopPropagation === 'function') {
        event.stopPropagation();
      }
      var touch = event.touches[0];
      moveActionToolbarDrag(touch.clientX, touch.clientY);
    };
    var handleActionToolbarTouchEnd = function () {
      if (!actionToolbarTouchActive) {
        return;
      }
      actionToolbarTouchActive = false;
      endActionToolbarDrag();
    };
    var refreshToolbar = function () {
      try {
        var presentationState = video[livePresentationProperty] || livePresentationRegistry[expectedRuntimeId];
        if (toolbar.__airaFullscreenRequestPending === true ||
            (presentationState && presentationState.active === true)) {
          toolbar.style.visibility = 'hidden';
          return;
        }
        if (!video.isConnected || video.ended === true) {
          toolbar.style.visibility = 'hidden';
          return;
        }
        // While the user is dragging, keep the finger-driven position. A page scroll or video
        // geometry refresh must not yank the group back to its anchor mid-gesture.
        if (isActionToolbarDragging()) {
          toolbar.style.visibility = 'visible';
          return;
        }
        var rect = video.getBoundingClientRect();
        var viewportWidth = Math.max(1, Number(ownerWindow.innerWidth || ownerDocument.documentElement.clientWidth || 1));
        var viewportHeight = Math.max(1, Number(ownerWindow.innerHeight || ownerDocument.documentElement.clientHeight || 1));
        var visible = rect.width >= 80 && rect.height >= 45 && rect.right > 0 && rect.bottom > 0 &&
          rect.left < viewportWidth && rect.top < viewportHeight;
        if (!visible) {
          toolbar.style.visibility = 'hidden';
          return;
        }
        applyActionToolbarPosition();
        toolbar.style.visibility = 'visible';
      } catch (_toolbarPositionError) {
        toolbar.style.visibility = 'hidden';
      }
    };
    var scheduleToolbarRefresh = function () {
      if (ownerWindow && typeof ownerWindow.requestAnimationFrame === 'function') {
        ownerWindow.requestAnimationFrame(refreshToolbar);
      } else {
        refreshToolbar();
      }
    };
    var toolbarResizeObserver = null;
    try {
      if (ownerWindow && typeof ownerWindow.ResizeObserver === 'function') {
        toolbarResizeObserver = new ownerWindow.ResizeObserver(scheduleToolbarRefresh);
        toolbarResizeObserver.observe(video);
      }
    } catch (_toolbarResizeObserverError) {
    }
    ownerWindow.addEventListener('resize', scheduleToolbarRefresh, false);
    ownerWindow.addEventListener('scroll', scheduleToolbarRefresh, true);
    video.addEventListener('resize', scheduleToolbarRefresh, false);
    video.addEventListener('playing', scheduleToolbarRefresh, false);
    video.addEventListener('ended', scheduleToolbarRefresh, false);
    toolbar.addEventListener('pointerdown', handleActionToolbarPointerDown, { capture: true, passive: false });
    ownerWindow.addEventListener('pointermove', handleActionToolbarPointerMove, { capture: true, passive: false });
    ownerWindow.addEventListener('pointerup', handleActionToolbarPointerEnd, true);
    ownerWindow.addEventListener('pointercancel', handleActionToolbarPointerEnd, true);
    toolbar.addEventListener('touchstart', handleActionToolbarTouchStart, { capture: true, passive: false });
    ownerWindow.addEventListener('touchmove', handleActionToolbarTouchMove, { capture: true, passive: false });
    ownerWindow.addEventListener('touchend', handleActionToolbarTouchEnd, true);
    ownerWindow.addEventListener('touchcancel', handleActionToolbarTouchEnd, true);
    // A drag that started on a button must not also trigger that button's action.
    toolbar.addEventListener('click', function (event) {
      if (actionToolbarSuppressClick) {
        actionToolbarSuppressClick = false;
        event.preventDefault();
        event.stopPropagation();
      }
    }, true);
    toolbar.__airaRefresh = scheduleToolbarRefresh;
    toolbar.__airaResetInteractionState = resetToolbarInteractionState;
    toolbar.__airaCleanup = function () {
      try {
        ownerWindow.removeEventListener('resize', scheduleToolbarRefresh, false);
        ownerWindow.removeEventListener('scroll', scheduleToolbarRefresh, true);
        video.removeEventListener('resize', scheduleToolbarRefresh, false);
        video.removeEventListener('playing', scheduleToolbarRefresh, false);
        video.removeEventListener('ended', scheduleToolbarRefresh, false);
        toolbar.removeEventListener('pointerdown', handleActionToolbarPointerDown, { capture: true });
        ownerWindow.removeEventListener('pointermove', handleActionToolbarPointerMove, { capture: true });
        ownerWindow.removeEventListener('pointerup', handleActionToolbarPointerEnd, true);
        ownerWindow.removeEventListener('pointercancel', handleActionToolbarPointerEnd, true);
        toolbar.removeEventListener('touchstart', handleActionToolbarTouchStart, { capture: true });
        ownerWindow.removeEventListener('touchmove', handleActionToolbarTouchMove, { capture: true });
        ownerWindow.removeEventListener('touchend', handleActionToolbarTouchEnd, true);
        ownerWindow.removeEventListener('touchcancel', handleActionToolbarTouchEnd, true);
        if (actionToolbarSuppressClickTimer >= 0) {
          clearTimeout(actionToolbarSuppressClickTimer);
          actionToolbarSuppressClickTimer = -1;
        }
        if (toolbarResizeObserver && typeof toolbarResizeObserver.disconnect === 'function') {
          toolbarResizeObserver.disconnect();
        }
      } catch (_toolbarCleanupError) {
      }
    };
    toolbarHost.appendChild(toolbar);
    scheduleToolbarRefresh();
    return true;
  }
  try {
    if (registeredPresentationState && registeredPresentationState.active === true &&
        commandAction !== 'restore_presentation') {
      if (!ensureLivePresentationStable(registeredPresentationState)) {
        scheduleLivePresentationWatchdog(registeredPresentationState, true);
        return result(false, 'live_presentation_target_unavailable',
          commandAction === 'enter_live_presentation' ? '' : '网页视频会话正在切换，请稍后重试。',
          registeredPresentationState.targetVideo || video);
      }
      video = registeredPresentationState.targetVideo || video;
    } else if (registeredPresentationState && registeredPresentationState.targetVideo) {
      video = registeredPresentationState.targetVideo;
    }
    if (commandAction === 'enter_live_presentation') {
      var entered = enterLivePresentation();
      return result(entered, entered ? 'live_presentation_entered' :
        'live_presentation_failed_' + (lastPresentationFailureReason || 'unknown'),
        entered ? '' : '网页视频画面接管失败，原网页将继续播放。', video);
    }
    if (commandAction === 'suppress_native_controls') {
      return result(suppressNativeControls(), 'native_controls_suppressed',
        '网页播放器拒绝隐藏原生控制栏。', video);
    }
    if (commandAction === 'install_action_toolbar') {
      return result(installActionToolbar(), 'action_toolbar_installed',
        '当前网页无法显示视频操作按钮。', video);
    }
    if (commandAction === 'toggle') {
      suppressNativeControls();
      if (video.paused === false && video.ended !== true) {
        if (registeredPresentationState) {
          registeredPresentationState.playbackIntent = 'paused';
          registeredPresentationState.resumeTime = Number(video.currentTime || 0);
          registeredPresentationState.resumeAttempts = 0;
        }
        video.pause();
        return result(true, 'pause_applied', '', video);
      }
      try {
        if (registeredPresentationState) {
          registeredPresentationState.playbackIntent = 'playing';
          registeredPresentationState.resumeAttempts = 0;
          registeredPresentationState.playAttemptInFlight = true;
        }
        var pending = video.play();
        if (pending && typeof pending.then === 'function') {
          pending.then(function () {
            if (registeredPresentationState) {
              registeredPresentationState.playAttemptInFlight = false;
              registeredPresentationState.resumeAttempts = 0;
            }
          }).catch(function () {
            if (registeredPresentationState) {
              registeredPresentationState.playAttemptInFlight = false;
            }
          });
        } else {
          if (registeredPresentationState) {
            registeredPresentationState.playAttemptInFlight = false;
          }
        }
      } catch (_playError) {
        if (registeredPresentationState) {
          registeredPresentationState.playAttemptInFlight = false;
        }
        return result(false, 'play_request_failed', '网页播放器拒绝继续播放。', video);
      }
      return result(true, 'play_requested', '', video);
    }
    if (commandAction === 'seek') {
      var duration = Number.isFinite(Number(video.duration)) ? Math.max(0, Number(video.duration)) : 0;
      var targetTime = Math.max(0, commandValue);
      if (duration > 0) {
        targetTime = Math.min(duration, targetTime);
      }
      video.currentTime = targetTime;
      if (registeredPresentationState) {
        registeredPresentationState.resumeTime = targetTime;
      }
      return result(true, 'seek_applied', '', video);
    }
    if (commandAction === 'rate') {
      var rate = Math.max(0.25, Math.min(10, commandValue));
      video.playbackRate = rate;
      if (registeredPresentationState) {
        registeredPresentationState.playbackRate = rate;
      }
      return result(Math.abs(Number(video.playbackRate || 1) - rate) < 0.01,
        'rate_applied', '网页播放器拒绝调整倍速。', video);
    }
    if (commandAction === 'scale') {
      var scaleModes = ['contain', 'cover', 'fill'];
      var scaleIndex = Math.max(0, Math.min(scaleModes.length - 1, Math.round(commandValue)));
      var objectFit = scaleModes[scaleIndex];
      rememberObjectFit();
      if (registeredPresentationState) {
        registeredPresentationState.scaleMode = objectFit;
      }
      video.style.setProperty('object-fit', objectFit, 'important');
      if (registeredPresentationState) {
        refreshLivePresentationGeometry(video, registeredPresentationState);
      }
      return result(video.style.getPropertyValue('object-fit') === objectFit,
        'scale_applied', '网页播放器拒绝切换画面比例。', video);
    }
    if (commandAction === 'picture_in_picture') {
      var ownerDocument = video.ownerDocument || document;
      var pictureInPictureState = ensurePictureInPictureState();
      ensurePictureInPictureLifecycle(pictureInPictureState);
      if (ownerDocument.pictureInPictureElement === video ||
          video.webkitPresentationMode === 'picture-in-picture') {
        markPictureInPictureStarted(pictureInPictureState);
        return result(true, 'picture_in_picture_already_active', '', video);
      }
      if (video.disablePictureInPicture === true || video.hasAttribute('disablepictureinpicture')) {
        if (pictureInPictureState.everStarted === true) {
          try {
            video.disablePictureInPicture = false;
            video.removeAttribute('disablepictureinpicture');
          } catch (_restorePiPCapabilityError) {
          }
        }
        if (video.disablePictureInPicture === true || video.hasAttribute('disablepictureinpicture')) {
          return result(false, 'picture_in_picture_disabled', '当前视频暂不支持小窗播放。', video);
        }
      }
      pictureInPictureState.wasPlaying = video.paused === false && video.ended !== true;
      if ((ownerDocument.pictureInPictureEnabled === true || pictureInPictureState.everStarted === true) &&
          typeof video.requestPictureInPicture === 'function') {
        pictureInPictureState.status = 'pending';
        pictureInPictureState.reason = '';
        try {
          var pipRequest = video.requestPictureInPicture();
          if (pipRequest && typeof pipRequest.then === 'function') {
            pipRequest.then(function () {
              markPictureInPictureStarted(pictureInPictureState);
            }).catch(function (error) {
              pictureInPictureState.status = 'failed';
              pictureInPictureState.reason =
                String(error && (error.name || error.message) || error || 'picture_in_picture_rejected');
              resumePictureInPicturePlayback(pictureInPictureState);
            });
            return result(true, 'picture_in_picture_pending', '', video);
          }
          markPictureInPictureStarted(pictureInPictureState);
          return result(true, 'picture_in_picture_started', '', video);
        } catch (error) {
          var requestError = String(error && (error.name || error.message) || error ||
            'picture_in_picture_rejected');
          pictureInPictureState.status = 'failed';
          pictureInPictureState.reason = requestError;
          resumePictureInPicturePlayback(pictureInPictureState);
          return result(false, requestError, '当前视频暂不支持小窗播放。', video);
        }
      }
      if (typeof video.webkitSetPresentationMode === 'function') {
        try {
          pictureInPictureState.status = 'pending';
          pictureInPictureState.reason = '';
          video.webkitSetPresentationMode('picture-in-picture');
          if (video.webkitPresentationMode === 'picture-in-picture') {
            markPictureInPictureStarted(pictureInPictureState);
            return result(true, 'webkit_picture_in_picture_requested', '', video);
          }
        } catch (webkitError) {
          pictureInPictureState.status = 'failed';
          pictureInPictureState.reason = String(webkitError &&
            (webkitError.name || webkitError.message) || webkitError || 'webkit_picture_in_picture_rejected');
        }
        resumePictureInPicturePlayback(pictureInPictureState);
        return result(false, pictureInPictureState.reason || 'webkit_picture_in_picture_rejected',
          '网页播放器拒绝启动小窗。', video);
      }
      return result(false, 'picture_in_picture_unavailable',
        '当前视频暂不支持小窗播放。', video);
    }
    if (commandAction === 'picture_in_picture_status') {
      var pipOwnerDocument = video.ownerDocument || document;
      var pipRequestState = ensurePictureInPictureState();
      ensurePictureInPictureLifecycle(pipRequestState);
      if (pipOwnerDocument.pictureInPictureElement === video ||
          video.webkitPresentationMode === 'picture-in-picture') {
        markPictureInPictureStarted(pipRequestState);
        return result(true, 'picture_in_picture_started', '', video);
      }
      if (pipRequestState && pipRequestState.status === 'started') {
        return result(true, 'picture_in_picture_started', '', video);
      }
      if (pipRequestState && pipRequestState.status === 'failed') {
        return result(false, String(pipRequestState.reason || 'picture_in_picture_rejected'),
          '当前视频暂不支持小窗播放。', video);
      }
      if (pipRequestState && pipRequestState.status === 'pending') {
        return result(true, 'picture_in_picture_pending', '', video);
      }
      return result(false, 'picture_in_picture_not_requested', '当前视频暂不支持小窗播放。', video);
    }
    if (commandAction === 'restore_presentation') {
      restoreObjectFit();
      restoreLivePresentation();
      restoreNativeControls();
      return result(true, 'presentation_restored', '', video);
    }
  } catch (error) {
    return result(false, String(error && error.message || error || 'command_failed'), '网页视频控制失败。', video);
  }
  return result(false, 'unsupported_command', '当前网页视频暂不支持这个操作。', video);
})();`;
  }

}

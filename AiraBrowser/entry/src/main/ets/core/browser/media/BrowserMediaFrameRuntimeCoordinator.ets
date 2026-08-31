import { HostedWebVideoControllerBridge } from '../../web/HostedWebNode';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  MEDIA_VIDEO_FRAME_COMMAND_KIND_PREFIX,
  MEDIA_VIDEO_FRAME_COMMAND_PROTOCOL,
  MEDIA_VIDEO_FRAME_PROBE_CHANNEL_KIND,
  MEDIA_VIDEO_FRAME_PROBE_PROTOCOL,
  MediaVideoFrameProbeScript
} from '../../../features/mediaDiscovery/MediaVideoFrameProbeScript';
import {
  WebVideoFrameCommandRequest,
  WebVideoFrameCommandTransport
} from '../../../services/video/WebVideoFrameCommandTransport';

const MAX_READY_MEDIA_FRAMES_PER_TAB: number = 64;
const MAX_CHANNEL_READ_DIAGNOSTICS_PER_TAB: number = 16;
const MEDIA_FRAME_RUNTIME_LOG_DOMAIN: number = 0x3900;
const MEDIA_FRAME_RUNTIME_LOG_TAG: string = 'AiraMediaFrameRuntime';
const MEDIA_FRAME_COMMAND_TIMEOUT_MS: number = 3500;
const MAX_MEDIA_FRAME_COMMAND_SCRIPT_LENGTH: number = 131072;
const MAX_MEDIA_FRAME_COMMAND_RESULT_LENGTH: number = 131072;
const MAX_MEDIA_FRAME_COMMAND_RESULT_PAYLOAD_LENGTH: number = 140000;
const MAX_QUEUED_MEDIA_FRAME_COMMANDS_PER_TAB: number = 12;

interface BrowserMediaFrameDocumentChannelState {
  channelId: string;
  generation: number;
  issuedAt: number;
}

interface BrowserMediaFrameDocumentChannelSnapshot {
  protocol: string;
  channelId: string;
  generation: number;
  issuedAt: number;
}

interface BrowserMediaFramePendingCommand {
  requestId: string;
  frameRuntimeId: string;
  frameControlKey: string;
  channelId: string;
  action: string;
  script: string;
  timeoutId: number;
  resolve: (value: string) => void;
  reject: (reason: Error) => void;
}

interface BrowserMediaFrameCommandResultPayload {
  protocol?: string;
  channelId?: string;
  requestId?: string;
  frameRuntimeId?: string;
  frameControlKey?: string;
  action?: string;
  result?: string;
}

interface BrowserMediaFrameQueuedCommand {
  request: WebVideoFrameCommandRequest;
  resolve: (value: string) => void;
  reject: (reason: Error) => void;
}

export interface BrowserMediaFrameNativeActionHost {
  requestFullscreen: (tabId: string, payloadJson: string) => void;
}

export class BrowserMediaFrameRuntimeCoordinator implements HostedWebVideoControllerBridge,
  WebVideoFrameCommandTransport {
  private probeScript: MediaVideoFrameProbeScript = new MediaVideoFrameProbeScript();
  private channelByTabId: Map<string, BrowserMediaFrameDocumentChannelState> = new Map();
  private generationByTabId: Map<string, number> = new Map();
  private readyFrameRuntimeIdsByTabId: Map<string, string[]> = new Map();
  private frameControlKeyByTabAndRuntimeId: Map<string, Map<string, string>> = new Map();
  private pendingCommandByTabId: Map<string, BrowserMediaFramePendingCommand> = new Map();
  private queuedCommandsByTabId: Map<string, BrowserMediaFrameQueuedCommand[]> = new Map();
  private channelReadDiagnosticCountByTabId: Map<string, number> = new Map();
  private suppressDiagnosticsByTabId: Map<string, boolean> = new Map();
  private nextChannelSequence: number = 1;
  private nextCommandSequence: number = 1;
  private nativeActionHost?: BrowserMediaFrameNativeActionHost = undefined;

  bindNativeActionHost(host: BrowserMediaFrameNativeActionHost): void {
    this.nativeActionHost = host;
  }

  buildDocumentStartScriptItem(): ScriptItem {
    return this.probeScript.buildDocumentStartScriptItem();
  }

  beginDocument(tabId: string, suppressDiagnostics: boolean): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    const generation = (this.generationByTabId.get(normalizedTabId) ?? 0) + 1;
    this.rejectAllCommands(normalizedTabId, 'document_changed');
    this.generationByTabId.set(normalizedTabId, generation);
    this.channelByTabId.set(normalizedTabId, this.allocateChannel(generation));
    this.readyFrameRuntimeIdsByTabId.set(normalizedTabId, []);
    this.frameControlKeyByTabAndRuntimeId.set(normalizedTabId, new Map<string, string>());
    this.channelReadDiagnosticCountByTabId.set(normalizedTabId, 0);
    this.suppressDiagnosticsByTabId.set(normalizedTabId, suppressDiagnostics);
  }

  clearTab(tabId: string): void {
    const normalizedTabId = tabId.trim();
    this.channelByTabId.delete(normalizedTabId);
    this.generationByTabId.delete(normalizedTabId);
    this.readyFrameRuntimeIdsByTabId.delete(normalizedTabId);
    this.frameControlKeyByTabAndRuntimeId.delete(normalizedTabId);
    this.channelReadDiagnosticCountByTabId.delete(normalizedTabId);
    this.suppressDiagnosticsByTabId.delete(normalizedTabId);
    this.rejectAllCommands(normalizedTabId, 'tab_cleared');
  }

  acceptsProbeChannel(tabId: string, channelId: string): boolean {
    const state = this.channelByTabId.get(tabId.trim());
    return state !== undefined && channelId.trim().length > 0 && state.channelId === channelId.trim();
  }

  acceptReadyFrame(tabId: string, frameRuntimeId: string, frameControlKey: string): boolean {
    const normalizedTabId = tabId.trim();
    const normalizedFrameRuntimeId = frameRuntimeId.trim();
    const normalizedFrameControlKey = frameControlKey.trim();
    if (normalizedTabId.length <= 0 || normalizedFrameRuntimeId.length <= 0 ||
      normalizedFrameControlKey.length <= 0) {
      return false;
    }
    const readyFrameRuntimeIds = this.readyFrameRuntimeIdsByTabId.get(normalizedTabId) ?? [];
    if (readyFrameRuntimeIds.indexOf(normalizedFrameRuntimeId) >= 0) {
      return false;
    }
    if (readyFrameRuntimeIds.length >= MAX_READY_MEDIA_FRAMES_PER_TAB) {
      return false;
    }
    readyFrameRuntimeIds.push(normalizedFrameRuntimeId);
    this.readyFrameRuntimeIdsByTabId.set(normalizedTabId, readyFrameRuntimeIds);
    const controlKeys = this.frameControlKeyByTabAndRuntimeId.get(normalizedTabId) ?? new Map<string, string>();
    controlKeys.set(normalizedFrameRuntimeId, normalizedFrameControlKey);
    this.frameControlKeyByTabAndRuntimeId.set(normalizedTabId, controlKeys);
    return true;
  }

  hasReadyFrame(tabId: string, frameRuntimeId: string): boolean {
    const readyFrameRuntimeIds = this.readyFrameRuntimeIdsByTabId.get(tabId.trim()) ?? [];
    return readyFrameRuntimeIds.indexOf(frameRuntimeId.trim()) >= 0;
  }

  endReadyFrame(tabId: string, frameRuntimeId: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedFrameRuntimeId = frameRuntimeId.trim();
    const readyFrameRuntimeIds = this.readyFrameRuntimeIdsByTabId.get(normalizedTabId);
    if (readyFrameRuntimeIds === undefined) {
      return;
    }
    this.readyFrameRuntimeIdsByTabId.set(
      normalizedTabId,
      readyFrameRuntimeIds.filter((value: string): boolean => value !== normalizedFrameRuntimeId)
    );
    this.frameControlKeyByTabAndRuntimeId.get(normalizedTabId)?.delete(normalizedFrameRuntimeId);
    this.rejectCommandsForFrame(normalizedTabId, normalizedFrameRuntimeId, 'frame_ended');
  }

  enterFullscreen(tabId: string, payloadJson: string): void {
    this.nativeActionHost?.requestFullscreen(tabId.trim(), payloadJson);
  }

  exitFullscreen(_tabId: string): void {
  }

  cast(_tabId: string, _payloadJson: string): void {
  }

  readSystemControl(tabId: string, kind: string): string {
    const normalizedKind = kind.trim();
    if (normalizedKind.indexOf(MEDIA_VIDEO_FRAME_COMMAND_KIND_PREFIX) === 0) {
      return this.readPendingFrameCommand(tabId, normalizedKind);
    }
    if (normalizedKind !== MEDIA_VIDEO_FRAME_PROBE_CHANNEL_KIND) {
      return '{}';
    }
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return '{}';
    }
    let state = this.channelByTabId.get(normalizedTabId);
    if (state === undefined) {
      const generation = (this.generationByTabId.get(normalizedTabId) ?? 0) + 1;
      this.generationByTabId.set(normalizedTabId, generation);
      state = this.allocateChannel(generation);
      this.channelByTabId.set(normalizedTabId, state);
      this.readyFrameRuntimeIdsByTabId.set(normalizedTabId, []);
      this.frameControlKeyByTabAndRuntimeId.set(normalizedTabId, new Map<string, string>());
    }
    const snapshot: BrowserMediaFrameDocumentChannelSnapshot = {
      protocol: MEDIA_VIDEO_FRAME_PROBE_PROTOCOL,
      channelId: state.channelId,
      generation: state.generation,
      issuedAt: state.issuedAt
    };
    this.logChannelRead(normalizedTabId, state.generation);
    return JSON.stringify(snapshot);
  }

  setSystemControl(tabId: string, payloadJson: string): string {
    const normalizedTabId = tabId.trim();
    const pending = this.pendingCommandByTabId.get(normalizedTabId);
    if (pending === undefined || payloadJson.length > MAX_MEDIA_FRAME_COMMAND_RESULT_PAYLOAD_LENGTH) {
      return '{"accepted":false}';
    }
    let payload: BrowserMediaFrameCommandResultPayload;
    try {
      payload = JSON.parse(payloadJson) as BrowserMediaFrameCommandResultPayload;
    } catch (_error) {
      return '{"accepted":false}';
    }
    const result = payload.result ?? '';
    if (payload.protocol !== MEDIA_VIDEO_FRAME_COMMAND_PROTOCOL || payload.channelId !== pending.channelId ||
      payload.requestId !== pending.requestId || payload.frameRuntimeId !== pending.frameRuntimeId ||
      payload.frameControlKey !== pending.frameControlKey || payload.action !== pending.action ||
      result.length > MAX_MEDIA_FRAME_COMMAND_RESULT_LENGTH) {
      return '{"accepted":false}';
    }
    clearTimeout(pending.timeoutId);
    this.pendingCommandByTabId.delete(normalizedTabId);
    pending.resolve(result);
    this.drainNextCommand(normalizedTabId);
    if (this.suppressDiagnosticsByTabId.get(normalizedTabId) === true) {
      return '{"accepted":true}';
    }
    hilog.info(
      MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
      MEDIA_FRAME_RUNTIME_LOG_TAG,
      'media_frame_command_result tab=%{public}s action=%{public}s ok=received',
      normalizedTabId,
      pending.action
    );
    return '{"accepted":true}';
  }

  close(_tabId: string): void {
  }

  executeFrameCommand(request: WebVideoFrameCommandRequest): Promise<string> {
    const tabId = request.tabId.trim();
    const frameRuntimeId = request.frameRuntimeId.trim();
    const action = request.action.trim();
    const script = request.script;
    if (tabId.length <= 0 || frameRuntimeId.length <= 0 || action.length <= 0 || action.length > 64 ||
      script.length <= 0 ||
      script.length > MAX_MEDIA_FRAME_COMMAND_SCRIPT_LENGTH) {
      return Promise.reject(new Error('invalid_frame_command'));
    }
    if (!this.isFrameTransportAvailable(tabId, frameRuntimeId)) {
      return Promise.reject(new Error('frame_transport_unavailable'));
    }
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void): void => {
      const queue = this.queuedCommandsByTabId.get(tabId) ?? [];
      if (queue.length >= MAX_QUEUED_MEDIA_FRAME_COMMANDS_PER_TAB) {
        reject(new Error('frame_command_queue_full'));
        return;
      }
      const queued: BrowserMediaFrameQueuedCommand = {
        request: {
          tabId: tabId,
          frameRuntimeId: frameRuntimeId,
          action: action,
          script: script
        },
        resolve: resolve,
        reject: reject
      };
      queue.push(queued);
      this.queuedCommandsByTabId.set(tabId, queue);
      this.drainNextCommand(tabId);
    });
  }

  private allocateChannel(generation: number): BrowserMediaFrameDocumentChannelState {
    const issuedAt = Date.now();
    const sequence = this.nextChannelSequence++;
    return {
      channelId: 'media-frame-channel:' + issuedAt.toString(36) + ':' + sequence.toString(36),
      generation: generation,
      issuedAt: issuedAt
    };
  }

  private readPendingFrameCommand(tabId: string, kind: string): string {
    const normalizedTabId = tabId.trim();
    const pending = this.pendingCommandByTabId.get(normalizedTabId);
    if (pending === undefined) {
      return '{}';
    }
    const frameControlKey = kind.substring(MEDIA_VIDEO_FRAME_COMMAND_KIND_PREFIX.length);
    if (frameControlKey.length <= 0 || frameControlKey !== pending.frameControlKey) {
      return '{}';
    }
    return JSON.stringify({
      protocol: MEDIA_VIDEO_FRAME_COMMAND_PROTOCOL,
      channelId: pending.channelId,
      requestId: pending.requestId,
      frameRuntimeId: pending.frameRuntimeId,
      frameControlKey: pending.frameControlKey,
      action: pending.action,
      script: pending.script
    });
  }

  private isFrameTransportAvailable(tabId: string, frameRuntimeId: string): boolean {
    const channel = this.channelByTabId.get(tabId);
    const frameControlKey = this.frameControlKeyByTabAndRuntimeId.get(tabId)?.get(frameRuntimeId) ?? '';
    return channel !== undefined && frameControlKey.length > 0 && this.hasReadyFrame(tabId, frameRuntimeId);
  }

  private drainNextCommand(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (this.pendingCommandByTabId.has(normalizedTabId)) {
      return;
    }
    const queue = this.queuedCommandsByTabId.get(normalizedTabId);
    if (queue === undefined) {
      return;
    }
    while (queue.length > 0) {
      const queued = queue.shift();
      if (queued === undefined) {
        break;
      }
      const frameRuntimeId = queued.request.frameRuntimeId.trim();
      const channel = this.channelByTabId.get(normalizedTabId);
      const frameControlKey = this.frameControlKeyByTabAndRuntimeId.get(normalizedTabId)?.get(frameRuntimeId) ?? '';
      if (channel === undefined || frameControlKey.length <= 0 ||
        !this.hasReadyFrame(normalizedTabId, frameRuntimeId)) {
        queued.reject(new Error('frame_transport_unavailable'));
        continue;
      }
      const requestId = 'media-frame-command:' + Date.now().toString(36) + ':' +
        (this.nextCommandSequence++).toString(36);
      const timeoutId = setTimeout((): void => {
        const current = this.pendingCommandByTabId.get(normalizedTabId);
        if (current === undefined || current.requestId !== requestId) {
          return;
        }
        this.pendingCommandByTabId.delete(normalizedTabId);
        current.reject(new Error('frame_command_timeout'));
        this.drainNextCommand(normalizedTabId);
      }, MEDIA_FRAME_COMMAND_TIMEOUT_MS);
      const pending: BrowserMediaFramePendingCommand = {
        requestId: requestId,
        frameRuntimeId: frameRuntimeId,
        frameControlKey: frameControlKey,
        channelId: channel.channelId,
        action: queued.request.action,
        script: queued.request.script,
        timeoutId: timeoutId,
        resolve: queued.resolve,
        reject: queued.reject
      };
      this.pendingCommandByTabId.set(normalizedTabId, pending);
      if (this.suppressDiagnosticsByTabId.get(normalizedTabId) === true) {
        return;
      }
      hilog.info(
        MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
        MEDIA_FRAME_RUNTIME_LOG_TAG,
        'media_frame_command_queued tab=%{public}s action=%{public}s frameRuntime=yes',
        normalizedTabId,
        pending.action
      );
      return;
    }
    this.queuedCommandsByTabId.delete(normalizedTabId);
  }

  private rejectPendingCommand(tabId: string, reason: string, drainNext: boolean = true): void {
    const normalizedTabId = tabId.trim();
    const pending = this.pendingCommandByTabId.get(normalizedTabId);
    if (pending === undefined) {
      return;
    }
    clearTimeout(pending.timeoutId);
    this.pendingCommandByTabId.delete(normalizedTabId);
    pending.reject(new Error(reason));
    if (drainNext) {
      this.drainNextCommand(normalizedTabId);
    }
  }

  private rejectCommandsForFrame(tabId: string, frameRuntimeId: string, reason: string): void {
    const normalizedTabId = tabId.trim();
    const normalizedFrameRuntimeId = frameRuntimeId.trim();
    const queue = this.queuedCommandsByTabId.get(normalizedTabId);
    if (queue !== undefined) {
      const retained: BrowserMediaFrameQueuedCommand[] = [];
      for (let i = 0; i < queue.length; i++) {
        if (queue[i].request.frameRuntimeId === normalizedFrameRuntimeId) {
          queue[i].reject(new Error(reason));
        } else {
          retained.push(queue[i]);
        }
      }
      if (retained.length > 0) {
        this.queuedCommandsByTabId.set(normalizedTabId, retained);
      } else {
        this.queuedCommandsByTabId.delete(normalizedTabId);
      }
    }
    const pending = this.pendingCommandByTabId.get(normalizedTabId);
    if (pending !== undefined && pending.frameRuntimeId === normalizedFrameRuntimeId) {
      this.rejectPendingCommand(normalizedTabId, reason);
      return;
    }
    this.drainNextCommand(normalizedTabId);
  }

  private rejectAllCommands(tabId: string, reason: string): void {
    const normalizedTabId = tabId.trim();
    this.rejectPendingCommand(normalizedTabId, reason, false);
    const queue = this.queuedCommandsByTabId.get(normalizedTabId);
    this.queuedCommandsByTabId.delete(normalizedTabId);
    if (queue === undefined) {
      return;
    }
    for (let i = 0; i < queue.length; i++) {
      queue[i].reject(new Error(reason));
    }
  }

  private logChannelRead(tabId: string, generation: number): void {
    if (this.suppressDiagnosticsByTabId.get(tabId) === true) {
      return;
    }
    const count = this.channelReadDiagnosticCountByTabId.get(tabId) ?? 0;
    if (count >= MAX_CHANNEL_READ_DIAGNOSTICS_PER_TAB) {
      return;
    }
    this.channelReadDiagnosticCountByTabId.set(tabId, count + 1);
    hilog.info(
      MEDIA_FRAME_RUNTIME_LOG_DOMAIN,
      MEDIA_FRAME_RUNTIME_LOG_TAG,
      'media_frame_probe_channel_read tab=%{public}s generation=%{public}d read=%{public}d',
      tabId,
      generation,
      count + 1
    );
  }
}

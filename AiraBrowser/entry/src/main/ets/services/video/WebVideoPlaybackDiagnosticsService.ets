import { hilog } from '@kit.PerformanceAnalysisKit';
import { WEB_VIDEO_LIVE_PRESENTATION_PROPERTY } from './WebVideoRuntimeProtocol';

// Shared by the document and child-frame probes. Read only: never changes the
// site's player, requests resources, or installs another polling timer.
export const WEB_VIDEO_PLAYBACK_HEALTH_SCRIPT: string = `
  function readAiraVideoPlaybackHealth(video) {
    var health = {
      timeMs: -1, aheadMs: -1, nextBufferMs: -1, liveLagMs: -1, rate: -1,
      ready: -1, network: -1, error: 0, paused: false, seeking: false,
      hidden: false, live: false, takeover: false, dropped: -1, frames: -1,
      airaSeeks: 0, airaPlays: 0, airaStyles: 0, airaReplacements: 0
    };
    try {
      var time = Number(video.currentTime);
      health.timeMs = Number.isFinite(time) ? Math.round(time * 1000) : -1;
      health.rate = Number(video.playbackRate);
      health.ready = Number(video.readyState);
      health.network = Number(video.networkState);
      health.error = Number(video.error && video.error.code || 0);
      health.paused = video.paused === true;
      health.seeking = video.seeking === true;
      health.hidden = !!(video.ownerDocument && video.ownerDocument.hidden);
      health.live = video.duration === Infinity;
      var state = video[${JSON.stringify(WEB_VIDEO_LIVE_PRESENTATION_PROPERTY)}];
      health.takeover = !!(state && state.active === true);
      if (state) {
        health.airaSeeks = Number(state.diagnosticSeeks || 0);
        health.airaPlays = Number(state.diagnosticPlays || 0);
        health.airaStyles = Number(state.diagnosticStyles || 0);
        health.airaReplacements = Number(state.diagnosticReplacements || 0);
      }
      var ranges = video.buffered;
      health.aheadMs = 0;
      for (var i = 0; ranges && i < Math.min(ranges.length, 128); i += 1) {
        var start = ranges.start(i);
        var end = ranges.end(i);
        if (start <= time && end >= time) {
          health.aheadMs = Math.max(0, Math.round((end - time) * 1000));
        } else if (start > time && health.nextBufferMs < 0) {
          health.nextBufferMs = Math.round((start - time) * 1000);
        }
      }
      var seekable = video.seekable;
      if (seekable && seekable.length > 0) {
        health.liveLagMs = Math.round((seekable.end(seekable.length - 1) - time) * 1000);
      }
      if (typeof video.getVideoPlaybackQuality === 'function') {
        var quality = video.getVideoPlaybackQuality();
        health.dropped = Number(quality.droppedVideoFrames);
        health.frames = Number(quality.totalVideoFrames);
      }
    } catch (_playbackHealthError) {
      // Partial snapshots are useful when MSE ranges change during a read.
    }
    return health;
  }
`;

interface WebVideoPlaybackHealth {
  timeMs?: number;
  aheadMs?: number;
  nextBufferMs?: number;
  liveLagMs?: number;
  rate?: number;
  ready?: number;
  network?: number;
  error?: number;
  paused?: boolean;
  seeking?: boolean;
  hidden?: boolean;
  live?: boolean;
  takeover?: boolean;
  dropped?: number;
  frames?: number;
  airaSeeks?: number;
  airaPlays?: number;
  airaStyles?: number;
  airaReplacements?: number;
}

interface WebVideoPlaybackHealthEvent {
  eventName?: string;
  runtimeId?: string;
  playbackHealth?: WebVideoPlaybackHealth;
}

interface WebVideoPlaybackHealthPayload {
  frameRuntimeId?: string;
  videoEvent?: WebVideoPlaybackHealthEvent;
}

interface WebVideoPlaybackDiagnosticTarget {
  key: string;
  lastSampleAt: number;
  windowStartedAt: number;
  lines: number;
  suppressed: number;
  waitingAt: number;
  waits: number;
}

export class WebVideoPlaybackDiagnosticsService {
  private targetsByTab: Map<string, WebVideoPlaybackDiagnosticTarget[]> = new Map();

  clearTab(tabId: string): void {
    this.targetsByTab.delete(tabId);
  }

  observe(tabId: string, payloadJson: string, suppressDiagnostics: boolean,
    transport: 'document_direct' | 'frame_proxy'): void {
    if (suppressDiagnostics) {
      this.clearTab(tabId);
      return;
    }
    if (payloadJson.length > 140000) {
      return;
    }
    try {
      const payload = JSON.parse(payloadJson) as WebVideoPlaybackHealthPayload;
      const event = payload.videoEvent;
      const health = event?.playbackHealth;
      const name = event?.eventName ?? '';
      if (health === undefined || typeof health !== 'object' || health === null ||
        !['loadstart', 'loadedmetadata', 'canplay', 'canplaythrough', 'play', 'playing', 'waiting',
          'stalled', 'seeking', 'seeked', 'pause', 'ended', 'emptied', 'abort', 'error',
          'ratechange', 'timeupdate'].includes(name) || typeof event?.runtimeId !== 'string' ||
        event.runtimeId.length <= 0 || event.runtimeId.length > 256) {
        return;
      }
      const now = Date.now();
      const key = transport + ':' + String(payload.frameRuntimeId ?? '').slice(0, 256) + ':' + event.runtimeId;
      const targets = this.targetsByTab.get(tabId) ?? [];
      let target = targets.find((item: WebVideoPlaybackDiagnosticTarget): boolean => item.key === key);
      if (target === undefined) {
        if (targets.length >= 16) {
          return;
        }
        target = { key: key, lastSampleAt: 0, windowStartedAt: now, lines: 0,
          suppressed: 0, waitingAt: 0, waits: 0 };
        targets.push(target);
        this.targetsByTab.set(tabId, targets);
      }
      let recoveredMs = -1;
      if (name === 'waiting') {
        target.waits += 1;
        if (target.waitingAt === 0) {
          target.waitingAt = now;
        }
      } else if (name === 'playing' && target.waitingAt > 0) {
        recoveredMs = Math.max(0, now - target.waitingAt);
        target.waitingAt = 0;
      } else if (['pause', 'ended', 'emptied', 'abort', 'error'].includes(name)) {
        target.waitingAt = 0;
      }
      if (name === 'timeupdate' && (health.takeover !== true || now - target.lastSampleAt < 5000)) {
        return;
      }
      if (now - target.windowStartedAt >= 1000) {
        target.windowStartedAt = now;
        target.lines = 0;
      }
      if (target.lines >= 8) {
        target.suppressed += 1;
        return;
      }
      target.lines += 1;
      target.lastSampleAt = now;
      // Serialize a fixed numeric/boolean vocabulary. Never print arbitrary page
      // strings, runtime IDs, URLs, token queries, error messages, or headers.
      const summary = `transport=${transport} target=${targets.indexOf(target)} event=${name} ` +
        `takeover=${health.takeover === true} tMs=${this.number(health.timeMs)} ` +
        `aheadMs=${this.number(health.aheadMs)} gapMs=${this.number(health.nextBufferMs)} ` +
        `lagMs=${this.number(health.liveLagMs)} rate=${this.number(health.rate)} ` +
        `ready=${this.number(health.ready)} network=${this.number(health.network)} ` +
        `paused=${health.paused === true} seeking=${health.seeking === true} hidden=${health.hidden === true} ` +
        `live=${health.live === true} error=${this.number(health.error)} ` +
        `dropped=${this.number(health.dropped)} frames=${this.number(health.frames)} ` +
        `airaSeeks=${this.number(health.airaSeeks)} airaPlays=${this.number(health.airaPlays)} ` +
        `airaStyles=${this.number(health.airaStyles)} airaReplacements=${this.number(health.airaReplacements)} ` +
        `waits=${target.waits} recoveredMs=${recoveredMs} suppressed=${target.suppressed}`;
      target.suppressed = 0;
      hilog.info(0x3900, 'AiraVideoHealth', 'video_playback_health %{public}s', summary);
    } catch (_error) {
    }
  }

  private number(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) ?
      Math.round(Math.max(-1, Math.min(1000000000000, value)) * 1000) / 1000 : -1;
  }
}

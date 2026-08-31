import {
  MediaEvidenceSemanticObservation,
  MediaFrameDocumentType,
  MediaPlaybackGeometryObservation,
  MediaPlaybackObservationEvent,
  MediaPlaybackTargetObservation,
  resolveFrameMediaDocumentKey,
  resolveFrameMediaPlaybackTargetKey
} from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import {
  MEDIA_VIDEO_FRAME_PROBE_PROTOCOL,
  MEDIA_VIDEO_FRAME_PROBE_SOURCE
} from '../../features/mediaDiscovery/MediaVideoFrameProbeScript';
import { MediaEvidenceLocatorIdentityService } from './MediaEvidenceLocatorIdentityService';

interface MediaVideoFrameProbeRectPayload {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

interface MediaVideoFrameProbeVideoEventPayload {
  eventName?: string;
  runtimeId?: string;
  elementId?: string;
  source?: string;
  muted?: boolean;
  paused?: boolean;
  ended?: boolean;
  seeking?: boolean;
  readyState?: number;
  networkState?: number;
  visible?: boolean;
  rect?: MediaVideoFrameProbeRectPayload;
  viewportWidth?: number;
  viewportHeight?: number;
  videoWidth?: number;
  videoHeight?: number;
  currentTime?: number;
  duration?: number;
}

interface MediaVideoFrameProbePayload {
  source?: string;
  protocol?: string;
  kind?: string;
  reason?: string;
  timestamp?: number;
  channelId?: string;
  frameRuntimeId?: string;
  frameControlKey?: string;
  frameUrl?: string;
  isMainFrame?: boolean;
  videoEvent?: MediaVideoFrameProbeVideoEventPayload;
}

export type MediaVideoFrameProbeEventKind = 'bootstrap' | 'ready' | 'video_event' | 'frame_ended';

export interface MediaVideoFrameProbeVideoSnapshot {
  eventName: string;
  runtimeId: string;
  elementId: string;
  source: string;
  muted?: boolean;
  paused?: boolean;
  ended?: boolean;
  seeking?: boolean;
  readyState: number;
  networkState: number;
  visible?: boolean;
  rect?: MediaPlaybackGeometryObservation;
  viewportWidth: number;
  viewportHeight: number;
  videoWidth: number;
  videoHeight: number;
  currentTime: number;
  duration: number;
}

export interface MediaVideoFrameProbeAdaptResult {
  kind: MediaVideoFrameProbeEventKind;
  channelId: string;
  frameRuntimeId: string;
  frameControlKey: string;
  frameType: MediaFrameDocumentType;
  targetKey: string;
  safeFrameLocator: string;
  sourceKind: string;
  eventName: string;
  reason: string;
  hasVideoRuntime: boolean;
  video?: MediaVideoFrameProbeVideoSnapshot;
  observedAt: number;
  observations: MediaEvidenceSemanticObservation[];
}

export class MediaVideoFrameProbeEvidenceAdapter {
  private locatorIdentityService: MediaEvidenceLocatorIdentityService = new MediaEvidenceLocatorIdentityService();

  isProbePayload(payloadJson: string): boolean {
    try {
      const payload = JSON.parse(payloadJson) as MediaVideoFrameProbePayload;
      return payload.source === MEDIA_VIDEO_FRAME_PROBE_SOURCE;
    } catch (_error) {
      return false;
    }
  }

  adapt(payloadJson: string, fallbackObservedAt: number): MediaVideoFrameProbeAdaptResult | undefined {
    let payload: MediaVideoFrameProbePayload;
    try {
      payload = JSON.parse(payloadJson) as MediaVideoFrameProbePayload;
    } catch (_error) {
      return undefined;
    }
    if (payload.source !== MEDIA_VIDEO_FRAME_PROBE_SOURCE ||
      payload.protocol !== MEDIA_VIDEO_FRAME_PROBE_PROTOCOL) {
      return undefined;
    }
    const kind = this.resolveKind(payload.kind);
    const channelId = this.boundedIdentity(payload.channelId);
    const frameRuntimeId = this.boundedIdentity(payload.frameRuntimeId);
    const frameControlKey = this.boundedIdentity(payload.frameControlKey);
    if (kind === undefined || frameRuntimeId.length <= 0 ||
      (kind !== 'bootstrap' && (channelId.length <= 0 || frameControlKey.length <= 0))) {
      return undefined;
    }
    const observedAt = this.resolveObservedAt(payload.timestamp, fallbackObservedAt);
    const frameType: MediaFrameDocumentType = payload.isMainFrame === true ?
      'main_document' : 'child_document';
    const frameDocumentKey = resolveFrameMediaDocumentKey(frameRuntimeId);
    const observations: MediaEvidenceSemanticObservation[] = [{
      kind: 'frame_document',
      frameDocumentKey: frameDocumentKey,
      frameType: frameType,
      lifecycle: kind === 'frame_ended' ? 'ended' : 'observed',
      documentUrl: payload.frameUrl,
      quality: 'direct'
    }];
    let eventName = '';
    let sourceKind = 'none';
    let hasVideoRuntime = false;
    let targetKey = '';
    let videoSnapshot: MediaVideoFrameProbeVideoSnapshot | undefined = undefined;
    if (kind === 'video_event') {
      const videoEvent = payload.videoEvent;
      const runtimeId = this.boundedIdentity(videoEvent?.runtimeId);
      if (videoEvent === undefined || runtimeId.length <= 0) {
        return undefined;
      }
      eventName = (videoEvent.eventName ?? '').trim().toLowerCase();
      const source = videoEvent.source?.trim() ?? '';
      sourceKind = this.resolveSourceKind(source);
      hasVideoRuntime = true;
      targetKey = resolveFrameMediaPlaybackTargetKey(frameRuntimeId, runtimeId);
      const geometry = this.buildGeometry(videoEvent);
      videoSnapshot = {
        eventName: eventName,
        runtimeId: runtimeId,
        elementId: videoEvent.elementId?.trim() ?? '',
        source: source,
        muted: videoEvent.muted,
        paused: videoEvent.paused,
        ended: videoEvent.ended,
        seeking: videoEvent.seeking,
        readyState: this.boundedInteger(videoEvent.readyState, 0, 4),
        networkState: this.boundedInteger(videoEvent.networkState, 0, 3),
        visible: videoEvent.visible,
        rect: geometry,
        viewportWidth: this.nonNegative(videoEvent.viewportWidth),
        viewportHeight: this.nonNegative(videoEvent.viewportHeight),
        videoWidth: this.nonNegative(videoEvent.videoWidth),
        videoHeight: this.nonNegative(videoEvent.videoHeight),
        currentTime: this.nonNegative(videoEvent.currentTime),
        duration: this.nonNegative(videoEvent.duration)
      };
      const sourceLocators: string[] = [];
      if (source.length > 0) {
        sourceLocators.push(source);
      }
      const target: MediaPlaybackTargetObservation = {
        kind: 'playback_target',
        targetKey: targetKey,
        targetIdentityQuality: 'stable',
        frameDocumentKey: frameDocumentKey,
        event: this.resolvePlaybackEvent(videoEvent),
        sourceLocators: sourceLocators,
        elementId: videoEvent.elementId?.trim(),
        muted: videoEvent.muted,
        currentTimeSeconds: this.optionalNonNegative(videoEvent.currentTime),
        durationSeconds: this.optionalNonNegative(videoEvent.duration),
        geometry: geometry,
        quality: 'direct'
      };
      observations.push(target);
    }
    const result: MediaVideoFrameProbeAdaptResult = {
      kind: kind,
      channelId: channelId,
      frameRuntimeId: frameRuntimeId,
      frameControlKey: frameControlKey,
      frameType: frameType,
      targetKey: targetKey,
      safeFrameLocator: this.locatorIdentityService.resolve(payload.frameUrl)?.safeLocator ?? '<unavailable>',
      sourceKind: sourceKind,
      eventName: eventName,
      reason: this.boundedIdentity(payload.reason),
      hasVideoRuntime: hasVideoRuntime,
      video: videoSnapshot,
      observedAt: observedAt,
      observations: observations
    };
    return result;
  }

  private resolveKind(value: string | undefined): MediaVideoFrameProbeEventKind | undefined {
    const normalized = (value ?? '').trim();
    if (normalized === 'bootstrap' || normalized === 'ready' || normalized === 'video_event' ||
      normalized === 'frame_ended') {
      return normalized;
    }
    return undefined;
  }

  private resolvePlaybackEvent(event: MediaVideoFrameProbeVideoEventPayload): MediaPlaybackObservationEvent {
    const eventName = (event.eventName ?? '').trim().toLowerCase();
    if (eventName === 'playing') {
      return 'playing';
    }
    if (eventName === 'ended' || event.ended === true) {
      return 'ended';
    }
    if (eventName === 'emptied' || eventName === 'abort') {
      return 'source_changed';
    }
    if (eventName === 'pause' || event.paused === true) {
      return 'paused';
    }
    if (eventName === 'resize' || eventName.indexOf('geometry_') === 0 ||
      eventName.indexOf('fullscreen') >= 0) {
      return 'geometry_changed';
    }
    return 'snapshot';
  }

  private buildGeometry(
    event: MediaVideoFrameProbeVideoEventPayload
  ): MediaPlaybackGeometryObservation | undefined {
    const rect = event.rect;
    if (rect === undefined && event.visible === undefined && event.videoWidth === undefined &&
      event.videoHeight === undefined) {
      return undefined;
    }
    return {
      x: this.finiteOrZero(rect?.x),
      y: this.finiteOrZero(rect?.y),
      width: this.nonNegative(rect?.width),
      height: this.nonNegative(rect?.height),
      viewportWidth: this.nonNegative(event.viewportWidth),
      viewportHeight: this.nonNegative(event.viewportHeight),
      visible: event.visible === true,
      videoWidth: this.nonNegative(event.videoWidth),
      videoHeight: this.nonNegative(event.videoHeight)
    };
  }

  private resolveObservedAt(value: number | undefined, fallback: number): number {
    if (value === undefined || !Number.isFinite(value) || value <= 0 ||
      Math.abs(value - fallback) > 60000) {
      return fallback;
    }
    return value;
  }

  private boundedIdentity(value: string | undefined): string {
    const normalized = (value ?? '').trim();
    return normalized.length <= 256 ? normalized : normalized.substring(0, 256);
  }

  private resolveSourceKind(source: string): string {
    const normalized = source.trim().toLowerCase();
    if (normalized.length <= 0) {
      return 'none';
    }
    if (normalized.indexOf('blob:') === 0) {
      return 'blob';
    }
    if (normalized.indexOf('data:') === 0) {
      return 'data';
    }
    if (normalized.indexOf('http://') === 0 || normalized.indexOf('https://') === 0) {
      return 'http';
    }
    return 'other';
  }

  private optionalNonNegative(value: number | undefined): number | undefined {
    if (value === undefined || !Number.isFinite(value)) {
      return undefined;
    }
    return Math.max(0, value);
  }

  private nonNegative(value: number | undefined): number {
    return Math.max(0, this.finiteOrZero(value));
  }

  private boundedInteger(value: number | undefined, minimum: number, maximum: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return minimum;
    }
    return Math.max(minimum, Math.min(maximum, Math.floor(value)));
  }

  private finiteOrZero(value: number | undefined): number {
    return value !== undefined && Number.isFinite(value) ? value : 0;
  }
}

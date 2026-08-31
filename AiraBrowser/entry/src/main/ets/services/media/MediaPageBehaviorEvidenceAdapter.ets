import {
  MediaEvidenceSemanticObservation,
  MediaPlaybackGeometryObservation,
  MediaPlaybackObservationEvent,
  MediaPlaybackTargetObservation,
  resolveDomMediaPlaybackTargetKey
} from '../../features/mediaDiscovery/MediaEvidenceGraphModels';

interface MediaPageBehaviorVideoRectPayload {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

interface MediaPageBehaviorVideoEventPayload {
  eventName?: string;
  runtimeId?: string;
  elementId?: string;
  source?: string;
  muted?: boolean;
  paused?: boolean;
  ended?: boolean;
  visible?: boolean;
  rect?: MediaPageBehaviorVideoRectPayload;
  viewportWidth?: number;
  viewportHeight?: number;
  videoWidth?: number;
  videoHeight?: number;
  currentTime?: number;
  duration?: number;
}

interface MediaPageBehaviorPayload {
  timestamp?: number;
  isVideoPlaying?: boolean;
  videoEvent?: MediaPageBehaviorVideoEventPayload;
}

export interface MediaPageBehaviorEvidenceAdaptResult {
  observedAt: number;
  observations: MediaEvidenceSemanticObservation[];
}

export class MediaPageBehaviorEvidenceAdapter {
  adapt(payloadJson: string, fallbackObservedAt: number): MediaPageBehaviorEvidenceAdaptResult {
    const emptyResult: MediaPageBehaviorEvidenceAdaptResult = {
      observedAt: fallbackObservedAt,
      observations: []
    };
    let payload: MediaPageBehaviorPayload;
    try {
      payload = JSON.parse(payloadJson) as MediaPageBehaviorPayload;
    } catch (_error) {
      return emptyResult;
    }
    const videoEvent = payload.videoEvent;
    if (videoEvent === undefined) {
      return emptyResult;
    }
    const runtimeId = videoEvent.runtimeId?.trim() ?? '';
    if (runtimeId.length <= 0) {
      return emptyResult;
    }
    const observedAt = this.positiveFinite(payload.timestamp, fallbackObservedAt);
    const observations: MediaEvidenceSemanticObservation[] = [];
    const source = videoEvent.source?.trim() ?? '';
    const sourceLocators: string[] = [];
    if (source.length > 0) {
      sourceLocators.push(source);
    }
    const targetObservation: MediaPlaybackTargetObservation = {
      kind: 'playback_target',
      targetKey: resolveDomMediaPlaybackTargetKey(runtimeId),
      targetIdentityQuality: 'stable',
      event: this.resolvePlaybackEvent(videoEvent, payload.isVideoPlaying === true),
      sourceLocators: sourceLocators,
      elementId: videoEvent.elementId?.trim(),
      muted: videoEvent.muted,
      currentTimeSeconds: this.optionalNonNegative(videoEvent.currentTime),
      durationSeconds: this.optionalNonNegative(videoEvent.duration),
      geometry: this.buildGeometry(videoEvent),
      quality: 'direct'
    };
    observations.push(targetObservation);
    const result: MediaPageBehaviorEvidenceAdaptResult = {
      observedAt: observedAt,
      observations: observations
    };
    return result;
  }

  private resolvePlaybackEvent(
    event: MediaPageBehaviorVideoEventPayload,
    isVideoPlaying: boolean
  ): MediaPlaybackObservationEvent {
    const eventName = event.eventName?.trim().toLowerCase() ?? '';
    if (eventName === 'ended' || event.ended === true) {
      return 'ended';
    }
    if (eventName === 'emptied' || eventName === 'abort') {
      return 'source_changed';
    }
    if (eventName === 'timeupdate') {
      return 'heartbeat';
    }
    if (eventName === 'resize' || eventName.indexOf('geometry_') === 0 ||
      eventName.indexOf('fullscreen') >= 0) {
      return 'geometry_changed';
    }
    if (eventName === 'playing') {
      return 'playing';
    }
    if (eventName === 'pause' || event.paused === true) {
      return 'paused';
    }
    if (isVideoPlaying) {
      return 'playing';
    }
    return 'snapshot';
  }

  private buildGeometry(
    event: MediaPageBehaviorVideoEventPayload
  ): MediaPlaybackGeometryObservation | undefined {
    const rect = event.rect;
    if (rect === undefined && event.visible === undefined && event.videoWidth === undefined &&
      event.videoHeight === undefined) {
      return undefined;
    }
    const geometry: MediaPlaybackGeometryObservation = {
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
    return geometry;
  }

  private positiveFinite(value: number | undefined, fallback: number): number {
    if (value !== undefined && Number.isFinite(value) && value > 0) {
      return value;
    }
    return fallback;
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

  private finiteOrZero(value: number | undefined): number {
    return value !== undefined && Number.isFinite(value) ? value : 0;
  }
}

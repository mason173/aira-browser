import { webview } from '@kit.ArkWeb';
import {
  MediaEvidenceSemanticObservation,
  MediaPlaybackGeometryObservation,
  MediaPlaybackTargetObservation
} from '../../features/mediaDiscovery/MediaEvidenceGraphModels';

export class MediaArkWebMediaInfoEvidenceAdapter {
  adapt(mediaInfo: webview.MediaInfo): MediaEvidenceSemanticObservation[] {
    const observations: MediaEvidenceSemanticObservation[] = [];
    if (mediaInfo.mediaType !== webview.MediaType.VIDEO) {
      return observations;
    }
    const embedId = mediaInfo.embedID.trim();
    const surfaceId = mediaInfo.surfaceInfo.id.trim();
    const sourceLocators: string[] = [];
    for (let i = 0; i < mediaInfo.mediaSrcList.length; i++) {
      const source = mediaInfo.mediaSrcList[i].source.trim();
      if (source.length > 0 && sourceLocators.indexOf(source) < 0) {
        sourceLocators.push(source);
      }
    }
    const targetKey = this.resolveTargetKey(embedId, surfaceId);
    const geometry: MediaPlaybackGeometryObservation = {
      x: this.finiteOrZero(mediaInfo.surfaceInfo.rect.x),
      y: this.finiteOrZero(mediaInfo.surfaceInfo.rect.y),
      width: this.nonNegative(mediaInfo.surfaceInfo.rect.width),
      height: this.nonNegative(mediaInfo.surfaceInfo.rect.height),
      viewportWidth: 0,
      viewportHeight: 0,
      visible: mediaInfo.surfaceInfo.rect.width > 1 && mediaInfo.surfaceInfo.rect.height > 1,
      videoWidth: 0,
      videoHeight: 0
    };
    const observation: MediaPlaybackTargetObservation = {
      kind: 'playback_target',
      targetKey: targetKey.length > 0 ? targetKey : undefined,
      targetIdentityQuality: targetKey.length > 0 ? 'ambiguous' : 'unattached',
      event: 'snapshot',
      sourceLocators: sourceLocators,
      muted: mediaInfo.muted,
      geometry: geometry,
      quality: 'direct'
    };
    observations.push(observation);
    return observations;
  }

  private resolveTargetKey(embedId: string, surfaceId: string): string {
    if (embedId.length > 0 || surfaceId.length > 0) {
      return 'arkweb:' + embedId + ':' + surfaceId;
    }
    return '';
  }

  private nonNegative(value: number): number {
    return Math.max(0, this.finiteOrZero(value));
  }

  private finiteOrZero(value: number): number {
    return Number.isFinite(value) ? value : 0;
  }
}

export type WebVideoFullscreenOrientationMode = 'portrait' | 'landscape';
export interface WebVideoFullscreenOrientationPayload {
  orientationMode?: string;
  mode?: string;
  sourceWidth?: number;
  sourceHeight?: number;
  width?: number;
  height?: number;
  videoWidth?: number;
  videoHeight?: number;
}

const WEB_VIDEO_FULLSCREEN_ORIENTATION_THRESHOLD: number = 1.05;

export class WebVideoFullscreenOrientationModel {
  resolveModeFromPayloadJson(payloadJson: string): WebVideoFullscreenOrientationMode {
    try {
      const payload = JSON.parse(payloadJson) as WebVideoFullscreenOrientationPayload;
      return this.resolveMode(payload);
    } catch (_error) {
      return 'landscape';
    }
  }

  resolveMode(payload: WebVideoFullscreenOrientationPayload): WebVideoFullscreenOrientationMode {
    const mode = this.resolveExplicitMode(payload.orientationMode) ??
      this.resolveExplicitMode(payload.mode) ??
      this.resolveModeFromDimensions(payload.sourceWidth ?? 0, payload.sourceHeight ?? 0) ??
      this.resolveModeFromDimensions(payload.videoWidth ?? 0, payload.videoHeight ?? 0) ??
      this.resolveModeFromDimensions(payload.width ?? 0, payload.height ?? 0);
    return mode ?? 'landscape';
  }

  private resolveExplicitMode(mode: string | undefined): WebVideoFullscreenOrientationMode | undefined {
    const normalizedMode = (mode ?? '').trim().toLowerCase();
    if (normalizedMode === 'portrait') {
      return 'portrait';
    }
    if (normalizedMode === 'landscape') {
      return 'landscape';
    }
    return undefined;
  }

  private resolveModeFromDimensions(
    width: number,
    height: number
  ): WebVideoFullscreenOrientationMode | undefined {
    const safeWidth = Math.max(0, Math.floor(width));
    const safeHeight = Math.max(0, Math.floor(height));
    if (safeWidth <= 0 || safeHeight <= 0) {
      return undefined;
    }
    if (safeHeight >= safeWidth * WEB_VIDEO_FULLSCREEN_ORIENTATION_THRESHOLD) {
      return 'portrait';
    }
    if (safeWidth >= safeHeight * WEB_VIDEO_FULLSCREEN_ORIENTATION_THRESHOLD) {
      return 'landscape';
    }
    return undefined;
  }
}

export interface AiraDownloadSnapshot {
  state: 'created' | 'running' | 'pausing' | 'paused' | 'completed' | 'failed' | 'canceled';
  receivedBytes: number;
  totalBytes: number;
  progressFraction: number;
  estimatedTotalBytes: number;
  speedBytesPerSecond: number;
  errorCode: number;
  errorMessage: string;
  diagnosticMessage: string;
  failurePhase: string;
  fileExtension: string;
}

export interface AiraDownloadNativeModule {
  createTask(
    url: string,
    targetPath: string,
    headers: string[],
    hls: boolean,
    caPath: string,
    hlsSegmentConcurrency: number,
    proxyScheme: string,
    proxyHost: string,
    proxyPort: number,
    proxyUsername: string,
    proxyPassword: string,
    proxyNoProxy: string
  ): number;
  startTask(handle: number): boolean;
  pauseTask(handle: number): boolean;
  resumeTask(handle: number): boolean;
  cancelTask(handle: number): boolean;
  releaseTask(handle: number): void;
  cleanupHlsArtifacts(targetPath: string): void;
  getSnapshot(handle: number): AiraDownloadSnapshot;
  backendVersion(): string;
  hlsPolicySummary(): string;
}

declare const nativeDownload: AiraDownloadNativeModule;
export default nativeDownload;

export interface DownloadRuntimeDiagnosticEvent {
  owner: string;
  operation: string;
  state: string;
  result: string;
}

export interface DownloadRuntimeDiagnosticRecorder {
  recordDownloadRuntimeDiagnostic(event: DownloadRuntimeDiagnosticEvent): void;
  recordDownloadRuntimeDiagnosticAndWait(event: DownloadRuntimeDiagnosticEvent): Promise<void>;
}

export function bucketRuntimeDiagnosticDuration(elapsedMs: number): string {
  const duration = Math.max(0, Math.floor(elapsedMs));
  if (duration < 10) {
    return 'lt10ms';
  }
  if (duration < 50) {
    return '10_49ms';
  }
  if (duration < 200) {
    return '50_199ms';
  }
  if (duration < 500) {
    return '200_499ms';
  }
  if (duration < 1000) {
    return '500_999ms';
  }
  if (duration < 2000) {
    return '1_2s';
  }
  if (duration < 5000) {
    return '2_5s';
  }
  return 'ge5s';
}

export type UserScriptRuntimeStatus = 'never_run' | 'success' | 'failed' | 'skipped';
export type UserScriptInjectionPhase =
  'document-start' |
  'document-idle' |
  'document-end' |
  'main-menu' |
  'tool-menu' |
  'context-menu' |
  'unknown';

export interface UserScriptRuntimeStateRecord {
  scriptId: string;
  status: UserScriptRuntimeStatus;
  lastUrl: string;
  lastInjectionPhase: UserScriptInjectionPhase;
  lastErrorMessage: string;
  lastSkipReason: string;
  lastBridgeCapability: string;
  lastBridgeRejectReason: string;
  lastRunAt: number;
  lastSuccessAt: number;
  lastFailureAt: number;
  runCount: number;
  failureCount: number;
}

export interface UserScriptRuntimeStateSettings {
  records: UserScriptRuntimeStateRecord[];
  updatedAt: number;
}

export function cloneUserScriptRuntimeStateRecord(
  record: UserScriptRuntimeStateRecord
): UserScriptRuntimeStateRecord {
  return {
    scriptId: record.scriptId,
    status: record.status,
    lastUrl: record.lastUrl,
    lastInjectionPhase: record.lastInjectionPhase,
    lastErrorMessage: record.lastErrorMessage,
    lastSkipReason: record.lastSkipReason,
    lastBridgeCapability: record.lastBridgeCapability,
    lastBridgeRejectReason: record.lastBridgeRejectReason,
    lastRunAt: record.lastRunAt,
    lastSuccessAt: record.lastSuccessAt,
    lastFailureAt: record.lastFailureAt,
    runCount: record.runCount,
    failureCount: record.failureCount
  };
}

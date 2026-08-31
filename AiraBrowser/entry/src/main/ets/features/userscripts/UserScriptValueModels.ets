export const USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION: number = 1;
export const USER_SCRIPT_VALUE_MAX_VALUE_BYTES: number = 16 * 1024 * 1024;
export const USER_SCRIPT_VALUE_MAX_STATE_BYTES: number = 96 * 1024 * 1024;

export type UserScriptValueMutationOperation = 'set' | 'delete';
export type UserScriptValueReadinessStatus = 'idle' | 'ready' | 'blocked';
export type UserScriptValueIncidentKind = 'none' | 'startup' | 'runtime_commit';
export type UserScriptValueFailureKind = 'validation' | 'readiness' | 'commit';
export type UserScriptValueDiagnosticKind =
  'startup_blocked' |
  'startup_backup_recovered' |
  'runtime_commit_failed' |
  'runtime_commit_recovered';

export interface UserScriptValueDiagnosticEvent {
  kind: UserScriptValueDiagnosticKind;
  stage: string;
  code: string;
  occurredAt: number;
}

export interface UserScriptValueDiagnosticSink {
  recordValueStateDiagnostic(event: UserScriptValueDiagnosticEvent): Promise<void>;
}

export interface UserScriptValueRecord {
  scriptId: string;
  key: string;
  valueJson: string;
  updatedAt: number;
}

export interface UserScriptValueStateDocument {
  schemaVersion: number;
  revision: number;
  values: UserScriptValueRecord[];
  updatedAt: number;
}

export interface UserScriptValueMutation {
  operation: UserScriptValueMutationOperation;
  key: string;
  valueJson: string;
}

export interface UserScriptValueReadinessSnapshot {
  status: UserScriptValueReadinessStatus;
  revision: number;
  failureStage: string;
  failureCode: string;
}

export interface UserScriptValueIncidentSnapshot {
  active: boolean;
  id: number;
  kind: UserScriptValueIncidentKind;
  stage: string;
  code: string;
  startedAt: number;
}

export interface UserScriptValueMigrationSummary {
  skippedScriptCount: number;
  skippedUnattributedRecordCount: number;
  unreadableLegacySnapshot: boolean;
}

export interface UserScriptValueManagementProjection {
  readiness: UserScriptValueReadinessSnapshot;
  incident: UserScriptValueIncidentSnapshot;
  migration: UserScriptValueMigrationSummary;
  revision: number;
  valueCount: number;
}

export interface UserScriptValueScriptManagementProjection {
  scriptId: string;
  records: UserScriptValueRecord[];
  readiness: UserScriptValueReadinessSnapshot;
}

export interface UserScriptValueRuntimeView {
  revision: number;
  snapshotLiteral: string;
}

export interface UserScriptValueCommitTransition {
  scriptId: string;
  key: string;
  hasOldValue: boolean;
  oldValueJson: string;
  hasNewValue: boolean;
  newValueJson: string;
}

export interface UserScriptValueCommitResult {
  revision: number;
  changed: boolean;
  transitions: UserScriptValueCommitTransition[];
  incidentRecovered: boolean;
}

export class UserScriptValueStateError extends Error {
  readonly failureKind: UserScriptValueFailureKind;
  readonly publicCode: string;
  readonly stage: string;
  readonly platformCode: string;
  readonly incidentId: number;
  readonly incidentStarted: boolean;

  constructor(
    failureKind: UserScriptValueFailureKind,
    publicCode: string,
    stage: string = '',
    platformCode: string = '',
    incidentId: number = 0,
    incidentStarted: boolean = false
  ) {
    super(publicCode);
    this.failureKind = failureKind;
    this.publicCode = publicCode;
    this.stage = stage;
    this.platformCode = platformCode;
    this.incidentId = incidentId;
    this.incidentStarted = incidentStarted;
  }
}

export function cloneUserScriptValueRecord(record: UserScriptValueRecord): UserScriptValueRecord {
  return {
    scriptId: record.scriptId,
    key: record.key,
    valueJson: record.valueJson,
    updatedAt: record.updatedAt
  };
}

export function cloneUserScriptValueReadinessSnapshot(
  snapshot: UserScriptValueReadinessSnapshot
): UserScriptValueReadinessSnapshot {
  return {
    status: snapshot.status,
    revision: snapshot.revision,
    failureStage: snapshot.failureStage,
    failureCode: snapshot.failureCode
  };
}

export function cloneUserScriptValueIncidentSnapshot(
  snapshot: UserScriptValueIncidentSnapshot
): UserScriptValueIncidentSnapshot {
  return {
    active: snapshot.active,
    id: snapshot.id,
    kind: snapshot.kind,
    stage: snapshot.stage,
    code: snapshot.code,
    startedAt: snapshot.startedAt
  };
}

export function cloneUserScriptValueMigrationSummary(
  summary: UserScriptValueMigrationSummary
): UserScriptValueMigrationSummary {
  return {
    skippedScriptCount: summary.skippedScriptCount,
    skippedUnattributedRecordCount: summary.skippedUnattributedRecordCount,
    unreadableLegacySnapshot: summary.unreadableLegacySnapshot
  };
}

export function cloneUserScriptValueCommitTransition(
  transition: UserScriptValueCommitTransition
): UserScriptValueCommitTransition {
  return {
    scriptId: transition.scriptId,
    key: transition.key,
    hasOldValue: transition.hasOldValue,
    oldValueJson: transition.oldValueJson,
    hasNewValue: transition.hasNewValue,
    newValueJson: transition.newValueJson
  };
}

import { buffer } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  cloneUserScriptValueCommitTransition,
  cloneUserScriptValueIncidentSnapshot,
  cloneUserScriptValueMigrationSummary,
  cloneUserScriptValueReadinessSnapshot,
  cloneUserScriptValueRecord,
  USER_SCRIPT_VALUE_MAX_STATE_BYTES,
  USER_SCRIPT_VALUE_MAX_VALUE_BYTES,
  USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
  UserScriptValueCommitResult,
  UserScriptValueCommitTransition,
  UserScriptValueDiagnosticEvent,
  UserScriptValueDiagnosticKind,
  UserScriptValueDiagnosticSink,
  UserScriptValueIncidentSnapshot,
  UserScriptValueManagementProjection,
  UserScriptValueMigrationSummary,
  UserScriptValueMutation,
  UserScriptValueReadinessSnapshot,
  UserScriptValueRecord,
  UserScriptValueRuntimeView,
  UserScriptValueScriptManagementProjection,
  UserScriptValueStateDocument,
  UserScriptValueStateError
} from '../../features/userscripts/UserScriptValueModels';
import {
  UserScriptValueDocumentValidationResult,
  UserScriptValueDocumentValidator
} from './UserScriptValueDocumentValidator';

const USER_SCRIPT_VALUE_MUTATION_BATCH_DELAY_MS: number = 12;
const USER_SCRIPT_VALUE_LOG_DOMAIN: number = 0x0000;
const USER_SCRIPT_VALUE_LOG_TAG: string = 'AiraUserScriptValue';

export interface UserScriptValueCommittedBytesAdapter {
  readonly persistenceLayout?: UserScriptValuePersistenceLayout;
  readCommitted(): Promise<Uint8Array | undefined>;
  readFallbackCommitted?: () => Promise<Uint8Array | undefined>;
  replaceCommitted(bytes: Uint8Array): Promise<void>;
  replaceCommittedScript?: (
    scriptId: string,
    revision: number,
    updatedAt: number,
    values: UserScriptValueRecord[]
  ) => Promise<void>;
  replaceCommittedRemovingScript?: (scriptId: string, bytes: Uint8Array) => Promise<void>;
  isScriptAvailable?: (scriptId: string) => boolean;
  readMigrationSummary?: () => UserScriptValueMigrationSummary;
  /**
   * Optional production fast path for compatibility-sensitive GM callers. When
   * present, the store completes the whole-file replacement before the
   * mutation Promise is returned, preserving the desktop expectation that a
   * GM_setValue/GM_deleteValue call can be followed immediately by reload().
   */
  replaceCommittedSync?: (bytes: Uint8Array) => void;
}

export type UserScriptValuePersistenceLayout = 'shared_document' | 'isolated_script_documents';

export type UserScriptValueStateStoreClock = () => number;

type UserScriptValueCommandKind = 'mutations' | 'delete-package' | 'barrier';

interface UserScriptValueCommandRequest {
  kind: UserScriptValueCommandKind;
  scriptId: string;
  mutations: UserScriptValueMutation[];
  acceptedAt: number;
  resolve: (result: UserScriptValueCommitResult) => void;
  reject: (error: UserScriptValueStateError) => void;
}

interface UserScriptValueBatchCommit {
  document: UserScriptValueStateDocument;
  transitions: UserScriptValueCommitTransition[];
  incidentRecovered: boolean;
}

interface UserScriptValueFailureShape {
  stage?: string;
  platformCode?: string;
}

interface UserScriptValueResolvedFailure {
  stage: string;
  code: string;
}

export class UserScriptValueStateLimits {
  readonly maxValueBytes: number;
  readonly maxStateBytes: number;

  constructor(
    maxValueBytes: number = USER_SCRIPT_VALUE_MAX_VALUE_BYTES,
    maxStateBytes: number = USER_SCRIPT_VALUE_MAX_STATE_BYTES
  ) {
    this.maxValueBytes = Math.max(1, maxValueBytes);
    this.maxStateBytes = Math.max(1, maxStateBytes);
  }
}

export class UserScriptValueStateStore {
  private readonly adapter: UserScriptValueCommittedBytesAdapter;
  private readonly batchDelayMs: number;
  private readonly clock: UserScriptValueStateStoreClock;
  private readonly limits: UserScriptValueStateLimits;
  private readonly documentValidator: UserScriptValueDocumentValidator = new UserScriptValueDocumentValidator();
  private initializationPromise?: Promise<UserScriptValueReadinessSnapshot>;
  private readiness: UserScriptValueReadinessSnapshot = {
    status: 'idle',
    revision: 0,
    failureStage: '',
    failureCode: ''
  };
  private incident: UserScriptValueIncidentSnapshot = {
    active: false,
    id: 0,
    kind: 'none',
    stage: '',
    code: '',
    startedAt: 0
  };
  private incidentSerial: number = 0;
  private document: UserScriptValueStateDocument = this.createEmptyDocument(0, 0);
  private admissionDocument: UserScriptValueStateDocument = this.createEmptyDocument(0, 0);
  private pendingCommands: UserScriptValueCommandRequest[] = [];
  private batchTimer: number = -1;
  private commitActive: boolean = false;
  private diagnosticSink?: UserScriptValueDiagnosticSink;

  constructor(
    adapter: UserScriptValueCommittedBytesAdapter,
    batchDelayMs: number = USER_SCRIPT_VALUE_MUTATION_BATCH_DELAY_MS,
    clock: UserScriptValueStateStoreClock = (): number => Date.now(),
    limits: UserScriptValueStateLimits = new UserScriptValueStateLimits()
  ) {
    this.adapter = adapter;
    this.batchDelayMs = Math.max(0, batchDelayMs);
    this.clock = clock;
    this.limits = limits;
  }

  initialize(): Promise<UserScriptValueReadinessSnapshot> {
    if (this.readiness.status === 'ready') {
      return Promise.resolve(cloneUserScriptValueReadinessSnapshot(this.readiness));
    }
    if (this.readiness.status === 'blocked') {
      return Promise.reject(this.createReadinessError());
    }
    if (this.initializationPromise !== undefined) {
      return this.initializationPromise;
    }
    const pending = this.initializeState();
    this.initializationPromise = pending;
    pending.then(
      (): void => this.clearInitializationPromise(pending),
      (_error: Error): void => this.clearInitializationPromise(pending)
    );
    return pending;
  }

  attachDiagnosticSink(sink: UserScriptValueDiagnosticSink): void {
    this.diagnosticSink = sink;
  }

  readReadiness(): UserScriptValueReadinessSnapshot {
    return cloneUserScriptValueReadinessSnapshot(this.readiness);
  }

  isScriptStateAvailable(scriptId: string): boolean {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0 || this.readiness.status !== 'ready') {
      return false;
    }
    return this.adapter.isScriptAvailable?.(normalizedScriptId) ?? true;
  }

  readManagementProjection(): UserScriptValueManagementProjection {
    const migration = this.adapter.readMigrationSummary?.() ?? {
      skippedScriptCount: 0,
      skippedUnattributedRecordCount: 0,
      unreadableLegacySnapshot: false
    };
    return {
      readiness: cloneUserScriptValueReadinessSnapshot(this.readiness),
      incident: cloneUserScriptValueIncidentSnapshot(this.incident),
      migration: cloneUserScriptValueMigrationSummary(migration),
      revision: this.readiness.status === 'ready' ? this.document.revision : 0,
      valueCount: this.readiness.status === 'ready' ? this.document.values.length : 0
    };
  }

  readScriptManagementProjection(scriptId: string): UserScriptValueScriptManagementProjection {
    const normalizedScriptId = scriptId.trim();
    const records = !this.isScriptStateAvailable(normalizedScriptId) ? [] :
      this.document.values
        .filter((record: UserScriptValueRecord): boolean => record.scriptId === normalizedScriptId)
        .map((record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record));
    return {
      scriptId: normalizedScriptId,
      records: records,
      readiness: cloneUserScriptValueReadinessSnapshot(this.readiness)
    };
  }

  readCommittedRuntimeView(scriptId: string): UserScriptValueRuntimeView {
    this.requireReady();
    const normalizedScriptId = scriptId.trim();
    this.requireScriptAvailable(normalizedScriptId);
    const entries: string[] = [];
    this.document.values.forEach((record: UserScriptValueRecord): void => {
      if (record.scriptId === normalizedScriptId) {
        entries.push(`${JSON.stringify(record.key)}:${record.valueJson}`);
      }
    });
    return {
      revision: this.document.revision,
      snapshotLiteral: `{${entries.join(',')}}`
    };
  }

  readCommittedValueJson(scriptId: string, key: string): string | undefined {
    this.requireReady();
    const normalizedScriptId = scriptId.trim();
    this.requireScriptAvailable(normalizedScriptId);
    const normalizedKey = key.trim();
    if (normalizedScriptId.length === 0 || normalizedKey.length === 0) {
      return undefined;
    }
    return this.document.values.find((record: UserScriptValueRecord): boolean => {
      return record.scriptId === normalizedScriptId && record.key === normalizedKey;
    })?.valueJson;
  }

  readCommittedKeys(scriptId: string): string[] {
    this.requireReady();
    const normalizedScriptId = scriptId.trim();
    this.requireScriptAvailable(normalizedScriptId);
    const keys: string[] = [];
    this.document.values.forEach((record: UserScriptValueRecord): void => {
      if (record.scriptId === normalizedScriptId && !keys.includes(record.key)) {
        keys.push(record.key);
      }
    });
    return keys;
  }

  async commitMutations(
    scriptId: string,
    mutations: UserScriptValueMutation[]
  ): Promise<UserScriptValueCommitResult> {
    if (this.readiness.status !== 'ready') {
      await this.initialize();
    }
    const normalizedScriptId = this.requireScriptId(scriptId);
    this.requireScriptAvailable(normalizedScriptId);
    const normalizedMutations = this.normalizeMutations(normalizedScriptId, mutations);
    if (normalizedMutations.length === 0) {
      return this.createUnchangedResult();
    }
    if (this.adapter.replaceCommittedSync !== undefined) {
      return this.commitSynchronousCommand('mutations', normalizedScriptId, normalizedMutations);
    }
    return this.enqueueCommand('mutations', normalizedScriptId, normalizedMutations);
  }

  async synchronizeCommands(scriptId: string): Promise<void> {
    if (this.readiness.status !== 'ready') {
      await this.initialize();
    }
    const normalizedScriptId = this.requireScriptId(scriptId);
    if (this.adapter.replaceCommittedSync !== undefined) {
      return;
    }
    await this.enqueueCommand('barrier', normalizedScriptId, []);
  }

  async deletePackageValues(scriptId: string): Promise<UserScriptValueCommitResult> {
    if (this.readiness.status !== 'ready') {
      await this.initialize();
    }
    const normalizedScriptId = this.requireScriptId(scriptId);
    if (this.adapter.replaceCommittedSync !== undefined) {
      return this.commitSynchronousCommand('delete-package', normalizedScriptId, []);
    }
    return this.enqueueCommand('delete-package', normalizedScriptId, []);
  }

  private commitSynchronousCommand(
    kind: 'mutations' | 'delete-package',
    scriptId: string,
    mutations: UserScriptValueMutation[]
  ): UserScriptValueCommitResult {
    this.requireReady();
    const acceptedAt = this.clock();
    const previousDocument = this.cloneDocument(this.document);
    let nextValues = previousDocument.values.map((record: UserScriptValueRecord): UserScriptValueRecord => {
      return cloneUserScriptValueRecord(record);
    });
    if (kind === 'delete-package') {
      nextValues = nextValues.filter((record: UserScriptValueRecord): boolean => record.scriptId !== scriptId);
    } else {
      mutations.forEach((mutation: UserScriptValueMutation): void => {
        this.applyMutation(nextValues, scriptId, mutation, acceptedAt);
      });
    }
    this.restoreMetadataForUnchangedValues(previousDocument.values, nextValues);
    const transitions = this.buildTransitions(previousDocument.values, nextValues);
    if (transitions.length === 0) {
      this.admissionDocument = this.cloneDocument(this.document);
      return this.createUnchangedResult();
    }
    const nextDocument: UserScriptValueStateDocument = {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: previousDocument.revision + 1,
      values: nextValues,
      updatedAt: acceptedAt
    };
    const encoded = this.encodeDocument(nextDocument);
    if (this.adapter.replaceCommittedSync === undefined) {
      throw this.createCommitError(new Error('synchronous-commit-unavailable'));
    }
    try {
      this.adapter.replaceCommittedSync(encoded);
    } catch (error) {
      this.admissionDocument = this.cloneDocument(this.document);
      throw this.createCommitError(error as Error);
    }
    const incidentRecovered = this.incident.active;
    this.document = this.cloneDocument(nextDocument);
    this.admissionDocument = this.cloneDocument(nextDocument);
    this.readiness = {
      status: 'ready',
      revision: nextDocument.revision,
      failureStage: '',
      failureCode: ''
    };
    this.clearIncident();
    return {
      revision: nextDocument.revision,
      changed: true,
      transitions: transitions.map((transition: UserScriptValueCommitTransition): UserScriptValueCommitTransition => {
        return cloneUserScriptValueCommitTransition(transition);
      }),
      incidentRecovered: incidentRecovered
    };
  }

  private async initializeState(): Promise<UserScriptValueReadinessSnapshot> {
    let nextDocument: UserScriptValueStateDocument = this.createEmptyDocument(0, 0);
    try {
      let primaryMissing = false;
      let primaryFailure: Error | undefined;
      try {
        const bytes = await this.adapter.readCommitted();
        if (bytes === undefined) {
          primaryMissing = true;
        } else {
          nextDocument = this.decodeDocument(bytes);
        }
      } catch (error) {
        primaryFailure = this.normalizeError(error, 'primary-read-failed');
      }
      if (primaryMissing || primaryFailure !== undefined) {
        const recovered = await this.tryRecoverFallback(primaryFailure);
        if (recovered !== undefined) {
          nextDocument = recovered;
        } else if (primaryFailure !== undefined) {
          throw primaryFailure;
        } else {
          await this.adapter.replaceCommitted(this.encodeDocument(nextDocument));
        }
      }
      this.document = this.cloneDocument(nextDocument);
      this.admissionDocument = this.cloneDocument(nextDocument);
      this.readiness = {
        status: 'ready',
        revision: nextDocument.revision,
        failureStage: '',
        failureCode: ''
      };
      this.clearIncident();
      return cloneUserScriptValueReadinessSnapshot(this.readiness);
    } catch (error) {
      const failure = this.resolveFailure(error, 'initialize');
      this.readiness = {
        status: 'blocked',
        revision: 0,
        failureStage: failure.stage,
        failureCode: failure.code
      };
      const incident = this.openIncident('startup', failure.stage, failure.code);
      hilog.error(
        USER_SCRIPT_VALUE_LOG_DOMAIN,
        USER_SCRIPT_VALUE_LOG_TAG,
        'readiness blocked stage=%{public}s code=%{public}s incident=%{public}d',
        failure.stage,
        failure.code,
        incident.id
      );
      throw this.createReadinessError();
    }
  }

  private async tryRecoverFallback(
    primaryFailure: Error | undefined
  ): Promise<UserScriptValueStateDocument | undefined> {
    if (this.adapter.readFallbackCommitted === undefined) {
      return undefined;
    }
    let fallbackBytes: Uint8Array | undefined;
    try {
      fallbackBytes = await this.adapter.readFallbackCommitted();
    } catch (error) {
      throw this.normalizeError(error, 'fallback-read-failed');
    }
    if (fallbackBytes === undefined) {
      return undefined;
    }
    const recoveredDocument = this.decodeDocument(fallbackBytes);
    await this.adapter.replaceCommitted(fallbackBytes);
    const failure: UserScriptValueResolvedFailure = primaryFailure === undefined ?
      { stage: 'read', code: 'not-found' } : this.resolveFailure(primaryFailure, 'read');
    hilog.warn(
      USER_SCRIPT_VALUE_LOG_DOMAIN,
      USER_SCRIPT_VALUE_LOG_TAG,
      'startup state recovered stage=%{public}s code=%{public}s',
      failure.stage,
      failure.code
    );
    this.recordDiagnostic('startup_backup_recovered', failure.stage, failure.code);
    return recoveredDocument;
  }

  private normalizeError(
    error: Object | string | number | boolean | undefined,
    fallbackMessage: string
  ): Error {
    return error instanceof Error ? error : new Error(fallbackMessage);
  }

  private enqueueCommand(
    kind: UserScriptValueCommandKind,
    scriptId: string,
    mutations: UserScriptValueMutation[]
  ): Promise<UserScriptValueCommitResult> {
    const acceptedAt = this.clock();
    const nextAdmissionDocument = this.projectAdmissionCommand(
      this.admissionDocument,
      kind,
      scriptId,
      mutations,
      acceptedAt
    );
    return new Promise<UserScriptValueCommitResult>((resolve, reject) => {
      this.pendingCommands.push({
        kind: kind,
        scriptId: scriptId,
        mutations: mutations,
        acceptedAt: acceptedAt,
        resolve: resolve,
        reject: (error: UserScriptValueStateError): void => {
          reject(error);
        }
      });
      this.admissionDocument = nextAdmissionDocument;
      this.scheduleBatch();
    });
  }

  private scheduleBatch(): void {
    if (this.commitActive || this.batchTimer >= 0 || this.pendingCommands.length === 0) {
      return;
    }
    this.batchTimer = setTimeout((): void => {
      this.batchTimer = -1;
      this.flushNextBatch();
    }, this.batchDelayMs);
  }

  private flushNextBatch(): void {
    if (this.commitActive || this.pendingCommands.length === 0) {
      return;
    }
    const batch = this.takeNextBatch();
    this.commitActive = true;
    this.commitBatch(batch)
      .then((commit: UserScriptValueBatchCommit): void => {
        this.rebuildAdmissionDocument();
        batch.forEach((request: UserScriptValueCommandRequest): void => {
          request.resolve(this.buildRequestResult(request, commit));
        });
      })
      .catch((error: Error): void => {
        const stateError: UserScriptValueStateError = this.createCommitError(error);
        this.rebuildAdmissionDocument();
        batch.forEach((request: UserScriptValueCommandRequest): void => {
          request.reject(stateError);
        });
      })
      .finally((): void => {
        this.commitActive = false;
        this.scheduleBatch();
      });
  }

  private takeNextBatch(): UserScriptValueCommandRequest[] {
    const batch: UserScriptValueCommandRequest[] = [];
    while (this.pendingCommands.length > 0) {
      const candidate = this.pendingCommands[0];
      if (batch.length > 0 && candidate.scriptId !== batch[0].scriptId) {
        break;
      }
      const next = this.pendingCommands.shift();
      if (next === undefined) {
        break;
      }
      batch.push(next);
      if (next.kind === 'barrier') {
        break;
      }
    }
    return batch;
  }

  private async commitBatch(batch: UserScriptValueCommandRequest[]): Promise<UserScriptValueBatchCommit> {
    if (this.readiness.status !== 'ready') {
      throw this.createReadinessError();
    }
    const previousDocument = this.cloneDocument(this.document);
    const updatedAt = this.resolveBatchUpdatedAt(batch, previousDocument.updatedAt);
    let nextValues = previousDocument.values.map((record: UserScriptValueRecord): UserScriptValueRecord => {
      return cloneUserScriptValueRecord(record);
    });
    batch.forEach((request: UserScriptValueCommandRequest): void => {
      if (request.kind === 'delete-package') {
        nextValues = nextValues.filter((record: UserScriptValueRecord): boolean => {
          return record.scriptId !== request.scriptId;
        });
        return;
      }
      request.mutations.forEach((mutation: UserScriptValueMutation): void => {
        this.applyMutation(nextValues, request.scriptId, mutation, request.acceptedAt);
      });
    });
    this.restoreMetadataForUnchangedValues(previousDocument.values, nextValues);
    const transitions = this.buildTransitions(previousDocument.values, nextValues);
    const stateChanged = transitions.length > 0;
    const batchScriptId = batch.length > 0 ? batch[0].scriptId : '';
    const removeScriptState = batchScriptId.length > 0 &&
      batch.some((request: UserScriptValueCommandRequest): boolean => request.kind === 'delete-package') &&
      !nextValues.some((record: UserScriptValueRecord): boolean => record.scriptId === batchScriptId);
    if (!stateChanged) {
      if (removeScriptState && this.adapter.replaceCommittedRemovingScript !== undefined) {
        await this.adapter.replaceCommittedRemovingScript(batchScriptId, this.encodeDocument(previousDocument));
      }
      return {
        document: previousDocument,
        transitions: [],
        incidentRecovered: false
      };
    }
    const nextRevision = previousDocument.revision + 1;
    const nextDocument: UserScriptValueStateDocument = {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: nextRevision,
      values: nextValues,
      updatedAt: updatedAt
    };
    if (removeScriptState && this.adapter.replaceCommittedRemovingScript !== undefined) {
      await this.adapter.replaceCommittedRemovingScript(batchScriptId, this.encodeDocument(nextDocument));
    } else if (batchScriptId.length > 0 && this.adapter.replaceCommittedScript !== undefined) {
      const scriptValues = nextValues
        .filter((record: UserScriptValueRecord): boolean => record.scriptId === batchScriptId)
        .map((record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record));
      await this.adapter.replaceCommittedScript(batchScriptId, nextRevision, updatedAt, scriptValues);
    } else {
      await this.adapter.replaceCommitted(this.encodeDocument(nextDocument));
    }
    const incidentRecovered = this.incident.active;
    this.document = this.cloneDocument(nextDocument);
    this.readiness = {
      status: 'ready',
      revision: nextRevision,
      failureStage: '',
      failureCode: ''
    };
    this.clearIncident();
    return {
      document: this.cloneDocument(nextDocument),
      transitions: transitions,
      incidentRecovered: incidentRecovered
    };
  }

  private buildRequestResult(
    request: UserScriptValueCommandRequest,
    commit: UserScriptValueBatchCommit
  ): UserScriptValueCommitResult {
    const transitions = commit.transitions.filter(
      (transition: UserScriptValueCommitTransition): boolean => transition.scriptId === request.scriptId
    );
    return {
      revision: commit.document.revision,
      changed: transitions.length > 0,
      transitions: transitions.map((transition: UserScriptValueCommitTransition): UserScriptValueCommitTransition => {
        return cloneUserScriptValueCommitTransition(transition);
      }),
      incidentRecovered: commit.incidentRecovered
    };
  }

  private applyMutation(
    values: UserScriptValueRecord[],
    scriptId: string,
    mutation: UserScriptValueMutation,
    updatedAt: number
  ): void {
    const existingIndex = values.findIndex((record: UserScriptValueRecord): boolean => {
      return record.scriptId === scriptId && record.key === mutation.key;
    });
    if (mutation.operation === 'delete') {
      if (existingIndex >= 0) {
        values.splice(existingIndex, 1);
      }
      return;
    }
    const nextRecord: UserScriptValueRecord = {
      scriptId: scriptId,
      key: mutation.key,
      valueJson: mutation.valueJson,
      updatedAt: updatedAt
    };
    if (existingIndex >= 0) {
      values.splice(existingIndex, 1, nextRecord);
    } else {
      values.push(nextRecord);
    }
  }

  private restoreMetadataForUnchangedValues(
    previousValues: UserScriptValueRecord[],
    nextValues: UserScriptValueRecord[]
  ): void {
    nextValues.forEach((nextRecord: UserScriptValueRecord): void => {
      const previousRecord = previousValues.find((record: UserScriptValueRecord): boolean => {
        return record.scriptId === nextRecord.scriptId && record.key === nextRecord.key;
      });
      if (previousRecord !== undefined && previousRecord.valueJson === nextRecord.valueJson) {
        nextRecord.updatedAt = previousRecord.updatedAt;
      }
    });
  }

  private buildTransitions(
    previousValues: UserScriptValueRecord[],
    nextValues: UserScriptValueRecord[]
  ): UserScriptValueCommitTransition[] {
    const keys: string[] = [];
    previousValues.concat(nextValues).forEach((record: UserScriptValueRecord): void => {
      const identity = this.buildRecordIdentity(record.scriptId, record.key);
      if (!keys.includes(identity)) {
        keys.push(identity);
      }
    });
    const transitions: UserScriptValueCommitTransition[] = [];
    keys.forEach((identity: string): void => {
      const previousRecord = previousValues.find((record: UserScriptValueRecord): boolean => {
        return this.buildRecordIdentity(record.scriptId, record.key) === identity;
      });
      const nextRecord = nextValues.find((record: UserScriptValueRecord): boolean => {
        return this.buildRecordIdentity(record.scriptId, record.key) === identity;
      });
      if (previousRecord?.valueJson === nextRecord?.valueJson) {
        return;
      }
      const source = nextRecord ?? previousRecord;
      if (source === undefined) {
        return;
      }
      transitions.push({
        scriptId: source.scriptId,
        key: source.key,
        hasOldValue: previousRecord !== undefined,
        oldValueJson: previousRecord?.valueJson ?? '',
        hasNewValue: nextRecord !== undefined,
        newValueJson: nextRecord?.valueJson ?? ''
      });
    });
    return transitions;
  }

  private normalizeMutations(scriptId: string, mutations: UserScriptValueMutation[]): UserScriptValueMutation[] {
    const normalized: UserScriptValueMutation[] = [];
    mutations.forEach((mutation: UserScriptValueMutation): void => {
      const key = String(mutation.key ?? '').trim();
      if (key.length === 0) {
        throw this.createValidationError('invalid-key');
      }
      if (mutation.operation === 'delete') {
        normalized.push({
          operation: 'delete',
          key: key,
          valueJson: ''
        });
        return;
      }
      const valueJson = String(mutation.valueJson ?? '');
      if (valueJson.length === 0) {
        throw this.createValidationError('empty-value');
      }
      try {
        JSON.parse(valueJson);
      } catch (_error) {
        throw this.createValidationError('invalid-json');
      }
      const valueBytes = buffer.from(valueJson, 'utf8').length;
      if (valueBytes > this.limits.maxValueBytes) {
        hilog.warn(
          USER_SCRIPT_VALUE_LOG_DOMAIN,
          USER_SCRIPT_VALUE_LOG_TAG,
          'mutation rejected reason=%{public}s valueBytes=%{public}d',
          'value-too-large',
          valueBytes
        );
        throw this.createValidationError('value-too-large');
      }
      normalized.push({
        operation: 'set',
        key: key,
        valueJson: valueJson
      });
    });
    return normalized;
  }

  private encodeDocument(document: UserScriptValueStateDocument): Uint8Array {
    if (this.usesIsolatedScriptDocuments()) {
      this.validateIsolatedDocumentCapacities(document);
    }
    let serialized: string;
    try {
      serialized = JSON.stringify(document);
    } catch (_error) {
      throw new UserScriptValueStateError('commit', 'userscript-value-persist-failed', 'encode', 'json');
    }
    const encoded = buffer.from(serialized, 'utf8');
    if (!this.usesIsolatedScriptDocuments() && encoded.length > this.limits.maxStateBytes) {
      throw new UserScriptValueStateError(
        'validation',
        'userscript-value-rejected:state-too-large',
        'validation',
        'state-too-large'
      );
    }
    const bytes = new Uint8Array(encoded.length);
    for (let index = 0; index < encoded.length; index += 1) {
      bytes[index] = encoded[index];
    }
    return bytes;
  }

  private decodeDocument(bytes: Uint8Array): UserScriptValueStateDocument {
    if (bytes.byteLength <= 0 ||
      (!this.usesIsolatedScriptDocuments() && bytes.byteLength > this.limits.maxStateBytes)) {
      throw new UserScriptValueStateError('readiness', 'userscript-value-state-unavailable', 'decode-size', 'invalid-size');
    }
    let raw: string;
    try {
      raw = buffer.from(bytes).toString('utf8');
    } catch (_error) {
      throw new UserScriptValueStateError('readiness', 'userscript-value-state-unavailable', 'decode-text', 'utf-8');
    }
    if (raw.trim().length === 0) {
      throw new UserScriptValueStateError('readiness', 'userscript-value-state-unavailable', 'decode-json', 'empty');
    }
    let document: UserScriptValueStateDocument;
    try {
      document = JSON.parse(raw) as UserScriptValueStateDocument;
    } catch (_error) {
      throw new UserScriptValueStateError('readiness', 'userscript-value-state-unavailable', 'decode-json', 'invalid');
    }
    this.validateDocument(document);
    if (this.usesIsolatedScriptDocuments()) {
      this.validateIsolatedDocumentCapacities(document);
    }
    return this.cloneDocument(document);
  }

  private validateIsolatedDocumentCapacities(document: UserScriptValueStateDocument): void {
    const scriptIds: string[] = [];
    document.values.forEach((record: UserScriptValueRecord): void => {
      if (!scriptIds.includes(record.scriptId)) {
        scriptIds.push(record.scriptId);
      }
    });
    scriptIds.forEach((scriptId: string): void => {
      const isolatedShape: UserScriptValueStateDocument = {
        schemaVersion: document.schemaVersion,
        revision: document.revision,
        values: document.values
          .filter((record: UserScriptValueRecord): boolean => record.scriptId === scriptId)
          .map((record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record)),
        updatedAt: document.updatedAt
      };
      let serialized: string;
      try {
        serialized = JSON.stringify(isolatedShape);
      } catch (_error) {
        throw new UserScriptValueStateError('commit', 'userscript-value-persist-failed', 'encode', 'json');
      }
      if (buffer.from(serialized, 'utf8').length > this.limits.maxStateBytes) {
        throw new UserScriptValueStateError(
          'validation',
          'userscript-value-rejected:state-too-large',
          'validation',
          'state-too-large'
        );
      }
    });
  }

  private validateDocument(document: UserScriptValueStateDocument): void {
    const validation: UserScriptValueDocumentValidationResult = this.documentValidator.validate(
      document,
      this.limits.maxValueBytes
    );
    if (!validation.valid) {
      throw new UserScriptValueStateError(
        'readiness',
        'userscript-value-state-unavailable',
        validation.stage,
        validation.code
      );
    }
  }

  private usesIsolatedScriptDocuments(): boolean {
    return this.adapter.persistenceLayout === 'isolated_script_documents';
  }

  private cloneDocument(document: UserScriptValueStateDocument): UserScriptValueStateDocument {
    return {
      schemaVersion: document.schemaVersion,
      revision: document.revision,
      values: document.values.map((record: UserScriptValueRecord): UserScriptValueRecord => {
        return cloneUserScriptValueRecord(record);
      }),
      updatedAt: document.updatedAt
    };
  }

  private createEmptyDocument(revision: number, updatedAt: number): UserScriptValueStateDocument {
    return {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: revision,
      values: [],
      updatedAt: updatedAt
    };
  }

  private createUnchangedResult(): UserScriptValueCommitResult {
    return {
      revision: this.document.revision,
      changed: false,
      transitions: [],
      incidentRecovered: false
    };
  }

  private requireReady(): void {
    if (this.readiness.status !== 'ready') {
      throw this.createReadinessError();
    }
  }

  private requireScriptAvailable(scriptId: string): void {
    if (!this.isScriptStateAvailable(scriptId)) {
      throw new UserScriptValueStateError(
        'readiness',
        'userscript-value-script-unavailable',
        'script-state',
        'unavailable'
      );
    }
  }

  private requireScriptId(scriptId: string): string {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0) {
      throw this.createValidationError('invalid-script');
    }
    return normalizedScriptId;
  }

  private createValidationError(code: string): UserScriptValueStateError {
    return new UserScriptValueStateError('validation', `userscript-value-rejected:${code}`, 'validation', code);
  }

  private createReadinessError(): UserScriptValueStateError {
    return new UserScriptValueStateError(
      'readiness',
      'userscript-value-state-unavailable',
      this.readiness.failureStage,
      this.readiness.failureCode,
      this.incident.id,
      false
    );
  }

  private createCommitError(error: Error): UserScriptValueStateError {
    if (error instanceof UserScriptValueStateError && error.failureKind !== 'commit') {
      return error;
    }
    const failure = this.resolveFailure(error, 'commit');
    const wasActive = this.incident.active;
    const incident = this.openIncident('runtime_commit', failure.stage, failure.code);
    hilog.error(
      USER_SCRIPT_VALUE_LOG_DOMAIN,
      USER_SCRIPT_VALUE_LOG_TAG,
      'commit failed stage=%{public}s code=%{public}s incident=%{public}d',
      failure.stage,
      failure.code,
      incident.id
    );
    return new UserScriptValueStateError(
      'commit',
      'userscript-value-persist-failed',
      failure.stage,
      failure.code,
      incident.id,
      !wasActive
    );
  }

  private resolveFailure(
    error: Object | string | number | boolean | undefined,
    fallbackStage: string
  ): UserScriptValueResolvedFailure {
    if (error instanceof UserScriptValueStateError) {
      return {
        stage: error.stage.length > 0 ? error.stage : fallbackStage,
        code: error.platformCode.length > 0 ? error.platformCode : error.publicCode
      };
    }
    const shape = error as UserScriptValueFailureShape;
    const stage = String(shape?.stage ?? '').trim();
    const platformCode = String(shape?.platformCode ?? '').trim();
    return {
      stage: stage.length > 0 ? stage : fallbackStage,
      code: platformCode.length > 0 ? platformCode : 'unknown'
    };
  }

  private projectAdmissionCommand(
    baseDocument: UserScriptValueStateDocument,
    kind: UserScriptValueCommandKind,
    scriptId: string,
    mutations: UserScriptValueMutation[],
    acceptedAt: number
  ): UserScriptValueStateDocument {
    if (kind === 'barrier') {
      return this.cloneDocument(baseDocument);
    }
    let nextValues = baseDocument.values.map((record: UserScriptValueRecord): UserScriptValueRecord => {
      return cloneUserScriptValueRecord(record);
    });
    if (kind === 'delete-package') {
      nextValues = nextValues.filter((record: UserScriptValueRecord): boolean => record.scriptId !== scriptId);
    } else {
      mutations.forEach((mutation: UserScriptValueMutation): void => {
        this.applyMutation(nextValues, scriptId, mutation, acceptedAt);
      });
    }
    this.restoreMetadataForUnchangedValues(this.document.values, nextValues);
    const changed = this.buildTransitions(baseDocument.values, nextValues).length > 0;
    const projectedDocument: UserScriptValueStateDocument = {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: changed ? baseDocument.revision + 1 : baseDocument.revision,
      values: nextValues,
      updatedAt: acceptedAt
    };
    // Isolated adapters enforce the affected script document's capacity while committing it. Encoding the
    // aggregate in-memory document here would synchronously stringify every script from the ArkWeb proxy call,
    // even though only one script and one physical file can change.
    if (this.adapter.replaceCommittedScript === undefined) {
      this.encodeDocument(projectedDocument);
    }
    return projectedDocument;
  }

  private rebuildAdmissionDocument(): void {
    let nextAdmission = this.cloneDocument(this.document);
    const retainedCommands: UserScriptValueCommandRequest[] = [];
    this.pendingCommands.forEach((request: UserScriptValueCommandRequest): void => {
      try {
        nextAdmission = this.projectAdmissionCommand(
          nextAdmission,
          request.kind,
          request.scriptId,
          request.mutations,
          request.acceptedAt
        );
        retainedCommands.push(request);
      } catch (error) {
        const stateError = error instanceof UserScriptValueStateError ? error : this.createValidationError('state-too-large');
        request.reject(stateError);
      }
    });
    this.pendingCommands = retainedCommands;
    this.admissionDocument = nextAdmission;
  }

  private resolveBatchUpdatedAt(batch: UserScriptValueCommandRequest[], fallback: number): number {
    let updatedAt = fallback;
    batch.forEach((request: UserScriptValueCommandRequest): void => {
      if (request.kind !== 'barrier') {
        updatedAt = request.acceptedAt;
      }
    });
    return updatedAt;
  }

  private openIncident(
    kind: 'startup' | 'runtime_commit',
    stage: string,
    code: string
  ): UserScriptValueIncidentSnapshot {
    if (!this.incident.active) {
      this.incidentSerial += 1;
      this.incident = {
        active: true,
        id: this.incidentSerial,
        kind: kind,
        stage: stage,
        code: code,
        startedAt: this.clock()
      };
      this.recordDiagnostic(
        kind === 'startup' ? 'startup_blocked' : 'runtime_commit_failed',
        stage,
        code
      );
      return cloneUserScriptValueIncidentSnapshot(this.incident);
    }
    this.incident = {
      active: true,
      id: this.incident.id,
      kind: this.incident.kind,
      stage: stage,
      code: code,
      startedAt: this.incident.startedAt
    };
    return cloneUserScriptValueIncidentSnapshot(this.incident);
  }

  private clearIncident(): void {
    if (this.incident.active && this.incident.kind === 'runtime_commit') {
      this.recordDiagnostic('runtime_commit_recovered', this.incident.stage, this.incident.code);
    }
    this.incident = {
      active: false,
      id: 0,
      kind: 'none',
      stage: '',
      code: '',
      startedAt: 0
    };
  }

  private recordDiagnostic(
    kind: UserScriptValueDiagnosticKind,
    stage: string,
    code: string
  ): void {
    if (this.diagnosticSink === undefined) {
      return;
    }
    void this.diagnosticSink.recordValueStateDiagnostic({
      kind: kind,
      stage: stage,
      code: code,
      occurredAt: this.clock()
    }).catch((_error: Error): void => {});
  }

  private clearInitializationPromise(pending: Promise<UserScriptValueReadinessSnapshot>): void {
    if (this.initializationPromise === pending) {
      this.initializationPromise = undefined;
    }
  }

  private buildRecordIdentity(scriptId: string, key: string): string {
    return `${JSON.stringify(scriptId)}:${JSON.stringify(key)}`;
  }
}

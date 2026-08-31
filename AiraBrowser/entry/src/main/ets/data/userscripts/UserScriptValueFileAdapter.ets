import { buffer, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  cloneUserScriptValueRecord,
  USER_SCRIPT_VALUE_MAX_STATE_BYTES,
  USER_SCRIPT_VALUE_MAX_VALUE_BYTES,
  USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
  UserScriptValueMigrationSummary,
  UserScriptValueRecord,
  UserScriptValueStateDocument
} from '../../features/userscripts/UserScriptValueModels';
import { UserScriptValueCommittedBytesAdapter } from './UserScriptValueStateStore';
import {
  UserScriptValueDocumentValidationResult,
  UserScriptValueDocumentValidator
} from './UserScriptValueDocumentValidator';

const USER_SCRIPT_VALUE_ROOT_DIR_NAME: string = 'userscript-values';
const USER_SCRIPT_VALUE_LEGACY_FILE_NAME: string = 'values.json';
const USER_SCRIPT_VALUE_LEGACY_PREVIOUS_FILE_SUFFIX: string = '.previous';
const USER_SCRIPT_VALUE_MANIFEST_FILE_NAME: string = 'manifest.json';
const USER_SCRIPT_VALUE_SCRIPTS_DIR_NAME: string = 'scripts';
const USER_SCRIPT_VALUE_DOCUMENT_FILE_SUFFIX: string = '.json';
const USER_SCRIPT_VALUE_JOURNAL_FILE_SUFFIX: string = '.journal';
const USER_SCRIPT_VALUE_PENDING_FILE_SUFFIX: string = '.pending';
const USER_SCRIPT_VALUE_ROLLBACK_FILE_SUFFIX: string = '.rollback';
const USER_SCRIPT_VALUE_MANIFEST_SCHEMA_VERSION: number = 1;
const USER_SCRIPT_VALUE_ISOLATED_SCHEMA_VERSION: number = 1;
const USER_SCRIPT_VALUE_JOURNAL_SCHEMA_VERSION: number = 1;
const USER_SCRIPT_VALUE_MAX_PHYSICAL_DOCUMENT_BYTES: number = USER_SCRIPT_VALUE_MAX_STATE_BYTES * 2;
const USER_SCRIPT_VALUE_MAX_MANIFEST_BYTES: number = USER_SCRIPT_VALUE_MAX_STATE_BYTES * 2;
const USER_SCRIPT_VALUE_TOKEN_HEX_LENGTH: number = 64;
const USER_SCRIPT_VALUE_LOG_DOMAIN: number = 0x0000;
const USER_SCRIPT_VALUE_LOG_TAG: string = 'AiraUserScriptValue';

type UserScriptValueMigrationState = 'in_progress' | 'complete' | 'incomplete';
type UserScriptValueLegacySource = 'primary' | 'fallback' | 'none' | 'unreadable' | 'isolated_recovered';
type UserScriptValueLegacyReadStatus = 'missing' | 'valid' | 'invalid';

export type UserScriptValueDurableStage =
  'access' |
  'stat' |
  'read' |
  'read-verify' |
  'list' |
  'decode' |
  'mkdir' |
  'write' |
  'write-verify' |
  'atomic-start' |
  'atomic-finish' |
  'atomic-rollback' |
  'delete';

interface UserScriptValuePlatformErrorShape {
  code?: string | number;
  message?: string;
}

interface UserScriptValueManifestEntry {
  token: string;
  scriptId: string;
}

interface UserScriptValueManifestDocument {
  schemaVersion: number;
  migrationState: UserScriptValueMigrationState;
  legacySource: UserScriptValueLegacySource;
  entries: UserScriptValueManifestEntry[];
  stateRevision: number;
  stateUpdatedAt: number;
  skippedScriptCount: number;
  skippedUnattributedRecordCount: number;
  unreadableLegacySnapshot: boolean;
  updatedAt: number;
  completedAt: number;
}

interface UserScriptValueIsolatedDocument {
  schemaVersion: number;
  scriptId: string;
  revision: number;
  values: UserScriptValueRecord[];
  updatedAt: number;
}

interface UserScriptValueJournalMutation {
  operation: 'set' | 'delete';
  key: string;
  valueJson: string;
  updatedAt: number;
}

interface UserScriptValueJournalRecord {
  schemaVersion: number;
  scriptId: string;
  revision: number;
  mutations: UserScriptValueJournalMutation[];
  updatedAt: number;
}

interface UserScriptValueLegacyReadResult {
  status: UserScriptValueLegacyReadStatus;
  document?: UserScriptValueStateDocument;
  migration?: UserScriptValueMigrationSummary;
}

interface UserScriptValueLegacySelection {
  source: UserScriptValueLegacySource;
  document?: UserScriptValueStateDocument;
  migration: UserScriptValueMigrationSummary;
}

interface UserScriptValueLegacyDecodeResult {
  document: UserScriptValueStateDocument;
  migration: UserScriptValueMigrationSummary;
}

interface UserScriptValueManifestLoadResult {
  document: UserScriptValueStateDocument;
  unavailableTokens: string[];
  missingTokens: string[];
}

interface UserScriptValueRecoveredDocuments {
  document: UserScriptValueStateDocument;
  entries: UserScriptValueManifestEntry[];
  unavailableTokens: string[];
}

export class UserScriptValueDurableError extends Error {
  readonly stage: UserScriptValueDurableStage;
  readonly platformCode: string;

  constructor(stage: UserScriptValueDurableStage, platformCode: string) {
    super(`userscript-value-durable-${stage}`);
    this.stage = stage;
    this.platformCode = platformCode;
  }
}

export class UserScriptValueFileAdapter implements UserScriptValueCommittedBytesAdapter {
  readonly persistenceLayout: 'isolated_script_documents' = 'isolated_script_documents';
  private readonly committedStateFilePath: string;
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly documentValidator: UserScriptValueDocumentValidator = new UserScriptValueDocumentValidator();
  private currentManifest?: UserScriptValueManifestDocument;
  private lastDocument: UserScriptValueStateDocument = this.createEmptyStateDocument();
  private unavailableTokens: string[] = [];
  private migrationSummary: UserScriptValueMigrationSummary = this.createEmptyMigrationSummary();

  constructor(committedStateFilePath: string = '') {
    this.committedStateFilePath = committedStateFilePath.trim();
  }

  async readCommitted(): Promise<Uint8Array | undefined> {
    await this.ensureStorageDirs();
    const manifest = await this.readManifestTolerant();
    if (manifest !== undefined) {
      this.migrationSummary = this.readManifestMigrationSummary(manifest);
    }
    if (manifest !== undefined && manifest.migrationState === 'complete') {
      const loaded = await this.loadManifestDocuments(manifest);
      const unavailableTokens = this.mergeTokens(loaded.unavailableTokens, loaded.missingTokens);
      this.applyLoadedState(manifest, loaded.document, unavailableTokens);
      return this.encodeStateDocument(loaded.document);
    }
    if (manifest !== undefined && manifest.migrationState === 'incomplete') {
      return await this.resumeIncompleteMigration(manifest);
    }
    if (manifest !== undefined && manifest.migrationState === 'in_progress') {
      return await this.migrateLegacyState(manifest);
    }
    const recovered = await this.recoverDocumentsWithoutManifest();
    if (recovered.entries.length > 0 || recovered.unavailableTokens.length > 0) {
      const recoveredManifest = this.createManifest(
        'complete',
        'isolated_recovered',
        recovered.entries,
        Date.now(),
        recovered.document.revision,
        recovered.document.updatedAt
      );
      await this.writeManifest(recoveredManifest);
      this.applyLoadedState(recoveredManifest, recovered.document, recovered.unavailableTokens);
      return this.encodeStateDocument(recovered.document);
    }
    return await this.migrateLegacyState(undefined);
  }

  async replaceCommitted(bytes: Uint8Array): Promise<void> {
    const nextDocument = this.decodeStateDocument(bytes);
    const changedScriptIds = this.resolveChangedScriptIds(this.lastDocument, nextDocument);
    if (changedScriptIds.length === 0) {
      this.lastDocument = this.cloneStateDocument(nextDocument);
      return;
    }
    if (changedScriptIds.length !== 1) {
      throw new UserScriptValueDurableError('write-verify', 'multi-script-commit');
    }
    const scriptId = changedScriptIds[0];
    await this.replaceCommittedScript(
      scriptId,
      nextDocument.revision,
      nextDocument.updatedAt,
      nextDocument.values.filter((record: UserScriptValueRecord): boolean => record.scriptId === scriptId)
    );
    this.lastDocument = this.cloneStateDocument(nextDocument);
  }

  async replaceCommittedScript(
    scriptId: string,
    revision: number,
    updatedAt: number,
    values: UserScriptValueRecord[]
  ): Promise<void> {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0 || values.some(
      (record: UserScriptValueRecord): boolean => record.scriptId !== normalizedScriptId
    )) {
      throw new UserScriptValueDurableError('write-verify', 'invalid-script-document');
    }
    const normalizedValues = values.map(
      (record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record)
    );
    const canonicalScriptId = normalizedScriptId;
    const token = this.buildScriptToken(canonicalScriptId);
    const manifest = this.currentManifest;
    if (manifest === undefined || manifest.migrationState === 'in_progress') {
      throw new UserScriptValueDurableError('write-verify', 'manifest-not-ready');
    }
    const entryPublished = manifest.entries.some(
      (entry: UserScriptValueManifestEntry): boolean => entry.token === token
    );
    const nextEntries = entryPublished ?
      manifest.entries : manifest.entries.concat([{ token: token, scriptId: canonicalScriptId }]);
    const journalMutations = this.buildJournalMutations(canonicalScriptId, normalizedValues, updatedAt);
    let journalBytes = 0;
    let isolatedBytes: Uint8Array | undefined;
    let journalPayload = '';
    if (entryPublished) {
      journalPayload = this.encodeJournalRecord({
        schemaVersion: USER_SCRIPT_VALUE_JOURNAL_SCHEMA_VERSION,
        scriptId: canonicalScriptId,
        revision: revision,
        mutations: journalMutations,
        updatedAt: updatedAt
      });
      journalBytes = buffer.from(journalPayload, 'utf8').length;
    } else {
      const validationDocument: UserScriptValueStateDocument = {
        schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
        revision: revision,
        values: normalizedValues,
        updatedAt: updatedAt
      };
      this.requireValidStateDocument(validationDocument, canonicalScriptId);
      isolatedBytes = this.encodeIsolatedDocument({
        schemaVersion: USER_SCRIPT_VALUE_ISOLATED_SCHEMA_VERSION,
        scriptId: canonicalScriptId,
        revision: revision,
        values: normalizedValues,
        updatedAt: updatedAt
      });
    }
    const scriptFilePath = this.resolveScriptFilePath(token);
    if (entryPublished) {
      if (journalMutations.length > 0) {
        await this.appendJournal(this.resolveScriptJournalPath(token), journalPayload, journalBytes);
      }
    } else {
      if (isolatedBytes === undefined) {
        throw new UserScriptValueDurableError('write', 'snapshot-missing');
      }
      await this.writeAtomicVerified(scriptFilePath, isolatedBytes);
    }
    const committedManifest = this.createManifest(
      manifest.migrationState,
      manifest.legacySource,
      nextEntries,
      manifest.completedAt,
      revision,
      updatedAt
    );
    if (!entryPublished) {
      try {
        await this.writeManifest(committedManifest);
      } catch (error) {
        throw this.toDurableError('write', error);
      }
    }
    // The manifest is an index, not a per-mutation journal. Existing script documents carry their own
    // revision and startup merges the maximum document revision, so rewriting and fsyncing the manifest
    // for every GM_setValue only adds a second durability barrier without improving recovery semantics.
    this.currentManifest = this.cloneManifest(committedManifest);
    this.unavailableTokens = this.unavailableTokens.filter((candidate: string): boolean => candidate !== token);
    this.lastDocument = {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: revision,
      values: this.lastDocument.values
        .filter((record: UserScriptValueRecord): boolean => record.scriptId !== canonicalScriptId)
        .concat(normalizedValues.map(
          (record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record)
        )),
      updatedAt: updatedAt
    };
  }

  async replaceCommittedRemovingScript(scriptId: string, bytes: Uint8Array): Promise<void> {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0) {
      return;
    }
    const nextDocument = this.decodeStateDocument(bytes);
    if (nextDocument.values.some(
      (record: UserScriptValueRecord): boolean => record.scriptId === normalizedScriptId
    )) {
      throw new UserScriptValueDurableError('delete', 'script-values-retained');
    }
    const changedScriptIds = this.resolveChangedScriptIds(this.lastDocument, nextDocument);
    if (changedScriptIds.length > 1 ||
      (changedScriptIds.length === 1 && changedScriptIds[0] !== normalizedScriptId)) {
      throw new UserScriptValueDurableError('delete', 'multi-script-commit');
    }
    const token = this.buildScriptToken(normalizedScriptId);
    const manifest = this.currentManifest;
    if (manifest === undefined || manifest.migrationState === 'in_progress') {
      throw new UserScriptValueDurableError('delete', 'manifest-not-ready');
    }
    if (manifest.entries.some((entry: UserScriptValueManifestEntry): boolean => entry.token === token)) {
      const nextManifest = this.createManifest(
        manifest.migrationState,
        manifest.legacySource,
        manifest.entries.filter((entry: UserScriptValueManifestEntry): boolean => entry.token !== token),
        manifest.completedAt,
        nextDocument.revision,
        nextDocument.updatedAt
      );
      await this.writeManifest(nextManifest);
      this.currentManifest = this.cloneManifest(nextManifest);
    }
    this.unavailableTokens = this.unavailableTokens.filter((candidate: string): boolean => candidate !== token);
    this.lastDocument = this.cloneStateDocument(nextDocument);
    try {
      await this.removeScriptDocument(token);
    } catch (error) {
      const failure = this.toDurableError('delete', error);
      hilog.warn(
        USER_SCRIPT_VALUE_LOG_DOMAIN,
        USER_SCRIPT_VALUE_LOG_TAG,
        'retired script document cleanup deferred token=%{public}s stage=%{public}s code=%{public}s',
        token,
        failure.stage,
        failure.platformCode
      );
    }
  }

  isScriptAvailable(scriptId: string): boolean {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0) {
      return false;
    }
    return !this.unavailableTokens.includes(this.buildScriptToken(normalizedScriptId));
  }

  readMigrationSummary(): UserScriptValueMigrationSummary {
    return this.cloneMigrationSummary(this.migrationSummary);
  }

  private async migrateLegacyState(
    existingManifest: UserScriptValueManifestDocument | undefined
  ): Promise<Uint8Array> {
    const legacy = await this.selectLegacySnapshot();
    this.migrationSummary = this.cloneMigrationSummary(legacy.migration);
    const source = legacy.source;
    const legacyDocument = legacy.document;
    if (legacyDocument === undefined) {
      const retainedEntries = existingManifest?.entries ?? [];
      const loadManifest = this.createManifest(
        'in_progress',
        source,
        retainedEntries,
        0,
        existingManifest?.stateRevision ?? 0,
        existingManifest?.stateUpdatedAt ?? 0
      );
      const loaded = await this.loadManifestDocuments(loadManifest);
      const terminalState: UserScriptValueMigrationState =
        loaded.missingTokens.length > 0 || loaded.unavailableTokens.length > 0 ? 'incomplete' : 'complete';
      const completedManifest = this.createManifest(
        terminalState,
        source,
        retainedEntries,
        terminalState === 'complete' ? Date.now() : 0,
        loaded.document.revision,
        loaded.document.updatedAt
      );
      await this.writeManifest(completedManifest);
      const unavailableTokens = terminalState === 'incomplete' ?
        this.mergeTokens(loaded.unavailableTokens, loaded.missingTokens) : loaded.unavailableTokens;
      this.applyLoadedState(completedManifest, loaded.document, unavailableTokens);
      return this.encodeStateDocument(loaded.document);
    }

    const entries = this.buildManifestEntries(legacyDocument.values);
    const inProgressManifest = this.createManifest(
      'in_progress',
      source,
      entries,
      0,
      legacyDocument.revision,
      legacyDocument.updatedAt
    );
    await this.writeManifest(inProgressManifest);
    for (let index = 0; index < entries.length; index += 1) {
      const entry = entries[index];
      const isolatedDocument: UserScriptValueIsolatedDocument = {
        schemaVersion: USER_SCRIPT_VALUE_ISOLATED_SCHEMA_VERSION,
        scriptId: entry.scriptId,
        revision: legacyDocument.revision,
        values: legacyDocument.values
          .filter((record: UserScriptValueRecord): boolean => record.scriptId === entry.scriptId)
          .map((record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record)),
        updatedAt: legacyDocument.updatedAt
      };
      await this.writeAndVerifyIsolatedDocument(entry, isolatedDocument);
    }
    const completedAt = Date.now();
    const completedManifest = this.createManifest(
      'complete',
      source,
      entries,
      completedAt,
      legacyDocument.revision,
      legacyDocument.updatedAt
    );
    await this.writeManifest(completedManifest);
    this.applyLoadedState(completedManifest, legacyDocument, []);
    hilog.info(
      USER_SCRIPT_VALUE_LOG_DOMAIN,
      USER_SCRIPT_VALUE_LOG_TAG,
      'isolated migration completed source=%{public}s scripts=%{public}d values=%{public}d',
      source,
      entries.length,
      legacyDocument.values.length
    );
    return this.encodeStateDocument(legacyDocument);
  }

  private async resumeIncompleteMigration(manifest: UserScriptValueManifestDocument): Promise<Uint8Array> {
    const loaded = await this.loadManifestDocuments(manifest);
    const unavailableTokens = this.mergeTokens(loaded.unavailableTokens, loaded.missingTokens);
    if (unavailableTokens.length === 0) {
      const completedManifest = this.createManifest(
        'complete',
        manifest.legacySource,
        manifest.entries,
        Date.now(),
        loaded.document.revision,
        loaded.document.updatedAt
      );
      await this.writeManifest(completedManifest);
      this.applyLoadedState(completedManifest, loaded.document, []);
      return this.encodeStateDocument(loaded.document);
    }
    const legacy = await this.selectLegacySnapshot();
    if (legacy.document === undefined) {
      this.applyLoadedState(manifest, loaded.document, unavailableTokens);
      return this.encodeStateDocument(loaded.document);
    }
    const repairRevision = Math.max(loaded.document.revision, legacy.document.revision);
    const repairUpdatedAt = Math.max(loaded.document.updatedAt, legacy.document.updatedAt);
    let repairedAny = false;
    for (let index = 0; index < manifest.entries.length; index += 1) {
      const entry = manifest.entries[index];
      if (!unavailableTokens.includes(entry.token)) {
        continue;
      }
      const legacyValues = legacy.document.values
        .filter((record: UserScriptValueRecord): boolean => record.scriptId === entry.scriptId)
        .map((record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record));
      if (legacyValues.length === 0) {
        continue;
      }
      const isolatedDocument: UserScriptValueIsolatedDocument = {
        schemaVersion: USER_SCRIPT_VALUE_ISOLATED_SCHEMA_VERSION,
        scriptId: entry.scriptId,
        revision: repairRevision,
        values: legacyValues,
        updatedAt: repairUpdatedAt
      };
      try {
        await this.writeAndVerifyIsolatedDocument(entry, isolatedDocument);
        repairedAny = true;
      } catch (error) {
        this.logIsolatedDocumentFailure(entry.token, error);
      }
    }
    if (!repairedAny) {
      this.applyLoadedState(manifest, loaded.document, unavailableTokens);
      return this.encodeStateDocument(loaded.document);
    }
    const reloaded = await this.loadManifestDocuments(manifest);
    const remainingUnavailable = this.mergeTokens(reloaded.unavailableTokens, reloaded.missingTokens);
    const nextState: UserScriptValueMigrationState =
      remainingUnavailable.length === 0 ? 'complete' : 'incomplete';
    const nextManifest = this.createManifest(
      nextState,
      legacy.source,
      manifest.entries,
      nextState === 'complete' ? Date.now() : 0,
      reloaded.document.revision,
      reloaded.document.updatedAt
    );
    await this.writeManifest(nextManifest);
    this.applyLoadedState(nextManifest, reloaded.document, remainingUnavailable);
    return this.encodeStateDocument(reloaded.document);
  }

  private async selectLegacySnapshot(): Promise<UserScriptValueLegacySelection> {
    const primary = await this.readLegacySnapshot(this.resolveLegacyPrimaryFilePath());
    const fallback = primary.status === 'valid' ? undefined :
      await this.readLegacySnapshot(this.resolveLegacyFallbackFilePath());
    if (primary.status === 'valid') {
      return {
        source: 'primary',
        document: primary.document,
        migration: primary.migration ?? this.createEmptyMigrationSummary()
      };
    }
    if (fallback?.status === 'valid') {
      return {
        source: 'fallback',
        document: fallback.document,
        migration: fallback.migration ?? this.createEmptyMigrationSummary()
      };
    }
    const source: UserScriptValueLegacySource =
      primary.status === 'invalid' || fallback?.status === 'invalid' ? 'unreadable' : 'none';
    const migration = this.createEmptyMigrationSummary();
    migration.unreadableLegacySnapshot = source === 'unreadable';
    return { source: source, migration: migration };
  }

  private async writeAndVerifyIsolatedDocument(
    entry: UserScriptValueManifestEntry,
    document: UserScriptValueIsolatedDocument
  ): Promise<void> {
    const encoded = this.encodeIsolatedDocument(document);
    await this.writeAtomicVerified(this.resolveScriptFilePath(entry.token), encoded);
    const readBack = await this.readStateFile(
      this.resolveScriptFilePath(entry.token),
      USER_SCRIPT_VALUE_MAX_PHYSICAL_DOCUMENT_BYTES
    );
    if (readBack === undefined) {
      throw new UserScriptValueDurableError('read-verify', 'migration-readback-missing');
    }
    const verified = this.decodeIsolatedDocument(readBack);
    if (verified.scriptId !== entry.scriptId || !this.recordsEqual(verified.values, document.values)) {
      throw new UserScriptValueDurableError('read-verify', 'migration-readback-mismatch');
    }
  }

  private buildJournalMutations(
    scriptId: string,
    nextValues: UserScriptValueRecord[],
    updatedAt: number
  ): UserScriptValueJournalMutation[] {
    const previousValues = this.lastDocument.values.filter(
      (record: UserScriptValueRecord): boolean => record.scriptId === scriptId
    );
    const mutations: UserScriptValueJournalMutation[] = [];
    nextValues.forEach((record: UserScriptValueRecord): void => {
      const previous = previousValues.find(
        (candidate: UserScriptValueRecord): boolean => candidate.key === record.key
      );
      if (previous?.valueJson === record.valueJson) {
        return;
      }
      try {
        JSON.parse(record.valueJson);
      } catch (_error) {
        throw new UserScriptValueDurableError('write-verify', 'journal-value-json');
      }
      if (buffer.from(record.valueJson, 'utf8').length > USER_SCRIPT_VALUE_MAX_VALUE_BYTES) {
        throw new UserScriptValueDurableError('write-verify', 'journal-value-too-large');
      }
      mutations.push({
        operation: 'set',
        key: record.key,
        valueJson: record.valueJson,
        updatedAt: record.updatedAt
      });
    });
    previousValues.forEach((record: UserScriptValueRecord): void => {
      if (nextValues.some((candidate: UserScriptValueRecord): boolean => candidate.key === record.key)) {
        return;
      }
      mutations.push({
        operation: 'delete',
        key: record.key,
        valueJson: '',
        updatedAt: updatedAt
      });
    });
    return mutations;
  }

  private encodeJournalRecord(record: UserScriptValueJournalRecord): string {
    if (record.mutations.length === 0) {
      return '';
    }
    let serialized = '';
    try {
      serialized = JSON.stringify(record);
    } catch (_error) {
      throw new UserScriptValueDurableError('write', 'journal-json');
    }
    return `\n${serialized}\n`;
  }

  private async appendJournal(path: string, payload: string, expectedBytes: number): Promise<void> {
    if (payload.length === 0 || expectedBytes <= 0) {
      return;
    }
    let journalFile: fileIo.File | undefined;
    let failure: UserScriptValueDurableError | undefined;
    try {
      journalFile = await fileIo.open(
        path,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND | fileIo.OpenMode.SYNC
      );
      const written = await fileIo.write(journalFile.fd, payload, { encoding: 'utf-8' });
      if (written !== expectedBytes) {
        throw new UserScriptValueDurableError('write-verify', 'journal-short-write');
      }
      await fileIo.fsync(journalFile.fd);
    } catch (error) {
      failure = this.toDurableError(journalFile === undefined ? 'atomic-start' : 'write', error);
    }
    if (journalFile !== undefined) {
      try {
        await fileIo.close(journalFile);
      } catch (error) {
        if (failure === undefined) {
          failure = this.toDurableError('write', error);
        }
      }
    }
    if (failure !== undefined) {
      throw failure;
    }
  }

  private async replayJournal(
    entry: UserScriptValueManifestEntry,
    base: UserScriptValueIsolatedDocument
  ): Promise<UserScriptValueIsolatedDocument> {
    const bytes = await this.readStateFile(
      this.resolveScriptJournalPath(entry.token),
      USER_SCRIPT_VALUE_MAX_STATE_BYTES
    );
    if (bytes === undefined) {
      return base;
    }
    const lines = this.decodeText(bytes).split('\n');
    let values = base.values.map(
      (record: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(record)
    );
    let revision = base.revision;
    let updatedAt = base.updatedAt;
    let ignoredLines = 0;
    lines.forEach((line: string): void => {
      const trimmed = line.trim();
      if (trimmed.length === 0) {
        return;
      }
      let record: UserScriptValueJournalRecord;
      try {
        record = JSON.parse(trimmed) as UserScriptValueJournalRecord;
        if (record.schemaVersion !== USER_SCRIPT_VALUE_JOURNAL_SCHEMA_VERSION ||
          record.scriptId !== entry.scriptId || !Number.isInteger(record.revision) || record.revision < 0 ||
          !this.isNonNegativeFinite(record.updatedAt) || !Array.isArray(record.mutations) ||
          record.revision < revision) {
          throw new Error('journal-schema');
        }
        const nextValues = values.map(
          (value: UserScriptValueRecord): UserScriptValueRecord => cloneUserScriptValueRecord(value)
        );
        record.mutations.forEach((mutation: UserScriptValueJournalMutation): void => {
          const key = String(mutation.key ?? '').trim();
          if (key.length === 0 || (mutation.operation !== 'set' && mutation.operation !== 'delete') ||
            !this.isNonNegativeFinite(mutation.updatedAt)) {
            throw new Error('journal-mutation');
          }
          const existingIndex = nextValues.findIndex(
            (value: UserScriptValueRecord): boolean => value.key === key
          );
          if (mutation.operation === 'delete') {
            if (existingIndex >= 0) {
              nextValues.splice(existingIndex, 1);
            }
            return;
          }
          const valueJson = String(mutation.valueJson ?? '');
          JSON.parse(valueJson);
          if (buffer.from(valueJson, 'utf8').length > USER_SCRIPT_VALUE_MAX_VALUE_BYTES) {
            throw new Error('journal-value-too-large');
          }
          const nextRecord: UserScriptValueRecord = {
            scriptId: entry.scriptId,
            key: key,
            valueJson: valueJson,
            updatedAt: mutation.updatedAt
          };
          if (existingIndex >= 0) {
            nextValues.splice(existingIndex, 1, nextRecord);
          } else {
            nextValues.push(nextRecord);
          }
        });
        values = nextValues;
        revision = Math.max(revision, record.revision);
        updatedAt = Math.max(updatedAt, record.updatedAt);
      } catch (_error) {
        ignoredLines += 1;
      }
    });
    if (ignoredLines > 0) {
      hilog.warn(
        USER_SCRIPT_VALUE_LOG_DOMAIN,
        USER_SCRIPT_VALUE_LOG_TAG,
        'script journal ignored invalid records token=%{public}s count=%{public}d',
        entry.token,
        ignoredLines
      );
    }
    return {
      schemaVersion: USER_SCRIPT_VALUE_ISOLATED_SCHEMA_VERSION,
      scriptId: entry.scriptId,
      revision: revision,
      values: values,
      updatedAt: updatedAt
    };
  }

  private async readLegacySnapshot(path: string): Promise<UserScriptValueLegacyReadResult> {
    let bytes: Uint8Array | undefined;
    try {
      bytes = await this.readStateFile(path, USER_SCRIPT_VALUE_MAX_STATE_BYTES);
    } catch (error) {
      const failure = this.toDurableError('read', error);
      hilog.warn(
        USER_SCRIPT_VALUE_LOG_DOMAIN,
        USER_SCRIPT_VALUE_LOG_TAG,
        'legacy snapshot unreadable stage=%{public}s code=%{public}s',
        failure.stage,
        failure.platformCode
      );
      return { status: 'invalid' };
    }
    if (bytes === undefined) {
      return { status: 'missing' };
    }
    try {
      const decoded = this.decodeLegacyStateDocument(bytes);
      return {
        status: 'valid',
        document: decoded.document,
        migration: decoded.migration
      };
    } catch (_error) {
      return { status: 'invalid' };
    }
  }

  private async readManifestTolerant(): Promise<UserScriptValueManifestDocument | undefined> {
    let bytes: Uint8Array | undefined;
    try {
      bytes = await this.readStateFile(this.resolveManifestFilePath(), USER_SCRIPT_VALUE_MAX_MANIFEST_BYTES);
    } catch (error) {
      hilog.warn(
        USER_SCRIPT_VALUE_LOG_DOMAIN,
        USER_SCRIPT_VALUE_LOG_TAG,
        'manifest read ignored stage=%{public}s code=%{public}s',
        String((error as UserScriptValueDurableError)?.stage ?? 'read'),
        String((error as UserScriptValueDurableError)?.platformCode ?? 'invalid')
      );
      return undefined;
    }
    if (bytes === undefined) {
      return undefined;
    }
    try {
      return this.decodeManifest(bytes);
    } catch (_error) {
      hilog.warn(
        USER_SCRIPT_VALUE_LOG_DOMAIN,
        USER_SCRIPT_VALUE_LOG_TAG,
        'manifest decode ignored code=%{public}s',
        'invalid'
      );
      return undefined;
    }
  }

  private async loadManifestDocuments(
    manifest: UserScriptValueManifestDocument
  ): Promise<UserScriptValueManifestLoadResult> {
    const values: UserScriptValueRecord[] = [];
    const unavailableTokens: string[] = [];
    const missingTokens: string[] = [];
    let revision = manifest.stateRevision;
    let updatedAt = manifest.stateUpdatedAt;
    for (let index = 0; index < manifest.entries.length; index += 1) {
      const entry = manifest.entries[index];
      try {
        const bytes = await this.readStateFile(
          this.resolveScriptFilePath(entry.token),
          USER_SCRIPT_VALUE_MAX_PHYSICAL_DOCUMENT_BYTES
        );
        if (bytes === undefined) {
          missingTokens.push(entry.token);
          continue;
        }
        const isolatedBase = this.decodeIsolatedDocument(bytes);
        const isolated = await this.replayJournal(entry, isolatedBase);
        if (isolated.scriptId !== entry.scriptId || this.buildScriptToken(isolated.scriptId) !== entry.token) {
          throw new UserScriptValueDurableError('decode', 'identity-mismatch');
        }
        isolated.values.forEach((record: UserScriptValueRecord): void => {
          values.push(cloneUserScriptValueRecord(record));
        });
        revision = Math.max(revision, isolated.revision);
        updatedAt = Math.max(updatedAt, isolated.updatedAt);
      } catch (error) {
        unavailableTokens.push(entry.token);
        this.logIsolatedDocumentFailure(entry.token, error);
      }
    }
    return {
      document: {
        schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
        revision: revision,
        values: values,
        updatedAt: updatedAt
      },
      unavailableTokens: unavailableTokens,
      missingTokens: missingTokens
    };
  }

  private async recoverDocumentsWithoutManifest(): Promise<UserScriptValueRecoveredDocuments> {
    let fileNames: string[];
    try {
      fileNames = await fileIo.listFile(this.resolveScriptsDir());
    } catch (error) {
      throw this.toDurableError('list', error);
    }
    const entries: UserScriptValueManifestEntry[] = [];
    const unavailableTokens: string[] = [];
    const values: UserScriptValueRecord[] = [];
    let revision = 0;
    let updatedAt = 0;
    for (let index = 0; index < fileNames.length; index += 1) {
      const token = this.parseScriptTokenFileName(fileNames[index]);
      if (token.length === 0) {
        continue;
      }
      try {
        const bytes = await this.readStateFile(
          this.resolveScriptFilePath(token),
          USER_SCRIPT_VALUE_MAX_PHYSICAL_DOCUMENT_BYTES
        );
        if (bytes === undefined) {
          continue;
        }
        const isolatedBase = this.decodeIsolatedDocument(bytes);
        if (this.buildScriptToken(isolatedBase.scriptId) !== token) {
          throw new UserScriptValueDurableError('decode', 'identity-mismatch');
        }
        const isolated = await this.replayJournal({ token: token, scriptId: isolatedBase.scriptId }, isolatedBase);
        entries.push({ token: token, scriptId: isolated.scriptId });
        isolated.values.forEach((record: UserScriptValueRecord): void => {
          values.push(cloneUserScriptValueRecord(record));
        });
        revision = Math.max(revision, isolated.revision);
        updatedAt = Math.max(updatedAt, isolated.updatedAt);
      } catch (error) {
        unavailableTokens.push(token);
        this.logIsolatedDocumentFailure(token, error);
      }
    }
    return {
      document: {
        schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
        revision: revision,
        values: values,
        updatedAt: updatedAt
      },
      entries: this.sortManifestEntries(entries),
      unavailableTokens: unavailableTokens
    };
  }

  private async writeManifest(manifest: UserScriptValueManifestDocument): Promise<void> {
    const encoded = this.encodeManifest(manifest);
    await this.writeAtomicVerified(this.resolveManifestFilePath(), encoded);
  }

  private async writeAtomicVerified(path: string, bytes: Uint8Array): Promise<void> {
    await this.writeAtomicFile(path, bytes);
    await this.verifyCommittedFile(path, bytes);
  }

  private async verifyCommittedFile(path: string, bytes: Uint8Array): Promise<void> {
    const verified = await this.readStateFile(
      path,
      Math.max(USER_SCRIPT_VALUE_MAX_PHYSICAL_DOCUMENT_BYTES, USER_SCRIPT_VALUE_MAX_MANIFEST_BYTES)
    );
    if (verified === undefined || !this.bytesEqual(verified, bytes)) {
      throw new UserScriptValueDurableError('write-verify', 'readback-mismatch');
    }
  }

  private async writeAtomicFile(path: string, bytes: Uint8Array): Promise<void> {
    if (bytes.byteLength <= 0) {
      throw new UserScriptValueDurableError('write-verify', 'empty-payload');
    }
    await this.recoverInterruptedAtomicReplacement(path);
    const pendingPath = `${path}${USER_SCRIPT_VALUE_PENDING_FILE_SUFFIX}`;
    const rollbackPath = `${path}${USER_SCRIPT_VALUE_ROLLBACK_FILE_SUFFIX}`;
    const text = this.decodeText(bytes);
    let pendingFile: fileIo.File | undefined;
    let failure: UserScriptValueDurableError | undefined;
    let rollbackPublished = false;
    try {
      pendingFile = await fileIo.open(
        pendingPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.SYNC
      );
      const written: number = await fileIo.write(pendingFile.fd, text, { offset: 0, encoding: 'utf-8' });
      if (written !== bytes.byteLength) {
        throw new UserScriptValueDurableError('write-verify', 'short-write');
      }
      await fileIo.fsync(pendingFile.fd);
    } catch (error) {
      failure = this.toDurableError(pendingFile === undefined ? 'atomic-start' : 'write', error);
    }
    if (pendingFile !== undefined) {
      try {
        await fileIo.close(pendingFile);
      } catch (error) {
        if (failure === undefined) {
          failure = this.toDurableError('write', error);
        }
      }
    }
    if (failure === undefined) {
      try {
        const pendingSize: number = (await fileIo.stat(pendingPath)).size;
        if (pendingSize !== bytes.byteLength) {
          throw new UserScriptValueDurableError('write-verify', 'pending-size-mismatch');
        }
        if (await fileIo.access(path)) {
          await fileIo.rename(path, rollbackPath);
          rollbackPublished = true;
        }
        await fileIo.rename(pendingPath, path);
        const committedSize: number = (await fileIo.stat(path)).size;
        if (committedSize !== bytes.byteLength) {
          throw new UserScriptValueDurableError('write-verify', 'committed-size-mismatch');
        }
        if (rollbackPublished && await fileIo.access(rollbackPath)) {
          try {
            await fileIo.unlink(rollbackPath);
          } catch (_error) {
          }
        }
        return;
      } catch (error) {
        failure = this.toDurableError('atomic-finish', error);
      }
    }
    try {
      if (rollbackPublished && await fileIo.access(rollbackPath)) {
        if (await fileIo.access(path)) {
          await fileIo.unlink(path);
        }
        await fileIo.rename(rollbackPath, path);
      }
      if (await fileIo.access(pendingPath)) {
        await fileIo.unlink(pendingPath);
      }
    } catch (rollbackError) {
      if (failure === undefined) {
        failure = this.toDurableError('atomic-rollback', rollbackError);
      }
    }
    throw failure ?? new UserScriptValueDurableError('write', 'unknown');
  }

  private async readStateFile(path: string, maximumBytes: number): Promise<Uint8Array | undefined> {
    await this.recoverInterruptedAtomicReplacement(path);
    let exists = false;
    try {
      exists = await fileIo.access(path);
    } catch (error) {
      throw this.toDurableError('access', error);
    }
    if (!exists) {
      return undefined;
    }
    let expectedSize = 0;
    try {
      const stat = await fileIo.stat(path);
      expectedSize = stat.size;
    } catch (error) {
      throw this.toDurableError('stat', error);
    }
    if (expectedSize <= 0 || expectedSize > maximumBytes) {
      throw new UserScriptValueDurableError('read-verify', 'invalid-size');
    }
    let sourceFile: fileIo.File | undefined;
    let content: ArrayBuffer = new ArrayBuffer(expectedSize);
    let readFailure: UserScriptValueDurableError | undefined;
    let readBytes = 0;
    try {
      sourceFile = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      readBytes = await fileIo.read(sourceFile.fd, content, { offset: 0, length: expectedSize });
    } catch (error) {
      readFailure = this.toDurableError('read', error);
    }
    if (sourceFile !== undefined) {
      try {
        await fileIo.close(sourceFile);
      } catch (error) {
        if (readFailure === undefined) {
          readFailure = this.toDurableError('read', error);
        }
      }
    }
    if (readFailure !== undefined) {
      throw readFailure;
    }
    if (readBytes !== expectedSize || content.byteLength !== expectedSize) {
      throw new UserScriptValueDurableError('read-verify', 'size-changed');
    }
    return new Uint8Array(content);
  }

  private async recoverInterruptedAtomicReplacement(path: string): Promise<void> {
    const rollbackPath = `${path}${USER_SCRIPT_VALUE_ROLLBACK_FILE_SUFFIX}`;
    let rollbackExists = false;
    let targetExists = false;
    try {
      rollbackExists = await fileIo.access(rollbackPath);
      targetExists = await fileIo.access(path);
      if (!rollbackExists) {
        return;
      }
      if (!targetExists) {
        await fileIo.rename(rollbackPath, path);
        return;
      }
      const targetSize: number = (await fileIo.stat(path)).size;
      if (targetSize <= 0) {
        await fileIo.unlink(path);
        await fileIo.rename(rollbackPath, path);
        return;
      }
      await fileIo.unlink(rollbackPath);
    } catch (error) {
      throw this.toDurableError('atomic-rollback', error);
    }
  }

  private async removeScriptDocument(token: string): Promise<void> {
    const paths = [this.resolveScriptFilePath(token), this.resolveScriptJournalPath(token)];
    for (let index = 0; index < paths.length; index += 1) {
      try {
        if (await fileIo.access(paths[index])) {
          await fileIo.unlink(paths[index]);
        }
      } catch (error) {
        throw this.toDurableError('delete', error);
      }
    }
  }

  private decodeManifest(bytes: Uint8Array): UserScriptValueManifestDocument {
    let manifest: UserScriptValueManifestDocument;
    try {
      manifest = JSON.parse(this.decodeText(bytes)) as UserScriptValueManifestDocument;
    } catch (_error) {
      throw new UserScriptValueDurableError('decode', 'manifest-json');
    }
    if (manifest === undefined || manifest === null ||
      manifest.schemaVersion !== USER_SCRIPT_VALUE_MANIFEST_SCHEMA_VERSION ||
      (manifest.migrationState !== 'in_progress' && manifest.migrationState !== 'complete' &&
        manifest.migrationState !== 'incomplete') ||
      !this.isLegacySource(manifest.legacySource) ||
      !Array.isArray(manifest.entries) ||
      !Number.isInteger(manifest.stateRevision) || manifest.stateRevision < 0 ||
      !this.isNonNegativeFinite(manifest.stateUpdatedAt) ||
      !Number.isInteger(manifest.skippedScriptCount) || manifest.skippedScriptCount < 0 ||
      !Number.isInteger(manifest.skippedUnattributedRecordCount) ||
      manifest.skippedUnattributedRecordCount < 0 ||
      typeof manifest.unreadableLegacySnapshot !== 'boolean' ||
      !this.isNonNegativeFinite(manifest.updatedAt) ||
      !this.isNonNegativeFinite(manifest.completedAt)) {
      throw new UserScriptValueDurableError('decode', 'manifest-schema');
    }
    const seenTokens: string[] = [];
    const seenScriptIds: string[] = [];
    manifest.entries.forEach((entry: UserScriptValueManifestEntry): void => {
      if (entry === undefined || entry === null ||
        typeof entry.token !== 'string' || !this.isValidToken(entry.token) ||
        typeof entry.scriptId !== 'string' || entry.scriptId.trim().length === 0 ||
        entry.scriptId !== entry.scriptId.trim() ||
        entry.token !== this.buildScriptToken(entry.scriptId) ||
        seenTokens.includes(entry.token) || seenScriptIds.includes(entry.scriptId)) {
        throw new UserScriptValueDurableError('decode', 'manifest-entry');
      }
      seenTokens.push(entry.token);
      seenScriptIds.push(entry.scriptId);
    });
    return this.cloneManifest(manifest);
  }

  private decodeIsolatedDocument(bytes: Uint8Array): UserScriptValueIsolatedDocument {
    let document: UserScriptValueIsolatedDocument;
    try {
      document = JSON.parse(this.decodeText(bytes)) as UserScriptValueIsolatedDocument;
    } catch (_error) {
      throw new UserScriptValueDurableError('decode', 'isolated-json');
    }
    if (document === undefined || document === null ||
      document.schemaVersion !== USER_SCRIPT_VALUE_ISOLATED_SCHEMA_VERSION ||
      typeof document.scriptId !== 'string' || document.scriptId.trim().length === 0 ||
      document.scriptId !== document.scriptId.trim() ||
      !Number.isInteger(document.revision) || document.revision < 0 ||
      !this.isNonNegativeFinite(document.updatedAt) ||
      !Array.isArray(document.values)) {
      throw new UserScriptValueDurableError('decode', 'isolated-schema');
    }
    const validationShape: UserScriptValueStateDocument = {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: document.revision,
      values: document.values,
      updatedAt: document.updatedAt
    };
    this.requireValidStateDocument(validationShape, document.scriptId);
    return {
      schemaVersion: document.schemaVersion,
      scriptId: document.scriptId,
      revision: document.revision,
      values: document.values.map((record: UserScriptValueRecord): UserScriptValueRecord => {
        return cloneUserScriptValueRecord(record);
      }),
      updatedAt: document.updatedAt
    };
  }

  private decodeStateDocument(bytes: Uint8Array): UserScriptValueStateDocument {
    let document: UserScriptValueStateDocument;
    try {
      document = JSON.parse(this.decodeText(bytes)) as UserScriptValueStateDocument;
    } catch (_error) {
      throw new UserScriptValueDurableError('decode', 'state-json');
    }
    if (document === undefined || document === null ||
      document.schemaVersion !== USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION ||
      !Number.isInteger(document.revision) || document.revision < 0 ||
      !this.isNonNegativeFinite(document.updatedAt) ||
      !Array.isArray(document.values)) {
      throw new UserScriptValueDurableError('decode', 'state-schema');
    }
    this.requireValidStateDocument(document);
    return this.cloneStateDocument(document);
  }

  private decodeLegacyStateDocument(bytes: Uint8Array): UserScriptValueLegacyDecodeResult {
    let document: UserScriptValueStateDocument;
    try {
      document = JSON.parse(this.decodeText(bytes)) as UserScriptValueStateDocument;
    } catch (_error) {
      throw new UserScriptValueDurableError('decode', 'legacy-json');
    }
    if (document === undefined || document === null || !Array.isArray(document.values)) {
      throw new UserScriptValueDurableError('decode', 'legacy-schema');
    }
    const legacyRevision = Number.isInteger(document.revision) && document.revision >= 0 ? document.revision : 0;
    const legacyUpdatedAt = this.isNonNegativeFinite(document.updatedAt) ? document.updatedAt : 0;
    const migratedValues: UserScriptValueRecord[] = [];
    const migratedIdentities: string[] = [];
    const skippedScriptIds: string[] = [];
    let skippedUnattributedRecordCount = 0;
    for (let index = 0; index < document.values.length; index += 1) {
      const record = document.values[index];
      const attributableScriptId = record !== undefined && record !== null &&
        typeof record.scriptId === 'string' && record.scriptId.trim().length > 0 &&
        record.scriptId === record.scriptId.trim() ? record.scriptId : '';
      const candidateDocument: UserScriptValueStateDocument = {
        schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
        revision: legacyRevision,
        values: [record],
        updatedAt: legacyUpdatedAt
      };
      const validation = this.documentValidator.validate(candidateDocument, USER_SCRIPT_VALUE_MAX_VALUE_BYTES);
      const identity = validation.valid ? `${JSON.stringify(record.scriptId)}:${JSON.stringify(record.key)}` : '';
      if (!validation.valid || migratedIdentities.includes(identity)) {
        if (attributableScriptId.length === 0) {
          skippedUnattributedRecordCount += 1;
          continue;
        }
        if (!skippedScriptIds.includes(attributableScriptId)) {
          skippedScriptIds.push(attributableScriptId);
        }
        for (let valueIndex = migratedValues.length - 1; valueIndex >= 0; valueIndex -= 1) {
          if (migratedValues[valueIndex].scriptId === attributableScriptId) {
            migratedValues.splice(valueIndex, 1);
          }
        }
        continue;
      }
      if (skippedScriptIds.includes(record.scriptId)) {
        continue;
      }
      migratedIdentities.push(identity);
      migratedValues.push(cloneUserScriptValueRecord(record));
    }
    return {
      document: {
        schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
        revision: legacyRevision,
        values: migratedValues,
        updatedAt: legacyUpdatedAt
      },
      migration: {
        skippedScriptCount: skippedScriptIds.length,
        skippedUnattributedRecordCount: skippedUnattributedRecordCount,
        unreadableLegacySnapshot: false
      }
    };
  }

  private requireValidStateDocument(document: UserScriptValueStateDocument, scriptId: string = ''): void {
    const validation: UserScriptValueDocumentValidationResult = this.documentValidator.validate(
      document,
      USER_SCRIPT_VALUE_MAX_VALUE_BYTES,
      scriptId
    );
    if (!validation.valid) {
      throw new UserScriptValueDurableError('decode', `${validation.stage}:${validation.code}`);
    }
  }

  private encodeManifest(manifest: UserScriptValueManifestDocument): Uint8Array {
    const encoded = this.encodeJson(manifest);
    if (encoded.byteLength > USER_SCRIPT_VALUE_MAX_MANIFEST_BYTES) {
      throw new UserScriptValueDurableError('write-verify', 'manifest-too-large');
    }
    return encoded;
  }

  private encodeIsolatedDocument(document: UserScriptValueIsolatedDocument): Uint8Array {
    const encoded = this.encodeJson(document);
    if (encoded.byteLength > USER_SCRIPT_VALUE_MAX_PHYSICAL_DOCUMENT_BYTES) {
      throw new UserScriptValueDurableError('write-verify', 'script-state-too-large');
    }
    return encoded;
  }

  private encodeStateDocument(document: UserScriptValueStateDocument): Uint8Array {
    return this.encodeJson(document);
  }

  private encodeJson(value: Object): Uint8Array {
    let serialized: string;
    try {
      serialized = JSON.stringify(value);
    } catch (_error) {
      throw new UserScriptValueDurableError('write', 'json');
    }
    const encoded = buffer.from(serialized, 'utf8');
    const bytes = new Uint8Array(encoded.length);
    for (let index = 0; index < encoded.length; index += 1) {
      bytes[index] = encoded[index];
    }
    return bytes;
  }

  private decodeText(bytes: Uint8Array): string {
    try {
      return buffer.from(bytes).toString('utf8');
    } catch (_error) {
      throw new UserScriptValueDurableError('decode', 'utf-8');
    }
  }

  private buildManifestEntries(values: UserScriptValueRecord[]): UserScriptValueManifestEntry[] {
    const entries: UserScriptValueManifestEntry[] = [];
    values.forEach((record: UserScriptValueRecord): void => {
      if (!entries.some((entry: UserScriptValueManifestEntry): boolean => entry.scriptId === record.scriptId)) {
        entries.push({
          token: this.buildScriptToken(record.scriptId),
          scriptId: record.scriptId
        });
      }
    });
    return this.sortManifestEntries(entries);
  }

  private createManifest(
    migrationState: UserScriptValueMigrationState,
    legacySource: UserScriptValueLegacySource,
    entries: UserScriptValueManifestEntry[],
    completedAt: number,
    stateRevision: number = 0,
    stateUpdatedAt: number = 0
  ): UserScriptValueManifestDocument {
    return {
      schemaVersion: USER_SCRIPT_VALUE_MANIFEST_SCHEMA_VERSION,
      migrationState: migrationState,
      legacySource: legacySource,
      entries: this.sortManifestEntries(entries),
      stateRevision: stateRevision,
      stateUpdatedAt: stateUpdatedAt,
      skippedScriptCount: this.migrationSummary.skippedScriptCount,
      skippedUnattributedRecordCount: this.migrationSummary.skippedUnattributedRecordCount,
      unreadableLegacySnapshot: this.migrationSummary.unreadableLegacySnapshot,
      updatedAt: Date.now(),
      completedAt: migrationState === 'complete' ? completedAt : 0
    };
  }

  private sortManifestEntries(entries: UserScriptValueManifestEntry[]): UserScriptValueManifestEntry[] {
    return entries
      .map((entry: UserScriptValueManifestEntry): UserScriptValueManifestEntry => {
        return { token: entry.token, scriptId: entry.scriptId };
      })
      .sort((left: UserScriptValueManifestEntry, right: UserScriptValueManifestEntry): number => {
        return left.token.localeCompare(right.token);
      });
  }

  private resolveChangedScriptIds(
    previous: UserScriptValueStateDocument,
    next: UserScriptValueStateDocument
  ): string[] {
    const scriptIds: string[] = [];
    previous.values.concat(next.values).forEach((record: UserScriptValueRecord): void => {
      if (!scriptIds.includes(record.scriptId)) {
        scriptIds.push(record.scriptId);
      }
    });
    return scriptIds.filter((scriptId: string): boolean => {
      const previousValues = previous.values.filter((record: UserScriptValueRecord): boolean => {
        return record.scriptId === scriptId;
      });
      const nextValues = next.values.filter((record: UserScriptValueRecord): boolean => {
        return record.scriptId === scriptId;
      });
      return !this.recordsEqual(previousValues, nextValues);
    });
  }

  private recordsEqual(left: UserScriptValueRecord[], right: UserScriptValueRecord[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      const leftRecord = left[index];
      const rightRecord = right[index];
      if (leftRecord.scriptId !== rightRecord.scriptId ||
        leftRecord.key !== rightRecord.key ||
        leftRecord.valueJson !== rightRecord.valueJson ||
        leftRecord.updatedAt !== rightRecord.updatedAt) {
        return false;
      }
    }
    return true;
  }

  private applyLoadedState(
    manifest: UserScriptValueManifestDocument,
    document: UserScriptValueStateDocument,
    unavailableTokens: string[]
  ): void {
    this.currentManifest = this.cloneManifest(manifest);
    this.lastDocument = this.cloneStateDocument(document);
    this.unavailableTokens = unavailableTokens.slice();
  }

  private cloneManifest(manifest: UserScriptValueManifestDocument): UserScriptValueManifestDocument {
    return {
      schemaVersion: manifest.schemaVersion,
      migrationState: manifest.migrationState,
      legacySource: manifest.legacySource,
      entries: manifest.entries.map((entry: UserScriptValueManifestEntry): UserScriptValueManifestEntry => {
        return { token: entry.token, scriptId: entry.scriptId };
      }),
      stateRevision: manifest.stateRevision,
      stateUpdatedAt: manifest.stateUpdatedAt,
      skippedScriptCount: manifest.skippedScriptCount,
      skippedUnattributedRecordCount: manifest.skippedUnattributedRecordCount,
      unreadableLegacySnapshot: manifest.unreadableLegacySnapshot,
      updatedAt: manifest.updatedAt,
      completedAt: manifest.completedAt
    };
  }

  private cloneStateDocument(document: UserScriptValueStateDocument): UserScriptValueStateDocument {
    return {
      schemaVersion: document.schemaVersion,
      revision: document.revision,
      values: document.values.map((record: UserScriptValueRecord): UserScriptValueRecord => {
        return cloneUserScriptValueRecord(record);
      }),
      updatedAt: document.updatedAt
    };
  }

  private createEmptyStateDocument(): UserScriptValueStateDocument {
    return {
      schemaVersion: USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
      revision: 0,
      values: [],
      updatedAt: 0
    };
  }

  private createEmptyMigrationSummary(): UserScriptValueMigrationSummary {
    return {
      skippedScriptCount: 0,
      skippedUnattributedRecordCount: 0,
      unreadableLegacySnapshot: false
    };
  }

  private cloneMigrationSummary(summary: UserScriptValueMigrationSummary): UserScriptValueMigrationSummary {
    return {
      skippedScriptCount: summary.skippedScriptCount,
      skippedUnattributedRecordCount: summary.skippedUnattributedRecordCount,
      unreadableLegacySnapshot: summary.unreadableLegacySnapshot
    };
  }

  private readManifestMigrationSummary(manifest: UserScriptValueManifestDocument): UserScriptValueMigrationSummary {
    return {
      skippedScriptCount: manifest.skippedScriptCount,
      skippedUnattributedRecordCount: manifest.skippedUnattributedRecordCount,
      unreadableLegacySnapshot: manifest.unreadableLegacySnapshot
    };
  }

  private buildScriptToken(scriptId: string): string {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: this.encoder.encodeInto(scriptId) });
    const bytes = (digest.digestSync() as cryptoFramework.DataBlob).data;
    let token = '';
    for (let index = 0; index < bytes.length; index += 1) {
      token += bytes[index].toString(16).padStart(2, '0');
    }
    return token;
  }

  private parseScriptTokenFileName(fileName: string): string {
    if (!fileName.endsWith(USER_SCRIPT_VALUE_DOCUMENT_FILE_SUFFIX)) {
      return '';
    }
    const token = fileName.slice(0, fileName.length - USER_SCRIPT_VALUE_DOCUMENT_FILE_SUFFIX.length);
    return this.isValidToken(token) ? token : '';
  }

  private isValidToken(token: string): boolean {
    if (token.length !== USER_SCRIPT_VALUE_TOKEN_HEX_LENGTH) {
      return false;
    }
    for (let index = 0; index < token.length; index += 1) {
      const character = token[index];
      const decimal = character >= '0' && character <= '9';
      const hex = character >= 'a' && character <= 'f';
      if (!decimal && !hex) {
        return false;
      }
    }
    return true;
  }

  private isLegacySource(value: string): boolean {
    return value === 'primary' || value === 'fallback' || value === 'none' ||
      value === 'unreadable' || value === 'isolated_recovered';
  }

  private isNonNegativeFinite(value: number): boolean {
    return Number.isFinite(value) && value >= 0;
  }

  private bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
    if (left.byteLength !== right.byteLength) {
      return false;
    }
    for (let index = 0; index < left.byteLength; index += 1) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  private mergeTokens(left: string[], right: string[]): string[] {
    const merged = left.slice();
    right.forEach((token: string): void => {
      if (!merged.includes(token)) {
        merged.push(token);
      }
    });
    return merged;
  }

  private async ensureStorageDirs(): Promise<void> {
    await this.ensureDir(this.resolveRootDir());
    await this.ensureDir(this.resolveScriptsDir());
  }

  private async ensureDir(path: string): Promise<void> {
    let exists = false;
    try {
      exists = await fileIo.access(path);
    } catch (_error) {
      exists = false;
    }
    if (exists) {
      return;
    }
    try {
      await fileIo.mkdir(path, true);
    } catch (error) {
      try {
        if (await fileIo.access(path)) {
          return;
        }
      } catch (_verifyError) {
      }
      throw this.toDurableError('mkdir', error);
    }
  }

  private resolveRootDir(): string {
    if (this.committedStateFilePath.length > 0) {
      const separatorIndex = this.committedStateFilePath.lastIndexOf('/');
      return separatorIndex > 0 ? this.committedStateFilePath.slice(0, separatorIndex) : '';
    }
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${USER_SCRIPT_VALUE_ROOT_DIR_NAME}`;
  }

  private resolveLegacyPrimaryFilePath(): string {
    if (this.committedStateFilePath.length > 0) {
      return this.committedStateFilePath;
    }
    return `${this.resolveRootDir()}/${USER_SCRIPT_VALUE_LEGACY_FILE_NAME}`;
  }

  private resolveLegacyFallbackFilePath(): string {
    return `${this.resolveLegacyPrimaryFilePath()}${USER_SCRIPT_VALUE_LEGACY_PREVIOUS_FILE_SUFFIX}`;
  }

  private resolveManifestFilePath(): string {
    return `${this.resolveRootDir()}/${USER_SCRIPT_VALUE_MANIFEST_FILE_NAME}`;
  }

  private resolveScriptsDir(): string {
    return `${this.resolveRootDir()}/${USER_SCRIPT_VALUE_SCRIPTS_DIR_NAME}`;
  }

  private resolveScriptFilePath(token: string): string {
    return `${this.resolveScriptsDir()}/${token}${USER_SCRIPT_VALUE_DOCUMENT_FILE_SUFFIX}`;
  }

  private resolveScriptJournalPath(token: string): string {
    return `${this.resolveScriptsDir()}/${token}${USER_SCRIPT_VALUE_JOURNAL_FILE_SUFFIX}`;
  }

  private logIsolatedDocumentFailure(
    token: string,
    error: Object | string | number | boolean | undefined
  ): void {
    const failure = this.toDurableError('read', error);
    hilog.error(
      USER_SCRIPT_VALUE_LOG_DOMAIN,
      USER_SCRIPT_VALUE_LOG_TAG,
      'isolated document unavailable token=%{public}s stage=%{public}s code=%{public}s',
      token,
      failure.stage,
      failure.platformCode
    );
  }

  private toDurableError(
    stage: UserScriptValueDurableStage,
    error: Object | string | number | boolean | undefined
  ): UserScriptValueDurableError {
    if (error instanceof UserScriptValueDurableError) {
      return error;
    }
    const shape = error as UserScriptValuePlatformErrorShape;
    const code = this.normalizePlatformCode(String(shape?.code ?? '').trim());
    const message = String(shape?.message ?? error ?? '').trim();
    return new UserScriptValueDurableError(
      stage,
      code.length > 0 ? code : this.classifyPlatformMessage(message)
    );
  }

  private normalizePlatformCode(code: string): string {
    if (code.length <= 0 || code.length > 64) {
      return '';
    }
    for (let index = 0; index < code.length; index += 1) {
      const character = code[index];
      const alphaNumeric = (character >= '0' && character <= '9') ||
        (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z');
      if (!alphaNumeric && character !== '-' && character !== '_') {
        return '';
      }
    }
    return code;
  }

  private classifyPlatformMessage(message: string): string {
    const normalized = message.toLowerCase();
    if (normalized.includes('invalid argument') || normalized.includes('illegal') ||
      normalized.includes('encoding') || normalized.includes('einval')) {
      return 'invalid-argument';
    }
    if (normalized.includes('permission') || normalized.includes('denied') ||
      normalized.includes('not permitted') || normalized.includes('eacces') || normalized.includes('eperm')) {
      return 'permission-denied';
    }
    if (normalized.includes('not found') || normalized.includes('no such') || normalized.includes('enoent')) {
      return 'not-found';
    }
    if (normalized.includes('no space') || normalized.includes('disk full') || normalized.includes('enospc')) {
      return 'no-space';
    }
    if (normalized.includes('busy') || normalized.includes('locked') || normalized.includes('ebusy')) {
      return 'busy';
    }
    return 'platform-error';
  }
}

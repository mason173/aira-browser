import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  cloneUserScriptRuntimeStateRecord,
  UserScriptInjectionPhase,
  UserScriptRuntimeStateRecord,
  UserScriptRuntimeStateSettings,
  UserScriptRuntimeStatus
} from '../../features/userscripts/UserScriptRuntimeStateModels';
import {
  UserScriptValueDiagnosticEvent,
  UserScriptValueDiagnosticKind,
  UserScriptValueDiagnosticSink
} from '../../features/userscripts/UserScriptValueModels';

const PREFERENCES_NAME: string = 'aira_browser_userscript_runtime_state';
const USER_SCRIPT_RUNTIME_STATE_KEY: string = 'user_script_runtime_state';
const USER_SCRIPT_VALUE_DIAGNOSTICS_KEY: string = 'user_script_value_diagnostics';
const MAX_RUNTIME_STATE_RECORDS: number = 500;
const MAX_VALUE_DIAGNOSTIC_EVENTS: number = 20;
const MAX_ERROR_MESSAGE_LENGTH: number = 800;
const MAX_DIAGNOSTIC_CODE_LENGTH: number = 64;
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'UserScriptRuntimeState';

export interface UserScriptRuntimeExecutionResultInput {
  scriptId: string;
  url: string;
  injectionPhase: UserScriptInjectionPhase;
  success: boolean;
  errorMessage: string;
}

export interface UserScriptRuntimeSkippedResultInput {
  scriptId: string;
  url: string;
  injectionPhase: UserScriptInjectionPhase;
  skipReason: string;
}

export interface UserScriptValueDiagnosticRecorder {
  record(event: UserScriptValueDiagnosticEvent): void;
}

export class UserScriptValueDiagnosticRecorderAdapter implements UserScriptValueDiagnosticRecorder {
  private readonly callback: (event: UserScriptValueDiagnosticEvent) => void;

  constructor(callback: (event: UserScriptValueDiagnosticEvent) => void) {
    this.callback = callback;
  }

  record(event: UserScriptValueDiagnosticEvent): void {
    this.callback(event);
  }
}

export class UserScriptRuntimeStateRepository implements UserScriptValueDiagnosticSink {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private initializationPromise?: Promise<void>;
  private initialized: boolean = false;
  private initializationFailureLogged: boolean = false;
  private valueStateDiagnostics: UserScriptValueDiagnosticEvent[] = [];
  private diagnosticRecorder?: UserScriptValueDiagnosticRecorder;
  private settings: UserScriptRuntimeStateSettings = {
    records: [],
    updatedAt: 0
  };

  async initialize(): Promise<UserScriptRuntimeStateSettings> {
    if (this.initialized) {
      return this.getSettings();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.loadSettings();
    }
    try {
      await this.initializationPromise;
    } catch (error) {
      this.initializationPromise = undefined;
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('User script runtime state initialization failed.');
    }
    return this.getSettings();
  }

  attachDiagnosticRecorder(recorder: UserScriptValueDiagnosticRecorder): void {
    this.diagnosticRecorder = recorder;
  }

  getSettings(): UserScriptRuntimeStateSettings {
    return {
      records: this.settings.records.map((record: UserScriptRuntimeStateRecord) =>
        cloneUserScriptRuntimeStateRecord(record)
      ),
      updatedAt: this.settings.updatedAt
    };
  }

  listRecords(): UserScriptRuntimeStateRecord[] {
    return this.getSettings().records;
  }

  listValueStateDiagnostics(): UserScriptValueDiagnosticEvent[] {
    return this.valueStateDiagnostics.map((event: UserScriptValueDiagnosticEvent): UserScriptValueDiagnosticEvent => {
      return {
        kind: event.kind,
        stage: event.stage,
        code: event.code,
        occurredAt: event.occurredAt
      };
    });
  }

  findRecord(scriptId: string): UserScriptRuntimeStateRecord | undefined {
    const normalizedScriptId = scriptId.trim();
    return this.settings.records.find((record: UserScriptRuntimeStateRecord) => record.scriptId === normalizedScriptId);
  }

  async recordSuccess(
    scriptId: string,
    url: string,
    injectionPhase: UserScriptInjectionPhase
  ): Promise<UserScriptRuntimeStateSettings> {
    if (!await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    return this.upsertRecord(scriptId, {
      status: 'success',
      url: url,
      injectionPhase: injectionPhase,
      errorMessage: '',
      skipReason: '',
      bridgeCapability: '',
      bridgeRejectReason: ''
    });
  }

  async recordFailure(
    scriptId: string,
    url: string,
    injectionPhase: UserScriptInjectionPhase,
    errorMessage: string
  ): Promise<UserScriptRuntimeStateSettings> {
    if (!await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    return this.upsertRecord(scriptId, {
      status: 'failed',
      url: url,
      injectionPhase: injectionPhase,
      errorMessage: errorMessage,
      skipReason: '',
      bridgeCapability: '',
      bridgeRejectReason: ''
    });
  }

  async recordExecutionResults(
    results: UserScriptRuntimeExecutionResultInput[]
  ): Promise<UserScriptRuntimeStateSettings> {
    if (results.length === 0 || !await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    let nextSettings = this.settings;
    const now = Date.now();
    results.forEach((result: UserScriptRuntimeExecutionResultInput): void => {
      nextSettings = this.buildUpsertedSettings(nextSettings, result.scriptId, {
        status: result.success ? 'success' : 'failed',
        url: result.url,
        injectionPhase: result.injectionPhase,
        errorMessage: result.success ? '' : result.errorMessage,
        skipReason: '',
        bridgeCapability: '',
        bridgeRejectReason: ''
      }, now);
    });
    return this.persistSettings(nextSettings);
  }

  async recordSkipped(
    scriptId: string,
    url: string,
    injectionPhase: UserScriptInjectionPhase,
    skipReason: string
  ): Promise<UserScriptRuntimeStateSettings> {
    if (!await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    return this.upsertRecord(scriptId, {
      status: 'skipped',
      url: url,
      injectionPhase: injectionPhase,
      errorMessage: '',
      skipReason: skipReason,
      bridgeCapability: '',
      bridgeRejectReason: ''
    });
  }

  async recordSkippedResults(
    results: UserScriptRuntimeSkippedResultInput[]
  ): Promise<UserScriptRuntimeStateSettings> {
    if (results.length === 0 || !await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    let nextSettings = this.settings;
    const now = Date.now();
    results.forEach((result: UserScriptRuntimeSkippedResultInput): void => {
      nextSettings = this.buildUpsertedSettings(nextSettings, result.scriptId, {
        status: 'skipped',
        url: result.url,
        injectionPhase: result.injectionPhase,
        errorMessage: '',
        skipReason: result.skipReason,
        bridgeCapability: '',
        bridgeRejectReason: ''
      }, now);
    });
    return this.persistSettings(nextSettings);
  }

  async recordBridgeRejected(
    scriptId: string,
    url: string,
    injectionPhase: UserScriptInjectionPhase,
    capability: string,
    rejectReason: string
  ): Promise<UserScriptRuntimeStateSettings> {
    if (!await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    const normalizedCapability = capability.trim();
    const normalizedReason = rejectReason.trim();
    const errorMessage = normalizedCapability.length > 0
      ? `native bridge rejected: ${normalizedCapability} · ${normalizedReason}`
      : `native bridge rejected: ${normalizedReason}`;
    return this.upsertRecord(scriptId, {
      status: 'failed',
      url: url,
      injectionPhase: injectionPhase,
      errorMessage: errorMessage,
      skipReason: '',
      bridgeCapability: normalizedCapability,
      bridgeRejectReason: normalizedReason
    });
  }

  async recordValueStateDiagnostic(event: UserScriptValueDiagnosticEvent): Promise<void> {
    this.diagnosticRecorder?.record(event);
    if (!await this.ensureInitializedForMutation()) {
      return;
    }
    const normalized = this.normalizeValueStateDiagnostic(event);
    this.valueStateDiagnostics = this.valueStateDiagnostics
      .concat(normalized)
      .slice(-MAX_VALUE_DIAGNOSTIC_EVENTS);
    const store = await this.getStore();
    store.putSync(USER_SCRIPT_VALUE_DIAGNOSTICS_KEY, JSON.stringify(this.valueStateDiagnostics));
    await store.flush();
  }

  async deleteScriptState(scriptId: string): Promise<UserScriptRuntimeStateSettings> {
    if (!await this.ensureInitializedForMutation()) {
      return this.getSettings();
    }
    const normalizedScriptId = scriptId.trim();
    return this.persistSettings({
      records: this.settings.records.filter((record: UserScriptRuntimeStateRecord) =>
        record.scriptId !== normalizedScriptId
      ),
      updatedAt: Date.now()
    });
  }

  private async upsertRecord(scriptId: string, next: RuntimeStateUpsert): Promise<UserScriptRuntimeStateSettings> {
    if (scriptId.trim().length === 0) {
      return this.getSettings();
    }
    return this.persistSettings(this.buildUpsertedSettings(this.settings, scriptId, next, Date.now()));
  }

  private buildUpsertedSettings(
    settings: UserScriptRuntimeStateSettings,
    scriptId: string,
    next: RuntimeStateUpsert,
    now: number
  ): UserScriptRuntimeStateSettings {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length === 0) {
      return settings;
    }
    const existing = settings.records.find((record: UserScriptRuntimeStateRecord): boolean => {
      return record.scriptId === normalizedScriptId;
    });
    const failed = next.status === 'failed';
    const record: UserScriptRuntimeStateRecord = {
      scriptId: normalizedScriptId,
      status: next.status,
      lastUrl: next.url.trim(),
      lastInjectionPhase: this.normalizeInjectionPhase(next.injectionPhase),
      lastErrorMessage: failed ? this.truncateErrorMessage(next.errorMessage) : '',
      lastSkipReason: next.status === 'skipped' ? this.truncateReason(next.skipReason) : '',
      lastBridgeCapability: failed ? this.truncateReason(next.bridgeCapability) : '',
      lastBridgeRejectReason: failed ? this.truncateReason(next.bridgeRejectReason) : '',
      lastRunAt: now,
      lastSuccessAt: failed ? existing?.lastSuccessAt ?? 0 : now,
      lastFailureAt: failed ? now : existing?.lastFailureAt ?? 0,
      runCount: Math.max(0, existing?.runCount ?? 0) + 1,
      failureCount: Math.max(0, existing?.failureCount ?? 0) + (failed ? 1 : 0)
    };
    const nextRecords = settings.records
      .filter((item: UserScriptRuntimeStateRecord) => item.scriptId !== normalizedScriptId)
      .concat(record)
      .sort((left: UserScriptRuntimeStateRecord, right: UserScriptRuntimeStateRecord) =>
        right.lastRunAt - left.lastRunAt
      )
      .slice(0, MAX_RUNTIME_STATE_RECORDS);
    return {
      records: nextRecords,
      updatedAt: now
    };
  }

  private normalizeSettings(value: UserScriptRuntimeStateSettings | undefined): UserScriptRuntimeStateSettings {
    return {
      records: this.normalizeRecords(value?.records ?? []),
      updatedAt: this.normalizeTimestamp(value?.updatedAt)
    };
  }

  private normalizeRecords(values: UserScriptRuntimeStateRecord[]): UserScriptRuntimeStateRecord[] {
    const results: UserScriptRuntimeStateRecord[] = [];
    values.forEach((value: UserScriptRuntimeStateRecord) => {
      const scriptId = String(value.scriptId ?? '').trim();
      if (scriptId.length === 0 || results.some((record: UserScriptRuntimeStateRecord) => record.scriptId === scriptId)) {
        return;
      }
      results.push({
        scriptId: scriptId,
        status: this.normalizeStatus(value.status),
        lastUrl: String(value.lastUrl ?? '').trim(),
        lastInjectionPhase: this.normalizeInjectionPhase(value.lastInjectionPhase),
        lastErrorMessage: this.truncateErrorMessage(String(value.lastErrorMessage ?? '')),
        lastSkipReason: this.truncateReason(String(value.lastSkipReason ?? '')),
        lastBridgeCapability: this.truncateReason(String(value.lastBridgeCapability ?? '')),
        lastBridgeRejectReason: this.truncateReason(String(value.lastBridgeRejectReason ?? '')),
        lastRunAt: this.normalizeTimestamp(value.lastRunAt),
        lastSuccessAt: this.normalizeTimestamp(value.lastSuccessAt),
        lastFailureAt: this.normalizeTimestamp(value.lastFailureAt),
        runCount: Math.max(0, Math.round(value.runCount ?? 0)),
        failureCount: Math.max(0, Math.round(value.failureCount ?? 0))
      });
    });
    return results.slice(0, MAX_RUNTIME_STATE_RECORDS);
  }

  private normalizeStatus(value: UserScriptRuntimeStatus | undefined): UserScriptRuntimeStatus {
    if (value === 'success' || value === 'failed' || value === 'skipped') {
      return value;
    }
    return 'never_run';
  }

  private normalizeInjectionPhase(value: UserScriptInjectionPhase | string | undefined): UserScriptInjectionPhase {
    if (value === 'document-start' ||
      value === 'document-idle' ||
      value === 'document-end' ||
      value === 'main-menu' ||
      value === 'tool-menu' ||
      value === 'context-menu') {
      return value;
    }
    return 'unknown';
  }

  private truncateErrorMessage(value: string): string {
    const trimmed = value.trim();
    if (trimmed.length <= MAX_ERROR_MESSAGE_LENGTH) {
      return trimmed;
    }
    return trimmed.substring(0, MAX_ERROR_MESSAGE_LENGTH);
  }

  private truncateReason(value: string): string {
    return this.truncateErrorMessage(value);
  }

  private async loadSettings(): Promise<void> {
    const store = await this.getStore();
    const rawSettings = String(store.getSync(USER_SCRIPT_RUNTIME_STATE_KEY, ''));
    if (rawSettings.trim().length === 0) {
      this.settings = this.normalizeSettings(undefined);
      await this.persistSettings(this.settings);
    } else {
      this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
    }
    this.valueStateDiagnostics = this.parseValueStateDiagnostics(
      String(store.getSync(USER_SCRIPT_VALUE_DIAGNOSTICS_KEY, ''))
    );
    this.initialized = true;
    this.initializationFailureLogged = false;
  }

  private parseSettings(value: string): UserScriptRuntimeStateSettings {
    let parsed: UserScriptRuntimeStateSettings;
    try {
      parsed = JSON.parse(value) as UserScriptRuntimeStateSettings;
    } catch (error) {
      const message = error instanceof Error ? error.message : 'parse-failed';
      throw new Error(`userscript-runtime-state-invalid-state: invalid-json:${message}`);
    }
    if (parsed === undefined || parsed === null || !Array.isArray(parsed.records) ||
      parsed.records.length > MAX_RUNTIME_STATE_RECORDS ||
      !this.isValidNonNegativeNumber(parsed.updatedAt)) {
      throw new Error('userscript-runtime-state-invalid-state: invalid-settings-shape');
    }
    const seenScriptIds: string[] = [];
    parsed.records.forEach((record: UserScriptRuntimeStateRecord) => {
      if (record === undefined || record === null ||
        typeof record.scriptId !== 'string' || record.scriptId.trim().length === 0 ||
        seenScriptIds.includes(record.scriptId.trim()) ||
        !this.isValidStatus(record.status) ||
        typeof record.lastUrl !== 'string' ||
        !this.isValidOptionalInjectionPhase(record.lastInjectionPhase) ||
        !this.isValidDiagnosticText(record.lastErrorMessage) ||
        !this.isValidOptionalDiagnosticText(record.lastSkipReason) ||
        !this.isValidOptionalDiagnosticText(record.lastBridgeCapability) ||
        !this.isValidOptionalDiagnosticText(record.lastBridgeRejectReason) ||
        !this.isValidNonNegativeNumber(record.lastRunAt) ||
        !this.isValidNonNegativeNumber(record.lastSuccessAt) ||
        !this.isValidNonNegativeNumber(record.lastFailureAt) ||
        !this.isValidNonNegativeInteger(record.runCount) ||
        !this.isValidNonNegativeInteger(record.failureCount) ||
        record.failureCount > record.runCount) {
        throw new Error('userscript-runtime-state-invalid-state: invalid-runtime-record');
      }
      seenScriptIds.push(record.scriptId.trim());
    });
    return parsed;
  }

  private parseValueStateDiagnostics(value: string): UserScriptValueDiagnosticEvent[] {
    if (value.trim().length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as UserScriptValueDiagnosticEvent[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .map((event: UserScriptValueDiagnosticEvent): UserScriptValueDiagnosticEvent => {
          return this.normalizeValueStateDiagnostic(event);
        })
        .slice(-MAX_VALUE_DIAGNOSTIC_EVENTS);
    } catch (_error) {
      return [];
    }
  }

  private normalizeValueStateDiagnostic(event: UserScriptValueDiagnosticEvent): UserScriptValueDiagnosticEvent {
    return {
      kind: this.normalizeValueStateDiagnosticKind(event?.kind),
      stage: this.normalizeDiagnosticCode(event?.stage),
      code: this.normalizeDiagnosticCode(event?.code),
      occurredAt: this.normalizeTimestamp(event?.occurredAt)
    };
  }

  private normalizeValueStateDiagnosticKind(
    kind: UserScriptValueDiagnosticKind | string | undefined
  ): UserScriptValueDiagnosticKind {
    if (kind === 'startup_blocked' || kind === 'startup_backup_recovered' ||
      kind === 'runtime_commit_failed' || kind === 'runtime_commit_recovered') {
      return kind;
    }
    return 'startup_blocked';
  }

  private normalizeDiagnosticCode(value: string | undefined): string {
    return String(value ?? '').trim().substring(0, MAX_DIAGNOSTIC_CODE_LENGTH);
  }

  private isValidStatus(value: UserScriptRuntimeStatus | string | undefined): boolean {
    return value === 'never_run' || value === 'success' || value === 'failed' || value === 'skipped';
  }

  private isValidInjectionPhase(value: UserScriptInjectionPhase | string | undefined): boolean {
    return value === 'document-start' ||
      value === 'document-idle' ||
      value === 'document-end' ||
      value === 'main-menu' ||
      value === 'tool-menu' ||
      value === 'context-menu' ||
      value === 'unknown';
  }

  private isValidOptionalInjectionPhase(value: UserScriptInjectionPhase | string | undefined): boolean {
    return value === undefined || this.isValidInjectionPhase(value);
  }

  private isValidDiagnosticText(value: string | undefined): boolean {
    return typeof value === 'string' && value.trim().length <= MAX_ERROR_MESSAGE_LENGTH;
  }

  private isValidOptionalDiagnosticText(value: string | undefined): boolean {
    return value === undefined || this.isValidDiagnosticText(value);
  }

  private isValidNonNegativeNumber(value: number | undefined): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value >= 0;
  }

  private isValidNonNegativeInteger(value: number | undefined): boolean {
    return this.isValidNonNegativeNumber(value) && Math.floor(value as number) === value;
  }

  private async ensureInitializedForMutation(): Promise<boolean> {
    try {
      await this.initialize();
      return true;
    } catch (error) {
      if (!this.initializationFailureLogged) {
        this.initializationFailureLogged = true;
        const message = error instanceof Error ? error.message : String(error);
        hilog.warn(
          LOG_DOMAIN,
          LOG_TAG,
          'Runtime diagnostics mutation skipped because initialization failed: %{public}s',
          message
        );
      }
      return false;
    }
  }

  private async persistSettings(settings: UserScriptRuntimeStateSettings): Promise<UserScriptRuntimeStateSettings> {
    this.settings = this.normalizeSettings(settings);
    const store = await this.getStore();
    store.putSync(USER_SCRIPT_RUNTIME_STATE_KEY, JSON.stringify(this.settings));
    await store.flush();
    return this.getSettings();
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && value > 0 ? value : 0;
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}

interface RuntimeStateUpsert {
  status: UserScriptRuntimeStatus;
  url: string;
  injectionPhase: UserScriptInjectionPhase;
  errorMessage: string;
  skipReason: string;
  bridgeCapability: string;
  bridgeRejectReason: string;
}

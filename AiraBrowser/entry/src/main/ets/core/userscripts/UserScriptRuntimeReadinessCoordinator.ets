import { UserScriptRepository } from '../../data/userscripts/UserScriptRepository';
import { UserScriptRiskConsentRepository } from '../../data/userscripts/UserScriptRiskConsentRepository';
import { UserScriptRuntimeStateRepository } from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import { InstalledUserScriptState } from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptValueStateError } from '../../features/userscripts/UserScriptValueModels';

export class UserScriptRuntimeReadinessCoordinator {
  private static executionReady: boolean = false;
  private readonly scriptRepository: UserScriptRepository;
  private readonly riskConsentRepository: UserScriptRiskConsentRepository;
  private readonly valueStore: UserScriptValueStateStore;
  private readonly runtimeStateRepository: UserScriptRuntimeStateRepository;
  private executionInitializationPromise?: Promise<void>;
  private diagnosticsInitializationPromise?: Promise<void>;

  constructor(
    scriptRepository: UserScriptRepository,
    riskConsentRepository: UserScriptRiskConsentRepository,
    valueStore: UserScriptValueStateStore,
    runtimeStateRepository: UserScriptRuntimeStateRepository
  ) {
    this.scriptRepository = scriptRepository;
    this.riskConsentRepository = riskConsentRepository;
    this.valueStore = valueStore;
    this.runtimeStateRepository = runtimeStateRepository;
  }

  initializeExecutionState(): Promise<void> {
    if (this.executionInitializationPromise === undefined) {
      const pending = this.initializeExecutionRepositories();
      this.executionInitializationPromise = pending;
      pending.then(
        (): void => this.clearExecutionInitialization(pending),
        (_error: Error): void => this.clearExecutionInitialization(pending)
      );
    }
    return this.executionInitializationPromise;
  }

  listExecutionReadyScripts(): InstalledUserScriptState[] {
    if (!UserScriptRuntimeReadinessCoordinator.executionReady) {
      return [];
    }
    return this.scriptRepository.listScripts().filter((script: InstalledUserScriptState): boolean => {
      return this.valueStore.isScriptStateAvailable(script.id);
    });
  }

  findExecutionReadyScript(scriptId: string): InstalledUserScriptState | undefined {
    if (!UserScriptRuntimeReadinessCoordinator.executionReady) {
      return undefined;
    }
    if (!this.valueStore.isScriptStateAvailable(scriptId)) {
      return undefined;
    }
    return this.scriptRepository.findScript(scriptId);
  }

  initializeDiagnostics(): Promise<void> {
    if (this.diagnosticsInitializationPromise === undefined) {
      const pending = this.runtimeStateRepository.initialize().then((): void => undefined);
      this.diagnosticsInitializationPromise = pending;
      pending.catch((_error: Error) => {
        if (this.diagnosticsInitializationPromise === pending) {
          this.diagnosticsInitializationPromise = undefined;
        }
      });
    }
    return this.diagnosticsInitializationPromise;
  }

  private async initializeExecutionRepositories(): Promise<void> {
    try {
      await this.riskConsentRepository.initialize();
      if (await this.scriptRepository.mayHaveEnabledScriptsAtStartup()) {
        const settings = await this.scriptRepository.initialize();
        if (settings.scripts.some((script: InstalledUserScriptState): boolean => script.enabled)) {
          await this.valueStore.initialize();
        }
      }
      // Diagnostics have their own background initializer. All-disabled packages
      // retain their files without reading or replaying GM state on cold startup.
      UserScriptRuntimeReadinessCoordinator.executionReady = true;
    } catch (error) {
      UserScriptRuntimeReadinessCoordinator.executionReady = false;
      if (error instanceof UserScriptValueStateError && error.failureKind === 'readiness' &&
        this.valueStore.readReadiness().status === 'blocked') {
        return;
      }
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('User script execution readiness initialization failed.');
    }
  }

  private clearExecutionInitialization(pending: Promise<void>): void {
    if (this.executionInitializationPromise === pending) {
      // Coalesce concurrent calls, not future enable/install transitions. A later
      // navigation must reconsider packages enabled since the empty cold start.
      this.executionInitializationPromise = undefined;
    }
  }
}

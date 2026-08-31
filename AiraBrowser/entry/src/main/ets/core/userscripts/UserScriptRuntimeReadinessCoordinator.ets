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
      pending.catch((_error: Error) => {
        if (this.executionInitializationPromise === pending) {
          this.executionInitializationPromise = undefined;
        }
      });
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
    UserScriptRuntimeReadinessCoordinator.executionReady = false;
    try {
      const readinessTasks: Promise<void>[] = [
        this.scriptRepository.initialize().then((): void => undefined),
        this.riskConsentRepository.initialize().then((): void => undefined),
        this.valueStore.initialize().then((): void => undefined),
        this.runtimeStateRepository.initialize()
          .then((): void => undefined)
          .catch((_error: Error): void => {
            // Runtime diagnostics are best-effort and must never block script execution readiness.
          })
      ];
      await Promise.all(readinessTasks);
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
}

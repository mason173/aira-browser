import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import {
  BrowserCreateTabOptions,
  BrowserTabState
} from '../tabs/TabManager';
import {
  BrowserWindowContextCoordinator,
  BrowserWindowContextDependencies,
  BrowserWindowContextPort,
  BrowserWindowContextShell,
  BrowserWindowLaunchApplicationResolver
} from './BrowserWindowContextCoordinator';
import { BrowserWindowSessionContextStateBinding } from './BrowserWindowSessionContextState';

export class BrowserWindowSessionContextBinding {
}

export interface BrowserWindowSessionContextComposition {
  dependencies: BrowserWindowContextDependencies;
  shell: BrowserWindowContextShell;
  resolveLaunchApplication: BrowserWindowLaunchApplicationResolver;
}

export interface BrowserWindowSessionContextOperations extends BrowserWindowContextPort {
  isAvailable(): boolean;
  connect(composition: BrowserWindowSessionContextComposition): void;
  disconnect(): void;
}

export class BrowserWindowSessionContextOperationsImplementation
  implements BrowserWindowSessionContextOperations {
  private readonly isSessionAvailable: () => boolean;
  private coordinator?: BrowserWindowContextCoordinator;

  constructor(isSessionAvailable: () => boolean) {
    this.isSessionAvailable = isSessionAvailable;
  }

  isAvailable(): boolean {
    return this.isSessionAvailable() && this.coordinator !== undefined;
  }

  connect(composition: BrowserWindowSessionContextComposition): void {
    if (!this.isSessionAvailable()) {
      return;
    }
    this.coordinator?.disconnectSessionContextState();
    this.coordinator = new BrowserWindowContextCoordinator(
      composition.dependencies,
      composition.shell,
      composition.resolveLaunchApplication
    );
  }

  disconnect(): void {
    this.coordinator?.disconnectSessionContextState();
    this.coordinator = undefined;
  }

  connectSessionContextState(binding: BrowserWindowSessionContextStateBinding | undefined): void {
    this.coordinator?.connectSessionContextState(binding);
  }

  disconnectSessionContextState(): void {
    this.coordinator?.disconnectSessionContextState();
  }

  resolveCurrentScope(): void {
    this.coordinator?.resolveCurrentScope();
  }

  hasPendingWebSceneLaunch(): boolean {
    return this.coordinator?.hasPendingWebSceneLaunch() ?? false;
  }

  consumePendingLaunch(source: string): boolean {
    return this.coordinator?.consumePendingLaunch(source) ?? false;
  }

  consumePendingWebSceneLaunch(source: string): boolean {
    return this.coordinator?.consumePendingWebSceneLaunch(source) ?? false;
  }

  resolveCurrentTabSessionBoundary(): BrowserCreateTabOptions {
    return this.coordinator?.resolveCurrentTabSessionBoundary() ?? this.buildDefaultTabSessionBoundary();
  }

  resolveCurrentTabSessionProfileId(): BrowserProfileId {
    return this.coordinator?.resolveCurrentTabSessionProfileId() ?? DEFAULT_BROWSER_PROFILE_ID;
  }

  schedulePendingLaunchPolling(): void {
    this.coordinator?.schedulePendingLaunchPolling();
  }

  stopPendingLaunchPolling(): void {
    this.coordinator?.stopPendingLaunchPolling();
  }

  getSuspendedWindowTabsByWindowId(): Record<string, BrowserTabState[] | undefined> {
    return this.coordinator?.getSuspendedWindowTabsByWindowId() ?? {};
  }

  private buildDefaultTabSessionBoundary(): BrowserCreateTabOptions {
    return {
      profileId: DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: 'regular' as BrowserSessionPrivacyMode,
      dataScope: 'profile_persistent' as BrowserDataScope
    };
  }
}

const contextOperationsByBinding: Map<BrowserWindowSessionContextBinding,
  BrowserWindowSessionContextOperations> = new Map();

export function registerBrowserWindowSessionContextOperations(
  binding: BrowserWindowSessionContextBinding,
  operations: BrowserWindowSessionContextOperations
): void {
  contextOperationsByBinding.set(binding, operations);
}

export function unregisterBrowserWindowSessionContextOperations(
  binding: BrowserWindowSessionContextBinding
): void {
  contextOperationsByBinding.delete(binding);
}

export function resolveBrowserWindowSessionContextOperations(
  binding: BrowserWindowSessionContextBinding | undefined
): BrowserWindowSessionContextOperations | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return contextOperationsByBinding.get(binding);
}

export class BrowserWindowSessionContextPort implements BrowserWindowContextPort {
  private operations?: BrowserWindowSessionContextOperations;

  connect(binding: BrowserWindowSessionContextBinding | undefined): void {
    this.operations = resolveBrowserWindowSessionContextOperations(binding);
  }

  disconnect(): void {
    this.operations = undefined;
  }

  isConnected(): boolean {
    return this.operations?.isAvailable() === true;
  }

  connectSessionContextState(binding: BrowserWindowSessionContextStateBinding | undefined): void {
    this.operations?.connectSessionContextState(binding);
  }

  disconnectSessionContextState(): void {
    this.operations?.disconnectSessionContextState();
  }

  resolveCurrentScope(): void {
    this.operations?.resolveCurrentScope();
  }

  hasPendingWebSceneLaunch(): boolean {
    return this.operations?.hasPendingWebSceneLaunch() ?? false;
  }

  consumePendingLaunch(source: string): boolean {
    return this.operations?.consumePendingLaunch(source) ?? false;
  }

  consumePendingWebSceneLaunch(source: string): boolean {
    return this.operations?.consumePendingWebSceneLaunch(source) ?? false;
  }

  resolveCurrentTabSessionBoundary(): BrowserCreateTabOptions {
    return this.operations?.resolveCurrentTabSessionBoundary() ?? {
      profileId: DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: 'regular' as BrowserSessionPrivacyMode,
      dataScope: 'profile_persistent' as BrowserDataScope
    };
  }

  resolveCurrentTabSessionProfileId(): BrowserProfileId {
    return this.operations?.resolveCurrentTabSessionProfileId() ?? DEFAULT_BROWSER_PROFILE_ID;
  }

  schedulePendingLaunchPolling(): void {
    this.operations?.schedulePendingLaunchPolling();
  }

  stopPendingLaunchPolling(): void {
    this.operations?.stopPendingLaunchPolling();
  }

  getSuspendedWindowTabsByWindowId(): Record<string, BrowserTabState[] | undefined> {
    return this.operations?.getSuspendedWindowTabsByWindowId() ?? {};
  }
}

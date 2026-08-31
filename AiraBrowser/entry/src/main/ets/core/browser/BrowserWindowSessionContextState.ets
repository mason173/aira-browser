import { BrowserWindowSuspendedContext } from './BrowserWindowContextState';

export class BrowserWindowSessionContextStateBinding {
}

export interface BrowserWindowSessionContextStateStore {
  isAvailable(): boolean;
  getSuspendedContexts(): Record<string, BrowserWindowSuspendedContext | undefined>;
  setSuspendedContext(windowId: string, context: BrowserWindowSuspendedContext): void;
  takeSuspendedContext(windowId: string): BrowserWindowSuspendedContext | undefined;
}

const contextStateStoresByBinding: Map<BrowserWindowSessionContextStateBinding,
  BrowserWindowSessionContextStateStore> = new Map();

export function registerBrowserWindowSessionContextStateStore(
  binding: BrowserWindowSessionContextStateBinding,
  store: BrowserWindowSessionContextStateStore
): void {
  contextStateStoresByBinding.set(binding, store);
}

export function unregisterBrowserWindowSessionContextStateStore(
  binding: BrowserWindowSessionContextStateBinding
): void {
  contextStateStoresByBinding.delete(binding);
}

export function resolveBrowserWindowSessionContextStateBinding(
  binding: BrowserWindowSessionContextStateBinding | undefined
): BrowserWindowSessionContextStateStore | undefined {
  if (binding === undefined) {
    return undefined;
  }
  return contextStateStoresByBinding.get(binding);
}

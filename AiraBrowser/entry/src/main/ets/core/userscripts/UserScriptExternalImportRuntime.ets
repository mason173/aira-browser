export type UserScriptExternalImportStatus = 'prepared' | 'failed';

export interface UserScriptExternalImportEnvelope {
  requestId: string;
  status: UserScriptExternalImportStatus;
  errorMessage: string;
}

export interface UserScriptExternalImportStageResult {
  notifiedListenerCount: number;
  displaced?: UserScriptExternalImportEnvelope;
}

export type UserScriptExternalImportListener = () => void;

export class UserScriptExternalImportRuntime {
  private static pending?: UserScriptExternalImportEnvelope;
  private static listeners: UserScriptExternalImportListener[] = [];

  static stage(envelope: UserScriptExternalImportEnvelope): UserScriptExternalImportStageResult {
    const displaced = UserScriptExternalImportRuntime.pending;
    UserScriptExternalImportRuntime.pending = envelope;
    const listeners = UserScriptExternalImportRuntime.listeners.slice();
    listeners.forEach((listener: UserScriptExternalImportListener): void => {
      listener();
    });
    return {
      notifiedListenerCount: listeners.length,
      displaced: displaced
    };
  }

  static consume(requestId: string = ''): UserScriptExternalImportEnvelope | undefined {
    const pending = UserScriptExternalImportRuntime.pending;
    if (requestId.length > 0 && pending?.requestId !== requestId) {
      return undefined;
    }
    UserScriptExternalImportRuntime.pending = undefined;
    return pending;
  }

  static isPending(requestId: string): boolean {
    return requestId.length > 0 && UserScriptExternalImportRuntime.pending?.requestId === requestId;
  }

  static subscribe(listener: UserScriptExternalImportListener): void {
    if (UserScriptExternalImportRuntime.listeners.indexOf(listener) >= 0) {
      return;
    }
    UserScriptExternalImportRuntime.listeners.push(listener);
  }

  static unsubscribe(listener: UserScriptExternalImportListener): void {
    UserScriptExternalImportRuntime.listeners = UserScriptExternalImportRuntime.listeners.filter(
      (candidate: UserScriptExternalImportListener): boolean => candidate !== listener
    );
  }
}

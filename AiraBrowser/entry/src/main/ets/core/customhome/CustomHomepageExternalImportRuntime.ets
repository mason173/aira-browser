import { CustomHomepageItem } from '../../common/models/CustomHomepageModels';
import { CustomHomepagePreparedPackageImport } from '../../services/customhome/CustomHomepageFileService';

export type CustomHomepageExternalImportStatus = 'prepared' | 'failed';

export interface CustomHomepageExternalImportEnvelope {
  requestId: string;
  status: CustomHomepageExternalImportStatus;
  prepared?: CustomHomepagePreparedPackageImport;
  item?: CustomHomepageItem;
  updated: boolean;
  errorMessage: string;
}

export interface CustomHomepageExternalImportStageResult {
  notifiedListenerCount: number;
  displaced?: CustomHomepageExternalImportEnvelope;
}

export type CustomHomepageExternalImportListener = () => void;

export class CustomHomepageExternalImportRuntime {
  private static pending?: CustomHomepageExternalImportEnvelope;
  private static listeners: CustomHomepageExternalImportListener[] = [];

  static stage(envelope: CustomHomepageExternalImportEnvelope): CustomHomepageExternalImportStageResult {
    const displaced = CustomHomepageExternalImportRuntime.pending;
    CustomHomepageExternalImportRuntime.pending = envelope;
    const listeners = CustomHomepageExternalImportRuntime.listeners.slice();
    listeners.forEach((listener: CustomHomepageExternalImportListener): void => {
      listener();
    });
    return {
      notifiedListenerCount: listeners.length,
      displaced: displaced
    };
  }

  static consume(requestId: string = ''): CustomHomepageExternalImportEnvelope | undefined {
    const pending = CustomHomepageExternalImportRuntime.pending;
    if (requestId.length > 0 && pending?.requestId !== requestId) {
      return undefined;
    }
    CustomHomepageExternalImportRuntime.pending = undefined;
    return pending;
  }

  static isPending(requestId: string): boolean {
    return requestId.length > 0 && CustomHomepageExternalImportRuntime.pending?.requestId === requestId;
  }

  static subscribe(listener: CustomHomepageExternalImportListener): void {
    if (CustomHomepageExternalImportRuntime.listeners.indexOf(listener) >= 0) {
      return;
    }
    CustomHomepageExternalImportRuntime.listeners.push(listener);
  }

  static unsubscribe(listener: CustomHomepageExternalImportListener): void {
    CustomHomepageExternalImportRuntime.listeners = CustomHomepageExternalImportRuntime.listeners.filter(
      (candidate: CustomHomepageExternalImportListener): boolean => candidate !== listener
    );
  }
}

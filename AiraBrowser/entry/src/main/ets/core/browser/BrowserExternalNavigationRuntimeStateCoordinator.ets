import {
  ExternalNavigationPolicyService,
  ExternalNavigationSuppressionRecord
} from '../../services/web/ExternalNavigationPolicyService';

export class BrowserExternalNavigationRuntimeStateCoordinator {
  private lastExternalNavigationUrl: string = '';
  private lastExternalNavigationToastAt: number = 0;
  private suppressionRecords: ExternalNavigationSuppressionRecord[] = [];

  refreshSuppressionRecords(
    policyService: ExternalNavigationPolicyService,
    now: number
  ): ExternalNavigationSuppressionRecord[] {
    this.suppressionRecords = policyService.pruneSuppressionRecords(this.suppressionRecords, now);
    return this.suppressionRecords;
  }

  resolveSuppressionRecords(): ExternalNavigationSuppressionRecord[] {
    return this.suppressionRecords;
  }

  replaceSuppressionRecords(records: ExternalNavigationSuppressionRecord[]): void {
    this.suppressionRecords = records;
  }

  resolveDuplicateUrl(): string {
    return this.lastExternalNavigationUrl;
  }

  resolveDuplicateAt(): number {
    return this.lastExternalNavigationToastAt;
  }

  recordPromptShown(url: string, createdAt: number): void {
    this.lastExternalNavigationUrl = url;
    this.lastExternalNavigationToastAt = createdAt;
  }

  clearDuplicatePromptRecord(): void {
    this.lastExternalNavigationUrl = '';
    this.lastExternalNavigationToastAt = 0;
  }
}

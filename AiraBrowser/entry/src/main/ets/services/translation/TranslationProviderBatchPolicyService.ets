import { TranslationProviderConfig } from '../../common/models/BrowserModels';

export interface TranslationProviderBatchPolicy {
  batchCharBudget: number;
  batchItemGuard: number;
  initialNodeLimit: number;
  initialCharLimit: number;
}

export class TranslationProviderBatchPolicyService {
  resolvePolicy(provider: TranslationProviderConfig | undefined): TranslationProviderBatchPolicy {
    switch (provider?.templateId) {
      case 'aira_system':
        return this.buildPolicy(12000, 120, 220, 12000);
      case 'google_cloud':
        return this.buildPolicy(30000, 128, 220, 30000);
      case 'microsoft':
        return this.buildPolicy(45000, 100, 240, 45000);
      case 'deepl':
        return this.buildPolicy(45000, 120, 240, 45000);
      case 'tencent_cloud':
        return this.buildPolicy(5800, 120, 160, 12000);
      case 'volcano':
        return this.buildPolicy(4800, 16, 120, 12000);
      case 'alibaba_cloud':
        return this.buildPolicy(4500, 80, 120, 9000);
      case 'baidu':
        return this.buildPolicy(1800, 24, 120, 6000);
      case 'youdao':
        return this.buildPolicy(1800, 24, 120, 6000);
      case 'custom_http':
      default:
        return this.buildPolicy(4500, 40, 120, 6000);
    }
  }

  private buildPolicy(
    batchCharBudget: number,
    batchItemGuard: number,
    initialNodeLimit: number,
    initialCharLimit: number
  ): TranslationProviderBatchPolicy {
    return {
      batchCharBudget: batchCharBudget,
      batchItemGuard: batchItemGuard,
      initialNodeLimit: initialNodeLimit,
      initialCharLimit: initialCharLimit
    };
  }
}

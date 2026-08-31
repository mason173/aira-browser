import { statfs } from '@kit.CoreFileKit';
import {
  OfflinePageStorageQuotaCheckInput,
  OfflinePageStorageQuotaCheckResult
} from '../../common/models/OfflinePageModels';
import { OfflinePageFileStore } from '../../data/offline/OfflinePageFileStore';

const DEFAULT_SAFETY_MARGIN_BYTES: number = 20 * 1024 * 1024;
const DEFAULT_MANIFEST_BUDGET_BYTES: number = 64 * 1024;
const DEFAULT_PREVIEW_BUDGET_BYTES: number = 512 * 1024;

export class OfflinePageStorageQuotaService {
  private fileStore: OfflinePageFileStore;
  private safetyMarginBytes: number;

  constructor(
    fileStore: OfflinePageFileStore = new OfflinePageFileStore(),
    safetyMarginBytes: number = DEFAULT_SAFETY_MARGIN_BYTES
  ) {
    this.fileStore = fileStore;
    this.safetyMarginBytes = Math.max(0, Math.floor(safetyMarginBytes));
  }

  async check(input: OfflinePageStorageQuotaCheckInput): Promise<OfflinePageStorageQuotaCheckResult> {
    await this.fileStore.ensureRoot();
    const availableBytes = await statfs.getFreeSize(this.fileStore.getRootDir());
    const requiredBytes = this.estimateRequiredBytes(input);
    return {
      canWrite: availableBytes >= requiredBytes + this.safetyMarginBytes,
      availableBytes: Math.max(0, Math.floor(availableBytes)),
      requiredBytes: requiredBytes,
      safetyMarginBytes: this.safetyMarginBytes
    };
  }

  buildInput(htmlBytes: number, resourceBudgetBytes: number): OfflinePageStorageQuotaCheckInput {
    return {
      htmlBytes: Math.max(0, Math.floor(htmlBytes)),
      resourceBudgetBytes: Math.max(0, Math.floor(resourceBudgetBytes)),
      manifestBudgetBytes: DEFAULT_MANIFEST_BUDGET_BYTES,
      previewBudgetBytes: DEFAULT_PREVIEW_BUDGET_BYTES
    };
  }

  private estimateRequiredBytes(input: OfflinePageStorageQuotaCheckInput): number {
    const raw = input.htmlBytes + input.resourceBudgetBytes + input.manifestBudgetBytes + input.previewBudgetBytes;
    return Math.max(0, Math.floor(raw * 1.35));
  }
}

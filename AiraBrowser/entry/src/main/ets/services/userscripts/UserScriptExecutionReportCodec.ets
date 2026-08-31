import { UserScriptExecutionReport } from '../../features/userscripts/UserScriptRuntimeModels';
import { normalizeUserScriptJavaScriptResult } from './UserScriptJavaScriptResultCodec';

interface RawUserScriptExecutionReport {
  scriptId?: string;
  success?: boolean;
  errorMessage?: string;
  durationMs?: number;
}

export class UserScriptExecutionReportCodec {
  parse(rawResult: Object | string | number | boolean | undefined): UserScriptExecutionReport[] {
    const normalized = normalizeUserScriptJavaScriptResult(rawResult);
    if (normalized.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(normalized) as RawUserScriptExecutionReport[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return this.normalizeReports(parsed);
    } catch (_error) {
      return [];
    }
  }

  private normalizeReports(values: RawUserScriptExecutionReport[]): UserScriptExecutionReport[] {
    const results: UserScriptExecutionReport[] = [];
    values.forEach((value: RawUserScriptExecutionReport) => {
      if (typeof value.scriptId !== 'string' || value.scriptId.trim().length === 0 ||
        typeof value.success !== 'boolean' || typeof value.errorMessage !== 'string') {
        return;
      }
      results.push({
        scriptId: value.scriptId.trim(),
        success: value.success,
        errorMessage: value.errorMessage.trim(),
        durationMs: this.normalizeDuration(value.durationMs)
      });
    });
    return results;
  }

  private normalizeDuration(value: number | undefined): number | undefined {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
      return undefined;
    }
    return Math.min(Math.round(value), 24 * 60 * 60 * 1000);
  }

}

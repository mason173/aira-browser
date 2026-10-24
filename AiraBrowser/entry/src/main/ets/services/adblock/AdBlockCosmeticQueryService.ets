export interface AdBlockCosmeticQuery {
  classes: string[];
  ids: string[];
  includeScriptlets: boolean;
}

// The synchronous page bridge accepts only bounded selector candidates. Page identity is supplied
// separately by ArkWeb, never by the untrusted JSON payload.
export class AdBlockCosmeticQueryService {
  parse(payloadJson: string): AdBlockCosmeticQuery | undefined {
    if (typeof payloadJson !== 'string' || payloadJson.length > 128 * 1024) {
      return undefined;
    }
    try {
      const payload = JSON.parse(payloadJson) as AdBlockCosmeticQuery;
      if (payload === null || typeof payload !== 'object' ||
        typeof payload.includeScriptlets !== 'boolean') {
        return undefined;
      }
      const classes = this.normalizeCandidates(payload.classes);
      const ids = this.normalizeCandidates(payload.ids);
      if (classes === undefined || ids === undefined) {
        return undefined;
      }
      return { classes: classes, ids: ids, includeScriptlets: payload.includeScriptlets };
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeCandidates(values: string[]): string[] | undefined {
    if (!Array.isArray(values) || values.length > 128) {
      return undefined;
    }
    const result: string[] = [];
    const seen = new Set<string>();
    for (let index = 0; index < values.length; index += 1) {
      const value = values[index];
      if (typeof value !== 'string' || value.length === 0 || value.length > 256) {
        return undefined;
      }
      if (!seen.has(value)) {
        seen.add(value);
        result.push(value);
      }
    }
    return result;
  }
}

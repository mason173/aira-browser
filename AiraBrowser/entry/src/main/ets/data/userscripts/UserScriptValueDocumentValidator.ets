import { buffer } from '@kit.ArkTS';
import {
  USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION,
  UserScriptValueRecord,
  UserScriptValueStateDocument
} from '../../features/userscripts/UserScriptValueModels';

export interface UserScriptValueDocumentValidationResult {
  valid: boolean;
  stage: string;
  code: string;
}

export class UserScriptValueDocumentValidator {
  validate(
    document: UserScriptValueStateDocument,
    maximumValueBytes: number,
    requiredScriptId: string = ''
  ): UserScriptValueDocumentValidationResult {
    if (document === undefined || document === null ||
      document.schemaVersion !== USER_SCRIPT_VALUE_STATE_SCHEMA_VERSION ||
      !Number.isInteger(document.revision) || document.revision < 0 ||
      !Number.isFinite(document.updatedAt) || document.updatedAt < 0 ||
      !Array.isArray(document.values)) {
      return this.failure('schema', 'unsupported');
    }
    const normalizedRequiredScriptId = requiredScriptId.trim();
    const identities: string[] = [];
    for (let index = 0; index < document.values.length; index += 1) {
      const record = document.values[index];
      const recordFailure = this.validateRecord(
        record,
        normalizedRequiredScriptId,
        Math.max(1, maximumValueBytes)
      );
      if (!recordFailure.valid) {
        return recordFailure;
      }
      const identity = `${JSON.stringify(record.scriptId)}:${JSON.stringify(record.key)}`;
      if (identities.includes(identity)) {
        return this.failure('schema-record', 'duplicate');
      }
      identities.push(identity);
    }
    return {
      valid: true,
      stage: '',
      code: ''
    };
  }

  private validateRecord(
    record: UserScriptValueRecord,
    requiredScriptId: string,
    maximumValueBytes: number
  ): UserScriptValueDocumentValidationResult {
    if (record === undefined || record === null ||
      typeof record.scriptId !== 'string' || record.scriptId.trim().length === 0 ||
      record.scriptId !== record.scriptId.trim() ||
      (requiredScriptId.length > 0 && record.scriptId !== requiredScriptId) ||
      typeof record.key !== 'string' || record.key.trim().length === 0 ||
      record.key !== record.key.trim() ||
      typeof record.valueJson !== 'string' || record.valueJson.length === 0 ||
      !Number.isFinite(record.updatedAt) || record.updatedAt < 0) {
      return this.failure('schema-record', 'invalid');
    }
    if (buffer.from(record.valueJson, 'utf8').length > maximumValueBytes) {
      return this.failure('schema-record', 'value-too-large');
    }
    try {
      JSON.parse(record.valueJson);
    } catch (_error) {
      return this.failure('schema-record', 'invalid-json');
    }
    return {
      valid: true,
      stage: '',
      code: ''
    };
  }

  private failure(stage: string, code: string): UserScriptValueDocumentValidationResult {
    return {
      valid: false,
      stage: stage,
      code: code
    };
  }
}

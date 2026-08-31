import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

export type TranslationSecretStoreStatus = 'unavailable' | 'available';

export interface TranslationSecretStoreInfo {
  status: TranslationSecretStoreStatus;
  message: string;
}

const TRANSLATION_SECRET_STORE_PREFIX: string = 'aira.translation';

interface AssetStoreError {
  code?: number;
}

export class TranslationSecretStore {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  getInfo(): TranslationSecretStoreInfo {
    return {
      status: 'available',
      message: 'API 密钥将通过系统安全存储加密保存在本机。'
    };
  }

  isAvailable(): boolean {
    return this.getInfo().status === 'available';
  }

  async saveSecret(alias: string, value: string): Promise<void> {
    const normalizedAlias = this.normalizeAlias(alias);
    const normalizedValue = value.trim();
    if (normalizedAlias.length === 0 || normalizedValue.length === 0) {
      return;
    }
    await asset.add(this.buildSecretAttributes(normalizedAlias, normalizedValue));
  }

  async getSecret(alias: string): Promise<string> {
    const normalizedAlias = this.normalizeAlias(alias);
    if (normalizedAlias.length === 0) {
      return '';
    }
    const query = this.buildQueryAttributes(normalizedAlias, asset.ReturnType.ALL);
    try {
      const results = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const secret = results[0].get(asset.Tag.SECRET);
      return secret instanceof Uint8Array ? this.decode(secret) : '';
    } catch (error) {
      if (this.isNotFoundError(error)) {
        return '';
      }
      throw this.wrapAssetStoreError(error, '读取翻译密钥失败');
    }
  }

  async removeSecret(alias: string): Promise<void> {
    const normalizedAlias = this.normalizeAlias(alias);
    if (normalizedAlias.length === 0) {
      return;
    }
    try {
      await asset.remove(this.buildAliasQueryAttributes(normalizedAlias));
    } catch (error) {
      if (!this.isNotFoundError(error)) {
        throw this.wrapAssetStoreError(error, '删除翻译密钥失败');
      }
    }
  }

  private buildSecretAttributes(alias: string, value: string): asset.AssetMap {
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, this.encode(alias));
    attributes.set(asset.Tag.SECRET, this.encode(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.IS_PERSISTENT, true);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    attributes.set(asset.Tag.DATA_LABEL_NORMAL_LOCAL_1, this.encode(TRANSLATION_SECRET_STORE_PREFIX));
    return attributes;
  }

  private buildQueryAttributes(alias: string, returnType: asset.ReturnType): asset.AssetMap {
    const query = this.buildAliasQueryAttributes(alias);
    query.set(asset.Tag.RETURN_TYPE, returnType);
    query.set(asset.Tag.RETURN_LIMIT, 1);
    return query;
  }

  private buildAliasQueryAttributes(alias: string): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, this.encode(alias));
    return query;
  }

  private normalizeAlias(alias: string): string {
    return alias.trim();
  }

  private encode(value: string): Uint8Array {
    return this.encoder.encodeInto(value);
  }

  private decode(value: Uint8Array): string {
    return this.decoder.decodeToString(value);
  }

  private isNotFoundError(error: Error | Object): boolean {
    const code = (error as AssetStoreError).code;
    return code === asset.ErrorCode.NOT_FOUND;
  }

  private wrapAssetStoreError(error: Error | Object, fallbackMessage: string): Error {
    if (error instanceof Error && error.message.length > 0) {
      return new Error(error.message);
    }
    return new Error(fallbackMessage);
  }
}

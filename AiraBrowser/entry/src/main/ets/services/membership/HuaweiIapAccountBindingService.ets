import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

const IAP_ACCOUNT_BINDING_PREFIX: string = 'aira_iap_uid_v1:';

export class HuaweiIapAccountBindingService {
  private encoder: util.TextEncoder = util.TextEncoder.create('utf-8');

  buildApplicationUserName(uid: string): string {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      return '';
    }
    const md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: this.encoder.encodeInto(`${IAP_ACCOUNT_BINDING_PREFIX}${normalizedUid}`) });
    return this.toHex((md.digestSync() as cryptoFramework.DataBlob).data);
  }

  private toHex(bytes: Uint8Array): string {
    let result = '';
    for (let index = 0; index < bytes.length; index += 1) {
      result += bytes[index].toString(16).padStart(2, '0');
    }
    return result;
  }
}

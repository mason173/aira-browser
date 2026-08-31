import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';

export type BrowserQrScanStatus = 'success' | 'empty' | 'canceled' | 'failed';

export interface BrowserQrScanResult {
  status: BrowserQrScanStatus;
  value: string;
  message: string;
}

export class BrowserQrScanService {
  async scan(context: common.Context): Promise<BrowserQrScanResult> {
    try {
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableAlbum: true
      });
      const value = result.originalValue.trim();
      if (value.length <= 0) {
        return {
          status: 'empty',
          value: '',
          message: '没有识别到二维码内容。'
        };
      }
      return {
        status: 'success',
        value,
        message: ''
      };
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === 1000500002) {
        return {
          status: 'canceled',
          value: '',
          message: ''
        };
      }
      return {
        status: 'failed',
        value: '',
        message: this.resolveFailureMessage(businessError)
      };
    }
  }

  private resolveFailureMessage(error: BusinessError): string {
    if (error.message !== undefined && error.message.length > 0) {
      return `扫码失败：${error.message}`;
    }
    return '扫码失败，请稍后重试。';
  }
}

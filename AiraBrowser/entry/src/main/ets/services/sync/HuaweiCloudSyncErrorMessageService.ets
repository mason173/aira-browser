export interface HuaweiCloudSyncErrorMessage {
  userMessage: string;
  technicalMessage: string;
}

export type HuaweiCloudSyncErrorMessageContext = 'aira_cloud' | 'huawei_space';

export class HuaweiCloudSyncErrorMessageService {
  build(
    error: Object | string,
    context: HuaweiCloudSyncErrorMessageContext = 'aira_cloud'
  ): HuaweiCloudSyncErrorMessage {
    const technicalMessage = this.stringify(error);
    if (this.isCloudDatabasePermissionDenied(technicalMessage)) {
      return {
        userMessage: this.buildPermissionDeniedMessage(context),
        technicalMessage: technicalMessage
      };
    }
    if (this.isCloudDatabaseObjectMissing(technicalMessage)) {
      return {
        userMessage: this.buildObjectMissingMessage(context),
        technicalMessage: technicalMessage
      };
    }
    if (this.isHuaweiAccountAuthRejected(technicalMessage)) {
      return {
        userMessage: this.buildAuthRejectedMessage(),
        technicalMessage: technicalMessage
      };
    }
    if (this.isSerializedJsonDetail(technicalMessage)) {
      return {
        userMessage: '未知错误，请稍后重试。',
        technicalMessage: technicalMessage
      };
    }
    return {
      userMessage: technicalMessage.length > 0 ? technicalMessage : '未知错误',
      technicalMessage: technicalMessage.length > 0 ? technicalMessage : '未知错误'
    };
  }

  formatForDialog(
    error: Object | string,
    context: HuaweiCloudSyncErrorMessageContext = 'aira_cloud'
  ): string {
    const message = this.build(error, context);
    if (message.userMessage === message.technicalMessage) {
      return message.userMessage;
    }
    return `${message.userMessage}\n\n技术信息：${message.technicalMessage}`;
  }

  private isCloudDatabasePermissionDenied(message: string): boolean {
    const normalized = message.toLowerCase();
    return normalized.indexOf('2001015') >= 0 ||
      normalized.indexOf('permission denied') >= 0 ||
      normalized.indexOf('no operation permission') >= 0;
  }

  private isCloudDatabaseObjectMissing(message: string): boolean {
    return message.toLowerCase().indexOf('object type is not found') >= 0;
  }

  /**
   * Account Kit reports 401 as a parameter check failure, not an expired login.
   * A bare `{"code":401}` body and a BusinessError whose only field is code 401
   * both end up in the technical message after stringify.
   */
  private isHuaweiAccountAuthRejected(message: string): boolean {
    const normalized = message.toLowerCase().replace(/\s+/g, '');
    return normalized.indexOf('"code":401') >= 0 ||
      normalized.indexOf("'code':401") >= 0 ||
      normalized.indexOf('code=401') >= 0 ||
      normalized.indexOf('code:401') >= 0;
  }

  private buildAuthRejectedMessage(): string {
    return '华为账号登录参数校验失败。请确认已登录系统华为账号后重试。';
  }

  /**
   * A message that is only serialized JSON carries nothing a user can read;
   * show a generic message and keep the JSON as technical detail.
   */
  private isSerializedJsonDetail(message: string): boolean {
    const trimmed = message.trim();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  private buildPermissionDeniedMessage(context: HuaweiCloudSyncErrorMessageContext): string {
    if (context === 'huawei_space') {
      return '华为云空间结构化同步拒绝了这次请求。请确认已登录华为账号、系统云空间同步已开启、云侧容器和记录类型已部署，并且云空间容量可用。';
    }
    return 'Aira 云同步拒绝了这次请求。请确认华为账号仍有效，并稍后重试。';
  }

  private buildObjectMissingMessage(context: HuaweiCloudSyncErrorMessageContext): string {
    if (context === 'huawei_space') {
      return '华为云空间结构化同步的云侧记录类型未就绪。请确认 AppGallery Connect 已部署与本机 RDB 表一致的容器和 Record Types。';
    }
    return 'Aira 云同步返回了无法识别的数据结构，请稍后重试。';
  }

  private stringify(error: Object | string): string {
    if (typeof error === 'string') {
      return error.trim();
    }
    const detail = error as HuaweiCloudSyncErrorDetail;
    const codeText = detail.code !== undefined ? `${detail.code}` : '';
    const messageText = detail.message !== undefined ? `${detail.message}` : '';
    if (codeText.length > 0 && messageText.length > 0) {
      return `code=${codeText}, message=${messageText}`;
    }
    if (messageText.length > 0) {
      return messageText;
    }
    const err = error as Error;
    if (err.message !== undefined && err.message.length > 0) {
      return err.message;
    }
    return JSON.stringify(error);
  }
}

interface HuaweiCloudSyncErrorDetail {
  code?: number | string;
  message?: string;
}

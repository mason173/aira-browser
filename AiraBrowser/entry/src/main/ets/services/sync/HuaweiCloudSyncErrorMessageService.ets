import { HuaweiAccountOperationError, HuaweiAccountOperationStage } from './HuaweiAccountOperationError';

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
    if (this.isParameterCheckFailure(technicalMessage)) {
      return {
        userMessage: '本次操作参数检查失败。请保留错误详情并反馈。',
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

  formatForAccountOperation(error: Object, stage: HuaweiAccountOperationStage): string {
    const failure = HuaweiAccountOperationError.from(stage, error);
    let message = '登录未完成，请稍后重试。若仍失败，请反馈错误详情。';
    if (failure.stage === 'session-reset') {
      message = '重置本机登录状态失败，请反馈错误详情。';
    } else if (failure.stage === 'cached-user-read') {
      message = '读取本机登录状态失败，请反馈错误详情。';
    } else if (failure.stage === 'settings-save') {
      message = '保存本机登录信息失败，请反馈错误详情。';
    } else if (failure.code === 1001502001 || failure.code === '1001502001') {
      message = '请先登录系统华为账号，然后重试。';
    }
    return `${message}\n\n技术信息：${failure.technicalMessage()}`;
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
   * 401 is shared by native APIs, including Account Kit, storage and HUKS.
   * Without a failing boundary it cannot identify an account/login problem.
   */
  private isParameterCheckFailure(message: string): boolean {
    return /["']?code["']?\s*[:=]\s*401(?=\s*[,}\]]|\s*$)/i.test(message);
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

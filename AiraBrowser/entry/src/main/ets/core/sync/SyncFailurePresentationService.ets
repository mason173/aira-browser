import { HuaweiCloudSyncErrorMessageService } from '../../services/sync/HuaweiCloudSyncErrorMessageService';
import {
  AiraBookmarkSyncFailure,
  AiraBookmarkSyncFailureStage,
  AiraSyncRemoteKind
} from '../../common/models/AiraSyncModels';

const HUAWEI_SPACE_PERSONALIZATION_PROGRESS_CODE_ONE: string =
  '华为云空间个性化同步未完成（进度码 1）';
const HUAWEI_SPACE_PERSONALIZATION_SYSTEM_UPDATE_GUIDANCE: string =
  '请先将系统更新到最新版本并重启，然后再次同步。';

export interface SyncFailurePresentationInput {
  serviceName: string;
  operationName: string;
  errorMessage: string;
}

export interface SyncFailurePresentation {
  title: string;
  summary: string;
  diagnostics: string;
  details: SyncFailureDetailItem[];
}

export interface SyncFailureDetailItem {
  label: string;
  value: string;
}

export interface SyncBookmarkFailurePresentationInput {
  remoteKind: AiraSyncRemoteKind;
  operationName: string;
  failure?: AiraBookmarkSyncFailure;
}

interface SyncHttpFailure {
  provider: string;
  action: string;
  path: string;
  status: number;
}

export class SyncFailurePresentationService {
  private huaweiCloudErrorMessageService: HuaweiCloudSyncErrorMessageService = new HuaweiCloudSyncErrorMessageService();

  buildBookmarkFailureMessage(input: SyncBookmarkFailurePresentationInput): string {
    const failure = input.failure ?? {
      code: 'BKM-UNKNOWN-001',
      stage: 'unknown' as AiraBookmarkSyncFailureStage,
      safeDetail: '书签同步在未识别的阶段中断，请重试并向客服提供错误码。'
    };
    const operationName = input.operationName.trim().length > 0 ? input.operationName.trim() : '书签同步';
    const providerLabel = this.resolveBookmarkProviderLabel(input.remoteKind);
    return `${operationName}未完成（同步源：${providerLabel}；阶段：${this.resolveBookmarkStageLabel(failure.stage)}；` +
      `错误码：${failure.code}）。${failure.safeDetail}`;
  }

  buildHuaweiSpacePersonalizationSystemUpdateGuidance(errorMessage: string): string {
    return errorMessage.indexOf(HUAWEI_SPACE_PERSONALIZATION_PROGRESS_CODE_ONE) >= 0
      ? HUAWEI_SPACE_PERSONALIZATION_SYSTEM_UPDATE_GUIDANCE
      : '';
  }

  build(input: SyncFailurePresentationInput): SyncFailurePresentation {
    const rawMessage = input.errorMessage.trim();
    const parsedMessage = this.stripFailurePrefix(rawMessage);
    const huaweiCloudPermissionFailure = this.buildHuaweiCloudPermissionFailure(input, parsedMessage, rawMessage);
    if (huaweiCloudPermissionFailure !== null) {
      return huaweiCloudPermissionFailure;
    }
    const httpFailure = this.parseHttpFailure(parsedMessage);
    if (httpFailure !== null) {
      return this.buildHttpFailure(input, httpFailure, rawMessage);
    }

    const fallbackMessage = this.resolveFallbackSummary(parsedMessage, input);
    const diagnostics = this.buildDiagnostics(input, rawMessage.length > 0 ? rawMessage : '未知错误', '');
    return {
      title: '同步失败',
      summary: fallbackMessage,
      diagnostics: diagnostics,
      details: [
        { label: '同步方式', value: input.serviceName },
        { label: '操作', value: input.operationName }
      ]
    };
  }

  private buildHttpFailure(
    input: SyncFailurePresentationInput,
    failure: SyncHttpFailure,
    rawMessage: string
  ): SyncFailurePresentation {
    const explanation = this.resolveHttpExplanation(failure.status, failure.provider);
    const details: SyncFailureDetailItem[] = [
      { label: '同步方式', value: input.serviceName },
      { label: '操作', value: input.operationName },
      { label: '请求路径', value: failure.path.length > 0 ? failure.path : '未提供' },
      { label: 'HTTP 状态码', value: `${failure.status}` }
    ];
    const technicalDetails = this.buildTechnicalDetails(details);

    return {
      title: '同步失败',
      summary: explanation,
      diagnostics: this.buildDiagnostics(input, rawMessage, technicalDetails),
      details: details
    };
  }

  private parseHttpFailure(message: string): SyncHttpFailure | null {
    const requestFailure = /^(WebDAV|云同步) 请求失败：(.+)，HTTP ([0-9]+)$/.exec(message);
    if (requestFailure !== null) {
      return {
        provider: requestFailure[1],
        action: '请求失败',
        path: requestFailure[2],
        status: Number(requestFailure[3])
      };
    }

    const connectionFailure = /^(WebDAV|云同步) 连接失败：HTTP ([0-9]+)$/.exec(message);
    if (connectionFailure !== null) {
      return {
        provider: connectionFailure[1],
        action: '连接失败',
        path: '',
        status: Number(connectionFailure[2])
      };
    }

    const directoryFailure = /^(WebDAV) 创建目录失败：(.+)，HTTP ([0-9]+)$/.exec(message);
    if (directoryFailure !== null) {
      return {
        provider: directoryFailure[1],
        action: '创建目录失败',
        path: directoryFailure[2],
        status: Number(directoryFailure[3])
      };
    }

    return null;
  }

  private stripFailurePrefix(message: string): string {
    let current = message.trim();
    while (true) {
      const parts = /^(.*?)(?:：|:)\s*(.+)$/.exec(current);
      if (parts === null) {
        return current;
      }
      const prefix = parts[1].trim();
      const suffix = parts[2].trim();
      if (suffix.length === 0 || !this.isLikelyFailurePrefix(prefix)) {
        return current;
      }
      current = suffix;
    }
  }

  private isLikelyFailurePrefix(prefix: string): boolean {
    return prefix.indexOf('失败') >= 0 ||
      prefix.indexOf('错误') >= 0 ||
      prefix.indexOf('异常') >= 0 ||
      prefix.indexOf('超时') >= 0 ||
      prefix.indexOf('无效') >= 0 ||
      prefix.indexOf('未能') >= 0 ||
      prefix.indexOf('无法') >= 0;
  }

  private resolveFallbackSummary(message: string, input: SyncFailurePresentationInput): string {
    const normalized = message.trim();
    if (normalized.length === 0) {
      return '未知错误';
    }
    const lowerMessage = normalized.toLowerCase();
    if (lowerMessage.indexOf('operation timeout') >= 0 ||
      lowerMessage.indexOf('timeout') >= 0 ||
      lowerMessage.indexOf('timed out') >= 0) {
      return this.resolveTimeoutSummary(input);
    }
    if (lowerMessage.indexOf('socket hang up') >= 0 ||
      lowerMessage.indexOf('connection reset') >= 0 ||
      lowerMessage.indexOf('connection aborted') >= 0) {
      return `${input.serviceName}连接中断了，可能是网络波动或本次书签数据较大，请稍后重试。`;
    }
    const firstLine = normalized.split('\n')[0].trim();
    return firstLine.length > 0 ? firstLine : '未知错误';
  }

  private resolveTimeoutSummary(input: SyncFailurePresentationInput): string {
    if (this.isCloudBookmarkSyncService(input.serviceName)) {
      if (input.operationName.indexOf('检查') >= 0) {
        return '云端书签数据读取耗时较长，本次检查已超时。书签很多时请保持网络稳定后再试。';
      }
      return 'Aira 云同步耗时较长，本次操作已超时。请保持应用在前台并稍后重试。';
    }
    return `${input.serviceName}响应时间过长，本次${input.operationName}没有完成。请检查网络后再试。`;
  }

  private resolveHttpExplanation(status: number, provider: string): string {
    if (status === 401 || status === 403) {
      return `${provider} 拒绝了这次同步请求，请检查账号、密码或远端目录权限。`;
    }
    if (status === 404) {
      return `${provider} 没有找到同步文件，可能是首次同步或远端目录已变更。`;
    }
    if (status === 409) {
      return `${provider} 远端目录状态冲突，请检查同步目录结构后重试。`;
    }
    if (status === 423) {
      return `${provider} 远端文件暂时被锁定，可能有其他设备正在同步。`;
    }
    if (status === 429) {
      return `${provider} 请求过于频繁，服务商可能触发了限流。`;
    }
    if (status === 500) {
      return `${provider} 服务端出现内部异常，暂时无法完成同步。`;
    }
    if (status === 502 || status === 504) {
      return `${provider} 网关或网络中转异常，请稍后再试。`;
    }
    if (status === 503) {
      return `${provider} 服务暂时不可用，可能是限流、维护或服务器繁忙，请稍后再试。`;
    }
    return `${provider} 返回了 HTTP ${status}，这次同步请求没有成功完成。`;
  }

  private buildHuaweiCloudPermissionFailure(
    input: SyncFailurePresentationInput,
    parsedMessage: string,
    rawMessage: string
  ): SyncFailurePresentation | null {
    if (!this.isCloudBookmarkSyncService(input.serviceName)) {
      return null;
    }
    const message = this.huaweiCloudErrorMessageService.build(
      parsedMessage,
      this.resolveHuaweiCloudErrorContext(input.serviceName)
    );
    if (message.userMessage === message.technicalMessage) {
      return null;
    }
    const details: SyncFailureDetailItem[] = [
      { label: '同步方式', value: input.serviceName },
      { label: '操作', value: input.operationName },
      { label: '技术信息', value: message.technicalMessage }
    ];
    return {
      title: '同步失败',
      summary: message.userMessage,
      diagnostics: this.buildDiagnostics(input, rawMessage.length > 0 ? rawMessage : message.technicalMessage,
        this.buildTechnicalDetails(details)),
      details: details
    };
  }

  private isCloudBookmarkSyncService(serviceName: string): boolean {
    return serviceName.indexOf('Aira 云同步') >= 0 ||
      serviceName.indexOf('云同步') >= 0 ||
      serviceName.indexOf('华为') >= 0 ||
      serviceName.indexOf('Cloud') >= 0;
  }

  private resolveBookmarkStageLabel(stage: AiraBookmarkSyncFailureStage): string {
    if (stage === 'authentication') {
      return '账号与配置校验';
    }
    if (stage === 'network') {
      return '网络请求';
    }
    if (stage === 'remote_read_validation') {
      return '读取与校验云端快照';
    }
    if (stage === 'local_snapshot') {
      return '生成本机快照';
    }
    if (stage === 'merge') {
      return '合并书签';
    }
    if (stage === 'remote_commit') {
      return '提交云端快照';
    }
    if (stage === 'remote_confirmation') {
      return '确认云端提交';
    }
    if (stage === 'local_apply') {
      return '写入与校验本机书签';
    }
    return '未识别阶段';
  }

  private resolveBookmarkProviderLabel(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      return 'Aira 云';
    }
    if (remoteKind === 'huawei_space') {
      return '华为云空间';
    }
    if (remoteKind === 'webdav') {
      return 'WebDAV';
    }
    return '未配置';
  }

  private resolveHuaweiCloudErrorContext(serviceName: string): 'aira_cloud' | 'huawei_space' {
    return serviceName.indexOf('华为云空间') >= 0 ? 'huawei_space' : 'aira_cloud';
  }

  private buildDiagnostics(input: SyncFailurePresentationInput, rawMessage: string, technicalDetails: string): string {
    const lines: string[] = [
      `同步方式：${input.serviceName}`,
      `操作：${input.operationName}`,
      `原始错误：${rawMessage}`
    ];
    if (technicalDetails.length > 0) {
      lines.push('');
      lines.push(technicalDetails);
    }
    return lines.join('\n');
  }

  private buildTechnicalDetails(details: SyncFailureDetailItem[]): string {
    const lines: string[] = ['技术详情'];
    for (let index = 0; index < details.length; index += 1) {
      const detail = details[index];
      lines.push(`${detail.label}：${detail.value}`);
    }
    return lines.join('\n');
  }
}

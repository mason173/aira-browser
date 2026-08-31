import { InstalledUserScriptState } from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptRuntimeStateRecord } from '../../features/userscripts/UserScriptRuntimeStateModels';
import { UserScriptValueRecord } from '../../features/userscripts/UserScriptValueModels';
import { UserScriptMatchService } from '../../services/userscripts/UserScriptMatchService';

export interface UserScriptDetailRowView {
  label: string;
  value: string;
}

export interface UserScriptDetailActionView {
  editEnabled: boolean;
  deleteEnabled: boolean;
}

export interface UserScriptDetailState {
  title: string;
  subtitle: string;
  enabled: boolean;
  found: boolean;
  statusTitle: string;
  statusDescription: string;
  metadataRows: UserScriptDetailRowView[];
  runtimeRows: UserScriptDetailRowView[];
  storageRows: UserScriptDetailRowView[];
  sourcePreview: string;
  actions: UserScriptDetailActionView;
}

export class UserScriptDetailViewModel {
  private matchService: UserScriptMatchService = new UserScriptMatchService();

  buildState(
    script: InstalledUserScriptState | undefined,
    runtimeState: UserScriptRuntimeStateRecord | undefined,
    values: UserScriptValueRecord[]
  ): UserScriptDetailState {
    if (script === undefined) {
      return {
        title: '脚本不存在',
        subtitle: '可能已被删除',
        enabled: false,
        found: false,
        statusTitle: '无法查看',
        statusDescription: '返回脚本列表后刷新状态。',
        metadataRows: [],
        runtimeRows: [],
        storageRows: [],
        sourcePreview: '',
        actions: {
          editEnabled: false,
          deleteEnabled: false
        }
      };
    }
    return {
      title: script.name,
      subtitle: `${this.matchService.summarizeScope(script)} · ${script.version}`,
      enabled: script.enabled,
      found: true,
      statusTitle: script.enabled ? '已启用' : '已关闭',
      statusDescription: this.buildStatusDescription(script, runtimeState),
      metadataRows: this.buildMetadataRows(script),
      runtimeRows: this.buildRuntimeRows(runtimeState),
      storageRows: this.buildStorageRows(values),
      sourcePreview: this.buildSourcePreview(script.source),
      actions: {
        editEnabled: true,
        deleteEnabled: true
      }
    };
  }

  private buildStatusDescription(
    script: InstalledUserScriptState,
    runtimeState: UserScriptRuntimeStateRecord | undefined
  ): string {
    if (!script.enabled) {
      return '脚本关闭后不会在匹配网页运行。';
    }
    if (runtimeState === undefined || runtimeState.status === 'never_run') {
      return '尚未记录运行结果，打开匹配网页后会更新。';
    }
    if (runtimeState.status === 'skipped') {
      return `最近一次注入被跳过：${this.formatRuntimeReason(runtimeState.lastSkipReason)}`;
    }
    if (runtimeState.lastBridgeRejectReason.length > 0) {
      return `最近一次 native bridge 被拒绝：${this.formatRuntimeReason(runtimeState.lastBridgeRejectReason)}`;
    }
    if (runtimeState.status === 'failed') {
      return runtimeState.lastErrorMessage.length > 0 ? runtimeState.lastErrorMessage : '最近一次运行失败。';
    }
    if (runtimeState.status === 'success') {
      return `最近运行成功，累计运行 ${runtimeState.runCount} 次。`;
    }
    return '最近一次注入被跳过。';
  }

  private buildMetadataRows(script: InstalledUserScriptState): UserScriptDetailRowView[] {
    return [
      { label: '名称', value: script.name },
      { label: '版本', value: script.version },
      { label: '命名空间', value: script.namespace.length > 0 ? script.namespace : '未声明' },
      { label: '描述', value: script.description.length > 0 ? script.description : '未声明' },
      { label: '作用范围', value: this.matchService.summarizeScope(script) },
      { label: '排除规则', value: script.excludes.length > 0 ? script.excludes.join('\n') : '无' },
      { label: '授权', value: script.grants.join(', ') },
      { label: '运行时机', value: script.runAt },
      { label: '来源', value: this.buildSourceUrl(script) }
    ];
  }

  private buildRuntimeRows(runtimeState: UserScriptRuntimeStateRecord | undefined): UserScriptDetailRowView[] {
    if (runtimeState === undefined || runtimeState.status === 'never_run') {
      return [
        { label: '状态', value: '尚未运行' },
        { label: '最近匹配 URL', value: '无' },
        { label: '最近注入时机', value: '无' },
        { label: '最近 bridge 拒绝', value: '无' }
      ];
    }
    return [
      { label: '状态', value: this.formatRuntimeStatus(runtimeState.status) },
      { label: '最近匹配 URL', value: runtimeState.lastUrl.length > 0 ? runtimeState.lastUrl : '无' },
      { label: '最近注入时机', value: this.formatInjectionPhase(runtimeState.lastInjectionPhase) },
      { label: '运行次数', value: `${runtimeState.runCount}` },
      { label: '失败次数', value: `${runtimeState.failureCount}` },
      { label: '最近运行', value: this.formatTime(runtimeState.lastRunAt) },
      { label: '最近成功', value: this.formatTime(runtimeState.lastSuccessAt) },
      { label: '最近失败', value: this.formatTime(runtimeState.lastFailureAt) },
      { label: '最近跳过原因', value: this.formatRuntimeReason(runtimeState.lastSkipReason) },
      {
        label: '最近 bridge 拒绝',
        value: this.buildBridgeRejectValue(runtimeState.lastBridgeCapability, runtimeState.lastBridgeRejectReason)
      },
      { label: '错误信息', value: runtimeState.lastErrorMessage.length > 0 ? runtimeState.lastErrorMessage : '无' }
    ];
  }

  private buildStorageRows(values: UserScriptValueRecord[]): UserScriptDetailRowView[] {
    return [
      { label: '本地值数量', value: `${values.length}` },
      { label: '键名', value: values.length > 0 ? values.map((record: UserScriptValueRecord) => record.key).join(', ') : '无' }
    ];
  }

  private buildSourcePreview(source: string): string {
    const trimmed = source.trim();
    if (trimmed.length <= 1200) {
      return trimmed;
    }
    return `${trimmed.substring(0, 1200)}\n...`;
  }

  private buildSourceUrl(script: InstalledUserScriptState): string {
    if (script.sourceUrl.length > 0) {
      return script.sourceUrl;
    }
    if (script.downloadUrl.length > 0) {
      return script.downloadUrl;
    }
    if (script.updateUrl.length > 0) {
      return script.updateUrl;
    }
    return script.installSource;
  }

  private formatRuntimeStatus(status: string): string {
    if (status === 'success') {
      return '最近成功';
    }
    if (status === 'failed') {
      return '最近失败';
    }
    if (status === 'skipped') {
      return '最近跳过';
    }
    return '尚未运行';
  }

  private formatInjectionPhase(value: string): string {
    if (value === 'document-start') {
      return 'document-start';
    }
    if (value === 'document-end') {
      return 'document-end';
    }
    if (value === 'main-menu' || value === 'tool-menu' || value === 'context-menu') {
      return value;
    }
    return '未知';
  }

  private buildBridgeRejectValue(capability: string, reason: string): string {
    const normalizedReason = this.formatRuntimeReason(reason);
    if (normalizedReason === '无') {
      return '无';
    }
    if (capability.trim().length === 0) {
      return normalizedReason;
    }
    return `${capability.trim()} · ${normalizedReason}`;
  }

  private formatRuntimeReason(reason: string): string {
    const normalized = reason.trim();
    if (normalized.length === 0) {
      return '无';
    }
    const labels: Record<string, string> = {
      'private_mode': 'private_mode · 无痕/临时会话不注入脚本',
      'missing_controller': 'missing_controller · Web 控制器不可用',
      'grant-denied': 'grant-denied · 脚本未获得该 GM 能力授权',
      'url-not-matched': 'url-not-matched · 当前网页不再匹配脚本规则',
      'invalid-bridge-token': 'invalid-bridge-token · native bridge token 无效',
      'missing-bridge-auth': 'missing-bridge-auth · bridge 鉴权参数缺失',
      'missing-page-url': 'missing-page-url · 当前网页地址不可用',
      'capability-mismatch': 'capability-mismatch · bridge 能力名不匹配',
      'unsupported-capability': 'unsupported-capability · native bridge 不支持该能力',
      'script-disabled': 'script-disabled · 脚本当前已关闭'
    };
    return labels[normalized] ?? normalized;
  }

  private formatTime(value: number): string {
    if (value <= 0) {
      return '无';
    }
    return new Date(value).toLocaleString();
  }
}

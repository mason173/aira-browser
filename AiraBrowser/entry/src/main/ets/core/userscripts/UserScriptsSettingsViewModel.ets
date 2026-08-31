import {
  InstalledUserScriptState,
  UserScriptPackageCandidate
} from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptValueManagementProjection } from '../../features/userscripts/UserScriptValueModels';
import { UserScriptCapabilityContractService } from '../../services/userscripts/UserScriptCapabilityContractService';
import { UserScriptMatchService } from '../../services/userscripts/UserScriptMatchService';

export interface UserScriptRowView {
  id: string;
  title: string;
  iconUrl: string;
  enabled: boolean;
  canUpdate: boolean;
}

export interface UserScriptsSettingsState {
  autoUpdateEnabled: boolean;
  rows: UserScriptRowView[];
  hasScripts: boolean;
}

export interface UserScriptValueRecoveryViewState {
  visible: boolean;
  title: string;
  message: string;
}

export interface UserScriptInstallPreviewState {
  name: string;
  iconUrl: string;
  version: string;
  description: string;
  scope: string;
  scopeDetail: string;
  grants: string;
  sourceLabel: string;
  updateLabel: string;
  runAtLabel: string;
  warnings: string[];
  errorMessage: string;
  saveEnabled: boolean;
}

export class UserScriptsSettingsViewModel {
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private matchService: UserScriptMatchService = new UserScriptMatchService();

  buildState(
    scripts: InstalledUserScriptState[],
    autoUpdateEnabled: boolean = false
  ): UserScriptsSettingsState {
    const rows = scripts.map((script: InstalledUserScriptState): UserScriptRowView => {
      return {
        id: script.id,
        title: script.name,
        iconUrl: script.iconUrl,
        enabled: script.enabled,
        canUpdate: script.updateUrl.length > 0 || script.downloadUrl.length > 0
      };
    });
    return {
      autoUpdateEnabled: autoUpdateEnabled,
      rows: rows,
      hasScripts: scripts.length > 0
    };
  }

  buildValueRecoveryState(projection: UserScriptValueManagementProjection): UserScriptValueRecoveryViewState {
    const blocked = projection.readiness.status === 'blocked';
    if (!blocked && !projection.incident.active &&
      !projection.migration.unreadableLegacySnapshot &&
      projection.migration.skippedScriptCount <= 0 &&
      projection.migration.skippedUnattributedRecordCount <= 0) {
      return {
        visible: false,
        title: '',
        message: ''
      };
    }
    if (!blocked && !projection.incident.active) {
      if (projection.migration.unreadableLegacySnapshot) {
        return {
          visible: true,
          title: '部分旧用户脚本数据未迁移',
          message: '旧数据文件无法解析，已保留原文件；用户脚本仍可正常运行。'
        };
      }
      const scriptMessage = projection.migration.skippedScriptCount > 0 ?
        `${projection.migration.skippedScriptCount} 个脚本的旧数据未能迁移。` : '';
      const recordMessage = projection.migration.skippedUnattributedRecordCount > 0 ?
        `${projection.migration.skippedUnattributedRecordCount} 条旧记录无法识别所属脚本。` : '';
      return {
        visible: true,
        title: '部分旧用户脚本数据未迁移',
        message: `${scriptMessage}${recordMessage}旧文件已保留，其他脚本可正常运行。`
      };
    }
    const stage = projection.incident.stage.length > 0 ?
      projection.incident.stage : projection.readiness.failureStage;
    const code = projection.incident.code.length > 0 ?
      projection.incident.code : projection.readiness.failureCode;
    const diagnostic = stage.length > 0 || code.length > 0 ? `（${stage || 'unknown'}/${code || 'unknown'}）` : '';
    return {
      visible: true,
      title: blocked ? '用户脚本数据不可用' : '用户脚本数据暂未保存',
      message: blocked ?
        `已暂停脚本运行；重新打开 Aira 后会自动重试。${diagnostic}` :
        `仍使用上个已提交版本；脚本下次写入时会自动重试。${diagnostic}`
    };
  }

  buildInstallPreview(
    candidate: UserScriptPackageCandidate | undefined,
    warnings: string[],
    errorMessage: string
  ): UserScriptInstallPreviewState {
    if (candidate === undefined) {
      return {
        name: '',
        iconUrl: '',
        version: '',
        description: '',
        scope: '',
        scopeDetail: '',
        grants: '',
        sourceLabel: '',
        updateLabel: '',
        runAtLabel: '',
        warnings: warnings,
        errorMessage: errorMessage,
        saveEnabled: false
      };
    }
    return {
      name: candidate.name,
      iconUrl: candidate.iconUrl,
      version: candidate.version,
      description: candidate.description,
      scope: this.matchService.summarizeScope(candidate),
      scopeDetail: this.summarizeScopeDetail(candidate),
      grants: this.capabilityContract.summarizeGrants(candidate.grants),
      sourceLabel: this.summarizeInstallSource(candidate),
      updateLabel: this.summarizeUpdateInfo(candidate),
      runAtLabel: this.summarizeRunAt(candidate.runAt),
      warnings: warnings,
      errorMessage: errorMessage,
      saveEnabled: errorMessage.length === 0
    };
  }

  private summarizeScopeDetail(record: InstalledUserScriptState | UserScriptPackageCandidate): string {
    const rules: string[] = [];
    record.matches.forEach((rule: string) => rules.push(`@match ${rule}`));
    record.includes.forEach((rule: string) => rules.push(`@include ${rule}`));
    record.excludes.forEach((rule: string) => rules.push(`@exclude ${rule}`));
    if (rules.length <= 0) {
      return '';
    }
    const previewRules = rules.slice(0, 3);
    const suffix = rules.length > previewRules.length ? ` 等 ${rules.length} 条规则` : `${rules.length} 条规则`;
    return `${previewRules.join('\n')}\n${suffix}`;
  }

  private summarizeInstallSource(record: InstalledUserScriptState | UserScriptPackageCandidate): string {
    if (record.installSource === 'url') {
      return 'URL';
    }
    if (record.installSource === 'file') {
      return '本地文件';
    }
    if (record.installSource === 'gallery') {
      return '脚本市场';
    }
    return '手动输入';
  }

  private summarizeUpdateInfo(record: InstalledUserScriptState | UserScriptPackageCandidate): string {
    if (record.updateUrl.length > 0 && record.downloadUrl.length > 0) {
      return '支持检查更新和下载更新';
    }
    if (record.updateUrl.length > 0) {
      return '支持检查更新';
    }
    if (record.downloadUrl.length > 0) {
      return '支持下载更新';
    }
    return '未提供更新地址';
  }

  private summarizeRunAt(runAt: string): string {
    if (runAt === 'document-start') {
      return '页面开始加载时';
    }
    if (runAt === 'document-idle') {
      return '页面空闲后';
    }
    if (runAt === 'main-menu') {
      return '主菜单触发';
    }
    if (runAt === 'tool-menu') {
      return '工具菜单触发';
    }
    if (runAt === 'context-menu') {
      return '上下文菜单触发';
    }
    return '页面加载完成后';
  }

}

export type SyncWebdavProviderRole = 'active' | 'additional_backup' | 'inactive';

export type SyncWebdavConfigLifecycleStage =
  | 'empty'
  | 'configured_off'
  | 'enabling'
  | 'syncing'
  | 'enabled'
  | 'disabling';

export interface SyncWebdavConfigLifecycleInput {
  providerRole: SyncWebdavProviderRole;
  bookmarkDomainEnabled: boolean;
  formEndpoint: string;
  formUsername: string;
  formPassword: string;
  operation: SyncWebdavConfigLifecycleStage | '';
  targetRole: 'active' | 'additional_backup';
}

export interface SyncWebdavConfigViewState {
  stage: SyncWebdavConfigLifecycleStage;
  isConfigured: boolean;
  isEnabled: boolean;
  isBusy: boolean;
  primaryActionTitle: string;
  primaryActionEnabled: boolean;
  showDisableAction: boolean;
  disableActionEnabled: boolean;
  statusText: string;
  renderKey: string;
}

export class SyncWebdavConfigViewModel {
  resolveTargetRole(params: Record<string, string | undefined> | undefined): 'active' | 'additional_backup' {
    return params?.syncTargetRole === 'additional_backup' ? 'additional_backup' : 'active';
  }

  resolvePageTitle(role: 'active' | 'additional_backup'): string {
    return role === 'additional_backup' ? 'WebDAV 附加备份' : 'WebDAV 同步';
  }

  resolveDisplayedPrimaryActionTitle(
    role: 'active' | 'additional_backup',
    defaultTitle: string,
    isBusy: boolean
  ): string {
    if (role === 'additional_backup') {
      return isBusy ? '正在开启 WebDAV 附加备份' : '保存并开启为附加备份';
    }
    return defaultTitle;
  }

  shouldActivateOnSave(role: 'active' | 'additional_backup'): boolean {
    return role === 'active';
  }

  buildState(input: SyncWebdavConfigLifecycleInput): SyncWebdavConfigViewState {
    const providerRole = input.providerRole;
    const bookmarkDomainEnabled = providerRole === 'active' && input.bookmarkDomainEnabled;
    const isEnabled = input.targetRole === 'additional_backup'
      ? providerRole === 'additional_backup'
      : bookmarkDomainEnabled;
    const isConfigured = this.hasConfig(input.formEndpoint, input.formUsername, input.formPassword);
    const stage = this.resolveStage(input.operation, isEnabled, isConfigured);
    return {
      stage: stage,
      isConfigured: isConfigured,
      isEnabled: isEnabled,
      isBusy: this.isBusyStage(stage),
      primaryActionTitle: this.resolvePrimaryActionTitle(stage, input.targetRole, providerRole),
      primaryActionEnabled: !this.isBusyStage(stage),
      showDisableAction: input.targetRole === 'active' && bookmarkDomainEnabled,
      disableActionEnabled: !this.isBusyStage(stage),
      statusText: this.resolveStatusText(stage, providerRole, bookmarkDomainEnabled),
      renderKey: this.buildRenderKey(stage, isEnabled, isConfigured, providerRole)
    };
  }

  private resolveStage(
    operation: SyncWebdavConfigLifecycleStage | '',
    isEnabled: boolean,
    isConfigured: boolean
  ): SyncWebdavConfigLifecycleStage {
    if (operation === 'enabling' || operation === 'syncing' || operation === 'disabling') {
      return operation;
    }
    if (isEnabled) {
      return 'enabled';
    }
    return isConfigured ? 'configured_off' : 'empty';
  }

  private resolvePrimaryActionTitle(
    stage: SyncWebdavConfigLifecycleStage,
    targetRole: 'active' | 'additional_backup',
    providerRole: SyncWebdavProviderRole
  ): string {
    if (stage === 'enabled') {
      return targetRole === 'additional_backup' ? '附加备份已开启' : '立即同步';
    }
    if (stage === 'enabling') {
      return '正在启用 WebDAV 同步';
    }
    if (stage === 'syncing') {
      return '正在同步 WebDAV';
    }
    if (stage === 'disabling') {
      return '正在关闭 WebDAV 同步';
    }
    if (targetRole === 'additional_backup') {
      return '开启 WebDAV 附加备份';
    }
    return providerRole === 'additional_backup' ? '设为当前同步方式并开启' : '启用 WebDAV 书签同步';
  }

  private resolveStatusText(
    stage: SyncWebdavConfigLifecycleStage,
    providerRole: SyncWebdavProviderRole,
    bookmarkDomainEnabled: boolean
  ): string {
    if (stage === 'enabled') {
      return providerRole === 'additional_backup' ? '附加备份已开启' : '书签同步已开启';
    }
    if (stage === 'enabling') {
      return '正在开启';
    }
    if (stage === 'syncing') {
      return '正在同步';
    }
    if (stage === 'disabling') {
      return '正在关闭';
    }
    if (stage === 'configured_off') {
      if (providerRole === 'additional_backup') {
        return '当前为附加备份位置';
      }
      if (providerRole === 'active' && !bookmarkDomainEnabled) {
        return '当前同步方式，书签同步未开启';
      }
      return '已保存，未开启';
    }
    return '未配置';
  }

  private isBusyStage(stage: SyncWebdavConfigLifecycleStage): boolean {
    return stage === 'enabling' || stage === 'syncing' || stage === 'disabling';
  }

  private hasConfig(endpoint: string, username: string, password: string): boolean {
    return endpoint.trim().length > 0 && username.trim().length > 0 && password.length > 0;
  }

  private buildRenderKey(
    stage: SyncWebdavConfigLifecycleStage,
    isEnabled: boolean,
    isConfigured: boolean,
    providerRole: SyncWebdavProviderRole
  ): string {
    return `${stage}|${isEnabled ? 'on' : 'off'}|${isConfigured ? 'configured' : 'empty'}|${providerRole}`;
  }
}

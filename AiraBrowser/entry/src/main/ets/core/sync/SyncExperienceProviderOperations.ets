import {
  AIRA_FEATURE_CLOUD_SYNC,
  AIRA_FEATURE_WEBDAV_SYNC
} from '../../common/constants/MembershipFeatureKeys';
import { EntitlementDecision } from '../../common/models/MembershipModels';
import {
  AiraBookmarkMergeSyncResult,
  AiraBookmarkSyncFailure,
  AiraSyncProviderKind,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  AiraSyncWebdavConfig,
  AiraSyncWriteStateResult,
  isAiraBookmarkProviderTransition,
  resolveAiraPersonalServerConfig
} from '../../common/models/AiraSyncModels';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { AiraBookmarkTargetMergeIntent, SyncService } from '../../services/sync/SyncService';
import { PersonalizationSyncService } from '../../services/sync/PersonalizationSyncService';
import { SyncExperienceProviderActivation } from './SyncExperienceProviderActivation';
import { SyncActivationResult } from './SyncActivationModels';
import { SyncExperienceAutomaticRuntime } from './SyncExperienceAutomaticRuntime';
import { SyncRemoteStatusCoordinator } from './SyncRemoteStatusCoordinator';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type SyncExperienceProviderOutcomeType =
  | 'no-action'
  | 'configuration-required'
  | 'membership-required'
  | 'provider-selection-confirmation-required'
  | 'provider-selected'
  | 'provider-selection-blocked'
  | 'additional-backup-enabled'
  | 'additional-backup-disabled'
  | 'bookmark-domain-enabled'
  | 'bookmark-domain-disabled'
  | 'bookmark-domain-blocked'
  | 'failed';

export interface SyncExperienceProviderOutcome {
  type: SyncExperienceProviderOutcomeType;
  remoteKind: AiraSyncProviderKind;
  providerLabel: string;
  title: string;
  message: string;
  membershipDecision?: EntitlementDecision;
  bookmarkResult?: AiraBookmarkMergeSyncResult;
  bookmarkFailure?: AiraBookmarkSyncFailure;
}

export interface SyncExperienceProviderDomains {
  bookmarks: boolean;
  personalization: boolean;
  history?: boolean;
}

export type SyncWebdavTargetRole = 'active' | 'additional_backup';
export type SyncWebdavActivationOutcomeType =
  | 'configuration-saved'
  | 'activation-completed'
  | 'activation-blocked'
  | 'additional-backup-enabled'
  | 'deactivated'
  | 'signed-in'
  | 'failed';

export interface SyncWebdavActivationOutcome {
  type: SyncWebdavActivationOutcomeType;
  title: string;
  message: string;
  membershipDecision?: EntitlementDecision;
}

export interface SyncWebdavConfigurationParams {
  endpoint: string;
  username: string;
  password: string;
}

export class SyncExperienceProviderOperations {
  private syncService: SyncService;
  private personalizationSyncService: PersonalizationSyncService;
  private membershipFeature: MembershipFeature;
  private activation: SyncExperienceProviderActivation;
  private automaticRuntime: SyncExperienceAutomaticRuntime;
  private remoteStatusCoordinator: SyncRemoteStatusCoordinator;

  constructor(
    syncService: SyncService,
    personalizationSyncService: PersonalizationSyncService,
    membershipFeature: MembershipFeature,
    activation: SyncExperienceProviderActivation,
    automaticRuntime: SyncExperienceAutomaticRuntime,
    remoteStatusCoordinator: SyncRemoteStatusCoordinator
  ) {
    this.syncService = syncService;
    this.personalizationSyncService = personalizationSyncService;
    this.membershipFeature = membershipFeature;
    this.activation = activation;
    this.automaticRuntime = automaticRuntime;
    this.remoteStatusCoordinator = remoteStatusCoordinator;
  }

  signInHuaweiAccount(): Promise<SyncActivationResult> {
    return this.runProviderTransition(async (): Promise<SyncActivationResult> => {
      return this.activation.signInHuaweiAccountOnly();
    });
  }

  refreshHuaweiAccountIdentity(): Promise<SyncActivationResult> {
    return this.runProviderTransition(async (): Promise<SyncActivationResult> => {
      return this.activation.refreshHuaweiAccountIdentity();
    });
  }

  clearHuaweiAccountIdentity(): Promise<void> {
    return this.runProviderTransition(async (): Promise<void> => {
      await this.activation.clearHuaweiAccountIdentity();
    });
  }

  deactivateCurrentSync(): Promise<void> {
    return this.runProviderTransition(async (): Promise<void> => {
      await this.syncService.initializeAiraSyncSettings();
      await this.syncService.deactivateCurrentSync();
      this.automaticRuntime.cancelBookmarkAutomaticSync();
      this.automaticRuntime.cancelPersonalizationAutomaticSync();
      this.automaticRuntime.cancelHistoryAutomaticSync();
    });
  }

  requestProviderSelection(remoteKind: AiraSyncProviderKind): Promise<SyncExperienceProviderOutcome> {
    return this.runProviderTransition(async (): Promise<SyncExperienceProviderOutcome> => {
      return this.requestProviderSelectionWithinTransition(remoteKind);
    });
  }

  private async requestProviderSelectionWithinTransition(
    remoteKind: AiraSyncProviderKind
  ): Promise<SyncExperienceProviderOutcome> {
    try {
      const distributionOutcome = this.checkDistributionAccess(remoteKind, '选择同步方式');
      if (distributionOutcome !== undefined) {
        return distributionOutcome;
      }
      await this.syncService.initializeAiraSyncSettings();
      let settings = this.syncService.getAiraSyncSettings();
      if (settings.remoteKind === remoteKind) {
        if (remoteKind === 'huawei_space') {
          await this.syncService.checkHuaweiSpaceCapability();
        }
        return this.outcome('no-action', remoteKind, '当前设备已使用此同步方式。');
      }
      if (!this.isProviderConfigured(settings, remoteKind)) {
        if (remoteKind === 'webdav' || remoteKind === 'self_hosted') {
          return this.outcome('configuration-required', remoteKind, '请先完成同步方式配置。');
        }
        const activation = remoteKind === 'huawei_space'
          ? await this.activation.signInHuaweiSpaceAccountOnly()
          : await this.activation.signInHuaweiAccountOnly();
        if (activation.type === 'failed') {
          return this.activationFailure(remoteKind, activation);
        }
        settings = this.syncService.getAiraSyncSettings();
      }
      const accessOutcome = await this.checkProviderAccess(remoteKind, '选择同步方式');
      if (accessOutcome !== undefined) {
        return accessOutcome;
      }
      return this.outcome(
        'provider-selection-confirmation-required',
        remoteKind,
        '会先合并已开启且目标支持的同步内容，完成后只修改当前设备的同步方式。'
      );
    } catch (error) {
      return this.failure(remoteKind, '选择同步方式', error as Error);
    }
  }

  async selectProvider(
    remoteKind: AiraSyncProviderKind,
    domains?: SyncExperienceProviderDomains
  ): Promise<SyncExperienceProviderOutcome> {
    return this.runProviderTransition(async (): Promise<SyncExperienceProviderOutcome> => {
      return this.selectProviderWithinTransition(remoteKind, domains);
    });
  }

  private async selectProviderWithinTransition(
    remoteKind: AiraSyncProviderKind,
    domains?: SyncExperienceProviderDomains
  ): Promise<SyncExperienceProviderOutcome> {
    let bookmarkSyncStarted = false;
    let bookmarkSyncCompleted = false;
    try {
      const distributionOutcome = this.checkDistributionAccess(remoteKind, '选择同步方式');
      if (distributionOutcome !== undefined) {
        return distributionOutcome;
      }
      await this.syncService.initializeAiraSyncSettings();
      const settings = this.syncService.getAiraSyncSettings();
      if (!this.isProviderConfigured(settings, remoteKind)) {
        return this.outcome('configuration-required', remoteKind, '请先完成同步方式配置。');
      }
      const accessOutcome = await this.checkProviderAccess(remoteKind, '选择同步方式');
      if (accessOutcome !== undefined) {
        return accessOutcome;
      }
      const defersFirstHuaweiBookmarkInitialization = remoteKind === 'huawei_space' &&
        settings.remoteKind === 'none' && domains?.bookmarks === false && domains?.personalization === false;
      if (remoteKind === 'huawei_space' && !defersFirstHuaweiBookmarkInitialization) {
        await this.syncService.checkHuaweiSpaceCapability();
      }
      let bookmarkResult: AiraBookmarkMergeSyncResult | undefined = undefined;
      let personalizationMessage = '';
      let historyMessage = '';
      const shouldSyncPersonalization = domains?.personalization ?? settings.personalizationSyncEnabled === true;
      const shouldSyncBookmarks = domains?.bookmarks ?? settings.bookmarkSyncEnabled === true;
      const shouldSyncHistory = domains?.history ?? true;
      const defersHuaweiBookmarkUpload = settings.bookmarkSyncEnabled === true &&
        settings.remoteKind === 'aira_cloud' &&
        remoteKind === 'huawei_space' && shouldSyncBookmarks;
      if (shouldSyncPersonalization) {
        const result = await this.personalizationSyncService.syncToProvider(remoteKind);
        if (!result.ok) {
          throw new Error(result.message);
        }
        personalizationMessage = result.message;
      }
      if (shouldSyncBookmarks && !defersHuaweiBookmarkUpload) {
        bookmarkSyncStarted = true;
        bookmarkResult = await this.syncService.syncBookmarksToProvider(
          remoteKind,
          this.resolveBookmarkTargetMergeIntent(settings.remoteKind, remoteKind)
        );
        if (bookmarkResult.blocked || bookmarkResult.conflictCount > 0) {
          return this.outcome('provider-selection-blocked', remoteKind, bookmarkResult.summary, bookmarkResult);
        }
        bookmarkSyncCompleted = true;
      }
      if (shouldSyncHistory && settings.remoteKind !== remoteKind) {
        const historyResult = await this.automaticRuntime.runHistoryProviderTransitionWithinCurrentOperation(
          remoteKind,
          settings.remoteKind
        );
        if (historyResult !== undefined) {
          if (!historyResult.ok) {
            throw new Error(historyResult.message);
          }
          historyMessage = historyResult.message;
        }
      }
      if (defersHuaweiBookmarkUpload) {
        await this.syncService.selectActiveProviderWithPendingBookmarkSync(remoteKind, 'aira_cloud');
        this.automaticRuntime.schedulePendingBookmarkSync();
      } else {
        await this.syncService.selectActiveProvider(remoteKind);
      }
      if (remoteKind === 'webdav') {
        await this.automaticRuntime.clearHistorySelectionForWebdav();
      }
      this.automaticRuntime.notifyHistoryProviderChanged();
      if (remoteKind === 'aira_cloud') {
        await this.membershipFeature.recordUsage(AIRA_FEATURE_CLOUD_SYNC);
      }
      const messages: string[] = [];
      if (bookmarkResult !== undefined && bookmarkResult.summary.length > 0) {
        messages.push(bookmarkResult.summary);
      }
      if (personalizationMessage.length > 0) {
        messages.push(`主页收藏、小说书架和常用设置：${personalizationMessage}`);
      }
      if (historyMessage.length > 0) {
        messages.push(`历史记录：${historyMessage}`);
      }
      messages.push(`当前设备已改用${this.resolveProviderLabel(remoteKind)}。`);
      return this.outcome('provider-selected', remoteKind, messages.join('\n'), bookmarkResult);
    } catch (error) {
      const normalizedError = error as Error;
      return this.failure(
        remoteKind,
        '选择同步方式',
        normalizedError,
        bookmarkSyncStarted && !bookmarkSyncCompleted
          ? this.syncService.resolveBookmarkSyncFailure(normalizedError)
          : undefined
      );
    }
  }

  setAdditionalBackupEnabled(
    remoteKind: AiraSyncProviderKind,
    enabled: boolean
  ): Promise<SyncExperienceProviderOutcome> {
    return this.runProviderTransition(async (): Promise<SyncExperienceProviderOutcome> => {
      return this.setAdditionalBackupEnabledWithinTransition(remoteKind, enabled);
    });
  }

  private async setAdditionalBackupEnabledWithinTransition(
    remoteKind: AiraSyncProviderKind,
    enabled: boolean
  ): Promise<SyncExperienceProviderOutcome> {
    try {
      const distributionOutcome = this.checkDistributionAccess(remoteKind, enabled ? '开启附加备份' : '关闭附加备份');
      if (distributionOutcome !== undefined && enabled) {
        return distributionOutcome;
      }
      await this.syncService.initializeAiraSyncSettings();
      const settings = this.syncService.getAiraSyncSettings();
      if (!enabled) {
        await this.syncService.setAdditionalBackupProviderEnabled(remoteKind, false);
        return this.outcome('additional-backup-disabled', remoteKind, '已停止向此位置写入附加备份。');
      }
      if (settings.remoteKind === 'none') {
        return this.outcome('configuration-required', remoteKind, '请先选择当前设备使用的同步方式。');
      }
      if (settings.remoteKind === remoteKind) {
        return this.outcome('no-action', remoteKind, '当前同步方式不需要重复设置为附加备份。');
      }
      if (!this.isProviderConfigured(settings, remoteKind)) {
        return this.outcome('configuration-required', remoteKind, '请先完成附加备份位置配置。');
      }
      const accessOutcome = await this.checkProviderAccess(remoteKind, '开启附加备份');
      if (accessOutcome !== undefined) {
        return accessOutcome;
      }
      if (remoteKind === 'huawei_space') {
        await this.syncService.checkHuaweiSpaceCapability();
      }
      await this.initializeAdditionalBackup(remoteKind);
      await this.syncService.setAdditionalBackupProviderEnabled(remoteKind, true);
      if (remoteKind === 'aira_cloud') {
        await this.membershipFeature.recordUsage(AIRA_FEATURE_CLOUD_SYNC);
      }
      return this.outcome(
        'additional-backup-enabled',
        remoteKind,
        `${this.resolveProviderLabel(remoteKind)}会在普通同步成功后接收本机书签和常用设置的附加备份，并以本机内容覆盖该位置已有副本。`
      );
    } catch (error) {
      const message = this.stringifyError(error as Error);
      return this.failure(remoteKind, enabled ? '开启附加备份' : '关闭附加备份', new Error(message));
    }
  }

  private async activateBookmarkDomainWithProviderWithinTransition(
    remoteKind: AiraSyncProviderKind
  ): Promise<SyncExperienceProviderOutcome> {
    const settings = this.syncService.getAiraSyncSettings();
    const bookmarkAlreadyEnabled = settings.bookmarkSyncEnabled === true;
    if (settings.remoteKind !== remoteKind) {
      const selection = await this.selectProviderWithinTransition(remoteKind);
      if (selection.type !== 'provider-selected') {
        return selection;
      }
      if (bookmarkAlreadyEnabled) {
        return this.outcome('bookmark-domain-enabled', remoteKind, selection.message, selection.bookmarkResult);
      }
    }
    return this.setBookmarkDomainEnabledWithinTransition(true);
  }

  setBookmarkDomainEnabled(enabled: boolean): Promise<SyncExperienceProviderOutcome> {
    return this.runProviderTransition(async (): Promise<SyncExperienceProviderOutcome> => {
      return this.setBookmarkDomainEnabledWithinTransition(enabled);
    });
  }

  private async setBookmarkDomainEnabledWithinTransition(
    enabled: boolean
  ): Promise<SyncExperienceProviderOutcome> {
    const settings = this.syncService.getAiraSyncSettings();
    const activeProvider = this.requireProviderKind(settings.remoteKind);
    try {
      if (!enabled) {
        await this.syncService.setBookmarkSyncEnabled(false);
        this.automaticRuntime.cancelBookmarkAutomaticSync();
        return this.outcome('bookmark-domain-disabled', activeProvider, '书签同步已暂停。');
      }
      const accessOutcome = await this.checkProviderAccess(activeProvider, '开启书签同步');
      if (accessOutcome !== undefined) {
        return accessOutcome;
      }
      if (activeProvider === 'huawei_space') {
        await this.syncService.beginHuaweiBookmarkInitialization();
        this.automaticRuntime.schedulePendingBookmarkSync();
        return this.outcome(
          'bookmark-domain-enabled',
          activeProvider,
          '正在从华为云空间初始化书签，完成后会自动保持同步。'
        );
      }
      const result = await this.syncService.initializeBookmarkSyncDomain();
      if (result.blocked || result.conflictCount > 0) {
        return this.outcome('bookmark-domain-blocked', activeProvider, result.summary, result);
      }
      if (activeProvider === 'aira_cloud') {
        await this.membershipFeature.recordUsage(AIRA_FEATURE_CLOUD_SYNC);
      }
      this.automaticRuntime.scheduleBookmarkPeriodicSync();
      return this.outcome('bookmark-domain-enabled', activeProvider, result.summary, result);
    } catch (error) {
      const normalizedError = error as Error;
      return this.failure(
        activeProvider,
        enabled ? '开启书签同步' : '暂停书签同步',
        normalizedError,
        this.syncService.resolveBookmarkSyncFailure(normalizedError)
      );
    }
  }

  private async deactivateProviderWithinTransition(
    remoteKind: AiraSyncProviderKind
  ): Promise<SyncExperienceProviderOutcome> {
    await this.syncService.initializeAiraSyncSettings();
    const settings = this.syncService.getAiraSyncSettings();
    if ((settings.additionalBackupRemoteKinds ?? []).indexOf(remoteKind) >= 0) {
      return this.setAdditionalBackupEnabledWithinTransition(remoteKind, false);
    }
    if (settings.remoteKind === remoteKind && settings.bookmarkSyncEnabled === true) {
      return this.setBookmarkDomainEnabledWithinTransition(false);
    }
    return this.outcome('no-action', remoteKind, `${this.resolveProviderLabel(remoteKind)}当前没有可关闭的同步任务。`);
  }

  private async initializeAdditionalBackup(
    remoteKind: AiraSyncProviderKind
  ): Promise<AiraSyncWriteStateResult | undefined> {
    const settings = this.syncService.getAiraSyncSettings();
    if (settings.personalizationSyncEnabled === true) {
      await this.personalizationSyncService.writeAdditionalBackup(remoteKind);
    }
    if (settings.bookmarkSyncEnabled === true) {
      return this.syncService.writeAdditionalBookmarkBackup(remoteKind);
    }
    return undefined;
  }

  saveWebdavConfiguration(
    role: SyncWebdavTargetRole,
    params: SyncWebdavConfigurationParams,
    configureOnly: boolean = false
  ): Promise<SyncWebdavActivationOutcome> {
    return this.runProviderTransition(async (): Promise<SyncWebdavActivationOutcome> => {
      return this.saveWebdavConfigurationWithinTransition(role, params, configureOnly);
    });
  }

  private async saveWebdavConfigurationWithinTransition(
    role: SyncWebdavTargetRole,
    params: SyncWebdavConfigurationParams,
    configureOnly: boolean
  ): Promise<SyncWebdavActivationOutcome> {
    await this.syncService.initializeAiraSyncSettings();
    const previousSettings = this.syncService.getAiraSyncSettings();
    const activeWebdav = role === 'active' && this.isActiveWebdav(previousSettings);
    const additionalBackupWebdav = role === 'additional_backup' &&
      (previousSettings.additionalBackupRemoteKinds ?? []).indexOf('webdav') >= 0;
    const sourceChanged = this.hasWebdavSourceChanged(previousSettings.webdav, params);
    const credentialsChanged = previousSettings.webdav.password !== params.password;
    const replacesActiveWebdav = activeWebdav && sourceChanged;
    const updatesActiveCredentials = activeWebdav && !sourceChanged && credentialsChanged;
    const reconfiguresAdditionalBackup = additionalBackupWebdav && (sourceChanged || credentialsChanged);
    if (role === 'active') {
      const decision = await this.membershipFeature.canUse(AIRA_FEATURE_WEBDAV_SYNC, {
        dataScope: 'profile_persistent',
        privacyMode: 'regular'
      });
      if (!decision.allowed) {
        return {
          type: 'failed',
          title: decision.title.length > 0 ? decision.title : '启用 WebDAV 同步',
          message: decision.message,
          membershipDecision: decision
        };
      }
    }
    if (replacesActiveWebdav || updatesActiveCredentials || reconfiguresAdditionalBackup) {
      try {
        await this.syncService.testAiraWebdavConnectionForConfig(
          params.endpoint,
          params.username,
          params.password
        );
      } catch (_error) {
        return {
          type: 'failed',
          title: 'WebDAV 连接失败',
          message: '无法连接新的 WebDAV 服务商，请检查地址、账号密码和网络后再试。'
        };
      }
    }
    const result = await this.activation.saveWebdavConfig({
      endpoint: params.endpoint,
      username: params.username,
      password: params.password
    });
    if (updatesActiveCredentials && result.type === 'saved') {
      await this.remoteStatusCoordinator.readAndCache('webdav').catch((_error: Error): void => {
      });
      return {
        type: 'activation-completed',
        title: 'WebDAV 凭据已更新',
        message: '新的账号凭据已验证并保存，同步方式没有改变。'
      };
    }
    if (activeWebdav && !replacesActiveWebdav && result.type === 'saved') {
      return {
        type: 'activation-completed',
        title: 'WebDAV 配置未更改',
        message: '当前 WebDAV 服务商和账号配置仍在使用。'
      };
    }
    if (replacesActiveWebdav && result.type === 'saved') {
      const transition = await this.selectProviderWithinTransition('webdav');
      const outcome = this.toWebdavActiveOutcome(transition);
      if (outcome.type === 'activation-completed') {
        await this.remoteStatusCoordinator.readAndCache('webdav').catch((_error: Error): void => {
        });
        return {
          type: 'activation-completed',
          title: 'WebDAV 服务商已更换',
          message: '书签、主页收藏、小说书架和已开启的常用设置已经在新的 WebDAV 服务商完成准备。'
        };
      }
      const restored = await this.restorePreviousWebdav(previousSettings);
      if (!restored) {
        return {
          type: 'failed',
          title: '更换服务商未完成',
          message: '新服务商没有完成同步准备，请重新打开 WebDAV 设置确认当前配置。'
        };
      }
      return {
        type: outcome.type,
        title: '服务商未更改',
        message: `${outcome.message} 当前仍继续使用原来的 WebDAV 服务商。`,
        membershipDecision: outcome.membershipDecision
      };
    }
    if (reconfiguresAdditionalBackup && result.type === 'saved') {
      const outcome = await this.handleWebdavActivationResultWithinTransition(role, result);
      if (outcome.type === 'additional-backup-enabled') {
        return outcome;
      }
      const restored = await this.restorePreviousWebdav(previousSettings);
      if (!restored) {
        return {
          type: 'failed',
          title: '附加备份位置未更新',
          message: '新的 WebDAV 备份位置没有完成初始化，请重新打开设置确认当前配置。'
        };
      }
      return {
        type: outcome.type,
        title: '附加备份位置未更改',
        message: `${outcome.message} 当前仍继续使用原来的 WebDAV 附加备份位置。`,
        membershipDecision: outcome.membershipDecision
      };
    }
    if (configureOnly && role === 'active' && result.type === 'saved') {
      return {
        type: 'configuration-saved',
        title: result.title,
        message: result.message
      };
    }
    return this.handleWebdavActivationResultWithinTransition(role, result);
  }

  deactivateWebdav(): Promise<SyncWebdavActivationOutcome> {
    return this.runProviderTransition(async (): Promise<SyncWebdavActivationOutcome> => {
      const outcome = await this.deactivateProviderWithinTransition('webdav');
      if (outcome.type === 'additional-backup-disabled' || outcome.type === 'bookmark-domain-disabled' ||
        outcome.type === 'no-action') {
        return {
          type: 'deactivated',
          title: 'WebDAV 同步已关闭',
          message: outcome.message
        };
      }
      return {
        type: 'failed',
        title: outcome.title,
        message: outcome.message,
        membershipDecision: outcome.membershipDecision
      };
    });
  }

  signInHuaweiAccountForSync(): Promise<SyncWebdavActivationOutcome> {
    return this.runProviderTransition(async (): Promise<SyncWebdavActivationOutcome> => {
      const result = await this.activation.signInHuaweiAccountOnly();
      if (result.type === 'failed') {
        return { type: 'failed', title: result.title, message: result.message };
      }
      return { type: 'signed-in', title: result.title, message: result.message };
    });
  }

  private async handleWebdavActivationResultWithinTransition(
    role: SyncWebdavTargetRole,
    result: SyncActivationResult
  ): Promise<SyncWebdavActivationOutcome> {
    if (result.type !== 'saved') {
      return {
        type: 'failed',
        title: result.title,
        message: result.message
      };
    }
    if (role === 'additional_backup') {
      return this.toWebdavAdditionalBackupOutcome(
        await this.setAdditionalBackupEnabledWithinTransition('webdav', true)
      );
    }
    const outcome = this.toWebdavActiveOutcome(
      await this.activateBookmarkDomainWithProviderWithinTransition('webdav')
    );
    if (outcome.type === 'activation-completed') {
      await this.remoteStatusCoordinator.readAndCache('webdav').catch((_error: Error): void => {
      });
    }
    return outcome;
  }

  private toWebdavActiveOutcome(outcome: SyncExperienceProviderOutcome): SyncWebdavActivationOutcome {
    if (outcome.type === 'bookmark-domain-enabled' || outcome.type === 'provider-selected' || outcome.type === 'no-action') {
      return {
        type: 'activation-completed',
        title: 'WebDAV 书签同步已开启',
        message: outcome.message
      };
    }
    if (outcome.type === 'provider-selection-blocked' || outcome.type === 'bookmark-domain-blocked') {
      return { type: 'activation-blocked', title: outcome.title, message: outcome.message };
    }
    return {
      type: 'failed',
      title: outcome.title,
      message: outcome.message,
      membershipDecision: outcome.membershipDecision
    };
  }

  private toWebdavAdditionalBackupOutcome(
    outcome: SyncExperienceProviderOutcome
  ): SyncWebdavActivationOutcome {
    if (outcome.type === 'additional-backup-enabled') {
      return {
        type: 'additional-backup-enabled',
        title: 'WebDAV 备份已开启',
        message: outcome.message
      };
    }
    return {
      type: 'failed',
      title: outcome.title,
      message: outcome.message
    };
  }

  private isActiveWebdav(settings: AiraSyncSettings): boolean {
    return settings.remoteKind === 'webdav';
  }

  private hasWebdavSourceChanged(
    current: AiraSyncWebdavConfig,
    candidate: SyncWebdavConfigurationParams
  ): boolean {
    return this.normalizeEndpoint(current.endpoint) !== this.normalizeEndpoint(candidate.endpoint) ||
      current.username.trim() !== candidate.username.trim();
  }

  private async restorePreviousWebdav(settings: AiraSyncSettings): Promise<boolean> {
    try {
      const previous = settings.webdav;
      await this.syncService.saveAiraWebdavConfig(
        previous.endpoint,
        previous.username,
        previous.password
      );
      if (previous.remoteStatusCache !== null) {
        await this.syncService.saveAiraRemoteStatusCacheForKind('webdav', previous.remoteStatusCache);
      }
      return true;
    } catch (_error) {
      return false;
    }
  }

  private normalizeEndpoint(endpoint: string): string {
    return endpoint.trim().replace(/\/+$/, '');
  }

  private runProviderTransition<T>(operation: () => Promise<T>): Promise<T> {
    return this.automaticRuntime.runProviderTransition(operation);
  }

  resolveProviderLabel(remoteKind: AiraSyncRemoteKind): string {
    if (remoteKind === 'aira_cloud') {
      return 'Aira 云同步';
    }
    if (remoteKind === 'huawei_space') {
      return '华为云空间';
    }
    if (remoteKind === 'webdav') {
      return 'WebDAV';
    }
    if (remoteKind === 'self_hosted') {
      return '个人服务器';
    }
    return '同步方式';
  }

  private async checkProviderAccess(
    remoteKind: AiraSyncProviderKind,
    title: string
  ): Promise<SyncExperienceProviderOutcome | undefined> {
    const distributionOutcome = this.checkDistributionAccess(remoteKind, title);
    if (distributionOutcome !== undefined) {
      return distributionOutcome;
    }
    if (remoteKind !== 'aira_cloud') {
      return undefined;
    }
    const decision = await this.membershipFeature.canUse(AIRA_FEATURE_CLOUD_SYNC, {
      dataScope: 'profile_persistent',
      privacyMode: 'regular',
      loggedIn: this.syncService.getAiraSyncSettings().huaweiCloud.uid.trim().length > 0
    });
    if (decision.allowed) {
      return undefined;
    }
    return {
      type: 'membership-required',
      remoteKind: remoteKind,
      providerLabel: this.resolveProviderLabel(remoteKind),
      title: decision.title.length > 0 ? decision.title : title,
      message: decision.message,
      membershipDecision: decision
    };
  }

  private checkDistributionAccess(
    remoteKind: AiraSyncProviderKind,
    title: string
  ): SyncExperienceProviderOutcome | undefined {
    const capability = remoteKind === 'aira_cloud'
      ? 'aira_cloud'
      : (remoteKind === 'huawei_space'
        ? 'huawei_space'
        : (remoteKind === 'self_hosted' ? 'personal_server' : undefined));
    if (capability === undefined || AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable(capability)) {
      return undefined;
    }
    return {
      type: 'provider-selection-blocked',
      remoteKind: remoteKind,
      providerLabel: this.resolveProviderLabel(remoteKind),
      title: title,
      message: AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason(capability)
    };
  }

  private isProviderConfigured(settings: AiraSyncSettings, remoteKind: AiraSyncProviderKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud') &&
        settings.huaweiCloud.uid.trim().length > 0;
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space') &&
        settings.huaweiSpace.uid.trim().length > 0;
    }
    if (remoteKind === 'self_hosted') {
      const config = resolveAiraPersonalServerConfig(settings);
      return config.baseUrl.trim().length > 0 && config.instanceId.trim().length > 0 &&
        config.credentialId.trim().length > 0 && config.deviceToken.trim().length > 0;
    }
    return settings.webdav.endpoint.trim().length > 0;
  }

  private resolveBookmarkTargetMergeIntent(
    currentRemoteKind: AiraSyncRemoteKind,
    targetRemoteKind: AiraSyncProviderKind
  ): AiraBookmarkTargetMergeIntent {
    return isAiraBookmarkProviderTransition(currentRemoteKind, targetRemoteKind)
      ? 'provider-switch'
      : 'ordinary';
  }

  private activationFailure(
    remoteKind: AiraSyncProviderKind,
    result: SyncActivationResult
  ): SyncExperienceProviderOutcome {
    return {
      type: 'failed',
      remoteKind: remoteKind,
      providerLabel: this.resolveProviderLabel(remoteKind),
      title: result.title,
      message: result.message
    };
  }

  private failure(
    remoteKind: AiraSyncProviderKind,
    title: string,
    error: Error,
    bookmarkFailure?: AiraBookmarkSyncFailure
  ): SyncExperienceProviderOutcome {
    return {
      type: 'failed',
      remoteKind: remoteKind,
      providerLabel: this.resolveProviderLabel(remoteKind),
      title: title,
      message: this.stringifyError(error),
      bookmarkFailure: bookmarkFailure
    };
  }

  private outcome(
    type: SyncExperienceProviderOutcomeType,
    remoteKind: AiraSyncProviderKind,
    message: string,
    bookmarkResult?: AiraBookmarkMergeSyncResult
  ): SyncExperienceProviderOutcome {
    return {
      type: type,
      remoteKind: remoteKind,
      providerLabel: this.resolveProviderLabel(remoteKind),
      title: this.resolveProviderLabel(remoteKind),
      message: message,
      bookmarkResult: bookmarkResult
    };
  }

  private requireProviderKind(remoteKind: AiraSyncRemoteKind): AiraSyncProviderKind {
    if (remoteKind === 'aira_cloud' || remoteKind === 'huawei_space' || remoteKind === 'webdav' ||
      remoteKind === 'self_hosted') {
      return remoteKind;
    }
    throw new Error('请先选择同步方式。');
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}

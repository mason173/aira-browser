import {
  AiraAdditionalBackupIntervalDays,
  AiraSyncSettings
} from '../../common/models/AiraSyncModels';
import { SyncAdditionalBackupPolicyService } from '../../services/sync/SyncAdditionalBackupPolicyService';
import { SyncSettingsProviderCardViewState } from './SyncSettingsCenterViewModel';

export interface SyncAdditionalBackupViewState {
  enabled: boolean;
  intervalDays: AiraAdditionalBackupIntervalDays;
  intervalLabel: string;
  providerCards: SyncSettingsProviderCardViewState[];
  providerSummary: string;
  lastBackupLabel: string;
  statusMessage: string;
  canBackupNow: boolean;
}

export function createDefaultSyncAdditionalBackupViewState(): SyncAdditionalBackupViewState {
  return {
    enabled: false,
    intervalDays: 7,
    intervalLabel: '7 天一次',
    providerCards: [],
    providerSummary: '未设置',
    lastBackupLabel: '尚未完成备份',
    statusMessage: '额外备份只会覆盖写入你的 WebDAV，不会改成当前同步方式。',
    canBackupNow: false
  };
}

export class SyncAdditionalBackupViewModel {
  private policyService: SyncAdditionalBackupPolicyService = new SyncAdditionalBackupPolicyService();

  buildState(
    settings: AiraSyncSettings,
    providerCards: SyncSettingsProviderCardViewState[]
  ): SyncAdditionalBackupViewState {
    const destinationCard = this.resolveWebdavDestination(providerCards);
    const destinationReady = destinationCard !== undefined && destinationCard.role === 'additional_backup';
    const enabled = this.policyService.isEnabled(settings);
    const lastBackupAt = this.policyService.resolveLastCompleteBackupAt(settings);
    return {
      enabled: enabled,
      intervalDays: this.policyService.resolveIntervalDays(settings),
      intervalLabel: this.policyService.resolveIntervalLabel(settings),
      providerCards: destinationCard === undefined ? [] : [destinationCard],
      providerSummary: this.resolveProviderSummary(destinationCard, settings),
      lastBackupLabel: this.formatTimestamp(lastBackupAt),
      statusMessage: this.resolveStatusMessage(enabled, destinationReady, destinationCard),
      canBackupNow: enabled && destinationReady &&
        (settings.bookmarkSyncEnabled === true || settings.personalizationSyncEnabled === true)
    };
  }

  private resolveWebdavDestination(
    providerCards: SyncSettingsProviderCardViewState[]
  ): SyncSettingsProviderCardViewState | undefined {
    return providerCards.find((card: SyncSettingsProviderCardViewState): boolean => {
      return card.id === 'webdav';
    });
  }

  private resolveProviderSummary(
    destinationCard: SyncSettingsProviderCardViewState | undefined,
    settings: AiraSyncSettings
  ): string {
    if (destinationCard === undefined) {
      return settings.remoteKind === 'webdav' ? '当前同步已是 WebDAV' : '不可用';
    }
    if (destinationCard.role === 'additional_backup') {
      const endpoint = settings.webdav.endpoint.trim();
      return endpoint.length > 0 ? endpoint : 'WebDAV 已开启';
    }
    return destinationCard.isConfigured ? '已填写，未开启' : '未设置';
  }

  private resolveStatusMessage(
    enabled: boolean,
    destinationReady: boolean,
    destinationCard: SyncSettingsProviderCardViewState | undefined
  ): string {
    if (destinationCard === undefined) {
      return '当前同步方式已经是 WebDAV 时，无需再设额外备份。';
    }
    if (!destinationReady) {
      return '额外备份只会覆盖写入你的 WebDAV，不会改成当前同步方式。';
    }
    if (!enabled) {
      return 'WebDAV 备份位置已保留，重新开启后会按设定频率继续覆盖写入。';
    }
    return '当前同步完成后，仅在达到设定间隔时用本机内容覆盖 WebDAV 上的额外副本。';
  }

  private formatTimestamp(timestamp: number): string {
    if (timestamp <= 0) {
      return '尚未完成备份';
    }
    const date = new Date(timestamp);
    const now = new Date();
    const time = `${this.pad(date.getHours())}:${this.pad(date.getMinutes())}`;
    if (date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() &&
      date.getDate() === now.getDate()) {
      return `今天 ${time}`;
    }
    return `${date.getMonth() + 1}月${date.getDate()}日 ${time}`;
  }

  private pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}

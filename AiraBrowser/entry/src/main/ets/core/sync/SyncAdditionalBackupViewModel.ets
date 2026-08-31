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
    providerSummary: '未选择',
    lastBackupLabel: '尚未完成备份',
    statusMessage: '选择备份位置后，可以按设定频率保存额外副本。',
    canBackupNow: false
  };
}

export class SyncAdditionalBackupViewModel {
  private policyService: SyncAdditionalBackupPolicyService = new SyncAdditionalBackupPolicyService();

  buildState(
    settings: AiraSyncSettings,
    providerCards: SyncSettingsProviderCardViewState[]
  ): SyncAdditionalBackupViewState {
    const selectedProviderCount = providerCards.filter((card: SyncSettingsProviderCardViewState): boolean => {
      return card.role === 'additional_backup';
    }).length;
    const enabled = this.policyService.isEnabled(settings);
    const lastBackupAt = this.policyService.resolveLastCompleteBackupAt(settings);
    return {
      enabled: enabled,
      intervalDays: this.policyService.resolveIntervalDays(settings),
      intervalLabel: this.policyService.resolveIntervalLabel(settings),
      providerCards: providerCards,
      providerSummary: selectedProviderCount > 0 ? `${selectedProviderCount} 个位置` : '未选择',
      lastBackupLabel: this.formatTimestamp(lastBackupAt),
      statusMessage: this.resolveStatusMessage(enabled, selectedProviderCount),
      canBackupNow: enabled && selectedProviderCount > 0 &&
        (settings.bookmarkSyncEnabled === true || settings.personalizationSyncEnabled === true)
    };
  }

  private resolveStatusMessage(enabled: boolean, selectedProviderCount: number): string {
    if (selectedProviderCount <= 0) {
      return '请选择至少一个备份位置。额外备份不会自动变成当前同步方式。';
    }
    if (!enabled) {
      return '备份位置已保留，重新开启后会按设定频率继续。';
    }
    return '当前同步完成后，仅在达到设定间隔时更新额外副本。';
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

import {
  AiraSyncProviderKind,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  isAiraSyncProviderEnabled
} from '../../common/models/AiraSyncModels';
import { SettingsColoredTileIconResources } from '../resources/SettingsColoredTileIconResources';
import {
  BrowserSyncProviderIconBackgroundTokenSet,
  DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS
} from '../../features/theme/BrowserThemePaletteModels';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export interface SyncSettingsProviderCardViewState {
  id: AiraSyncRemoteKind;
  role: 'active' | 'additional_backup' | 'available';
  title: string;
  subtitle: string;
  status: string;
  icon: Resource;
  imageIcon?: Resource;
  iconBackgroundColor: ResourceColor;
  isActive: boolean;
  isEnabled: boolean;
  isConfigured: boolean;
  requiresPro: boolean;
}

export type SyncHuaweiSpaceReadinessState =
  | 'needs_account'
  | 'checking'
  | 'ready'
  | 'unavailable';

export interface SyncSettingsCenterViewState {
  additionalBackupProviderCards: SyncSettingsProviderCardViewState[];
  hasActiveSync: boolean;
}

export interface SyncSettingsCenterViewModelInput {
  settings: AiraSyncSettings;
  hasCloudConfig: boolean;
  hasHuaweiSpaceConfig: boolean;
  hasWebdavConfig: boolean;
  huaweiSpaceReadiness: SyncHuaweiSpaceReadinessState;
  isPrivateSession: boolean;
  syncProviderIconBackgrounds?: BrowserSyncProviderIconBackgroundTokenSet;
}

export class SyncSettingsCenterViewModel {
  buildState(input: SyncSettingsCenterViewModelInput): SyncSettingsCenterViewState {
    const iconBackgrounds = this.resolveProviderIconBackgrounds(input);
    if (input.isPrivateSession) {
      return {
        additionalBackupProviderCards: [],
        hasActiveSync: false
      };
    }

    const activeProvider = this.resolveActiveProvider(input.settings);
    const activeKinds = this.resolveActiveKinds(input.settings, activeProvider);
    return {
      additionalBackupProviderCards: this.buildAdditionalBackupCards(
        input,
        activeProvider,
        activeKinds,
        iconBackgrounds
      ),
      hasActiveSync: input.settings.bookmarkSyncEnabled === true &&
        activeProvider !== 'none' && this.isRemoteKindActive(input.settings, activeProvider)
    };
  }

  private resolveActiveProvider(settings: AiraSyncSettings): AiraSyncRemoteKind {
    if (!this.isProviderAvailable(settings.remoteKind)) {
      return 'none';
    }
    return settings.remoteKind;
  }

  private resolveActiveKinds(
    settings: AiraSyncSettings,
    activeProvider: AiraSyncRemoteKind
  ): AiraSyncRemoteKind[] {
    const result: AiraSyncRemoteKind[] = [];
    if (activeProvider !== 'none' && this.isRemoteKindActive(settings, activeProvider)) {
      result.push(activeProvider);
    }
    const backups = settings.additionalBackupRemoteKinds ?? [];
    backups.forEach((kind: AiraSyncProviderKind) => {
      if (kind !== activeProvider && this.isRemoteKindActive(settings, kind) && result.indexOf(kind) < 0) {
        result.push(kind);
      }
    });
    return result;
  }

  private buildAdditionalBackupCards(
    input: SyncSettingsCenterViewModelInput,
    activeProvider: AiraSyncRemoteKind,
    activeKinds: AiraSyncRemoteKind[],
    iconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet
  ): SyncSettingsProviderCardViewState[] {
    if (activeProvider === 'none' || activeProvider === 'webdav') {
      return [];
    }
    return [this.buildWebdavBackupCard(
      this.resolveProviderRole('webdav', activeProvider, activeKinds),
      input.settings,
      input.hasWebdavConfig,
      iconBackgrounds
    )];
  }

  private buildWebdavBackupCard(
    role: 'active' | 'additional_backup' | 'available',
    settings: AiraSyncSettings,
    hasWebdavConfig: boolean,
    iconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet
  ): SyncSettingsProviderCardViewState {
    const endpoint = settings.webdav.endpoint.trim();
    return {
      id: 'webdav',
      role: role,
      title: 'WebDAV',
      subtitle: role === 'additional_backup'
        ? (endpoint.length > 0 ? `普通同步成功后覆盖写入 ${endpoint}` : '普通同步成功后覆盖写入你的 WebDAV')
        : (hasWebdavConfig ? '已保存配置，可开启为额外备份' : '填写 WebDAV 地址后即可开启额外备份'),
      status: role === 'additional_backup' ? '额外备份已开启' : '未开启',
      icon: $r('sys.symbol.folder_fill'),
      imageIcon: SettingsColoredTileIconResources.foregroundIcon('webdav'),
      iconBackgroundColor: iconBackgrounds.webdav,
      isActive: false,
      isEnabled: role === 'additional_backup',
      isConfigured: hasWebdavConfig,
      requiresPro: false
    };
  }

  private resolveProviderRole(
    remoteKind: AiraSyncProviderKind,
    activeProvider: AiraSyncRemoteKind,
    activeKinds: AiraSyncRemoteKind[]
  ): 'active' | 'additional_backup' | 'available' {
    if (remoteKind === activeProvider) {
      return 'active';
    }
    return this.containsKind(activeKinds, remoteKind) ? 'additional_backup' : 'available';
  }

  private resolveProviderIconBackgrounds(
    input: SyncSettingsCenterViewModelInput
  ): BrowserSyncProviderIconBackgroundTokenSet {
    return input.syncProviderIconBackgrounds ?? DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS;
  }

  private containsKind(kinds: AiraSyncRemoteKind[], kind: AiraSyncRemoteKind): boolean {
    return kinds.indexOf(kind) >= 0;
  }

  private isRemoteKindActive(settings: AiraSyncSettings, remoteKind: AiraSyncRemoteKind): boolean {
    return remoteKind !== 'none' && this.isProviderAvailable(remoteKind) &&
      isAiraSyncProviderEnabled(settings, remoteKind);
  }

  private isProviderAvailable(remoteKind: AiraSyncRemoteKind): boolean {
    if (remoteKind === 'aira_cloud') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud');
    }
    if (remoteKind === 'huawei_space') {
      return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space');
    }
    return remoteKind === 'webdav' || remoteKind === 'self_hosted';
  }

}

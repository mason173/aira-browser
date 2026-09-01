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
    const providerCards = this.buildProviderCards(input, activeProvider, activeKinds, iconBackgrounds);
    return {
      additionalBackupProviderCards: activeProvider === 'none'
        ? []
        : providerCards.filter((card: SyncSettingsProviderCardViewState) => card.role !== 'active'),
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

  private buildProviderCards(
    input: SyncSettingsCenterViewModelInput,
    activeProvider: AiraSyncRemoteKind,
    activeKinds: AiraSyncRemoteKind[],
    iconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet
  ): SyncSettingsProviderCardViewState[] {
    const huaweiSpaceCard = this.buildHuaweiSpaceCard(
      this.resolveProviderRole('huawei_space', activeProvider, activeKinds),
      input.hasHuaweiSpaceConfig,
      input.huaweiSpaceReadiness,
      iconBackgrounds
    );
    const webdavCard = this.buildWebdavCard(
      this.resolveProviderRole('webdav', activeProvider, activeKinds),
      input.settings,
      input.hasWebdavConfig,
      iconBackgrounds
    );
    const cards: SyncSettingsProviderCardViewState[] = [];
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      cards.push(huaweiSpaceCard);
    }
    cards.push(webdavCard);
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('aira_cloud')) {
      cards.push(this.buildCloudCard(
        this.resolveProviderRole('aira_cloud', activeProvider, activeKinds),
        input.hasCloudConfig,
        iconBackgrounds
      ));
    }
    return cards;
  }

  private buildHuaweiSpaceCard(
    role: 'active' | 'additional_backup' | 'available',
    hasHuaweiSpaceConfig: boolean,
    readiness: SyncHuaweiSpaceReadinessState,
    iconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet
  ): SyncSettingsProviderCardViewState {
    return {
      id: 'huawei_space',
      role: role,
      title: '华为云空间同步',
      subtitle: this.resolveHuaweiSpaceSubtitle(role, hasHuaweiSpaceConfig, readiness),
      status: this.resolveHuaweiSpaceStatus(role, readiness),
      icon: $r('sys.symbol.icloud_fill'),
      imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
      iconBackgroundColor: iconBackgrounds.cloud,
      isActive: role === 'active',
      isEnabled: role !== 'available',
      isConfigured: hasHuaweiSpaceConfig,
      requiresPro: false
    };
  }

  private resolveHuaweiSpaceSubtitle(
    role: 'active' | 'additional_backup' | 'available',
    hasHuaweiSpaceConfig: boolean,
    readiness: SyncHuaweiSpaceReadinessState
  ): string {
    if (role === 'active' && readiness === 'unavailable') {
      return '已选为当前同步方式，但系统云空间同步暂不可用';
    }
    if (role === 'active') {
      return '正在使用用户自己的华为云空间同步书签';
    }
    if (role === 'additional_backup') {
      return readiness === 'unavailable' ? '附加备份位置暂不可用' : '普通同步成功后写入华为云空间';
    }
    if (readiness === 'checking') {
      return '正在检查账号、系统云空间同步和本机能力';
    }
    if (readiness === 'unavailable') {
      return '当前账号或系统云空间同步未通过能力检查';
    }
    if (hasHuaweiSpaceConfig && readiness === 'ready') {
      return '已通过能力检查，可设为当前同步方式';
    }
    if (hasHuaweiSpaceConfig) {
      return '已登录华为账号，需要先完成能力检查';
    }
    return '登录华为账号并检查系统云空间同步后可开启';
  }

  private resolveHuaweiSpaceStatus(
    role: 'active' | 'additional_backup' | 'available',
    readiness: SyncHuaweiSpaceReadinessState
  ): string {
    if (readiness === 'checking') {
      return '检查中';
    }
    if (readiness === 'unavailable') {
      return role === 'active' ? '当前同步方式暂不可用' : '暂不可用';
    }
    if (readiness === 'needs_account') {
      return '需登录';
    }
    if (role === 'active') {
      return '当前同步方式';
    }
    return role === 'additional_backup' ? '附加备份已开启' : '未开启';
  }

  private buildCloudCard(
    role: 'active' | 'additional_backup' | 'available',
    hasCloudConfig: boolean,
    iconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet
  ): SyncSettingsProviderCardViewState {
    return {
      id: 'aira_cloud',
      role: role,
      title: 'Aira 云同步',
      subtitle: role === 'active'
        ? '可配合浏览器插件跨系统同步书签'
        : (role === 'additional_backup'
          ? '普通同步成功后写入 Aira 云端'
          : (hasCloudConfig ? '已登录华为账号，可作为同步来源' : 'Aira Pro 提供官方托管的跨系统书签同步')),
      status: role === 'active' ? '当前同步方式' : (role === 'additional_backup' ? '附加备份已开启' : '未开启'),
      icon: $r('sys.symbol.icloud_fill'),
      imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
      iconBackgroundColor: iconBackgrounds.cloud,
      isActive: role === 'active',
      isEnabled: role !== 'available',
      isConfigured: hasCloudConfig,
      requiresPro: true
    };
  }

  private buildWebdavCard(
    role: 'active' | 'additional_backup' | 'available',
    settings: AiraSyncSettings,
    hasWebdavConfig: boolean,
    iconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet
  ): SyncSettingsProviderCardViewState {
    const endpoint = settings.webdav.endpoint.trim();
    return {
      id: 'webdav',
      role: role,
      title: 'WebDAV 同步',
      subtitle: role === 'active'
        ? (endpoint.length > 0 ? endpoint : '自定义服务')
        : (role === 'additional_backup'
          ? '普通同步成功后写入你的 WebDAV'
          : (hasWebdavConfig ? '已保存配置，可作为同步来源' : '免费使用自己的 WebDAV 服务同步书签')),
      status: role === 'active' ? '当前同步方式' : (role === 'additional_backup' ? '附加备份已开启' : '未开启'),
      icon: $r('sys.symbol.folder_fill'),
      imageIcon: SettingsColoredTileIconResources.foregroundIcon('webdav'),
      iconBackgroundColor: iconBackgrounds.webdav,
      isActive: role === 'active',
      isEnabled: role !== 'available',
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

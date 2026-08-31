import {
  DynamicAppIconAvailability,
  DynamicAppIconOption,
  DynamicAppIconQueryResult
} from '../../services/appicon/DynamicAppIconService';

export type AppIconSettingsAvailability = DynamicAppIconAvailability | 'loading';

export interface AppIconSettingsOptionState {
  id: string;
  title: string;
  iconUrl: string;
  isDefault: boolean;
  isSelected: boolean;
  isEnabled: boolean;
}

export interface AppIconSettingsState {
  title: string;
  availability: AppIconSettingsAvailability;
  options: AppIconSettingsOptionState[];
  statusText: string;
  footerText: string;
}

interface KnownDynamicAppIconMetadata {
  id: string;
  title: string;
  sortIndex: number;
}

const KNOWN_DYNAMIC_APP_ICONS: KnownDynamicAppIconMetadata[] = [
  { id: 'Aira_dark', title: '深色图标', sortIndex: 10 },
  { id: 'Aira_dark_pad', title: '平板深色图标', sortIndex: 11 },
  { id: 'Aira_blue', title: '蓝色图标', sortIndex: 20 },
  { id: 'Aira_blue_pad', title: '平板蓝色图标', sortIndex: 21 }
];

export class AppIconSettingsViewModel {
  buildLoadingState(): AppIconSettingsState {
    return {
      title: '应用图标',
      availability: 'loading',
      options: [],
      statusText: '正在读取应用图标...',
      footerText: '应用图标由华为应用市场图标管理服务提供，审核通过后会在这里显示。'
    };
  }

  buildState(result: DynamicAppIconQueryResult): AppIconSettingsState {
    const dynamicOptions = result.icons
      .filter((icon: DynamicAppIconOption): boolean => this.shouldShowDynamicIcon(icon.iconId))
      .map((icon: DynamicAppIconOption): AppIconSettingsOptionState => {
        return {
          id: icon.iconId,
          title: this.formatIconTitle(icon.iconId),
          iconUrl: icon.iconUrl,
          isDefault: false,
          isSelected: icon.enabled,
          isEnabled: true
        };
      })
      .sort((left: AppIconSettingsOptionState, right: AppIconSettingsOptionState): number => {
        return this.compareDynamicIconOptions(left, right);
      });
    const hasSelectedDynamicIcon = dynamicOptions.some((option: AppIconSettingsOptionState) => option.isSelected);
    return {
      title: '应用图标',
      availability: result.availability,
      options: this.buildDefaultOption(!hasSelectedDynamicIcon).concat(dynamicOptions),
      statusText: this.resolveStatusText(result),
      footerText: this.resolveFooterText(result.availability, result.code)
    };
  }

  private buildDefaultOption(isSelected: boolean): AppIconSettingsOptionState[] {
    return [
      {
        id: 'default',
        title: '默认图标',
        iconUrl: '',
        isDefault: true,
        isSelected: isSelected,
        isEnabled: true
      }
    ];
  }

  private resolveStatusText(result: DynamicAppIconQueryResult): string {
    if (result.availability === 'available') {
      return '';
    }
    if (result.message.length > 0) {
      return result.message;
    }
    return '暂无可用的应用图标。';
  }

  private resolveFooterText(availability: DynamicAppIconAvailability, code: number): string {
    if (availability === 'available') {
      return '切换后桌面图标会由系统更新；如果系统正在使用自定义主题图标，切换可能会失败。';
    }
    if (availability === 'empty') {
      return '需要先在 AppGallery Connect 图标管理中创建图标并通过审核，审核通过后会自动出现在这里。';
    }
    if (code > 0) {
      return `图标管理服务暂不可用，错误码 ${code}。`;
    }
    return '图标管理服务暂不可用。';
  }

  private formatIconTitle(iconId: string): string {
    const normalizedIconId = iconId.trim();
    const knownIcon = this.resolveKnownIconMetadata(normalizedIconId);
    if (knownIcon !== undefined) {
      return knownIcon.title;
    }
    return normalizedIconId.length > 0 ? normalizedIconId : '应用图标';
  }

  private shouldShowDynamicIcon(iconId: string): boolean {
    const normalizedIconId = iconId.trim();
    return normalizedIconId !== 'Aira_light' && normalizedIconId !== 'Aira_light_pad';
  }

  private compareDynamicIconOptions(left: AppIconSettingsOptionState, right: AppIconSettingsOptionState): number {
    const leftSortIndex = this.resolveIconSortIndex(left.id);
    const rightSortIndex = this.resolveIconSortIndex(right.id);
    if (leftSortIndex !== rightSortIndex) {
      return leftSortIndex - rightSortIndex;
    }
    if (left.id === right.id) {
      return 0;
    }
    return left.id < right.id ? -1 : 1;
  }

  private resolveIconSortIndex(iconId: string): number {
    const knownIcon = this.resolveKnownIconMetadata(iconId);
    return knownIcon?.sortIndex ?? 1000;
  }

  private resolveKnownIconMetadata(iconId: string): KnownDynamicAppIconMetadata | undefined {
    const normalizedIconId = iconId.trim();
    return KNOWN_DYNAMIC_APP_ICONS.find((icon: KnownDynamicAppIconMetadata) => icon.id === normalizedIconId);
  }
}

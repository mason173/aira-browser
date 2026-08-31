import {
  PersonalizationSyncConfig,
  PersonalizationSyncContentId,
  PersonalizationSyncItemId
} from '../../common/models/PersonalizationSyncModels';
import { BrowserSettingsIconBackgroundTokenSet } from '../../features/theme/BrowserThemePaletteModels';

export type PersonalizationSyncItemIconKey =
  | 'custom_homepage'
  | 'appearance'
  | 'activity_heatmap'
  | 'search'
  | 'bookshelf';

type PersonalizationSyncItemBackgroundRole =
  | 'sync'
  | 'appearance'
  | 'about'
  | 'search'
  | 'general';

interface PersonalizationSyncItemPresentationDescriptor {
  iconKey: PersonalizationSyncItemIconKey;
  backgroundRole: PersonalizationSyncItemBackgroundRole;
}

export interface PersonalizationSyncItemState {
  id: PersonalizationSyncContentId;
  title: string;
  summary: string;
  enabled: boolean;
}

export interface PersonalizationSyncSettingsState {
  title: string;
  summary: string;
  items: PersonalizationSyncItemState[];
}

export class PersonalizationSyncSettingsViewModel {
  buildDefaultState(
    config?: PersonalizationSyncConfig,
    novelBookshelfEnabled: boolean = true
  ): PersonalizationSyncSettingsState {
    return {
      title: '主页收藏、小说书架、活动和常用设置',
      summary: '选择需要在设备之间保持一致的主页收藏、小说书架、活动热力图和常用设置。',
      items: [
        {
          id: 'home_shortcuts',
          title: '主页收藏',
          summary: '同步主页收藏项目和排序',
          enabled: this.resolveEnabled(config, 'home_shortcuts')
        },
        {
          id: 'core_preferences',
          title: '核心偏好',
          summary: '同步主题和常用偏好',
          enabled: this.resolveEnabled(config, 'core_preferences')
        },
        {
          id: 'activity_heatmap',
          title: '活动热力图',
          summary: '同步每日活动统计',
          enabled: this.resolveEnabled(config, 'activity_heatmap')
        },
        {
          id: 'search',
          title: '搜索',
          summary: '同步搜索引擎和建议',
          enabled: this.resolveEnabled(config, 'search')
        },
        {
          id: 'novel_bookshelf',
          title: '小说书架',
          summary: '同步已收藏小说的链接、书籍信息和阅读进度',
          enabled: novelBookshelfEnabled
        }
      ]
    };
  }

  updateItemEnabled(
    state: PersonalizationSyncSettingsState,
    id: PersonalizationSyncContentId,
    enabled: boolean
  ): PersonalizationSyncSettingsState {
    return {
      title: state.title,
      summary: state.summary,
      items: state.items.map((item: PersonalizationSyncItemState): PersonalizationSyncItemState => {
        if (item.id !== id) {
          return {
            id: item.id,
            title: item.title,
            summary: item.summary,
            enabled: item.enabled
          };
        }
        return {
          id: item.id,
          title: item.title,
          summary: item.summary,
          enabled: enabled
        };
      })
    };
  }

  resolveItemIconKey(id: PersonalizationSyncContentId): PersonalizationSyncItemIconKey {
    return this.resolveItemPresentation(id).iconKey;
  }

  resolveItemIconBackgroundColor(
    id: PersonalizationSyncContentId,
    tokens: BrowserSettingsIconBackgroundTokenSet
  ): string {
    const role = this.resolveItemPresentation(id).backgroundRole;
    if (role === 'sync') {
      return tokens.sync;
    }
    if (role === 'appearance') {
      return tokens.appearance;
    }
    if (role === 'about') {
      return tokens.about;
    }
    if (role === 'search') {
      return tokens.search;
    }
    if (role === 'general') {
      return tokens.general;
    }
    return tokens.general;
  }

  resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private resolveEnabled(config: PersonalizationSyncConfig | undefined, id: PersonalizationSyncItemId): boolean {
    const item = config?.items.find((value) => value.id === id);
    return item === undefined ? true : item.enabled;
  }

  private resolveItemPresentation(id: PersonalizationSyncContentId): PersonalizationSyncItemPresentationDescriptor {
    if (id === 'home_shortcuts') {
      return { iconKey: 'custom_homepage', backgroundRole: 'sync' };
    }
    if (id === 'core_preferences') {
      return { iconKey: 'appearance', backgroundRole: 'appearance' };
    }
    if (id === 'activity_heatmap') {
      return { iconKey: 'activity_heatmap', backgroundRole: 'about' };
    }
    if (id === 'search') {
      return { iconKey: 'search', backgroundRole: 'search' };
    }
    if (id === 'novel_bookshelf') {
      return { iconKey: 'bookshelf', backgroundRole: 'general' };
    }
    return { iconKey: 'custom_homepage', backgroundRole: 'general' };
  }
}

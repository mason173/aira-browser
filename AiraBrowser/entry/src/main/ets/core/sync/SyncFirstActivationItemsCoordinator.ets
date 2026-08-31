import {
  PersonalizationSyncContentId
} from '../../common/models/PersonalizationSyncModels';
import {
  SyncBookmarkActivationProvider
} from './SyncActivationModels';
import {
  PersonalizationSyncItemState,
  PersonalizationSyncSettingsViewModel
} from './PersonalizationSyncSettingsViewModel';

export type SyncFirstActivationItemId = 'bookmarks' | 'history' | PersonalizationSyncContentId;

export interface SyncFirstActivationItemState {
  id: SyncFirstActivationItemId;
  title: string;
  summary: string;
  enabled: boolean;
  kind: 'bookmarks' | 'history' | 'personalization';
}

export interface SyncFirstActivationItemsState {
  title: string;
  summary: string;
  items: SyncFirstActivationItemState[];
}

export class SyncFirstActivationItemsCoordinator {
  private personalizationViewModel: PersonalizationSyncSettingsViewModel = new PersonalizationSyncSettingsViewModel();

  buildDefaultState(bookmarkProvider: SyncBookmarkActivationProvider = 'aira_cloud'): SyncFirstActivationItemsState {
    const personalizationState = this.personalizationViewModel.buildDefaultState();
    const items: SyncFirstActivationItemState[] = [
      {
        id: 'bookmarks',
        title: '书签',
        summary: bookmarkProvider === 'huawei_space'
          ? '同步本机书签、文件夹和排序到华为云空间'
          : '同步本机书签、文件夹和排序',
        enabled: true,
        kind: 'bookmarks'
      },
      {
        id: 'history',
        title: '历史记录',
        summary: '在支持的设备之间增量合并浏览历史',
        enabled: true,
        kind: 'history'
      }
    ];
    personalizationState.items.forEach((item: PersonalizationSyncItemState) => {
      items.push({
        id: item.id,
        title: item.title,
        summary: item.summary,
        enabled: item.enabled,
        kind: 'personalization'
      });
    });
    return {
      title: '选择同步内容',
      summary: '先选择要在设备之间保持一致的内容，下一步再选择同步方式。',
      items: items
    };
  }

  buildStateFromExperience(
    bookmarkEnabled: boolean,
    historyEnabled: boolean,
    personalizationItems: PersonalizationSyncItemState[]
  ): SyncFirstActivationItemsState {
    const state = this.buildDefaultState();
    return {
      title: state.title,
      summary: state.summary,
      items: state.items.map((item: SyncFirstActivationItemState): SyncFirstActivationItemState => {
        if (item.id === 'bookmarks') {
          return {
            id: item.id,
            title: item.title,
            summary: item.summary,
            enabled: bookmarkEnabled,
            kind: item.kind
          };
        }
        if (item.id === 'history') {
          return {
            id: item.id,
            title: item.title,
            summary: item.summary,
            enabled: historyEnabled,
            kind: item.kind
          };
        }
        const savedItem = personalizationItems.find((value: PersonalizationSyncItemState): boolean => {
          return value.id === item.id;
        });
        return {
          id: item.id,
          title: item.title,
          summary: item.summary,
          enabled: savedItem?.enabled ?? item.enabled,
          kind: item.kind
        };
      })
    };
  }

  updateItemEnabled(
    state: SyncFirstActivationItemsState,
    id: SyncFirstActivationItemId,
    enabled: boolean
  ): SyncFirstActivationItemsState {
    return {
      title: state.title,
      summary: state.summary,
      items: state.items.map((item: SyncFirstActivationItemState): SyncFirstActivationItemState => {
        return {
          id: item.id,
          title: item.title,
          summary: item.summary,
          enabled: item.id === id ? enabled : item.enabled,
          kind: item.kind
        };
      })
    };
  }

  hasSelectedItems(state: SyncFirstActivationItemsState): boolean {
    return state.items.some((item: SyncFirstActivationItemState) => item.enabled);
  }

}

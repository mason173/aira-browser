import {
  CustomHomepageItem,
  CustomHomepageSettings,
  normalizeCustomHomepageBooleanByItemId,
  normalizeCustomHomepageSystemSearchVisibilityByItemId
} from '../../common/models/CustomHomepageModels';

interface CustomHomepagePreferenceState {
  systemHomepageShowSystemSearchBar: boolean;
  showSystemSearchBarByItemId: Record<string, boolean>;
  showSystemEntryButtonByItemId: Record<string, boolean>;
  forceDarkWebContentByItemId: Record<string, boolean>;
  hideToolbarOnScrollByItemId: Record<string, boolean>;
  hideToolbarOnScroll: boolean;
}

export class CustomHomepagePreferenceService {
  buildSelectedSystemSearchBarSettings(
    current: CustomHomepageSettings,
    visible: boolean
  ): CustomHomepageSettings {
    return this.buildItemSystemSearchBarSettings(current, this.resolveSelectedItemId(current), visible);
  }

  buildItemSystemSearchBarSettings(
    current: CustomHomepageSettings,
    itemId: string,
    visible: boolean
  ): CustomHomepageSettings {
    return this.writeItemBoolean(current, itemId, 'search', visible);
  }

  buildSelectedSystemEntryButtonSettings(
    current: CustomHomepageSettings,
    visible: boolean
  ): CustomHomepageSettings {
    return this.buildItemSystemEntryButtonSettings(current, this.resolveSelectedItemId(current), visible);
  }

  buildItemSystemEntryButtonSettings(
    current: CustomHomepageSettings,
    itemId: string,
    visible: boolean
  ): CustomHomepageSettings {
    return this.writeItemBoolean(current, itemId, 'entry', visible);
  }

  buildSelectedForceDarkSettings(
    current: CustomHomepageSettings,
    enabled: boolean
  ): CustomHomepageSettings {
    return this.buildItemForceDarkSettings(current, this.resolveSelectedItemId(current), enabled);
  }

  buildItemForceDarkSettings(
    current: CustomHomepageSettings,
    itemId: string,
    enabled: boolean
  ): CustomHomepageSettings {
    return this.writeItemBoolean(current, itemId, 'dark', enabled);
  }

  buildSelectedHideToolbarOnScrollSettings(
    current: CustomHomepageSettings,
    enabled: boolean
  ): CustomHomepageSettings {
    return this.buildItemHideToolbarOnScrollSettings(current, this.resolveSelectedItemId(current), enabled);
  }

  buildItemHideToolbarOnScrollSettings(
    current: CustomHomepageSettings,
    itemId: string,
    enabled: boolean
  ): CustomHomepageSettings {
    return this.writeItemBoolean(current, itemId, 'scroll', enabled);
  }

  buildSystemHomepageSearchBarSettings(
    current: CustomHomepageSettings,
    visible: boolean
  ): CustomHomepageSettings {
    const preferences = this.buildPreferenceState(current);
    preferences.systemHomepageShowSystemSearchBar = visible;
    return this.buildSettings(current, preferences);
  }

  buildSystemHomepageHideToolbarOnScrollSettings(
    current: CustomHomepageSettings,
    enabled: boolean
  ): CustomHomepageSettings {
    const preferences = this.buildPreferenceState(current);
    preferences.hideToolbarOnScroll = enabled;
    return this.buildSettings(current, preferences);
  }

  private writeItemBoolean(
    current: CustomHomepageSettings,
    itemId: string,
    field: 'search' | 'entry' | 'dark' | 'scroll',
    value: boolean
  ): CustomHomepageSettings {
    const normalizedId = itemId.trim();
    const itemExists = current.items.some((item: CustomHomepageItem): boolean => item.id === normalizedId);
    if (normalizedId.length <= 0 || !itemExists) {
      return current;
    }
    const preferences = this.buildPreferenceState(current);
    if (field === 'search') {
      preferences.showSystemSearchBarByItemId[normalizedId] = value;
    } else if (field === 'entry') {
      preferences.showSystemEntryButtonByItemId[normalizedId] = value;
    } else if (field === 'dark') {
      preferences.forceDarkWebContentByItemId[normalizedId] = value;
    } else {
      preferences.hideToolbarOnScrollByItemId[normalizedId] = value;
    }
    return this.buildSettings(current, preferences);
  }

  private buildPreferenceState(current: CustomHomepageSettings): CustomHomepagePreferenceState {
    return {
      systemHomepageShowSystemSearchBar: current.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: normalizeCustomHomepageSystemSearchVisibilityByItemId(
        current.items,
        current.showSystemSearchBarByItemId
      ),
      showSystemEntryButtonByItemId: normalizeCustomHomepageBooleanByItemId(
        current.items,
        current.showSystemEntryButtonByItemId,
        false
      ),
      forceDarkWebContentByItemId: normalizeCustomHomepageBooleanByItemId(
        current.items,
        current.forceDarkWebContentByItemId,
        true
      ),
      hideToolbarOnScrollByItemId: normalizeCustomHomepageBooleanByItemId(
        current.items,
        current.hideToolbarOnScrollByItemId,
        false
      ),
      hideToolbarOnScroll: current.hideToolbarOnScroll
    };
  }

  private buildSettings(
    current: CustomHomepageSettings,
    preferences: CustomHomepagePreferenceState
  ): CustomHomepageSettings {
    return {
      mode: current.mode,
      selectedItemId: current.selectedItemId,
      items: current.items,
      updatedAt: Date.now(),
      systemHomepageShowSystemSearchBar: preferences.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: preferences.showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: preferences.showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: preferences.forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: preferences.hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: preferences.hideToolbarOnScroll
    };
  }

  private resolveSelectedItemId(current: CustomHomepageSettings): string {
    if (current.mode !== 'custom_html' || current.selectedItemId.length <= 0) {
      return '';
    }
    const selectedItem = current.items.find((item: CustomHomepageItem): boolean => {
      return item.id === current.selectedItemId;
    });
    return selectedItem?.id ?? '';
  }
}

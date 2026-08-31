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
    const selectedItemId = this.resolveSelectedItemId(current);
    if (selectedItemId.length <= 0) {
      return current;
    }
    const preferences = this.buildPreferenceState(current);
    preferences.showSystemSearchBarByItemId[selectedItemId] = visible;
    return this.buildSettings(current, preferences);
  }

  buildSelectedSystemEntryButtonSettings(
    current: CustomHomepageSettings,
    visible: boolean
  ): CustomHomepageSettings {
    const selectedItemId = this.resolveSelectedItemId(current);
    if (selectedItemId.length <= 0) {
      return current;
    }
    const preferences = this.buildPreferenceState(current);
    preferences.showSystemEntryButtonByItemId[selectedItemId] = visible;
    return this.buildSettings(current, preferences);
  }

  buildSelectedForceDarkSettings(
    current: CustomHomepageSettings,
    enabled: boolean
  ): CustomHomepageSettings {
    const selectedItemId = this.resolveSelectedItemId(current);
    if (selectedItemId.length <= 0) {
      return current;
    }
    const preferences = this.buildPreferenceState(current);
    preferences.forceDarkWebContentByItemId[selectedItemId] = enabled;
    return this.buildSettings(current, preferences);
  }

  buildSelectedHideToolbarOnScrollSettings(
    current: CustomHomepageSettings,
    enabled: boolean
  ): CustomHomepageSettings {
    const selectedItemId = this.resolveSelectedItemId(current);
    if (selectedItemId.length <= 0) {
      return current;
    }
    const preferences = this.buildPreferenceState(current);
    preferences.hideToolbarOnScrollByItemId[selectedItemId] = enabled;
    return this.buildSettings(current, preferences);
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

import { describe, expect, it } from '@ohos/hypium';
import { CustomHomepageRepositorySnapshot } from '../main/ets/common/models/CustomHomepageModels';
import { CustomHomepageSettingsViewModel } from '../main/ets/core/customhome/CustomHomepageSettingsViewModel';
import { SYSTEM_HOMEPAGE_STYLE_CATALOG } from '../main/ets/core/customhome/SystemHomepageStyleCatalog';

function buildSnapshot(mode: 'system' | 'custom_html', selectedItemId: string): CustomHomepageRepositorySnapshot {
  return {
    settings: {
      mode: mode,
      selectedItemId: selectedItemId,
      items: [],
      updatedAt: 0,
      systemHomepageShowSystemSearchBar: true,
      showSystemSearchBarByItemId: {},
      showSystemEntryButtonByItemId: {},
      forceDarkWebContentByItemId: {},
      hideToolbarOnScrollByItemId: {},
      hideToolbarOnScroll: true
    }
  };
}

export default function systemHomepageStyleCatalogTest(): void {
  describe('SystemHomepageStyleCatalog', () => {
    it('lists_every_built_in_homepage_style', 0, () => {
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG.length).assertEqual(2);
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[0].style).assertEqual('classic');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[0].title.length > 0).assertTrue();
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[1].style).assertEqual('centered');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[1].title.length > 0).assertTrue();
    });

    it('marks_only_the_style_the_new_tab_renders', 0, () => {
      const viewModel = new CustomHomepageSettingsViewModel();
      const centered = viewModel.buildState(buildSnapshot('system', ''), 'light', 'centered');
      expect(centered.systemChoices.length).assertEqual(SYSTEM_HOMEPAGE_STYLE_CATALOG.length);
      expect(centered.systemChoices[0].isActive).assertFalse();
      expect(centered.systemChoices[1].isActive).assertTrue();

      const classic = viewModel.buildState(buildSnapshot('system', ''), 'light', 'classic');
      expect(classic.systemChoices[0].isActive).assertTrue();
      expect(classic.systemChoices[1].isActive).assertFalse();
    });

    it('leaves_every_built_in_card_off_while_a_third_party_homepage_is_selected', 0, () => {
      const viewModel = new CustomHomepageSettingsViewModel();
      const state = viewModel.buildState(buildSnapshot('custom_html', 'home_1'), 'light', 'centered');
      expect(state.systemHomepageSelected).assertFalse();
      state.systemChoices.forEach((choice) => {
        expect(choice.isActive).assertFalse();
      });
    });
  });
}

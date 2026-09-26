import { describe, expect, it } from '@ohos/hypium';
import { CustomHomepageRepositorySnapshot } from '../main/ets/common/models/CustomHomepageModels';
import { CustomHomepagePreviewViewModel } from '../main/ets/core/customhome/CustomHomepagePreviewViewModel';
import { CustomHomepageSettingsViewModel } from '../main/ets/core/customhome/CustomHomepageSettingsViewModel';
import {
  resolveSystemHomepageToolbarChrome,
  SYSTEM_HOMEPAGE_STYLE_CATALOG
} from '../main/ets/core/customhome/SystemHomepageStyleCatalog';

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
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[0].title).assertEqual('经典主页');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[1].style).assertEqual('centered');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[1].title).assertEqual('简约主页');
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

    it('pairs_classic_with_floating_chrome_and_centered_with_split_chrome', 0, () => {
      expect(resolveSystemHomepageToolbarChrome('classic')).assertEqual('floating');
      expect(resolveSystemHomepageToolbarChrome('centered')).assertEqual('split');
    });

    it('orders_system_cards_before_third_party_and_focuses_the_current_one', 0, () => {
      const viewModel = new CustomHomepageSettingsViewModel();
      const cards = viewModel.buildCarouselCards(
        viewModel.buildState(buildSnapshot('system', ''), 'light', 'centered')
      );
      expect(cards.length).assertEqual(2);
      expect(cards[0].kind).assertEqual('system');
      expect(cards[0].systemStyle).assertEqual('classic');
      expect(cards[0].isCurrent).assertFalse();
      expect(cards[1].systemStyle).assertEqual('centered');
      expect(cards[1].isCurrent).assertTrue();
      expect(viewModel.resolveCarouselIndex(cards, '')).assertEqual(1);
      expect(viewModel.resolveCarouselIndex(cards, 'system:classic')).assertEqual(0);
    });

    it('keeps_carousel_cards_in_the_screen_aspect_ratio', 0, () => {
      const layout = new CustomHomepagePreviewViewModel().buildCarouselLayoutState({
        viewportWidth: 390,
        viewportHeight: 844,
        availableWidth: 390,
        availableHeight: 700
      });
      const ratio = layout.cardWidth / layout.cardHeight;
      expect(Math.abs(ratio - (390 / 844)) < 0.03).assertTrue();
      expect(layout.cardWidth < 390).assertTrue();
      expect(layout.sidePeek >= 16).assertTrue();
      expect(layout.cardWidth > 0).assertTrue();
      expect(layout.cardHeight > layout.cardWidth).assertTrue();
    });
  });
}

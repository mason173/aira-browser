import { describe, expect, it } from '@ohos/hypium';
import { CustomHomepageRepositorySnapshot } from '../main/ets/common/models/CustomHomepageModels';
import { CustomHomepagePreviewViewModel } from '../main/ets/core/customhome/CustomHomepagePreviewViewModel';
import { CustomHomepageSettingsViewModel } from '../main/ets/core/customhome/CustomHomepageSettingsViewModel';
import { resolveMountedSystemHomeFrame } from '../main/ets/common/models/HomePagePresentationSettingsModels';
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
    it('mounts_each_built_in_style_as_its_own_frame', 0, () => {
      expect(resolveMountedSystemHomeFrame('classic')).assertEqual('classic');
      expect(resolveMountedSystemHomeFrame('search_dock')).assertEqual('search_dock');
      expect(resolveMountedSystemHomeFrame('centered')).assertEqual('centered');
      expect(resolveMountedSystemHomeFrame('minimal')).assertEqual('minimal');
      expect(resolveMountedSystemHomeFrame('centered') === resolveMountedSystemHomeFrame('minimal')).assertFalse();
    });

    it('lists_every_built_in_homepage_style', 0, () => {
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG.length).assertEqual(4);
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[0].style).assertEqual('classic');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[0].title).assertEqual('经典主页');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[1].style).assertEqual('search_dock');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[1].title).assertEqual('搜索导航主页');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[2].style).assertEqual('centered');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[2].title).assertEqual('简约主页');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[3].style).assertEqual('minimal');
      expect(SYSTEM_HOMEPAGE_STYLE_CATALOG[3].title).assertEqual('极简主页');
    });

    it('marks_only_the_style_the_new_tab_renders', 0, () => {
      const viewModel = new CustomHomepageSettingsViewModel();
      const centered = viewModel.buildState(buildSnapshot('system', ''), 'light', 'centered');
      expect(centered.systemChoices.length).assertEqual(SYSTEM_HOMEPAGE_STYLE_CATALOG.length);
      expect(centered.systemChoices[0].isActive).assertFalse();
      expect(centered.systemChoices[2].isActive).assertTrue();

      const classic = viewModel.buildState(buildSnapshot('system', ''), 'light', 'classic');
      expect(classic.systemChoices[0].isActive).assertTrue();
      expect(classic.systemChoices[1].isActive).assertFalse();
      expect(classic.systemChoices[2].isActive).assertFalse();

      const searchDock = viewModel.buildState(buildSnapshot('system', ''), 'light', 'search_dock');
      expect(searchDock.systemChoices[1].isActive).assertTrue();
      expect(searchDock.systemChoices[0].isActive).assertFalse();

      const minimal = viewModel.buildState(buildSnapshot('system', ''), 'light', 'minimal');
      expect(minimal.systemChoices[3].isActive).assertTrue();
      expect(minimal.systemChoices[2].isActive).assertFalse();
    });

    it('leaves_every_built_in_card_off_while_a_third_party_homepage_is_selected', 0, () => {
      const viewModel = new CustomHomepageSettingsViewModel();
      const state = viewModel.buildState(buildSnapshot('custom_html', 'home_1'), 'light', 'centered');
      expect(state.systemHomepageSelected).assertFalse();
      state.systemChoices.forEach((choice) => {
        expect(choice.isActive).assertFalse();
      });
    });

    it('pairs_each_home_with_its_matching_chrome', 0, () => {
      expect(resolveSystemHomepageToolbarChrome('classic')).assertEqual('floating');
      expect(resolveSystemHomepageToolbarChrome('search_dock')).assertEqual('dock');
      expect(resolveSystemHomepageToolbarChrome('centered')).assertEqual('split');
      expect(resolveSystemHomepageToolbarChrome('minimal')).assertEqual('split');
    });

    it('orders_system_cards_before_third_party_and_focuses_the_current_one', 0, () => {
      const viewModel = new CustomHomepageSettingsViewModel();
      const cards = viewModel.buildCarouselCards(
        viewModel.buildState(buildSnapshot('system', ''), 'light', 'centered')
      );
      expect(cards.length).assertEqual(4);
      expect(cards[0].kind).assertEqual('system');
      expect(cards[0].systemStyle).assertEqual('classic');
      expect(cards[0].isCurrent).assertFalse();
      expect(cards[1].systemStyle).assertEqual('search_dock');
      expect(cards[1].isCurrent).assertFalse();
      expect(cards[2].systemStyle).assertEqual('centered');
      expect(cards[2].isCurrent).assertTrue();
      expect(cards[3].systemStyle).assertEqual('minimal');
      expect(cards[3].title).assertEqual('极简主页');
      expect(cards[3].isCurrent).assertFalse();
      expect(viewModel.resolveCarouselIndex(cards, '')).assertEqual(2);
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

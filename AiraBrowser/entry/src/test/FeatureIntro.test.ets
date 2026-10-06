import { describe, expect, it } from '@ohos/hypium';
import { FeatureIntroViewModel } from '../main/ets/core/onboarding/FeatureIntroViewModel';
import { resolveFeatureIntroLayout } from '../main/ets/core/onboarding/FeatureIntroLayoutPolicy';
import {
  clampFeatureIntroGateDrag,
  featureIntroGateBackdropColor,
  isFeatureIntroGateUnlocked,
  resolveFeatureIntroGateLogoTop,
  resolveFeatureIntroGateTravel
} from '../main/ets/core/onboarding/FeatureIntroGatePolicy';
import {
  resolveFeatureIntroExitDestination,
  resolveInitialOnboardingDestination,
  shouldResumeFeatureIntroSlides
} from '../main/ets/core/onboarding/FeatureIntroRoutePolicy';
import {
  FeatureIntroSearchEngineViewModel,
  resolveFeatureIntroSearchEngineChoice
} from '../main/ets/core/onboarding/FeatureIntroSearchEngineViewModel';
import {
  FeatureIntroHomepageViewModel,
  resolveFeatureIntroHomepageStyle
} from '../main/ets/core/onboarding/FeatureIntroHomepageViewModel';
import {
  FeatureIntroAppearanceViewModel,
  resolveFeatureIntroAppearancePalette,
  resolveFeatureIntroAppearanceTabStyle,
  resolveFeatureIntroDesktopTabPlacement,
  resolveFeatureIntroAppearanceThemeMode
} from '../main/ets/core/onboarding/FeatureIntroAppearanceViewModel';

export default function featureIntroTest(): void {
  describe('FeatureIntroViewModel', () => {
    it('keeps the four first-open slides in order', 0, () => {
      const slides = new FeatureIntroViewModel().slides();

      expect(slides.length).assertEqual(4);
      expect(slides[0].id).assertEqual('ad_block');
      expect(slides[0].title).assertEqual('少一点广告打扰');
      expect(slides[1].id).assertEqual('video_takeover');
      expect(slides[1].title).assertEqual('接管网页视频');
      expect(slides[2].id).assertEqual('user_scripts');
      expect(slides[2].title).assertEqual('支持用户脚本');
      expect(slides[3].id).assertEqual('sync');
      expect(slides[3].title).assertEqual('换一台，接着用');
    });

    it('uses next on every slide, including the last', 0, () => {
      const viewModel = new FeatureIntroViewModel();

      expect(viewModel.actionLabel(0)).assertEqual('下一步');
      expect(viewModel.actionLabel(2)).assertEqual('下一步');
      expect(viewModel.isLast(2)).assertFalse();
      expect(viewModel.actionLabel(3)).assertEqual('下一步');
      expect(viewModel.isLast(3)).assertTrue();
      expect(viewModel.gateActionLabel()).assertEqual('向右滑动开始使用');
      expect(viewModel.gateSkipLabel()).assertEqual('跳过');
      expect(viewModel.skipConfirmTitle()).assertEqual('跳过介绍');
      expect(viewModel.skipConfirmMessage()).assertEqual('跳过后将直接进入主页，不再显示这些介绍。');
      expect(viewModel.skipConfirmCancelLabel()).assertEqual('取消');
      expect(viewModel.skipConfirmEnterLabel()).assertEqual('进入主页');
    });
  });

  describe('featureIntroGate', () => {
    it('uses a black backdrop in dark mode and white otherwise', 0, () => {
      expect(featureIntroGateBackdropColor('dark')).assertEqual('#000000');
      expect(featureIntroGateBackdropColor('light')).assertEqual('#FFFFFF');
    });

    it('unlocks only after the knob travels almost the full track', 0, () => {
      const travel = resolveFeatureIntroGateTravel(320);

      expect(clampFeatureIntroGateDrag(-20, travel)).assertEqual(0);
      expect(clampFeatureIntroGateDrag(travel + 40, travel)).assertEqual(travel);
      expect(isFeatureIntroGateUnlocked(travel * 0.5, travel)).assertFalse();
      expect(isFeatureIntroGateUnlocked(travel * 0.86, travel)).assertTrue();
      expect(isFeatureIntroGateUnlocked(10, 0)).assertFalse();
    });

    it('keeps the logo in the upper middle without covering the slider', 0, () => {
      const phoneTop = resolveFeatureIntroGateLogoTop(844, 36, 108);
      const shortTop = resolveFeatureIntroGateLogoTop(480, 24, 96);

      expect(phoneTop).assertEqual(236);
      expect(shortTop < 480 - 96 - 120).assertTrue();
    });
  });

  describe('resolveFeatureIntroLayout', () => {
    it('keeps a phone slot near 9:8', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 390,
        windowHeightVp: 844,
        topInsetVp: 36,
        bottomInsetVp: 28
      });

      expect(layout.videoHeightVp).assertEqual(347);
      expect(layout.videoWidthVp).assertEqual(0);
      expect(layout.contentMaxWidthVp).assertEqual(430);
      expect(layout.bottomPaddingVp).assertEqual(28);
    });

    it('shrinks the slot on a short window so the copy still fits', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 360,
        windowHeightVp: 520,
        topInsetVp: 24,
        bottomInsetVp: 16
      });

      expect(layout.videoHeightVp).assertEqual(244);
      expect(layout.videoWidthVp).assertEqual(0);
    });

    it('grows a portrait tablet slot to the real 9:8 frame', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 800,
        windowHeightVp: 1200,
        topInsetVp: 32,
        bottomInsetVp: 24
      });

      expect(layout.videoHeightVp).assertEqual(711);
      expect(layout.videoWidthVp).assertEqual(0);
      expect(layout.horizontalPaddingVp).assertEqual(24);
    });

    it('centers a whole frame on a landscape window', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 1280,
        windowHeightVp: 800,
        topInsetVp: 24,
        bottomInsetVp: 16
      });

      expect(layout.videoHeightVp).assertEqual(524);
      expect(layout.videoWidthVp).assertEqual(590);
    });

    it('does not invent a slot from empty measurements', 0, () => {
      const layout = resolveFeatureIntroLayout({
        windowWidthVp: 0,
        windowHeightVp: -1,
        topInsetVp: 0,
        bottomInsetVp: 0
      });

      expect(layout.videoHeightVp).assertEqual(0);
    });
  });

  describe('featureIntroSearchEngine', () => {
    it('offers six built-in engines, with Bing selected by default', 0, () => {
      const viewModel = new FeatureIntroSearchEngineViewModel();
      const choices = viewModel.choices();

      expect(viewModel.title()).assertEqual('选择默认搜索引擎');
      expect(viewModel.continueLabel()).assertEqual('下一步');
      expect(viewModel.skipLabel()).assertEqual('跳过');
      expect(viewModel.defaultChoiceId()).assertEqual('bing');
      expect(choices.length).assertEqual(6);
      expect(choices[0].id).assertEqual('bing');
      expect(choices[0].label).assertEqual('必应');
      expect(choices[1].id).assertEqual('baidu');
      expect(choices[1].label).assertEqual('百度');
      expect(choices[2].id).assertEqual('google');
      expect(choices[2].label).assertEqual('谷歌');
      expect(choices[3].id).assertEqual('sogou');
      expect(choices[3].label).assertEqual('搜狗');
      expect(choices[4].id).assertEqual('qihoo');
      expect(choices[4].label).assertEqual('360搜索');
      expect(choices[5].id).assertEqual('shenma');
      expect(choices[5].label).assertEqual('神马');
      expect(resolveFeatureIntroSearchEngineChoice('sogou')).assertEqual('sogou');
      expect(resolveFeatureIntroSearchEngineChoice('qihoo')).assertEqual('qihoo');
      expect(resolveFeatureIntroSearchEngineChoice('shenma')).assertEqual('shenma');
      expect(resolveFeatureIntroSearchEngineChoice('brave')).assertEqual('bing');
    });
  });

  describe('featureIntroHomepage', () => {
    it('offers the built-in homepage cards, with classic selected by default', 0, () => {
      const viewModel = new FeatureIntroHomepageViewModel();
      const choices = viewModel.choices(viewModel.defaultStyle());

      expect(viewModel.title()).assertEqual('选择主页样式');
      expect(viewModel.continueLabel()).assertEqual('下一步');
      expect(viewModel.previousLabel()).assertEqual('上一步');
      expect(viewModel.skipLabel()).assertEqual('跳过');
      expect(viewModel.defaultStyle()).assertEqual('classic');
      expect(choices.length).assertEqual(4);
      expect(choices[0].style).assertEqual('classic');
      expect(choices[0].title).assertEqual('经典主页');
      expect(choices[0].isActive).assertTrue();
      expect(choices[1].style).assertEqual('search_dock');
      expect(choices[1].title).assertEqual('搜索导航主页');
      expect(choices[1].isActive).assertFalse();
      expect(choices[2].style).assertEqual('centered');
      expect(choices[2].title).assertEqual('简约主页');
      expect(choices[2].isActive).assertFalse();
      expect(choices[3].style).assertEqual('minimal');
      expect(choices[3].title).assertEqual('极简主页');
      expect(choices[3].isActive).assertFalse();
      expect(viewModel.cards('classic').length).assertEqual(4);
      expect(viewModel.cards('classic')[0].kind).assertEqual('system');
      expect(viewModel.cards('search_dock')[1].isCurrent).assertTrue();
      expect(viewModel.cards('centered')[2].isCurrent).assertTrue();
      expect(viewModel.cards('minimal')[3].isCurrent).assertTrue();
      expect(resolveFeatureIntroHomepageStyle('centered')).assertEqual('centered');
      expect(resolveFeatureIntroHomepageStyle('minimal')).assertEqual('minimal');
      expect(resolveFeatureIntroHomepageStyle('search_dock')).assertEqual('search_dock');
      expect(resolveFeatureIntroHomepageStyle('other')).assertEqual('classic');
    });
  });

  describe('featureIntroAppearance', () => {
    it('offers six theme colors and the four tab styles, with the defaults selected', 0, () => {
      const viewModel = new FeatureIntroAppearanceViewModel();
      const palettes = viewModel.palettes(viewModel.defaultPaletteId());
      const tabs = viewModel.tabOptions(viewModel.defaultTabStyle());

      expect(viewModel.title()).assertEqual('选择外观');
      expect(viewModel.themeSectionTitle()).assertEqual('主题色');
      expect(viewModel.tabSectionTitle()).assertEqual('标签页样式');
      expect(viewModel.continueLabel()).assertEqual('下一步');
      expect(viewModel.previousLabel()).assertEqual('上一步');
      expect(viewModel.skipLabel()).assertEqual('跳过');
      expect(viewModel.defaultPaletteId()).assertEqual('default');
      expect(viewModel.defaultTabStyle()).assertEqual('grid');
      expect(palettes.length).assertEqual(6);
      expect(palettes[0].id).assertEqual('default');
      expect(palettes[0].title).assertEqual('默认');
      expect(palettes[0].isSelected).assertTrue();
      expect(palettes[1].id).assertEqual('aurora');
      expect(palettes[1].title).assertEqual('晨屿');
      expect(palettes[2].id).assertEqual('cedar');
      expect(palettes[3].id).assertEqual('indigo');
      expect(palettes[4].id).assertEqual('amber');
      expect(palettes[5].id).assertEqual('coral');
      expect(palettes[5].title).assertEqual('橙潮');
      expect(palettes[5].isSelected).assertFalse();
      expect(tabs.length).assertEqual(4);
      expect(tabs[0].style).assertEqual('grid');
      expect(tabs[0].title).assertEqual('卡片平铺');
      expect(tabs[0].isSelected).assertTrue();
      expect(tabs[1].style).assertEqual('horizontal_cards');
      expect(tabs[1].title).assertEqual('横向大卡片');
      expect(tabs[1].isSelected).assertFalse();
      expect(tabs[2].style).assertEqual('stack');
      expect(tabs[2].title).assertEqual('堆叠式');
      expect(tabs[3].style).assertEqual('list');
      expect(tabs[3].title).assertEqual('列表式');
      expect(tabs[3].isSelected).assertFalse();
      expect(viewModel.palettes('coral')[5].isSelected).assertTrue();
      expect(viewModel.tabOptions('stack')[2].isSelected).assertTrue();
      expect(viewModel.tabOptions('list')[3].isSelected).assertTrue();
      expect(resolveFeatureIntroAppearancePalette('indigo')).assertEqual('indigo');
      expect(resolveFeatureIntroAppearancePalette('sage')).assertEqual('default');
      expect(resolveFeatureIntroAppearanceTabStyle('horizontal_cards')).assertEqual('horizontal_cards');
      expect(resolveFeatureIntroAppearanceTabStyle('list')).assertEqual('list');
      expect(resolveFeatureIntroAppearanceTabStyle('other')).assertEqual('grid');
      const desktopTabs = viewModel.desktopTabOptions(viewModel.defaultDesktopTabPlacement());
      expect(viewModel.defaultDesktopTabPlacement()).assertEqual('horizontal');
      expect(desktopTabs.length).assertEqual(2);
      expect(desktopTabs[0].placement).assertEqual('horizontal');
      expect(desktopTabs[0].title).assertEqual('水平标签页');
      expect(desktopTabs[0].isSelected).assertTrue();
      expect(desktopTabs[1].placement).assertEqual('vertical');
      expect(desktopTabs[1].title).assertEqual('竖向标签页');
      expect(desktopTabs[1].isSelected).assertFalse();
      expect(viewModel.desktopTabOptions('vertical')[1].isSelected).assertTrue();
      expect(resolveFeatureIntroDesktopTabPlacement('vertical')).assertEqual('vertical');
      expect(resolveFeatureIntroDesktopTabPlacement('other')).assertEqual('horizontal');
      const themeModes = viewModel.themeModes('system');
      expect(themeModes.length).assertEqual(3);
      expect(themeModes[0].mode).assertEqual('dark');
      expect(themeModes[0].title).assertEqual('深色');
      expect(themeModes[0].isSelected).assertFalse();
      expect(themeModes[1].mode).assertEqual('light');
      expect(themeModes[1].title).assertEqual('浅色');
      expect(themeModes[2].mode).assertEqual('system');
      expect(themeModes[2].title).assertEqual('系统');
      expect(themeModes[2].isSelected).assertTrue();
      expect(viewModel.themeModes('dark')[0].isSelected).assertTrue();
      expect(resolveFeatureIntroAppearanceThemeMode('light')).assertEqual('light');
      expect(resolveFeatureIntroAppearanceThemeMode('other')).assertEqual('system');
      expect(viewModel.previewTokens('coral', 'light').accent).assertEqual('#D36559');
      expect(viewModel.previewTokens('coral', 'dark').accent).assertEqual('#F29B91');
      expect(viewModel.previewTokens('sage', 'light').accent).assertEqual('#0A59F7');
    });
  });

  describe('resolveInitialOnboardingDestination', () => {
    it('restarts the intro until the user has entered the browser', 0, () => {
      expect(resolveInitialOnboardingDestination(false, false)).assertEqual('feature_intro');
      expect(resolveInitialOnboardingDestination(true, false)).assertEqual('feature_intro');
      expect(resolveInitialOnboardingDestination(false, true)).assertEqual('browser');
      expect(resolveInitialOnboardingDestination(true, true)).assertEqual('browser');
    });

    it('returns to the sync welcome after the feature intro on a new install', 0, () => {
      expect(resolveFeatureIntroExitDestination(false)).assertEqual('startup_welcome');
      expect(resolveFeatureIntroExitDestination(true)).assertEqual('browser');
    });

    it('resumes the intro slides only for the search-engine back navigation', 0, () => {
      expect(shouldResumeFeatureIntroSlides('1')).assertTrue();
      expect(shouldResumeFeatureIntroSlides(undefined)).assertFalse();
      expect(shouldResumeFeatureIntroSlides('')).assertFalse();
    });
  });
}

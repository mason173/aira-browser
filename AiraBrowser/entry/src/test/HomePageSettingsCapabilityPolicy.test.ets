import { describe, expect, it } from '@ohos/hypium';
import { HomePageRecoveryEntryPolicyService } from '../main/ets/services/settings/HomePageRecoveryEntryPolicyService';
import {
  resolveHomePageRecoveryEntries,
  resolveHomePageSettingsCapabilities,
  resolveHomePageSettingsRecoveryFooter
} from '../main/ets/services/settings/HomePageSettingsCapabilityPolicy';

export default function homePageSettingsCapabilityPolicyTest(): void {
  describe('HomePageSettingsCapabilityPolicy', () => {
    it('keeps_the_classic_sheet_complete', 0, () => {
      const capabilities = resolveHomePageSettingsCapabilities('classic');
      expect(capabilities.recentlyClosed).assertTrue();
      expect(capabilities.systemSearch).assertTrue();
      expect(capabilities.compactFavorites).assertTrue();
      expect(capabilities.favoritesTitle).assertTrue();
      expect(capabilities.iconCornerRadius).assertTrue();
      expect(resolveHomePageRecoveryEntries('classic').length).assertEqual(3);
      expect(resolveHomePageSettingsRecoveryFooter('classic'))
        .assertEqual('收藏、最近关闭和主页设置按钮至少保留一项。');
    });

    it('hides_controls_the_centered_frame_does_not_honor', 0, () => {
      const capabilities = resolveHomePageSettingsCapabilities('centered');
      expect(capabilities.wallpaper).assertTrue();
      expect(capabilities.favorites).assertTrue();
      expect(capabilities.shortcutNames).assertTrue();
      expect(capabilities.iconSize).assertTrue();
      expect(capabilities.compactFavorites).assertFalse();
      expect(capabilities.favoritesTitle).assertFalse();
      expect(capabilities.iconCornerRadius).assertFalse();
      expect(capabilities.recentlyClosed).assertFalse();
      expect(capabilities.systemSearch).assertFalse();
      expect(capabilities.settingsButton).assertFalse();
      expect(resolveHomePageRecoveryEntries('centered').length).assertEqual(0);
      expect(resolveHomePageSettingsRecoveryFooter('centered'))
        .assertEqual('主页设置入口固定显示，不可移除。');
    });

    it('keeps_the_pinned_centered_settings_tile_out_of_recovery', 0, () => {
      const policy = new HomePageRecoveryEntryPolicyService();
      const centeredEntries = resolveHomePageRecoveryEntries('centered');
      const current = {
        showFavorites: true,
        showRecentlyClosed: true,
        showSettingsButton: false
      };
      // The pinned tile always exists on that frame, so hiding favorites stays allowed.
      expect(policy.resolveChange('favorites', false, current, centeredEntries).allowed).assertTrue();
      // ...and the frame never rewrites the stored classic settings-button flag.
      expect(policy.resolveSettingsButtonVisibility({
        showFavorites: false,
        showRecentlyClosed: false,
        showSettingsButton: false
      }, centeredEntries)).assertFalse();
    });

    it('still_counts_recently_closed_on_the_classic_frame', 0, () => {
      const policy = new HomePageRecoveryEntryPolicyService();
      const decision = policy.resolveChange('favorites', false, {
        showFavorites: true,
        showRecentlyClosed: true,
        showSettingsButton: false
      });
      expect(decision.allowed).assertTrue();
      expect(policy.resolveSettingsButtonVisibility({
        showFavorites: false,
        showRecentlyClosed: true,
        showSettingsButton: false
      })).assertFalse();
    });
  });
}

import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserLargeScreenTabTitleSlotInput,
  resolveBrowserLargeScreenTabDisplayTitle,
  resolveBrowserLargeScreenTabTitleSlots
} from '../main/ets/core/browser/BrowserLargeScreenTabTitleSlotPolicy';
import {
  BrowserLargeScreenTabProjection,
  BrowserLargeScreenTabProjectionInput,
  BrowserLargeScreenTabStripFacts,
  BrowserLargeScreenTabStripViewModel
} from '../main/ets/core/browser/BrowserLargeScreenTabStripViewModel';

export default function browserLargeScreenTabTitleSlotPolicyTest(): void {
  describe('BrowserLargeScreenTabTitleSlotPolicy', () => {
    it('keeps roomy insets when the title slot can already show a fragment', 0, () => {
      const slot = resolveBrowserLargeScreenTabTitleSlots([tabInput(240, 'GitHub')])[0];
      expect(slot.visible).assertTrue();
      expect(slot.widthVp).assertEqual(162);
      expect(slot.leadingPaddingVp).assertEqual(16);
      expect(slot.trailingPaddingVp).assertEqual(10);
    });

    it('gives compressed padding to the title instead of collapsing a medium tab to dots', 0, () => {
      const slot = resolveBrowserLargeScreenTabTitleSlots([tabInput(122, '小红书 - 你的生活指南')])[0];
      expect(slot.visible).assertTrue();
      expect(slot.widthVp).assertEqual(62);
      expect(slot.leadingPaddingVp).assertEqual(8);
      expect(slot.contentEndPaddingVp).assertEqual(0);
      expect(slot.widthVp >= 56).assertTrue();
    });

    it('uses the same compressed insets for every tab once one title would be clipped', 0, () => {
      const slots = resolveBrowserLargeScreenTabTitleSlots([
        tabInput(240, 'GitHub'),
        tabInput(122, '小红书')
      ]);
      expect(slots[0].leadingPaddingVp).assertEqual(8);
      expect(slots[1].leadingPaddingVp).assertEqual(8);
      expect(slots[0].widthVp).assertEqual(180);
      expect(slots[1].visible).assertTrue();
    });

    it('hides the title when the slot cannot fit one glyph before the ellipsis', 0, () => {
      const slot = resolveBrowserLargeScreenTabTitleSlots([tabInput(64, '小红书')])[0];
      expect(slot.visible).assertFalse();
      expect(slot.widthVp).assertEqual(0);
    });

    it('keeps pinned tabs icon-only', 0, () => {
      const slot = resolveBrowserLargeScreenTabTitleSlots([{
        tabWidthVp: 40,
        title: 'GitHub',
        pinned: true,
        closable: true,
        hasAudioAction: false
      }])[0];
      expect(slot.visible).assertFalse();
      expect(slot.widthVp).assertEqual(0);
    });

    it('reserves the audio action without hiding a title that still fits', 0, () => {
      const quiet = resolveBrowserLargeScreenTabTitleSlots([tabInput(180, '微博')])[0];
      const audible = resolveBrowserLargeScreenTabTitleSlots([tabInput(180, '微博', true)])[0];
      expect(quiet.visible).assertTrue();
      expect(audible.visible).assertTrue();
      expect(quiet.widthVp - audible.widthVp).assertEqual(28);
    });

    it('falls back to the new-tab label before deciding the slot', 0, () => {
      expect(resolveBrowserLargeScreenTabDisplayTitle('  ')).assertEqual('新标签页');
      const slot = resolveBrowserLargeScreenTabTitleSlots([tabInput(160, '   ')])[0];
      expect(slot.visible).assertTrue();
    });
  });

  describe('BrowserLargeScreenTabStripViewModel title slots', () => {
    it('shows a real title fragment on a packed desktop strip', 0, () => {
      const presentation = new BrowserLargeScreenTabStripViewModel().resolvePresentation(stripFacts(8));
      expect(presentation.visibleTabs.length).assertEqual(8);
      presentation.visibleTabs.forEach((tab: BrowserLargeScreenTabProjection): void => {
        expect(tab.titleSlot.visible).assertTrue();
        expect(tab.titleSlot.widthVp >= 72).assertTrue();
        expect(tab.titleSlot.leadingPaddingVp).assertEqual(8);
      });
      expect(presentation.visibleTabs[0].titleSlot.widthVp).assertEqual(106);
      expect(presentation.visibleTabs[1].titleSlot.widthVp).assertEqual(79);
    });
  });
}

function tabInput(
  tabWidthVp: number,
  title: string,
  hasAudioAction: boolean = false
): BrowserLargeScreenTabTitleSlotInput {
  return {
    tabWidthVp: tabWidthVp,
    title: title,
    pinned: false,
    closable: true,
    hasAudioAction: hasAudioAction
  };
}

function stripFacts(tabCount: number): BrowserLargeScreenTabStripFacts {
  const tabs: BrowserLargeScreenTabProjectionInput[] = [];
  for (let index = 0; index < tabCount; index++) {
    tabs.push({
      id: `tab-${index}`,
      title: index === 0 ? 'GitHub' : '小红书 - 你的生活指南',
      url: 'https://example.com',
      active: index === 0,
      closable: true,
      loading: false,
      muted: false,
      privateMode: false,
      reloadable: true,
      pinned: false,
      audible: false
    });
  }
  return {
    availableWidthVp: 1280,
    titleButtonWidthVp: 0,
    titleButtonHeightVp: 40,
    windowTitleBarIntegrated: false,
    windowProfile: 'expanded',
    inputProfile: 'pointer',
    activeTabId: 'tab-0',
    dragSupported: true,
    tabs: tabs,
    policy: {
      minimumTabWidthVp: 64,
      maximumTabWidthVp: 240,
      compactTabWidthVp: 64,
      selectedTabExtraWidthVp: 24,
      fixedChromeWidthVp: 140
    }
  };
}

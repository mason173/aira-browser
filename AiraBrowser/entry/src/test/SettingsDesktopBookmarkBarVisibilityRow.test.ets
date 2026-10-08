import { describe, expect, it } from '@ohos/hypium';
import { isAppString } from '../main/ets/core/resources/AppResourceText';
import {
  BrowserAppearanceSettings,
  BrowserExperimentSettings,
  BrowserRetentionSettings,
  DesktopBookmarkBarVisibility
} from '../main/ets/common/models/BrowserModels';
import {
  buildDesktopBookmarkBarBlankMenuModel,
  BrowserDesktopBookmarkBarMenuItem
} from '../main/ets/core/browser/BrowserDesktopBookmarkBarMenuModel';
import {
  DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES
} from '../main/ets/core/browser/DesktopBookmarkBarVisibility';
import {
  SettingsDetailGroupState,
  SettingsDetailOption,
  SettingsDetailRowState,
  SettingsDetailState,
  SettingsDetailViewModel,
  SettingsGeneralDisplayState,
  SettingsSitePermissionsDisplayState
} from '../main/ets/core/settings/SettingsDetailViewModel';

const DESKTOP_BOOKMARK_BAR_GROUP_ID: string = 'desktop_bookmark_bar';
const DESKTOP_BOOKMARK_BAR_ROW_ID: string = 'desktop_bookmark_bar';
const DESKTOP_BOOKMARK_BAR_ROW_ACTION: string = 'set_desktop_bookmark_bar_visibility';

function appearance(
  showDesktopBookmarkBar: boolean,
  visibility?: DesktopBookmarkBarVisibility
): BrowserAppearanceSettings {
  const settings: BrowserAppearanceSettings = {
    bottomToolbarScrollBehavior: 'compact',
    toolbarChromeStyle: 'floating',
    globalImmersionEnabled: false,
    alwaysTopImmersionEnabled: false,
    forceDarkWebContentEnabled: true,
    blurPrivateTabPreviews: true,
    showHomeRecentlyClosed: true,
    showHomeShortcuts: true,
    homeRecentlyClosedLimit: 8,
    homeShortcutLayoutDensity: 'standard',
    homeShortcutIconSizeRatio: 0.54,
    siteIconCornerRadiusRatio: 0.3,
    themePaletteId: 'default',
    tabsOverviewLayoutStyle: 'grid',
    tabsOverviewCloseButtonAlwaysVisible: false,
    showDesktopBookmarkBar: showDesktopBookmarkBar
  };
  if (visibility !== undefined) {
    settings.desktopBookmarkBarVisibility = visibility;
  }
  return settings;
}

function generalState(): SettingsGeneralDisplayState {
  return {
    homeLayoutLabel: '搜索和书签',
    customHomepageLabel: '系统主页',
    startupBehaviorLabel: '恢复常规标签',
    tabAutoCloseLabel: '不自动关闭',
    defaultBrowserLabel: '由系统设置管理',
    historyRetentionLabel: '10000 条',
    privateBrowsingLabel: '关闭后不恢复',
    privateModeAuthenticationEnabled: false,
    alwaysUsePrivateMode: false,
    privateModePreserveCookiesOnClose: false,
    enhancedTrackingProtectionEnabled: false,
    allowUserScriptsInPrivateMode: true
  };
}

function experimentState(): BrowserExperimentSettings {
  return {
    pauseWebAnimationsDuringScroll: false,
    reduceMediaMotionDuringScroll: false,
    strengthenAdBlockingForSmoothScroll: false,
    pullRefreshEnabled: true,
    forceEnableWebZoom: false,
    webBottomSafeAreaEnabled: true,
    smartGripTabsActionsEnabled: false,
    webVideoTakeoverEnabled: false,
    novelModeEnabled: false,
    novelAutoTakeoverEnabled: false,
    appProxyActiveProfileId: '',
    appProxyProfiles: [],
    appProxyEnabled: false,
    appProxy: {
      scheme: 'http',
      host: '',
      port: 0,
      username: '',
      password: '',
      bypassHosts: 'localhost,127.0.0.1,::1',
      updatedAt: 0
    }
  };
}

function retentionState(): BrowserRetentionSettings {
  return {
    profileId: 'balanced',
    deviceTierHint: 'auto',
    maxMountedRuntimeTabs: 15,
    maxHotBackgroundTabs: 5,
    maxWarmBackgroundTabs: 10,
    hotBackgroundMaxAgeMs: 30 * 60 * 1000,
    warmBackgroundMaxAgeMs: 24 * 60 * 60 * 1000,
    staleAfterMs: 24 * 60 * 60 * 1000
  };
}

function sitePermissionState(): SettingsSitePermissionsDisplayState {
  return {
    savedOriginCount: 0,
    allowRuleCount: 0,
    blockRuleCount: 0,
    askRuleCount: 0,
    defaults: {
      camera: 'ask',
      microphone: 'ask',
      location: 'ask',
      sensor: 'ask',
      clipboard: 'ask'
    },
    defaultCapabilities: [],
    canClearPermissions: false,
    summaryLine: ''
  };
}

function appearanceDetailState(
  appearanceSettings: BrowserAppearanceSettings,
  isLargeScreen: boolean
): SettingsDetailState {
  return new SettingsDetailViewModel().buildState(
    'appearance_toolbar',
    '',
    '',
    'system',
    'bing',
    generalState(),
    {
      acceptCookies: true,
      acceptThirdPartyCookies: true,
      thirdPartyCookiePolicyLocked: false
    },
    { appOpenPolicy: 'ask' },
    appearanceSettings,
    experimentState(),
    retentionState(),
    sitePermissionState(),
    { appName: 'Aira', bundleName: 'org.aira.browser', versionName: '1.0.0', versionCode: '1' },
    false,
    'full',
    isLargeScreen,
    false,
    '自动',
    '系统 DNS',
    false
  );
}

function bookmarkBarRow(state: SettingsDetailState): SettingsDetailRowState | undefined {
  for (let groupIndex = 0; groupIndex < state.groups.length; groupIndex += 1) {
    const group: SettingsDetailGroupState = state.groups[groupIndex];
    if (group.id !== DESKTOP_BOOKMARK_BAR_GROUP_ID) {
      continue;
    }
    const rows: SettingsDetailRowState[] = group.rows;
    return rows.length > 0 ? rows[0] : undefined;
  }
  return undefined;
}

function selectedOptionId(row: SettingsDetailRowState): string {
  const options: SettingsDetailOption[] = row.options ?? [];
  for (let index = 0; index < options.length; index += 1) {
    if (options[index].isSelected) {
      return options[index].id;
    }
  }
  return '';
}

function visibilityLabel(id: string): Resource {
  if (id === 'never') {
    return $r('app.string.bookmark_bar_visibility_never');
  }
  if (id === 'always') {
    return $r('app.string.bookmark_bar_visibility_always');
  }
  return $r('app.string.bookmark_bar_visibility_new_tab');
}

function optionIds(row: SettingsDetailRowState): string {
  const options: SettingsDetailOption[] = row.options ?? [];
  const ids: string[] = [];
  options.forEach((option: SettingsDetailOption): void => {
    ids.push(option.id);
  });
  return ids.join(',');
}

export default function settingsDesktopBookmarkBarVisibilityRowTest(): void {
  describe('SettingsDesktopBookmarkBarVisibilityRow', () => {
    it('offers the three bar policies as a dropdown row instead of a switch', 0, () => {
      const row = bookmarkBarRow(appearanceDetailState(appearance(true, 'always'), true));

      expect(row?.id).assertEqual(DESKTOP_BOOKMARK_BAR_ROW_ID);
      expect(row?.kind).assertEqual('dropdown');
      expect(row?.action).assertEqual(DESKTOP_BOOKMARK_BAR_ROW_ACTION);
      expect(row?.title).assertEqual('显示书签栏');
      expect(row?.value).assertEqual('一律显示');
      expect(optionIds(row as SettingsDetailRowState)).assertEqual('never,always,new_tab_only');
      expect(selectedOptionId(row as SettingsDetailRowState)).assertEqual('always');
    });

    it('shows the policy that is stored, including the new-tab-only state', 0, () => {
      const newTabOnly = bookmarkBarRow(appearanceDetailState(appearance(true, 'new_tab_only'), true));
      expect(newTabOnly?.value).assertEqual('仅在“新标签页”页面上显示');
      expect(selectedOptionId(newTabOnly as SettingsDetailRowState)).assertEqual('new_tab_only');

      const hidden = bookmarkBarRow(appearanceDetailState(appearance(true, 'never'), true));
      expect(hidden?.value).assertEqual('一律隐藏');
      expect(selectedOptionId(hidden as SettingsDetailRowState)).assertEqual('never');
    });

    it('reads the legacy two-state switch as always or never', 0, () => {
      const legacyShown = bookmarkBarRow(appearanceDetailState(appearance(true), true));
      expect(selectedOptionId(legacyShown as SettingsDetailRowState)).assertEqual('always');

      const legacyHidden = bookmarkBarRow(appearanceDetailState(appearance(false), true));
      expect(selectedOptionId(legacyHidden as SettingsDetailRowState)).assertEqual('never');
    });

    it('keeps the row out of the phone surface and lists the three policies in order', 0, () => {
      expect(bookmarkBarRow(appearanceDetailState(appearance(true, 'always'), false))).assertUndefined();
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES.length).assertEqual(3);
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES[0].visibility).assertEqual('never');
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES[0].label).assertEqual('一律隐藏');
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES[1].visibility).assertEqual('always');
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES[1].label).assertEqual('一律显示');
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES[2].visibility).assertEqual('new_tab_only');
      expect(DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES[2].label).assertEqual('仅在“新标签页”页面上显示');
    });

    it('words the setting exactly like the bar menu, in the same order', 0, () => {
      const row = bookmarkBarRow(appearanceDetailState(appearance(true, 'always'), true));
      const options: SettingsDetailOption[] = row?.options ?? [];
      const menuItems: BrowserDesktopBookmarkBarMenuItem[] =
        buildDesktopBookmarkBarBlankMenuModel({ barVisibility: 'always' }).groups[0];

      expect(options.length).assertEqual(menuItems.length);
      options.forEach((option: SettingsDetailOption, index: number): void => {
        expect(option.id).assertEqual(menuItems[index].id.replace('bar_visibility_', ''));
        expect(isAppString(menuItems[index].label, visibilityLabel(option.id))).assertTrue();
      });
    });
  });
}

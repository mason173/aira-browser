import { describe, expect, it } from '@ohos/hypium';
import {
  SettingsDestinationNavigationOwner,
  SettingsDestinationNavigationRouter,
  SettingsNavigationIntent,
  SettingsNavigationSnapshot,
  SettingsRoutedDestination
} from '../main/ets/core/settings/SettingsDestinationNavigationOwner';
import {
  SettingsCenterDestination,
  SettingsCenterViewModel
} from '../main/ets/core/settings/SettingsCenterViewModel';
import {
  SettingsDetailGroupState,
  SettingsDetailRowState,
  SettingsDetailState,
  SettingsDetailViewModel
} from '../main/ets/core/settings/SettingsDetailViewModel';
import { BrowserBoundaryRouteState } from '../main/ets/common/utils/RouteParamUtils';

class InMemorySettingsNavigationRouter implements SettingsDestinationNavigationRouter {
  exitResult: boolean = true;
  exitCount: number = 0;
  openResult: boolean = true;
  openCount: number = 0;
  lastOpenedTarget: SettingsRoutedDestination | undefined = undefined;

  openRoutedDestination(
    target: SettingsRoutedDestination,
    _boundary: BrowserBoundaryRouteState
  ): Promise<boolean> {
    this.openCount += 1;
    this.lastOpenedTarget = target;
    return Promise.resolve(this.openResult);
  }

  exitSettings(): Promise<boolean> {
    this.exitCount += 1;
    return Promise.resolve(this.exitResult);
  }
}

export default function settingsDestinationNavigationOwnerTest(): void {
  describe('SettingsDestinationNavigationOwner', () => {
    it('finds a missing setting by its complete canonical title', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const searchState = owner.search(new SettingsCenterViewModel().buildState(), '安全 DNS');

      expect(searchState.resultCount).assertEqual(1);
      expect(searchState.groups[0].rows[0].id).assertEqual('secure_dns_settings');
      expect(searchState.groups[0].rows[0].title).assertEqual('安全 DNS');
    });

    it('finds every reproduced missing setting by its complete canonical title', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();

      expect(owner.search(state, '密码管理').groups[0].rows[0].id).assertEqual('passwords');
      expect(owner.search(state, '下载设置').groups[0].rows[0].id).assertEqual('downloads');
      expect(owner.search(state, '自动关闭标签页').groups[0].rows[0].id).assertEqual('tab_auto_close');
      expect(owner.search(state, '界面模式').groups[0].rows[0].id).assertEqual('tablet_interface_mode');
      expect(owner.search(state, '强制允许网页缩放').groups[0].rows[0].id).assertEqual('force_enable_web_zoom');
      expect(owner.search(state, '网页视频接管').groups[0].rows[0].id).assertEqual('web_video_takeover');
      expect(owner.search(state, '自动进入小说模式').groups[0].rows[0].id).assertEqual('novel_auto_takeover');
    });

    it('finds every canonical title exposed by the stable primary detail states', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const centerState = new SettingsCenterViewModel().buildState();
      const detailViewModel = new SettingsDetailViewModel();
      const destinations: SettingsCenterDestination[] = [
        'general',
        'appearance_toolbar',
        'privacy_security',
        'site_settings',
        'search',
        'web_features',
        'experiments',
        'advanced_settings',
        'app_service_mode',
        'about'
      ];

      for (let destinationIndex = 0; destinationIndex < destinations.length; destinationIndex += 1) {
        const detailState: SettingsDetailState = detailViewModel.buildState(destinations[destinationIndex]);
        for (let groupIndex = 0; groupIndex < detailState.groups.length; groupIndex += 1) {
          const group: SettingsDetailGroupState = detailState.groups[groupIndex];
          for (let rowIndex = 0; rowIndex < group.rows.length; rowIndex += 1) {
            const row: SettingsDetailRowState = group.rows[rowIndex];
            if (owner.search(centerState, row.title).resultCount <= 0) {
              throw new Error(`Missing settings search target for row: ${row.title}`);
            }
          }
        }
        for (let actionIndex = 0; actionIndex < detailState.actionButtons.length; actionIndex += 1) {
          const title = detailState.actionButtons[actionIndex].title;
          if (owner.search(centerState, title).resultCount <= 0) {
            throw new Error(`Missing settings search target for detail action: ${title}`);
          }
        }
      }
    });

    it('finds stable controls inside independently rendered settings pages', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      const canonicalTitles: string[] = [
        '网页密码保险箱',
        '自动填充已有密码',
        '提示保存新密码',
        '一次性填充已有密码',
        '下载位置',
        '下载前询问',
        '允许使用移动数据',
        '启动后自动恢复',
        '自动清理',
        '私密下载文件',
        '私密下载记录',
        '默认搜索引擎',
        '快速切换搜索引擎',
        '智能搜索回退',
        '备用搜索引擎',
        '回退提示',
        '搜索历史建议',
        '网络搜索建议',
        '跨应用搜索',
        '清除搜索历史',
        '选择翻译服务',
        '编辑服务配置',
        '目标语言',
        '私密标签页允许翻译',
        '过滤规则',
        '已清理页面元素',
        '清空统计',
        '全量模式',
        '基本模式'
      ];

      for (let index = 0; index < canonicalTitles.length; index += 1) {
        const title = canonicalTitles[index];
        const searchState = owner.search(state, title);
        expect(searchState.resultCount > 0).assertTrue();
        expect(searchState.groups[0].rows[0].title).assertEqual(title);
      }
    });

    it('normalizes width punctuation and whitespace before matching technical aliases', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();

      expect(owner.search(state, 'ｕａ').groups[0].rows[0].id).assertEqual('user_agent');
      expect(owner.search(state, '安全，ＤＮＳ').groups[0].rows[0].id).assertEqual('secure_dns_settings');
      expect(owner.search(state, '  WebDAV  ').groups[0].rows[0].id).assertEqual('sync');
    });

    it('returns the exact target identity for every fixed built-in search engine', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      const titles: string[] = [
        'Bing',
        'Google',
        'DuckDuckGo',
        'Baidu',
        '360 搜索',
        '搜狗',
        '神马',
        'Brave Search',
        'Startpage',
        'Ecosia',
        'Yandex'
      ];
      const targetIds: string[] = [
        'search_engine_bing',
        'search_engine_google',
        'search_engine_duckduckgo',
        'search_engine_baidu',
        'search_engine_qihoo',
        'search_engine_sogou',
        'search_engine_shenma',
        'search_engine_brave',
        'search_engine_startpage',
        'search_engine_ecosia',
        'search_engine_yandex'
      ];

      for (let index = 0; index < titles.length; index += 1) {
        const searchState = owner.search(state, titles[index]);
        expect(searchState.groups[0].rows[0].id).assertEqual(targetIds[index]);
      }
    });

    it('returns exact identities for fixed user-agent and toolbar-scroll choices', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      const titles: string[] = [
        '默认网页标识',
        'Aira默认',
        'ArkWeb 原始标识',
        '华为浏览器',
        'Chrome Android',
        'Safari iPhone',
        'Chrome Windows',
        'Microsoft Edge Windows',
        'Safari macOS',
        'Firefox Windows',
        '自定义 UA',
        '始终显示',
        '滚动时收起',
        '滚动时隐藏'
      ];
      const targetIds: string[] = [
        'default_user_agent',
        'user_agent_preset_system_default',
        'user_agent_preset_arkweb_original',
        'user_agent_preset_mobile_huawei_browser',
        'user_agent_preset_mobile_chrome_android',
        'user_agent_preset_mobile_safari_iphone',
        'user_agent_preset_desktop_chrome_windows',
        'user_agent_preset_desktop_edge_windows',
        'user_agent_preset_desktop_safari_mac',
        'user_agent_preset_desktop_firefox_windows',
        'custom_user_agent',
        'toolbar_scroll_fixed',
        'toolbar_scroll_compact',
        'toolbar_scroll_hidden'
      ];

      for (let index = 0; index < titles.length; index += 1) {
        const searchState = owner.search(state, titles[index]);
        expect(searchState.groups[0].rows[0].id).assertEqual(targetIds[index]);
      }
    });

    it('requires every query token and ranks an exact canonical title first', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      const tokenSearch = owner.search(state, '网页 视频');
      const exactSearch = owner.search(state, '网页视频接管');

      expect(tokenSearch.groups[0].rows[0].id).assertEqual('web_video_takeover');
      expect(exactSearch.groups[0].rows[0].id).assertEqual('web_video_takeover');
    });

    it('keeps a temporarily disabled target discoverable', 0, () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState('', '', 'basic');
      const searchState = owner.search(state, '网页翻译');

      expect(searchState.resultCount > 0).assertTrue();
      expect(searchState.groups[0].rows[0].id).assertEqual('webpage_translation');
      expect(searchState.groups[0].rows[0].isAvailable).assertFalse();
      expect(searchState.groups[0].rows[0].unavailableReason).assertEqual('需全量模式');
    });

    it('commits a disabled two-pane target to its presentable subpage without granting a mutation', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState('', '', 'basic');
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        'translation_provider_selection',
        state
      ));
      const snapshot = owner.snapshot();

      expect(result.committed).assertTrue();
      expect(snapshot.selectedPrimaryDestination).assertEqual('web_features');
      expect(snapshot.activeDetailKind).assertEqual('embedded_subpage');
      expect(snapshot.subpageId).assertEqual('webpage_translation');
      expect(snapshot.revealTargetId).assertEqual('translation_provider_selection');
    });

    it('routes a compact independent-page target with its exact reveal instruction', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);
      const state = new SettingsCenterViewModel().buildState();

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget('download_location', state));

      expect(result.committed).assertTrue();
      expect(router.lastOpenedTarget?.subpageId).assertEqual('downloads');
      expect(router.lastOpenedTarget?.revealTargetId).assertEqual('download_location');
    });

    it('routes a compact fixed engine through its owning subpage with exact reveal identity', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);
      const state = new SettingsCenterViewModel().buildState();

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        'search_engine_google',
        state
      ));

      expect(result.committed).assertTrue();
      expect(router.lastOpenedTarget?.destination).assertEqual('search');
      expect(router.lastOpenedTarget?.targetId).assertEqual('search_engine_google');
      expect(router.lastOpenedTarget?.subpageId).assertEqual('search_built_in_engines');
      expect(router.lastOpenedTarget?.revealTargetId).assertEqual('search_engine_google');
    });

    it('routes a toolbar scroll choice directly to its subpage with exact reveal identity', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);
      const state = new SettingsCenterViewModel().buildState();

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        'toolbar_scroll_hidden',
        state
      ));

      expect(result.committed).assertTrue();
      expect(router.lastOpenedTarget?.destination).assertEqual('toolbar_customization');
      expect(router.lastOpenedTarget?.targetId).assertEqual('toolbar_scroll_hidden');
      expect(router.lastOpenedTarget?.subpageId).assertEqual('toolbar_scroll_behavior');
      expect(router.lastOpenedTarget?.revealTargetId).assertEqual('toolbar_scroll_hidden');
    });

    it('publishes the built-in engine workspace presentation from the owner', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        'search_engine_google',
        state
      ));
      const snapshot = owner.snapshot();

      expect(result.committed).assertTrue();
      expect(snapshot.selectedPrimaryDestination).assertEqual('search');
      expect(snapshot.detailDepth).assertEqual(2);
      expect(snapshot.activeDestination).assertEqual('search');
      expect(snapshot.workspaceTitle).assertEqual('管理更多搜索引擎');
      expect(snapshot.activePanelKind).assertEqual('search_built_in_engines');
      expect(snapshot.revealTargetId).assertEqual('search_engine_google');
    });

    it('opens Secure DNS as a dedicated two-pane workspace subpage', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary('privacy_security', state));

      const result = await owner.dispatch(SettingsNavigationIntent.openEmbeddedSubpage('secure_dns_settings'));
      const snapshot = owner.snapshot();

      expect(result.committed).assertTrue();
      expect(snapshot.selectedPrimaryDestination).assertEqual('privacy_security');
      expect(snapshot.detailDepth).assertEqual(2);
      expect(snapshot.activeDetailKind).assertEqual('embedded_subpage');
      expect(snapshot.activeDestination).assertEqual('privacy_security');
      expect(snapshot.workspaceTitle).assertEqual('安全 DNS');
      expect(snapshot.activePanelKind).assertEqual('secure_dns');
    });

    it('keeps app service mode choices inside the advanced settings detail stack', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      const targetIds: string[] = ['app_service_mode_basic', 'app_service_mode_full'];

      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      for (let index = 0; index < targetIds.length; index += 1) {
        const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(targetIds[index], state));
        let snapshot = owner.snapshot();

        expect(result.committed).assertTrue();
        expect(snapshot.selectedPrimaryDestination).assertEqual('advanced_settings');
        expect(snapshot.detailDepth).assertEqual(2);
        expect(snapshot.activeDestination).assertEqual('app_service_mode');
        expect(snapshot.workspaceTitle).assertEqual('应用服务模式');
        expect(snapshot.activePanelKind).assertEqual('settings_destination');
        expect(snapshot.revealTargetId).assertEqual(targetIds[index]);

        await owner.dispatch(SettingsNavigationIntent.back());
        snapshot = owner.snapshot();
        expect(snapshot.selectedPrimaryDestination).assertEqual('advanced_settings');
        expect(snapshot.detailDepth).assertEqual(1);
        expect(snapshot.activeDestination).assertEqual('advanced_settings');
        expect(snapshot.workspaceTitle).assertEqual('高级设置');
      }
    });

    it('excludes targets without two-pane presentation capability', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));

      expect(owner.search(state, '顶部沉浸').resultCount).assertEqual(0);
      expect(owner.search(state, '标签页样式').resultCount).assertEqual(0);
    });

    it('rechecks presentation capability when a rendered result is selected', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);
      const state = new SettingsCenterViewModel().buildState();
      const compactSearch = owner.search(state, '顶部沉浸');
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      const before = owner.snapshot();

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        compactSearch.groups[0].rows[0].id,
        state
      ));
      const after = owner.snapshot();

      expect(result.committed).assertFalse();
      expect(result.failureReason).assertEqual('capability_missing');
      expect(router.openCount).assertEqual(0);
      expect(after.selectedPrimaryDestination).assertEqual(before.selectedPrimaryDestination);
      expect(after.revealRevision).assertEqual(before.revealRevision);
    });

    it('commits the destination before publishing an exact row reveal', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        'secure_dns_settings',
        state
      ));
      const snapshot = owner.snapshot();

      expect(result.committed).assertTrue();
      expect(snapshot.selectedPrimaryDestination).assertEqual('privacy_security');
      expect(snapshot.revealTargetId).assertEqual('secure_dns_settings');
      expect(snapshot.revealRevision).assertEqual(1);
    });

    it('reveals about detail rows in the primary two-pane detail instead of a fake subpage', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const state = new SettingsCenterViewModel().buildState();
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget('version', state));
      const snapshot = owner.snapshot();

      expect(result.committed).assertTrue();
      expect(snapshot.selectedPrimaryDestination).assertEqual('about');
      expect(snapshot.activeDetailKind).assertEqual('primary');
      expect(snapshot.subpageId).assertEqual('');
      expect(snapshot.revealTargetId).assertEqual('version');
    });

    it('preserves the originating state when exact-target routing fails', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      router.openResult = false;
      const owner = new SettingsDestinationNavigationOwner(router);
      const state = new SettingsCenterViewModel().buildState();
      const before = owner.snapshot();

      const result = await owner.dispatch(SettingsNavigationIntent.selectSearchTarget(
        'secure_dns_settings',
        state
      ));
      const after = owner.snapshot();

      expect(result.committed).assertFalse();
      expect(result.failureReason).assertEqual('router_failed');
      expect(result.targetTitle).assertEqual('安全 DNS');
      expect(after.selectedPrimaryDestination).assertEqual(before.selectedPrimaryDestination);
      expect(after.revealRevision).assertEqual(before.revealRevision);
      expect(router.lastOpenedTarget?.revealTargetId).assertEqual('secure_dns_settings');
    });

    it('keeps web apps detail history inside the settings session', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);

      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      await owner.dispatch(SettingsNavigationIntent.openWebAppDetail('shortcut-1'));
      await owner.dispatch(SettingsNavigationIntent.openSitePermission('example.com', 'https://example.com', 'camera'));

      let snapshot: SettingsNavigationSnapshot = owner.snapshot();
      expect(snapshot.selectedPrimaryDestination).assertEqual('web_apps');
      expect(snapshot.activeDetailKind).assertEqual('site_permission');
      expect(snapshot.detailDepth).assertEqual(3);

      await owner.dispatch(SettingsNavigationIntent.back());
      snapshot = owner.snapshot();
      expect(snapshot.activeDetailKind).assertEqual('web_app_detail');
      expect(snapshot.detailDepth).assertEqual(2);
      expect(router.exitCount).assertEqual(0);
    });

    it('changes shell without changing the active detail', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      await owner.dispatch(SettingsNavigationIntent.openWebAppDetail('shortcut-2'));
      const before = owner.snapshot();

      await owner.dispatch(SettingsNavigationIntent.setShell('compact'));
      const after = owner.snapshot();

      expect(after.shellMode).assertEqual('compact');
      expect(after.activeDetailKind).assertEqual(before.activeDetailKind);
      expect(after.shortcutId).assertEqual(before.shortcutId);
      expect(after.detailDepth).assertEqual(before.detailDepth);
    });

    it('resets web apps detail history when the primary destination changes', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      await owner.dispatch(SettingsNavigationIntent.openWebAppDetail('shortcut-3'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'general',
        new SettingsCenterViewModel().buildState()
      ));

      const snapshot = owner.snapshot();
      expect(snapshot.selectedPrimaryDestination).assertEqual('general');
      expect(snapshot.activeDetailKind).assertEqual('primary');
      expect(snapshot.detailDepth).assertEqual(1);
    });

    it('routes compact primary selection without publishing a second session state', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);
      await owner.dispatch(SettingsNavigationIntent.setShell('compact'));
      const before = owner.snapshot();

      const result = await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      const after = owner.snapshot();

      expect(result.handled).assertTrue();
      expect(result.committed).assertFalse();
      expect(router.openCount).assertEqual(1);
      expect(after.selectedPrimaryDestination).assertEqual(before.selectedPrimaryDestination);
      expect(after.detailDepth).assertEqual(before.detailDepth);
    });

    it('does not publish a failed platform navigation commit', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      router.exitResult = false;
      const owner = new SettingsDestinationNavigationOwner(router);
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      const before = owner.snapshot();
      let observedCount = 0;
      owner.observe((_snapshot: SettingsNavigationSnapshot): void => {
        observedCount += 1;
      });

      const result = await owner.dispatch(SettingsNavigationIntent.back());
      const after = owner.snapshot();

      expect(result.committed).assertFalse();
      expect(result.failureReason).assertEqual('router_failed');
      expect(after.activeDetailKind).assertEqual(before.activeDetailKind);
      expect(after.detailDepth).assertEqual(before.detailDepth);
      expect(observedCount).assertEqual(0);
    });

    it('fails closed for a detail intent outside the web apps session', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      const result = await owner.dispatch(SettingsNavigationIntent.openWebAppDetail('shortcut-4'));

      expect(result.committed).assertFalse();
      expect(result.failureReason).assertEqual('invalid_transition');
      expect(owner.snapshot().selectedPrimaryDestination).assertEqual('general');
    });

    it('fails closed when web apps requests an undeclared full-screen task', 0, async () => {
      const owner = new SettingsDestinationNavigationOwner(new InMemorySettingsNavigationRouter());
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      const before = owner.snapshot();

      const result = await owner.dispatch(SettingsNavigationIntent.startFullScreenTask('unknown-task'));
      const after = owner.snapshot();

      expect(result.committed).assertFalse();
      expect(result.failureReason).assertEqual('capability_missing');
      expect(after.activeDetailKind).assertEqual(before.activeDetailKind);
      expect(after.detailDepth).assertEqual(before.detailDepth);
    });

    it('closes settings without popping the active detail stack first', 0, async () => {
      const router = new InMemorySettingsNavigationRouter();
      const owner = new SettingsDestinationNavigationOwner(router);
      await owner.dispatch(SettingsNavigationIntent.setShell('twoPane'));
      await owner.dispatch(SettingsNavigationIntent.selectPrimary(
        'web_apps',
        new SettingsCenterViewModel().buildState()
      ));
      await owner.dispatch(SettingsNavigationIntent.openWebAppDetail('shortcut-close'));
      const before = owner.snapshot();

      const result = await owner.dispatch(SettingsNavigationIntent.close());
      const after = owner.snapshot();

      expect(result.committed).assertFalse();
      expect(router.exitCount).assertEqual(1);
      expect(after.activeDetailKind).assertEqual(before.activeDetailKind);
      expect(after.detailDepth).assertEqual(before.detailDepth);
    });
  });
}

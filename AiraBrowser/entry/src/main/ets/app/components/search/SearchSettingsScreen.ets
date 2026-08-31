import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SearchEngineManagementState } from '../../../core/search/SearchEngineManagementViewModel';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsFooterText,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../settings/SettingsTargetReveal';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';

@Component
export struct SearchSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#14000000';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: SearchEngineManagementState = {
    defaultEngineName: 'Bing',
    fallbackEnabled: false,
    fallbackEngineName: '',
    fallbackEngineSelectable: true,
    fallbackNoticeEnabled: true,
    fallbackInfoText: '',
    builtInEngines: [],
    customEngines: [],
    historySuggestionsEnabled: true,
    remoteSuggestionsEnabled: true
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop pageBackground: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop controlBackground: ResourceColor | undefined = undefined;
  @Prop pressedBackground: ResourceColor | undefined = undefined;
  @Prop accentColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = this.storedPrimaryTextColor;
  @Prop secondaryTextColor: ResourceColor = this.storedSecondaryTextColor;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );
  @Prop externalAppSearchSummary: string = '已开启';
  @Prop quickSearchSwitchingEnabled: boolean = true;
  onOpenDefaultEngine: () => void = () => {};
  onQuickSearchSwitchingChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onFallbackEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenFallbackEngine: () => void = () => {};
  onFallbackNoticeEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onHistorySuggestionsChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onRemoteSuggestionsChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenExternalAppSearchSettings: () => void = () => {};
  onClearSearchHistory: () => void = () => {};

  aboutToAppear(): void {
    this.revealController.bindScroller(this.settingsScroller);
    this.handleRevealRequest();
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    SettingsHdsScaffold({
      title: '搜索',
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.resolveControlBackground(),
      primaryTextColor: this.resolvePrimaryTextColor(),
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      contentKind: this.contentKind,
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsPresentationScrollBody({
          contentSpace: 18,
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller,
          onContentAreaChanged: (area: Area): void => {
            this.revealController.rememberContentArea(area);
          }
        }) {
          this.buildDefaultSection()
          this.buildExternalAppSearchEntrySection()
          this.buildSuggestionsSection()
          this.buildClearSearchHistorySection()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePageBackground())
    }
  }

  @Builder
  private buildDefaultSection() {
    SettingsTargetRevealRegion({
      targetId: 'search_engine',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.resolveAccentColor(),
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsSection({
        title: '搜索引擎',
        secondaryTextColor: this.resolveSecondaryTextColor()
      }) {
        SettingsGroupCard({
          surfaceColor: this.resolveSurfaceBackground(),
          desktopPresentation: this.desktopPresentation
        }) {
        SettingsTargetRevealRegion({
          targetId: 'default_search_engine',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '默认搜索引擎',
            desktopPresentation: this.desktopPresentation,
            value: this.state.defaultEngineName,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'first',
            onAction: () => {
              this.onOpenDefaultEngine();
            }
          })
        }
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsTargetRevealRegion({
          targetId: 'quick_search_switching',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '快速切换搜索引擎',
            desktopPresentation: this.desktopPresentation,
            checked: this.quickSearchSwitchingEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'middle',
            onChange: (enabled: boolean) => {
              this.onQuickSearchSwitchingChange(enabled);
            }
          })
        }
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsTargetRevealRegion({
          targetId: 'smart_search_fallback',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '智能搜索回退',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.fallbackEnabled,
            isEnabled: this.state.fallbackEngineSelectable,
            titleActionIcon: $r('sys.symbol.info_circle'),
            titlePopupText: this.state.fallbackInfoText,
            titleActionAccessibilityText: '查看智能搜索回退说明',
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'middle',
            onChange: (enabled: boolean) => {
              this.onFallbackEnabledChange(enabled);
            }
          })
        }
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsTargetRevealRegion({
          targetId: 'fallback_search_engine',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '备用搜索引擎',
            desktopPresentation: this.desktopPresentation,
            value: this.resolveFallbackEngineName(),
            isEnabled: this.state.fallbackEnabled && this.state.fallbackEngineSelectable,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'middle',
            onAction: () => {
              this.onOpenFallbackEngine();
            }
          })
        }
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsTargetRevealRegion({
          targetId: 'fallback_notice',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '回退提示',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.fallbackNoticeEnabled,
            isEnabled: this.state.fallbackEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'last',
            onChange: (enabled: boolean) => {
              this.onFallbackNoticeEnabledChange(enabled);
            }
          })
        }
        }
        SettingsFooterText({
          text: '主搜索引擎当前不可用时，地址栏会自动使用备用搜索引擎完成本次搜索。检测不会发送搜索词。',
          secondaryTextColor: this.resolveSecondaryTextColor()
        })
      }
    }
  }

  @Builder
  private buildSuggestionsSection() {
    SettingsTargetRevealRegion({
      targetId: 'suggestions_info',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.resolveAccentColor(),
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsSection({
        title: '搜索建议',
        secondaryTextColor: this.resolveSecondaryTextColor()
      }) {
        SettingsGroupCard({
          surfaceColor: this.resolveSurfaceBackground(),
          desktopPresentation: this.desktopPresentation
        }) {
        SettingsTargetRevealRegion({
          targetId: 'search_history_suggestions',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '搜索历史建议',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.historySuggestionsEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'first',
            onChange: (enabled: boolean) => {
              this.onHistorySuggestionsChange(enabled);
            }
          })
        }
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsTargetRevealRegion({
          targetId: 'remote_search_suggestions',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '网络搜索建议',
            desktopPresentation: this.desktopPresentation,
            checked: this.state.remoteSuggestionsEnabled,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'last',
            onChange: (enabled: boolean) => {
              this.onRemoteSuggestionsChange(enabled);
            }
          })
        }
        }
        SettingsFooterText({
          text: '搜索历史保存在本机；网络搜索建议会在输入搜索词时获取联想词。',
          secondaryTextColor: this.resolveSecondaryTextColor()
        })
      }
    }
  }

  @Builder
  private buildExternalAppSearchEntrySection() {
    SettingsSection({
      title: '更多搜索方式',
      secondaryTextColor: this.resolveSecondaryTextColor()
    }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'external_app_search',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.resolveAccentColor(),
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '跨应用搜索',
            desktopPresentation: this.desktopPresentation,
            value: this.externalAppSearchSummary,
            primaryTextColor: this.resolvePrimaryTextColor(),
            secondaryTextColor: this.resolveSecondaryTextColor(),
            pressedBackgroundColor: this.resolvePressedBackground(),
            rowPosition: 'single',
            onAction: () => {
              this.onOpenExternalAppSearchSettings();
            }
          })
        }
      }
    }
  }

  @Builder
  private buildClearSearchHistorySection() {
    SettingsTargetRevealRegion({
      targetId: 'clear_search_history',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.resolveAccentColor(),
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsActionButton({
        title: '清除搜索历史',
        emphasis: 'danger',
        pressedBackgroundColor: this.resolvePressedBackground(),
        onAction: () => {
          this.onClearSearchHistory();
        }
      })
    }
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  private resolveAccentColor(): ResourceColor {
    return `${this.accentColor}`.length > 0 ? this.accentColor : this.storedAccentColor;
  }

  private resolvePageBackground(): ResourceColor {
    return this.pageBackground === undefined ? this.storedPageBackgroundColor : this.pageBackground;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolveControlBackground(): ResourceColor {
    return this.controlBackground === undefined ? this.storedPressedBackgroundColor : this.controlBackground;
  }

  private resolvePressedBackground(): ResourceColor {
    return this.pressedBackground === undefined ? this.storedPressedBackgroundColor : this.pressedBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }

  private resolveFallbackEngineName(): string {
    return this.state.fallbackEngineName.length > 0 ? this.state.fallbackEngineName : '未选择';
  }

}

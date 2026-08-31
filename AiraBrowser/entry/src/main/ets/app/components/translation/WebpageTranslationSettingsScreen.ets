import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { WebpageTranslationSettingsViewState } from '../../../core/translation/WebpageTranslationSettingsViewModel';
import {
  SettingsNavigationRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import { SettingsNoticeCard } from '../settings/SettingsNoticeCard';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import { WebpageTranslationTargetLanguageSheet } from './WebpageTranslationTargetLanguageSheet';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { sharedSettingsNoticeDismissalRepository } from '../../bootstrap/BrowserAppRuntime';
import { SETTINGS_NOTICE_TRANSLATION } from '../../../data/preferences/SettingsNoticeDismissalRepository';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../settings/SettingsTargetReveal';

@Component
export struct WebpageTranslationSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop state: WebpageTranslationSettingsViewState = {
    enabled: true,
    allowInPrivateTabs: false,
    preferredTargetLanguage: 'zh-CN',
    preferredTargetLanguageLabel: '简体中文',
    targetLanguageDescription: '手动翻译网页时默认使用此语言',
    targetLanguageSheetHelperText: '多语言能力由当前服务商提供，实际可用语种以服务商为准。',
    targetLanguageOptions: [],
    providerStatusText: '未配置',
    hasActiveProvider: false,
    providers: []
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop controlsEnabled: boolean = true;
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  onEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onAllowPrivateTabsChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenProviderSelection: () => void = () => {};
  onEditActiveProvider: () => void = () => {};
  onSelectTargetLanguage: (languageCode: string) => void = (_languageCode: string) => {};
  @State private targetLanguageSheetVisible: boolean = false;

  build() {
    SettingsHdsScaffold({
      title: '网页翻译',
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      onBack: () => {
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsScrollBody({
          contentSpace: 18,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller
        }) {
          WebpageTranslationSettingsContent({
            state: this.state,
            dividerColor: this.storedDividerColor,
            surfaceBackground: this.storedSurfaceBackgroundColor,
            accentColor: this.storedAccentColor,
            controlsEnabled: this.controlsEnabled,
            revealTargetId: this.revealTargetId,
            revealRevision: this.revealRevision,
            scroller: this.settingsScroller,
            onEnabledChange: (enabled: boolean) => {
              this.onEnabledChange(enabled);
            },
            onAllowPrivateTabsChange: (enabled: boolean) => {
              this.onAllowPrivateTabsChange(enabled);
            },
            onOpenProviderSelection: () => {
              this.onOpenProviderSelection();
            },
            onEditActiveProvider: () => {
              this.onEditActiveProvider();
            },
            onSelectTargetLanguage: (languageCode: string) => {
              this.onSelectTargetLanguage(languageCode);
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.storedPageBackgroundColor)
    }
  }
}

@Component
export struct WebpageTranslationSettingsContent {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @Prop state: WebpageTranslationSettingsViewState = {
    enabled: true,
    allowInPrivateTabs: false,
    preferredTargetLanguage: 'zh-CN',
    preferredTargetLanguageLabel: '简体中文',
    targetLanguageDescription: '手动翻译网页时默认使用此语言',
    targetLanguageSheetHelperText: '多语言能力由当前服务商提供，实际可用语种以服务商为准。',
    targetLanguageOptions: [],
    providerStatusText: '未配置',
    hasActiveProvider: false,
    providers: []
  };
  @Prop dividerColor: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop accentColor: ResourceColor = '';
  @Prop controlsEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  scroller?: Scroller;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );
  onEnabledChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onAllowPrivateTabsChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenProviderSelection: () => void = () => {};
  onEditActiveProvider: () => void = () => {};
  onSelectTargetLanguage: (languageCode: string) => void = (_languageCode: string) => {};
  @State private targetLanguageSheetVisible: boolean = false;
  @State private showTranslationNotice: boolean = true;

  aboutToAppear(): void {
    this.revealController.bindScroller(this.scroller);
    this.handleRevealRequest();
    this.showTranslationNotice = !sharedSettingsNoticeDismissalRepository.hasDismissed(SETTINGS_NOTICE_TRANSLATION);
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    Column({ space: 18 }) {
      if (this.showTranslationNotice) {
        SettingsNoticeCard({
          title: '翻译会发送页面文字',
          message: '页面文本可能发送到翻译服务，请确认服务来源可信。',
          siblingSpace: 18,
          desktopPresentation: this.desktopPresentation,
          onClosed: () => {
            this.showTranslationNotice = false;
            this.dismissNotice(SETTINGS_NOTICE_TRANSLATION);
          }
        })
      }
      this.buildStatusSection()
      this.buildLanguageSection()
      this.buildProviderSection()
      this.buildPromptSection()
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.revealController.rememberContentArea(newArea);
    })
    .bindSheet($$this.targetLanguageSheetVisible, this.buildTargetLanguageSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.targetLanguageSheetVisible = false;
      }
    })
  }

  @Builder
  private buildStatusSection() {
    SettingsSection({ title: '功能' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '网页翻译',
          desktopPresentation: this.desktopPresentation,
          description: this.state.enabled ? '可从菜单手动翻译当前网页' : '关闭后不显示网页翻译入口',
          checked: this.state.enabled,
          isEnabled: this.controlsEnabled,
          rowPosition: 'single',
          onChange: (enabled: boolean) => {
            this.onEnabledChange(enabled);
          }
        })
      }
    }
  }

  @Builder
  private buildProviderSection() {
    SettingsSection({ title: '服务管理' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'translation_provider_selection',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '选择翻译服务',
            desktopPresentation: this.desktopPresentation,
            value: this.state.providerStatusText,
            description: '选择或添加 API 翻译服务',
            rowPosition: 'first',
            isEnabled: this.controlsEnabled,
            onAction: () => {
              this.onOpenProviderSelection();
            }
          })
        }
        SettingsGroupDivider({ dividerColor: this.resolveDividerColor() })
        SettingsTargetRevealRegion({
          targetId: 'translation_provider_config',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '编辑服务配置',
            desktopPresentation: this.desktopPresentation,
            description: this.state.hasActiveProvider ? '更新 API Key、Endpoint 或区域' : '请先选择翻译服务',
            rowPosition: 'last',
            isEnabled: this.controlsEnabled && this.state.hasActiveProvider,
            onAction: () => {
              this.onEditActiveProvider();
            }
          })
        }
      }
    }
  }

  @Builder
  private buildLanguageSection() {
    SettingsSection({ title: '语言' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'translation_target_language',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsNavigationRow({
            title: '目标语言',
            desktopPresentation: this.desktopPresentation,
            value: this.state.preferredTargetLanguageLabel,
            description: this.state.targetLanguageDescription,
            rowPosition: 'single',
            isEnabled: this.controlsEnabled,
            onAction: () => {
              this.targetLanguageSheetVisible = true;
            }
          })
        }
      }
    }
  }

  @Builder
  private buildPromptSection() {
    SettingsSection({ title: '隐私' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsTargetRevealRegion({
          targetId: 'translation_private_tabs',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.accentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsSwitchRow({
            title: '私密标签页允许翻译',
            desktopPresentation: this.desktopPresentation,
            description: '关闭时私密标签页不提供网页翻译',
            checked: this.state.allowInPrivateTabs,
            rowPosition: 'single',
            isEnabled: this.controlsEnabled && this.state.enabled,
            onChange: (enabled: boolean) => {
              this.onAllowPrivateTabsChange(enabled);
            }
          })
        }
      }
    }
  }

  @Builder
  private buildTargetLanguageSheet() {
    WebpageTranslationTargetLanguageSheet({
      selectedLanguage: this.state.preferredTargetLanguage,
      helperText: this.state.targetLanguageSheetHelperText,
      options: this.state.targetLanguageOptions,
      onSelectTargetLanguage: (languageCode: string) => {
        this.targetLanguageSheetVisible = false;
        this.onSelectTargetLanguage(languageCode);
      }
    })
  }

  private resolveDividerColor(): ResourceColor {
    return this.dividerColor === undefined ? this.storedDividerColor : this.dividerColor;
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private dismissNotice(noticeId: string): void {
    sharedSettingsNoticeDismissalRepository.dismiss(noticeId).catch((_error: Error) => {});
  }
}

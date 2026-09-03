import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { AdBlockCustomRuleSourceRowView } from '../../../core/adblock/AdBlockSettingsViewModel';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsDesktopWorkspaceHeader,
  SettingsDesktopWorkspaceHeaderAction
} from '../settings/SettingsDesktopWorkspaceHeader';
import {
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsSwitchRow,
  SettingsTextField
} from '../settings/SettingsRows';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { AdBlockRuleNoticeCard } from './AdBlockRuleNoticeCard';
import { sharedSettingsNoticeDismissalRepository } from '../../bootstrap/BrowserAppRuntime';
import { SETTINGS_NOTICE_ADBLOCK_RULES } from '../../../data/preferences/SettingsNoticeDismissalRepository';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode
} from '../common/FloatingGlassMaterialTokens';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';

@CustomDialog
export struct AdBlockGithubRuleDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link ruleUrl: string;
  confirm: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text('URL 订阅导入')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      SettingsTextField({
        text: this.ruleUrl,
        placeholder: '粘贴 HTTPS 规则订阅地址',
        underlineStyle: true,
        controlBackgroundColor: this.storedControlBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        onChange: (value: string) => {
          this.ruleUrl = value;
        }
      })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '确定',
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          textColor: this.storedOnPrimaryColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}

@Component
export struct AdBlockCustomRulesScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop sources: AdBlockCustomRuleSourceRowView[] = [];
  @Prop adBlockEnabled: boolean = false;
  @Prop updateOnForeground: boolean = true;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @State private pressedSourceId: string = '';
  @State private contextMenuSourceId: string = '';
  @State private showRuleNotice: boolean = true;
  onImportLocal: () => void = () => {};
  onOpenGithubDialog: () => void = () => {};
  onUpdateOnForegroundChange: (enabled: boolean) => void = (_enabled: boolean) => {};
  onRefreshSource: (sourceId: string) => void = (_sourceId: string) => {};
  onRemoveSource: (sourceId: string) => void = (_sourceId: string) => {};
  onSourceEnabledChange: (sourceId: string, enabled: boolean) => void =
    (_sourceId: string, _enabled: boolean) => {};
  onBack?: () => void;

  aboutToAppear(): void {
    this.showRuleNotice = !sharedSettingsNoticeDismissalRepository.hasDismissed(SETTINGS_NOTICE_ADBLOCK_RULES);
  }

  build() {
    SettingsHdsScaffold({
      title: '过滤规则',
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: !this.desktopPresentation,
      showTitleBar: !this.desktopPresentation,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      scrollers: [this.settingsScroller],
      menuActions: [
        {
          label: '本地导入',
          icon: $r('sys.symbol.folder_badge_plus'),
          action: () => {
            this.onImportLocal();
          }
        },
        {
          label: 'URL 订阅导入',
          icon: $r('sys.symbol.link'),
          action: () => {
            this.onOpenGithubDialog();
          }
        }
      ],
      onBack: () => {
        if (this.onBack !== undefined) {
          this.onBack();
          return;
        }
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        if (this.desktopPresentation) {
          SettingsDesktopWorkspaceHeader({
            title: '过滤规则',
            showBackButton: true,
            primaryTextColor: this.storedPrimaryTextColor,
            iconColor: this.storedSecondaryTextColor,
            buttonBackgroundColor: this.storedPressedBackgroundColor,
            menuActions: this.buildDesktopHeaderActions(),
            onBack: () => {
              this.onBack?.();
            }
          })
        }

        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 32,
          scroller: this.settingsScroller
        }) {
          this.buildUpdatePolicySection()
          if (this.showRuleNotice) {
            AdBlockRuleNoticeCard({
              desktopPresentation: this.desktopPresentation,
              onClosed: () => {
                this.showRuleNotice = false;
                this.dismissNotice(SETTINGS_NOTICE_ADBLOCK_RULES);
              }
            })
          }
          if (this.hasThirdPartyPresetSources()) {
            this.buildRuleSourceSection('第三方规则', true)
          }
          if (this.hasUserRuleSources()) {
            this.buildRuleSourceSection('自定义规则', false)
          }
        }
      }
      .width('100%')
      .height('100%')
      .clip(this.desktopPresentation)
    }
  }

  private buildDesktopHeaderActions(): SettingsDesktopWorkspaceHeaderAction[] {
    return [
      {
        label: '本地导入',
        action: (): void => {
          this.onImportLocal();
        }
      },
      {
        label: 'URL 订阅导入',
        action: (): void => {
          this.onOpenGithubDialog();
        }
      }
    ];
  }

  @Builder
  private buildRuleSourceSection(title: string, isThirdPartyPreset: boolean) {
    SettingsSection({ title: title }) {
      Column({ space: 10 }) {
        ForEach(this.filterSources(isThirdPartyPreset), (item: AdBlockCustomRuleSourceRowView) => {
          SettingsGroupCard({
            surfaceColor: this.storedSurfaceBackgroundColor,
            desktopPresentation: this.desktopPresentation
          }) {
            this.buildSourceRow(item)
          }
        }, (item: AdBlockCustomRuleSourceRowView) => item.id)
      }
    }
  }

  @Builder
  private buildUpdatePolicySection() {
    SettingsSection({
      title: '更新策略',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      Column({ space: 8 }) {
        SettingsGroupCard({
          surfaceColor: this.storedSurfaceBackgroundColor,
          desktopPresentation: this.desktopPresentation
        }) {
          SettingsSwitchRow({
            title: '订阅规则自动更新',
            desktopPresentation: this.desktopPresentation,
            checked: this.updateOnForeground,
            rowPosition: 'single',
            isEnabled: this.adBlockEnabled,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onChange: (enabled: boolean) => {
              this.onUpdateOnForegroundChange(enabled);
            }
          })
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildSourceRow(item: AdBlockCustomRuleSourceRowView) {
    Row({ space: 12 }) {
      Column() {
        Text(item.title)
          .width('100%')
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.hasError) {
        Text('更新失败')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
      }

      Toggle({ type: ToggleType.Switch, isOn: item.enabled })
        .selectedColor(this.storedAccentColor)
        .onChange((value: boolean) => {
          this.onSourceEnabledChange(item.id, value);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.pressedSourceId === item.id
      ? this.storedPressedBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(20)
    .onTouch((event: TouchEvent) => {
      this.updatePressedSource(item.id, event.type);
    })
    .gesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
        .onAction(() => {
          if (!item.canRefresh && !item.canRemove) {
            return;
          }
          this.contextMenuSourceId = item.id;
        })
    )
    .bindContextMenu((item.canRefresh || item.canRemove) && this.contextMenuSourceId === item.id, this.buildSourceContextMenu(item), {
      preview: this.buildSourceContextPreview(item),
      previewBorderRadius: 18,
      onDisappear: () => {
        this.contextMenuSourceId = '';
      }
    })
  }

  @Builder
  private buildSourceContextPreview(item: AdBlockCustomRuleSourceRowView) {
    Row({ space: 12 }) {
      Column() {
        Text(item.title)
          .width('100%')
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(18)
  }

  @Builder
  private buildSourceContextMenu(item: AdBlockCustomRuleSourceRowView) {
    Menu() {
      if (item.canRefresh) {
        MenuItem({ content: '刷新' })
          .onClick(() => {
            this.onRefreshSource(item.id);
          })
      }
      if (item.canRemove) {
        MenuItem({ content: '删除' })
          .onClick(() => {
            this.onRemoveSource(item.id);
          })
      }
    }
    .width(188)
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .systemMaterial(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    ))
  }

  private hasThirdPartyPresetSources(): boolean {
    return this.sources.some((item: AdBlockCustomRuleSourceRowView) => item.isThirdPartyPreset);
  }

  private hasUserRuleSources(): boolean {
    return this.sources.some((item: AdBlockCustomRuleSourceRowView) => !item.isThirdPartyPreset);
  }

  private filterSources(isThirdPartyPreset: boolean): AdBlockCustomRuleSourceRowView[] {
    return this.sources.filter((item: AdBlockCustomRuleSourceRowView) => {
      return item.isThirdPartyPreset === isThirdPartyPreset;
    });
  }

  private updatePressedSource(sourceId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedSourceId = sourceId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedSourceId = '';
    }
  }

  private dismissNotice(noticeId: string): void {
    sharedSettingsNoticeDismissalRepository.dismiss(noticeId).catch((_error: Error) => {});
  }
}

import { common } from '@kit.AbilityKit';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BlurStrategy,
  DividerShowType,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  hdsMaterial,
  IconStyleMode,
  ScrollEffectType,
  TitleSize
} from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { BrowserStatusBarStyleService } from '../../../services/browser/BrowserStatusBarStyleService';
import { SettingsTopSafeInsetService } from '../../../services/settings/SettingsTopSafeInsetService';
import { SettingsContentFrame } from './SettingsContentFrame';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';

export type SettingsHdsBackIconKind = 'close' | 'back';

export interface SettingsHdsMenuAction {
  label: string;
  icon?: Resource;
  enabled?: boolean;
  action: () => void;
}

const SETTINGS_TITLE_BAR_MENU_BADGE_SIZE: number = 8;
const SETTINGS_TITLE_BAR_MENU_BADGE_BORDER_WIDTH: number = 2;
const SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE: number = 40;
const SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_TOP: number = 8;
const SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_GAP: number = 8;
const SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_LEFT: number = 16;
const SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_RIGHT: number = 16;
const SETTINGS_TITLE_BAR_ACTION_ICON_SIZE: number = 21;

@Component
export struct SettingsHdsScaffold {
  private statusBarStyleService: BrowserStatusBarStyleService = new BrowserStatusBarStyleService();
  private topSafeInsetService: SettingsTopSafeInsetService = new SettingsTopSafeInsetService();
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('syncStatusBarContentStyle')
  private storedResolvedThemeMode: string = 'light';
  @Prop title: string = '';
  @Prop backIconKind: SettingsHdsBackIconKind = 'back';
  @Prop pageBackground: ResourceColor = DEFAULT_THEME_PALETTE.light.pageBackground;
  @Prop headerButtonBackground: ResourceColor = DEFAULT_THEME_PALETTE.light.controlBackground;
  @Prop primaryTextColor: ResourceColor = DEFAULT_THEME_PALETTE.light.textPrimary;
  @Prop dividerColor: ResourceColor = DEFAULT_THEME_PALETTE.light.divider;
  @Prop showPrivateIndicator: boolean = false;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop desktopPresentation: boolean = false;
  @Prop menuActionLabel: string = '';
  @Prop menuActionIcon: Resource | undefined = undefined;
  @Prop menuActionImageIcon: Resource | undefined = undefined;
  @Prop menuActionAiraIconId: AiraRenderableIconId | undefined = undefined;
  @Prop menuActionEnabled: boolean = true;
  @Prop menuActionBadgeVisible: boolean = false;
  @Prop menuActions: SettingsHdsMenuAction[] = [];
  scrollers: Array<Scroller> = [];
  @State private topSafeInsetVp: number = 0;
  onBack: () => void = (): void => {};
  onMenuAction: () => void = (): void => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.syncStatusBarContentStyle();
    this.refreshTopSafeInset();
  }

  build() {
    if (this.showTitleBar) {
      this.buildScaffoldWithTitleBar()
    } else {
      this.buildScaffoldWithoutTitleBar()
    }
  }

  @Builder
  private buildScaffoldWithoutTitleBar() {
    Column() {
      this.buildContentFrame()
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.desktopPresentation ? 1 : 0)
    .padding({ top: this.useTopSafeInset ? this.resolveTopSafeInset() : 0 })
    .backgroundColor(this.pageBackground)
  }

  @Builder
  private buildScaffoldWithTitleBar() {
    Stack() {
      HdsNavDestination() {
        this.buildContentFrame()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageBackground)
      .titleBar({
        content: {
          title: {
            mainTitle: this.title,
            mainTitleSize: TitleSize.TITLE_S
          },
          backIcon: {
            label: this.resolveBackLabel(),
            icon: this.resolveBackIcon(),
            isEnabled: false,
            type: IconStyleMode.NORMAL,
            action: () => {}
          },
          menu: undefined,
          divider: {
            showType: DividerShowType.AUTO
          }
        },
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        style: {
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(72)
          },
          blurStrategy: BlurStrategy.ADAPTIVE,
          originalStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent,
              maskExtraHeight: 40,
              blurRadius: 0
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: this.primaryTextColor
              },
              backIconStyle: {
                backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
                iconColor: $r('sys.color.ohos_id_color_background_transparent')
              },
              menuStyle: {
                backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
                iconColor: $r('sys.color.ohos_id_color_background_transparent')
              },
              dividerStyle: {
                dividerColor: this.dividerColor
              }
            }
          },
          scrollEffectStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent,
              maskExtraHeight: 40,
              blurRadius: 28
            },
            contentStyle: {
              titleStyle: {
                mainTitleColor: this.primaryTextColor
              },
              backIconStyle: {
                backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
                iconColor: $r('sys.color.ohos_id_color_background_transparent')
              },
              menuStyle: {
                backgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
                iconColor: $r('sys.color.ohos_id_color_background_transparent')
              },
              dividerStyle: {
                dividerColor: this.dividerColor
              }
            }
          },
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        }
      })
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .bindToScrollable(this.scrollers)
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
      )
      .hideBackButton(!this.showBackButton)
      .onBackPressed(() => {
        this.onBack();
        return true;
      })

      this.buildGlassTitleActions()
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.desktopPresentation ? 1 : 0)
    .backgroundColor(this.pageBackground)
  }

  @Builder
  private buildContentFrame() {
    SettingsContentFrame({ kind: this.desktopPresentation ? 'unframed' : this.contentKind }) {
      this.content()
    }
  }

  @Builder
  private buildGlassTitleActions() {
    if (this.showBackButton) {
      this.buildGlassBackButton()
    }
    if (this.shouldShowTrailingTitleActions()) {
      this.buildGlassTrailingTitleActions()
    }
  }

  @Builder
  private buildGlassBackButton() {
    Button() {
      AiraIcon({
        airaIconId: 'browser.toolbar.back',
        iconSize: SETTINGS_TITLE_BAR_ACTION_ICON_SIZE,
        iconColor: this.resolveTitleActionIconColor()
      })
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .type(ButtonType.Normal)
    .stateEffect(true)
    .backgroundColor(this.headerButtonBackground)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
    .position({
      x: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_LEFT,
      y: this.resolveCustomMenuActionButtonTop()
    })
    .zIndex(4)
    .accessibilityText(this.resolveBackLabel())
    .onClick(() => {
      this.onBack();
    })
  }

  @Builder
  private buildGlassTrailingTitleActions() {
    Row({ space: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_GAP }) {
      if (this.menuActions.length > 0) {
        ForEach(this.menuActions, (menuAction: SettingsHdsMenuAction) => {
          this.buildGlassMenuAction(menuAction)
        }, (menuAction: SettingsHdsMenuAction) => menuAction.label)
      } else if (this.menuActionLabel.length > 0) {
        if (this.menuActionBadgeVisible) {
          Badge({
            value: '',
            position: BadgePosition.RightTop,
            style: {
              badgeSize: SETTINGS_TITLE_BAR_MENU_BADGE_SIZE,
              badgeColor: $r('app.color.settings_title_bar_menu_badge'),
              borderWidth: SETTINGS_TITLE_BAR_MENU_BADGE_BORDER_WIDTH,
              borderColor: this.headerButtonBackground
            }
          }) {
            this.buildCustomMenuActionButtonControl()
          }
          .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
          .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
        } else {
          this.buildCustomMenuActionButtonControl()
        }
      }
      if (this.showPrivateIndicator) {
        this.buildGlassPrivateIndicator()
      }
    }
    .width('100%')
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .padding({ right: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_RIGHT })
    .justifyContent(FlexAlign.End)
    .position({ x: 0, y: this.resolveCustomMenuActionButtonTop() })
    .hitTestBehavior(HitTestMode.Transparent)
    .zIndex(4)
  }

  @Builder
  private buildGlassMenuAction(menuAction: SettingsHdsMenuAction) {
    Button() {
      SymbolGlyph(this.resolveMenuActionIcon(menuAction.icon))
        .fontSize(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.resolveTitleActionIconColor()])
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .type(ButtonType.Normal)
    .stateEffect(true)
    .backgroundColor(this.headerButtonBackground)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
    .enabled(menuAction.enabled !== false)
    .accessibilityText(menuAction.label)
    .onClick(() => {
      if (menuAction.enabled !== false) {
        menuAction.action();
      }
    })
  }

  @Builder
  private buildCustomMenuActionButtonControl() {
    Button() {
      if (this.menuActionAiraIconId !== undefined) {
        AiraIcon({
          airaIconId: this.menuActionAiraIconId,
          iconSize: SETTINGS_TITLE_BAR_ACTION_ICON_SIZE,
          iconColor: this.resolveTitleActionIconColor()
        })
      } else if (this.menuActionImageIcon !== undefined) {
        Stack({ alignContent: Alignment.Center }) {
          ForEach([this.resolveMenuActionImageRenderKey()], (_renderKey: string) => {
            this.buildMenuActionImage()
          }, (renderKey: string) => renderKey)
        }
          .width(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
          .height(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
      } else {
        SymbolGlyph(this.resolveMenuActionIcon(this.menuActionIcon))
          .fontSize(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.resolveTitleActionIconColor()])
      }
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .type(ButtonType.Normal)
    .backgroundColor(this.headerButtonBackground)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
    .enabled(this.menuActionEnabled)
    .stateEffect(true)
    .accessibilityText(this.menuActionLabel)
    .onClick(() => {
      if (this.menuActionEnabled) {
        this.onMenuAction();
      }
    })
  }

  @Builder
  private buildMenuActionImage() {
    Image(this.resolveMenuActionImageIcon())
      .width(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
      .height(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
      .objectFit(ImageFit.Contain)
      .fillColor(this.resolveTitleActionIconColor())
  }

  @Builder
  private buildGlassPrivateIndicator() {
    Button() {
      SymbolGlyph($r('sys.symbol.lock_fill'))
        .fontSize(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor([this.resolveTitleActionIconColor()])
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .type(ButtonType.Normal)
    .stateEffect(false)
    .backgroundColor(this.headerButtonBackground)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityText('私密模式')
  }

  private refreshTopSafeInset(): void {
    this.topSafeInsetService.resolve(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((topSafeInsetVp: number) => {
        this.topSafeInsetVp = topSafeInsetVp;
      });
  }

  private syncStatusBarContentStyle(): void {
    this.statusBarStyleService.applyLightContentStyle(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      this.storedResolvedThemeMode === 'dark'
    );
  }

  private resolveTopSafeInset(): number {
    return Math.max(0, Math.ceil(this.topSafeInsetVp));
  }

  private resolveBackLabel(): string {
    return this.backIconKind === 'close' ? '关闭设置' : '返回设置';
  }

  private resolveBackIcon(): Resource {
    return $r('sys.symbol.chevron_left');
  }

  private resolveCustomMenuActionButtonTop(): number {
    return (this.useTopSafeInset ? this.resolveTopSafeInset() : 0) + SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_TOP;
  }

  private shouldShowTrailingTitleActions(): boolean {
    return this.menuActions.length > 0 || this.menuActionLabel.length > 0 || this.showPrivateIndicator;
  }

  private resolveMenuActionIcon(icon: Resource | undefined): Resource {
    return icon === undefined ? $r('sys.symbol.checkmark') : icon;
  }

  private resolveMenuActionImageIcon(): Resource {
    return this.menuActionImageIcon === undefined ? $r('sys.media.ohos_ic_public_more') : this.menuActionImageIcon;
  }

  private resolveTitleActionIconColor(): ResourceColor {
    return $r('sys.color.icon_primary');
  }

  private resolveMenuActionImageRenderKey(): string {
    return `${this.menuActionLabel}:${this.menuActionAiraIconId ?? 'image'}:${this.storedResolvedThemeMode}`;
  }

  @Builder
  private emptyContent() {
  }
}

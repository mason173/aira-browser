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
import { LengthMetrics, window } from '@kit.ArkUI';
import { BrowserStatusBarStyleService } from '../../../services/browser/BrowserStatusBarStyleService';
import { SettingsTopSafeInsetService } from '../../../services/settings/SettingsTopSafeInsetService';
import { SettingsContentFrame } from './SettingsContentFrame';
import { SettingsHeaderBlurScope } from './SettingsLayout';
import { SettingsHeaderScrollRegistry } from './SettingsHeaderScrollRegistry';
import { BROWSER_SHEET_BLUR_SCROLL_RANGE_VP } from '../browser/BrowserModalBottomSheet';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';

export type SettingsHdsBackIconKind = 'close' | 'back';

export interface SettingsHdsMenuAction {
  label: string;
  icon?: Resource;
  airaIconId?: AiraRenderableIconId;
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
const SETTINGS_TITLE_BAR_TEXT_ACTION_HEIGHT: number = 36;
const SETTINGS_TITLE_BAR_TEXT_ACTION_HORIZONTAL_PADDING: number = 16;
const SETTINGS_TITLE_BAR_TEXT_ACTION_FONT_SIZE: number = 14;

@Component
export struct SettingsHdsScaffold {
  private statusBarStyleService: BrowserStatusBarStyleService = new BrowserStatusBarStyleService();
  private topSafeInsetService: SettingsTopSafeInsetService = new SettingsTopSafeInsetService();
  private boundAvoidAreaWindow?: window.Window = undefined;
  private avoidAreaBindGeneration: number = 0;
  private readonly avoidAreaChangeCallback: (options: window.AvoidAreaOptions) => void =
    (_options: window.AvoidAreaOptions): void => {
      this.refreshTopSafeInset();
    };
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
  /**
   * Title-bar action rendered as a text pill instead of an icon button. Used by
   * the membership page, whose only title-bar action is the low-frequency but
   * must-be-findable “恢复购买”. Empty keeps the icon-only surfaces unchanged.
   */
  @Prop menuActionText: string = '';
  @Prop menuActionIcon: Resource | undefined = undefined;
  @Prop menuActionImageIcon: Resource | undefined = undefined;
  @Prop menuActionAiraIconId: AiraRenderableIconId | undefined = undefined;
  @Prop menuActionEnabled: boolean = true;
  @Prop menuActionBadgeVisible: boolean = false;
  @Prop menuActions: SettingsHdsMenuAction[] = [];
  /** One trailing more button that opens these actions, instead of one icon per action. */
  @Prop collapseMenuActions: boolean = false;
  /** Keep the title bar from painting a blur band over the content beneath it. */
  @Prop suppressContentBlur: boolean = false;
  scrollers: Array<Scroller> = [];
  private fallbackScroller: Scroller = new Scroller();
  @Provide('settingsHeaderScrollRegistry') scrollRegistry: SettingsHeaderScrollRegistry =
    new SettingsHeaderScrollRegistry();
  @State private registeredScrollers: Scroller[] = [];
  @State private topSafeInsetVp: number = 0;
  onBack: () => void = (): void => {};
  onMenuAction: () => void = (): void => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.syncStatusBarContentStyle();
    this.bindTopSafeInsetUpdates();
    this.scrollRegistry.setListener(() => {
      this.registeredScrollers = this.scrollRegistry.scrollers.slice();
    });
  }

  aboutToDisappear(): void {
    this.avoidAreaBindGeneration += 1;
    this.unbindTopSafeInsetUpdates();
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
    Column() {
      // Fullscreen layout starts under the status bar. Official clearance is
      // getWindowAvoidArea(TYPE_SYSTEM).topRect.height, applied here so the
      // title does not depend on HdsNavDestination.avoidLayoutSafeArea.
      Blank()
        .width('100%')
        .height(this.useTopSafeInset ? this.resolveTopSafeInset() : 0)
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
        avoidLayoutSafeArea: false,
        enableComponentSafeArea: true,
        style: {
          scrollEffectOpts: {
            enableScrollEffect: this.resolveHeaderBlurEnabled(),
            scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(this.resolveHeaderBlurEnabled() ?
              BROWSER_SHEET_BLUR_SCROLL_RANGE_VP : 0)
          },
          blurStrategy: BlurStrategy.ADAPTIVE,
          originalStyle: {
            backgroundStyle: {
              backgroundColor: Color.Transparent,
              maskExtraHeight: 0,
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
              maskExtraHeight: this.resolveHeaderBlurEnabled() ? 40 : 0,
              blurRadius: this.resolveHeaderBlurEnabled() ? 28 : 0
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
      .bindToScrollable(this.resolveTitleBarScrollers())
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.BOTTOM]
      )
      .hideBackButton(!this.showBackButton)
      .onBackPressed(() => {
        this.onBack();
        return true;
      })

      this.buildGlassTitleActions()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.desktopPresentation ? 1 : 0)
    .backgroundColor(this.pageBackground)
  }

  @Builder
  private buildContentFrame() {
    SettingsHeaderBlurScope({ headerBlurScroller: this.fallbackScroller }) {
      SettingsContentFrame({ kind: this.desktopPresentation ? 'unframed' : this.contentKind }) {
        this.content()
      }
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
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        this.buildTitleActionMaterialPlate()
      }
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
      .backgroundColor(this.resolveTitleActionBackground())
      .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
      .accessibilityText(this.resolveBackLabel())
      .onClick(() => {
        this.onBack();
      })
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
    .position({
      x: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_LEFT,
      y: this.resolveCustomMenuActionButtonTop()
    })
    .zIndex(4)
  }

  @Builder
  private buildGlassTrailingTitleActions() {
    Row({ space: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_GAP }) {
      if (this.menuActionText.length > 0) {
        this.buildGlassTextAction()
      }
      if (this.menuActions.length > 0 && this.collapseMenuActions) {
        this.buildCollapsedMenuAction()
      } else if (this.menuActions.length > 0) {
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
  private buildGlassTextAction() {
    // The pill sizes itself to its label, so the material plate wraps the button
    // instead of guessing a width from the font.
    Stack({ alignContent: Alignment.Center }) {
      Button() {
        Text(this.menuActionText)
          .fontSize(SETTINGS_TITLE_BAR_TEXT_ACTION_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveTitleActionIconColor())
          .maxLines(1)
      }
      .height(SETTINGS_TITLE_BAR_TEXT_ACTION_HEIGHT)
      .type(ButtonType.Normal)
      .stateEffect(true)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .borderRadius(SETTINGS_TITLE_BAR_TEXT_ACTION_HEIGHT / 2)
      .padding({ left: SETTINGS_TITLE_BAR_TEXT_ACTION_HORIZONTAL_PADDING, right: SETTINGS_TITLE_BAR_TEXT_ACTION_HORIZONTAL_PADDING })
      .accessibilityText(this.menuActionText)
      .onClick(() => {
        this.onMenuAction();
      })
    }
    .height(SETTINGS_TITLE_BAR_TEXT_ACTION_HEIGHT)
    .borderRadius(SETTINGS_TITLE_BAR_TEXT_ACTION_HEIGHT / 2)
    .backgroundColor(this.resolveTitleActionBackground())
  }

  @Builder
  private buildCollapsedMenuAction() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        this.buildTitleActionMaterialPlate()
      }
      Button() {
        AiraIcon({
          airaIconId: 'browser.toolbar.more',
          iconSize: SETTINGS_TITLE_BAR_ACTION_ICON_SIZE,
          iconColor: this.resolveTitleActionIconColor()
        })
      }
      .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
      .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
      .type(ButtonType.Normal)
      .stateEffect(true)
      .backgroundColor(this.resolveTitleActionBackground())
      .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
      .accessibilityText('更多操作')
      .bindMenu(this.buildCollapsedMenu())
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
  }

  @Builder
  private buildCollapsedMenu() {
    Menu() {
      ForEach(this.menuActions, (menuAction: SettingsHdsMenuAction) => {
        MenuItem({ content: menuAction.label })
          .enabled(menuAction.enabled !== false)
          .onClick(() => {
            if (menuAction.enabled !== false) {
              menuAction.action();
            }
          })
      }, (menuAction: SettingsHdsMenuAction) => menuAction.label)
    }
  }

  @Builder
  private buildGlassMenuAction(menuAction: SettingsHdsMenuAction) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        this.buildTitleActionMaterialPlate()
      }
      Button() {
        if (menuAction.airaIconId !== undefined) {
          AiraIcon({
            airaIconId: menuAction.airaIconId,
            iconSize: SETTINGS_TITLE_BAR_ACTION_ICON_SIZE,
            iconColor: this.resolveTitleActionIconColor()
          })
        } else {
          SymbolGlyph(this.resolveMenuActionIcon(menuAction.icon))
            .fontSize(SETTINGS_TITLE_BAR_ACTION_ICON_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.resolveTitleActionIconColor()])
        }
      }
      .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
      .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
      .type(ButtonType.Normal)
      .stateEffect(true)
      .backgroundColor(this.resolveTitleActionBackground())
      .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
      .enabled(menuAction.enabled !== false)
      .accessibilityText(menuAction.label)
      .onClick(() => {
        if (menuAction.enabled !== false) {
          menuAction.action();
        }
      })
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
  }

  @Builder
  private buildCustomMenuActionButtonControl() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        this.buildTitleActionMaterialPlate()
      }
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
      .backgroundColor(this.resolveTitleActionBackground())
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
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
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
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        this.buildTitleActionMaterialPlate()
      }
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
      .backgroundColor(this.resolveTitleActionBackground())
      .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityText('私密模式')
    }
    .width(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .height(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE)
    .borderRadius(SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2)
  }

  /**
   * Immersive light-sense backplate for a title-bar action. The action keeps its own Button
   * and gesture; the plate only supplies the material behind it.
   */
  @Builder
  private buildTitleActionMaterialPlate() {
    HdsImmersiveMaterialSurface({
      plateWidth: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE,
      plateHeight: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE,
      plateRadius: SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_SIZE / 2
    })
  }

  private shouldUseHdsMaterial(): boolean {
    return isHdsMaterialAvailable();
  }

  /**
   * The material paints the button surface itself, so the opaque HeaderButtonBackground has
   * to step aside or it would hide the material (the same rule as the bottom chrome).
   */
  private resolveTitleActionBackground(): ResourceColor {
    return this.shouldUseHdsMaterial() ?
      $r('sys.color.ohos_id_color_background_transparent') : this.headerButtonBackground;
  }

  private refreshTopSafeInset(): void {
    this.topSafeInsetService.resolve(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((topSafeInsetVp: number) => {
        this.topSafeInsetVp = topSafeInsetVp;
      });
  }

  private bindTopSafeInsetUpdates(): void {
    const generation = this.avoidAreaBindGeneration + 1;
    this.avoidAreaBindGeneration = generation;
    this.unbindTopSafeInsetUpdates();
    this.refreshTopSafeInset();
    window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((mainWindow: window.Window) => {
        if (generation !== this.avoidAreaBindGeneration) {
          return;
        }
        this.boundAvoidAreaWindow = mainWindow;
        try {
          mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
        } catch (_error) {
        }
      })
      .catch(() => {
      });
  }

  private unbindTopSafeInsetUpdates(): void {
    if (this.boundAvoidAreaWindow === undefined) {
      return;
    }
    try {
      this.boundAvoidAreaWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
    } catch (_error) {
    }
    this.boundAvoidAreaWindow = undefined;
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

  private resolveHeaderBlurEnabled(): boolean {
    return !this.suppressContentBlur && this.resolveTitleBarScrollers().length > 0;
  }

  private resolveTitleBarScrollers(): Scroller[] {
    if (this.scrollers.length > 0) {
      return this.scrollers;
    }
    if (this.registeredScrollers.length > 0) {
      return this.registeredScrollers;
    }
    return [this.fallbackScroller];
  }

  private resolveBackLabel(): string {
    return this.backIconKind === 'close' ? '关闭设置' : '返回设置';
  }

  private resolveBackIcon(): Resource {
    return $r('sys.symbol.chevron_left');
  }

  private resolveCustomMenuActionButtonTop(): number {
    // The scaffold already pads by the status-bar inset. The 8vp is the
    // button's place inside the 56vp title bar, not another status-bar offset.
    return SETTINGS_TITLE_BAR_CUSTOM_MENU_BUTTON_TOP;
  }

  private shouldShowTrailingTitleActions(): boolean {
    return this.menuActions.length > 0 || this.menuActionLabel.length > 0 || this.showPrivateIndicator ||
      this.menuActionText.length > 0;
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

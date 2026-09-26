import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { common } from '@kit.AbilityKit';
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
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveWindowTopSafeInsetVp } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';
import { AiraIcon } from './AiraIcon';
import { FloatingGlassMaterialSurface } from './FloatingGlassMaterialSurface';
import { HdsImmersiveMaterialSurface } from './HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from './HdsImmersiveMaterialTokens';
import { SettingsHeaderScrollRegistry } from '../settings/SettingsHeaderScrollRegistry';
import { BROWSER_SHEET_BLUR_SCROLL_RANGE_VP } from '../browser/BrowserModalBottomSheet';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from './FloatingGlassMaterialTokens';

export type ManagementHdsBackIconKind = 'close' | 'back';

export interface ManagementHdsMenuAction {
  label: string;
  icon?: Resource;
  enabled?: boolean;
  action: () => void;
}

const MANAGEMENT_TITLE_BAR_OVERFLOW_ICON_COUNT: number = 1;
const MANAGEMENT_TITLE_ACTION_SIZE: number = 40;
const MANAGEMENT_TITLE_ACTION_ICON_SIZE: number = 21;
const MANAGEMENT_TITLE_ACTION_EDGE_INSET: number = 16;
const MANAGEMENT_TITLE_ACTION_TOP_INSET: number = 8;
const MANAGEMENT_TITLE_ACTION_GAP: number = 8;
const MANAGEMENT_IMMERSIVE_TITLE_HEIGHT: number = 40;
const MANAGEMENT_IMMERSIVE_TITLE_HORIZONTAL_GAP: number = 12;
const MANAGEMENT_TITLE_ACTION_SHADOW_RADIUS: number = 28;
const MANAGEMENT_TITLE_ACTION_SHADOW_OFFSET_Y: number = 6;

export function resolveManagementImmersiveTitleBottomInset(topSafeInsetVp: number): number {
  return Math.max(0, Math.ceil(topSafeInsetVp)) + MANAGEMENT_TITLE_ACTION_TOP_INSET +
    MANAGEMENT_IMMERSIVE_TITLE_HEIGHT;
}

@Component
export struct ManagementHdsScaffold {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop title: string = '';
  @Prop backIconKind: ManagementHdsBackIconKind = 'close';
  @Prop pageBackground: ResourceColor = DEFAULT_THEME_PALETTE.light.pageBackground;
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop dividerColor: ResourceColor = '#E3E8EF';
  @Prop showPrivateIndicator: boolean = false;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop topSafeInsetVpOverride: number = -1;
  @Prop fillRemainingHeight: boolean = false;
  @Prop immersiveContent: boolean = false;
  @Prop menuActions: ManagementHdsMenuAction[] = [];
  @Prop titleBarMenuMaxCount: number = MANAGEMENT_TITLE_BAR_OVERFLOW_ICON_COUNT;
  @Prop elevateTitleActions: boolean = false;
  scrollers: Array<Scroller> = [];
  @Provide('settingsHeaderScrollRegistry') scrollRegistry: SettingsHeaderScrollRegistry =
    new SettingsHeaderScrollRegistry();
  @State private registeredScrollers: Scroller[] = [];
  @State private topSafeInsetVp: number = 0;
  onBack: () => void = (): void => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.refreshTopSafeInset();
    this.scrollRegistry.setListener(() => {
      this.registeredScrollers = this.scrollRegistry.scrollers.slice();
    });
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
      this.content()
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.fillRemainingHeight ? 1 : 0)
    .padding({ top: this.useTopSafeInset ? this.resolveTopSafeInset() : 0 })
    .backgroundColor(this.pageBackground)
  }

  @Builder
  private buildScaffoldWithTitleBar() {
    if (this.immersiveContent) {
      this.buildImmersiveScaffold()
    } else {
      Column() {
        Blank()
          .width('100%')
          .height(this.useTopSafeInset ? this.resolveTopSafeInset() : 0)
      Stack({ alignContent: Alignment.TopStart }) {
        HdsNavDestination() {
          this.content()
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
      .layoutWeight(this.fillRemainingHeight ? 1 : 0)
      .backgroundColor(this.pageBackground)
    }
  }

  @Builder
  private buildImmersiveScaffold() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavDestination() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageBackground)
      .hideTitleBar(true)
      .ignoreLayoutSafeArea(
        [LayoutSafeAreaType.SYSTEM],
        [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
      )
      .onBackPressed(() => {
        this.onBack();
        return true;
      })

      this.buildImmersiveTitle()
      this.buildGlassTitleActions()
    }
    .width('100%')
    .height('100%')
    .layoutWeight(this.fillRemainingHeight ? 1 : 0)
    .backgroundColor(this.pageBackground)
  }

  @Builder
  private buildImmersiveTitle() {
    Row() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(MANAGEMENT_IMMERSIVE_TITLE_HEIGHT)
    .padding({
      left: this.showBackButton
        ? MANAGEMENT_TITLE_ACTION_EDGE_INSET + MANAGEMENT_TITLE_ACTION_SIZE + MANAGEMENT_IMMERSIVE_TITLE_HORIZONTAL_GAP
        : MANAGEMENT_TITLE_ACTION_EDGE_INSET,
      right: this.resolveImmersiveTitleEndInset()
    })
    .position({ x: 0, y: this.resolveTitleActionTop() })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .zIndex(3)
  }

  @Builder
  private buildGlassTitleActions() {
    if (this.showBackButton) {
      this.buildGlassBackButton()
    }
    if (this.shouldShowTrailingActions()) {
      this.buildGlassTrailingActions()
    }
  }

  @Builder
  private buildGlassBackButton() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildTitleActionShadowCaster()
      FloatingGlassMaterialSurface({
        surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialEnabled: true,
        hostMaterialActive: this.shouldUseHdsMaterial()
      }) {
        if (this.shouldUseHdsMaterial()) {
          this.buildTitleActionMaterialPlate()
        }
        Button() {
          if (this.backIconKind === 'close') {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(MANAGEMENT_TITLE_ACTION_ICON_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.primaryTextColor])
          } else {
            AiraIcon({
              airaIconId: 'browser.toolbar.back',
              iconSize: MANAGEMENT_TITLE_ACTION_ICON_SIZE,
              iconColor: this.primaryTextColor
            })
          }
        }
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(MANAGEMENT_TITLE_ACTION_SIZE / 2)
        .stateEffect(true)
        .accessibilityText(this.resolveBackLabel())
        .onClick(() => {
          this.onBack();
        })
      }
    }
    .width(MANAGEMENT_TITLE_ACTION_SIZE)
    .height(MANAGEMENT_TITLE_ACTION_SIZE)
    .position({
      x: MANAGEMENT_TITLE_ACTION_EDGE_INSET,
      y: this.resolveTitleActionTop()
    })
    .zIndex(4)
  }

  @Builder
  private buildGlassTrailingActions() {
    Row({ space: MANAGEMENT_TITLE_ACTION_GAP }) {
      ForEach(this.resolveDirectMenuActions(), (menuAction: ManagementHdsMenuAction) => {
        this.buildGlassMenuAction(menuAction)
      }, (menuAction: ManagementHdsMenuAction) => menuAction.label)
      if (this.resolveOverflowMenuActions().length > 0) {
        this.buildGlassOverflowAction()
      }
      if (this.showPrivateIndicator) {
        this.buildGlassPrivateIndicator()
      }
    }
    .width('100%')
    .height(MANAGEMENT_TITLE_ACTION_SIZE)
    .padding({ right: MANAGEMENT_TITLE_ACTION_EDGE_INSET })
    .justifyContent(FlexAlign.End)
    .position({ x: 0, y: this.resolveTitleActionTop() })
    .hitTestBehavior(HitTestMode.Transparent)
    .zIndex(4)
  }

  @Builder
  private buildGlassMenuAction(menuAction: ManagementHdsMenuAction) {
    Stack({ alignContent: Alignment.Center }) {
      this.buildTitleActionShadowCaster()
      FloatingGlassMaterialSurface({
        surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialEnabled: true,
        hostMaterialActive: this.shouldUseHdsMaterial()
      }) {
        if (this.shouldUseHdsMaterial()) {
          this.buildTitleActionMaterialPlate()
        }
        Button() {
          SymbolGlyph(this.resolveMenuActionIcon(menuAction))
            .fontSize(MANAGEMENT_TITLE_ACTION_ICON_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor([this.primaryTextColor])
        }
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(MANAGEMENT_TITLE_ACTION_SIZE / 2)
        .stateEffect(true)
        .enabled(menuAction.enabled !== false)
        .accessibilityText(menuAction.label)
        .onClick(() => {
          if (menuAction.enabled !== false) {
            menuAction.action();
          }
        })
      }
    }
    .width(MANAGEMENT_TITLE_ACTION_SIZE)
    .height(MANAGEMENT_TITLE_ACTION_SIZE)
  }

  @Builder
  private buildGlassOverflowAction() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildTitleActionShadowCaster()
      FloatingGlassMaterialSurface({
        surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialEnabled: true,
        hostMaterialActive: this.shouldUseHdsMaterial()
      }) {
        if (this.shouldUseHdsMaterial()) {
          this.buildTitleActionMaterialPlate()
        }
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.more',
            iconSize: MANAGEMENT_TITLE_ACTION_ICON_SIZE,
            iconColor: this.primaryTextColor
          })
        }
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(MANAGEMENT_TITLE_ACTION_SIZE / 2)
        .stateEffect(true)
        .accessibilityText('更多操作')
        .bindMenu(this.buildOverflowMenu())
      }
    }
    .width(MANAGEMENT_TITLE_ACTION_SIZE)
    .height(MANAGEMENT_TITLE_ACTION_SIZE)
  }

  @Builder
  private buildOverflowMenu() {
    Menu() {
      ForEach(this.resolveOverflowMenuActions(), (menuAction: ManagementHdsMenuAction) => {
        MenuItem({ content: menuAction.label })
          .enabled(menuAction.enabled !== false)
          .onClick(() => {
            if (menuAction.enabled !== false) {
              menuAction.action();
            }
          })
      }, (menuAction: ManagementHdsMenuAction) => menuAction.label)
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }

  @Builder
  private buildGlassPrivateIndicator() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildTitleActionShadowCaster()
      FloatingGlassMaterialSurface({
        surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialEnabled: true,
        hostMaterialActive: this.shouldUseHdsMaterial()
      }) {
        if (this.shouldUseHdsMaterial()) {
          this.buildTitleActionMaterialPlate()
        }
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(MANAGEMENT_TITLE_ACTION_ICON_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.primaryTextColor])
      }
    }
    .width(MANAGEMENT_TITLE_ACTION_SIZE)
    .height(MANAGEMENT_TITLE_ACTION_SIZE)
    .hitTestBehavior(HitTestMode.None)
    .accessibilityText('私密会话')
  }

  private refreshTopSafeInset(): void {
    window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((mainWindow: window.Window) => {
        this.topSafeInsetVp = resolveWindowTopSafeInsetVp(mainWindow);
      })
      .catch((_error: Error) => {
        this.topSafeInsetVp = 0;
      });
  }

  private resolveTopSafeInset(): number {
    if (this.topSafeInsetVpOverride >= 0) {
      return Math.max(0, Math.ceil(this.topSafeInsetVpOverride));
    }
    return Math.max(0, Math.ceil(this.topSafeInsetVp));
  }

  private resolveHeaderBlurEnabled(): boolean {
    return this.resolveTitleBarScrollers().length > 0;
  }

  private resolveTitleBarScrollers(): Scroller[] {
    if (this.scrollers.length > 0) {
      return this.scrollers;
    }
    return this.registeredScrollers;
  }

  private resolveBackLabel(): string {
    return this.backIconKind === 'close' ? '关闭' : '返回';
  }

  private resolveBackIcon(): Resource {
    return this.backIconKind === 'close' ? $r('sys.media.ohos_ic_public_close') : $r('sys.symbol.chevron_left');
  }

  private resolveTitleActionTop(): number {
    // Immersive pages draw their own title over a full-bleed page, so the
    // status-bar inset stays on the title. The HDS title bar is padded by the
    // scaffold instead, and only needs the 8vp place inside the 56vp bar.
    if (this.immersiveContent) {
      return (this.useTopSafeInset ? this.resolveTopSafeInset() : 0) + MANAGEMENT_TITLE_ACTION_TOP_INSET;
    }
    return MANAGEMENT_TITLE_ACTION_TOP_INSET;
  }

  /**
   * Backplate that carries the immersive light-sense material behind a title-bar action.
   * A cluster renders it first so HDS materializes onto the button without owning any of
   * the button's own gestures.
   */
  @Builder
  private buildTitleActionMaterialPlate() {
    HdsImmersiveMaterialSurface({
      plateWidth: MANAGEMENT_TITLE_ACTION_SIZE,
      plateHeight: MANAGEMENT_TITLE_ACTION_SIZE,
      plateRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2
    })
  }

  private shouldUseHdsMaterial(): boolean {
    return isHdsMaterialAvailable();
  }

  @Builder
  private buildTitleActionShadowCaster() {
    // The cast fill is near-opaque on purpose, to lift a button off scrolled content. Behind
    // the immersive material it would instead be the sampled backdrop, turning the glass into
    // a flat disc, so the material-backed case draws no caster and lets the material be the
    // surface (the same trade the floating bottom chrome makes).
    if (this.elevateTitleActions && !this.shouldUseHdsMaterial()) {
      Stack()
        .width(MANAGEMENT_TITLE_ACTION_SIZE)
        .height(MANAGEMENT_TITLE_ACTION_SIZE)
        .borderRadius(MANAGEMENT_TITLE_ACTION_SIZE / 2)
        .backgroundColor(this.resolveTitleActionShadowFill())
        .shadow(this.resolveTitleActionShadow())
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  private resolveTitleActionShadowFill(): ResourceColor {
    return this.storedResolvedThemeMode === 'dark' ? '#F22C2C2C' : '#F7FFFFFF';
  }

  private resolveTitleActionShadow(): ShadowOptions {
    return {
      radius: MANAGEMENT_TITLE_ACTION_SHADOW_RADIUS,
      color: this.storedResolvedThemeMode === 'dark' ? '#59000000' : '#2A000000',
      offsetX: 0,
      offsetY: MANAGEMENT_TITLE_ACTION_SHADOW_OFFSET_Y
    };
  }

  private shouldShowTrailingActions(): boolean {
    return this.resolveTrailingActionSlotCount() > 0;
  }

  private resolveTrailingActionSlotCount(): number {
    let count = this.resolveDirectMenuActions().length;
    if (this.resolveOverflowMenuActions().length > 0) {
      count += 1;
    }
    if (this.showPrivateIndicator) {
      count += 1;
    }
    return count;
  }

  private resolveImmersiveTitleEndInset(): number {
    const slotCount = this.resolveTrailingActionSlotCount();
    if (slotCount <= 0) {
      return MANAGEMENT_TITLE_ACTION_EDGE_INSET;
    }
    return MANAGEMENT_TITLE_ACTION_EDGE_INSET +
      slotCount * MANAGEMENT_TITLE_ACTION_SIZE +
      (slotCount - 1) * MANAGEMENT_TITLE_ACTION_GAP +
      MANAGEMENT_IMMERSIVE_TITLE_HORIZONTAL_GAP;
  }

  private resolveDirectMenuActions(): ManagementHdsMenuAction[] {
    const maxCount = Math.max(1, this.titleBarMenuMaxCount);
    if (this.menuActions.length <= maxCount) {
      return this.menuActions;
    }
    return this.menuActions.slice(0, Math.max(0, maxCount - 1));
  }

  private resolveOverflowMenuActions(): ManagementHdsMenuAction[] {
    const maxCount = Math.max(1, this.titleBarMenuMaxCount);
    if (this.menuActions.length <= maxCount) {
      return [];
    }
    return this.menuActions.slice(Math.max(0, maxCount - 1));
  }

  private resolveMenuActionIcon(menuAction: ManagementHdsMenuAction): Resource {
    return menuAction.icon === undefined ? $r('sys.symbol.ellipsis_circle') : menuAction.icon;
  }

  @Builder
  private emptyContent() {
  }
}

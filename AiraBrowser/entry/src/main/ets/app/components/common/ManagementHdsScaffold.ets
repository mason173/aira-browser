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
  scrollers: Array<Scroller> = [];
  @State private topSafeInsetVp: number = 0;
  onBack: () => void = (): void => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
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
      .layoutWeight(this.fillRemainingHeight ? 1 : 0)
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
      right: this.shouldShowTrailingActions()
        ? MANAGEMENT_TITLE_ACTION_EDGE_INSET + MANAGEMENT_TITLE_ACTION_SIZE + MANAGEMENT_IMMERSIVE_TITLE_HORIZONTAL_GAP
        : MANAGEMENT_TITLE_ACTION_EDGE_INSET
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
      FloatingGlassMaterialSurface({
        surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialEnabled: true
      }) {
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
    FloatingGlassMaterialSurface({
      surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
      surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
      surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      materialEnabled: true
    }) {
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

  @Builder
  private buildGlassOverflowAction() {
    FloatingGlassMaterialSurface({
      surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
      surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
      surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      materialEnabled: true
    }) {
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
      FloatingGlassMaterialSurface({
        surfaceWidth: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceHeight: MANAGEMENT_TITLE_ACTION_SIZE,
        surfaceRadius: MANAGEMENT_TITLE_ACTION_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        materialEnabled: true
      }) {
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

  private resolveBackLabel(): string {
    return this.backIconKind === 'close' ? '关闭' : '返回';
  }

  private resolveBackIcon(): Resource {
    return this.backIconKind === 'close' ? $r('sys.media.ohos_ic_public_close') : $r('sys.symbol.chevron_left');
  }

  private resolveTitleActionTop(): number {
    return (this.useTopSafeInset ? this.resolveTopSafeInset() : 0) + MANAGEMENT_TITLE_ACTION_TOP_INSET;
  }

  private shouldShowTrailingActions(): boolean {
    return this.menuActions.length > 0 || this.showPrivateIndicator;
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

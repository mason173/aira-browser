import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserTabsOverviewLayoutStyle } from '../../../common/models/BrowserModels';
import {
  TabOverviewLayoutOptionState
} from '../../../core/settings/TabOverviewLayoutSettingsCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';
import { BrowserLargeScreenModalHeader } from '../browser/BrowserLargeScreenModalHeader';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';
import { SettingsGroupCard } from './SettingsLayout';
import { SettingsSwitchRow } from './SettingsRows';

const TAB_OVERVIEW_LAYOUT_SHEET_MAX_WIDTH: number = 620;
const TAB_OVERVIEW_LAYOUT_OPTION_PREVIEW_HEIGHT: number = 168;
const TAB_OVERVIEW_LAYOUT_RADIO_GROUP: string = 'tab-overview-layout-style';

@Component
export struct TabOverviewLayoutChoiceSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop options: TabOverviewLayoutOptionState[] = [];
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Prop closeButtonAlwaysVisible: boolean = false;
  @Prop isSaving: boolean = false;
  @Prop errorMessage: string = '';
  onSelect: (style: BrowserTabsOverviewLayoutStyle) => void = (_style: BrowserTabsOverviewLayoutStyle) => {};
  onCloseButtonAlwaysVisibleChange: (alwaysVisible: boolean) => void = (_alwaysVisible: boolean) => {};
  onCancel: () => void = () => {};
  onApply: () => void = () => {};

  build() {
    if (this.layoutMode === 'large_screen') {
      CenteredDialogSurface({ fillHeight: true }) {
        Column() {
          this.buildLargeScreenHeader()
          this.buildChoiceScroll(0, BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING)
          this.buildActionFooter()
        }
        .width('100%')
        .height('100%')
      }
    } else {
      BrowserBottomSheetSurface({
        maxWidth: TAB_OVERVIEW_LAYOUT_SHEET_MAX_WIDTH,
        surfaceColor: this.storedPageBackgroundColor,
        fullHeight: true,
        contentJustifyContent: FlexAlign.Start,
        horizontalPadding: 0,
        topPadding: 0,
        bottomPadding: 0
      }) {
        BrowserImmersiveSheetLayout({
          footerVisible: true,
          scrollContent: () => {
            this.buildPhoneScrollContent()
          },
          header: () => {
            this.buildPhoneHeader()
          },
          footer: () => {
            this.buildActionFooter()
          }
        })
      }
    }
  }

  @Builder
  private buildLargeScreenHeader() {
    BrowserLargeScreenModalHeader({
      title: '标签页样式',
      dialogMode: true,
      onClose: () => {
        this.onCancel();
      }
    })
  }

  @Builder
  private buildPhoneHeader() {
    // Keep this header in a @Builder. API 24 bindSheet crashes with
    // "class constructor cannot called without 'new'" if BrowserFeatureSheetHeader
    // is constructed directly inside a @BuilderParam arrow function.
    BrowserFeatureSheetHeader({
      title: '标签页样式',
      leadingAccessibilityLabel: '关闭标签页样式',
      onLeadingAction: () => {
        this.onCancel();
      }
    })
  }

  @Builder
  private buildPhoneScrollContent() {
    this.buildChoiceScroll(
      BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
      BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
    )
  }

  @Builder
  private buildChoiceScroll(topPadding: number, bottomPadding: number) {
    Scroll() {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          ForEach(this.options, (option: TabOverviewLayoutOptionState) => {
            TabOverviewLayoutOption({
              option: option,
              previewResource: this.resolvePreviewResource(option.style),
              onSelect: (style: BrowserTabsOverviewLayoutStyle) => {
                this.onSelect(style);
              }
            })
              .layoutWeight(1)
          }, (option: TabOverviewLayoutOptionState) =>
            `${option.style}:${option.isSelected ? 'selected' : 'idle'}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        SettingsGroupCard({}) {
          SettingsSwitchRow({
            title: '始终显示卡片关闭按钮',
            checked: this.closeButtonAlwaysVisible,
            rowPosition: 'single',
            isEnabled: !this.isSaving,
            onChange: (checked: boolean) => {
              this.onCloseButtonAlwaysVisibleChange(checked);
            }
          })
        }

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.storedAccentColor)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 16, right: 16, top: topPadding, bottom: bottomPadding })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }

  @Builder
  private buildActionFooter() {
    Row({ space: 12 }) {
      BrowserSheetActionButton({
        label: '取消',
        emphasis: 'secondary',
        actionEnabled: !this.isSaving,
        onAction: () => {
          this.onCancel();
        }
      })
      BrowserSheetActionButton({
        label: this.isSaving ? '应用中…' : '应用',
        emphasis: 'primary',
        actionEnabled: !this.isSaving,
        accentColor: this.storedAccentColor,
        onAction: () => {
          this.onApply();
        }
      })
    }
    .width('100%')
  }

  private resolvePreviewResource(style: BrowserTabsOverviewLayoutStyle): Resource {
    if (style === 'horizontal_cards') {
      return this.storedResolvedThemeMode === 'dark' ?
        $r('app.media.tab_overview_large_cards_dark') : $r('app.media.tab_overview_large_cards_light');
    }
    return this.storedResolvedThemeMode === 'dark' ?
      $r('app.media.tab_overview_grid_dark') : $r('app.media.tab_overview_grid_light');
  }
}

@Component
struct TabOverviewLayoutOption {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop option: TabOverviewLayoutOptionState = {
    style: 'grid',
    title: '卡片平铺',
    isSelected: false
  };
  @Prop previewResource: Resource = $r('app.media.tab_overview_grid_light');
  onSelect: (style: BrowserTabsOverviewLayoutStyle) => void = (_style: BrowserTabsOverviewLayoutStyle) => {};

  build() {
    Column({ space: 10 }) {
      Image(this.previewResource)
        .width('100%')
        .height(TAB_OVERVIEW_LAYOUT_OPTION_PREVIEW_HEIGHT)
        .objectFit(ImageFit.Contain)

      Text(this.option.title)
        .width('100%')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Radio({
        value: this.option.style,
        group: TAB_OVERVIEW_LAYOUT_RADIO_GROUP
      })
        .checked(this.option.isSelected)
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({ checkedBackgroundColor: this.storedAccentColor })
        .onChange((checked: boolean) => {
          if (checked) {
            this.onSelect(this.option.style);
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.onSelect(this.option.style);
    })
  }
}

import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  CustomHomepageInfoRowViewState,
  CustomHomepageInfoViewState
} from '../../../core/customhome/CustomHomepageInfoViewModel';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { SettingsGroupCard, SettingsGroupDivider } from '../settings/SettingsLayout';
import {
  BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';

const CUSTOM_HOMEPAGE_INFO_SHEET_MAX_HEIGHT: number = 620;
const CUSTOM_HOMEPAGE_INFO_SHEET_ACTION_CONTENT_MAX_HEIGHT: number = 540;

@Component
export struct CustomHomepageInfoSheet {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: CustomHomepageInfoViewState = {
    title: '',
    typeLabel: '',
    description: '',
    rows: []
  };
  @Prop presentation: 'bottom_sheet' | 'centered' = 'bottom_sheet';
  @Prop actionLabel: string = '';
  @Prop actionEnabled: boolean = true;
  onAction?: () => void;

  build() {
    if (this.presentation === 'centered') {
      CenteredDialogSurface() {
        this.buildSurfaceContent()
      }
    } else {
      this.buildSurfaceContent()
    }
  }

  @Builder
  private buildSurfaceContent() {
    Column() {
      Scroll() {
        Column({ space: 16 }) {
          this.buildHeader()
          if (this.state.description.length > 0) {
            this.buildDescriptionCard()
          }
          this.buildInformationCard()
        }
        .width('100%')
        .padding({
          left: APP_STANDARD_HORIZONTAL_PADDING,
          right: APP_STANDARD_HORIZONTAL_PADDING,
          top: 8,
          bottom: this.actionLabel.length > 0 ? 12 : 32
        })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({
        maxHeight: this.actionLabel.length > 0
          ? CUSTOM_HOMEPAGE_INFO_SHEET_ACTION_CONTENT_MAX_HEIGHT
          : CUSTOM_HOMEPAGE_INFO_SHEET_MAX_HEIGHT
      })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .linearGradientBlur(BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS, {
        fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
        direction: GradientDirection.Bottom
      })

      if (this.actionLabel.length > 0) {
        Row() {
          BrowserSheetActionButton({
            label: this.actionLabel,
            emphasis: 'primary',
            actionEnabled: this.actionEnabled,
            onAction: () => {
              this.onAction?.();
            }
          })
        }
        .width('100%')
        .padding({
            left: APP_STANDARD_HORIZONTAL_PADDING,
            right: APP_STANDARD_HORIZONTAL_PADDING,
            top: 8,
            bottom: 16
        })
      }
    }
    .width('100%')
    .backgroundColor(this.presentation === 'centered'
      ? Color.Transparent
      : this.storedPageBackgroundColor)
  }

  @Builder
  private buildHeader() {
    Column({ space: 6 }) {
      Text(this.state.title)
        .width('100%')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.state.typeLabel)
        .width('100%')
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 6, right: 6, top: 4 })
  }

  @Builder
  private buildDescriptionCard() {
    Column({ space: 8 }) {
      Text('开发者说明')
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedSecondaryTextColor)

      Text(this.state.description)
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)
        .wordBreak(WordBreak.BREAK_ALL)
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(22)
  }

  @Builder
  private buildInformationCard() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      ForEach(this.state.rows, (row: CustomHomepageInfoRowViewState, index: number) => {
        this.buildInformationRow(row)
        if (index < this.state.rows.length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (row: CustomHomepageInfoRowViewState) => row.id)
    }
  }

  @Builder
  private buildInformationRow(row: CustomHomepageInfoRowViewState) {
    Row({ space: 12 }) {
      Text(row.label)
        .width(88)
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)

      Text(row.value)
        .layoutWeight(1)
        .fontSize(row.technical ? 13 : 14)
        .lineHeight(20)
        .fontColor(this.storedPrimaryTextColor)
        .wordBreak(WordBreak.BREAK_ALL)
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .alignItems(VerticalAlign.Top)
  }
}

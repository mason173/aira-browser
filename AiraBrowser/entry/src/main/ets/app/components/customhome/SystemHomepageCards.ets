import {
  CustomHomepageSystemChoiceViewState
} from '../../../core/customhome/CustomHomepageSettingsViewModel';
import { CustomHomepagePreviewLayoutState } from '../../../core/customhome/CustomHomepagePreviewViewModel';
import { BrowserHomePageStyle } from '../../../common/models/HomePagePresentationSettingsModels';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SelectedCheckIndicator } from '../common/SelectedCheckIndicator';

const SYSTEM_PREVIEW_REFERENCE_CARD_WIDTH: number = 172;
const SYSTEM_PREVIEW_SELECTED_BADGE_SIZE: number = 28;
const SYSTEM_PREVIEW_GRID_COLUMNS: number = 4;

/**
 * Built-in homepage cards. Same card geometry as the installed homepage list, but no
 * overflow menu: there is nothing to export, delete, or inspect, and the frame is not
 * an installed record.
 *
 * The preview is drawn from the theme instead of a bitmap. When artwork lands, add the
 * packaged resource here and prefer it over the drawn schematic.
 */
@Component
export struct SystemHomepageCards {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop choices: CustomHomepageSystemChoiceViewState[] = [];
  @Prop busy: boolean = false;
  @Prop layoutState: CustomHomepagePreviewLayoutState = {
    cardWidth: 172,
    cardHeight: 340,
    listHeight: 372,
    cardGap: 18,
    cardRadius: 18,
    orientation: 'portrait'
  };

  onSelect: (style: BrowserHomePageStyle) => void = (_style: BrowserHomePageStyle) => {};

  build() {
    List({ space: this.layoutState.cardGap }) {
      ForEach(this.choices, (choice: CustomHomepageSystemChoiceViewState) => {
        ListItem() {
          this.buildSystemHomepageItem(choice)
        }
        .width(this.layoutState.cardWidth)
      }, (choice: CustomHomepageSystemChoiceViewState) => `${choice.style}-${choice.isActive}`)
    }
    .width('100%')
    .height(this.layoutState.listHeight)
    .listDirection(Axis.Horizontal)
    .scrollSnapAlign(ScrollSnapAlign.START)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .padding({ left: 2, right: 2 })
  }

  @Builder
  private buildSystemHomepageItem(choice: CustomHomepageSystemChoiceViewState) {
    Column({ space: 8 }) {
      Row() {
        Text(choice.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(24)
      .padding({ left: 2, right: 2 })
      .alignItems(VerticalAlign.Center)

      Stack() {
        this.buildSystemHomepagePreview(choice.style)
        if (choice.isActive) {
          Stack({ alignContent: Alignment.Bottom }) {
            SelectedCheckIndicator({
              indicatorSize: SYSTEM_PREVIEW_SELECTED_BADGE_SIZE,
              checkmarkSize: 17,
              indicatorColor: this.storedAccentColor,
              checkmarkColor: this.storedSurfaceBackgroundColor
            })
              .margin({ bottom: 10 })
              .accessibilityText('当前主页')
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Bottom)
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(this.layoutState.cardWidth)
      .height(this.layoutState.cardHeight)
      .borderRadius(this.layoutState.cardRadius)
      .border({ width: 0.5, color: this.storedDividerColor })
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .clip(true)
      .enabled(!this.busy)
      .opacity(this.busy ? 0.6 : 1)
      .accessibilityText(choice.isActive ? `${choice.title}，当前主页` : choice.title)
      .onClick(() => {
        this.onSelect(choice.style);
      })
    }
    .width(this.layoutState.cardWidth)
  }

  @Builder
  private buildSystemHomepagePreview(style: BrowserHomePageStyle) {
    Column() {
      if (style === 'centered') {
        this.buildCenteredHomepageSchematic()
      } else {
        this.buildClassicHomepageSchematic()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildClassicHomepageSchematic() {
    Column({ space: this.previewValue(6) }) {
      this.buildSchematicTileRow()
      this.buildSchematicTileRow()
      this.buildSchematicTileRow()

      Column({ space: this.previewValue(5) }) {
        this.buildSchematicBar('100%')
        this.buildSchematicBar('76%')
      }
      .width('100%')
      .padding({ top: this.previewValue(6) })

      Blank()

      Row({ space: this.previewValue(8) }) {
        this.buildSchematicBarWithWeight(1)
        this.buildSchematicBarWithWeight(0.5)
        this.buildSchematicBarWithWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.previewValue(12),
      right: this.previewValue(12),
      top: this.previewValue(16),
      bottom: this.previewValue(16)
    })
  }

  @Builder
  private buildCenteredHomepageSchematic() {
    Column({ space: this.previewValue(10) }) {
      Column()
        .width('58%')
        .height(this.previewValue(12))
        .borderRadius(this.previewValue(6))
        .backgroundColor(this.storedPrimaryTextColor)

      Row() {
        Column()
          .width(this.previewValue(9))
          .height(this.previewValue(9))
          .borderRadius(this.previewValue(3))
          .backgroundColor(this.storedPrimaryTextColor)
      }
      .width('84%')
      .height(this.previewValue(24))
      .padding({ right: this.previewValue(5) })
      .borderWidth(this.previewValue(2))
      .borderColor(this.storedPrimaryTextColor)
      .borderRadius(this.previewValue(12))
      .justifyContent(FlexAlign.End)

      Row({ space: this.previewValue(7) }) {
        this.buildSchematicCircle()
        this.buildSchematicCircle()
        this.buildSchematicCircle()
        this.buildSchematicCircle()
        this.buildSchematicCircle()
      }
      .justifyContent(FlexAlign.Center)
      .padding({ top: this.previewValue(4) })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildSchematicTileRow() {
    Row({ space: this.previewValue(6) }) {
      ForEach(this.buildSchematicTileIndexes(), (_index: number) => {
        Column()
          .width(this.schematicTileSize())
          .height(this.schematicTileSize())
          .borderRadius(this.previewValue(9))
          .backgroundColor(this.storedControlBackgroundColor)
      }, (index: number) => `${index}`)
    }
    .width('100%')
  }

  @Builder
  private buildSchematicBar(width: string) {
    Column()
      .width(width)
      .height(this.previewValue(5))
      .borderRadius(this.previewValue(3))
      .backgroundColor(this.storedControlBackgroundColor)
  }

  @Builder
  private buildSchematicBarWithWeight(weight: number) {
    Column()
      .layoutWeight(weight > 0 ? weight : 1)
      .height(this.previewValue(6))
      .borderRadius(this.previewValue(3))
      .backgroundColor(this.storedControlBackgroundColor)
  }

  @Builder
  private buildSchematicCircle() {
    Column()
      .width(this.previewValue(16))
      .height(this.previewValue(16))
      .borderRadius(this.previewValue(8))
      .backgroundColor(this.storedControlBackgroundColor)
  }

  private buildSchematicTileIndexes(): number[] {
    const indexes: number[] = [];
    for (let index = 0; index < SYSTEM_PREVIEW_GRID_COLUMNS; index++) {
      indexes.push(index);
    }
    return indexes;
  }

  private schematicTileSize(): number {
    const innerWidth = this.layoutState.cardWidth - this.previewValue(12) * 2;
    const totalGap = this.previewValue(6) * (SYSTEM_PREVIEW_GRID_COLUMNS - 1);
    return Math.max(6, Math.floor((innerWidth - totalGap) / SYSTEM_PREVIEW_GRID_COLUMNS));
  }

  private previewValue(value: number): number {
    const scale = this.layoutState.cardWidth / SYSTEM_PREVIEW_REFERENCE_CARD_WIDTH;
    return Math.max(1, Math.round(value * scale));
  }
}

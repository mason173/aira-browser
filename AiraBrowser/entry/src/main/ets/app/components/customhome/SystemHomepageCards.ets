import {
  CustomHomepageSystemChoiceViewState
} from '../../../core/customhome/CustomHomepageSettingsViewModel';
import { CustomHomepagePreviewLayoutState } from '../../../core/customhome/CustomHomepagePreviewViewModel';
import { BrowserHomePageStyle } from '../../../common/models/HomePagePresentationSettingsModels';
import { resolveSystemHomepagePreviewResource } from '../../../core/customhome/SystemHomepageStyleCatalog';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SelectedCheckIndicator } from '../common/SelectedCheckIndicator';

const SYSTEM_PREVIEW_SELECTED_BADGE_SIZE: number = 28;

/**
 * Built-in homepage cards. Same card geometry as the installed homepage list, but no
 * overflow menu: there is nothing to export, delete, or inspect, and the frame is not
 * an installed record.
 *
 * Previews are packaged SVG wireframes (see `SystemHomepageStyleCatalog`). They are
 * transparent with neutral translucent shapes, so they read on both theme surfaces.
 */
@Component
export struct SystemHomepageCards {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
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
        Image(resolveSystemHomepagePreviewResource(choice.style))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
          .draggable(false)
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
}

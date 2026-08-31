import { CustomHomepageChoiceViewState } from '../../../core/customhome/CustomHomepageSettingsViewModel';
import { CustomHomepagePreviewLayoutState } from '../../../core/customhome/CustomHomepagePreviewViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import { SiteIconView } from '../common/SiteIconView';
import { SelectedCheckIndicator } from '../common/SelectedCheckIndicator';

const HOMEPAGE_PREVIEW_OVERFLOW_BUTTON_SIZE: number = 34;
const HOMEPAGE_PREVIEW_OVERFLOW_ICON_SIZE: number = 18;
const HOMEPAGE_PREVIEW_OVERFLOW_INSET: number = 10;
const HOMEPAGE_PREVIEW_REMOTE_ICON_SIZE: number = 62;
const HOMEPAGE_PREVIEW_SELECTED_BADGE_SIZE: number = 28;

@Component
export struct CustomHomepagePreviewCards {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop choices: CustomHomepageChoiceViewState[] = [];
  @Prop selectedChoiceId: string = '';
  @Prop revision: number = 0;
  @Prop busy: boolean = false;
  @Prop layoutState: CustomHomepagePreviewLayoutState = {
    cardWidth: 172,
    cardHeight: 340,
    listHeight: 372,
    cardGap: 18,
    cardRadius: 18,
    orientation: 'portrait'
  };

  onSelect: (choice: CustomHomepageChoiceViewState) => void = (_choice: CustomHomepageChoiceViewState) => {};
  onImport: () => void = () => {};
  onInfo: (choice: CustomHomepageChoiceViewState) => void = (_choice: CustomHomepageChoiceViewState) => {};
  onExport: (choice: CustomHomepageChoiceViewState) => void = (_choice: CustomHomepageChoiceViewState) => {};
  onRemove: (choice: CustomHomepageChoiceViewState) => void = (_choice: CustomHomepageChoiceViewState) => {};

  build() {
    List({ space: this.layoutState.cardGap }) {
      ForEach(this.choices, (choice: CustomHomepageChoiceViewState) => {
        ListItem() {
          this.buildHomepagePreviewItem(choice)
        }
        .width(this.layoutState.cardWidth)
      }, (choice: CustomHomepageChoiceViewState) => `${choice.id}-${this.revision}`)
      ListItem() {
        this.buildImportHomepageItem()
      }
      .width(this.layoutState.cardWidth)
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
  private buildHomepagePreviewItem(choice: CustomHomepageChoiceViewState) {
    Column({ space: 8 }) {
      this.buildHomepageCardTitle(choice.title)
      this.buildHomepagePreviewCard(choice)
    }
    .width(this.layoutState.cardWidth)
  }

  @Builder
  private buildImportHomepageItem() {
    Column({ space: 8 }) {
      this.buildHomepageCardTitle('导入主页')
      this.buildImportHomepageCard()
    }
    .width(this.layoutState.cardWidth)
  }

  @Builder
  private buildHomepagePreviewCard(choice: CustomHomepageChoiceViewState) {
    Stack() {
      this.buildHomepagePreviewImage(choice)
      if (choice.id === this.selectedChoiceId) {
        this.buildCurrentHomepageBadge()
      }
      if (choice.isRemoteUrl && choice.previewPath.trim().length <= 0) {
        this.buildRemoteUrlPlaceholder(choice)
      }
      this.buildHomepageOverflowButton(choice)
    }
    .width(this.layoutState.cardWidth)
    .height(this.layoutState.cardHeight)
    .borderRadius(this.layoutState.cardRadius)
    .border({ width: 0.5, color: this.storedDividerColor })
    .clip(true)
    .enabled(!this.busy)
    .opacity(this.busy ? 0.6 : 1)
    .onClick(() => {
      this.onSelect(choice);
    })
  }

  @Builder
  private buildHomepageOverflowButton(choice: CustomHomepageChoiceViewState) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Button({ type: ButtonType.Circle }) {
        AiraIcon({
          airaIconId: 'browser.toolbar.more',
          iconSize: HOMEPAGE_PREVIEW_OVERFLOW_ICON_SIZE,
          iconColor: this.storedSecondaryTextColor
        })
      }
      .width(HOMEPAGE_PREVIEW_OVERFLOW_BUTTON_SIZE)
      .height(HOMEPAGE_PREVIEW_OVERFLOW_BUTTON_SIZE)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .border({ width: 0.5, color: this.storedDividerColor })
      .borderRadius(HOMEPAGE_PREVIEW_OVERFLOW_BUTTON_SIZE / 2)
      .margin({ top: HOMEPAGE_PREVIEW_OVERFLOW_INSET, right: HOMEPAGE_PREVIEW_OVERFLOW_INSET })
      .enabled(!this.busy)
      .accessibilityText(`更多“${choice.title}”操作`)
      .bindMenu([
        {
          value: '查看信息',
          action: () => {
            this.onInfo(choice);
          }
        },
        {
          value: '导出',
          action: () => {
            this.onExport(choice);
          }
        },
        {
          value: '删除',
          action: () => {
            this.onRemove(choice);
          }
        }
      ])
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildCurrentHomepageBadge() {
    Stack({ alignContent: Alignment.Bottom }) {
      SelectedCheckIndicator({
        indicatorSize: HOMEPAGE_PREVIEW_SELECTED_BADGE_SIZE,
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

  @Builder
  private buildRemoteUrlPlaceholder(choice: CustomHomepageChoiceViewState) {
    Column({ space: 12 }) {
      SiteIconView({
        iconUri: choice.siteIconPath,
        fallbackLabel: choice.title,
        iconSize: HOMEPAGE_PREVIEW_REMOTE_ICON_SIZE,
        cornerRadiusRatio: 0.3,
        frameBorderWidth: choice.siteIconPath.length > 0 ? 0 : 1,
        contentPadding: 0,
        fallbackFontSize: 24,
        containerBackgroundColor: this.storedControlBackgroundColor,
        frameBorderColor: this.storedDividerColor,
        textColor: this.storedSecondaryTextColor,
        fit: ImageFit.Contain,
        hitTestMode: HitTestMode.None
      })
      Text(choice.title)
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(16)
    .align(Alignment.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildImportHomepageCard() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.storedAccentColor])
    }
    .width(this.layoutState.cardWidth)
    .height(this.layoutState.cardHeight)
    .borderRadius(this.layoutState.cardRadius)
    .border({ width: 0.5, color: this.storedDividerColor })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .clip(true)
    .enabled(!this.busy)
    .opacity(this.busy ? 0.6 : 1)
    .onClick(() => {
      this.onImport();
    })
  }

  @Builder
  private buildHomepageCardTitle(title: string) {
    Row() {
      Text(title)
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
  }

  @Builder
  private buildHomepagePreviewImage(choice: CustomHomepageChoiceViewState) {
    if (choice.previewResource !== undefined) {
      Image(choice.previewResource)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
    } else if (choice.previewPath.trim().length > 0) {
      Image(choice.previewPath)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.storedControlBackgroundColor)
    }
  }

}

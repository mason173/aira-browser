import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';

const SETTINGS_SECTION_TITLE_LEFT_PADDING: number = 6;
const SETTINGS_GROUP_CORNER_RADIUS: number = 22;
const SETTINGS_GROUP_HORIZONTAL_PADDING: number = 4;
const SETTINGS_GROUP_VERTICAL_PADDING: number = 4;
const SETTINGS_GROUP_DIVIDER_HORIZONTAL_MARGIN: number = 16;
export const SETTINGS_DESKTOP_SCROLLBAR_GUTTER: number = APP_STANDARD_HORIZONTAL_PADDING;

@Component
export struct SettingsScrollBody {
  @Prop contentSpace: number = 16;
  @Prop topPadding: number = 0;
  @Prop bottomPadding: number = 28;
  @Prop scrollEnabled: boolean = true;
  @Prop scrollInteractionEnabled: boolean = true;
  @Prop clipContent: boolean = false;
  @Prop topGradientBlurRadius: number = 0;
  scroller?: Scroller;
  onContentAreaChanged: (area: Area) => void = (_area: Area) => {};
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Scroll(this.scroller) {
      Column({ space: this.contentSpace }) {
        this.content()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING,
        top: this.topPadding,
        bottom: this.bottomPadding
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.onContentAreaChanged(newArea);
      })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollable(this.scrollEnabled ? ScrollDirection.Vertical : ScrollDirection.None)
    .enableScrollInteraction(this.scrollInteractionEnabled)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .linearGradientBlur(this.topGradientBlurRadius, {
      fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
      direction: GradientDirection.Bottom
    })
    .clip(this.clipContent)
  }

  @Builder
  private emptyContent() {
  }
}

/**
 * Scroll body for content that can be hosted by either a touch page or the
 * large-screen settings workspace. The workspace already owns its horizontal
 * content track, so embedded desktop content must not add a second inset.
 */
@Component
export struct SettingsPresentationScrollBody {
  @Prop contentSpace: number = 16;
  @Prop topPadding: number = 0;
  @Prop bottomPadding: number = 28;
  @Prop desktopPresentation: boolean = false;
  @Prop scrollEnabled: boolean = true;
  @Prop scrollInteractionEnabled: boolean = true;
  @Prop clipContent: boolean = false;
  scroller?: Scroller;
  onContentAreaChanged: (area: Area) => void = (_area: Area) => {};
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Scroll(this.scroller) {
      Column({ space: this.contentSpace }) {
        this.content()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: this.desktopPresentation ? 0 : APP_STANDARD_HORIZONTAL_PADDING,
        right: this.desktopPresentation ? SETTINGS_DESKTOP_SCROLLBAR_GUTTER : APP_STANDARD_HORIZONTAL_PADDING,
        top: this.topPadding,
        bottom: this.bottomPadding
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.onContentAreaChanged(newArea);
      })
    }
    .layoutWeight(1)
    .width('100%')
    .scrollable(this.scrollEnabled ? ScrollDirection.Vertical : ScrollDirection.None)
    .enableScrollInteraction(this.scrollInteractionEnabled)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(this.desktopPresentation || this.clipContent)
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct SettingsSection {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Column({ space: 10 }) {
      if (`${this.title}`.length > 0) {
        SettingsSectionTitle({
          title: this.title,
          secondaryTextColor: this.resolveSecondaryTextColor()
        })
      }
      this.content()
    }
    .width('100%')
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct SettingsSectionTitle {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop leftPadding: number = SETTINGS_SECTION_TITLE_LEFT_PADDING;

  build() {
    Text(this.title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.resolveSecondaryTextColor())
      .padding({ left: this.leftPadding })
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }
}

@Component
export struct SettingsGroupCard {
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @Prop surfaceColor: ResourceColor = '';
  @Prop fullHeight: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.fullHeight ? '100%' : '')
    .padding({
      left: SETTINGS_GROUP_HORIZONTAL_PADDING,
      right: SETTINGS_GROUP_HORIZONTAL_PADDING,
      top: SETTINGS_GROUP_VERTICAL_PADDING,
      bottom: SETTINGS_GROUP_VERTICAL_PADDING
    })
    .backgroundColor(this.resolveSurfaceColor())
    .borderRadius(this.desktopPresentation ? 8 : SETTINGS_GROUP_CORNER_RADIUS)
    .clip(true)
  }

  private resolveSurfaceColor(): ResourceColor {
    return `${this.surfaceColor}`.length > 0 ? this.surfaceColor : this.storedSurfaceBackgroundColor;
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct SettingsGroupDivider {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @Prop dividerColor: ResourceColor = '';

  build() {
    Divider()
      .width('100%')
      .height(1)
      .color(this.resolveDividerColor())
      .margin({
        left: SETTINGS_GROUP_DIVIDER_HORIZONTAL_MARGIN,
        right: SETTINGS_GROUP_DIVIDER_HORIZONTAL_MARGIN
      })
  }

  private resolveDividerColor(): ResourceColor {
    return `${this.dividerColor}`.length > 0 ? this.dividerColor : this.storedDividerColor;
  }
}

@Component
export struct SettingsFooterText {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop text: ResourceStr = '';
  @Prop secondaryTextColor: ResourceColor = '';

  build() {
    Text(this.text)
      .width('100%')
      .fontSize(13)
      .lineHeight(18)
      .fontColor(this.resolveSecondaryTextColor())
      .padding({ left: 6, right: 6 })
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }
}

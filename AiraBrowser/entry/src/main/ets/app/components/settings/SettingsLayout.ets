import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { sharedBrowsingActivitySignal } from '../../../common/activity/BrowsingActivitySignal';
import { SettingsHeaderScrollRegistry } from './SettingsHeaderScrollRegistry';

const SETTINGS_SECTION_TITLE_LEFT_PADDING: number = 6;
const SETTINGS_GROUP_CORNER_RADIUS: number = 22;
const SETTINGS_GROUP_HORIZONTAL_PADDING: number = 4;
const SETTINGS_GROUP_VERTICAL_PADDING: number = 4;
const SETTINGS_GROUP_DIVIDER_HORIZONTAL_MARGIN: number = 16;
export const SETTINGS_DESKTOP_SCROLLBAR_GUTTER: number = APP_STANDARD_HORIZONTAL_PADDING;

/** @Provide cannot hold a Scroller directly, so the shared instance lives in this holder. */
class SettingsHeaderBlurScrollerRef {
  scroller: Scroller = new Scroller();
}

/**
 * Shares one Scroller between a settings title bar and the scroll under it.
 * The title bar binds this object on the first frame; the scroll body uses it
 * when the page did not bring its own.
 */
@Component
export struct SettingsHeaderBlurScope {
  headerBlurScroller: Scroller = new Scroller();
  @Provide('settingsHeaderBlurScroller') headerBlurScrollerRef: SettingsHeaderBlurScrollerRef =
    new SettingsHeaderBlurScrollerRef();
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.headerBlurScrollerRef.scroller = this.headerBlurScroller;
  }

  build() {
    this.content()
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct SettingsScrollBody {
  @Prop contentSpace: number = 16;
  @Prop topPadding: number = 0;
  @Prop bottomPadding: number = 28;
  @Prop scrollEnabled: boolean = true;
  @Prop scrollInteractionEnabled: boolean = true;
  @Prop clipContent: boolean = false;
  scroller?: Scroller;
  @Consume('settingsHeaderScrollRegistry') scrollRegistry: SettingsHeaderScrollRegistry =
    new SettingsHeaderScrollRegistry();
  @Consume('settingsHeaderBlurScroller') headerBlurScrollerRef: SettingsHeaderBlurScrollerRef =
    new SettingsHeaderBlurScrollerRef();
  onContentAreaChanged: (area: Area) => void = (_area: Area) => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.scrollRegistry.bind(this.resolveScroller());
  }

  build() {
    Scroll(this.resolveScroller()) {
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
    .onDidScroll((xOffset: number, yOffset: number): void => {
      if (xOffset !== 0 || yOffset !== 0) {
        sharedBrowsingActivitySignal.markBrowsingInteraction();
      }
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    // No linearGradientBlur here on purpose. With it, a sheet overlaying this
    // container flashed the region it covered blank for one frame on dismiss;
    // removing it fixed that. The likely mechanism is that a blur node, even at
    // radius 0, puts the scroll content into an offscreen render group that is
    // discarded and rebuilt when the overlay above it is removed. This container
    // never received a non-zero radius, so no visible effect is lost.
    .clip(this.clipContent)
  }

  private resolveScroller(): Scroller {
    return this.scroller !== undefined ? this.scroller : this.headerBlurScrollerRef.scroller;
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
  @Consume('settingsHeaderScrollRegistry') scrollRegistry: SettingsHeaderScrollRegistry =
    new SettingsHeaderScrollRegistry();
  @Consume('settingsHeaderBlurScroller') headerBlurScrollerRef: SettingsHeaderBlurScrollerRef =
    new SettingsHeaderBlurScrollerRef();
  onContentAreaChanged: (area: Area) => void = (_area: Area) => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.scrollRegistry.bind(this.resolveScroller());
  }

  build() {
    Scroll(this.resolveScroller()) {
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
    .onDidScroll((xOffset: number, yOffset: number): void => {
      if (xOffset !== 0 || yOffset !== 0) {
        sharedBrowsingActivitySignal.markBrowsingInteraction();
      }
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(this.desktopPresentation || this.clipContent)
  }

  private resolveScroller(): Scroller {
    return this.scroller !== undefined ? this.scroller : this.headerBlurScrollerRef.scroller;
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
  @Prop titleLeftPadding: number = SETTINGS_SECTION_TITLE_LEFT_PADDING;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Column({ space: 10 }) {
      if (`${this.title}`.length > 0) {
        SettingsSectionTitle({
          title: this.title,
          secondaryTextColor: this.resolveSecondaryTextColor(),
          leftPadding: this.titleLeftPadding
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
  // A dialog whose surface is already the card color cannot show this wrapper.
  // Flatten it and bleed the row padding back out so text shares the section baseline.
  @Prop flat: boolean = false;
  @Prop horizontalBleed: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.fullHeight ? '100%' : '')
    .margin({
      left: -this.horizontalBleed,
      right: -this.horizontalBleed
    })
    .padding({
      left: this.flat ? 0 : SETTINGS_GROUP_HORIZONTAL_PADDING,
      right: this.flat ? 0 : SETTINGS_GROUP_HORIZONTAL_PADDING,
      top: this.flat ? 0 : SETTINGS_GROUP_VERTICAL_PADDING,
      bottom: this.flat ? 0 : SETTINGS_GROUP_VERTICAL_PADDING
    })
    .backgroundColor(this.flat ? Color.Transparent : this.resolveSurfaceColor())
    .borderRadius(this.flat ? 0 : (this.desktopPresentation ? 8 : SETTINGS_GROUP_CORNER_RADIUS))
    .clip(!this.flat)
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
  @Prop horizontalMargin: number = SETTINGS_GROUP_DIVIDER_HORIZONTAL_MARGIN;

  build() {
    Divider()
      .width('100%')
      .height(1)
      .color(this.resolveDividerColor())
      .margin({
        left: this.horizontalMargin,
        right: this.horizontalMargin
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
  @Prop horizontalPadding: number = SETTINGS_SECTION_TITLE_LEFT_PADDING;

  build() {
    Text(this.text)
      .width('100%')
      .fontSize(13)
      .lineHeight(18)
      .fontColor(this.resolveSecondaryTextColor())
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding })
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }
}

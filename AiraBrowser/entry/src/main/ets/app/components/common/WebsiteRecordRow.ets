import { image } from '@kit.ImageKit';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from './FloatingGlassMaterialTokens';
import {
  DEFAULT_WEBSITE_ICON_CONTENT_RATIO,
  WebsiteIconVariant,
  WebsiteIconView
} from './WebsiteIconView';
import {
  RECORD_LIST_ROW_CONTENT_SPACE,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_HORIZONTAL_INSET,
  RECORD_LIST_ROW_ICON_SIZE,
  RECORD_LIST_ROW_MENU_WIDTH,
  RECORD_LIST_ROW_RADIUS,
  RECORD_LIST_ROW_SUBTITLE_SIZE,
  RECORD_LIST_ROW_TITLE_SIZE
} from './RecordListTokens';
import { normalizeHomeWallpaperTransitionDuration } from '../../../core/wallpaper/HomeWallpaperPresentationTokens';

@Component
export struct WebsiteRecordRow {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: string = '';
  @Prop titleMeta: string = '';
  @Prop subtitle: string = '';
  @Prop fallbackLabel: string = '#';
  @Prop iconUri: string = '';
  @Prop iconPixelMap: image.PixelMap | undefined = undefined;
  @Prop pressed: boolean = false;
  @Prop menuVisible: boolean = false;
  @Prop showDivider: boolean = false;
  @Prop leftInset: number = RECORD_LIST_ROW_HORIZONTAL_INSET;
  @Prop rightInset: number = RECORD_LIST_ROW_HORIZONTAL_INSET;
  @Prop rowHeight: number = RECORD_LIST_ROW_HEIGHT;
  @Prop rowBorderRadius: number | BorderRadiuses = RECORD_LIST_ROW_RADIUS;
  @Prop pressedBorderRadius: number | BorderRadiuses | undefined = undefined;
  @Prop iconVariant: WebsiteIconVariant = 'list';
  @Prop iconSize: number = 0;
  @Prop iconSlotSize: number = 0;
  @Prop iconContentRatio: number = DEFAULT_WEBSITE_ICON_CONTENT_RATIO;
  @Prop iconCornerRadius: number = 0;
  @Prop iconCornerRadiusRatio: number = 0.3;
  @Prop fallbackFontSize: number = 0;
  @Prop preferPixelMap: boolean = false;
  @Prop sourceRevision: number = 0;
  @Prop menuWidth: number = RECORD_LIST_ROW_MENU_WIDTH;
  @Prop pressedHorizontalInset: number = 0;
  @Prop pressedVerticalInset: number = 0;
  @Prop primaryTextColor: ResourceColor | undefined = undefined;
  @Prop secondaryTextColor: ResourceColor | undefined = undefined;
  @Prop fallbackIconTextColor: ResourceColor | undefined = undefined;
  @Prop previewPrimaryTextColor: ResourceColor | undefined = undefined;
  @Prop previewSecondaryTextColor: ResourceColor | undefined = undefined;
  @Prop pressedBackgroundColor: ResourceColor | undefined = undefined;
  @Prop pressedBackdropBlurRadius: number = 0;
  @Prop textShadow: Array<ShadowOptions> = [];
  @Prop foregroundTransitionDurationMs: number = 0;

  onTouchAction: (type: TouchType) => void = (_type: TouchType) => {};
  onOpenMenu: () => void = () => {};
  onRowClick: () => void = () => {};
  onMenuAppear: () => void = () => {};
  onMenuDisappear: () => void = () => {};
  onIconLoadError: (iconUri: string, sourceRevision: number) => void =
    (_iconUri: string, _sourceRevision: number) => {};

  @BuilderParam leadingAccessory: () => void = this.emptyBuilder;
  @BuilderParam leading: () => void = this.buildIcon;
  @BuilderParam trailing: () => void = this.emptyBuilder;
  @BuilderParam previewTrailing: () => void = this.emptyBuilder;
  @BuilderParam menuContent: () => void = this.emptyBuilder;

  build() {
    Column({ space: 0 }) {
      this.buildInteractiveRow()

      if (this.showDivider) {
        Divider()
          .margin({ left: this.resolveDividerLeft(), right: this.rightInset })
          .color(this.storedDividerColor)
      }
    }
    .width('100%')
  }

  @Builder
  private buildInteractiveRow() {
    Row() {
      Row({ space: RECORD_LIST_ROW_CONTENT_SPACE }) {
        this.buildLeadingContent()

        this.trailing()
      }
      .width('100%')
      .height(this.rowHeight - this.resolvePressedVerticalInset() * 2)
      .padding({ left: this.leftInset - this.resolvePressedHorizontalInset(), right: this.rightInset - this.resolvePressedHorizontalInset() })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveBackgroundColor())
      .backdropBlur(this.resolveBackdropBlurRadius())
      .borderRadius(this.resolveInteractiveRowBorderRadius())
      .clip(true)
    }
    .width('100%')
    .height(this.rowHeight)
    .padding({
      left: this.resolvePressedHorizontalInset(),
      right: this.resolvePressedHorizontalInset(),
      top: this.resolvePressedVerticalInset(),
      bottom: this.resolvePressedVerticalInset()
    })
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      this.onTouchAction(event.type);
    })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
          .onAction(() => {
            this.onOpenMenu();
          }),
        TapGesture()
          .onAction(() => {
            this.onRowClick();
          })
      )
    )
    .bindContextMenu(this.menuVisible, this.buildMenu(), {
      preview: this.buildPreview(),
      previewBorderRadius: this.rowBorderRadius,
      onAppear: () => {
        this.onMenuAppear();
      },
      onDisappear: () => {
        this.onMenuDisappear();
      }
    })
  }

  @Builder
  private buildLeadingContent() {
    Row({ space: RECORD_LIST_ROW_CONTENT_SPACE }) {
      this.leadingAccessory()

      this.leading()

      Column({ space: this.hasSubtitle() ? 4 : 0 }) {
        this.buildTitleLine()

        if (this.hasSubtitle()) {
          Text(this.subtitle)
            .width('100%')
            .fontSize(RECORD_LIST_ROW_SUBTITLE_SIZE)
            .fontColor(this.resolveSecondaryTextColor())
            .textShadow(this.textShadow)
            .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildIcon() {
    if (this.iconSlotSize > 0) {
      Row() {
        this.buildWebsiteIcon()
      }
      .width(this.iconSlotSize)
      .height(this.iconSlotSize)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    } else {
      this.buildWebsiteIcon()
    }
  }

  @Builder
  private buildWebsiteIcon() {
    WebsiteIconView({
      iconUri: this.iconUri,
      iconPixelMap: this.iconPixelMap,
      fallbackLabel: this.fallbackLabel,
      variant: this.iconVariant,
      iconSize: this.iconSize,
      contentRatio: this.iconContentRatio,
      cornerRadius: this.iconCornerRadius,
      cornerRadiusRatio: this.iconCornerRadiusRatio,
      fallbackFontSize: this.fallbackFontSize,
      preferPixelMap: this.preferPixelMap,
      sourceRevision: this.sourceRevision,
      containerBackgroundColor: this.storedSurfaceBackgroundColor,
      frameBorderColor: this.storedDividerColor,
      textColor: this.resolveFallbackIconTextColor(),
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.onIconLoadError(iconUri, sourceRevision);
      }
    })
  }

  @Builder
  private buildPreview() {
    Row({ space: RECORD_LIST_ROW_CONTENT_SPACE }) {
      this.leadingAccessory()

      this.leading()

      Column({ space: this.hasSubtitle() ? 4 : 0 }) {
        this.buildPreviewTitleLine()

        if (this.hasSubtitle()) {
          Text(this.subtitle)
            .fontSize(RECORD_LIST_ROW_SUBTITLE_SIZE)
            .fontColor(this.resolvePreviewSecondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.previewTrailing()
    }
    .width('100%')
    .height(this.rowHeight)
    .padding({ left: this.leftInset, right: this.rightInset })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.rowBorderRadius)
  }

  @Builder
  private buildTitleLine() {
    Row({ space: 8 }) {
      Text(this.title)
        .fontSize(RECORD_LIST_ROW_TITLE_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryTextColor())
        .textShadow(this.textShadow)
        .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })

      if (this.titleMeta.length > 0) {
        Text(this.titleMeta)
          .fontSize(RECORD_LIST_ROW_SUBTITLE_SIZE)
          .fontColor(this.resolveSecondaryTextColor())
          .textShadow(this.textShadow)
          .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildPreviewTitleLine() {
    Row({ space: 8 }) {
      Text(this.title)
        .fontSize(RECORD_LIST_ROW_TITLE_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePreviewPrimaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })

      if (this.titleMeta.length > 0) {
        Text(this.titleMeta)
          .fontSize(RECORD_LIST_ROW_SUBTITLE_SIZE)
          .fontColor(this.resolvePreviewSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildMenu() {
    Menu() {
      this.menuContent()
    }
    .width(this.menuWidth)
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }

  private resolveDividerLeft(): number {
    const leadingSize = this.iconSlotSize > 0
      ? this.iconSlotSize
      : (this.iconSize > 0 ? this.iconSize : RECORD_LIST_ROW_ICON_SIZE);
    return this.leftInset + leadingSize + RECORD_LIST_ROW_CONTENT_SPACE;
  }

  private hasSubtitle(): boolean {
    return this.subtitle.trim().length > 0;
  }

  private resolvePressedHorizontalInset(): number {
    return Math.min(Math.max(0, this.pressedHorizontalInset), Math.min(this.leftInset, this.rightInset));
  }

  private resolvePressedVerticalInset(): number {
    return Math.min(Math.max(0, this.pressedVerticalInset), Math.floor(this.rowHeight / 2));
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }

  private resolveFallbackIconTextColor(): ResourceColor {
    return this.fallbackIconTextColor === undefined ? this.storedPrimaryTextColor : this.fallbackIconTextColor;
  }

  private resolvePreviewPrimaryTextColor(): ResourceColor {
    return this.previewPrimaryTextColor === undefined ? this.storedPrimaryTextColor : this.previewPrimaryTextColor;
  }

  private resolvePreviewSecondaryTextColor(): ResourceColor {
    return this.previewSecondaryTextColor === undefined ? this.storedSecondaryTextColor : this.previewSecondaryTextColor;
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.pressed
      ? this.resolvePressedBackgroundColor()
      : $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    return this.pressedBackgroundColor === undefined ? this.storedPressedBackgroundColor : this.pressedBackgroundColor;
  }

  private resolveBackdropBlurRadius(): number {
    return this.pressed ? Math.max(0, this.pressedBackdropBlurRadius) : 0;
  }

  private resolveForegroundTransitionDuration(): number {
    return normalizeHomeWallpaperTransitionDuration(this.foregroundTransitionDurationMs);
  }

  private resolveInteractiveRowBorderRadius(): number | BorderRadiuses {
    if (this.pressed && this.pressedBorderRadius !== undefined) {
      return this.pressedBorderRadius;
    }
    return this.rowBorderRadius;
  }

  @Builder
  private emptyBuilder() {
  }
}

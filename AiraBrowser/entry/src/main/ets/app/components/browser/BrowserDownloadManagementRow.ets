import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  DownloadManagementRowAction,
  DownloadManagementRowMenuActionView,
  DownloadManagementRowState
} from '../../../core/download/DownloadManagerViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveDownloadFileTypeImage } from './DownloadFileTypeIcon';
import { SelectedCheckIndicator } from '../common/SelectedCheckIndicator';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem,
  buildBrowserDesktopMenuOptions
} from './BrowserDesktopContextMenu';
import {
  MANAGEMENT_LARGE_SCREEN_ROW_INSET,
  MANAGEMENT_LARGE_SCREEN_ROW_RADIUS
} from '../common/ManagementLargeScreenShell';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';

const DOWNLOAD_CARD_ACTION_VISUAL_SIZE: number = 36;
const DOWNLOAD_CARD_ACTION_HIT_SIZE: number = 48;
const DOWNLOAD_CARD_ACTION_HIT_INSET: number =
  (DOWNLOAD_CARD_ACTION_HIT_SIZE - DOWNLOAD_CARD_ACTION_VISUAL_SIZE) / 2;
const DOWNLOAD_CARD_TEXT_ACTION_HEIGHT: number = 40;
const DOWNLOAD_CARD_COMPLETED_ACTION_HEIGHT: number = 32;
const DOWNLOAD_CARD_COMPLETED_ACTION_HORIZONTAL_PADDING: number = 12;
const DOWNLOAD_CARD_RADIUS: number = 22;
const DOWNLOAD_CARD_PRESSED_BACKDROP_BLUR_RADIUS: number = 36;

@Component
export struct BrowserDownloadManagementRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @ObjectLink row: DownloadManagementRowState;
  @State private cardPressed: boolean = false;
  @State private contextMenuVisible: boolean = false;
  @Prop presentation: 'card' | 'desktop_row' = 'card';
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @State private desktopHovered: boolean = false;
  @State private desktopPressed: boolean = false;
  onAction: (guid: string, action: DownloadManagementRowAction) => void =
    (_guid: string, _action: DownloadManagementRowAction): void => {};
  onToggleSelection: (guid: string) => void = (_guid: string): void => {};

  build() {
    if (this.presentation === 'desktop_row') {
      this.buildDesktopRow()
    } else if (this.row.status === 'completed') {
      this.buildCompletedCard()
    } else {
      this.buildActiveCard()
    }
  }

  @Builder
  private buildDesktopRow() {
    Row({ space: 12 }) {
      Image(this.resolveFileTypeImage())
        .width(28)
        .height(28)
        .objectFit(ImageFit.Contain)
        .flexShrink(0)

      Column({ space: 2 }) {
        this.buildFileNameText()
        if (this.row.status === 'completed') {
          this.buildCompletedSubtitle()
        } else {
          this.buildActiveSubtitle()
          this.buildTaskProgressBlock()
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.selectionMode) {
        this.buildSelectionCheckbox()
      } else if (this.row.primaryAction !== undefined && (this.row.status !== 'completed' || this.desktopHovered)) {
        this.buildPrimaryActionButton()
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({
      left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
      right: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
      top: 8,
      bottom: 8
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.resolveDesktopRowBackground())
    .borderRadius(MANAGEMENT_LARGE_SCREEN_ROW_RADIUS)
    .clip(true)
    .onHover((hovered: boolean): void => {
      this.desktopHovered = hovered;
      if (!hovered) {
        this.desktopPressed = false;
      }
    })
    .onTouch((event: TouchEvent): void => {
      this.handleDesktopTouch(event);
    })
    .onMouse((event: MouseEvent): void => {
      this.handleDesktopMouse(event);
    })
    .onClick((): void => {
      if (this.selectionMode) {
        this.onToggleSelection(this.row.guid);
        return;
      }
      if (this.row.status === 'completed') {
        this.handleCompletedCardClick();
      }
    })
    .bindContextMenuWithResponse(
      this.buildDesktopContextMenuResponse,
      buildBrowserDesktopMenuOptions({
        preview: MenuPreviewMode.NONE,
        onAppear: (): void => {
          this.desktopPressed = false;
        }
      })
    )
  }

  private handleDesktopTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.desktopPressed = true;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.desktopPressed = false;
    }
  }

  private handleDesktopMouse(event: MouseEvent): void {
    if (event.button !== MouseButton.Left) {
      return;
    }
    if (event.action === MouseAction.Press) {
      this.desktopPressed = true;
      return;
    }
    if (event.action === MouseAction.Release || event.action === MouseAction.CANCEL) {
      this.desktopPressed = false;
    }
  }

  /**
   * PC rows are used with a mouse and with touch. Right click and long press open the
   * same actions the phone card already offers from a long press.
   */
  @Builder
  private buildDesktopContextMenuResponse(responseType: ResponseType) {
    if ((responseType === ResponseType.LongPress || responseType === ResponseType.RightClick) &&
      !this.selectionMode && this.row.menuActions.length > 0) {
      this.buildDesktopContextMenu()
    }
  }

  @Builder
  private buildDesktopContextMenu() {
    BrowserDesktopContextMenu() {
      ForEach(this.row.menuActions, (menuAction: DownloadManagementRowMenuActionView) => {
        BrowserDesktopContextMenuItem({
          label: menuAction.label,
          reserveCheckmark: false,
          onAction: (): void => {
            this.onAction(this.row.guid, menuAction.action);
          }
        })
      }, (menuAction: DownloadManagementRowMenuActionView): string => `${menuAction.action}:${menuAction.label}`)
    }
  }

  private resolveDesktopRowBackground(): ResourceColor {
    if (this.desktopPressed || this.selected || this.desktopHovered) {
      return this.storedPressedBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  @Builder
  private buildCompletedCard() {
    Row({ space: 12 }) {
      this.buildFileTypeIcon()

      Column({ space: 6 }) {
        this.buildFileNameText()
        this.buildCompletedSubtitle()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.selectionMode) {
        this.buildSelectionCheckbox()
      } else if (this.row.primaryAction !== undefined) {
        this.buildPrimaryActionButton()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.resolveInteractiveCardBackgroundColor())
    .backdropBlur(this.resolveInteractiveCardBackdropBlurRadius())
    .borderRadius(DOWNLOAD_CARD_RADIUS)
    .clip(true)
    .onTouch((event: TouchEvent): void => {
      this.handleCardTouch(event);
    })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
          .onAction((): void => {
            this.openContextMenu();
          }),
        TapGesture()
          .onAction((): void => {
            this.handleCompletedCardClick();
          })
      )
    )
    .bindContextMenu(this.shouldShowContextMenu(), this.buildContextMenu(), {
      preview: this.buildCompletedCardPreview(),
      previewBorderRadius: DOWNLOAD_CARD_RADIUS,
      onDisappear: (): void => {
        this.dismissContextMenu();
      }
    })
  }

  @Builder
  private buildActiveCard() {
    Row({ space: 12 }) {
      this.buildFileTypeIcon()

      Column({ space: 5 }) {
        this.buildFileNameText()
        this.buildActiveSubtitle()
        this.buildTaskProgressBlock()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        if (this.selectionMode) {
          this.buildSelectionCheckbox()
        } else if (this.row.primaryAction !== undefined) {
          this.buildPrimaryActionButton()
        }
      }
      .flexShrink(0)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.resolveInteractiveCardBackgroundColor())
    .backdropBlur(this.resolveInteractiveCardBackdropBlurRadius())
    .borderRadius(DOWNLOAD_CARD_RADIUS)
    .clip(true)
    .onTouch((event: TouchEvent): void => {
      this.handleCardTouch(event);
    })
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
          .onAction((): void => {
            this.openContextMenu();
          }),
        TapGesture()
          .onAction((): void => {
            if (this.selectionMode) {
              this.onToggleSelection(this.row.guid);
            }
          })
      )
    )
    .bindContextMenu(this.shouldShowContextMenu(), this.buildContextMenu(), {
      preview: this.buildActiveCardPreview(),
      previewBorderRadius: DOWNLOAD_CARD_RADIUS,
      onDisappear: (): void => {
        this.dismissContextMenu();
      }
    })
  }

  @Builder
  private buildFileTypeIcon() {
    Image(this.resolveFileTypeImage())
      .width(44)
      .height(44)
      .objectFit(ImageFit.Contain)
      .accessibilityText(this.resolveFileTypeLabel())
      .flexShrink(0)
  }

  @Builder
  private buildActiveCardPreview() {
    Row({ space: 12 }) {
      this.buildFileTypeIcon()

      Column({ space: 5 }) {
        this.buildFileNameText()
        this.buildActiveSubtitle()
        this.buildTaskProgressBlock()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.row.primaryAction !== undefined) {
        this.buildPrimaryActionButton()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(DOWNLOAD_CARD_RADIUS)
  }

  @Builder
  private buildCompletedCardPreview() {
    Row({ space: 12 }) {
      this.buildFileTypeIcon()

      Column({ space: 6 }) {
        this.buildFileNameText()
        this.buildCompletedSubtitle()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.row.primaryAction !== undefined) {
        this.buildPrimaryActionButton()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(DOWNLOAD_CARD_RADIUS)
  }

  @Builder
  private buildActiveSubtitle() {
    Text(this.resolveActiveSubtitleText())
      .width('100%')
      .fontSize(12)
      .lineHeight(18)
      .fontColor(this.storedSecondaryTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildCompletedSubtitle() {
    Text(this.buildCompletedMetaText())
      .width('100%')
      .fontSize(12)
      .lineHeight(18)
      .fontColor(this.storedSecondaryTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildFileNameText() {
    Text(this.row.fileName)
      .width('100%')
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.storedPrimaryTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildTaskProgressBlock() {
    Row({ space: 8 }) {
      Progress({
        value: this.row.progressValue,
        total: 100,
        type: ProgressType.Linear
      })
        .layoutWeight(1)
        .height(4)
        .style({ strokeWidth: 4, enableSmoothEffect: false })
        .borderRadius(2)
        .color(this.storedAccentColor)
        .backgroundColor(this.storedDividerColor)

      Text(`${this.row.progressValue}%`)
        .fontSize(11)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildPrimaryActionButton() {
    if (this.shouldUsePrimaryActionIconButton()) {
      Button() {
        SymbolGlyph(this.resolvePrimaryActionIcon())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.resolvePrimaryButtonFontColor()])
      }
      .width(DOWNLOAD_CARD_ACTION_VISUAL_SIZE)
      .height(DOWNLOAD_CARD_ACTION_VISUAL_SIZE)
      .type(ButtonType.Normal)
      .backgroundColor(this.resolvePrimaryButtonBackgroundColor())
      .borderRadius(DOWNLOAD_CARD_ACTION_VISUAL_SIZE / 2)
      .stateEffect(true)
      .responseRegion({
        x: -DOWNLOAD_CARD_ACTION_HIT_INSET,
        y: -DOWNLOAD_CARD_ACTION_HIT_INSET,
        width: DOWNLOAD_CARD_ACTION_HIT_SIZE,
        height: DOWNLOAD_CARD_ACTION_HIT_SIZE
      })
      .accessibilityText(this.row.primaryActionLabel)
      .onClick(() => {
        if (this.row.primaryAction !== undefined) {
          this.onAction(this.row.guid, this.row.primaryAction);
        }
      })
    } else {
      Button(this.row.primaryActionLabel)
        .height(this.isCompletedOpenAction() ?
          DOWNLOAD_CARD_COMPLETED_ACTION_HEIGHT : DOWNLOAD_CARD_TEXT_ACTION_HEIGHT)
        .type(ButtonType.Normal)
        .fontSize(this.isCompletedOpenAction() ? 13 : 14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryButtonFontColor())
        .backgroundColor(this.resolvePrimaryButtonBackgroundColor())
        .borderRadius(this.isCompletedOpenAction() ?
          DOWNLOAD_CARD_COMPLETED_ACTION_HEIGHT / 2 : 18)
        .padding({
          left: this.isCompletedOpenAction() ? DOWNLOAD_CARD_COMPLETED_ACTION_HORIZONTAL_PADDING : 18,
          right: this.isCompletedOpenAction() ? DOWNLOAD_CARD_COMPLETED_ACTION_HORIZONTAL_PADDING : 18
        })
        .stateEffect(true)
        .onClick(() => {
          if (this.row.primaryAction !== undefined) {
            this.onAction(this.row.guid, this.row.primaryAction);
          }
        })
    }
  }

  private resolvePrimaryButtonFontColor(): ResourceColor {
    if (this.isCompletedOpenAction()) {
      return this.storedAccentColor;
    }
    if (this.isNeutralDownloadControl()) {
      return this.storedPrimaryTextColor;
    }
    return this.storedOnPrimaryColor;
  }

  private resolvePrimaryButtonBackgroundColor(): ResourceColor {
    if (this.isCompletedOpenAction()) {
      return this.storedControlBackgroundColor;
    }
    if (this.isNeutralDownloadControl()) {
      return this.storedControlBackgroundColor;
    }
    return this.storedAccentColor;
  }

  private isNeutralDownloadControl(): boolean {
    return this.row.primaryAction === 'pause' || this.row.primaryAction === 'resume' ||
      this.row.primaryActionEmphasis === 'secondary';
  }

  private isCompletedOpenAction(): boolean {
    return this.row.status === 'completed' && this.row.primaryAction === 'open_file';
  }

  private shouldUsePrimaryActionIconButton(): boolean {
    return this.row.primaryAction === 'pause' ||
      this.row.primaryAction === 'resume';
  }

  private resolvePrimaryActionIcon(): Resource {
    if (this.row.primaryAction === 'resume') {
      return $r('sys.symbol.play_fill');
    }
    return $r('sys.symbol.pause_fill');
  }

  private isCompletedCardClickable(): boolean {
    return this.row.status === 'completed' && this.row.primaryAction === 'open_file';
  }

  @Builder
  private buildSelectionCheckbox() {
    // Display-only: the row owns the single selection toggle.
    Stack() {
      if (this.selected) {
        SelectedCheckIndicator({ indicatorSize: 22 })
      } else {
        Circle()
          .width(22)
          .height(22)
          .fill(Color.Transparent)
          .stroke(this.storedSecondaryTextColor)
          .strokeWidth(1.5)
      }
    }
    .width(22)
    .height(22)
    .hitTestBehavior(HitTestMode.None)
    .focusable(false)
  }

  private resolveInteractiveCardBackgroundColor(): ResourceColor {
    if (this.cardPressed) {
      return this.storedPressedBackgroundColor;
    }
    if (this.selectionMode && this.selected) {
      return this.storedControlBackgroundColor;
    }
    return this.storedSurfaceBackgroundColor;
  }

  private resolveInteractiveCardBackdropBlurRadius(): number {
    return this.cardPressed ? DOWNLOAD_CARD_PRESSED_BACKDROP_BLUR_RADIUS : 0;
  }

  private handleCardTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.cardPressed = true;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.cardPressed = false;
    }
  }

  private handleCompletedCardClick(): void {
    if (this.selectionMode) {
      this.onToggleSelection(this.row.guid);
      return;
    }
    if (!this.isCompletedCardClickable()) {
      return;
    }
    this.onAction(this.row.guid, 'open_file');
  }

  private buildCompletedMetaText(): string {
    if (this.row.completionTimeText.length === 0) {
      return this.row.completionSizeText.length > 0 ? this.row.completionSizeText : this.row.sourceText;
    }
    if (this.row.completionSizeText.length === 0) {
      return this.row.completionTimeText;
    }
    return `${this.row.completionTimeText} · ${this.row.completionSizeText}`;
  }

  private openContextMenu(): void {
    if (this.selectionMode) {
      return;
    }
    if (this.row.menuActions.length > 0) {
      this.contextMenuVisible = true;
    }
  }

  private shouldShowContextMenu(): boolean {
    return this.contextMenuVisible && !this.selectionMode && this.row.menuActions.length > 0;
  }

  private dismissContextMenu(): void {
    this.contextMenuVisible = false;
    this.cardPressed = false;
  }

  @Builder
  private buildContextMenu() {
    Menu() {
      ForEach(this.row.menuActions, (menuAction: DownloadManagementRowMenuActionView) => {
        MenuItem({ content: menuAction.label })
          .onClick((): void => {
            this.contextMenuVisible = false;
            this.onAction(this.row.guid, menuAction.action);
          })
      }, (menuAction: DownloadManagementRowMenuActionView): string => {
        return `${menuAction.action}:${menuAction.label}`;
      })
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }

  private resolveActiveSubtitleText(): string {
    if (this.row.statusText.length > 0) {
      return this.row.statusText;
    }
    if (this.row.trailingText.length > 0) {
      return this.row.trailingText;
    }
    if (this.row.detailText.length > 0) {
      return this.row.detailText;
    }
    return this.row.sourceText;
  }

  private resolveFileTypeImage(): Resource {
    return resolveDownloadFileTypeImage(this.row.fileType);
  }

  private resolveFileTypeLabel(): string {
    switch (this.row.fileType) {
      case 'archive':
        return resolveAppResourceText($r('app.string.browser_ui_browser_download_management_row_001'));
      case 'video':
        return resolveAppResourceText($r('app.string.media_resource_tab_video'));
      case 'audio':
        return resolveAppResourceText($r('app.string.media_resource_kind_audio'));
      case 'image':
        return resolveAppResourceText($r('app.string.media_resource_kind_image'));
      case 'spreadsheet':
        return resolveAppResourceText($r('app.string.browser_ui_browser_download_management_row_006'));
      case 'presentation':
        return resolveAppResourceText($r('app.string.browser_ui_browser_download_management_row_004'));
      case 'web':
        return resolveAppResourceText($r('app.string.browser_ui_browser_download_management_row_005'));
      case 'json':
        return 'JSON';
      case 'apk':
        return 'APK';
      case 'hap':
        return 'HAP';
      case 'pdf':
        return 'PDF';
      case 'text':
        return resolveAppResourceText($r('app.string.browser_ui_browser_download_management_row_003'));
      case 'document':
        return resolveAppResourceText($r('app.string.media_resource_kind_document'));
      default:
        return resolveAppResourceText($r('app.string.browser_ui_browser_download_management_row_002'));
    }
  }
}

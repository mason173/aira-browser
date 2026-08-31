import {
  BrowserBookmarkActionSessionSnapshot,
  BrowserBookmarkFolderSelectionAction
} from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { BookmarkFolderOptionView } from '../../../core/browser/BookmarkFolderSelectionViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';

const LARGE_SCREEN_BOOKMARK_BUTTON_SIZE_VP: number = 28;
const LARGE_SCREEN_BOOKMARK_ICON_SIZE_VP: number = 17;
const LARGE_SCREEN_BOOKMARK_POPUP_WIDTH_VP: number = 360;
const LARGE_SCREEN_BOOKMARK_POPUP_RADIUS_VP: number = 16;
const LARGE_SCREEN_BOOKMARK_FOLDER_LIST_MAX_HEIGHT_VP: number = 232;
const LARGE_SCREEN_BOOKMARK_FOLDER_ROW_HEIGHT_VP: number = 38;
const LARGE_SCREEN_BOOKMARK_TARGET_SPACE_VP: number = 6;
const LARGE_SCREEN_BOOKMARK_POPUP_FIXED_HEIGHT_VP: number = 170;

const EMPTY_BOOKMARK_SESSION: BrowserBookmarkActionSessionSnapshot = {
  actionVersion: 0,
  scope: 'regular',
  addToHome: false,
  preparing: false,
  options: []
};

@Component
export struct BrowserLargeScreenBookmarkPopover {
  @Prop actionEnabled: boolean = false;
  @Prop actionSelected: boolean = false;
  @Prop disabledMessage: string = '';
  @Prop @Watch('syncSelectedFolder') session: BrowserBookmarkActionSessionSnapshot = EMPTY_BOOKMARK_SESSION;
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onOpen: () => void = () => {};
  onAction: (action: BrowserBookmarkFolderSelectionAction) => void =
    (_action: BrowserBookmarkFolderSelectionAction): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  @State private popupVisible: boolean = false;
  @State private selectedFolderId: string = '';
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();

  build() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: this.actionSelected ? 'browser.omnibox.bookmarked' : 'browser.omnibox.addBookmark',
        iconSize: LARGE_SCREEN_BOOKMARK_ICON_SIZE_VP,
        iconColor: this.actionSelected ? this.storedAccentColor : this.storedSecondaryTextColor
      })
    }
    .width(LARGE_SCREEN_BOOKMARK_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_BOOKMARK_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(this.actionEnabled)
    .enabled(this.actionEnabled)
    .opacity(this.actionEnabled ? 1 : 0.38)
    .accessibilityText(this.actionSelected ? '取消书签' : '添加书签')
    .onClick(() => {
      if (!this.actionEnabled) {
        this.showDisabledMessage();
        return;
      }
      if (!this.actionSelected) {
        this.selectedFolderId = this.resolveSelectedFolderId();
        this.popupVisible = true;
      }
      this.onOpen();
    })
    .bindPopup(this.popupVisible, {
      builder: this.buildBookmarkPopup,
      placement: Placement.BottomRight,
      popupColor: this.storedFloatingSurfaceColor,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: LARGE_SCREEN_BOOKMARK_TARGET_SPACE_VP,
      width: this.resolvePopupWidth(),
      radius: LARGE_SCREEN_BOOKMARK_POPUP_RADIUS_VP,
      showInSubWindow: false,
      focusable: true,
      shadow: {
        radius: 24,
        color: $r('app.color.elevation_shadow'),
        offsetX: 0,
        offsetY: 8
      },
      onStateChange: (event: PopupStateChangeParam) => {
        const wasVisible = this.popupVisible;
        this.popupVisible = event.isVisible;
        if (wasVisible && !event.isVisible) {
          this.onAction({ type: 'dismiss' });
        }
      }
    })
  }

  @Builder
  private buildBookmarkPopup() {
    Column({ space: 12 }) {
      Text(this.session.scope === 'private' ? '添加隐私书签' : '添加书签')
        .width('100%')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)

      Column({ space: 6 }) {
        Text('保存到')
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)

        this.buildFolderChoices()
      }
      .width('100%')

      if (this.session.scope === 'regular') {
        Row({ space: 8 }) {
          Checkbox()
            .select(this.session.addToHome)
            .selectedColor(this.storedAccentColor)
            .width(20)
            .height(20)
            .onChange((selected: boolean) => {
              this.onAction({ type: 'set_add_to_home', selected: selected });
            })

          Text('同时添加到主页')
            .fontSize(13)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .onClick(() => {
              this.onAction({ type: 'set_add_to_home', selected: !this.session.addToHome });
            })
        }
        .width('100%')
      }

      Divider()
        .color(this.storedDividerColor)

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(36)
          .fontSize(14)
          .fontColor(this.storedPrimaryTextColor)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(8)
          .onClick(() => {
            this.closePopup(true);
          })

        Button('添加')
          .layoutWeight(1)
          .height(36)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.storedAccentColor)
          .borderRadius(8)
          .enabled(this.selectedFolderId.length > 0)
          .opacity(this.selectedFolderId.length > 0 ? 1 : 0.38)
          .onClick(() => {
            if (this.selectedFolderId.length <= 0) {
              return;
            }
            const folderId = this.selectedFolderId;
            this.popupVisible = false;
            this.onAction({ type: 'confirm_add', folderId: folderId });
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 14 })
    .backgroundColor(this.storedFloatingSurfaceColor)
  }

  @Builder
  private buildFolderChoices() {
    if (this.session.preparing && this.session.options.length <= 0) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.storedAccentColor)

        Text('正在准备文件夹')
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')
      .height(54)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.storedControlBackgroundColor)
      .borderRadius(8)
    } else if (this.session.options.length <= 0) {
      Text('没有可保存书签的文件夹')
        .width('100%')
        .height(54)
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.storedControlBackgroundColor)
        .borderRadius(8)
    } else {
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.session.options, (option: BookmarkFolderOptionView) => {
            this.buildFolderRow(option)
          }, (option: BookmarkFolderOptionView) => option.id)
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: this.resolveFolderListMaxHeight() })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
    }
  }

  @Builder
  private buildFolderRow(option: BookmarkFolderOptionView) {
    Row({ space: 8 }) {
      AiraIcon({
        airaIconId: 'bookmarks.folder',
        iconSize: 17,
        iconColor: this.selectedFolderId === option.id ? this.storedAccentColor : this.storedSecondaryTextColor
      })

      Text(option.title)
        .layoutWeight(1)
        .fontSize(13)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(option.bookmarkCountText)
        .fontSize(11)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
    }
    .width('100%')
    .height(LARGE_SCREEN_BOOKMARK_FOLDER_ROW_HEIGHT_VP)
    .padding({ left: 10 + Math.min(4, option.depth) * 14, right: 10 })
    .backgroundColor(this.selectedFolderId === option.id ?
      this.storedPressedBackgroundColor : $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(6)
    .hoverEffect(HoverEffect.Auto)
    .onClick(() => {
      this.selectedFolderId = option.id;
    })
  }

  private syncSelectedFolder(): void {
    this.selectedFolderId = this.resolveSelectedFolderId();
  }

  private resolveSelectedFolderId(): string {
    if (this.session.options.some((option: BookmarkFolderOptionView) => option.id === this.selectedFolderId)) {
      return this.selectedFolderId;
    }
    return this.session.options.length > 0 ? this.session.options[0].id : '';
  }

  private closePopup(notifyDismiss: boolean): void {
    this.popupVisible = false;
    if (notifyDismiss) {
      this.onAction({ type: 'dismiss' });
    }
  }

  private showDisabledMessage(): void {
    const message = this.disabledMessage.trim();
    if (message.length <= 0) {
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
  }

  private resolvePopupWidth(): number {
    return this.modalLayoutService.resolvePopupWidth(
      this.viewportWidthVp,
      LARGE_SCREEN_BOOKMARK_POPUP_WIDTH_VP
    );
  }

  private resolveFolderListMaxHeight(): number {
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      LARGE_SCREEN_BOOKMARK_FOLDER_LIST_MAX_HEIGHT_VP,
      this.popupReservedTopVp + LARGE_SCREEN_BOOKMARK_POPUP_FIXED_HEIGHT_VP
    );
  }
}

import { createBookmarkAddDraft } from '../../../core/bookmarks/BookmarkAddDraft';
import { BookmarkAddForm } from '../bookmarks/BookmarkAddForm';
import {
  BrowserBookmarkActionSessionSnapshot,
  BrowserBookmarkFolderSelectionAction
} from '../../../core/browser/BrowserBookmarkActionCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import { resourceStrPresent } from '../../../core/browser/BrowserBottomPanelText';
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';

const LARGE_SCREEN_BOOKMARK_BUTTON_SIZE_VP: number = 28;
const LARGE_SCREEN_BOOKMARK_ICON_SIZE_VP: number = 17;
const LARGE_SCREEN_BOOKMARK_POPUP_WIDTH_VP: number = 360;
const LARGE_SCREEN_BOOKMARK_POPUP_RADIUS_VP: number = 16;
const LARGE_SCREEN_BOOKMARK_FORM_HEIGHT_VP: number = 480;
const LARGE_SCREEN_BOOKMARK_TARGET_SPACE_VP: number = 6;

const EMPTY_BOOKMARK_SESSION: BrowserBookmarkActionSessionSnapshot = {
  actionVersion: 0,
  sessionVersion: 0,
  active: false,
  draft: createBookmarkAddDraft(),
  scope: 'regular',
  addToHome: false,
  preparing: false,
  options: []
};

@Component
export struct BrowserLargeScreenBookmarkPopover {
  @Prop actionEnabled: boolean = false;
  @Prop actionSelected: boolean = false;
  @Prop disabledMessage: ResourceStr = '';
  @Prop @Watch('syncSession') session: BrowserBookmarkActionSessionSnapshot = EMPTY_BOOKMARK_SESSION;
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onOpen: () => void = () => {};
  onAction: (action: BrowserBookmarkFolderSelectionAction) => void =
    (_action: BrowserBookmarkFolderSelectionAction): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';

  @State private popupVisible: boolean = false;
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
    .accessibilityText(this.actionSelected ? $r('app.string.history_remove_bookmark') : $r('app.string.history_add_bookmark'))
    .onClick(() => {
      if (!this.actionEnabled) {
        this.showDisabledMessage();
        return;
      }
      if (!this.actionSelected) {
        this.popupVisible = true;
      }
      this.onOpen();
    })
    .bindPopup(this.popupVisible, {
      builder: this.buildBookmarkPopup,
      placement: Placement.BottomRight,
      popupColor: this.storedFloatingSurfaceColor,
      enableArrow: false,
      autoCancel: !this.session.draft.saving,
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
        if (wasVisible && !event.isVisible && this.session.active) {
          this.onAction({ type: 'dismiss' });
        }
      }
    })
  }

  @Builder
  private buildBookmarkPopup() {
    Column() {
      BookmarkAddForm({
        draft: this.session.draft,
        options: this.session.options,
        isPreparing: this.session.preparing,
        sessionVersion: this.session.sessionVersion,
        layoutMode: 'large_screen',
        title: this.session.scope === 'private' ? $r('app.string.bookmark_popover_add_private') : $r('app.string.history_add_bookmark'),
        showAddToHome: this.session.scope === 'regular',
        addToHome: this.session.addToHome,
        onAction: (action: BrowserBookmarkFolderSelectionAction) => { this.onAction(action); }
      })
    }
    .width('100%')
    .height(this.resolveFormHeight())
    .backgroundColor(this.storedFloatingSurfaceColor)
    .borderRadius(LARGE_SCREEN_BOOKMARK_POPUP_RADIUS_VP)
    .clip(true)
  }

  private syncSession(): void {
    if (!this.session.active) {
      this.popupVisible = false;
    }
  }

  private showDisabledMessage(): void {
    if (!resourceStrPresent(this.disabledMessage)) {
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: this.disabledMessage, duration: 1500 });
  }

  private resolvePopupWidth(): number {
    return this.modalLayoutService.resolvePopupWidth(
      this.viewportWidthVp,
      LARGE_SCREEN_BOOKMARK_POPUP_WIDTH_VP
    );
  }

  private resolveFormHeight(): number {
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      LARGE_SCREEN_BOOKMARK_FORM_HEIGHT_VP,
      this.popupReservedTopVp
    );
  }
}

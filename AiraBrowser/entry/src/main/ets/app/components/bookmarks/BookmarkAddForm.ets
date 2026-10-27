import { BookmarkAddDraft, createBookmarkAddDraft } from '../../../core/bookmarks/BookmarkAddDraft';
import { BrowserBookmarkFolderSelectionAction } from '../../../core/browser/BrowserBookmarkActionCoordinator';
import { BookmarkFolderOptionView } from '../../../core/browser/BookmarkFolderSelectionViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS } from '../browser/BrowserModalBottomSheet';
import { ManagementHdsScaffold } from '../common/ManagementHdsScaffold';
import { BookmarkMoveFolderSelectionResult, BookmarkMoveFolderSelectionSheet } from './BookmarkMoveFolderSelectionSheet';

@Component
export struct BookmarkAddForm {
  @Prop draft: BookmarkAddDraft = createBookmarkAddDraft();
  @Prop options: BookmarkFolderOptionView[] = [];
  @Prop isPreparing: boolean = false;
  @Prop showAddToHome: boolean = true;
  @Prop addToHome: boolean = false;
  @Prop sessionVersion: number = 0;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Prop title: ResourceStr = $r('app.string.history_add_bookmark');
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private accentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private controlColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private pageColor: string = '#F6F8FB';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private dividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private primaryColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private secondaryColor: string = '#5F6875';
  private scroller: Scroller = new Scroller();
  onAction: (action: BrowserBookmarkFolderSelectionAction) => void = (_action: BrowserBookmarkFolderSelectionAction) => {};

  build() {
    Column() {
      if (this.draft.choosingFolder) {
        BookmarkMoveFolderSelectionSheet({
          options: this.options,
          isPreparing: this.isPreparing,
          layoutMode: this.layoutMode,
          rootTitle: $r('app.string.bookmark_popover_save_to'),
          rootBackIconKind: 'back',
          rootEmptyTitle: $r('app.string.bookmark_no_save_folder'),
          confirmLabel: $r('app.string.bookmark_add_select_folder'),
          onDismiss: () => { this.setChoosingFolder(false); },
          onFolderOpened: (folderId: string) => {
            this.onAction({ type: 'preview_folder', folderId: folderId });
          },
          onConfirm: (result: BookmarkMoveFolderSelectionResult) => {
            this.onAction({ type: 'select_folder', folderId: result.targetFolderId });
            this.setChoosingFolder(false);
          }
        })
      } else {
        ManagementHdsScaffold({
          title: this.title,
          pageBackground: this.pageColor,
          primaryTextColor: this.primaryColor,
          dividerColor: this.dividerColor,
          useTopSafeInset: false,
          scrollers: [this.scroller],
          onBack: () => { this.onAction({ type: 'dismiss' }); }
        }) {
          Column() {
            Scroll(this.scroller) {
              Column({ space: 18 }) {
                this.buildTitleField()
                this.buildUrlField()
                this.buildFolderRow()
                if (this.showAddToHome) {
                  Row({ space: 12 }) {
                    Text($r('app.string.bookmark_also_home'))
                      .layoutWeight(1)
                      .fontSize(15)
                      .fontColor(this.primaryColor)
                    Toggle({ type: ToggleType.Switch, isOn: this.addToHome })
                      .selectedColor(this.accentColor)
                      .enabled(!this.draft.saving)
                      .onChange((value: boolean) => {
                        this.onAction({ type: 'set_add_to_home', selected: value });
                      })
                  }
                  .width('100%')
                  .constraintSize({ minHeight: 44 })
                }
                this.buildError(this.draft.saveError)
              }
              .width('100%')
              .constraintSize({ minHeight: '100%' })
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 16, right: 16, top: 12, bottom: 16 })
            }
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.TopStart)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

            Row({ space: 12 }) {
              Button($r('app.string.settings_account_cancel'))
                .defaultFocus(true)
                .layoutWeight(1)
                .height(44)
                .fontColor(this.primaryColor)
                .backgroundColor(this.controlColor)
                .enabled(!this.draft.saving)
                .onClick(() => { this.onAction({ type: 'dismiss' }); })
              Button(this.draft.saving ? $r('app.string.bookmark_add_saving') : $r('app.string.ui_save'))
                .layoutWeight(1)
                .height(44)
                .fontColor('#FFFFFF')
                .backgroundColor(this.accentColor)
                .enabled(!this.draft.saving && this.draft.folderId.length > 0)
                .onClick(() => { this.onAction({ type: 'confirm_add' }); })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Start)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor)
    .borderRadius(this.layoutMode === 'large_screen' ? 0 : {
      topLeft: BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
      topRight: BROWSER_MODAL_BOTTOM_SHEET_CORNER_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    })
    .clip(true)
  }

  @Builder
  private buildTitleField() {
    Column({ space: 6 }) {
      this.buildLabel($r('app.string.ui_name'))
      TextInput({ text: this.draft.title, placeholder: $r('app.string.ui_name') })
        .width('100%')
        .height(46)
        .fontSize(15)
        .fontColor(this.primaryColor)
        .placeholderColor(this.secondaryColor)
        .backgroundColor(this.controlColor)
        .borderRadius(12)
        .defaultFocus(false)
        .enabled(!this.draft.saving)
        .onChange((value: string) => { this.onAction({ type: 'edit_title', value: value }); })
      this.buildError(this.draft.titleError)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildUrlField() {
    Column({ space: 6 }) {
      this.buildLabel($r('app.string.ui_url'))
      TextInput({ text: this.draft.url, placeholder: $r('app.string.ui_url') })
        .width('100%')
        .height(46)
        .type(InputType.URL)
        .fontSize(15)
        .fontColor(this.primaryColor)
        .placeholderColor(this.secondaryColor)
        .backgroundColor(this.controlColor)
        .borderRadius(12)
        .defaultFocus(false)
        .enabled(!this.draft.saving)
        .onChange((value: string) => { this.onAction({ type: 'edit_url', value: value }); })
      this.buildError(this.draft.urlError)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFolderRow() {
    Row({ space: 12 }) {
      Text($r('app.string.bookmark_popover_save_to'))
        .fontSize(15)
        .fontColor(this.primaryColor)
      Text(this.resolveFolderTitle())
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(this.secondaryColor)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.secondaryColor])
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .enabled(!this.draft.saving)
    .onClick(() => { this.setChoosingFolder(true); })
  }

  @Builder
  private buildLabel(label: ResourceStr) {
    Text(label)
      .fontSize(13)
      .fontColor(this.secondaryColor)
  }

  @Builder
  private buildError(message: ResourceStr) {
    if (message !== '') {
      Text(message)
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_warning'))
        .width('100%')
    }
  }

  private resolveFolderTitle(): ResourceStr {
    const folder = this.options.find((option: BookmarkFolderOptionView) => option.id === this.draft.folderId);
    return folder !== undefined ? folder.title : this.isPreparing ?
      $r('app.string.bookmark_preparing_folders') : $r('app.string.bookmark_no_save_folder');
  }

  private setChoosingFolder(visible: boolean): void {
    this.onAction({ type: 'set_folder_picker', selected: visible });
  }
}

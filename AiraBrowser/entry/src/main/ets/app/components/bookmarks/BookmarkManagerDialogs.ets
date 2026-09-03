import { image } from '@kit.ImageKit';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  SiteIconListPresenter,
  SiteIconListRenderState,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { BookmarkFolderIcon } from './BookmarkFolderIcon';
import { SiteIconView } from '../common/SiteIconView';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';

const BOOKMARK_EDIT_ICON_TARGET_ID: string = 'bookmark-edit-node-dialog';

@CustomDialog
export struct BookmarkManagerCreateFolderDialog {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link folderTitle: string;
  confirm: (title: string) => void = (_title: string) => {};

  build() {
    Column({ space: 16 }) {
      Text('新建文件夹')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.folderTitle, placeholder: '文件夹名称' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.folderTitle = value;
        })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '确定',
          emphasis: 'primary',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm(this.folderTitle);
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}

@CustomDialog
export struct BookmarkManagerEditNodeDialog {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link nodeTitle: string;
  @Link nodeUrl: string;
  @Link nodeType: string;
  @Link iconPath: string;
  confirm: () => void = () => {};
  @State private iconStates: SiteIconListRenderState[] = [];
  private iconTargetUrl: string = '';
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();

  aboutToAppear(): void {
    this.iconStates = [];
    this.iconTargetUrl = this.nodeUrl.trim();
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedIcon(result)
    );
    this.resolveIcon();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    Column({ space: 16 }) {
      this.buildIcon()

      Text(this.nodeType === 'folder' ? '编辑文件夹' : '编辑书签')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.nodeTitle, placeholder: '名称' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.nodeTitle = value;
        })

      if (this.nodeType === 'bookmark') {
        TextInput({ text: this.nodeUrl, placeholder: '网址' })
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(this.storedPrimaryTextColor)
          .placeholderColor(this.storedSecondaryTextColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .border({ width: { bottom: 1 }, color: this.storedDividerColor })
          .borderRadius(0)
          .padding({ left: 0, right: 0 })
          .onChange((value: string) => {
            this.nodeUrl = value;
          })
      }

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '保存',
          emphasis: 'primary',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildIcon() {
    Row() {
      if (this.nodeType === 'folder') {
        BookmarkFolderIcon({
          widthVp: 42,
          hasContent: false,
          animatePaper: false
        })
      } else if (this.resolveIconUri().length > 0 || this.resolveIconPixelMap() !== undefined) {
        this.buildBookmarkIcon()
      } else {
        SymbolGlyph($r('sys.symbol.bookmark_fill'))
          .fontSize(32)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width(56)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(18)
  }

  @Builder
  private buildBookmarkIcon() {
    SiteIconView({
      iconUri: this.resolveIconUri(),
      iconPixelMap: this.resolveIconPixelMap(),
      fallbackLabel: resolveSiteIconFallbackLabel(this.nodeTitle, this.nodeUrl),
      iconSize: 34,
      cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      frameBorderWidth: 0,
      containerBackgroundColor: this.storedControlBackgroundColor,
      preferPixelMap: this.resolveIconPixelMap() !== undefined,
      sourceRevision: this.resolveIconSourceRevision(),
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.resolvePixelMapAfterUriFailure(iconUri, sourceRevision);
      }
    })
  }

  private resolveIcon(): void {
    this.siteIconListPresenter.resolveTargets(
      this.buildIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedIcon(result),
      { resolutionPolicy: 'memoryOnly' }
    );
  }

  private buildIconTargets(): SiteIconListTarget[] {
    if (this.iconTargetUrl.length <= 0) {
      return [];
    }
    return [{
      id: BOOKMARK_EDIT_ICON_TARGET_ID,
      url: this.iconTargetUrl,
      initialIconUri: this.iconPath
    }];
  }

  private applyResolvedIcon(result: SiteIconListResolvedIcon): void {
    const next = this.siteIconListPresenter.applyResolvedIcon(this.iconStates, result);
    if (next !== this.iconStates) {
      this.iconStates = next;
    }
  }

  private resolveIconUri(): string {
    return this.getIconState()?.path ?? this.iconPath.trim();
  }

  private resolveIconPixelMap(): image.PixelMap | undefined {
    return this.getIconState()?.pixelMap;
  }

  private resolveIconSourceRevision(): number {
    return this.getIconState()?.sourceRevision ?? 0;
  }

  private getIconState(): SiteIconListRenderState | undefined {
    return this.iconStates.find((state: SiteIconListRenderState) => state.id === BOOKMARK_EDIT_ICON_TARGET_ID);
  }

  private resolvePixelMapAfterUriFailure(currentUri: string, sourceRevision: number): void {
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      {
        id: BOOKMARK_EDIT_ICON_TARGET_ID,
        url: this.iconTargetUrl
      },
      currentUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedIcon(result)
    );
  }
}

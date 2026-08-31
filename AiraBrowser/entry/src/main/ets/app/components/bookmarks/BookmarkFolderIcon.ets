import { curves, PathShape } from '@kit.ArkUI';
import {
  BookmarkFolderIconMaskState,
  BookmarkFolderIconPaletteState,
  BookmarkFolderIconViewModel
} from '../../../core/bookmarks/BookmarkFolderIconViewModel';
import { BROWSER_THEME_STORAGE_ACCENT_KEY } from '../../../core/theme/BrowserThemeStorageKeys';

const BOOKMARK_FOLDER_ICON_DEFAULT_WIDTH: number = 30;
const BOOKMARK_FOLDER_ICON_ANIMATION_DELAY_MS: number = 170;
const BOOKMARK_FOLDER_ICON_ANIMATION_MS: number = 720;
const BOOKMARK_FOLDER_ICON_REVEAL_CURVE: ICurve = curves.springMotion(0.58, 0.76);
const BOOKMARK_FOLDER_PAPER_HIDDEN_OFFSET_RATIO: number = 0.23;
const BOOKMARK_FOLDER_PAPER_VISIBLE_OFFSET_RATIO: number = -0.055;
const BOOKMARK_FOLDER_COUNT_CAPSULE_COLOR: string = '#33000000';
const BOOKMARK_FOLDER_COUNT_TEXT_COLOR: string = '#E6FFFFFF';
const BOOKMARK_FOLDER_COUNT_CAPSULE_WIDTH_RATIO: number = 0.58;

@Component
export struct BookmarkFolderIcon {
  @Prop widthVp: number = BOOKMARK_FOLDER_ICON_DEFAULT_WIDTH;
  @Prop @Watch('preparePaperState') hasContent: boolean = false;
  @Prop @Watch('preparePaperState') animatePaper: boolean = true;
  @Prop @Watch('preparePaperState') playbackKey: number = 0;
  @Prop count: number = -1;
  @Prop backColor: ResourceColor = '';
  @Prop frontColor: ResourceColor = '';
  @Prop paperColor: ResourceColor = '';
  @Prop countTextColor: ResourceColor = '';
  @Prop countCapsuleColor: ResourceColor = '';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @State private paperOffsetRatio: number = BOOKMARK_FOLDER_PAPER_HIDDEN_OFFSET_RATIO;
  @State private paperOpacity: number = 0;
  private viewModel: BookmarkFolderIconViewModel = new BookmarkFolderIconViewModel();
  private revealTimer: number = -1;

  aboutToAppear(): void {
    this.preparePaperState();
  }

  aboutToDisappear(): void {
    this.clearRevealTimer();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildMaskLayer(this.resolveMaskState().backCommands, this.resolveBackColor())

      if (this.hasContent) {
        this.buildPaperLayer()
      }

      this.buildMaskLayer(this.resolveMaskState().frontCommands, this.resolveFrontColor())

      if (this.hasCountLabel()) {
        this.buildCountLabel()
      }
    }
    .width(this.widthVp)
    .height(this.resolveHeightVp())
    .clip(false)
    .hitTestBehavior(HitTestMode.None)
    .onAppear(() => {
      this.preparePaperState();
    })
  }

  @Builder
  private buildMaskLayer(commands: string, color: ResourceColor) {
    Stack() {
      Row()
        .width(this.widthVp)
        .height(this.resolveHeightVp())
        .backgroundColor(color)
    }
    .width(this.widthVp)
    .height(this.resolveHeightVp())
    .clipShape(new PathShape({
      commands: commands
    }))
  }

  @Builder
  private buildPaperLayer() {
    Stack() {
      Row()
        .width(this.widthVp)
        .height(this.resolveHeightVp())
        .backgroundColor(this.resolvePaperColor())
    }
    .width(this.widthVp)
    .height(this.resolveHeightVp())
    .clipShape(new PathShape({
      commands: this.resolveMaskState().paperCommands
    }))
    .translate({ y: this.resolvePaperOffset() })
    .opacity(this.paperOpacity)
    .animation({
      duration: BOOKMARK_FOLDER_ICON_ANIMATION_MS,
      curve: BOOKMARK_FOLDER_ICON_REVEAL_CURVE
    })
  }

  @Builder
  private buildCountLabel() {
    Row() {
      Text(this.resolveCountLabel())
        .fontSize(this.resolveCountLabelFontSize())
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolveCountTextColor())
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width(this.resolveCountCapsuleWidth())
    .height(this.resolveCountCapsuleHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.resolveCountCapsuleColor())
    .borderRadius(this.resolveCountCapsuleHeight() / 2)
    .clip(true)
    .translate({
      x: this.resolveCountLabelX(),
      y: this.resolveCountLabelY()
    })
  }

  private preparePaperState(): void {
    this.clearRevealTimer();
    if (!this.hasContent) {
      this.paperOpacity = 0;
      this.paperOffsetRatio = BOOKMARK_FOLDER_PAPER_HIDDEN_OFFSET_RATIO;
      return;
    }
    if (!this.animatePaper) {
      this.paperOpacity = 1;
      this.paperOffsetRatio = BOOKMARK_FOLDER_PAPER_VISIBLE_OFFSET_RATIO;
      return;
    }
    this.paperOpacity = 0;
    this.paperOffsetRatio = BOOKMARK_FOLDER_PAPER_HIDDEN_OFFSET_RATIO;
    this.revealTimer = setTimeout(() => {
      this.paperOpacity = 1;
      this.paperOffsetRatio = BOOKMARK_FOLDER_PAPER_VISIBLE_OFFSET_RATIO;
    }, BOOKMARK_FOLDER_ICON_ANIMATION_DELAY_MS);
  }

  private clearRevealTimer(): void {
    if (this.revealTimer >= 0) {
      clearTimeout(this.revealTimer);
      this.revealTimer = -1;
    }
  }

  private resolvePaperOffset(): number {
    return this.resolveHeightVp() * this.paperOffsetRatio;
  }

  private resolveHeightVp(): number {
    return this.viewModel.resolveHeightVp(this.widthVp);
  }

  private resolveMaskState(): BookmarkFolderIconMaskState {
    return this.viewModel.buildMaskState(this.widthVp);
  }

  private resolvePaletteState(): BookmarkFolderIconPaletteState {
    return this.viewModel.buildPaletteState(this.storedAccentColor);
  }

  private resolveBackColor(): ResourceColor {
    return this.resolveOverrideColor(this.backColor, this.resolvePaletteState().backColor);
  }

  private resolveFrontColor(): ResourceColor {
    return this.resolveOverrideColor(this.frontColor, this.resolvePaletteState().frontColor);
  }

  private resolvePaperColor(): ResourceColor {
    return this.resolveOverrideColor(this.paperColor, this.resolvePaletteState().paperColor);
  }

  private hasCountLabel(): boolean {
    return this.resolveCountLabel().length > 0;
  }

  private resolveCountLabel(): string {
    return this.viewModel.buildCountLabel(this.count);
  }

  private resolveCountCapsuleWidth(): number {
    return this.widthVp * BOOKMARK_FOLDER_COUNT_CAPSULE_WIDTH_RATIO;
  }

  private resolveCountCapsuleHeight(): number {
    return this.resolveHeightVp() * 0.42;
  }

  private resolveCountLabelFontSize(): number {
    const label = this.resolveCountLabel();
    if (label.length >= 3) {
      return this.widthVp * 0.22;
    }
    if (label.length >= 2) {
      return this.widthVp * 0.25;
    }
    return this.widthVp * 0.29;
  }

  private resolveCountLabelX(): number {
    return (this.widthVp - this.resolveCountCapsuleWidth()) / 2;
  }

  private resolveCountLabelY(): number {
    return this.resolveHeightVp() * 0.45;
  }

  private resolveCountTextColor(): ResourceColor {
    return this.resolveOverrideColor(this.countTextColor, BOOKMARK_FOLDER_COUNT_TEXT_COLOR);
  }

  private resolveCountCapsuleColor(): ResourceColor {
    return this.resolveOverrideColor(this.countCapsuleColor, BOOKMARK_FOLDER_COUNT_CAPSULE_COLOR);
  }

  private resolveOverrideColor(color: ResourceColor, fallback: string): ResourceColor {
    if (`${color}`.length > 0) {
      return color;
    }
    return fallback;
  }
}

import {
  NovelReaderAction,
  NovelReaderSnapshot,
  resolveNovelModeLabel
} from '../../../features/novel/NovelReaderModels';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  resolveBrowserBottomFloatingMaterialShadowColor,
  resolveBrowserBottomNeutralPrimaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import {
  NovelReaderLayoutState,
  NovelReaderLayoutViewModel
} from '../../../core/novel/NovelReaderLayoutViewModel';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserBottomChromeMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';
import { NovelReaderOverlay } from './NovelReaderOverlay';

const NOVEL_REENTRY_BUTTON_SIZE: number = 52;
const NOVEL_REENTRY_ICON_SIZE: number = 24;
const NOVEL_REENTRY_EDGE_INSET: number = 8;
const NOVEL_REENTRY_DEFAULT_VERTICAL_RATIO: number = 0.38;
const NOVEL_REENTRY_PAN_START_DISTANCE: number = 4;
const NOVEL_REENTRY_SNAP_DURATION_MS: number = 180;
const NOVEL_REENTRY_BUTTON_Z_INDEX: number = 139;
const NOVEL_READER_OVERLAY_Z_INDEX: number = 141;

@Component
export struct NovelReaderSurfaceHost {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop state: NovelReaderSnapshot;
  @Prop webPageVisible: boolean = false;
  @Prop activeTabId: string = '';
  @Prop currentPageUrl: string = '';
  @Prop @Watch('handleViewportChanged') viewportWidth: number = 0;
  @Prop @Watch('handleViewportChanged') viewportHeight: number = 0;
  onAction: (action: NovelReaderAction) => void = (_action: NovelReaderAction): void => {};
  onReentryTap: () => void = (): void => {};
  onPageEntryTap: () => void = (): void => {};
  private layoutViewModel: NovelReaderLayoutViewModel = new NovelReaderLayoutViewModel();
  @State private layoutState: NovelReaderLayoutState = this.layoutViewModel.buildState({
    viewportWidth: this.viewportWidth,
    viewportHeight: this.viewportHeight
  });
  @State private buttonX: number = -1;
  @State private buttonY: number = -1;
  @State private dragging: boolean = false;
  private dragOriginX: number = 0;
  private dragOriginY: number = 0;

  aboutToAppear(): void {
    this.syncLayoutState();
  }

  build() {
    if (this.state.visible) {
      NovelReaderOverlay({
        state: this.state,
        readerTheme: this.state.preferences.theme,
        layoutState: this.layoutState,
        onAction: this.onAction
      })
        .zIndex(NOVEL_READER_OVERLAY_Z_INDEX)
    } else if (this.shouldShowReentryButton()) {
      Button({ type: ButtonType.Circle }) {
        BrowserFloatingGlassMaterialSurface({
          surfaceWidth: NOVEL_REENTRY_BUTTON_SIZE,
          surfaceHeight: NOVEL_REENTRY_BUTTON_SIZE,
          surfaceRadius: NOVEL_REENTRY_BUTTON_SIZE / 2,
          tintColor: resolveBrowserBottomChromeMaterialTintForMode(this.storedResolvedThemeMode)
        }) {
          AiraIcon({
            airaIconId: 'browser.toolbar.reader',
            iconSize: NOVEL_REENTRY_ICON_SIZE,
            iconColor: resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode)
          })
        }
      }
      .width(NOVEL_REENTRY_BUTTON_SIZE)
      .height(NOVEL_REENTRY_BUTTON_SIZE)
      .padding(0)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .accessibilityText(`重新进入${resolveNovelModeLabel(this.state.contentKind)}`)
      .position({ x: this.resolveButtonX(), y: this.resolveButtonY() })
      .zIndex(NOVEL_REENTRY_BUTTON_Z_INDEX)
      .shadow({
        radius: 6,
        color: resolveBrowserBottomFloatingMaterialShadowColor(this.storedResolvedThemeMode),
        offsetX: 0,
        offsetY: 0
      })
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.All, distance: NOVEL_REENTRY_PAN_START_DISTANCE })
            .onActionStart((): void => {
              this.beginButtonDrag();
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.updateButtonDrag(event);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.endButtonDrag(event);
            })
            .onActionCancel((): void => {
              this.cancelButtonDrag();
            }),
          TapGesture({ count: 1, fingers: 1 })
            .onAction((): void => {
              if (this.state.pageEntryAvailable) {
                this.onPageEntryTap();
              } else {
                this.onReentryTap();
              }
            })
        ),
        GestureMask.Normal
      )
    }
  }

  private shouldShowReentryButton(): boolean {
    if (this.state.pageEntryAvailable) {
      return this.webPageVisible && this.state.pageEntryTabId.length > 0 &&
        this.state.pageEntryTabId === this.activeTabId && this.state.pageEntryPageUrl.length > 0;
    }
    return this.state.reentryAvailable && this.webPageVisible && this.state.scope.tabId.length > 0 &&
      this.state.scope.tabId === this.activeTabId && this.state.reentryPageUrl.length > 0;
  }

  private resolveButtonX(): number {
    if (this.buttonX >= 0) {
      return this.clampButtonX(this.buttonX);
    }
    return this.resolveRightSnapX();
  }

  private resolveButtonY(): number {
    if (this.buttonY >= 0) {
      return this.clampButtonY(this.buttonY);
    }
    return this.clampButtonY(
      this.viewportHeight * NOVEL_REENTRY_DEFAULT_VERTICAL_RATIO - NOVEL_REENTRY_BUTTON_SIZE / 2
    );
  }

  private beginButtonDrag(): void {
    this.dragging = true;
    this.buttonX = this.resolveButtonX();
    this.buttonY = this.resolveButtonY();
    this.dragOriginX = this.buttonX;
    this.dragOriginY = this.buttonY;
  }

  private updateButtonDrag(event: GestureEvent): void {
    if (!this.dragging) {
      return;
    }
    const offsetX: number = Number(event.offsetX);
    const offsetY: number = Number(event.offsetY);
    if (!Number.isFinite(offsetX) || !Number.isFinite(offsetY)) {
      return;
    }
    this.buttonX = this.clampButtonX(this.dragOriginX + offsetX);
    this.buttonY = this.clampButtonY(this.dragOriginY + offsetY);
  }

  private endButtonDrag(event: GestureEvent): void {
    this.updateButtonDrag(event);
    this.dragging = false;
    this.snapButtonToNearestEdge();
  }

  private cancelButtonDrag(): void {
    this.dragging = false;
    this.snapButtonToNearestEdge();
  }

  private snapButtonToNearestEdge(): void {
    const currentX: number = this.resolveButtonX();
    const targetX: number = currentX + NOVEL_REENTRY_BUTTON_SIZE / 2 <= this.viewportWidth / 2
      ? this.resolveLeftSnapX()
      : this.resolveRightSnapX();
    animateTo({
      duration: NOVEL_REENTRY_SNAP_DURATION_MS,
      curve: Curve.EaseOut
    }, (): void => {
      this.buttonX = targetX;
      this.buttonY = this.clampButtonY(this.resolveButtonY());
    });
  }

  private handleViewportChanged(): void {
    this.syncLayoutState();
    if (this.buttonX < 0 || this.buttonY < 0) {
      return;
    }
    this.buttonY = this.clampButtonY(this.buttonY);
    if (!this.dragging) {
      this.buttonX = this.buttonX + NOVEL_REENTRY_BUTTON_SIZE / 2 <= this.viewportWidth / 2
        ? this.resolveLeftSnapX()
        : this.resolveRightSnapX();
    } else {
      this.buttonX = this.clampButtonX(this.buttonX);
    }
  }

  private syncLayoutState(): void {
    this.layoutState = this.layoutViewModel.buildState({
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight
    });
  }

  private clampButtonX(value: number): number {
    const maximumX: number = Math.max(0, this.viewportWidth - NOVEL_REENTRY_BUTTON_SIZE);
    const minimumX: number = Math.min(NOVEL_REENTRY_EDGE_INSET, maximumX);
    const insetMaximumX: number = Math.max(minimumX, maximumX - NOVEL_REENTRY_EDGE_INSET);
    return Math.max(minimumX, Math.min(insetMaximumX, value));
  }

  private clampButtonY(value: number): number {
    const maximumY: number = Math.max(0, this.viewportHeight - NOVEL_REENTRY_BUTTON_SIZE);
    const minimumY: number = Math.min(NOVEL_REENTRY_EDGE_INSET, maximumY);
    const insetMaximumY: number = Math.max(minimumY, maximumY - NOVEL_REENTRY_EDGE_INSET);
    return Math.max(minimumY, Math.min(insetMaximumY, value));
  }

  private resolveLeftSnapX(): number {
    return this.clampButtonX(NOVEL_REENTRY_EDGE_INSET);
  }

  private resolveRightSnapX(): number {
    return this.clampButtonX(this.viewportWidth - NOVEL_REENTRY_BUTTON_SIZE - NOVEL_REENTRY_EDGE_INSET);
  }
}

import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BrowserArkWebMediaButtonState,
  BrowserVideoActionToolbarAction,
  BrowserVideoActionToolbarPosition,
  BrowserVideoActionToolbarPositionModel,
  VIDEO_ACTION_BUTTON_GAP,
  VIDEO_ACTION_BUTTON_SIZE,
  VIDEO_ACTION_TOOLBAR_WIDTH
} from '../../../core/browser/media/BrowserVideoActionToolbarLayout';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';

@Component
struct BrowserVideoActionGlassButton {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private themeMode: string = 'light';
  @Prop icon: AiraRenderableIconId = 'videoAssistant.cast';
  @Prop label: Resource = $r('app.string.video_player_cast');
  @Prop busy: boolean = false;
  onPress: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (isHdsMaterialAvailable()) {
        HdsImmersiveMaterialSurface({
          plateWidth: VIDEO_ACTION_BUTTON_SIZE,
          plateHeight: VIDEO_ACTION_BUTTON_SIZE,
          plateRadius: VIDEO_ACTION_BUTTON_SIZE / 2
        })
      }
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: VIDEO_ACTION_BUTTON_SIZE,
        surfaceHeight: VIDEO_ACTION_BUTTON_SIZE,
        surfaceRadius: VIDEO_ACTION_BUTTON_SIZE / 2,
        tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.themeMode),
        hostMaterialActive: isHdsMaterialAvailable(),
        backgroundBlurEnabled: true
      }) {
        Button({ type: ButtonType.Circle }) {
          AiraIcon({
            airaIconId: this.icon,
            iconSize: 24,
            iconColor: this.themeMode === 'dark' ? Color.White : '#16181D'
          })
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .enabled(!this.busy)
        .stateEffect(true)
        .accessibilityText(this.label)
        .onClick(this.onPress)
      }
    }
    .width(VIDEO_ACTION_BUTTON_SIZE)
    .height(VIDEO_ACTION_BUTTON_SIZE)
    .opacity(this.busy ? 0.6 : 1)
  }
}

@Component
export struct BrowserArkWebMediaTakeoverFloatingButtonHost {
  @Prop state: BrowserArkWebMediaButtonState;
  @Prop layerIndex: number = 0;
  onAction: (identity: string, action: BrowserVideoActionToolbarAction) => void = (): void => {};
  private positionModel: BrowserVideoActionToolbarPositionModel = new BrowserVideoActionToolbarPositionModel();
  @State private dragRevision: number = 0;

  build() {
    if (this.state.visible) {
      Row({ space: VIDEO_ACTION_BUTTON_GAP }) {
        BrowserVideoActionGlassButton({
          icon: 'videoAssistant.cast', label: $r('app.string.video_player_cast'), busy: this.state.busy,
          onPress: (): void => this.onAction(this.state.identity, 'cast')
        })
        BrowserVideoActionGlassButton({
          icon: 'videoAssistant.popup', label: $r('app.string.video_player_pip'), busy: this.state.busy,
          onPress: (): void => this.onAction(this.state.identity, 'picture_in_picture')
        })
        BrowserVideoActionGlassButton({
          icon: 'browser.elementInspection.fullscreen', label: $r('app.string.video_player_fullscreen'),
          busy: this.state.busy,
          onPress: (): void => this.onAction(this.state.identity, 'fullscreen')
        })
      }
      .width(VIDEO_ACTION_TOOLBAR_WIDTH)
      .height(VIDEO_ACTION_BUTTON_SIZE)
      .position(this.resolvePosition(this.dragRevision))
      // Block excludes child buttons too: only the row's pan gesture would respond.
      // Keep the buttons in the hit chain while isolating this cluster from the Web layer.
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      .priorityGesture(
        PanGesture({ direction: PanDirection.All, distance: 6 })
          .onActionStart(() => {
            this.positionModel.begin(this.state);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.positionModel.move(this.state, event.offsetX, event.offsetY);
            this.dragRevision += 1;
          })
          .onActionEnd(() => {
            this.positionModel.end();
          })
          .onActionCancel(() => {
            this.positionModel.end();
          })
      )
      .zIndex(this.layerIndex)
    }
  }

  private resolvePosition(_revision: number): BrowserVideoActionToolbarPosition {
    return this.positionModel.resolve(this.state);
  }
}

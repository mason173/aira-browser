import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from './AiraIcon';
import { FloatingGlassMaterialSurface } from './FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from './FloatingGlassMaterialTokens';

const FLOATING_SELECTION_TOOLBAR_HEIGHT: number = 60;
const FLOATING_SELECTION_TOOLBAR_RADIUS: number = FLOATING_SELECTION_TOOLBAR_HEIGHT / 2;
const FLOATING_SELECTION_TOOLBAR_HORIZONTAL_PADDING: number = 10;
const FLOATING_SELECTION_TOOLBAR_MIN_WIDTH: number = 226;
const FLOATING_SELECTION_TOOLBAR_ACTION_MIN_WIDTH: number = 62;
const FLOATING_SELECTION_TOOLBAR_ACTION_MEDIUM_WIDTH: number = 78;
const FLOATING_SELECTION_TOOLBAR_ACTION_WIDE_WIDTH: number = 92;
const FLOATING_SELECTION_TOOLBAR_ACTION_GAP: number = 6;
const FLOATING_SELECTION_TOOLBAR_BUTTON_HEIGHT: number = 48;
const FLOATING_SELECTION_TOOLBAR_BUTTON_RADIUS: number = FLOATING_SELECTION_TOOLBAR_BUTTON_HEIGHT / 2;
const FLOATING_SELECTION_TOOLBAR_ICON_SIZE: number = 21;
const FLOATING_SELECTION_TOOLBAR_TEXT_SIZE: number = 11;

export interface FloatingSelectionToolbarAction {
  icon?: Resource;
  airaIconId?: AiraRenderableIconId;
  title: string;
  action: () => void;
}

@Component
export struct FloatingSelectionToolbar {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  actions: FloatingSelectionToolbarAction[] = [];

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: FLOATING_SELECTION_TOOLBAR_HEIGHT,
        surfaceRadius: FLOATING_SELECTION_TOOLBAR_RADIUS,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background'),
        backgroundBlurEnabled: true,
        materialBorderWidth: 0.5,
        materialBorderColor: this.storedDividerColor
      }) {
        Row({ space: FLOATING_SELECTION_TOOLBAR_ACTION_GAP }) {
          ForEach(this.actions, (item: FloatingSelectionToolbarAction) => {
            this.buildSelectionAction(item)
          }, (item: FloatingSelectionToolbarAction, index: number) => `${item.title}-${index}`)
        }
        .width('100%')
        .height('100%')
        .padding({
          left: FLOATING_SELECTION_TOOLBAR_HORIZONTAL_PADDING,
          right: FLOATING_SELECTION_TOOLBAR_HORIZONTAL_PADDING
        })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width(this.resolveToolbarWidth())
    .height(FLOATING_SELECTION_TOOLBAR_HEIGHT)
    .borderRadius(FLOATING_SELECTION_TOOLBAR_RADIUS)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  @Builder
  private buildSelectionAction(item: FloatingSelectionToolbarAction) {
    Button() {
      Column({ space: 3 }) {
        if (item.airaIconId !== undefined) {
          AiraIcon({
            airaIconId: item.airaIconId,
            iconSize: FLOATING_SELECTION_TOOLBAR_ICON_SIZE,
            iconColor: this.storedPrimaryTextColor
          })
        } else if (item.icon !== undefined) {
          Image(item.icon)
            .width(FLOATING_SELECTION_TOOLBAR_ICON_SIZE)
            .height(FLOATING_SELECTION_TOOLBAR_ICON_SIZE)
            .objectFit(ImageFit.Contain)
        }
        Text(item.title)
          .fontSize(FLOATING_SELECTION_TOOLBAR_TEXT_SIZE)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.resolveActionWidth(item.title))
    .height(FLOATING_SELECTION_TOOLBAR_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .padding(0)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(FLOATING_SELECTION_TOOLBAR_BUTTON_RADIUS)
    .stateEffect(true)
    .onClick(item.action)
  }

  private resolveToolbarWidth(): number {
    const actionCount = this.actions.length;
    if (actionCount === 0) {
      return FLOATING_SELECTION_TOOLBAR_MIN_WIDTH;
    }
    let width = FLOATING_SELECTION_TOOLBAR_HORIZONTAL_PADDING * 2;
    this.actions.forEach((item: FloatingSelectionToolbarAction) => {
      width += this.resolveActionWidth(item.title);
    });
    width += Math.max(actionCount - 1, 0) * FLOATING_SELECTION_TOOLBAR_ACTION_GAP;
    return Math.max(FLOATING_SELECTION_TOOLBAR_MIN_WIDTH, width);
  }

  private resolveActionWidth(title: string): number {
    if (title.length >= 6) {
      return FLOATING_SELECTION_TOOLBAR_ACTION_WIDE_WIDTH;
    }
    if (title.length >= 4) {
      return FLOATING_SELECTION_TOOLBAR_ACTION_MEDIUM_WIDTH;
    }
    return FLOATING_SELECTION_TOOLBAR_ACTION_MIN_WIDTH;
  }
}

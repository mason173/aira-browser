import { ReaderModeTheme } from '../../../common/models/BrowserModels';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  ReadingSurfaceAppearance
} from '../../../features/reading/ReadingSurfaceModels';
import { AiraIcon } from '../common/AiraIcon';
import {
  resolveEffectiveReadingTheme,
  resolveReadingThemeTokens
} from './ReadingThemeTokenResolver';

const READING_CHROME_HORIZONTAL_PADDING: number = 22;
const READING_CHROME_TOP_ACTION_HEIGHT: number = 32;
const READING_CHROME_TOP_BOTTOM_PADDING: number = 10;
const READING_CHROME_CONTEXT_ROW_HEIGHT: number = 46;
const READING_CHROME_NAV_HEIGHT: number = 60;
const READING_CHROME_NAV_BOTTOM_PADDING: number = 8;

export type ReadingExperiencePanelKind = 'appearance' | 'text' | 'settings';

export function resolveReadingExperienceTopChromeHeight(topSafeInset: number): number {
  return Math.max(0, Math.ceil(topSafeInset)) + READING_CHROME_TOP_ACTION_HEIGHT +
    READING_CHROME_TOP_BOTTOM_PADDING;
}

export function resolveReadingExperienceBottomChromeHeight(
  bottomSafeInset: number,
  contextRowVisible: boolean
): number {
  return Math.max(0, Math.ceil(bottomSafeInset)) + READING_CHROME_NAV_HEIGHT +
    (contextRowVisible ? READING_CHROME_CONTEXT_ROW_HEIGHT : 0);
}

/**
 * The single source-independent Chrome owner for Article and Novel reading.
 * It emits typed control-panel requests; the root system Sheet owns their shared presentation.
 */
@Component
export struct ReadingExperienceChrome {
  @Prop title: string = '';
  @Prop closeAccessibilityLabel: string = '退出阅读';
  @Prop visible: boolean = true;
  @Prop appearance: ReadingSurfaceAppearance;
  @Prop topSafeInset: number = 0;
  @Prop bottomSafeInset: number = 0;
  @Prop contextRowVisible: boolean = false;
  @Prop primaryActionIcon: AiraRenderableIconId = 'novelReader.catalog';
  @Prop primaryActionLabel: string = '';
  @Prop textActionVisible: boolean = true;
  @Prop trailingActionVisible: boolean = false;
  @Prop trailingActionIcon: AiraRenderableIconId = 'browser.shortcut.home';
  @Prop trailingActionLabel: string = '';
  @Prop topActionsWidth: number = READING_CHROME_TOP_ACTION_HEIGHT;
  @Prop controlContentWidth: number = 0;
  onClose: () => void = (): void => {};
  onPrimaryAction: () => void = (): void => {};
  onTrailingAction: () => void = (): void => {};
  onPanelRequest: (panel: ReadingExperiencePanelKind) => void =
    (_panel: ReadingExperiencePanelKind): void => {};
  @BuilderParam topActions: () => void = this.emptyBuilder;
  @BuilderParam contextRow: () => void = this.emptyBuilder;

  @Builder
  private emptyBuilder() {
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.visible) {
        this.buildTopBar()
        this.buildBottomBlock()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTopBar() {
    Column() {
      Blank()
        .width('100%')
        .height(Math.max(0, Math.ceil(this.topSafeInset)))

      Stack({ alignContent: Alignment.Center }) {
        Text(this.title)
          .width('100%')
          .padding({
            left: Math.max(READING_CHROME_TOP_ACTION_HEIGHT, this.topActionsWidth) + 8,
            right: Math.max(READING_CHROME_TOP_ACTION_HEIGHT, this.topActionsWidth) + 8
          })
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)

        Row() {
          Button() {
            AiraIcon({
              airaIconId: 'browser.toolbar.back',
              iconSize: 16,
              iconColor: this.resolveTextColor()
            })
          }
          .width(READING_CHROME_TOP_ACTION_HEIGHT)
          .height(READING_CHROME_TOP_ACTION_HEIGHT)
          .padding(0)
          .type(ButtonType.Normal)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .borderRadius(READING_CHROME_TOP_ACTION_HEIGHT / 2)
          .accessibilityText(this.closeAccessibilityLabel)
          .onClick((): void => {
            this.onClose();
          })

          Blank()

          Row() {
            this.topActions()
          }
          .width(this.topActionsWidth)
          .height(READING_CHROME_TOP_ACTION_HEIGHT)
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(READING_CHROME_TOP_ACTION_HEIGHT)
        .alignItems(VerticalAlign.Center)
      }
      .width(this.resolveControlContentWidth())
      .height(READING_CHROME_TOP_ACTION_HEIGHT)
      .padding({ left: READING_CHROME_HORIZONTAL_PADDING, right: READING_CHROME_HORIZONTAL_PADDING })

      Blank()
        .width('100%')
        .height(READING_CHROME_TOP_BOTTOM_PADDING)
    }
    .width('100%')
    .height(resolveReadingExperienceTopChromeHeight(this.topSafeInset))
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.resolveControlBackgroundColor())
    .position({ x: 0, y: 0 })
  }

  @Builder
  private buildBottomBlock() {
    Column() {
      Column() {
        if (this.contextRowVisible) {
          this.contextRow()
        }

        Row() {
          this.buildNavItem(this.primaryActionIcon, this.primaryActionLabel, 'primary')
          if (this.textActionVisible) {
            this.buildNavItem('novelReader.text', '文字', 'text')
          }
          this.buildNavItem('novelReader.theme', '亮度与主题', 'appearance')
          this.buildNavItem('novelReader.settings', '设置', 'settings')
          if (this.trailingActionVisible) {
            this.buildNavItem(this.trailingActionIcon, this.trailingActionLabel, 'trailing')
          }
        }
        .width('100%')
        .height(READING_CHROME_NAV_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ bottom: READING_CHROME_NAV_BOTTOM_PADDING })
      }
      .width(this.resolveControlContentWidth())
    }
    .width('100%')
    .padding({ bottom: Math.max(0, Math.ceil(this.bottomSafeInset)) })
    .backgroundColor(this.resolveControlBackgroundColor())
    .alignItems(HorizontalAlign.Center)
    .align(Alignment.Bottom)
  }

  @Builder
  private buildNavItem(iconId: AiraRenderableIconId, label: string, id: string) {
    Column() {
      AiraIcon({
        airaIconId: iconId,
        iconSize: 24,
        iconColor: this.resolveTextColor()
      })
    }
    .layoutWeight(1)
    .height(52)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick((): void => {
      this.handleNavAction(id);
    })
  }

  private handleNavAction(id: string): void {
    if (id === 'primary') {
      this.onPrimaryAction();
      return;
    }
    if (id === 'trailing') {
      this.onTrailingAction();
      return;
    }
    if (id === 'appearance' || id === 'text' || id === 'settings') {
      this.onPanelRequest(id);
    }
  }

  private resolveEffectiveTheme(): ReaderModeTheme {
    return resolveEffectiveReadingTheme(this.appearance.theme);
  }

  private resolveControlContentWidth(): Length {
    return this.controlContentWidth > 0 ? this.controlContentWidth : '100%';
  }

  private resolveControlBackgroundColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).controlBackgroundColor;
  }

  private resolveTextColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).primaryTextColor;
  }
}

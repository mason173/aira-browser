import {
  BrowserPageFindBarAction,
  BrowserPageFindBarState,
  createBrowserPageFindClosedBarState
} from '../../../core/browser/BrowserPageFindCoordinator';
import { AiraIcon } from '../common/AiraIcon';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import { TopFloatingSurface } from '../common/TopFloatingSurface';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';

const PAGE_FIND_BAR_HEIGHT: number = 56;
const PAGE_FIND_EMBEDDED_BAR_HEIGHT: number = 44;
const PAGE_FIND_BAR_HORIZONTAL_MARGIN: number = 12;
const PAGE_FIND_LARGE_SCREEN_MAX_WIDTH: number = 440;
const PAGE_FIND_BAR_RADIUS: number = 20;
const PAGE_FIND_ICON_BUTTON_SIZE: number = 40;
const PAGE_FIND_ICON_SIZE: number = 22;
const PAGE_FIND_EMBEDDED_HORIZONTAL_PADDING: number = 10;
const PAGE_FIND_INPUT_FOCUS_ID: string = 'aira-page-find-input';
const PAGE_FIND_PREVIOUS_BUTTON_FOCUS_ID: string = 'aira-page-find-previous';
const PAGE_FIND_NEXT_BUTTON_FOCUS_ID: string = 'aira-page-find-next';
const PAGE_FIND_CLOSE_BUTTON_FOCUS_ID: string = 'aira-page-find-close';
const PAGE_FIND_INPUT_FOCUS_DELAY_MS: number = 48;
const PAGE_FIND_ICON_ACTION_THROTTLE_MS: number = 180;

type BrowserPageFindBarButtonRole = 'previous' | 'next' | 'close';

@Component
export struct BrowserPageFindBar {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private inputFocusTimer: number = -1;
  private lastIconActionAt: number = 0;
  @Prop
  @Watch('syncInputFocusRequest')
  state: BrowserPageFindBarState = createBrowserPageFindClosedBarState();
  @Prop embeddedInTopChrome: boolean = false;
  onAction: (action: BrowserPageFindBarAction) => void = (_action: BrowserPageFindBarAction) => {};

  aboutToDisappear(): void {
    this.clearInputFocusRequest();
  }

  build() {
    if (this.embeddedInTopChrome) {
      this.buildEmbeddedBar()
    } else {
      this.buildFloatingBar()
    }
  }

  @Builder
  private buildEmbeddedBar() {
    Stack() {
      TopFloatingSurface({
        heightVp: PAGE_FIND_EMBEDDED_BAR_HEIGHT,
        radiusVp: PAGE_FIND_BAR_RADIUS,
        paddingLeftVp: PAGE_FIND_EMBEDDED_HORIZONTAL_PADDING,
        paddingRightVp: PAGE_FIND_EMBEDDED_HORIZONTAL_PADDING
      }) {
        this.buildBarContent()
      }
    }
    .width('100%')
    .height(PAGE_FIND_EMBEDDED_BAR_HEIGHT)
    .opacity(this.state.visible ? 1 : 0)
    .animation({ duration: 180, curve: Curve.EaseOut })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private buildFloatingBar() {
    Stack() {
      TopFloatingSurface({
        heightVp: PAGE_FIND_BAR_HEIGHT,
        radiusVp: PAGE_FIND_BAR_RADIUS,
        paddingLeftVp: 12,
        paddingRightVp: 6
      }) {
        this.buildBarContent()
      }
    }
    .width(`calc(100% - ${PAGE_FIND_BAR_HORIZONTAL_MARGIN * 2}vp)`)
    .constraintSize({ maxWidth: this.resolveFloatingBarMaxWidth() })
    .height(PAGE_FIND_BAR_HEIGHT)
    .margin({ left: PAGE_FIND_BAR_HORIZONTAL_MARGIN, right: PAGE_FIND_BAR_HORIZONTAL_MARGIN })
    .opacity(this.state.visible ? 1 : 0)
    .translate({ y: this.state.visible ? 0 : -12 })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private buildBarContent() {
    AiraIcon({
      airaIconId: 'browser.toolbar.search',
      iconSize: PAGE_FIND_ICON_SIZE,
      iconColor: this.storedSecondaryTextColor
    })
      .width(28)
      .height(28)

    TextInput({ text: this.state.query, placeholder: '在页面中查找' })
      .id(PAGE_FIND_INPUT_FOCUS_ID)
      .layoutWeight(1)
      .height(38)
      .fontSize(15)
      .fontColor(this.storedPrimaryTextColor)
      .placeholderColor(this.storedSecondaryTextColor)
      .caretColor(this.storedAccentColor)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .enterKeyType(EnterKeyType.Search)
      .textOverflow(TextOverflow.Clip)
      .padding({ left: 0, right: 0, top: 0, bottom: 0 })
      .focusOnTouch(true)
      .enableKeyboardOnFocus(true)
      .onAppear(() => {
        this.syncInputFocusRequest();
      })
      .onChange((value: string) => {
        this.onAction({ type: 'query_change', query: value });
      })
      .onSubmit((_enterKey: EnterKeyType) => {
        if (this.state.canSearchNext) {
          this.onAction({ type: 'next' });
        }
      })

    Text(this.resolveTrailingText())
      .fontSize(13)
      .fontColor(this.state.statusText.length > 0 ?
        this.storedSecondaryTextColor :
        this.storedPrimaryTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ minWidth: 42, maxWidth: 76 })
      .textAlign(TextAlign.End)

    this.buildIconButton(
      'browser.toolbar.back',
      'previous',
      PAGE_FIND_PREVIOUS_BUTTON_FOCUS_ID,
      () => this.onAction({ type: 'previous' })
    )
    this.buildIconButton(
      'browser.toolbar.back',
      'next',
      PAGE_FIND_NEXT_BUTTON_FOCUS_ID,
      () => this.onAction({ type: 'next' })
    )
    this.buildIconButton(
      'browser.toolbar.clearInput',
      'close',
      PAGE_FIND_CLOSE_BUTTON_FOCUS_ID,
      () => this.onAction({ type: 'close' })
    )
  }

  @Builder
  private buildIconButton(
    iconId: AiraRenderableIconId,
    role: BrowserPageFindBarButtonRole,
    focusId: string,
    action: () => void
  ) {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: PAGE_FIND_ICON_BUTTON_SIZE,
        surfaceHeight: PAGE_FIND_ICON_BUTTON_SIZE,
        surfaceRadius: PAGE_FIND_ICON_BUTTON_SIZE / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Stack({ alignContent: Alignment.Center }) {
          AiraIcon({
            airaIconId: iconId,
            iconSize: PAGE_FIND_ICON_SIZE,
            iconColor: this.storedPrimaryTextColor
          })
            .rotate({ angle: role === 'previous' ? 90 : role === 'next' ? -90 : 0 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .id(focusId)
    .width(PAGE_FIND_ICON_BUTTON_SIZE)
    .height(PAGE_FIND_ICON_BUTTON_SIZE)
    .borderRadius(PAGE_FIND_ICON_BUTTON_SIZE / 2)
    .opacity(this.isIconButtonEnabled(role) ? 1 : 0.42)
    .hitTestBehavior(HitTestMode.Default)
    .gesture(
      TapGesture()
        .onAction(() => {
          this.runIconButtonAction(role, action);
        })
    )
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Up) {
        this.runIconButtonAction(role, action);
      }
    })
  }

  private runIconButtonAction(role: BrowserPageFindBarButtonRole, action: () => void): void {
    if (!this.isIconButtonEnabled(role)) {
      return;
    }
    const now = Date.now();
    if (now - this.lastIconActionAt < PAGE_FIND_ICON_ACTION_THROTTLE_MS) {
      return;
    }
    this.lastIconActionAt = now;
    action();
  }

  private isIconButtonEnabled(role: BrowserPageFindBarButtonRole): boolean {
    if (role === 'previous') {
      return this.state.canSearchPrevious;
    }
    if (role === 'next') {
      return this.state.canSearchNext;
    }
    return true;
  }

  private resolveTrailingText(): string {
    if (this.state.statusText.length > 0) {
      return this.state.statusText;
    }
    return this.state.progressText;
  }

  private resolveFloatingBarMaxWidth(): Length {
    return BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen' ?
      PAGE_FIND_LARGE_SCREEN_MAX_WIDTH : '100%';
  }

  private syncInputFocusRequest(): void {
    this.clearInputFocusRequest();
    if (!this.state.visible || !this.state.inputFocused) {
      return;
    }
    this.inputFocusTimer = setTimeout(() => {
      this.inputFocusTimer = -1;
      if (this.state.visible && this.state.inputFocused) {
        focusControl.requestFocus(PAGE_FIND_INPUT_FOCUS_ID);
      }
    }, PAGE_FIND_INPUT_FOCUS_DELAY_MS);
  }

  private clearInputFocusRequest(): void {
    if (this.inputFocusTimer >= 0) {
      clearTimeout(this.inputFocusTimer);
      this.inputFocusTimer = -1;
    }
  }
}

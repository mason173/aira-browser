import {
  CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE,
  CustomHomepageSystemEntryButtonLayoutViewModel
} from '../../../core/customhome/CustomHomepageSystemEntryButtonLayoutViewModel';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';

const CUSTOM_HOMEPAGE_SYSTEM_ENTRY_BUTTON_SIZE: number = 48;
const CUSTOM_HOMEPAGE_SYSTEM_ENTRY_ICON_SIZE: number = 24;

@Component
export struct CustomHomepageSystemEntryButton {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  private layoutViewModel: CustomHomepageSystemEntryButtonLayoutViewModel =
    new CustomHomepageSystemEntryButtonLayoutViewModel();
  @Prop viewportWidth: number = 0;
  @Prop viewportHeight: number = 0;
  @Prop textColor: ResourceColor | undefined = undefined;

  onOpenTabs: () => void = () => {};
  onOpenBookmarks: () => void = () => {};
  onOpenHistory: () => void = () => {};
  onOpenSettings: () => void = () => {};

  build() {
    Button() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Stack()
            .width(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_BUTTON_SIZE)
            .height(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_BUTTON_SIZE)
            .borderRadius(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_BUTTON_SIZE / 2)
            .backgroundColor($r('app.color.surface_floating_background'))

          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_ICON_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.textColor])
        }
        .width(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_BUTTON_SIZE)
        .height(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_BUTTON_SIZE)
      }
      .width(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE)
      .height(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE)
      .padding({
        right: 16,
        bottom: 16
      })
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Bottom)
    }
    .width(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE)
    .height(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(CUSTOM_HOMEPAGE_SYSTEM_ENTRY_HIT_SIZE / 2)
    .stateEffect(true)
    .monopolizeEvents(true)
    .hitTestBehavior(HitTestMode.Block)
    .position({
      x: this.layoutViewModel.buildLayout({
        viewportWidth: this.viewportWidth,
        viewportHeight: this.viewportHeight
      }).left,
      y: this.layoutViewModel.buildLayout({
        viewportWidth: this.viewportWidth,
        viewportHeight: this.viewportHeight
      }).top
    })
    .zIndex(40)
    .bindMenu(this.buildMenu())
  }

  @Builder
  private buildMenu() {
    Menu() {
      MenuItem({ content: '标签页' })
        .onClick(() => {
          this.onOpenTabs();
        })
      MenuItem({ content: '书签' })
        .onClick(() => {
          this.onOpenBookmarks();
        })
      MenuItem({ content: '历史记录' })
        .onClick(() => {
          this.onOpenHistory();
        })
      MenuItem({ content: '设置' })
        .onClick(() => {
          this.onOpenSettings();
        })
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }
}

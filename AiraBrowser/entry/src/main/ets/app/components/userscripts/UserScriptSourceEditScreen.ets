import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  ManagementHdsMenuAction,
  ManagementHdsScaffold
} from '../common/ManagementHdsScaffold';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct UserScriptSourceEditScreen {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop source: string = '';
  onSourceChange: (source: string) => void = (_source: string) => {};
  onSave: () => void = () => {};

  build() {
    Column() {
      ManagementHdsScaffold({
        title: '脚本源码',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        menuActions: this.buildHeaderMenuActions(),
        onBack: () => {
          router.back();
        }
      }) {
        Column({ space: 12 }) {
          TextArea({ text: this.source, placeholder: '// ==UserScript==\\n// @name ...' })
            .width('100%')
            .layoutWeight(1)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor(this.storedPrimaryTextColor)
            .placeholderColor(this.storedSecondaryTextColor)
            .backgroundColor(this.storedSurfaceBackgroundColor)
            .borderRadius(22)
            .padding({ left: 14, right: 14, top: 14, bottom: 14 })
            .onChange((value: string) => {
              this.onSourceChange(value);
            })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    const actions: ManagementHdsMenuAction[] = [
      {
        label: '完成',
        icon: $r('sys.symbol.checkmark'),
        action: () => {
          this.onSave();
        }
      }
    ];
    return actions;
  }
}

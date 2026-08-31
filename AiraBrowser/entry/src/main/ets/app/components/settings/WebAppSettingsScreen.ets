import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  WebAppSettingsListItemState,
  WebAppSettingsListState
} from '../../../core/webapps/WebAppSettingsViewModel';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { AppEmptyState } from '../common/AppEmptyState';
import { SiteIconView } from '../common/SiteIconView';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';

export type WebAppSettingsPresentationMode = 'standalone' | 'embedded';

@Component
export struct WebAppSettingsScreen {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: WebAppSettingsListState = {
    items: [],
    emptyTitle: '还没有网页应用',
    emptyMessage: ''
  };
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop presentationMode: WebAppSettingsPresentationMode = 'standalone';
  @Prop desktopPresentation: boolean = false;
  @State private pressedShortcutId: string = '';
  onBack?: () => void;
  onOpenItem?: (shortcutId: string) => void;

  build() {
    if (this.presentationMode === 'embedded' && !this.desktopPresentation) {
      Column() {
        this.buildEmbeddedHeader()
        this.buildContent()
      }
      .width('100%')
      .height('100%')
    } else if (this.presentationMode === 'standalone') {
      SettingsHdsScaffold({
        title: '网页应用',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
        onBack: () => {
          this.onBack?.();
        }
      }) {
        this.buildContent()
      }
    } else {
      this.buildContent()
    }
  }

  @Builder
  private buildEmbeddedHeader() {
    Row() {
      Text('网页应用')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildContent() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: this.presentationMode === 'embedded' ? 0 : 16,
      bottomPadding: 28
    }) {
      if (this.state.items.length > 0) {
        this.buildInstalledSection()
        this.buildLimitNotice()
      } else {
        this.buildEmptyState()
      }
    }
  }

  @Builder
  private buildInstalledSection() {
    SettingsSection({ title: '已添加到桌面' }) {
      Column({ space: 12 }) {
        ForEach(this.state.items, (item: WebAppSettingsListItemState) => {
          this.buildWebAppRow(item)
        }, (item: WebAppSettingsListItemState) => `${item.shortcutId}-${item.defaultFullscreen ? '1' : '0'}`)
      }
      .width('100%')
    }
  }

  @Builder
  private buildLimitNotice() {
    SettingsFooterText({
      text: '受鸿蒙系统桌面入口能力限制，网页应用最多只能添加 2 个；这是系统限制，不是 Aira 的限制。',
      secondaryTextColor: this.storedSecondaryTextColor
    })
  }

  @Builder
  private buildWebAppRow(item: WebAppSettingsListItemState) {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      Row({ space: 12 }) {
        SiteIconView({
          iconUri: item.iconPath,
          fallbackLabel: item.title,
          iconSize: 34,
          cornerRadius: 10,
          frameBorderWidth: 0.5,
          containerBackgroundColor: this.storedPressedBackgroundColor,
          frameBorderColor: this.storedOutlineColor,
          textColor: this.storedSecondaryTextColor,
          imageContentScale: 1,
          syncLoad: true
        })

        Column({ space: 4 }) {
          Text(item.title)
            .width('100%')
            .fontSize(this.desktopPresentation ? 15 : 16)
            .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.subtitle.trim().length > 0) {
            Text(item.subtitle)
              .width('100%')
              .fontSize(13)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.storedSecondaryTextColor])
      }
      .width('100%')
      .backgroundColor(this.resolveWebAppRowBackground(item.shortcutId))
      .borderRadius(this.desktopPresentation ? 8 : 16)
      .clip(true)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      .onTouch((event: TouchEvent) => {
        this.updatePressedShortcutId(item.shortcutId, event.type);
      })
      .onClick(() => {
        this.onOpenItem?.(item.shortcutId);
      })
    }
  }

  @Builder
  private buildEmptyState() {
    AppEmptyState({
      airaIconId: 'settings.webApps',
      title: this.state.emptyTitle,
      message: this.state.emptyMessage,
      topPadding: 72,
      bottomPadding: 72
    })
  }

  private updatePressedShortcutId(shortcutId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedShortcutId = shortcutId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedShortcutId = '';
    }
  }

  private resolveWebAppRowBackground(shortcutId: string): ResourceColor {
    if (this.pressedShortcutId === shortcutId) {
      return this.storedPressedBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

}

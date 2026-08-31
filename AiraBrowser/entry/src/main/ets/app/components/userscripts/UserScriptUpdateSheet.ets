import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { UserScriptUpdateResult } from '../../../services/userscripts/UserScriptUpdateService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
} from '../browser/BrowserModalBottomSheet';
import { AiraIcon } from '../common/AiraIcon';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';

const USER_SCRIPT_UPDATE_SHEET_MAX_WIDTH: number = 540;
const USER_SCRIPT_UPDATE_RESULTS_MAX_HEIGHT: number = 360;

@Component
export struct UserScriptUpdateSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop results: UserScriptUpdateResult[] = [];
  @Prop checking: boolean = false;
  @Prop updating: boolean = false;
  @Prop fillAvailableHeight: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onUpdateSelected: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      maxWidth: USER_SCRIPT_UPDATE_SHEET_MAX_WIDTH,
      surfaceColor: this.storedPageBackgroundColor,
      fullHeight: this.layoutMode === 'phone' || this.fillAvailableHeight,
      presentation: this.layoutMode === 'large_screen' && this.fillAvailableHeight ? 'flat_content' : 'bottom_sheet',
      horizontalPadding: this.layoutMode === 'phone' ? 0 : 16,
      topPadding: this.layoutMode === 'phone' ? 0 : 26,
      bottomPadding: this.layoutMode === 'phone' ? 0 : 24
    }) {
      if (this.layoutMode === 'phone') {
        this.buildImmersivePhoneLayout()
      } else {
        this.buildLargeScreenLayout()
      }
    }
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      footerVisible: this.availableCount() > 0,
      scrollContent: () => {
        this.buildPhoneScrollContent()
      },
      header: () => {
        this.buildPhoneHeader()
      },
      footer: () => {
        this.buildUpdateButton()
      }
    })
  }

  @Builder
  private buildPhoneScrollContent() {
    Scroll() {
      Column({ space: 18 }) {
        Text(this.buildSummary())
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)

        this.buildStateCard(false)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: this.availableCount() > 0
          ? BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
          : BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }

  @Builder
  private buildPhoneHeader() {
    BrowserFeatureSheetHeader({
      title: '脚本更新检查',
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '关闭脚本更新检查',
      onLeadingAction: () => {
        this.onClose();
      }
    })
  }

  @Builder
  private buildLargeScreenLayout() {
    Column({ space: 18 }) {
      Column({ space: 6 }) {
        Text('脚本更新检查')
          .width('100%')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)

        Text(this.buildSummary())
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column() {
        this.buildStateCard(true)
      }
      .width('100%')
      .layoutWeight(this.fillAvailableHeight ? 1 : 0)

      Row({ space: 12 }) {
        BrowserSheetActionButton({
          label: '关闭',
          actionEnabled: !this.updating,
          onAction: () => {
            this.onClose();
          }
        })

        if (this.availableCount() > 0) {
          this.buildUpdateButton()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.fillAvailableHeight ? '100%' : '')
  }

  @Builder
  private buildUpdateButton() {
    BrowserSheetActionButton({
      label: this.updating ? '正在更新…' : `更新 ${this.availableCount()} 个`,
      emphasis: 'primary',
      actionEnabled: !this.checking && !this.updating,
      accentColor: this.storedAccentColor,
      onAction: () => {
        this.onUpdateSelected();
      }
    })
  }

  @Builder
  private buildStateCard(useInternalScroll: boolean) {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      fullHeight: useInternalScroll && this.fillAvailableHeight
    }) {
      if (this.checking) {
        this.buildLoadingState()
      } else if (this.results.length <= 0) {
        this.buildEmptyState()
      } else if (useInternalScroll) {
        Scroll() {
          this.buildResults()
        }
        .width('100%')
        .height(this.fillAvailableHeight ? '100%' : '')
        .constraintSize({
          maxHeight: this.fillAvailableHeight ? '100%' : USER_SCRIPT_UPDATE_RESULTS_MAX_HEIGHT
        })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
      } else {
        this.buildResults()
      }
    }
  }

  @Builder
  private buildResults() {
    Column({ space: 0 }) {
      ForEach(this.results, (result: UserScriptUpdateResult, index: number) => {
        this.buildResultRow(result)
        if (index < this.results.length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (result: UserScriptUpdateResult) => result.scriptId)
    }
    .width('100%')
  }

  @Builder
  private buildLoadingState() {
    Row({ space: 12 }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(this.storedAccentColor)

      Text('正在检查脚本更新…')
        .layoutWeight(1)
        .fontSize(16)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.fillAvailableHeight ? '100%' : '')
    .padding({ left: 12, right: 12, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildEmptyState() {
    Row({ space: 12 }) {
      AiraIcon({
        airaIconId: 'settings.userScripts',
        iconSize: 26,
        iconColor: this.storedSecondaryTextColor
      })

      Text('没有可检查更新的脚本。')
        .layoutWeight(1)
        .fontSize(16)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.fillAvailableHeight ? '100%' : '')
    .padding({ left: 12, right: 12, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildResultRow(result: UserScriptUpdateResult) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(result.scriptName.length > 0 ? result.scriptName : result.scriptId)
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.resultMessage(result))
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.statusLabel(result))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(result.status === 'available' ? this.storedAccentColor : this.storedSecondaryTextColor)
        .maxLines(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 13, bottom: 13 })
    .alignItems(VerticalAlign.Center)
  }

  private availableCount(): number {
    return this.results.filter((result: UserScriptUpdateResult) => result.status === 'available').length;
  }

  private failedCount(): number {
    return this.results.filter((result: UserScriptUpdateResult) => result.status === 'failed').length;
  }

  private buildSummary(): string {
    if (this.checking) {
      return '正在读取远程元信息，完成后会列出每个脚本的结果。';
    }
    if (this.updating) {
      return '正在安装选中的新版本。';
    }
    if (this.results.length <= 0) {
      return '当前没有脚本提供可检查的更新地址。';
    }
    const available = this.availableCount();
    if (available > 0) {
      return `发现 ${available} 个脚本有新版本，确认后再更新。`;
    }
    const failed = this.failedCount();
    if (failed > 0) {
      return `检查完成，${failed} 个脚本检查失败。`;
    }
    return '检查完成，脚本都已是最新版本。';
  }

  private statusLabel(result: UserScriptUpdateResult): string {
    if (result.status === 'available') {
      return '可更新';
    }
    if (result.status === 'up-to-date') {
      return '最新';
    }
    if (result.status === 'failed') {
      return '失败';
    }
    return '不支持';
  }

  private resultMessage(result: UserScriptUpdateResult): string {
    if (result.status === 'available') {
      return `${result.previousVersion} -> ${result.nextVersion}`;
    }
    return result.message;
  }
}

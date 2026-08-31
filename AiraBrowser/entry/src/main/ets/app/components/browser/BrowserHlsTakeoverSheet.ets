import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { MediaHlsManifestTarget } from '../../../features/mediaDiscovery/MediaHlsProjectionModels';
import {
  MediaManifestParseResult,
  MediaManifestSummary,
  MediaManifestVariant
} from '../../../features/mediaDiscovery/MediaManifestModels';
import {
  BrowserHlsTakeoverRequestContextLine,
  BrowserHlsTakeoverViewModel
} from '../../../core/browser/BrowserHlsTakeoverViewModel';
import { BrowserHlsTakeoverAction } from '../../../core/browser/BrowserMediaResourceSessionCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  BrowserBottomSheetSurface,
  BrowserModalBottomOverlay,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
} from './BrowserModalBottomSheet';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  HLS_TAKEOVER_OVERLAY_ANIMATION_DURATION_MS,
  HLS_TAKEOVER_OVERLAY_ENTER_OFFSET_Y
} from './BrowserShellPresentationTokens';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';

const HLS_TAKEOVER_SHEET_MAX_WIDTH: number = 560;
const HLS_TAKEOVER_STATUS_ICON_SIZE: number = 34;
const HLS_TAKEOVER_ROW_RADIUS: number = 10;

@Component
struct BrowserHlsTakeoverSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop target: MediaHlsManifestTarget | undefined = undefined;
  @Prop parsing: boolean = false;
  @Prop parseResult: MediaManifestParseResult | undefined = undefined;
  private viewModel: BrowserHlsTakeoverViewModel = new BrowserHlsTakeoverViewModel();
  onClose: () => void = () => {};
  onRefresh: () => void = () => {};
  onCopyUrl: () => void = () => {};
  onCopyContext: () => void = () => {};
  onOpenResources: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      maxWidth: HLS_TAKEOVER_SHEET_MAX_WIDTH,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      BrowserImmersiveSheetLayout({
        footerVisible: true,
        scrollContent: () => {
          this.buildBody()
        },
        header: () => {
          this.buildHeader()
        },
        footer: () => {
          this.buildFooter()
        }
      })
    }
  }

  @Builder
  private buildHeader() {
    BrowserFeatureSheetHeader({
      title: 'HLS 接管准备',
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '关闭 HLS 接管准备',
      onLeadingAction: () => {
        this.onClose();
      }
    })
  }

  @Builder
  private buildBody() {
    Scroll() {
      Column({ space: 12 }) {
        this.buildCandidateCard()
        this.buildParseCard()
        this.buildContextCard()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
      })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
    .clip(false)
  }

  @Builder
  private buildCandidateCard() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          this.buildStatusIcon()
          Column({ space: 4 }) {
            Text(this.buildCandidateTitle())
              .width('100%')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.buildCandidateMeta())
              .width('100%')
              .fontSize(12)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.viewModel.shortenUrl(this.target?.url ?? ''))
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    }
  }

  @Builder
  private buildStatusIcon() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(HLS_TAKEOVER_STATUS_ICON_SIZE)
        .height(HLS_TAKEOVER_STATUS_ICON_SIZE)
        .fill(this.storedPressedBackgroundColor)

      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(18)
        .fontColor([this.storedAccentColor])
    }
    .width(HLS_TAKEOVER_STATUS_ICON_SIZE)
    .height(HLS_TAKEOVER_STATUS_ICON_SIZE)
  }

  @Builder
  private buildParseCard() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      Column({ space: 12 }) {
        if (this.parsing) {
          Row({ space: 10 }) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(this.storedAccentColor)
            Column({ space: 3 }) {
              Text('正在解析 m3u8 清单')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.storedPrimaryTextColor)
              Text('会探测 master/media、清晰度、分片、Key 和请求上下文。')
                .fontSize(12)
                .fontColor(this.storedSecondaryTextColor)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else if (this.parseResult?.ok === true && this.parseResult?.summary !== undefined) {
          this.buildSummary(this.parseResult.summary)
        } else if (this.parseResult !== undefined) {
          this.buildParseError()
        } else {
          this.buildParseEmpty()
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    }
  }

  @Builder
  private buildParseEmpty() {
    Column({ space: 5 }) {
      Text('等待解析')
        .width('100%')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
      Text('点击浮窗后会自动解析；也可以手动刷新清单。')
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildParseError() {
    Column({ space: 5 }) {
      Text('清单解析失败')
        .width('100%')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
      Text(this.parseResult?.errorMessage ?? '清单解析失败。')
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildSummary(summary: MediaManifestSummary) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.viewModel.buildSummaryTitle(summary))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(summary.encrypted ? '加密' : '未加密')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedAccentColor)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor(this.storedPressedBackgroundColor)
          .borderRadius(8)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.viewModel.buildSummaryMetrics(summary))
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (summary.variants.length > 0) {
        Column({ space: 6 }) {
          ForEach(summary.variants, (variant: MediaManifestVariant) => {
            this.buildVariantRow(variant)
          }, (variant: MediaManifestVariant) => variant.index.toString() + variant.url)
        }
        .width('100%')
      }

      if (summary.keyUrls.length > 0) {
        this.buildInfoLine('Key', summary.keyUrls.length.toString() + ' 个 · ' + this.viewModel.shortenUrl(summary.keyUrls[0]))
      }

      if (summary.sampleSegments.length > 0) {
        this.buildInfoLine('样例分片', this.viewModel.shortenUrl(summary.sampleSegments[0]))
      }

      if (summary.warnings.length > 0) {
        this.buildInfoLine('提示', summary.warnings[0])
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildVariantRow(variant: MediaManifestVariant) {
    Row({ space: 8 }) {
      Text(this.viewModel.buildVariantName(variant))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.viewModel.buildVariantMeta(variant))
        .fontSize(11)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .borderRadius(HLS_TAKEOVER_ROW_RADIUS)
    .backgroundColor(this.storedControlBackgroundColor)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildInfoLine(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
      Text(value)
        .fontSize(11)
        .fontColor(this.storedSecondaryTextColor)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildContextCard() {
    SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
      Column({ space: 0 }) {
        Row() {
          Text('请求上下文')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .layoutWeight(1)
          Text(this.buildContextCountLabel())
            .fontSize(12)
            .fontColor(this.storedSecondaryTextColor)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 10 })
        .alignItems(VerticalAlign.Center)

        if (this.resolveContextLines().length > 0) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          ForEach(this.resolveContextLines(), (line: BrowserHlsTakeoverRequestContextLine, index: number) => {
            this.buildContextRow(line)
            if (index < this.resolveContextLines().length - 1) {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
          }, (line: BrowserHlsTakeoverRequestContextLine) => line.label + line.value)
        }
      }
      .width('100%')
    }
  }

  @Builder
  private buildContextRow(line: BrowserHlsTakeoverRequestContextLine) {
    Column({ space: 4 }) {
      Text(line.label)
        .width('100%')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.viewModel.shortenUrl(line.value))
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFooter() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '复制链接',
          emphasis: 'secondary',
          actionEnabled: this.target !== undefined,
          onAction: () => {
            this.onCopyUrl();
          }
        })
        BrowserSheetActionButton({
          label: '刷新解析',
          emphasis: 'primary',
          actionEnabled: this.target !== undefined && !this.parsing,
          accentColor: this.storedAccentColor,
          onAction: () => {
            this.onRefresh();
          }
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '复制上下文',
          emphasis: 'secondary',
          actionEnabled: this.target !== undefined,
          onAction: () => {
            this.onCopyContext();
          }
        })
        BrowserSheetActionButton({
          label: '资源嗅探',
          emphasis: 'secondary',
          actionEnabled: true,
          onAction: () => {
            this.onOpenResources();
          }
        })
      }
      .width('100%')
    }
    .width('100%')
  }

  private buildHeaderSubtitle(): string {
    if (this.target === undefined) {
      return '没有可处理的 HLS 清单';
    }
    return this.target.sourceHost.length > 0 ? this.target.sourceHost : this.viewModel.shortenUrl(this.target.url);
  }

  private buildCandidateTitle(): string {
    if (this.target === undefined) {
      return '未选择清单';
    }
    if (this.target.kind === 'dash') {
      return 'DASH 清单';
    }
    return 'HLS m3u8 清单';
  }

  private buildCandidateMeta(): string {
    const target = this.target;
    if (target === undefined) {
      return '暂无资源';
    }
    const parts: string[] = [];
    if (target.frameType === 'main_frame') {
      parts.push('主框架');
    } else if (target.frameType === 'sub_frame' || target.frameType === 'dom_frame') {
      parts.push('iframe/子框架');
    }
    if (target.sourceHost.length > 0) {
      parts.push(target.sourceHost);
    }
    if ((target.mimeType?.length ?? 0) > 0) {
      parts.push(target.mimeType ?? '');
    }
    return parts.length > 0 ? parts.join(' · ') : '已发现流媒体清单';
  }

  private resolveContextLines(): BrowserHlsTakeoverRequestContextLine[] {
    return this.viewModel.buildContextLines(this.target);
  }

  private buildContextCountLabel(): string {
    const count = this.resolveContextLines().length;
    return count > 0 ? count.toString() + ' 项' : '暂无';
  }
}

@Component
export struct BrowserHlsTakeoverOverlay {
  @Prop visible: boolean = false;
  @Prop target: MediaHlsManifestTarget | undefined = undefined;
  @Prop parsing: boolean = false;
  @Prop parseResult: MediaManifestParseResult | undefined = undefined;
  onAction: (action: BrowserHlsTakeoverAction) => void = (_action: BrowserHlsTakeoverAction) => {};

  build() {
    BrowserModalBottomOverlay({
      visible: this.visible,
      sheetHeight: '78%',
      enterOffsetY: HLS_TAKEOVER_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: HLS_TAKEOVER_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      onDismiss: () => {
        this.onAction('close');
      }
    }) {
      BrowserHlsTakeoverSheet({
        target: this.target,
        parsing: this.parsing,
        parseResult: this.parseResult,
        onClose: () => {
          this.onAction('close');
        },
        onRefresh: () => {
          this.onAction('refresh');
        },
        onCopyUrl: () => {
          this.onAction('copy_url');
        },
        onCopyContext: () => {
          this.onAction('copy_context');
        },
        onOpenResources: () => {
          this.onAction('open_resources');
        }
      })
    }
  }
}

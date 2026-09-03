import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  MediaResourceAction,
  MediaResourceListItem,
  MediaResourceTabCounts,
  emptyMediaResourceTabCounts
} from '../../../features/mediaDiscovery/MediaResourceProjectionModels';
import {
  MediaManifestParseResult,
  MediaManifestSummary,
  MediaManifestVariant
} from '../../../features/mediaDiscovery/MediaManifestModels';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
  BrowserSheetIconButton
} from './BrowserModalBottomSheet';
import {
  SegmentedTabOption,
  SegmentedTabs
} from '../common/SegmentedTabs';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode
} from '../common/FloatingGlassMaterialTokens';

type MediaResourceSurfaceTab = 'video' | 'other';

const RESOURCE_TABS: MediaResourceSurfaceTab[] = [
  'video',
  'other'
];

const BROWSER_RESOURCE_SHEET_MAX_WIDTH: number = 560;
const RESOURCE_ROW_MIN_HEIGHT: number = 78;
const RESOURCE_VIDEO_CARD_GAP: number = 10;
const RESOURCE_VIDEO_CARD_RADIUS: number = 12;
const RESOURCE_VIDEO_THUMBNAIL_WIDTH: number = 72;
const RESOURCE_VIDEO_THUMBNAIL_HEIGHT: number = 56;
const RESOURCE_VIDEO_THUMBNAIL_RADIUS: number = 8;
const RESOURCE_IMAGE_GRID_GAP: number = 8;
const RESOURCE_IMAGE_GRID_NARROW_WIDTH: number = 340;
const RESOURCE_IMAGE_GRID_WIDE_WIDTH: number = 520;
const RESOURCE_IMAGE_GRID_CARD_RADIUS: number = 8;
const RESOURCE_IMAGE_PREVIEW_BACKGROUND_COLOR: string = '#000000';
const RESOURCE_IMAGE_PREVIEW_FOREGROUND_COLOR: string = '#FFFFFF';
const RESOURCE_IMAGE_PREVIEW_CLOSE_SIZE: number = 44;
const RESOURCE_IMAGE_PREVIEW_TOP_PADDING: number = 54;
const RESOURCE_IMAGE_PREVIEW_SIDE_PADDING: number = 16;
const RESOURCE_TAB_INDEX_VIDEO: number = 0;
const RESOURCE_TAB_INDEX_OTHER: number = 1;
const BROWSER_RESOURCE_SHEET_CONTENT_TOP_PADDING: number = 124;

function describeKind(candidate: MediaResourceListItem): string {
  if (candidate.acquisition?.mode === 'paired_adaptive') {
    return '自适应音视频';
  }
  if (candidate.acquisition?.mode === 'progressive') {
    return candidate.acquisition.primaryTrack.role === 'audio' ? '音频' : '渐进式视频';
  }
  switch (candidate.kind) {
    case 'hls': return 'HLS';
    case 'dash': return 'DASH';
    case 'mp4': return 'MP4';
    case 'webm': return 'WebM';
    case 'mov': return 'MOV';
    case 'flv': return 'FLV';
    case 'mkv': return 'MKV';
    case 'avi': return 'AVI';
    case 'mpeg': return 'MPEG';
    case 'wmv': return 'WMV';
    case 'ogv': return 'OGV';
    case 'audio': return '音频';
    case 'image': return '图片';
    case 'document': return '文档';
    case 'archive': return '压缩包';
    case 'package': return '安装包';
    case 'segment': return '媒体分片';
    default: return '未知资源';
  }
}

function describeStatus(candidate: MediaResourceListItem): string {
  switch (candidate.status) {
    case 'playing_native': return '正在接管播放';
    case 'playable': return '已验证视频';
    case 'downloadable': return '可下载';
    case 'needs_processing':
      return candidate.kind === 'dash' ? '待解析视频' :
        candidate.actions.indexOf('download') >= 0 ? '可下载' : '需要处理';
    case 'protected': return '受保护，暂不支持';
    case 'expired': return '地址可能已过期';
    case 'unsupported': return describeFailureReason(candidate.failureReason);
    case 'failed': return '处理失败：' + (candidate.failureReason ?? '未知原因');
    default: return candidate.actions.indexOf('download') >= 0 ? '可下载' : '已发现';
  }
}

function describeFailureReason(reason: string | undefined): string {
  if (reason === 'hls_requires_web_mse_runtime') {
    return '需要网页 MSE，仅能由当前网页播放';
  }
  if (reason === 'hls_child_headers_not_inherited') {
    return 'HLS 分片鉴权暂不处理';
  }
  return '当前版本暂不支持';
}

function belongsToTab(candidate: MediaResourceListItem, tab: MediaResourceSurfaceTab): boolean {
  if (candidate.family === 'segment') {
    return false;
  }
  const videoFamily = candidate.family === 'video' ||
    (candidate.family === 'manifest' && candidate.acquisition?.primaryTrack.role !== 'audio');
  const actionableVideo = candidate.actions.indexOf('download') >= 0 ||
    candidate.actions.indexOf('parse_manifest') >= 0;
  const exceptionalVideo = candidate.status === 'protected' ||
    candidate.status === 'expired' ||
    candidate.status === 'unsupported' ||
    candidate.status === 'failed';
  if (tab === 'video') {
    return videoFamily && (actionableVideo || exceptionalVideo);
  }
  return !videoFamily || (!actionableVideo && !exceptionalVideo);
}

function shortenUrl(url: string): string {
  if (url.length <= 72) {
    return url;
  }
  return url.substring(0, 44) + '...' + url.substring(url.length - 24);
}

function buildMeta(candidate: MediaResourceListItem): string {
  const parts: string[] = [];
  const frameLabel = describeFrameType(candidate);
  if (frameLabel.length > 0) {
    parts.push(frameLabel);
  }
  if (candidate.sourceHost.length > 0) {
    parts.push(candidate.sourceHost);
  }
  if ((candidate.extension?.length ?? 0) > 0) {
    parts.push((candidate.extension ?? '').toUpperCase());
  }
  if (candidate.width !== undefined && candidate.height !== undefined && candidate.width > 0 && candidate.height > 0) {
    parts.push(candidate.width.toString() + 'x' + candidate.height.toString());
  }
  if (candidate.durationMs !== undefined && candidate.durationMs > 0) {
    parts.push(formatDuration(candidate.durationMs));
  }
  if (candidate.totalBytes !== undefined && candidate.totalBytes > 0) {
    parts.push(formatBytes(candidate.totalBytes));
  }
  return parts.join(' · ');
}

function describeFrameType(candidate: MediaResourceListItem): string {
  switch (candidate.frameType) {
    case 'main_frame': return '主框架';
    case 'sub_frame': return '子框架';
    case 'dom_frame': return 'iframe 入口';
    case 'dom_document': return candidate.source === 'dom' ? '页面扫描' : '';
    default: return '';
  }
}

function formatDuration(durationMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) {
    return hours.toString() + ':' + (minutes < 10 ? '0' : '') + minutes.toString() +
      ':' + (seconds < 10 ? '0' : '') + seconds.toString();
  }
  return minutes.toString() + ':' + (seconds < 10 ? '0' : '') + seconds.toString();
}

function formatBytes(bytes: number): string {
  const normalized = Math.max(0, Math.floor(bytes));
  if (normalized >= 1073741824) {
    return formatUnitValue(normalized / 1073741824) + ' GB';
  }
  if (normalized >= 1048576) {
    return formatUnitValue(normalized / 1048576) + ' MB';
  }
  if (normalized >= 1024) {
    return formatUnitValue(normalized / 1024) + ' KB';
  }
  return normalized.toString() + ' B';
}

function formatEstimatedBytes(bytes: number): string {
  const normalized = Math.max(0, Math.floor(bytes));
  if (normalized >= 1000000000) {
    return formatUnitValue(normalized / 1000000000) + ' GB';
  }
  if (normalized >= 1000000) {
    return formatUnitValue(normalized / 1000000) + ' MB';
  }
  if (normalized >= 1000) {
    return formatUnitValue(normalized / 1000) + ' KB';
  }
  return normalized.toString() + ' B';
}

function formatUnitValue(value: number): string {
  if (value >= 100) {
    return Math.round(value).toString();
  }
  if (value >= 10) {
    return (Math.round(value * 10) / 10).toString();
  }
  return (Math.round(value * 100) / 100).toString();
}

@Component
export struct BrowserMediaResourcesSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop
  @Watch('pruneFailedImageCandidates')
  candidates: MediaResourceListItem[] = [];
  @Prop
  @Watch('syncActiveTab')
  counts: MediaResourceTabCounts = emptyMediaResourceTabCounts();
  @Prop manifestParsingCandidateId: string = '';
  @Prop manifestParseResult: MediaManifestParseResult | undefined = undefined;
  @Prop scanning: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @State activeTab: MediaResourceSurfaceTab = 'video';
  @State contentWidth: number = BROWSER_RESOURCE_SHEET_MAX_WIDTH;
  @State failedImageCandidateIds: string[] = [];
  private resourceTabSwiperController: SwiperController = new SwiperController();
  onClose: () => void = () => {};
  onAction: (candidateId: string, action: MediaResourceAction) => void = (_candidateId: string, _action: MediaResourceAction) => {};

  aboutToAppear(): void {
    this.pruneFailedImageCandidates();
    this.syncActiveTab();
  }

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
      maxWidth: BROWSER_RESOURCE_SHEET_MAX_WIDTH,
      horizontalPadding: this.layoutMode === 'phone' ? 0 : 16,
      topPadding: this.layoutMode === 'phone' ? 0 : 26,
      bottomPadding: this.layoutMode === 'phone' ? 0 : 24,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      if (this.layoutMode === 'phone') {
        Stack() {
          BrowserImmersiveSheetLayout({
            scrollContent: () => {
              this.buildList()
            },
            header: () => {
              this.buildPhoneHeader()
            }
          })
        }
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const nextWidth = this.parseAreaDimension(newArea.width);
          if (nextWidth > 0 && Math.abs(nextWidth - this.contentWidth) >= 1) {
            this.contentWidth = nextWidth;
          }
        })
      } else {
        Column({ space: 14 }) {
          this.buildTabs()
          this.buildList()
        }
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const nextWidth = this.parseAreaDimension(newArea.width);
          if (nextWidth > 0 && Math.abs(nextWidth - this.contentWidth) >= 1) {
            this.contentWidth = nextWidth;
          }
        })
      }
    }
  }

  @Builder
  private buildPhoneHeader() {
    Column({ space: 14 }) {
      BrowserFeatureSheetHeader({
        title: this.buildTitle(),
        titleColor: this.storedPrimaryTextColor,
        leadingAccessibilityLabel: '关闭资源嗅探',
        onLeadingAction: () => {
          this.onClose();
        }
      })

      this.buildTabs()
    }
    .width('100%')
  }

  @Builder
  private buildTabs() {
    SegmentedTabs({
      options: this.buildTabOptions(),
      selectedId: this.activeTab,
      barHeight: 36,
      itemHeight: 30,
      fontSize: 12,
      barPadding: 3,
      secondaryTextColor: this.storedSecondaryTextColor,
      onSelect: (id: string) => {
        this.activeTab = id as MediaResourceSurfaceTab;
        this.syncSwiperToActiveTab(true);
      }
    })
    .width('100%')
  }

  @Builder
  private buildList() {
    Swiper(this.resourceTabSwiperController) {
      this.buildResourcePage('video')
      this.buildResourcePage('other')
    }
    .index(this.resolveActiveTabIndex())
    .indicator(false)
    .loop(false)
    .duration(280)
    .cachedCount(2)
    .width('100%')
    .height('100%')
    .onChange((index: number) => {
      this.syncActiveTabFromIndex(index);
    })
  }

  @Builder
  private buildResourcePage(tab: MediaResourceSurfaceTab) {
    Scroll() {
      Column() {
        if (this.filteredCandidatesForTab(tab).length === 0 && this.scanning) {
          AppEmptyState({
            airaIconId: 'browser.shortcut.pageResources',
            title: '正在扫描页面资源',
            message: '先展示已捕获的网络资源，页面隐藏链接会在扫描完成后补充。',
            topPadding: 28,
            bottomPadding: 28,
            fillHeight: true
          })
        } else if (this.filteredCandidatesForTab(tab).length === 0) {
          AppEmptyState({
            airaIconId: 'browser.shortcut.pageResources',
            title: this.buildEmptyTitle(tab),
            message: '部分网站会加密、延迟加载或隐藏真实资源地址。',
            topPadding: 28,
            bottomPadding: 28,
            fillHeight: true
          })
        } else {
          if (tab === 'video') {
            this.buildManifestDetailSection()
          }
          if (tab === 'video') {
            this.buildVideoCardList()
          } else {
            this.buildOtherResourceList()
          }
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: this.layoutMode === 'phone' ? 16 : 0,
        right: this.layoutMode === 'phone' ? 16 : 0,
        top: this.layoutMode === 'phone' ? BROWSER_RESOURCE_SHEET_CONTENT_TOP_PADDING : 0,
        bottom: this.layoutMode === 'phone' ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING : 0
      })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
  }

  @Builder
  private buildOtherResourceList() {
    Column({ space: 12 }) {
      if (this.imageCandidates().length > 0) {
        Text('图片 ' + this.imageCandidates().length.toString())
          .width('100%')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
        this.buildImageGrid()
      }
      if (this.nonImageOtherCandidates().length > 0) {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          ForEach(this.nonImageOtherCandidates(), (candidate: MediaResourceListItem, index: number) => {
            this.buildResourceRow(candidate)
            if (index < this.nonImageOtherCandidates().length - 1) {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
          }, (candidate: MediaResourceListItem) => candidate.id)
        }
      }
    }
  }

  @Builder
  private buildManifestDetailSection() {
    if (this.manifestParsingCandidateId.length > 0 || this.manifestParseResult !== undefined) {
      Column({ space: 10 }) {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          Column({ space: 10 }) {
            if (this.manifestParsingCandidateId.length > 0) {
              Row({ space: 10 }) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color(this.storedAccentColor)
                Text('正在解析流媒体清单...')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.storedPrimaryTextColor)
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            } else if (this.manifestParseResult?.ok === true && this.manifestParseResult?.summary !== undefined) {
              this.buildManifestSummary(this.manifestParseResult.summary)
            } else if (this.manifestParseResult !== undefined) {
              Text(this.manifestParseResult.errorMessage.length > 0 ?
                this.manifestParseResult.errorMessage : '清单解析失败。')
                .width('100%')
                .fontSize(14)
                .fontColor(this.storedSecondaryTextColor)
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })
        }
      }
      .width('100%')
      .margin({ bottom: 10 })
    }
  }

  @Builder
  private buildManifestSummary(summary: MediaManifestSummary) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.buildManifestTitle(summary))
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

      Text(this.buildManifestMetrics(summary))
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (summary.variants.length > 0) {
        Column({ space: 6 }) {
          ForEach(summary.variants, (variant: MediaManifestVariant) => {
            this.buildManifestVariantRow(variant)
          }, (variant: MediaManifestVariant) => variant.index.toString() + variant.url)
        }
        .width('100%')
      }

      if (summary.keyUrls.length > 0) {
        Text('Key ' + summary.keyUrls.length.toString() + ' 个 · ' + shortenUrl(summary.keyUrls[0]))
          .width('100%')
          .fontSize(11)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (summary.sampleSegments.length > 0) {
        Text('样例分片 ' + shortenUrl(summary.sampleSegments[0]))
          .width('100%')
          .fontSize(11)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (summary.warnings.length > 0) {
        Text(summary.warnings[0])
          .width('100%')
          .fontSize(11)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildManifestVariantRow(variant: MediaManifestVariant) {
    Row({ space: 8 }) {
      Text(this.buildVariantName(variant))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.buildVariantMeta(variant))
        .fontSize(11)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .borderRadius(8)
    .backgroundColor(this.storedControlBackgroundColor)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildVideoCardList() {
    Column({ space: RESOURCE_VIDEO_CARD_GAP }) {
      ForEach(this.filteredCandidatesForTab('video'), (candidate: MediaResourceListItem) => {
        BrowserResourceVideoCard({
          candidate: candidate,
          accentColor: this.storedAccentColor,
          cardBackgroundColor: this.storedSurfaceBackgroundColor,
          thumbnailBackgroundColor: this.storedControlBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onAction: (candidateId: string, action: MediaResourceAction) => {
            this.onAction(candidateId, action);
          }
        })
      }, (candidate: MediaResourceListItem) => candidate.id)
    }
    .width('100%')
  }

  @Builder
  private buildImageGrid() {
    Grid() {
      ForEach(this.imageCandidates(), (candidate: MediaResourceListItem) => {
        GridItem() {
          this.buildImageGridCard(candidate)
        }
      }, (candidate: MediaResourceListItem) => candidate.id)
    }
    .width('100%')
    .columnsTemplate(this.resolveImageGridColumnsTemplate())
    .columnsGap(RESOURCE_IMAGE_GRID_GAP)
    .rowsGap(RESOURCE_IMAGE_GRID_GAP)
    .scrollBar(BarState.Off)
  }

  @Builder
  private buildImageGridCard(candidate: MediaResourceListItem) {
    BrowserResourceImageGridCard({
      candidate: candidate,
      cardBackgroundColor: this.storedControlBackgroundColor,
      onImageLoadFailed: (candidateId: string) => {
        this.markImageLoadFailed(candidateId);
      },
      onAction: (candidateId: string, action: MediaResourceAction) => {
        this.onAction(candidateId, action);
      }
    })
  }

  @Builder
  private buildResourceRow(candidate: MediaResourceListItem) {
    Row({ space: 12 }) {
      this.buildResourceIcon(candidate)

      Column({ space: 5 }) {
        Column({ space: 3 }) {
          Text(candidate.displayName.length > 0 ? candidate.displayName : describeKind(candidate))
            .width('100%')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(buildMeta(candidate))
            .width('100%')
            .fontSize(11)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Text(shortenUrl(candidate.url))
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(describeStatus(candidate))
            .fontSize(11)
            .fontColor(this.storedSecondaryTextColor)
            .layoutWeight(1)

          this.buildActionButtons(candidate)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .constraintSize({ minHeight: RESOURCE_ROW_MIN_HEIGHT })
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
  }

  @Builder
  private buildResourceIcon(candidate: MediaResourceListItem) {
    Row() {
      SymbolGlyph(this.resolveResourceIcon(candidate))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.storedAccentColor])
    }
    .width(34)
    .height(34)
    .borderRadius(12)
    .backgroundColor(this.storedControlBackgroundColor)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildActionButtons(candidate: MediaResourceListItem) {
    Row({ space: 4 }) {
      if (candidate.actions.indexOf('parse_manifest') >= 0) {
        this.buildActionButton(candidate, 'parse_manifest', '解析', true)
      }
      if (candidate.actions.indexOf('download') >= 0) {
        this.buildActionButton(candidate, 'download', '下载', false)
      }
      if (candidate.actions.indexOf('copy') >= 0) {
        this.buildActionButton(candidate, 'copy', '复制', false)
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildActionButton(candidate: MediaResourceListItem, action: MediaResourceAction, label: string, primary: boolean) {
    BrowserSheetActionButton({
      label: label,
      emphasis: primary ? 'primary' : 'secondary',
      accentColor: this.storedAccentColor,
      fillAvailableWidth: false,
      buttonWidth: 56,
      buttonHeight: 28,
      fontSize: 13,
      onAction: () => {
        this.onAction(candidate.id, action);
      }
    })
  }

  private buildTabOptions(): SegmentedTabOption[] {
    const options: SegmentedTabOption[] = [];
    for (let i = 0; i < RESOURCE_TABS.length; i++) {
      const tab = RESOURCE_TABS[i];
      options.push({
        id: tab,
        title: this.resolveTabLabel(tab) + ' ' + this.resolveVisibleCountForTab(tab).toString()
      });
    }
    return options;
  }

  private resolveTabLabel(tab: MediaResourceSurfaceTab): string {
    return tab === 'video' ? '视频' : '其他资源';
  }

  private resolveResourceIcon(candidate: MediaResourceListItem): Resource {
    switch (candidate.family) {
      case 'video': return $r('sys.symbol.play_fill');
      case 'manifest':
      case 'segment': return $r('sys.symbol.doc_text_fill');
      case 'audio': return $r('sys.symbol.play_fill');
      case 'image': return $r('sys.symbol.doc_text_fill');
      case 'file': return $r('sys.symbol.doc_text_fill');
      default: return $r('sys.symbol.doc_text_fill');
    }
  }

  private filteredCandidatesForTab(tab: MediaResourceSurfaceTab): MediaResourceListItem[] {
    const results: MediaResourceListItem[] = [];
    for (let i = 0; i < this.candidates.length; i++) {
      if (belongsToTab(this.candidates[i], tab) && !this.isHiddenFailedImageCandidate(this.candidates[i])) {
        results.push(this.candidates[i]);
      }
    }
    return results;
  }

  private markImageLoadFailed(candidateId: string): void {
    const normalizedId = candidateId.trim();
    if (normalizedId.length <= 0 || this.failedImageCandidateIds.indexOf(normalizedId) >= 0) {
      return;
    }
    const nextFailedIds = this.failedImageCandidateIds.slice();
    nextFailedIds.push(normalizedId);
    this.failedImageCandidateIds = nextFailedIds;
  }

  private pruneFailedImageCandidates(): void {
    if (this.failedImageCandidateIds.length <= 0) {
      return;
    }
    const nextFailedIds: string[] = [];
    for (let i = 0; i < this.failedImageCandidateIds.length; i++) {
      if (this.hasImageCandidateId(this.failedImageCandidateIds[i])) {
        nextFailedIds.push(this.failedImageCandidateIds[i]);
      }
    }
    if (nextFailedIds.length !== this.failedImageCandidateIds.length) {
      this.failedImageCandidateIds = nextFailedIds;
    }
  }

  private hasImageCandidateId(candidateId: string): boolean {
    for (let i = 0; i < this.candidates.length; i++) {
      if (this.candidates[i].id === candidateId && this.candidates[i].family === 'image') {
        return true;
      }
    }
    return false;
  }

  private isHiddenFailedImageCandidate(candidate: MediaResourceListItem): boolean {
    return candidate.family === 'image' && this.failedImageCandidateIds.indexOf(candidate.id) >= 0;
  }

  private resolveVisibleCountForTab(tab: MediaResourceSurfaceTab): number {
    return this.filteredCandidatesForTab(tab).length;
  }

  private imageCandidates(): MediaResourceListItem[] {
    const results: MediaResourceListItem[] = [];
    for (let i = 0; i < this.candidates.length; i++) {
      const candidate = this.candidates[i];
      if (candidate.family === 'image' && !this.isHiddenFailedImageCandidate(candidate)) {
        results.push(candidate);
      }
    }
    return results;
  }

  private nonImageOtherCandidates(): MediaResourceListItem[] {
    const results: MediaResourceListItem[] = [];
    for (let i = 0; i < this.candidates.length; i++) {
      const candidate = this.candidates[i];
      if (belongsToTab(candidate, 'other') && candidate.family !== 'image' &&
        !this.isHiddenFailedImageCandidate(candidate)) {
        results.push(candidate);
      }
    }
    return results;
  }

  private resolveImageGridColumnsTemplate(): string {
    if (this.contentWidth < RESOURCE_IMAGE_GRID_NARROW_WIDTH) {
      return '1fr 1fr';
    }
    if (this.contentWidth >= RESOURCE_IMAGE_GRID_WIDE_WIDTH) {
      return '1fr 1fr 1fr 1fr';
    }
    return '1fr 1fr 1fr';
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private syncActiveTab(): void {
    if (RESOURCE_TABS.indexOf(this.activeTab) >= 0 && this.resolveVisibleCountForTab(this.activeTab) > 0) {
      return;
    }
    for (let i = 0; i < RESOURCE_TABS.length; i++) {
      const tab = RESOURCE_TABS[i];
      if (this.resolveVisibleCountForTab(tab) > 0) {
        this.activeTab = tab;
        this.syncSwiperToActiveTab(false);
        return;
      }
    }
    this.activeTab = RESOURCE_TABS[0];
    this.syncSwiperToActiveTab(false);
  }

  private buildTitle(): string {
    return '资源嗅探';
  }

  private buildEmptyTitle(tab: MediaResourceSurfaceTab): string {
    return tab === 'video' ? '当前页面未检测到视频' : '当前页面没有其他资源';
  }

  private buildManifestTitle(summary: MediaManifestSummary): string {
    if (summary.kind === 'hls') {
      return summary.role === 'master' ? 'HLS Master 清单' : 'HLS Media 清单';
    }
    if (summary.kind === 'dash') {
      return 'DASH MPD 清单';
    }
    return '流媒体清单';
  }

  private buildManifestMetrics(summary: MediaManifestSummary): string {
    const parts: string[] = [];
    if (summary.sourceHost.length > 0) {
      parts.push(summary.sourceHost);
    }
    if (summary.variantCount > 0) {
      parts.push(summary.variantCount.toString() + ' 个清晰度');
    }
    if (summary.segmentCount > 0) {
      parts.push(summary.segmentCount.toString() + ' 个分片');
    }
    if (summary.durationSeconds > 0) {
      parts.push(formatDuration(summary.durationSeconds * 1000));
    }
    if (summary.keyCount > 0) {
      parts.push(summary.keyCount.toString() + ' 个 Key');
    }
    return parts.length > 0 ? parts.join(' · ') : shortenUrl(summary.url);
  }

  private buildVariantName(variant: MediaManifestVariant): string {
    if (variant.name.length > 0) {
      return variant.name;
    }
    if (variant.resolution.length > 0) {
      return variant.resolution;
    }
    if (variant.bandwidth > 0) {
      return Math.round(variant.bandwidth / 1000).toString() + ' kbps';
    }
    return '清晰度 ' + (variant.index + 1).toString();
  }

  private buildVariantMeta(variant: MediaManifestVariant): string {
    const parts: string[] = [];
    if (variant.bandwidth > 0) {
      parts.push(Math.round(variant.bandwidth / 1000).toString() + ' kbps');
    }
    if (variant.segmentCount > 0) {
      parts.push(variant.segmentCount.toString() + ' 分片');
    }
    if (variant.targetDuration > 0) {
      parts.push(variant.targetDuration.toString() + 's');
    }
    if (variant.encrypted) {
      parts.push('加密');
    }
    return parts.length > 0 ? parts.join(' · ') : shortenUrl(variant.url);
  }

  private resolveActiveTabIndex(): number {
    return this.resolveTabIndex(this.activeTab);
  }

  private resolveTabIndex(tab: MediaResourceSurfaceTab): number {
    return tab === 'other' ? RESOURCE_TAB_INDEX_OTHER : RESOURCE_TAB_INDEX_VIDEO;
  }

  private resolveTabByIndex(index: number): MediaResourceSurfaceTab {
    return index === RESOURCE_TAB_INDEX_OTHER ? 'other' : 'video';
  }

  private syncActiveTabFromIndex(index: number): void {
    const nextTab = this.resolveTabByIndex(index);
    if (nextTab === this.activeTab) {
      return;
    }
    this.activeTab = nextTab;
  }

  private syncSwiperToActiveTab(withAnimation: boolean): void {
    const index = this.resolveActiveTabIndex();
    if (withAnimation) {
      this.resourceTabSwiperController.changeIndex(index);
      return;
    }
    this.resourceTabSwiperController.changeIndex(index, false);
  }
}

@Component
struct BrowserResourceVideoCard {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop candidate: MediaResourceListItem = createEmptyMediaResourceListItem();
  @Prop accentColor: ResourceColor = '#0A59F7';
  @Prop cardBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop thumbnailBackgroundColor: ResourceColor = '#EEF2F6';
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @State menuVisible: boolean = false;
  onAction: (candidateId: string, action: MediaResourceAction) => void =
    (_candidateId: string, _action: MediaResourceAction) => {};

  build() {
    Row({ space: 10 }) {
      this.buildThumbnail()

      Column({ space: 8 }) {
        Text(this.buildTitle())
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          Text(this.buildVideoSummary())
            .fontSize(12)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          this.buildPrimaryAction()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .borderRadius(RESOURCE_VIDEO_CARD_RADIUS)
    .backgroundColor(this.cardBackgroundColor)
    .gesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
        .onAction(() => {
          this.openMenu();
        })
    )
    .bindContextMenu(this.menuVisible, this.buildMenu(), {
      preview: this.buildMenuPreview(),
      previewBorderRadius: RESOURCE_VIDEO_CARD_RADIUS,
      onDisappear: () => {
        this.menuVisible = false;
      }
    })
  }

  @Builder
  private buildThumbnail() {
    Stack({ alignContent: Alignment.Center }) {
      if ((this.candidate.posterUrl?.trim().length ?? 0) > 0) {
        Image(this.candidate.posterUrl ?? '')
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor(this.thumbnailBackgroundColor)
          .draggable(false)
      } else {
        Column({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.accentColor])

          Text(this.buildKindBadge())
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(RESOURCE_VIDEO_THUMBNAIL_WIDTH)
    .height(RESOURCE_VIDEO_THUMBNAIL_HEIGHT)
    .borderRadius(RESOURCE_VIDEO_THUMBNAIL_RADIUS)
    .clip(true)
    .backgroundColor(this.thumbnailBackgroundColor)
  }

  @Builder
  private buildPrimaryAction() {
    if (this.candidate.actions.indexOf('download') >= 0) {
      this.buildPrimaryActionButton('download', '下载', true)
    } else if (this.candidate.actions.indexOf('parse_manifest') >= 0) {
      this.buildPrimaryActionButton('parse_manifest', '解析', true)
    }
  }

  @Builder
  private buildPrimaryActionButton(action: MediaResourceAction, label: string, primary: boolean) {
    BrowserSheetActionButton({
      label: label,
      emphasis: primary ? 'primary' : 'secondary',
      accentColor: this.accentColor,
      fillAvailableWidth: false,
      buttonWidth: 56,
      buttonHeight: 28,
      fontSize: 13,
      onAction: () => {
        this.runAction(action);
      }
    })
  }

  @Builder
  private buildMenu() {
    Menu() {
      if (this.candidate.actions.indexOf('parse_manifest') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.doc_text_fill'),
          content: '解析流媒体清单'
        })
          .onClick(() => {
            this.runAction('parse_manifest');
          })
      }
      if (this.candidate.actions.indexOf('download') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.arrow_down'),
          content: '下载视频'
        })
          .onClick(() => {
            this.runAction('download');
          })
      }
      if (this.candidate.actions.indexOf('copy') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.link'),
          content: '复制资源链接'
        })
          .onClick(() => {
            this.runAction('copy');
          })
      }
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .systemMaterial(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    ))
  }

  @Builder
  private buildMenuPreview() {
    Row({ space: 12 }) {
      this.buildThumbnail()
      Column({ space: 6 }) {
        Text(this.buildTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.buildVideoSummary())
          .fontSize(12)
          .fontColor(this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(320)
    .padding(10)
    .borderRadius(RESOURCE_VIDEO_CARD_RADIUS)
    .backgroundColor(this.cardBackgroundColor)
  }

  private buildTitle(): string {
    if (this.candidate.displayName.length > 0) {
      return this.candidate.displayName;
    }
    return describeKind(this.candidate);
  }

  private buildKindBadge(): string {
    return describeKind(this.candidate).toUpperCase();
  }

  private buildVideoSummary(): string {
    const parts: string[] = [];
    if (this.candidate.width !== undefined && this.candidate.height !== undefined &&
      this.candidate.width > 0 && this.candidate.height > 0) {
      parts.push(this.candidate.width.toString() + 'x' + this.candidate.height.toString());
    }
    if (this.candidate.durationMs !== undefined && this.candidate.durationMs > 0) {
      parts.push(formatDuration(this.candidate.durationMs));
    }
    if (this.candidate.estimatedTotalBytes !== undefined && this.candidate.estimatedTotalBytes > 0) {
      parts.push('约 ' + formatEstimatedBytes(this.candidate.estimatedTotalBytes));
    } else if (this.candidate.kind !== 'hls' &&
      this.candidate.totalBytes !== undefined && this.candidate.totalBytes > 0) {
      parts.push(formatBytes(this.candidate.totalBytes));
    }
    const exceptionalStatus = this.buildExceptionalStatus();
    if (exceptionalStatus.length > 0) {
      parts.push(exceptionalStatus);
    }
    if (parts.length > 0) {
      return parts.join(' · ');
    }
    return this.candidate.sourceHost.length > 0 ? this.candidate.sourceHost : shortenUrl(this.candidate.url);
  }

  private buildExceptionalStatus(): string {
    switch (this.candidate.status) {
      case 'protected':
      case 'expired':
      case 'unsupported':
      case 'failed':
        return describeStatus(this.candidate);
      default:
        return '';
    }
  }

  private openMenu(): void {
    if (this.candidate.actions.length <= 0) {
      return;
    }
    this.menuVisible = true;
  }

  private runAction(action: MediaResourceAction): void {
    this.menuVisible = false;
    this.onAction(this.candidate.id, action);
  }
}

@Component
struct BrowserResourceImageGridCard {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop candidate: MediaResourceListItem = createEmptyMediaResourceListItem();
  @Prop cardBackgroundColor: ResourceColor = '#EEF2F6';
  @State menuVisible: boolean = false;
  @State previewVisible: boolean = false;
  onImageLoadFailed: (candidateId: string) => void = (_candidateId: string) => {};
  onAction: (candidateId: string, action: MediaResourceAction) => void =
    (_candidateId: string, _action: MediaResourceAction) => {};

  build() {
    Image(this.candidate.url)
      .width('100%')
      .aspectRatio(1)
      .objectFit(ImageFit.Cover)
      .backgroundColor(this.cardBackgroundColor)
      .borderRadius(RESOURCE_IMAGE_GRID_CARD_RADIUS)
      .clip(true)
      .draggable(false)
      .onError(() => {
        this.markLoadFailed();
      })
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
            .onAction(() => {
              this.openMenu();
            }),
          TapGesture()
            .onAction(() => {
              this.openPreview();
            })
        )
      )
      .bindContextMenu(this.menuVisible, this.buildMenu(), {
        preview: this.buildMenuPreview(),
        previewBorderRadius: RESOURCE_IMAGE_GRID_CARD_RADIUS,
        onDisappear: () => {
          this.menuVisible = false;
        }
      })
      .bindContentCover($$this.previewVisible, this.buildPreview(), {
        modalTransition: ModalTransition.DEFAULT
      })
  }

  @Builder
  private buildMenu() {
    Menu() {
      if (this.candidate.actions.indexOf('copy') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.link'),
          content: '复制图片链接'
        })
          .onClick(() => {
            this.runAction('copy');
          })
      }
      if (this.candidate.actions.indexOf('download') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.arrow_down'),
          content: '下载图片'
        })
          .onClick(() => {
            this.runAction('download');
          })
      }
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .systemMaterial(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    ))
  }

  @Builder
  private buildMenuPreview() {
    Image(this.candidate.url)
      .width(180)
      .height(180)
      .objectFit(ImageFit.Cover)
      .backgroundColor(this.cardBackgroundColor)
      .borderRadius(RESOURCE_IMAGE_GRID_CARD_RADIUS)
      .clip(true)
      .draggable(false)
      .onError(() => {
        this.markLoadFailed();
      })
  }

  @Builder
  private buildPreview() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.candidate.url)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .backgroundColor(RESOURCE_IMAGE_PREVIEW_BACKGROUND_COLOR)
        .draggable(false)
        .onError(() => {
          this.markLoadFailed();
        })
        .onClick(() => {
          this.closePreview();
        })

      Stack({ alignContent: Alignment.Center }) {
        BrowserSheetIconButton({
          icon: $r('sys.symbol.xmark'),
          iconSize: 20,
          iconColor: RESOURCE_IMAGE_PREVIEW_FOREGROUND_COLOR,
          buttonSize: RESOURCE_IMAGE_PREVIEW_CLOSE_SIZE,
          accessibilityLabel: '关闭图片预览',
          onAction: () => {
            this.closePreview();
          }
        })
      }
      .width(RESOURCE_IMAGE_PREVIEW_CLOSE_SIZE)
      .height(RESOURCE_IMAGE_PREVIEW_CLOSE_SIZE)
      .margin({
        left: RESOURCE_IMAGE_PREVIEW_SIDE_PADDING,
        top: RESOURCE_IMAGE_PREVIEW_TOP_PADDING
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(RESOURCE_IMAGE_PREVIEW_BACKGROUND_COLOR)
  }

  private openMenu(): void {
    if (this.candidate.actions.length <= 0) {
      return;
    }
    this.menuVisible = true;
  }

  private openPreview(): void {
    if (this.candidate.url.trim().length <= 0) {
      return;
    }
    this.previewVisible = true;
  }

  private closePreview(): void {
    this.previewVisible = false;
  }

  private markLoadFailed(): void {
    this.menuVisible = false;
    this.previewVisible = false;
    this.onImageLoadFailed(this.candidate.id);
  }

  private runAction(action: MediaResourceAction): void {
    this.menuVisible = false;
    this.onAction(this.candidate.id, action);
  }
}

function createEmptyMediaResourceListItem(): MediaResourceListItem {
  return {
    id: '',
    tabId: '',
    pageTitle: '',
    url: '',
    source: 'dom',
    frameType: 'dom_document',
    family: 'image',
    kind: 'image',
    status: 'detected',
    displayName: '',
    sourceHost: '',
    actions: []
  };
}

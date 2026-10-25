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
import { DESKTOP_DIALOG_PADDING_VP } from '../../../core/browser/BrowserDialogPresentationTokens';
import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { AppEmptyState } from '../common/AppEmptyState';
import { FloatingSelectionToolbar } from '../common/FloatingSelectionToolbar';
import { SelectedCheckIndicator } from '../common/SelectedCheckIndicator';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import {
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  resolveBrowserSheetHeaderBlurRadius,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
  BrowserSheetIconButton,
  browserSheetHeaderBlurModifier
} from './BrowserModalBottomSheet';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
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
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';

import {
  MediaResourceSurfaceTab,
  MediaResourceBatchAction,
  belongsToMediaResourceTab,
  isSelectableMediaResource,
  reconcileMediaResourceSelection,
  selectedMediaResourcesForAction
} from '../../../features/mediaDiscovery/MediaResourceSelection';

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
const BROWSER_RESOURCE_SHEET_CONTENT_TOP_PADDING: number = 136;
const RESOURCE_TAB_BAR_HEIGHT: number = 36;
const RESOURCE_TAB_BAR_HORIZONTAL_PADDING: number = 16;

function describeKind(candidate: MediaResourceListItem): string {
  if (candidate.acquisition?.mode === 'paired_adaptive') {
    return resolveAppResourceText($r('app.string.media_resource_kind_adaptive_av'));
  }
  if (candidate.acquisition?.mode === 'progressive') {
    return candidate.acquisition.primaryTrack.role === 'audio'
      ? resolveAppResourceText($r('app.string.media_resource_kind_audio'))
      : resolveAppResourceText($r('app.string.media_resource_kind_progressive_video'));
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
    case 'audio': return resolveAppResourceText($r('app.string.media_resource_kind_audio'));
    case 'image': return resolveAppResourceText($r('app.string.media_resource_kind_image'));
    case 'document': return resolveAppResourceText($r('app.string.media_resource_kind_document'));
    case 'archive': return resolveAppResourceText($r('app.string.media_resource_kind_archive'));
    case 'package': return resolveAppResourceText($r('app.string.media_resource_kind_package'));
    case 'segment': return resolveAppResourceText($r('app.string.media_resource_kind_segment'));
    default: return resolveAppResourceText($r('app.string.media_resource_kind_unknown'));
  }
}

function describeStatus(candidate: MediaResourceListItem): string {
  const downloadable = resolveAppResourceText($r('app.string.media_resource_status_downloadable'));
  switch (candidate.status) {
    case 'playing_native': return resolveAppResourceText($r('app.string.media_resource_status_taking_over'));
    case 'playable': return resolveAppResourceText($r('app.string.media_resource_status_verified_video'));
    case 'downloadable': return downloadable;
    case 'needs_processing':
      return candidate.kind === 'dash'
        ? resolveAppResourceText($r('app.string.media_resource_status_parsing_pending'))
        : candidate.actions.indexOf('download') >= 0
          ? downloadable
          : resolveAppResourceText($r('app.string.media_resource_status_needs_processing'));
    case 'protected': return resolveAppResourceText($r('app.string.media_resource_status_protected'));
    case 'expired': return resolveAppResourceText($r('app.string.media_resource_status_expired'));
    case 'unsupported': return describeFailureReason(candidate.failureReason);
    case 'failed':
      return resolveAppResourceText($r(
        'app.string.media_resource_status_failed',
        candidate.failureReason ?? resolveAppResourceText($r('app.string.media_resource_unknown_reason'))
      ));
    default: return candidate.actions.indexOf('download') >= 0
      ? downloadable
      : resolveAppResourceText($r('app.string.media_resource_status_detected'));
  }
}

function describeFailureReason(reason: string | undefined): string {
  if (reason === 'hls_requires_web_mse_runtime') {
    return resolveAppResourceText($r('app.string.media_resource_failure_needs_mse'));
  }
  if (reason === 'hls_child_headers_not_inherited') {
    return resolveAppResourceText($r('app.string.media_resource_failure_hls_auth'));
  }
  return resolveAppResourceText($r('app.string.media_resource_failure_unsupported'));
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
    case 'main_frame': return resolveAppResourceText($r('app.string.media_resource_frame_main'));
    case 'sub_frame': return resolveAppResourceText($r('app.string.media_resource_frame_sub'));
    case 'dom_frame': return resolveAppResourceText($r('app.string.media_resource_frame_iframe'));
    case 'dom_document': return candidate.source === 'dom'
      ? resolveAppResourceText($r('app.string.media_resource_frame_page_scan'))
      : '';
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
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop
  @Watch('onCandidatesChanged')
  candidates: MediaResourceListItem[] = [];
  @Prop
  @Watch('syncActiveTab')
  counts: MediaResourceTabCounts = emptyMediaResourceTabCounts();
  @Prop manifestParsingCandidateId: string = '';
  @Prop manifestParseResult: MediaManifestParseResult | undefined = undefined;
  @Prop scanning: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @State activeTab: MediaResourceSurfaceTab = 'video';
  @State selectionMode: boolean = false;
  @State selectedCandidateIds: string[] = [];
  @State contentWidth: number = BROWSER_RESOURCE_SHEET_MAX_WIDTH;
  @State failedImageCandidateIds: string[] = [];
  private resourceTabSwiperController: SwiperController = new SwiperController();
  onClose: () => void = () => {};
  @State private sheetHeaderBlurRadius: number = 0;
  @State private sheetScrollOffset: number = 0;
  @State private tabBarWidth: number = 1;
  onAction: (candidateId: string, action: MediaResourceAction) => void = (_candidateId: string, _action: MediaResourceAction) => {};

  onBatchAction: (candidateIds: string[], action: MediaResourceBatchAction) => void =
    (_candidateIds: string[], _action: MediaResourceBatchAction) => {};

  aboutToAppear(): void {
    this.pruneFailedImageCandidates();
    this.syncActiveTab();
  }

  private sheetBlurScroller: Scroller = new Scroller();

  private noteSheetScrollOffset(offset: number): void {
    if (!Number.isFinite(offset)) {
      return;
    }
    const next = Math.max(0, offset);
    if (next === this.sheetScrollOffset) {
      return;
    }
    this.sheetScrollOffset = next;
    this.sheetHeaderBlurRadius = resolveBrowserSheetHeaderBlurRadius(next);
  }

  private resetSheetHeaderBlur(): void {
    this.sheetScrollOffset = 0;
    this.sheetHeaderBlurRadius = 0;
  }

  build() {
    if (this.layoutMode === 'large_screen') {
      this.buildLargeScreenDialog()
    } else {
      this.buildPhoneSheet()
    }
  }

  @Builder
  private buildPhoneSheet() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: 'bottom_sheet',
      maxWidth: BROWSER_RESOURCE_SHEET_MAX_WIDTH,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      Stack() {
        BrowserImmersiveSheetLayout({
          closeVisible: true,
          closeAccessibilityLabel: this.selectionMode ? $r('app.string.ui_done') : $r('app.string.media_resource_close'),
          onClose: (): void => {
            this.handleClose();
          },
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
        this.rememberContentWidth(newArea);
      })
    }
  }

  @Builder
  private buildLargeScreenDialog() {
    Column() {
      BrowserLargeScreenModalHeader({
        title: this.buildTitle(),
        dialogMode: true,
        onClose: (): void => {
          this.handleClose();
        }
      })

      Column({ space: 16 }) {
        this.buildLargeScreenTabs()
        this.buildList()
      }
      .width('100%')
      .layoutWeight(1)
      .padding({
        left: DESKTOP_DIALOG_PADDING_VP,
        right: DESKTOP_DIALOG_PADDING_VP,
        top: 4,
        bottom: DESKTOP_DIALOG_PADDING_VP
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.rememberContentWidth(newArea);
    })
  }

  @Builder
  private buildPhoneHeader() {
    Column({ space: 14 }) {
      BrowserFeatureSheetHeader({
        title: this.buildTitle(),
        titleColor: this.storedPrimaryTextColor
      })

      this.buildTabs()
    }
    .width('100%')
  }

  @Builder
  private buildTabs() {
    Column() {
      this.buildTabBar(true)
    }
    .width('100%')
    .padding({
      left: RESOURCE_TAB_BAR_HORIZONTAL_PADDING,
      right: RESOURCE_TAB_BAR_HORIZONTAL_PADDING
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // The immersive plate needs the bar's concrete width. A zero measurement collapses it.
      this.tabBarWidth = Math.max(1, Number(newArea.width) - RESOURCE_TAB_BAR_HORIZONTAL_PADDING * 2);
    })
  }

  @Builder
  private buildLargeScreenTabs() {
    this.buildTabBar(false)
  }

  @Builder
  private buildTabBar(immersive: boolean) {
    FloatingGlassMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: RESOURCE_TAB_BAR_HEIGHT,
      surfaceRadius: RESOURCE_TAB_BAR_HEIGHT / 2,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      fallbackColor: this.storedControlBackgroundColor,
      hostMaterialActive: immersive && this.shouldUseHdsMaterial(),
      backgroundBlurEnabled: false
    }) {
      if (immersive && this.shouldUseHdsMaterial()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.tabBarWidth,
          plateHeight: RESOURCE_TAB_BAR_HEIGHT,
          plateRadius: RESOURCE_TAB_BAR_HEIGHT / 2
        })
      }
      SegmentedTabs({
        options: this.buildTabOptions(),
        selectedId: this.activeTab,
        barHeight: RESOURCE_TAB_BAR_HEIGHT,
        itemHeight: RESOURCE_TAB_BAR_HEIGHT - 6,
        fontSize: 14,
        barPadding: 3,
        fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
        barMaterialEnabled: false,
        onSelect: (id: string) => {
          this.changeActiveTab(id as MediaResourceSurfaceTab);
          this.syncSwiperToActiveTab(true);
        }
      })
        .width('100%')
        .height(RESOURCE_TAB_BAR_HEIGHT)
    }
  }

  private shouldUseHdsMaterial(): boolean {
    return isHdsMaterialAvailable();
  }

  @Builder
  private buildList() {
    Stack({ alignContent: Alignment.Bottom }) {
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

      if (this.selectionMode && this.activeTab === 'other') {
        this.buildSelectionToolbar()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSelectionToolbar() {
    FloatingSelectionToolbar({
      actions: [
        {
          airaIconId: 'browser.toolbar.selectAll',
          title: this.allOtherResourcesSelected() ? $r('app.string.media_resource_deselect_all') : $r('app.string.ui_select_all'),
          action: () => { this.toggleSelectAll(); }
        },
        {
          airaIconId: 'browser.toolbar.copyLink',
          title: $r('app.string.media_resource_batch_copy'),
          enabled: this.selectedForAction('copy').length > 0,
          action: () => { this.runBatchAction('copy'); }
        },
        {
          airaIconId: 'browser.shortcut.downloads',
          title: $r('app.string.media_resource_batch_download', this.selectedForAction('download').length),
          enabled: this.selectedForAction('download').length > 0,
          action: () => { this.runBatchAction('download'); }
        }
      ]
    })
      .margin({ bottom: 16 })
  }

  @Builder
  private buildResourcePage(tab: MediaResourceSurfaceTab) {
    Scroll(this.sheetBlurScroller) {
      Column() {
        if (this.filteredCandidatesForTab(tab).length === 0 && this.scanning) {
          AppEmptyState({
            airaIconId: 'browser.shortcut.pageResources',
            title: $r('app.string.media_resource_scanning_title'),
            message: $r('app.string.media_resource_scanning_message'),
            topPadding: 28,
            bottomPadding: 28,
            fillHeight: true
          })
        } else if (this.filteredCandidatesForTab(tab).length === 0) {
          AppEmptyState({
            airaIconId: 'browser.shortcut.pageResources',
            title: this.buildEmptyTitle(tab),
            message: $r('app.string.media_resource_empty_message'),
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
        bottom: this.selectionMode && tab === 'other' ? 96 :
          this.layoutMode === 'phone' ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING : 0
      })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
    .clip(this.layoutMode !== 'phone')
    .attributeModifier(browserSheetHeaderBlurModifier(this.layoutMode === 'phone' ? this.sheetHeaderBlurRadius : 0))
    .onAppear(() => {
      this.resetSheetHeaderBlur();
    })
    .onDidScroll((_xOffset: number, yOffset: number) => {
      this.noteSheetScrollOffset(this.sheetBlurScroller.currentOffset().yOffset);
    })
  }

  @Builder
  private buildOtherResourceList() {
    Column({ space: 12 }) {
      Text($r('app.string.media_resource_selection_hint'))
        .width('100%')
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
      if (this.imageCandidates().length > 0) {
        Text($r('app.string.media_resource_images_count', this.imageCandidates().length))
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
                Text($r('app.string.media_resource_parsing_manifest'))
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
                this.manifestParseResult.errorMessage : $r('app.string.media_resource_manifest_parse_failed'))
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
        Text(summary.encrypted
          ? $r('app.string.media_resource_manifest_encrypted')
          : $r('app.string.media_resource_manifest_unencrypted'))
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
        Text($r('app.string.media_resource_manifest_keys', summary.keyUrls.length, shortenUrl(summary.keyUrls[0])))
          .width('100%')
          .fontSize(11)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (summary.sampleSegments.length > 0) {
        Text($r('app.string.media_resource_sample_segment', shortenUrl(summary.sampleSegments[0])))
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
          cardBorderColor: this.layoutMode === 'large_screen' ? this.storedDividerColor : Color.Transparent,
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
      selectionMode: this.selectionMode,
      selected: this.isSelected(candidate.id),
      selectable: isSelectableMediaResource(candidate),
      accentColor: this.storedAccentColor,
      onSelect: (candidateId: string) => {
        this.toggleSelection(candidateId);
      },
      onBeginSelection: (candidateId: string) => {
        this.beginSelection(candidateId);
      },
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
      if (this.selectionMode) {
        BrowserResourceSelectionIndicator({
          selected: this.isSelected(candidate.id),
          accentColor: this.storedAccentColor
        })
          .opacity(isSelectableMediaResource(candidate) ? 1 : 0.35)
      }
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

          if (!this.selectionMode) {
            this.buildActionButtons(candidate)
          }
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
    .backgroundColor(this.isSelected(candidate.id) ? this.storedPressedBackgroundColor : Color.Transparent)
    .accessibilityDescription(this.selectionMode ? resolveAppResourceText(this.isSelected(candidate.id)
      ? $r('app.string.media_resource_selected') : $r('app.string.media_resource_not_selected')) : '')
    .gesture(
      GestureGroup(
        GestureMode.Exclusive,
        LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
          .onAction(() => {
            this.beginSelection(candidate.id);
          }),
        TapGesture()
          .onAction(() => {
            if (this.selectionMode) {
              this.toggleSelection(candidate.id);
            }
          })
      )
    )
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
        this.buildActionButton(candidate, 'parse_manifest', $r('app.string.media_resource_action_parse'), true)
      }
      if (candidate.actions.indexOf('download') >= 0) {
        this.buildActionButton(candidate, 'download', $r('app.string.media_resource_action_download'), false)
      }
      if (candidate.actions.indexOf('copy') >= 0) {
        this.buildActionButton(candidate, 'copy', $r('app.string.media_resource_action_copy'), false)
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildActionButton(candidate: MediaResourceListItem, action: MediaResourceAction, label: ResourceStr, primary: boolean) {
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
    return tab === 'video'
      ? resolveAppResourceText($r('app.string.media_resource_tab_video'))
      : resolveAppResourceText($r('app.string.media_resource_tab_other'));
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
      if (belongsToMediaResourceTab(this.candidates[i], tab) && !this.isHiddenFailedImageCandidate(this.candidates[i])) {
        results.push(this.candidates[i]);
      }
    }
    return results;
  }

  private onCandidatesChanged(): void {
    this.pruneFailedImageCandidates();
    this.reconcileSelection();
  }

  private reconcileSelection(): void {
    this.selectedCandidateIds = reconcileMediaResourceSelection(
      this.selectedCandidateIds, this.filteredCandidatesForTab('other')
    );
    if (this.selectionMode && this.filteredCandidatesForTab('other').length === 0) {
      this.exitSelection();
    }
  }

  private beginSelection(candidateId: string): void {
    const candidate = this.filteredCandidatesForTab('other').find((item: MediaResourceListItem) => item.id === candidateId);
    if (candidate === undefined || !isSelectableMediaResource(candidate)) {
      return;
    }
    this.selectionMode = true;
    if (!this.isSelected(candidateId)) {
      this.selectedCandidateIds = this.selectedCandidateIds.concat([candidateId]);
    }
  }

  private toggleSelection(candidateId: string): void {
    if (!this.isSelected(candidateId)) {
      this.beginSelection(candidateId);
      return;
    }
    this.selectedCandidateIds = this.selectedCandidateIds.filter((id: string) => id !== candidateId);
  }

  private isSelected(candidateId: string): boolean {
    return this.selectedCandidateIds.indexOf(candidateId) >= 0;
  }

  private allOtherResourcesSelected(): boolean {
    const selectable = this.filteredCandidatesForTab('other').filter(isSelectableMediaResource);
    return selectable.length > 0 && selectable.every((item: MediaResourceListItem) => this.isSelected(item.id));
  }

  private toggleSelectAll(): void {
    this.selectedCandidateIds = this.allOtherResourcesSelected() ? [] :
      this.filteredCandidatesForTab('other').filter(isSelectableMediaResource).map((item: MediaResourceListItem) => item.id);
  }

  private selectedForAction(action: MediaResourceBatchAction): MediaResourceListItem[] {
    return selectedMediaResourcesForAction(this.selectedCandidateIds, this.filteredCandidatesForTab('other'), action);
  }

  private runBatchAction(action: MediaResourceBatchAction): void {
    const ids = this.selectedForAction(action).map((item: MediaResourceListItem) => item.id);
    if (ids.length > 0) {
      this.onBatchAction(ids, action);
    }
  }

  private exitSelection(): void {
    this.selectionMode = false;
    this.selectedCandidateIds = [];
  }

  private changeActiveTab(tab: MediaResourceSurfaceTab): void {
    if (tab !== this.activeTab) {
      this.exitSelection();
      this.activeTab = tab;
    }
  }

  private markImageLoadFailed(candidateId: string): void {
    const normalizedId = candidateId.trim();
    if (normalizedId.length <= 0 || this.failedImageCandidateIds.indexOf(normalizedId) >= 0) {
      return;
    }
    const nextFailedIds = this.failedImageCandidateIds.slice();
    nextFailedIds.push(normalizedId);
    this.failedImageCandidateIds = nextFailedIds;
    this.reconcileSelection();
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
      if (belongsToMediaResourceTab(candidate, 'other') && candidate.family !== 'image' &&
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

  private rememberContentWidth(area: Area): void {
    const nextWidth = this.parseAreaDimension(area.width);
    if (nextWidth > 0 && Math.abs(nextWidth - this.contentWidth) >= 1) {
      this.contentWidth = nextWidth;
    }
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private syncActiveTab(): void {
    if (this.selectionMode) {
      return;
    }
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

  private handleClose(): void {
    if (this.selectionMode) {
      this.exitSelection();
    } else {
      this.onClose();
    }
  }

  private buildTitle(): ResourceStr {
    return this.selectionMode ? $r('app.string.media_resource_selected_count', this.selectedCandidateIds.length) :
      $r('app.string.media_resource_title');
  }

  private buildEmptyTitle(tab: MediaResourceSurfaceTab): ResourceStr {
    return tab === 'video'
      ? $r('app.string.media_resource_empty_video')
      : $r('app.string.media_resource_empty_other');
  }

  private buildManifestTitle(summary: MediaManifestSummary): ResourceStr {
    if (summary.kind === 'hls') {
      return summary.role === 'master'
        ? $r('app.string.media_resource_manifest_hls_master')
        : $r('app.string.media_resource_manifest_hls_media');
    }
    if (summary.kind === 'dash') {
      return $r('app.string.media_resource_manifest_dash');
    }
    return $r('app.string.media_resource_manifest_stream');
  }

  private buildManifestMetrics(summary: MediaManifestSummary): string {
    const parts: string[] = [];
    if (summary.sourceHost.length > 0) {
      parts.push(summary.sourceHost);
    }
    if (summary.variantCount > 0) {
      parts.push(resolveAppResourceText($r('app.string.media_resource_manifest_quality_count', summary.variantCount)));
    }
    if (summary.segmentCount > 0) {
      parts.push(resolveAppResourceText($r('app.string.media_resource_manifest_segment_count', summary.segmentCount)));
    }
    if (summary.durationSeconds > 0) {
      parts.push(formatDuration(summary.durationSeconds * 1000));
    }
    if (summary.keyCount > 0) {
      parts.push(resolveAppResourceText($r('app.string.media_resource_manifest_key_count', summary.keyCount)));
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
    return resolveAppResourceText($r('app.string.media_resource_variant_quality', variant.index + 1));
  }

  private buildVariantMeta(variant: MediaManifestVariant): string {
    const parts: string[] = [];
    if (variant.bandwidth > 0) {
      parts.push(Math.round(variant.bandwidth / 1000).toString() + ' kbps');
    }
    if (variant.segmentCount > 0) {
      parts.push(resolveAppResourceText($r('app.string.media_resource_variant_segments', variant.segmentCount)));
    }
    if (variant.targetDuration > 0) {
      parts.push(variant.targetDuration.toString() + 's');
    }
    if (variant.encrypted) {
      parts.push(resolveAppResourceText($r('app.string.media_resource_manifest_encrypted')));
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
    this.changeActiveTab(nextTab);
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
  @Prop cardBorderColor: ResourceColor = Color.Transparent;
  @Prop thumbnailBackgroundColor: ResourceColor = '#EEF2F6';
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @State menuVisible: boolean = false;
  onAction: (candidateId: string, action: MediaResourceAction) => void =
    (_candidateId: string, _action: MediaResourceAction) => {};

  build() {
    Column() {
      this.buildVideoCard()
    }
    .width('100%')
    .bindContextMenu(this.buildMenu(), ResponseType.RightClick)
  }

  @Builder
  private buildVideoCard() {
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
    .border({ width: 0.5, color: this.cardBorderColor })
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
      this.buildPrimaryActionButton('download', $r('app.string.media_resource_action_download'), true)
    } else if (this.candidate.actions.indexOf('parse_manifest') >= 0) {
      this.buildPrimaryActionButton('parse_manifest', $r('app.string.media_resource_action_parse'), true)
    }
  }

  @Builder
  private buildPrimaryActionButton(action: MediaResourceAction, label: ResourceStr, primary: boolean) {
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
          content: $r('app.string.media_resource_menu_parse_manifest')
        })
          .onClick(() => {
            this.runAction('parse_manifest');
          })
      }
      if (this.candidate.actions.indexOf('download') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.arrow_down'),
          content: $r('app.string.media_resource_menu_download_video')
        })
          .onClick(() => {
            this.runAction('download');
          })
      }
      if (this.candidate.actions.indexOf('copy') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.link'),
          content: $r('app.string.media_resource_menu_copy_link')
        })
          .onClick(() => {
            this.runAction('copy');
          })
      }
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
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
      parts.push(resolveAppResourceText($r('app.string.media_resource_estimated_size', formatEstimatedBytes(this.candidate.estimatedTotalBytes))));
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
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @Prop selectable: boolean = false;
  @Prop accentColor: ResourceColor = '#0A59F7';
  @State previewVisible: boolean = false;
  onSelect: (candidateId: string) => void = (_candidateId: string) => {};
  onBeginSelection: (candidateId: string) => void = (_candidateId: string) => {};
  onImageLoadFailed: (candidateId: string) => void = (_candidateId: string) => {};
  onAction: (candidateId: string, action: MediaResourceAction) => void =
    (_candidateId: string, _action: MediaResourceAction) => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.buildImageCard()
      if (this.selectionMode) {
        BrowserResourceSelectionIndicator({ selected: this.selected, accentColor: this.accentColor })
          .margin(8)
          .opacity(this.selectable ? 1 : 0.35)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .border({ width: this.selected ? 2 : 0, color: this.accentColor, radius: RESOURCE_IMAGE_GRID_CARD_RADIUS })
    .accessibilityText(this.candidate.displayName)
    .accessibilityDescription(this.selectionMode ? resolveAppResourceText(this.selected
      ? $r('app.string.media_resource_selected') : $r('app.string.media_resource_not_selected')) : '')
    .bindContextMenu(this.buildMenu(), ResponseType.RightClick)
  }

  @Builder
  private buildImageCard() {
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
              this.onBeginSelection(this.candidate.id);
            }),
          TapGesture()
            .onAction(() => {
              if (this.selectionMode) {
                this.onSelect(this.candidate.id);
              } else {
                this.openPreview();
              }
            })
        )
      )
      .bindContentCover($$this.previewVisible, this.buildPreview(), {
        modalTransition: ModalTransition.DEFAULT
      })
  }

  @Builder
  private buildMenu() {
    Menu() {
      if (this.selectable) {
        MenuItem({
          startIcon: $r('sys.symbol.checkmark_circle'),
          content: $r('app.string.media_resource_select')
        })
          .onClick(() => {
            this.onBeginSelection(this.candidate.id);
          })
      }
      if (this.candidate.actions.indexOf('copy') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.link'),
          content: $r('app.string.media_resource_menu_copy_image_link')
        })
          .onClick(() => {
            this.runAction('copy');
          })
      }
      if (this.candidate.actions.indexOf('download') >= 0) {
        MenuItem({
          startIcon: $r('sys.symbol.arrow_down'),
          content: $r('app.string.media_resource_menu_download_image')
        })
          .onClick(() => {
            this.runAction('download');
          })
      }
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
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
          accessibilityLabel: $r('app.string.media_resource_close_image_preview'),
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
    this.previewVisible = false;
    this.onImageLoadFailed(this.candidate.id);
  }

  private runAction(action: MediaResourceAction): void {
    this.onAction(this.candidate.id, action);
  }
}

@Component
struct BrowserResourceSelectionIndicator {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @Prop selected: boolean = false;
  @Prop accentColor: ResourceColor = '#0A59F7';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.selected) {
        SelectedCheckIndicator({ indicatorSize: 24, indicatorColor: this.accentColor })
      } else {
        Circle()
          .width(24)
          .height(24)
          .fill(this.storedSurfaceBackgroundColor)
          .stroke(this.storedSecondaryTextColor)
          .strokeWidth(1.5)
      }
    }
    .width(24)
    .height(24)
    .hitTestBehavior(HitTestMode.None)
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

import {
  OfflinePageOpenStatus,
  OfflinePageSaveStatus,
  OfflinePageViewerInfoRow,
  OfflinePageViewerState
} from '../../common/models/OfflinePageModels';
import { BrowserResolvedThemeMode, ReaderModeTheme } from '../../common/models/BrowserModels';
import {
  BrowserBottomChromeGestureSource,
  BrowserBottomChromePresentation,
  BrowserBottomChromePresentationFacts,
  BrowserBottomChromePresentationViewModel
} from '../browser/BrowserBottomChromePresentationViewModel';
import { BrowserBottomAddressPanelHeaderAction } from '../browser/BrowserBottomAddressPanelViewModel';
import { BrowserBottomChromeScrollPresentation } from '../browser/BrowserBottomChromeScrollCoordinator';
import { BrowserBottomPanelResponsiveState } from '../browser/BrowserBottomPanelResponsiveViewModel';
import { HomeSearchPanelDetent } from '../browser/HomeSearchPanelDetentViewModel';

export type OfflinePageViewerBackAction =
  'dismiss_reader_image_preview' |
  'dismiss_reader_panel' |
  'close_reader_mode' |
  'collapse_offline_bottom_panel' |
  'route_back';
export type OfflinePageScrollTouchPhase = 'down' | 'move' | 'up' | 'cancel';

const OFFLINE_PAGE_SCROLL_GESTURE_GRACE_MS: number = 350;

export interface OfflinePageViewerBackState {
  readerModeVisible: boolean;
  readerImagePreviewVisible: boolean;
  readerPanelVisible: boolean;
  offlineBottomPanelExpanded: boolean;
}

export interface OfflineBottomChromeGestureState {
  returnHomeDrag: boolean;
  progress: number;
}

export interface OfflineBottomChromePresentationInput {
  currentDetent: HomeSearchPanelDetent;
  scrollPresentation: BrowserBottomChromeScrollPresentation;
  returnHomeDrag: boolean;
  returnHomeProgress: number;
  responsiveState: BrowserBottomPanelResponsiveState;
  panelExpansionEnabled: boolean;
  addressInput: string;
  addressDisplayText: string;
  placeholder: string;
  leadingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
  trailingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
}

export interface OfflineBottomChromeGestureReleasePlan {
  interceptPanelRelease: boolean;
  shouldReturnHome: boolean;
}

export class OfflinePageViewerViewModel {
  private bottomChromePresentationViewModel: BrowserBottomChromePresentationViewModel =
    new BrowserBottomChromePresentationViewModel();
  private scrollGestureActive: boolean = false;
  private scrollMoveObserved: boolean = false;
  private recentScrollGestureUntilAt: number = 0;

  createInitialBackState(): OfflinePageViewerBackState {
    return {
      readerModeVisible: false,
      readerImagePreviewVisible: false,
      readerPanelVisible: false,
      offlineBottomPanelExpanded: false
    };
  }

  resolveBackAction(state: OfflinePageViewerBackState): OfflinePageViewerBackAction {
    if (state.readerModeVisible) {
      if (state.readerImagePreviewVisible) {
        return 'dismiss_reader_image_preview';
      }
      if (state.readerPanelVisible) {
        return 'dismiss_reader_panel';
      }
      return 'close_reader_mode';
    }
    if (state.offlineBottomPanelExpanded) {
      return 'collapse_offline_bottom_panel';
    }
    return 'route_back';
  }

  buildBottomChromePresentation(
    input: OfflineBottomChromePresentationInput
  ): BrowserBottomChromePresentation {
    const facts: BrowserBottomChromePresentationFacts = {
      scene: 'web',
      addressFocused: false,
      addressEditable: false,
      currentDetent: input.currentDetent,
      scrollPresentation: input.scrollPresentation,
      returnHomeDrag: input.returnHomeDrag,
      returnHomeProgress: input.returnHomeProgress,
      panelWidth: input.responsiveState.panelWidth,
      floatingHeaderHorizontalPadding: input.responsiveState.floatingHeaderHorizontalPadding,
      restingChromeOuterSize: input.responsiveState.restingChromeOuterSize,
      restingChromeOuterGap: input.responsiveState.restingChromeOuterGap,
      panelExpansionEnabled: input.panelExpansionEnabled,
      addressInput: input.addressInput,
      addressDisplayText: input.addressDisplayText,
      placeholder: input.placeholder,
      leadingHeaderActions: input.leadingHeaderActions,
      trailingHeaderActions: input.trailingHeaderActions
    };
    return this.bottomChromePresentationViewModel.buildPresentation(facts);
  }

  beginBottomChromeGesture(source: BrowserBottomChromeGestureSource): OfflineBottomChromeGestureState {
    return {
      returnHomeDrag: this.bottomChromePresentationViewModel.isOuterGestureSource(source),
      progress: 0
    };
  }

  updateBottomChromeGesture(
    source: BrowserBottomChromeGestureSource,
    offsetY: number
  ): OfflineBottomChromeGestureState {
    const gesture = this.bottomChromePresentationViewModel.resolveReturnHomeGesture({
      source,
      offsetY,
      eligible: true
    });
    return {
      returnHomeDrag: this.bottomChromePresentationViewModel.isOuterGestureSource(source),
      progress: gesture.progress
    };
  }

  resolveBottomChromeGestureRelease(
    source: BrowserBottomChromeGestureSource,
    offsetY: number
  ): OfflineBottomChromeGestureReleasePlan {
    const outerSource = this.bottomChromePresentationViewModel.isOuterGestureSource(source);
    const gesture = this.bottomChromePresentationViewModel.resolveReturnHomeGesture({
      source,
      offsetY,
      eligible: outerSource
    });
    return {
      interceptPanelRelease: outerSource,
      shouldReturnHome: gesture.armed
    };
  }

  resolveBottomChromeMenuDetent(currentDetent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    return currentDetent === 'middle' ? 'low' : 'middle';
  }

  recordScrollTouchPhase(phase: OfflinePageScrollTouchPhase, now: number = Date.now()): void {
    const normalizedNow = Math.max(0, Math.floor(now));
    if (phase === 'down') {
      this.scrollGestureActive = false;
      this.scrollMoveObserved = false;
      this.recentScrollGestureUntilAt = 0;
      return;
    }
    if (phase === 'move') {
      this.scrollGestureActive = true;
      this.scrollMoveObserved = true;
      this.recentScrollGestureUntilAt = normalizedNow + OFFLINE_PAGE_SCROLL_GESTURE_GRACE_MS;
      return;
    }
    this.scrollGestureActive = false;
    if (phase === 'up' && this.scrollMoveObserved) {
      this.recentScrollGestureUntilAt = normalizedNow + OFFLINE_PAGE_SCROLL_GESTURE_GRACE_MS;
    } else {
      this.recentScrollGestureUntilAt = 0;
    }
    this.scrollMoveObserved = false;
  }

  isScrollPresentationChangeAllowed(now: number = Date.now()): boolean {
    const normalizedNow = Math.max(0, Math.floor(now));
    return this.scrollGestureActive || normalizedNow <= this.recentScrollGestureUntilAt;
  }

  resetScrollInteraction(): void {
    this.scrollGestureActive = false;
    this.scrollMoveObserved = false;
    this.recentScrollGestureUntilAt = 0;
  }

  resolveEffectiveReaderTheme(
    readerTheme: ReaderModeTheme,
    systemTheme: BrowserResolvedThemeMode
  ): ReaderModeTheme {
    return readerTheme === 'system' ? systemTheme : readerTheme;
  }

  shouldUseLightStatusBarContent(
    readerModeVisible: boolean,
    readerTheme: ReaderModeTheme,
    readerSystemTheme: BrowserResolvedThemeMode,
    resolvedAppTheme: BrowserResolvedThemeMode
  ): boolean {
    if (readerModeVisible) {
      const effectiveTheme = this.resolveEffectiveReaderTheme(readerTheme, readerSystemTheme);
      return effectiveTheme === 'dark' || effectiveTheme === 'charcoal';
    }
    return resolvedAppTheme === 'dark';
  }

  buildInfoRows(state: OfflinePageViewerState): OfflinePageViewerInfoRow[] {
    return [
      { label: '标题', value: this.resolveTitle(state) },
      { label: '站点', value: this.resolveSite(state) },
      { label: '原网页', value: state.originalUrl },
      { label: '保存时间', value: this.formatDateTime(state.savedAt) },
      { label: '更新时间', value: this.formatDateTime(state.updatedAt) },
      { label: '大小', value: this.formatBytes(state.totalBytes) },
      { label: '资源', value: this.formatResourceSummary(state.resourceCount, state.failedResourceCount) },
      { label: '保存状态', value: this.resolveSaveStatusText(state.saveStatus) },
      { label: '打开状态', value: this.resolveOpenStatusText(state.openStatus) }
    ];
  }

  private resolveTitle(state: OfflinePageViewerState): string {
    const title = state.title.trim();
    return title.length > 0 ? title : '未命名离线页面';
  }

  private resolveSite(state: OfflinePageViewerState): string {
    const siteName = state.siteName.trim();
    if (siteName.length > 0) {
      return siteName;
    }
    const host = state.host.trim();
    return host.length > 0 ? host : '未知来源';
  }

  private formatResourceSummary(resourceCount: number, failedResourceCount: number): string {
    const savedCount = Math.max(0, Math.floor(resourceCount));
    const failedCount = Math.max(0, Math.floor(failedResourceCount));
    if (failedCount > 0) {
      return `${savedCount} 个资源 · ${failedCount} 个失败`;
    }
    return `${savedCount} 个资源`;
  }

  private resolveSaveStatusText(status: OfflinePageSaveStatus): string {
    if (status === 'saved') {
      return '已完整保存';
    }
    if (status === 'partial_saved') {
      return '已部分保存';
    }
    if (status === 'saving') {
      return '保存中';
    }
    return '保存失败';
  }

  private resolveOpenStatusText(status: OfflinePageOpenStatus): string {
    if (status === 'available') {
      return '可正常打开';
    }
    if (status === 'missing_snapshot') {
      return '正文文件缺失';
    }
    if (status === 'missing_assets') {
      return '部分资源缺失';
    }
    return '离线副本异常';
  }

  private formatDateTime(value: number): string {
    if (value <= 0) {
      return '暂无';
    }
    const date = new Date(value);
    return `${date.getFullYear()}-${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ` +
      `${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`;
  }

  private formatBytes(value: number): string {
    const bytes = Math.max(0, Math.floor(value));
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb = bytes / 1024;
    if (kb < 1024) {
      return `${this.formatOneDecimal(kb)} KB`;
    }
    const mb = kb / 1024;
    return `${this.formatOneDecimal(mb)} MB`;
  }

  private formatOneDecimal(value: number): string {
    return (Math.round(value * 10) / 10).toString();
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}

import { image } from '@kit.ImageKit';
import { HistoryDisplayVisit } from '../../../features/history/HistoryViewModel';
import {
  HistoryTimelineDataSource,
  HistoryTimelineGroup
} from '../../../features/history/HistoryTimelineDataSource';
import {
  SiteIconListRenderState,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { WebsiteIconView } from '../common/WebsiteIconView';
import { AiraIcon } from '../common/AiraIcon';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem
} from '../browser/BrowserDesktopContextMenu';
import { HistoryWorkspaceSelectionMode } from '../../../core/history/HistoryWorkspaceSessionCoordinator';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  RECORD_LIST_CARD_RADIUS,
  RECORD_LIST_GROUP_SPACE,
  RECORD_LIST_GROUP_TITLE_BOTTOM_PADDING,
  RECORD_LIST_GROUP_TITLE_LEFT_INSET,
  RECORD_LIST_GROUP_TITLE_RIGHT_INSET,
  RECORD_LIST_GROUP_TITLE_SIZE,
  RECORD_LIST_GROUP_TITLE_TOP_PADDING,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_RADIUS,
  RECORD_LIST_ROW_SUBTITLE_SIZE,
  RECORD_LIST_ROW_TITLE_SIZE
} from '../common/RecordListTokens';

const HISTORY_DESKTOP_ROW_HEIGHT: number = RECORD_LIST_ROW_HEIGHT;
const HISTORY_DESKTOP_LIST_PADDING: number = 16;
const HISTORY_DESKTOP_GROUP_PADDING: number = 4;

@Component
export struct HistoryLargeScreenTimeline {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY)
  private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;

  dataSource: HistoryTimelineDataSource = new HistoryTimelineDataSource();
  listScroller: ListScroller = new ListScroller();
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedVisitIds: string[] = [];
  @Prop shiftPressed: boolean = false;
  @Prop controlPressed: boolean = false;
  @State private hoveredVisitId: string = '';
  onOpenVisit: (visit: HistoryDisplayVisit, openInNewTab: boolean) => void =
    (_visit: HistoryDisplayVisit, _openInNewTab: boolean): void => {};
  onSelectVisit: (visitId: string, mode: HistoryWorkspaceSelectionMode) => void =
    (_visitId: string, _mode: HistoryWorkspaceSelectionMode): void => {};
  onDeleteVisit: (visit: HistoryDisplayVisit) => void = (_visit: HistoryDisplayVisit): void => {};
  onDeleteSelection: () => void = (): void => {};
  onCopyLink: (visit: HistoryDisplayVisit) => void = (_visit: HistoryDisplayVisit): void => {};
  onReachEnd: () => void = (): void => {};
  onIconLoadError: (
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number
  ) => void = (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number): void => {};

  build() {
    List({ scroller: this.listScroller, space: 0 }) {
      LazyForEach(this.dataSource, (group: HistoryTimelineGroup, groupIndex: number) => {
        ListItemGroup({ header: this.buildDateHeader(group) }) {
          LazyForEach(group.itemDataSource, (visit: HistoryDisplayVisit, itemIndex: number) => {
            ListItem() {
              this.buildVisitRow(visit, itemIndex === group.itemDataSource.totalCount() - 1)
            }
            .width('100%')
          }, (visit: HistoryDisplayVisit): string => visit.id)
        }
        .width('100%')
        .margin({ top: groupIndex > 0 ? RECORD_LIST_GROUP_SPACE : 0 })
        .padding({ bottom: HISTORY_DESKTOP_GROUP_PADDING })
        .backgroundColor(this.storedSurfaceBackgroundColor)
        .borderRadius(RECORD_LIST_CARD_RADIUS)
        .clip(true)
      }, (group: HistoryTimelineGroup): string => group.key)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: HISTORY_DESKTOP_LIST_PADDING,
      right: HISTORY_DESKTOP_LIST_PADDING,
      top: HISTORY_DESKTOP_GROUP_PADDING,
      bottom: HISTORY_DESKTOP_GROUP_PADDING
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
    .scrollBar(BarState.Auto)
    .cachedCount(4)
    .onReachEnd((): void => {
      this.onReachEnd();
    })
  }

  @Builder
  private buildDateHeader(group: HistoryTimelineGroup) {
    Text(group.label)
      .width('100%')
      .fontSize(RECORD_LIST_GROUP_TITLE_SIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedSecondaryTextColor)
      .padding({
        left: RECORD_LIST_GROUP_TITLE_LEFT_INSET + HISTORY_DESKTOP_GROUP_PADDING,
        right: RECORD_LIST_GROUP_TITLE_RIGHT_INSET + HISTORY_DESKTOP_GROUP_PADDING,
        top: RECORD_LIST_GROUP_TITLE_TOP_PADDING,
        bottom: RECORD_LIST_GROUP_TITLE_BOTTOM_PADDING
      })
  }

  @Builder
  private buildVisitRow(visit: HistoryDisplayVisit, isLast: boolean) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        if (this.selectedVisitIds.length > 0) {
          this.buildSelectionControl(visit)
        }
        this.buildVisitIcon(visit)

        Column({ space: 3 }) {
          Text(visit.title)
            .width('100%')
            .fontSize(RECORD_LIST_ROW_TITLE_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(visit.url)
            .width('100%')
            .fontSize(RECORD_LIST_ROW_SUBTITLE_SIZE)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (visit.duplicateCount > 1) {
          Text(`${visit.duplicateCount} 次`)
            .fontSize(11)
            .fontColor(this.storedSecondaryTextColor)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.storedControlBackgroundColor)
            .borderRadius(8)
        }

        if (this.hoveredVisitId === visit.id && !this.isSelected(visit.id)) {
          Button() {
            AiraIcon({
              airaIconId: 'browser.tabs.delete',
              iconSize: 15,
              iconColor: this.storedSecondaryTextColor
            })
          }
          .width(30)
          .height(30)
          .type(ButtonType.Circle)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(this.storedControlBackgroundColor)
          .accessibilityText('删除历史记录')
          .onClick((): void => {
            this.onDeleteVisit(visit);
          })
        }
      }
      .width('100%')
      .height(HISTORY_DESKTOP_ROW_HEIGHT)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveRowBackground(visit.id))
      .borderRadius(RECORD_LIST_ROW_RADIUS)
      .clip(true)
      .onHover((hovered: boolean): void => {
        this.hoveredVisitId = hovered ? visit.id : '';
      })
      .onClick((): void => {
        if (this.shiftPressed) {
          this.onSelectVisit(visit.id, 'range');
          return;
        }
        this.onOpenVisit(visit, this.controlPressed);
      })
      .focusable(true)
      .onMouse((event: MouseEvent): void => {
        if (event.button === MouseButton.Middle && event.action === MouseAction.Press) {
          event.stopPropagation();
          this.onOpenVisit(visit, true);
        }
      })
      .bindContextMenu(this.buildVisitContextMenu(visit), ResponseType.RightClick)

      if (!isLast) {
        Divider()
          .margin({ left: 56, right: 12 })
          .color(this.storedDividerColor)
      }
    }
    .width('100%')
  }

  @Builder
  private buildSelectionControl(visit: HistoryDisplayVisit) {
    Checkbox()
      .width(18)
      .height(18)
      .shape(CheckBoxShape.CIRCLE)
      .select(this.isSelected(visit.id))
      .selectedColor(this.storedAccentColor)
      .onChange((selected: boolean): void => {
        if (selected !== this.isSelected(visit.id)) {
          this.onSelectVisit(visit.id, 'toggle');
        }
      })
  }

  @Builder
  private buildVisitIcon(visit: HistoryDisplayVisit) {
    WebsiteIconView({
      iconUri: this.getIconState(visit.id)?.path ?? '',
      iconPixelMap: this.getIconPixelMap(visit.id),
      fallbackLabel: resolveSiteIconFallbackLabel(visit.title, visit.host.length > 0 ? visit.host : visit.url),
      variant: 'list',
      iconSize: 28,
      contentRatio: 1,
      cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      preferPixelMap: this.getIconPixelMap(visit.id) !== undefined,
      sourceRevision: this.getIconState(visit.id)?.sourceRevision ?? 0,
      containerBackgroundColor: this.storedControlBackgroundColor,
      frameBorderColor: this.storedDividerColor,
      textColor: this.storedPrimaryTextColor,
      onIconLoadError: (iconUri: string, sourceRevision: number): void => {
        this.onIconLoadError({
          id: visit.id,
          url: visit.url,
          domain: visit.host
        }, iconUri, sourceRevision);
      }
    })
  }

  @Builder
  private buildVisitContextMenu(visit: HistoryDisplayVisit) {
    BrowserDesktopContextMenu() {
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: '打开',
          onAction: (): void => {
            this.onOpenVisit(visit, false);
          }
        })
        BrowserDesktopContextMenuItem({
          label: '在新标签页中打开',
          onAction: (): void => {
            this.onOpenVisit(visit, true);
          }
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: '复制链接',
          onAction: (): void => {
            this.onCopyLink(visit);
          }
        })
      }

      MenuItemGroup() {
        if (this.selectedVisitIds.length === 0) {
          BrowserDesktopContextMenuItem({
            label: '多选',
            onAction: (): void => {
              this.onSelectVisit(visit.id, 'replace');
            }
          })
        } else if (this.isSelected(visit.id)) {
          BrowserDesktopContextMenuItem({
            label: '取消选择',
            onAction: (): void => {
              this.onSelectVisit(visit.id, 'toggle');
            }
          })
        } else {
          BrowserDesktopContextMenuItem({
            label: '添加到多选',
            onAction: (): void => {
              this.onSelectVisit(visit.id, 'toggle');
            }
          })
        }
      }

      MenuItemGroup() {
        if (this.selectedVisitIds.length > 1 && this.isSelected(visit.id)) {
          BrowserDesktopContextMenuItem({
            label: `删除所选 ${this.selectedVisitIds.length} 项`,
            onAction: (): void => {
              this.onDeleteSelection();
            }
          })
        } else {
          BrowserDesktopContextMenuItem({
            label: '删除',
            onAction: (): void => {
              this.onDeleteVisit(visit);
            }
          })
        }
      }
    }
  }

  private isSelected(visitId: string): boolean {
    return this.selectedVisitIds.indexOf(visitId) >= 0;
  }

  private resolveRowBackground(visitId: string): ResourceColor {
    if (this.isSelected(visitId)) {
      return this.storedPressedBackgroundColor;
    }
    if (this.hoveredVisitId === visitId) {
      return this.storedControlBackgroundColor;
    }
    return this.storedSurfaceBackgroundColor;
  }

  private getIconState(visitId: string): SiteIconListRenderState | undefined {
    return this.icons.find((item: SiteIconListRenderState): boolean => item.id === visitId);
  }

  private getIconPixelMap(visitId: string): image.PixelMap | undefined {
    return this.getIconState(visitId)?.pixelMap;
  }
}

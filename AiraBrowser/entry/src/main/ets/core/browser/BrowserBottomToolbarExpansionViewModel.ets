import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

export type BrowserBottomToolbarExpansionStage = 'preview' | 'full';
export type BrowserBottomToolbarGestureReleaseDisposition = 'default' | 'stay-middle';

export interface BrowserBottomToolbarGestureReleaseInput {
  stage: BrowserBottomToolbarExpansionStage;
  currentDetent: HomeSearchPanelDetent;
  targetDetent: HomeSearchPanelDetent;
  offsetY: number;
  velocityY: number;
  fullExpansionAvailable: boolean;
}

export interface BrowserBottomToolbarGestureReleaseDecision {
  stage: BrowserBottomToolbarExpansionStage;
  disposition: BrowserBottomToolbarGestureReleaseDisposition;
}

export interface BrowserBottomToolbarSurfaceTransitionInput {
  actionSurfaceMounted: boolean;
  currentPanelHeight: number;
  lowPanelHeight: number;
  previewPanelHeight: number;
}

export interface BrowserBottomToolbarSurfaceTransitionState {
  searchOpacity: number;
  surfaceCoverProgress: number;
}

export interface BrowserBottomToolbarQuickActionLayoutInput {
  actionCount: number;
  availableWidth: number;
  availableHeight: number;
  preferredColumns: number;
  maxColumns: number;
  buttonSize: number;
  labelBlockHeight: number;
  columnGap: number;
  rowGap: number;
  groupHorizontalPadding: number;
  groupVerticalPadding: number;
  surfaceVerticalPadding: number;
  expansionHintSlotHeight: number;
  expansionHintBottomGap: number;
}

export interface BrowserBottomToolbarQuickActionLayoutState {
  actionCount: number;
  columnCount: number;
  rowCount: number;
  buttonSize: number;
  cardHeight: number;
  columnGap: number;
  rowGap: number;
  groupVerticalPadding: number;
  surfaceVerticalPadding: number;
  expansionHintSlotHeight: number;
  expansionHintBottomGap: number;
  gridHeight: number;
  contentHeight: number;
  previewSurfaceHeight: number;
  fullSurfaceHeight: number;
  fitsAvailableHeight: boolean;
}

interface BrowserBottomToolbarQuickActionLayoutCandidate extends BrowserBottomToolbarQuickActionLayoutState {
  spacingProgress: number;
}

interface BrowserBottomToolbarQuickActionVerticalSpacing {
  rowGap: number;
  groupVerticalPadding: number;
  surfaceVerticalPadding: number;
  progress: number;
}

const BROWSER_BOTTOM_TOOLBAR_PREVIEW_ROWS: number = 3;
const BROWSER_BOTTOM_TOOLBAR_STAGE_RELEASE_DISTANCE: number = 36;
const BROWSER_BOTTOM_TOOLBAR_STAGE_RELEASE_VELOCITY: number = 720;
const BROWSER_BOTTOM_TOOLBAR_SEARCH_EXIT_START_PROGRESS: number = 0.08;
const BROWSER_BOTTOM_TOOLBAR_SEARCH_EXIT_END_PROGRESS: number = 0.72;
const BROWSER_BOTTOM_TOOLBAR_SURFACE_COVER_START_PROGRESS: number = 0.58;
const BROWSER_BOTTOM_TOOLBAR_SURFACE_COVER_END_PROGRESS: number = 0.96;
const BROWSER_BOTTOM_TOOLBAR_FULL_MIN_BUTTON_SIZE: number = 48;
const BROWSER_BOTTOM_TOOLBAR_FULL_MIN_COLUMN_GAP: number = 6;
const BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP: number = 6;
const BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING: number = 4;
const BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING: number = 8;
const BROWSER_BOTTOM_TOOLBAR_PREVIEW_NEXT_ROW_CLEARANCE: number = 2;

export class BrowserBottomToolbarExpansionViewModel {
  resolvePreviewActionLimit(columns: number): number {
    return Math.max(1, Math.floor(columns)) * BROWSER_BOTTOM_TOOLBAR_PREVIEW_ROWS;
  }

  resolveQuickActionLayout(
    input: BrowserBottomToolbarQuickActionLayoutInput
  ): BrowserBottomToolbarQuickActionLayoutState {
    const actionCount = Math.max(0, Math.floor(this.normalizeNumber(input.actionCount)));
    const preferredColumns = this.resolvePreferredColumnCount(input);
    return this.buildFullQuickActionLayout(input, actionCount, preferredColumns);
  }

  shouldPreserveExpandedBackdropDuringGesture(stage: BrowserBottomToolbarExpansionStage): boolean {
    return stage === 'full';
  }

  shouldShowExpansionHint(fullExpansionAvailable: boolean): boolean {
    return fullExpansionAvailable;
  }

  resolveExpansionHintRotationAngle(
    stage: BrowserBottomToolbarExpansionStage,
    fullExpansionAvailable: boolean
  ): number {
    return stage === 'full' && fullExpansionAvailable ? 180 : 0;
  }

  resolveSurfaceTransition(
    input: BrowserBottomToolbarSurfaceTransitionInput
  ): BrowserBottomToolbarSurfaceTransitionState {
    if (!input.actionSurfaceMounted) {
      return {
        searchOpacity: 1,
        surfaceCoverProgress: 0
      };
    }
    const expansionProgress = this.resolveExpansionProgress(input);
    const searchFadeProgress = this.resolveRangedSmoothProgress(
      expansionProgress,
      BROWSER_BOTTOM_TOOLBAR_SEARCH_EXIT_START_PROGRESS,
      BROWSER_BOTTOM_TOOLBAR_SEARCH_EXIT_END_PROGRESS
    );
    return {
      searchOpacity: 1 - searchFadeProgress,
      surfaceCoverProgress: this.resolveRangedSmoothProgress(
        expansionProgress,
        BROWSER_BOTTOM_TOOLBAR_SURFACE_COVER_START_PROGRESS,
        BROWSER_BOTTOM_TOOLBAR_SURFACE_COVER_END_PROGRESS
      )
    };
  }

  resolveGestureRelease(
    input: BrowserBottomToolbarGestureReleaseInput
  ): BrowserBottomToolbarGestureReleaseDecision {
    if (input.currentDetent !== 'middle') {
      return this.keepCurrentStage(input.stage);
    }
    if (input.stage === 'preview' && input.fullExpansionAvailable &&
      input.targetDetent === 'middle' && this.isCommittedUpwardRelease(input.offsetY, input.velocityY)) {
      return {
        stage: 'full',
        disposition: 'stay-middle'
      };
    }
    if (input.stage === 'full' && input.targetDetent === 'low' &&
      this.isCommittedDownwardRelease(input.offsetY, input.velocityY)) {
      return {
        stage: 'preview',
        disposition: 'stay-middle'
      };
    }
    return this.keepCurrentStage(input.stage);
  }

  private keepCurrentStage(
    stage: BrowserBottomToolbarExpansionStage
  ): BrowserBottomToolbarGestureReleaseDecision {
    return {
      stage,
      disposition: 'default'
    };
  }

  private buildFullQuickActionLayout(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    actionCount: number,
    preferredColumns: number
  ): BrowserBottomToolbarQuickActionLayoutState {
    const maximumColumns = this.resolveMaximumColumnCount(input, actionCount, preferredColumns);
    let bestCandidate: BrowserBottomToolbarQuickActionLayoutCandidate | undefined = undefined;
    for (let columnCount = preferredColumns; columnCount <= maximumColumns; columnCount += 1) {
      const candidate = this.buildFullQuickActionLayoutCandidate(input, actionCount, columnCount);
      if (candidate === undefined || !candidate.fitsAvailableHeight) {
        continue;
      }
      if (this.shouldPreferQuickActionLayoutCandidate(candidate, bestCandidate, preferredColumns)) {
        bestCandidate = candidate;
      }
    }
    if (bestCandidate !== undefined) {
      return bestCandidate;
    }
    return this.buildEmergencyFullQuickActionLayout(input, actionCount, maximumColumns);
  }

  private buildFullQuickActionLayoutCandidate(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    actionCount: number,
    columnCount: number
  ): BrowserBottomToolbarQuickActionLayoutCandidate | undefined {
    const rowCount = this.resolveRowCount(actionCount, columnCount);
    const availableHeight = Math.max(0, this.normalizeNumber(input.availableHeight));
    const labelBlockHeight = Math.max(0, this.normalizeNumber(input.labelBlockHeight));
    const expansionHintSlotHeight = this.resolveExpansionHintSlotHeight(input);
    const expansionHintBottomGap = this.resolveExpansionHintBottomGap(input, expansionHintSlotHeight);
    const fixedTopHeight = expansionHintSlotHeight + expansionHintBottomGap;
    const columnGap = this.resolveFullColumnGap(input, columnCount, BROWSER_BOTTOM_TOOLBAR_FULL_MIN_BUTTON_SIZE);
    if (columnGap < 0) {
      return undefined;
    }
    const buttonWidthLimit = this.resolveButtonWidthLimit(input, columnCount, columnGap);
    const baseButtonSize = Math.max(1, this.normalizeNumber(input.buttonSize));
    const minimumSpacingHeight = this.resolveVerticalSpacingHeight(
      rowCount,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
      fixedTopHeight
    );
    const buttonHeightLimit = rowCount > 0 ?
      (availableHeight - minimumSpacingHeight) / rowCount - labelBlockHeight : baseButtonSize;
    const buttonSize = Math.min(baseButtonSize, buttonWidthLimit, buttonHeightLimit);
    if (buttonSize < BROWSER_BOTTOM_TOOLBAR_FULL_MIN_BUTTON_SIZE) {
      return undefined;
    }
    const cardHeight = buttonSize + labelBlockHeight;
    const spacing = this.resolveFullVerticalSpacing(input, rowCount, cardHeight, availableHeight);
    const gridHeight = this.resolveGridHeight(
      rowCount,
      cardHeight,
      spacing.rowGap,
      spacing.groupVerticalPadding
    );
    const contentHeight = gridHeight + spacing.surfaceVerticalPadding * 2 + fixedTopHeight;
    const previewSurfaceHeight = this.resolvePreviewSurfaceHeight(
      rowCount,
      cardHeight,
      spacing.rowGap,
      spacing.groupVerticalPadding,
      spacing.surfaceVerticalPadding,
      fixedTopHeight,
      contentHeight
    );
    return {
      actionCount,
      columnCount,
      rowCount,
      buttonSize,
      cardHeight,
      columnGap,
      rowGap: spacing.rowGap,
      groupVerticalPadding: spacing.groupVerticalPadding,
      surfaceVerticalPadding: spacing.surfaceVerticalPadding,
      expansionHintSlotHeight,
      expansionHintBottomGap,
      gridHeight,
      contentHeight,
      previewSurfaceHeight,
      fullSurfaceHeight: this.resolveFullSurfaceHeight(availableHeight, contentHeight, previewSurfaceHeight),
      fitsAvailableHeight: availableHeight <= 0 || contentHeight <= availableHeight + 0.01,
      spacingProgress: spacing.progress
    };
  }

  private buildEmergencyFullQuickActionLayout(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    actionCount: number,
    columnCount: number
  ): BrowserBottomToolbarQuickActionLayoutState {
    const rowCount = this.resolveRowCount(actionCount, columnCount);
    const availableHeight = Math.max(1, this.normalizeNumber(input.availableHeight));
    const labelBlockHeight = Math.max(0, this.normalizeNumber(input.labelBlockHeight));
    const expansionHintSlotHeight = this.resolveExpansionHintSlotHeight(input);
    const expansionHintBottomGap = this.resolveExpansionHintBottomGap(input, expansionHintSlotHeight);
    const fixedTopHeight = expansionHintSlotHeight + expansionHintBottomGap;
    const columnGap = Math.max(0, this.resolveFullColumnGap(input, columnCount, 1));
    const buttonWidthLimit = this.resolveButtonWidthLimit(input, columnCount, columnGap);
    const spacingHeight = this.resolveVerticalSpacingHeight(
      rowCount,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
      fixedTopHeight
    );
    const buttonHeightLimit = rowCount > 0 ?
      (availableHeight - spacingHeight) / rowCount - labelBlockHeight : input.buttonSize;
    const buttonSize = Math.max(1, Math.min(
      Math.max(1, this.normalizeNumber(input.buttonSize)),
      buttonWidthLimit,
      buttonHeightLimit
    ));
    const cardHeight = buttonSize + labelBlockHeight;
    const gridHeight = this.resolveGridHeight(
      rowCount,
      cardHeight,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING
    );
    const contentHeight = gridHeight + BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING * 2 + fixedTopHeight;
    const previewSurfaceHeight = this.resolvePreviewSurfaceHeight(
      rowCount,
      cardHeight,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
      fixedTopHeight,
      contentHeight
    );
    return {
      actionCount,
      columnCount,
      rowCount,
      buttonSize,
      cardHeight,
      columnGap,
      rowGap: BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP,
      groupVerticalPadding: BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
      surfaceVerticalPadding: BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
      expansionHintSlotHeight,
      expansionHintBottomGap,
      gridHeight,
      contentHeight,
      previewSurfaceHeight,
      fullSurfaceHeight: this.resolveFullSurfaceHeight(availableHeight, contentHeight, previewSurfaceHeight),
      fitsAvailableHeight: contentHeight <= availableHeight + 0.01
    };
  }

  private resolveFullVerticalSpacing(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    rowCount: number,
    cardHeight: number,
    availableHeight: number
  ): BrowserBottomToolbarQuickActionVerticalSpacing {
    const baseRowGap = Math.max(BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP, this.normalizeNumber(input.rowGap));
    const baseGroupPadding = Math.max(
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
      this.normalizeNumber(input.groupVerticalPadding)
    );
    const baseSurfacePadding = Math.max(
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
      this.normalizeNumber(input.surfaceVerticalPadding)
    );
    const expansionHintSlotHeight = this.resolveExpansionHintSlotHeight(input);
    const fixedTopHeight = expansionHintSlotHeight +
      this.resolveExpansionHintBottomGap(input, expansionHintSlotHeight);
    const minimumSpacingHeight = this.resolveVerticalSpacingHeight(
      rowCount,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
      BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
      fixedTopHeight
    );
    const baseSpacingHeight = this.resolveVerticalSpacingHeight(
      rowCount,
      baseRowGap,
      baseGroupPadding,
      baseSurfacePadding,
      fixedTopHeight
    );
    const availableSpacingHeight = Math.max(0, availableHeight - rowCount * cardHeight);
    const progress = baseSpacingHeight <= minimumSpacingHeight ? 1 : this.clampProgress(
      (availableSpacingHeight - minimumSpacingHeight) / (baseSpacingHeight - minimumSpacingHeight)
    );
    return {
      rowGap: this.interpolateNumber(BROWSER_BOTTOM_TOOLBAR_FULL_MIN_ROW_GAP, baseRowGap, progress),
      groupVerticalPadding: this.interpolateNumber(
        BROWSER_BOTTOM_TOOLBAR_FULL_MIN_GROUP_VERTICAL_PADDING,
        baseGroupPadding,
        progress
      ),
      surfaceVerticalPadding: this.interpolateNumber(
        BROWSER_BOTTOM_TOOLBAR_FULL_MIN_SURFACE_VERTICAL_PADDING,
        baseSurfacePadding,
        progress
      ),
      progress
    };
  }

  private shouldPreferQuickActionLayoutCandidate(
    candidate: BrowserBottomToolbarQuickActionLayoutCandidate,
    current: BrowserBottomToolbarQuickActionLayoutCandidate | undefined,
    preferredColumns: number
  ): boolean {
    if (current === undefined) {
      return true;
    }
    if (candidate.buttonSize > current.buttonSize + 0.01) {
      return true;
    }
    if (candidate.buttonSize < current.buttonSize - 0.01) {
      return false;
    }
    const candidateColumnDelta = Math.abs(candidate.columnCount - preferredColumns);
    const currentColumnDelta = Math.abs(current.columnCount - preferredColumns);
    if (candidateColumnDelta !== currentColumnDelta) {
      return candidateColumnDelta < currentColumnDelta;
    }
    return candidate.spacingProgress > current.spacingProgress;
  }

  private resolvePreferredColumnCount(input: BrowserBottomToolbarQuickActionLayoutInput): number {
    const maximumColumns = Math.max(1, Math.floor(this.normalizeNumber(input.maxColumns)));
    return Math.max(1, Math.min(maximumColumns, Math.floor(this.normalizeNumber(input.preferredColumns))));
  }

  private resolveMaximumColumnCount(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    actionCount: number,
    preferredColumns: number
  ): number {
    const requestedMaximum = Math.max(preferredColumns, Math.floor(this.normalizeNumber(input.maxColumns)));
    const actionMaximum = actionCount > 0 ? Math.max(preferredColumns, actionCount) : preferredColumns;
    return Math.max(preferredColumns, Math.min(requestedMaximum, actionMaximum));
  }

  private resolveFullColumnGap(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    columnCount: number,
    minimumButtonSize: number
  ): number {
    if (columnCount <= 1) {
      return 0;
    }
    const availableWidth = Math.max(0, this.normalizeNumber(input.availableWidth));
    const horizontalPadding = Math.max(0, this.normalizeNumber(input.groupHorizontalPadding));
    const availableGapWidth = availableWidth - horizontalPadding * 2 - columnCount * minimumButtonSize;
    const minimumGapWidth = (columnCount - 1) * BROWSER_BOTTOM_TOOLBAR_FULL_MIN_COLUMN_GAP;
    if (availableGapWidth < minimumGapWidth) {
      return -1;
    }
    return Math.min(
      Math.max(BROWSER_BOTTOM_TOOLBAR_FULL_MIN_COLUMN_GAP, this.normalizeNumber(input.columnGap)),
      availableGapWidth / (columnCount - 1)
    );
  }

  private resolveButtonWidthLimit(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    columnCount: number,
    columnGap: number
  ): number {
    const availableWidth = Math.max(0, this.normalizeNumber(input.availableWidth));
    if (availableWidth <= 0) {
      return Math.max(1, this.normalizeNumber(input.buttonSize));
    }
    const horizontalPadding = Math.max(0, this.normalizeNumber(input.groupHorizontalPadding));
    const totalGapWidth = Math.max(0, columnCount - 1) * Math.max(0, columnGap);
    return Math.max(1, (availableWidth - horizontalPadding * 2 - totalGapWidth) / Math.max(1, columnCount));
  }

  private resolveGridHeight(
    rowCount: number,
    cardHeight: number,
    rowGap: number,
    groupVerticalPadding: number
  ): number {
    if (rowCount <= 0) {
      return 0;
    }
    return rowCount * cardHeight + Math.max(0, rowCount - 1) * rowGap + groupVerticalPadding * 2;
  }

  private resolvePreviewSurfaceHeight(
    rowCount: number,
    cardHeight: number,
    rowGap: number,
    groupVerticalPadding: number,
    surfaceVerticalPadding: number,
    fixedTopHeight: number,
    contentHeight: number
  ): number {
    if (rowCount <= BROWSER_BOTTOM_TOOLBAR_PREVIEW_ROWS) {
      return contentHeight;
    }
    const visibleRowsHeight = BROWSER_BOTTOM_TOOLBAR_PREVIEW_ROWS * cardHeight +
      (BROWSER_BOTTOM_TOOLBAR_PREVIEW_ROWS - 1) * rowGap;
    const bottomRevealPadding = Math.max(
      0,
      Math.min(
        Math.max(0, rowGap),
        Math.max(0, groupVerticalPadding) + Math.max(0, surfaceVerticalPadding)
      ) - BROWSER_BOTTOM_TOOLBAR_PREVIEW_NEXT_ROW_CLEARANCE
    );
    return Math.min(
      contentHeight,
      fixedTopHeight + surfaceVerticalPadding + groupVerticalPadding + visibleRowsHeight + bottomRevealPadding
    );
  }

  private resolveFullSurfaceHeight(
    availableHeight: number,
    contentHeight: number,
    previewSurfaceHeight: number
  ): number {
    return Math.max(previewSurfaceHeight, contentHeight, Math.max(0, availableHeight));
  }

  private resolveExpansionHintSlotHeight(input: BrowserBottomToolbarQuickActionLayoutInput): number {
    return Math.max(0, this.normalizeNumber(input.expansionHintSlotHeight));
  }

  private resolveExpansionHintBottomGap(
    input: BrowserBottomToolbarQuickActionLayoutInput,
    slotHeight: number
  ): number {
    return slotHeight > 0 ? Math.max(0, this.normalizeNumber(input.expansionHintBottomGap)) : 0;
  }

  private resolveVerticalSpacingHeight(
    rowCount: number,
    rowGap: number,
    groupVerticalPadding: number,
    surfaceVerticalPadding: number,
    fixedTopHeight: number
  ): number {
    return Math.max(0, rowCount - 1) * rowGap + groupVerticalPadding * 2 + surfaceVerticalPadding * 2 +
      fixedTopHeight;
  }

  private resolveRowCount(actionCount: number, columnCount: number): number {
    if (actionCount <= 0) {
      return 0;
    }
    return Math.ceil(actionCount / Math.max(1, columnCount));
  }

  private interpolateNumber(start: number, end: number, progress: number): number {
    return start + (end - start) * this.clampProgress(progress);
  }

  private isCommittedUpwardRelease(offsetY: number, velocityY: number): boolean {
    return this.normalizeNumber(offsetY) <= -BROWSER_BOTTOM_TOOLBAR_STAGE_RELEASE_DISTANCE ||
      this.normalizeNumber(velocityY) <= -BROWSER_BOTTOM_TOOLBAR_STAGE_RELEASE_VELOCITY;
  }

  private isCommittedDownwardRelease(offsetY: number, velocityY: number): boolean {
    return this.normalizeNumber(offsetY) >= BROWSER_BOTTOM_TOOLBAR_STAGE_RELEASE_DISTANCE ||
      this.normalizeNumber(velocityY) >= BROWSER_BOTTOM_TOOLBAR_STAGE_RELEASE_VELOCITY;
  }

  private resolveExpansionProgress(input: BrowserBottomToolbarSurfaceTransitionInput): number {
    const lowHeight = Math.max(0, this.normalizeNumber(input.lowPanelHeight));
    const previewHeight = Math.max(lowHeight + 1, this.normalizeNumber(input.previewPanelHeight));
    const currentHeight = Math.max(lowHeight, this.normalizeNumber(input.currentPanelHeight));
    return this.clampProgress((currentHeight - lowHeight) / (previewHeight - lowHeight));
  }

  private resolveRangedSmoothProgress(progress: number, start: number, end: number): number {
    const safeRange = Math.max(0.01, end - start);
    const rangedProgress = this.clampProgress((progress - start) / safeRange);
    return rangedProgress * rangedProgress * (3 - 2 * rangedProgress);
  }

  private clampProgress(progress: number): number {
    return Math.max(0, Math.min(1, this.normalizeNumber(progress)));
  }

  private normalizeNumber(value: number): number {
    return Number.isFinite(value) ? value : 0;
  }
}

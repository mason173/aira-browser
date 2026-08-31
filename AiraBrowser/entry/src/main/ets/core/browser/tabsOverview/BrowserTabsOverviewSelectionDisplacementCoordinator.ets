export interface BrowserTabsOverviewSelectionDisplacementInput {
  tabId: string;
  itemIndex: number;
  selectedTabId: string;
  selectedIndex: number;
  columnCount: number;
  cardWidth: number;
  itemHeight: number;
  gridGap: number;
}

export interface BrowserTabsOverviewSelectionDisplacement {
  x: number;
  y: number;
}

export class BrowserTabsOverviewSelectionDisplacementCoordinator {
  resolveDisplacement(input: BrowserTabsOverviewSelectionDisplacementInput): BrowserTabsOverviewSelectionDisplacement {
    const selectedTabId = input.selectedTabId.trim();
    if (selectedTabId.length <= 0 || input.tabId === selectedTabId || input.selectedIndex < 0) {
      return this.buildZeroDisplacement();
    }
    const columnCount = Math.max(1, Math.floor(input.columnCount));
    const itemIndex = Math.max(0, Math.floor(input.itemIndex));
    const selectedIndex = Math.max(0, Math.floor(input.selectedIndex));
    const itemRow = Math.floor(itemIndex / columnCount);
    const selectedRow = Math.floor(selectedIndex / columnCount);
    if (itemRow < selectedRow) {
      return {
        x: 0,
        y: -this.resolveVerticalDistance(input)
      };
    }
    if (itemRow > selectedRow) {
      return {
        x: 0,
        y: this.resolveVerticalDistance(input)
      };
    }
    const itemColumn = itemIndex % columnCount;
    const selectedColumn = selectedIndex % columnCount;
    if (itemColumn < selectedColumn) {
      return {
        x: -this.resolveHorizontalDistance(input),
        y: 0
      };
    }
    if (itemColumn > selectedColumn) {
      return {
        x: this.resolveHorizontalDistance(input),
        y: 0
      };
    }
    return this.buildZeroDisplacement();
  }

  private resolveHorizontalDistance(input: BrowserTabsOverviewSelectionDisplacementInput): number {
    return Math.max(96, Math.round(Math.max(1, input.cardWidth) + Math.max(0, input.gridGap)));
  }

  private resolveVerticalDistance(input: BrowserTabsOverviewSelectionDisplacementInput): number {
    return Math.max(128, Math.round(Math.max(1, input.itemHeight) + Math.max(0, input.gridGap)));
  }

  private buildZeroDisplacement(): BrowserTabsOverviewSelectionDisplacement {
    return {
      x: 0,
      y: 0
    };
  }
}

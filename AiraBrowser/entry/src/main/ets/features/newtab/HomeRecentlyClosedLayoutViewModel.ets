export const HOME_RECENTLY_CLOSED_MINIMUM_CELL_WIDTH: number = 280;

export class HomeRecentlyClosedLayoutViewModel {
  resolveColumnCount(columns: number): number {
    return Math.max(1, Math.floor(columns));
  }

  resolveAdaptiveColumnCount(
    contentWidth: number,
    leftInset: number,
    rightInset: number,
    requestedColumns: number,
    columnGap: number
  ): number {
    const availableWidth = Math.max(1, contentWidth - Math.max(0, leftInset) - Math.max(0, rightInset));
    const gap = Math.max(0, columnGap);
    const supportedColumns = Math.max(1, Math.floor(
      (availableWidth + gap) / (HOME_RECENTLY_CLOSED_MINIMUM_CELL_WIDTH + gap)
    ));
    return Math.min(this.resolveColumnCount(requestedColumns), supportedColumns);
  }

  resolveRecordCellWidth(
    contentWidth: number,
    leftInset: number,
    rightInset: number,
    columns: number,
    columnGap: number
  ): number {
    const columnCount = this.resolveColumnCount(columns);
    const availableWidth = Math.max(1, contentWidth - Math.max(0, leftInset) - Math.max(0, rightInset));
    const fullRowGapWidth = Math.max(0, columnGap) * Math.max(0, columnCount - 1);
    return Math.max(1, (availableWidth - fullRowGapWidth) / columnCount);
  }

  resolveRecordRowWidth(
    recordCount: number,
    contentWidth: number,
    leftInset: number,
    rightInset: number,
    columns: number,
    columnGap: number
  ): number {
    const occupiedColumns = Math.max(1, Math.min(
      this.resolveColumnCount(columns),
      Math.max(0, Math.floor(recordCount))
    ));
    return this.resolveRecordCellWidth(contentWidth, leftInset, rightInset, columns, columnGap) * occupiedColumns +
      Math.max(0, columnGap) * Math.max(0, occupiedColumns - 1);
  }

  resolveRecordGridWidth(
    contentWidth: number,
    leftInset: number,
    rightInset: number,
    columns: number,
    columnGap: number
  ): number {
    return this.resolveRecordRowWidth(
      this.resolveColumnCount(columns),
      contentWidth,
      leftInset,
      rightInset,
      columns,
      columnGap
    );
  }

  resolveSectionWidth(
    recordCount: number,
    contentWidth: number,
    leftInset: number,
    rightInset: number,
    columns: number,
    columnGap: number
  ): number {
    return Math.min(
      Math.max(1, contentWidth),
      this.resolveRecordRowWidth(
        recordCount,
        contentWidth,
        leftInset,
        rightInset,
        columns,
        columnGap
      ) + Math.max(0, leftInset) + Math.max(0, rightInset)
    );
  }
}

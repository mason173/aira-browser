export class WebTextSelectionMenuController {
  private selectionText: string = '';
  private onSearch?: (selectionText: string) => void;

  bindSearch(onSearch: ((selectionText: string) => void) | undefined): void {
    this.onSearch = onSearch;
  }

  updateSelection(selectionText: string): void {
    this.selectionText = selectionText;
  }

  clearSelection(): void {
    this.selectionText = '';
  }

  handleMenuItemClick(menuItem: TextMenuItem): boolean {
    if (!menuItem.id.equals(TextMenuItemId.SEARCH) || this.onSearch === undefined) {
      return false;
    }
    // Consume SEARCH even when the selection has just been cleared. Falling
    // through would launch the system search outside the browser.
    const selectionText = this.selectionText;
    if (selectionText.trim().length > 0) {
      this.onSearch(selectionText);
    }
    return true;
  }

  unbind(): void {
    this.clearSelection();
    this.onSearch = undefined;
  }
}

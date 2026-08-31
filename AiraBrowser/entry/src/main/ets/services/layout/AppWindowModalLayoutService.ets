export interface AppWindowModalLayoutInput {
  viewportWidth: number;
  viewportHeight: number;
  preferredWidth: number;
  preferredHeight: number;
  softMinWidth: number;
  maxWidth: number;
  softMinHeight: number;
  maxHeight: number;
  edgeMargin?: number;
}

export interface AppWindowModalLayout {
  width: number;
  height: number;
}

const APP_WINDOW_MODAL_EDGE_MARGIN_VP: number = 16;

/** Keeps app-owned modal geometry inside the current resizable app window. */
export class AppWindowModalLayoutService {
  resolveModal(input: AppWindowModalLayoutInput): AppWindowModalLayout {
    const edgeMargin = Math.max(0, input.edgeMargin ?? APP_WINDOW_MODAL_EDGE_MARGIN_VP);
    const fallbackWidth = Math.max(1, input.maxWidth);
    const fallbackHeight = Math.max(1, input.maxHeight);
    const viewportWidth = this.resolveViewportExtent(input.viewportWidth, fallbackWidth + edgeMargin * 2);
    const viewportHeight = this.resolveViewportExtent(input.viewportHeight, fallbackHeight + edgeMargin * 2);
    return {
      width: this.resolveModalExtent(
        viewportWidth,
        input.preferredWidth,
        input.softMinWidth,
        input.maxWidth,
        edgeMargin
      ),
      height: this.resolveModalExtent(
        viewportHeight,
        input.preferredHeight,
        input.softMinHeight,
        input.maxHeight,
        edgeMargin
      )
    };
  }

  resolvePopupWidth(viewportWidth: number, preferredWidth: number, edgeMargin: number =
    APP_WINDOW_MODAL_EDGE_MARGIN_VP): number {
    return this.resolvePopupExtent(viewportWidth, preferredWidth, 0, edgeMargin * 2);
  }

  resolvePopupHeight(
    viewportHeight: number,
    preferredHeight: number,
    reservedTop: number = 0,
    edgeMargin: number = APP_WINDOW_MODAL_EDGE_MARGIN_VP
  ): number {
    return this.resolvePopupExtent(viewportHeight, preferredHeight, reservedTop, edgeMargin);
  }

  private resolveModalExtent(
    viewportExtent: number,
    preferredExtent: number,
    softMinimum: number,
    maximum: number,
    edgeMargin: number
  ): number {
    const availableExtent = Math.max(1, viewportExtent - edgeMargin * 2);
    const requestedExtent = Math.max(Math.max(0, softMinimum), preferredExtent);
    const configuredMaximum = Math.max(1, maximum);
    return Math.max(1, Math.min(availableExtent, configuredMaximum, requestedExtent));
  }

  private resolvePopupExtent(
    viewportExtent: number,
    preferredExtent: number,
    leadingReserved: number,
    trailingReserved: number
  ): number {
    const normalizedPreferredExtent = Math.max(1, preferredExtent);
    if (!Number.isFinite(viewportExtent) || viewportExtent <= 0) {
      return normalizedPreferredExtent;
    }
    const availableExtent = Math.max(
      1,
      viewportExtent - Math.max(0, leadingReserved) - Math.max(0, trailingReserved)
    );
    return Math.min(normalizedPreferredExtent, availableExtent);
  }

  private resolveViewportExtent(value: number, fallback: number): number {
    return Number.isFinite(value) && value > 0 ? value : Math.max(1, fallback);
  }
}

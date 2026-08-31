export type SettingsAboutOverviewLayoutMode = 'compact' | 'medium' | 'wide';

export interface SettingsAboutOverviewLayoutInput {
  viewportWidth: number;
  viewportHeight: number;
  horizontalPadding: number;
}

export interface SettingsAboutOverviewLayoutState {
  mode: SettingsAboutOverviewLayoutMode;
  topPadding: number;
  bottomPadding: number;
  actionGap: number;
  actionWidth: number;
  cardWidth: number;
  cardHeight: number;
  cardRadius: number;
  logoSize: number;
  heroHorizontalPadding: number;
  heroTopPadding: number;
  heroBottomPadding: number;
  titleTopMargin: number;
}

const ABOUT_OVERVIEW_COMPACT_MAX_WIDTH: number = 520;
const ABOUT_OVERVIEW_WIDE_MIN_WIDTH: number = 760;
const ABOUT_OVERVIEW_ACTION_HEIGHT: number = 44;
const ABOUT_OVERVIEW_ACTION_GAP: number = 16;
const ABOUT_OVERVIEW_ACTION_MAX_WIDTH: number = 360;
const ABOUT_OVERVIEW_BOTTOM_PADDING: number = 32;
const ABOUT_OVERVIEW_CARD_RADIUS: number = 28;

export class SettingsAboutOverviewLayoutViewModel {
  buildState(input: SettingsAboutOverviewLayoutInput): SettingsAboutOverviewLayoutState {
    const viewportWidth = Math.max(1, input.viewportWidth);
    const viewportHeight = Math.max(1, input.viewportHeight);
    const horizontalPadding = Math.max(0, input.horizontalPadding);
    const mode = this.resolveMode(viewportWidth);
    const ratio = this.resolveCardAspectRatio(mode);
    const topPadding = this.resolveTopPadding(mode);
    const availableWidth = Math.max(1, viewportWidth - horizontalPadding * 2);
    const widthLimit = Math.min(availableWidth, this.resolveCardMaxWidth(mode));
    const reservedHeight = topPadding + ABOUT_OVERVIEW_BOTTOM_PADDING +
      ABOUT_OVERVIEW_ACTION_HEIGHT + ABOUT_OVERVIEW_ACTION_GAP;
    const availableCardHeight = Math.max(
      this.resolveCardMinHeight(mode),
      viewportHeight - reservedHeight
    );
    const cardHeightLimit = Math.min(this.resolveCardMaxHeight(mode), availableCardHeight);
    const cardWidth = Math.max(1, Math.min(widthLimit, cardHeightLimit * ratio));
    const cardHeight = Math.max(1, cardWidth / ratio);

    return {
      mode,
      topPadding,
      bottomPadding: ABOUT_OVERVIEW_BOTTOM_PADDING,
      actionGap: ABOUT_OVERVIEW_ACTION_GAP,
      actionWidth: Math.min(cardWidth, ABOUT_OVERVIEW_ACTION_MAX_WIDTH),
      cardWidth,
      cardHeight,
      cardRadius: ABOUT_OVERVIEW_CARD_RADIUS,
      logoSize: this.resolveLogoSize(mode),
      heroHorizontalPadding: this.resolveHeroHorizontalPadding(mode),
      heroTopPadding: this.resolveHeroTopPadding(mode),
      heroBottomPadding: this.resolveHeroBottomPadding(mode),
      titleTopMargin: this.resolveTitleTopMargin(mode)
    };
  }

  buildRenderKey(state: SettingsAboutOverviewLayoutState): string {
    return [
      state.mode,
      Math.round(state.cardWidth),
      Math.round(state.cardHeight),
      Math.round(state.actionWidth)
    ].join(':');
  }

  private resolveMode(viewportWidth: number): SettingsAboutOverviewLayoutMode {
    if (viewportWidth >= ABOUT_OVERVIEW_WIDE_MIN_WIDTH) {
      return 'wide';
    }
    if (viewportWidth > ABOUT_OVERVIEW_COMPACT_MAX_WIDTH) {
      return 'medium';
    }
    return 'compact';
  }

  private resolveCardAspectRatio(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 1.5;
    }
    if (mode === 'medium') {
      return 1.15;
    }
    return 0.72;
  }

  private resolveCardMaxWidth(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 750;
    }
    if (mode === 'medium') {
      return 600;
    }
    return ABOUT_OVERVIEW_COMPACT_MAX_WIDTH;
  }

  private resolveCardMinHeight(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 360;
    }
    if (mode === 'medium') {
      return 380;
    }
    return 400;
  }

  private resolveCardMaxHeight(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 500;
    }
    if (mode === 'medium') {
      return 520;
    }
    return 620;
  }

  private resolveTopPadding(mode: SettingsAboutOverviewLayoutMode): number {
    return mode === 'compact' ? 24 : 32;
  }

  private resolveLogoSize(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 92;
    }
    if (mode === 'medium') {
      return 96;
    }
    return 104;
  }

  private resolveHeroHorizontalPadding(mode: SettingsAboutOverviewLayoutMode): number {
    return mode === 'wide' ? 32 : 28;
  }

  private resolveHeroTopPadding(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 30;
    }
    if (mode === 'medium') {
      return 32;
    }
    return 36;
  }

  private resolveHeroBottomPadding(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 32;
    }
    if (mode === 'medium') {
      return 34;
    }
    return 38;
  }

  private resolveTitleTopMargin(mode: SettingsAboutOverviewLayoutMode): number {
    if (mode === 'wide') {
      return 12;
    }
    if (mode === 'medium') {
      return 14;
    }
    return 18;
  }
}

